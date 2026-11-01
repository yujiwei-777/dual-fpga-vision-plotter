// Histogram equalisation on the display path (HDMI pixel clock domain, 1 px/clk).
//
// Per frame:
//   1. COLLECT   build a 256-bin luma histogram of the frame being displayed.
//   2. NORMALIZE at the next vsync walk the bins: running CDF, build
//                LUT[i] = (i + 255*cdf[i]/total)/2 into the BACK buffer while
//                clearing each bin as it is consumed.  The buffers are swapped
//                when the pass completes, so a pass that overruns the blanking
//                interval can never corrupt the frame on screen.
//   3. APPLY     luma Y -> LUT[Y]; R/G/B then each get +(Y'-Y).  The luma
//                weights sum to 1, so adding the same delta to all three
//                channels moves Y by exactly delta and leaves R-Y, G-Y, B-Y --
//                i.e. chroma -- untouched: a YCbCr round trip without the
//                multiplies (and without clipping chroma).
//
// The 50/50 blend with the identity in step 2 is what keeps this usable on real
// scenes: pure equalisation maps a flat/uniform area (a one-spike histogram)
// straight to white.  BLEND=0 gives textbook HE for comparison.
//
// Every input is delayed by 3 clocks so the module drops inline between
// video_out and hdmi_mixer without shifting the picture relative to the OSD or
// the VTC timing.
//
// Timing note: the histogram RAM is read and written on the same port in the
// same cycle (write address = read address = the bin of the pixel two clocks
// back).  A synchronous read returns the pre-write value, so when two
// consecutive pixels land in the same bin the second increment would be lost;
// the "+2 when the previous pixel hit the same bin and was actually written"
// term compensates for exactly that.  Without it a flat row of one colour
// would count only every other pixel and the histogram would be badly skewed.

