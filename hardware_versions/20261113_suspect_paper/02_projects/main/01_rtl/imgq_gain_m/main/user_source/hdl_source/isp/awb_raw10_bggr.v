// Bayer-domain white balance for the SC500CS 4-pixel RAW10 stream.
//
// The input word is packed little-endian as four 10-bit pixels:
//   I_tdata[ 9: 0] = P0, [19:10] = P1, [29:20] = P2, [39:30] = P3.
// For the configured BGGR phase, an even line is B,Gr,B,Gr and an odd
// line is Gb,R,Gb,R.  The module keeps the row phase from accepted AXI
// transactions, so a stalled beat cannot change the Bayer phase.
//
// A one-entry output register provides an elastic AXI4-Stream boundary.
// The pixel path has one beat of latency and keeps tuser/tlast aligned.  AWB
// statistics are accumulated from the BLC output and the four gains are
// updated only on the last beat of a complete frame.  Consequently the
// gains calculated from frame N are used for frame N+1.
//
// Gain format is unsigned Q4.16 (1.0 = 20'h10000).  The R/B gains slew by
// AWB_STEP (0x200 by default) per frame.  Gr/Gb are independently balanced,
// but are restricted to a narrow +/-2% range so Bayer phase or BLC errors
// cannot cause a large green excursion.  The data path remains 10-bit until
// the final saturating multiply result.
`timescale 1ns/1ps

module awb_raw10_bggr #(
    parameter integer IMG_WIDTH  = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer PIX_PER_BEAT = 4,
    parameter [19:0] AWB_STEP    = 20'h00200,
    // One sample is taken every STAT_DECIM accepted beats.  A beat contains
    // two samples of each colour in the active Bayer row.
    parameter integer STAT_DECIM = 8,
    // RAW values are post-BLC 10-bit DN.  The green pair is used as the
    // inexpensive brightness gate for the statistics.  The first complete
    // frame uses the fixed limits below; subsequent frames derive a broad
    // (approximately 0.5x..1.5x) gate from the previous frame's green mean.
    parameter integer STAT_LUM_MIN = 10'd32,
    parameter integer STAT_LUM_MAX = 10'd980
) (
    input  wire        I_clk,
    input  wire        I_rst_n,

    input  wire        I_tvalid,
    output wire        I_tready,
    input  wire        I_tuser,
    input  wire        I_tlast,
    input  wire [39:0] I_tdata,

    output wire        O_tvalid,
    input  wire        O_tready,
    output wire        O_tuser,
    output wire        O_tlast,
    output wire [39:0] O_tdata
);

    localparam integer BEATS_PER_LINE = IMG_WIDTH / PIX_PER_BEAT;
    localparam integer ROW_W = (IMG_HEIGHT <= 2) ? 1 : $clog2(IMG_HEIGHT);
    localparam integer BEAT_W = (BEATS_PER_LINE <= 2) ? 1 : $clog2(BEATS_PER_LINE);
    localparam integer DEC_W = (STAT_DECIM <= 2) ? 1 : $clog2(STAT_DECIM);
    localparam [10:0] LUM_MIN2 = STAT_LUM_MIN * 2;
    localparam [10:0] LUM_MAX2 = STAT_LUM_MAX * 2;
    localparam [19:0] GAIN_ONE = 20'h10000;
    localparam [19:0] GAIN_MIN = 20'h08000; // 0.5
    localparam [19:0] GAIN_MAX = 20'h20000; // 2.0
    localparam [19:0] GREEN_MIN = 20'h0fae1; // 0.98
    localparam [19:0] GREEN_MAX = 20'h1051f; // 1.02

    reg        valid_r;
    reg        user_r;
    reg        last_r;
    reg [39:0] data_r;

    // 0 = first BGGR row, 1 = second GBRG row.  A frame-start beat always
    // establishes row zero, independent of the previous frame's state.
    reg                    row_parity_r;
    reg [ROW_W-1:0]        row_idx_r;
    reg [BEAT_W-1:0]       beat_idx_r;
    reg                    frame_bad_r;

    reg [DEC_W-1:0]        stat_decim_r;

    // A 720p frame has fewer than 2^28 RAW values in each colour sum.  Keep
    // 32 bits so the accumulator also remains safe for wider test images.
    reg [31:0] sum_r;
    reg [31:0] sum_gr;
    reg [31:0] sum_gb;
    reg [31:0] sum_b;

    // Q4.16 frame gains.  The green gains have their own narrow range.
    reg [19:0] gain_r;
    reg [19:0] gain_gr;
    reg [19:0] gain_gb;
    reg [19:0] gain_b;

    wire in_fire = I_tvalid && I_tready;
    wire row_for_input = I_tuser ? 1'b0 : row_parity_r;

    wire [9:0] p0 = I_tdata[9:0];
    wire [9:0] p1 = I_tdata[19:10];
    wire [9:0] p2 = I_tdata[29:20];
    wire [9:0] p3 = I_tdata[39:30];

    wire [10:0] pair_02 = {1'b0,p0} + {1'b0,p2};
    wire [10:0] pair_13 = {1'b0,p1} + {1'b0,p3};
    wire [10:0] green_pair = row_for_input ? pair_02 : pair_13;

    // A low-resource frame-mean tracker.  It is an alpha=1/32 IIR updated at
    // the same decimated rate as the colour accumulators, so no frame divider
    // or extra multiplier is inferred.  The tracker is intentionally separate
    // from the AWB chroma statistics: even a large exposure step still moves
    // the next frame's brightness gate instead of locking it out.
    localparam [9:0] MEAN_INIT = (STAT_LUM_MIN + STAT_LUM_MAX) / 2;
    reg  [9:0] green_mean_run_r;
    reg  [9:0] green_mean_prev_r;
    reg        green_mean_valid_r;

    wire [9:0] mean_sample = green_pair[10:1];
    wire       mean_take = in_fire &&
                           ((STAT_DECIM <= 1) ||
                            (stat_decim_r == STAT_DECIM-1));
    wire [9:0] mean_diff = (mean_sample >= green_mean_run_r) ?
                           (mean_sample - green_mean_run_r) :
                           (green_mean_run_r - mean_sample);
    wire [9:0] mean_step_q = mean_diff >> 5;
    wire [9:0] mean_step = (mean_diff != 0) ?
                           ((mean_step_q == 0) ? 10'd1 : mean_step_q) :
                           10'd0;
    wire [10:0] mean_up_sum = {1'b0,green_mean_run_r} +
                               {1'b0,mean_step};
    wire [9:0] green_mean_next = (mean_sample >= green_mean_run_r) ?
                                  ((mean_up_sum > 11'd1023) ?
                                   10'd1023 : mean_up_sum[9:0]) :
                                  green_mean_run_r - mean_step;

    // Dynamic gate limits.  Keep the configured static floor/ceiling and
    // force a minimum useful window in very dark frames so a zero mean cannot
    // deadlock the tracker.  Values are doubled to compare against the pair
    // sum without adding a divider to the pixel path.
    wire [10:0] mean_ext       = {1'b0,green_mean_prev_r};
    wire [10:0] mean_half      = mean_ext >> 1;
    wire [10:0] dyn_min_raw    = (mean_ext > mean_half) ?
                                  (mean_ext - mean_half) : 11'd0;
    wire [10:0] dyn_max_raw    = mean_ext + mean_half;
    wire [10:0] dyn_min_floor  = (dyn_min_raw < STAT_LUM_MIN) ?
                                  STAT_LUM_MIN : dyn_min_raw;
    wire [10:0] dyn_max_ceil   = (dyn_max_raw > STAT_LUM_MAX) ?
                                  STAT_LUM_MAX : dyn_max_raw;
    wire [10:0] dyn_max_window = (dyn_max_ceil < dyn_min_floor + 11'd64) ?
                                  ((dyn_min_floor + 11'd64 > STAT_LUM_MAX) ?
                                   STAT_LUM_MAX : dyn_min_floor + 11'd64) :
                                  dyn_max_ceil;
    wire [10:0] gate_lum_min2  = green_mean_valid_r ?
                                  (dyn_min_floor << 1) : LUM_MIN2;
    wire [10:0] gate_lum_max2  = green_mean_valid_r ?
                                  (dyn_max_window << 1) : LUM_MAX2;

    wire        bright_enough = (green_pair >= gate_lum_min2) &&
                                (green_pair <= gate_lum_max2);
    wire        take_stat = in_fire && bright_enough &&
                            ((STAT_DECIM <= 1) ||
                             (stat_decim_r == STAT_DECIM-1));

    // Only the two same-colour slots for the current row are added.  Every
    // full frame has the same number of R/B/Gr/Gb slots, so sums can be used
    // directly for grey-world comparisons without an explicit pixel count.
    wire [31:0] add_r  = take_stat && row_for_input ? {21'd0,pair_13} : 32'd0;
    wire [31:0] add_gr = take_stat && !row_for_input ? {21'd0,pair_13} : 32'd0;
    wire [31:0] add_gb = take_stat && row_for_input ? {21'd0,pair_02} : 32'd0;
    wire [31:0] add_b  = take_stat && !row_for_input ? {21'd0,pair_02} : 32'd0;

    wire [31:0] sum_r_eff  = sum_r  + add_r;
    wire [31:0] sum_gr_eff = sum_gr + add_gr;
    wire [31:0] sum_gb_eff = sum_gb + add_gb;
    wire [31:0] sum_b_eff  = sum_b  + add_b;

    // A complete frame is identified from the configured line count.  This
    // avoids waiting for a separate frame-end marker and works with the
    // uial2axis/frame_guard contract (tlast at every line end).
    // Only a correctly shaped last beat may publish a frame's statistics.
    // The SOF+TLAST form is retained for a one-beat, one-line simulation frame.
    wire beat_is_last = (beat_idx_r == BEATS_PER_LINE-1);
    wire shape_ok = (I_tlast == beat_is_last);
    wire frame_end = in_fire && I_tlast && shape_ok && !frame_bad_r &&
                     ((I_tuser && (IMG_HEIGHT == 1) &&
                       (BEATS_PER_LINE == 1)) ||
                      (!I_tuser && (row_idx_r == IMG_HEIGHT-1)));

    // Gain tracking is deliberately multiply/compare based.  It avoids two
    // variable dividers in the pixel clock domain while converging to the
    // same grey-world ratio over successive frames.
    // Keep the operands at their true widths.  The previous explicit 52-bit
    // extensions encouraged a very large 52x52 multiplier in TD synthesis.
    // The 52-bit destinations preserve the full 32x20 product.
    // Use the registered accumulator values for gain estimation.  The final
    // beat is committed to the accumulators at the same edge as frame_end;
    // excluding that one beat breaks the long dynamic-gate -> add -> multiply
    // cone while changing a 720p frame estimate by less than 0.001%.
    wire [51:0] r_track_product  = sum_r  * gain_r;
    wire [51:0] b_track_product  = sum_b  * gain_b;
    wire [51:0] gr_track_product = sum_gr * gain_gr;
    wire [51:0] gb_track_product = sum_gb * gain_gb;
    wire [31:0] r_track = r_track_product >> 16;
    wire [31:0] b_track = b_track_product >> 16;
    wire [31:0] gr_track = gr_track_product >> 16;
    wire [31:0] gb_track = gb_track_product >> 16;

    // A small relative deadband avoids gain chatter when the two channel
    // sums differ by only quantisation noise.
    wire [32:0] green_total = {1'b0,sum_gr} + {1'b0,sum_gb};
    wire [32:0] g_ref = green_total >> 1;
    wire [32:0] g_db  = g_ref >> 8;
    wire [32:0] r_low_bound = g_ref - (g_ref >> 8);
    wire [32:0] r_high_bound = g_ref + (g_ref >> 8);

    function [9:0] gain_pixel;
        input [9:0] pixel;
        input [19:0] gain;
        reg [29:0] product;
        reg [29:0] scaled;
        begin
            product = pixel * gain;
            scaled  = (product + 30'd32768) >> 16;
            if (scaled > 30'd1023)
                gain_pixel = 10'd1023;
            else
                gain_pixel = scaled[9:0];
        end
    endfunction

    wire [9:0] q0 = row_for_input ? gain_pixel(p0,gain_gb)
                                  : gain_pixel(p0,gain_b);
    wire [9:0] q1 = row_for_input ? gain_pixel(p1,gain_r)
                                  : gain_pixel(p1,gain_gr);
    wire [9:0] q2 = row_for_input ? gain_pixel(p2,gain_gb)
                                  : gain_pixel(p2,gain_b);
    wire [9:0] q3 = row_for_input ? gain_pixel(p3,gain_r)
                                  : gain_pixel(p3,gain_gr);
    wire [39:0] scaled_word = {q3,q2,q1,q0};

    assign I_tready = ~valid_r | O_tready;
    assign O_tvalid = valid_r;
    assign O_tuser  = user_r;
    assign O_tlast  = last_r;
    assign O_tdata  = data_r;

    // Elastic output register and all frame/row/stat state.  Statistics are
    // updated only for accepted input beats; all state is therefore stable
    // while a downstream block applies back-pressure.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            valid_r      <= 1'b0;
            user_r       <= 1'b0;
            last_r       <= 1'b0;
            data_r       <= 40'd0;
            row_parity_r <= 1'b0;
            row_idx_r    <= {ROW_W{1'b0}};
            stat_decim_r <= {DEC_W{1'b0}};
            sum_r        <= 32'd0;
            sum_gr       <= 32'd0;
            sum_gb       <= 32'd0;
            sum_b        <= 32'd0;
            gain_r       <= GAIN_ONE;
            gain_gr      <= GAIN_ONE;
            gain_gb      <= GAIN_ONE;
            gain_b       <= GAIN_ONE;
            green_mean_run_r  <= MEAN_INIT;
            green_mean_prev_r <= MEAN_INIT;
            green_mean_valid_r<= 1'b0;
            beat_idx_r   <= {BEAT_W{1'b0}};
            frame_bad_r  <= 1'b0;
        end else begin
            if (I_tready) begin
                if (I_tvalid) begin
                    valid_r <= 1'b1;
                    user_r  <= I_tuser;
                    last_r  <= I_tlast;
                    data_r  <= scaled_word;
                end else begin
                    valid_r <= 1'b0;
                end
            end

            if (in_fire) begin
                // A frame-start beat establishes both the Bayer phase and
                // the row counter before this beat is interpreted.
                if (I_tuser) begin
                    // Always restart geometry at SOF, including after a
                    // malformed or truncated preceding frame.
                    row_idx_r    <= {ROW_W{1'b0}};
                    row_parity_r <= 1'b0;
                    frame_bad_r  <= (BEATS_PER_LINE == 1) ? !I_tlast : I_tlast;
                    beat_idx_r   <= (BEATS_PER_LINE <= 1) ?
                                    {BEAT_W{1'b0}} : {{(BEAT_W-1){1'b0}},1'b1};
                    // For a one-beat line, SOF+TLAST also completes line 0;
                    // advance to line 1 so a compact multi-line test frame
                    // gets the same phase/row semantics as the production
                    // stream.
                    if ((BEATS_PER_LINE == 1) && I_tlast &&
                        (IMG_HEIGHT > 1)) begin
                        row_idx_r    <= {{(ROW_W-1){1'b0}},1'b1};
                        row_parity_r <= 1'b1;
                    end
                end else if (I_tlast) begin
                    if (!shape_ok) begin
                        frame_bad_r <= 1'b1;
                        beat_idx_r  <= {BEAT_W{1'b0}};
                    end else if (row_idx_r == IMG_HEIGHT-1) begin
                        row_idx_r     <= {ROW_W{1'b0}};
                        row_parity_r  <= 1'b0;
                        beat_idx_r    <= {BEAT_W{1'b0}};
                    end else begin
                        row_idx_r     <= row_idx_r + 1'b1;
                        row_parity_r  <= ~row_parity_r;
                        beat_idx_r    <= {BEAT_W{1'b0}};
                    end
                end else begin
                    if (beat_is_last)
                        frame_bad_r <= 1'b1;
                    beat_idx_r <= beat_idx_r + 1'b1;
                end

                if (STAT_DECIM <= 1)
                    stat_decim_r <= {DEC_W{1'b0}};
                else if (stat_decim_r == STAT_DECIM-1)
                    stat_decim_r <= {DEC_W{1'b0}};
                else
                    stat_decim_r <= stat_decim_r + 1'b1;

                if (I_tuser) begin
                    // A new SOF must discard any incomplete prior-frame sums.
                    sum_r  <= add_r;
                    sum_gr <= add_gr;
                    sum_gb <= add_gb;
                    sum_b  <= add_b;
                end else if (frame_end) begin
                    sum_r  <= 32'd0;
                    sum_gr <= 32'd0;
                    sum_gb <= 32'd0;
                    sum_b  <= 32'd0;
                end else begin
                    sum_r  <= sum_r_eff;
                    sum_gr <= sum_gr_eff;
                    sum_gb <= sum_gb_eff;
                    sum_b  <= sum_b_eff;
                end

                // Track the green brightness independently of the colour
                // acceptance gate.  This lets the following frame recover
                // after a large exposure step that would otherwise reject
                // every sample against the previous narrow window.
                if (mean_take)
                    green_mean_run_r <= green_mean_next;
            end

            // Publish the completed frame estimate for the next frame.  The
            // valid bit keeps the first frame on the conservative static
            // limits, avoiding a startup decision from MEAN_INIT alone.
            if (frame_end) begin
                green_mean_prev_r  <= mean_take ? green_mean_next : green_mean_run_r;
                green_mean_valid_r <= 1'b1;
            end

            // Update all gains at the frame boundary.  A frame with no valid
            // mid-tone samples leaves its previous gains untouched.
            if (frame_end && (sum_r != 0) && (sum_gr != 0) &&
                (sum_gb != 0) && (sum_b != 0)) begin
                if (r_track < r_low_bound) begin
                    if (gain_r <= GAIN_MAX-AWB_STEP)
                        gain_r <= gain_r + AWB_STEP;
                    else
                        gain_r <= GAIN_MAX;
                end else if (r_track > r_high_bound) begin
                    if (gain_r >= GAIN_MIN+AWB_STEP)
                        gain_r <= gain_r - AWB_STEP;
                    else
                        gain_r <= GAIN_MIN;
                end

                if (b_track < r_low_bound) begin
                    if (gain_b <= GAIN_MAX-AWB_STEP)
                        gain_b <= gain_b + AWB_STEP;
                    else
                        gain_b <= GAIN_MAX;
                end else if (b_track > r_high_bound) begin
                    if (gain_b >= GAIN_MIN+AWB_STEP)
                        gain_b <= gain_b - AWB_STEP;
                    else
                        gain_b <= GAIN_MIN;
                end

                if ((gr_track + g_db) < gb_track) begin
                    if (gain_gr <= GREEN_MAX-AWB_STEP)
                        gain_gr <= gain_gr + AWB_STEP;
                    else
                        gain_gr <= GREEN_MAX;
                    if (gain_gb >= GREEN_MIN+AWB_STEP)
                        gain_gb <= gain_gb - AWB_STEP;
                    else
                        gain_gb <= GREEN_MIN;
                end else if ((gb_track + g_db) < gr_track) begin
                    if (gain_gb <= GREEN_MAX-AWB_STEP)
                        gain_gb <= gain_gb + AWB_STEP;
                    else
                        gain_gb <= GREEN_MAX;
                    if (gain_gr >= GREEN_MIN+AWB_STEP)
                        gain_gr <= gain_gr - AWB_STEP;
                    else
                        gain_gr <= GREEN_MIN;
                end
            end
        end
    end

endmodule