module hist_eq_px #(
    parameter integer BLEND = 1        // 0 = pure HE, 1 = half HE half identity
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_en,           // KEY1 toggle

    input  wire        I_vsync,
    input  wire        I_hsync,
    input  wire        I_de,
    input  wire        I_user,
    input  wire        I_last,
    input  wire [23:0] I_data,

    output reg         O_vsync,
    output reg         O_hsync,
    output reg         O_de,
    output reg         O_user,
    output reg         O_last,
    output reg  [23:0] O_data
);

    // Y = (77R + 150G + 29B) >> 8, all shift/add, no DSP.
    function [7:0] F_luma;
        input [7:0] r, g, b;
        reg [16:0] s;
        begin
            s =   ({9'd0, r} << 6) + ({9'd0, r} << 3) + ({9'd0, r} << 2) + {9'd0, r}
                + ({9'd0, g} << 7) + ({9'd0, g} << 4) + ({9'd0, g} << 2) + ({9'd0, g} << 1)
                + ({9'd0, b} << 4) + ({9'd0, b} << 3) + ({9'd0, b} << 2) + {9'd0, b};
            F_luma = s[15:8];
        end
    endfunction

    // 255/921600 (the 1280x720 display) as a fixed-point multiply:
    // round(255 * 2^20 / 921600) = 290.  290 = 256+32+2, so cdf*290
    // is six shifts and five adds, no DSP.
    // (cdf <= 921600 -> p <= 2.68e8, which fits the 28-bit product.)
    function [8:0] F_he;
        input [19:0] cdf;
        reg [27:0] p;
        begin
            p =   (cdf << 8) + (cdf << 5) + (cdf << 1);
            F_he = p[27:20];
        end
    endfunction

    // ---------------------------------------------------------------- luma --
    reg [7:0]  S_y;
    reg [7:0]  S_y2;
    reg [23:0] S_dat1, S_dat2;
    reg        S_en1, S_en2;

    wire [7:0] S_y_now = F_luma(I_data[23:16], I_data[15:8], I_data[7:0]);
    wire       S_y_v   = I_de & I_en;   // pixel counted this frame

    // ----------------------------------------------------------- histogram --
    // A 1280x720 frame contains 921600 pixels.  A 16-bit bin wrapped on
    // large flat regions, which could make the first enabled HE frame jump
    // to an incorrect LUT.  Twenty bits cover the complete frame count.
    reg [19:0] S_hist [0:255];
    reg [19:0] S_h_raw;
    reg S_ram_live;
    wire [19:0] S_h_rd = S_ram_live ? S_h_raw : 20'd0;
    reg [7:0]  S_h_a1, S_h_a2, S_h_a3;
    reg        S_h_v1, S_h_v2, S_h_v3;

    // S_h_a2 is the bin of the pixel 3 clocks back, so its validity is also
    // delayed by 3 (S_h_v2).  S_h_v3 tells whether the *previous* cycle's write
    // actually happened, which is what the same-bin compensation needs.
    wire       S_same_bin = (S_h_a2 == S_h_a3);
    wire [19:0] S_h_inc   = (S_h_v3 && S_same_bin) ? 20'd2 : 20'd1;
    wire [20:0] S_h_sum   = {1'b0, S_h_rd} + {1'b0, S_h_inc};
    // Limit a single bin to 14400 samples to avoid flat-scene jumps.
    wire [19:0] S_h_next  = (S_h_sum > 21'd14400) ? 20'd14400 : S_h_sum[19:0];

    // ------------------------------------------------------------ normalize --
    reg        S_norm;                 // pass running (1 at reset: clears the RAM)
    reg        S_norm_1d;
    reg        S_first;                // first pass = clear only, LUT stays invalid
    reg [8:0]  S_nidx;                 // 0..256, 256 = pass done
    reg [8:0]  S_nidx_d;
    reg [19:0] S_cdf;

    wire [20:0] S_cdf_nxt = {1'b0, S_cdf} + {1'b0, S_h_rd};
    wire [8:0]  S_he_val  = F_he(S_cdf_nxt[19:0]);
    wire [10:0] S_he_mix_w = BLEND ? ((({3'd0,S_nidx_d[7:0]} << 1) + {3'd0,S_nidx_d[7:0]} + {2'd0,S_he_val}) >> 2) : {2'd0,S_he_val};
    wire [8:0]  S_he_mix  = (S_he_mix_w > 11'd255) ? 9'd255 : S_he_mix_w[8:0];
    wire [7:0]  S_lut_val = (S_he_mix > 9'd255) ? 8'd255 : S_he_mix[7:0];

    // ------------------------------------------------------------------ LUT --
    reg [7:0] S_lut [0:511];
    reg        S_lut_sel;              // 0: read lut0 / write lut1
    reg        S_lut0_v, S_lut1_v;     // bank has been filled at least once
    reg [7:0] S_lut_raw;
    wire [7:0] S_lut_rd = S_ram_live ? S_lut_raw : 8'd0;

    wire       S_lut_v_now  = S_lut_sel ? S_lut1_v : S_lut0_v;

    // ----------------------------------------------------- apply (luma delta)
    wire signed [9:0]  S_dy_raw = $signed({1'b0, S_lut_rd}) - $signed({1'b0, S_y2});
    wire signed [9:0]  S_dy = (S_dy_raw > 10'sd24) ? 10'sd24 : (S_dy_raw < -10'sd24) ? -10'sd24 : S_dy_raw;
    wire signed [10:0] S_dr = $signed({3'b000, S_dat2[23:16]}) + S_dy;
    wire signed [10:0] S_dg = $signed({3'b000, S_dat2[15:8]})  + S_dy;
    wire signed [10:0] S_db = $signed({3'b000, S_dat2[7:0]})   + S_dy;

    wire [7:0] S_ro = S_dr[10] ? 8'd0 : (|S_dr[9:8] ? 8'd255 : S_dr[7:0]);
    wire [7:0] S_go = S_dg[10] ? 8'd0 : (|S_dg[9:8] ? 8'd255 : S_dg[7:0]);
    wire [7:0] S_bo = S_db[10] ? 8'd0 : (|S_db[9:8] ? 8'd255 : S_db[7:0]);

    // ------------------------------------------------------- timing delay 3 --
    reg S_vs1, S_vs2, S_vs3;
    reg S_hs1, S_hs2, S_hs3;
    reg S_de1, S_de2, S_de3;
    reg S_us1, S_us2, S_us3;
    reg S_ls1, S_ls2, S_ls3;

    // ------------------------------------------------------- frame tracking --
    reg  S_vsync_1d;
    wire S_vs_rise = I_vsync & ~S_vsync_1d;

    // Synchronous, read-before-write RAM ports without output resets map to
    // two block RAMs. The live mask preserves the original reset-visible
    // output values without resetting RAM cells or adding any video latency.
    always @(posedge I_clk) begin
        if (I_rst_n) begin
            S_h_raw <= S_hist[S_norm ? S_nidx[7:0] : S_h_a1];
            if (S_norm_1d) begin
                if (S_nidx_d < 9'd256)
                    S_hist[S_nidx_d[7:0]] <= 20'd0;
            end else if (S_h_v2)
                S_hist[S_h_a2] <= S_h_next;
        end
    end
    always @(posedge I_clk) begin
        if (I_rst_n) begin
            S_lut_raw <= S_lut[{S_lut_sel, S_y}];
            if (S_norm_1d && (S_nidx_d < 9'd256) && !S_first)
                S_lut[{S_lut_sel, S_nidx_d[7:0]}] <= S_lut_val;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_y <= 8'd0;  S_y2 <= 8'd0;
            S_dat1 <= 24'd0; S_dat2 <= 24'd0;
            S_en1 <= 1'b0; S_en2 <= 1'b0;
            S_ram_live <= 1'b0;
            S_h_a1 <= 8'd0; S_h_a2 <= 8'd0; S_h_a3 <= 8'd0;
            S_h_v1 <= 1'b0; S_h_v2 <= 1'b0; S_h_v3 <= 1'b0;
            S_norm <= 1'b1; S_norm_1d <= 1'b0; S_first <= 1'b1;
            S_nidx <= 9'd0; S_nidx_d <= 9'd0; S_cdf <= 20'd0;
            S_lut_sel <= 1'b0; S_lut0_v <= 1'b0; S_lut1_v <= 1'b0;
            S_vs1 <= 1'b0; S_vs2 <= 1'b0; S_vs3 <= 1'b0;
            S_hs1 <= 1'b0; S_hs2 <= 1'b0; S_hs3 <= 1'b0;
            S_de1 <= 1'b0; S_de2 <= 1'b0; S_de3 <= 1'b0;
            S_us1 <= 1'b0; S_us2 <= 1'b0; S_us3 <= 1'b0;
            S_ls1 <= 1'b0; S_ls2 <= 1'b0; S_ls3 <= 1'b0;
            S_vsync_1d <= 1'b0;
            O_vsync <= 1'b0; O_hsync <= 1'b0; O_de <= 1'b0;
            O_user <= 1'b0;  O_last <= 1'b0;  O_data <= 24'd0;
        end
        else begin
            S_ram_live <= 1'b1;
            // ------------------------------------------ pipeline: luma / data
            S_y    <= S_y_now;
            S_y2   <= S_y;
            S_dat1 <= I_data;
            S_dat2 <= S_dat1;
            S_en1  <= I_en;
            S_en2  <= S_en1;

            // ------------------------------------------ histogram collect
            S_h_a1  <= S_y;
            S_h_a2  <= S_h_a1;
            S_h_a3  <= S_h_a2;
            S_h_v1  <= S_y_v;
            S_h_v2  <= S_h_v1;
            S_h_v3  <= S_h_v2;

            // ------------------------------------------ normalize pass
            S_vsync_1d <= I_vsync;
            if (!S_norm) begin
                if (S_vs_rise) begin
                    S_norm    <= 1'b1;
                    S_nidx    <= 9'd0;
                    S_cdf     <= 20'd0;
                    // Work on the bank that is not being displayed: the read
                    // bank IS S_lut_sel, so the next pass must refill the other
                    // one -- i.e. select it and write it.
                    S_lut_sel <= ~S_lut_sel;
                    // Until the pass completes the selected bank is the one
                    // being overwritten, so drop its valid flag: the picture
                    // passes through untouched instead of showing half a LUT.
                    if (S_lut_sel) S_lut0_v <= 1'b0;   // new sel = 0
                    else           S_lut1_v <= 1'b0;   // new sel = 1
                end
            end
            else if (S_nidx == 9'd256) begin
                S_norm <= 1'b0;
                if (!S_first) begin
                    // flag the bank that was just written (same select)
                    if (S_lut_sel) S_lut1_v <= 1'b1;
                    else           S_lut0_v <= 1'b1;
                end
                S_first <= 1'b0;
            end
            else begin
                S_nidx <= S_nidx + 9'd1;
            end
            S_norm_1d <= S_norm;
            S_nidx_d  <= S_nidx;
            if (S_norm_1d)
                S_cdf <= S_cdf_nxt[19:0];

            // ------------------------------------------ apply
            O_data <= (S_en2 & S_lut_v_now) ? {S_ro, S_go, S_bo} : S_dat2;

            // ------------------------------------------ timing, delayed by 3
            S_vs1 <= I_vsync; S_vs2 <= S_vs1; S_vs3 <= S_vs2; O_vsync <= S_vs3;
            S_hs1 <= I_hsync; S_hs2 <= S_hs1; S_hs3 <= S_hs2; O_hsync <= S_hs3;
            S_de1 <= I_de;    S_de2 <= S_de1; S_de3 <= S_de2; O_de    <= S_de3;
            S_us1 <= I_user;  S_us2 <= S_us1; S_us3 <= S_us2; O_user  <= S_us3;
            S_ls1 <= I_last;  S_ls2 <= S_ls1; S_ls3 <= S_ls2; O_last  <= S_ls3;
        end
    end

endmodule
