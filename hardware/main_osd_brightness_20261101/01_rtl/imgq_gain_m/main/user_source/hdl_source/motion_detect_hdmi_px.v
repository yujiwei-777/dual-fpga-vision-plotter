// Post histogram motion detector in the HDMI pixel clock domain.
//
// The detector deliberately works on an 8x8 decimated image (160x90).  A
// BRAM-backed frame of luma samples is compared with the previous frame and
// the bounding box of a sufficiently large moving region is reported.
// Results are committed once, at the next frame USER pulse, so the mixer
// never observes half-updated coordinates.

module motion_detect_hdmi_px #(
    parameter [7:0]  MOTION_TH = 8'd20,
    parameter [7:0]  DARK_MIN  = 8'd16,
    // 8x8 decimation produces a 160x90 sample grid.  Keep the threshold
    // proportional to the grid; 400 samples (the old 4x4 setting) rejects
    // normal moving objects at this resolution.
    parameter [15:0] MIN_AREA  = 16'd80,
    parameter integer CONFIRM  = 2
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_en,
    input  wire [23:0] I_data,
    input  wire        I_vsync,
    input  wire        I_hsync,
    input  wire        I_de,
    input  wire        I_user,
    input  wire        I_last,
    input  wire        I_on_frame,
    output reg         O_valid,
    output reg  [10:0] O_x_min,
    output reg  [9:0]  O_y_min,
    output reg  [10:0] O_x_max,
    output reg  [9:0]  O_y_max,
    output reg  [15:0] O_count,
    output reg         O_toggle
);

    // 77R + 150G + 29B, rounded down by eight bits.  Shift/add form keeps
    // this post-HDMI experiment off the limited DSP budget.
    function [7:0] F_gray;
        input [7:0] r, g, b;
        reg [17:0] s;
        begin
            s = ({10'd0,r} << 6) + ({10'd0,r} << 3) +
                ({10'd0,r} << 2) + {10'd0,r} +
                ({10'd0,g} << 7) + ({10'd0,g} << 4) +
                ({10'd0,g} << 2) + ({10'd0,g} << 1) +
                ({10'd0,b} << 4) + ({10'd0,b} << 3) +
                ({10'd0,b} << 2) + {10'd0,b};
            F_gray = s[15:8];
        end
    endfunction

    wire [7:0] pix_gray = F_gray(I_data[23:16], I_data[15:8], I_data[7:0]);

    // Pixel counters are in the active 1280x720 area.  I_last is the final
    // active pixel of a line; USER is expected on the first valid pixel.
    reg [10:0] x;
    reg [9:0]  y;
    wire sample_now = I_de && (x[2:0] == 3'b000) && (y[2:0] == 3'b000);
    // Explicit zero extension is required before shifting; otherwise a
    // Verilog expression keeps the 8-bit row width and silently truncates
    // addresses above 255.
    // 160 samples per row: y*160 + x = (y<<7)+(y<<5)+x.
    // 14 bits cover the 0..14399 address range and keep the address adder
    // narrower than the former 16-bit implementation.
    wire [13:0] sample_addr = ({6'd0,y[9:3]} << 7) +
                              ({6'd0,y[9:3]} << 5) + {6'd0,x[10:3]};

    // Keep the frame store's write port in one small process.  Multiple
    // writes to the same inferred RAM (the USER first-pixel path and the
    // regular 8x8 sample path) make TD flatten the array into hundreds of
    // thousands of flip-flops.  A single write mux preserves BRAM inference.
    wire first_sample = I_user && I_de;
    wire sample_en = I_en && I_on_frame && I_de && (first_sample || sample_now);
    wire [13:0] sample_addr_rd = first_sample ? 14'd0 : sample_addr;

    // 160*90 bytes.  Keep the explicit BRAM attribute: converting this to
    // distributed RAM consumes the remaining LUT budget on HX1P35A.
    // Use a 16K power-of-two frame store.  Only addresses 0..14399 are used
    // by the 160x90 sample grid; the remaining locations are harmless
    // padding.  Keeping the array power-of-two preserves BRAM inference while
    // reducing the implementation footprint versus the previous 32K store.
    (* ram_style = "bram" *) reg [7:0] prev_luma [0:16383];
    reg       rd_valid;
    reg [7:0] rd_luma;
    reg [7:0] rd_current;
    reg [8:0] rd_x;
    reg [7:0] rd_y;
    reg       have_previous;
    reg       frame_started;

    reg [15:0] count;
    reg [8:0]  x_min, x_max;
    reg [7:0]  y_min, y_max;
    reg [2:0]  confirm_count;

    // Histogram LUT transitions can mark almost every sample as changed.
    // Reject frame-sized regions so that such transitions never become a
    // full-screen red box.  Limits are expressed in the 160x90 sample grid.
    wire [8:0] box_w = (x_max >= x_min) ? (x_max - x_min + 9'd1) : 9'd0;
    wire [7:0] box_h = (y_max >= y_min) ? (y_max - y_min + 8'd1) : 8'd0;
    wire box_limit_ok = (box_w <= 9'd120) && (box_h <= 8'd80);

    // Single synchronous RAM read/write port. Keeping the only write here
    // lets TD infer BRAM instead of flattening the frame store into FFs.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            rd_valid <= 1'b0;
            rd_luma <= 8'd0;
            rd_current <= 8'd0;
            rd_x <= 9'd0;
            rd_y <= 8'd0;
        end else begin
            rd_valid <= sample_en;
            if (sample_en) begin
                rd_luma <= prev_luma[sample_addr_rd];
                rd_current <= pix_gray;
                rd_x <= first_sample ? 9'd0 : x[10:3];
                // y is also kept in 8x8 sample units.  The previous [9:2]
                // expression was left over from the 4x4 detector and made
                // the reported vertical coordinates twice as large.
                rd_y <= first_sample ? 8'd0 : y[9:3];
                prev_luma[sample_addr_rd] <= pix_gray;
            end
        end
    end

    wire [8:0] diff = (rd_luma > rd_current) ?
                      ({1'b0,rd_luma} - {1'b0,rd_current}) :
                      ({1'b0,rd_current} - {1'b0,rd_luma});
    // rd_luma is the old sample read from BRAM.  The current sample is
    // written back in the same cycle, implementing a rolling frame store.
    wire moving_sample = rd_valid && have_previous &&
                         (diff > {1'b0,MOTION_TH}) &&
                         ((rd_luma > DARK_MIN) || (rd_current > DARK_MIN));

    // Lightweight candidate decision.  The previous implementation also
    // multiplied the bounding-box width and height and applied a fill-rate
    // test.  That wide combinational multiplier consumed SLICEL resources
    // and could prevent PHY placement.  The minimum sample count is retained
    // as the sole acceptance criterion; spatial filtering can be calibrated
    // later with MIN_AREA if needed.
    wire candidate = have_previous && (count >= MIN_AREA) && box_limit_ok;

    // Keep the currently accumulated frame separate from the committed
    // result.  At USER, CONFIRM qualifying frames are required before O_valid
    // is asserted; this suppresses histogram LUT transition flashes.
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x <= 11'd0; y <= 10'd0;
            have_previous <= 1'b0;
            frame_started <= 1'b0;
            count <= 16'd0;
            x_min <= 9'h1ff; x_max <= 9'd0;
            y_min <= 8'hff;  y_max <= 8'd0;
            confirm_count <= 3'd0;
            O_valid <= 1'b0; O_x_min <= 11'd0; O_y_min <= 10'd0;
            O_x_max <= 11'd0; O_y_max <= 10'd0; O_count <= 16'd0;
            O_toggle <= 1'b0;
        end else if (!I_en || !I_on_frame) begin
            x <= 11'd0; y <= 10'd0;
            have_previous <= 1'b0; count <= 16'd0;
            frame_started <= 1'b0;
            x_min <= 9'h1ff; x_max <= 9'd0;
            y_min <= 8'hff; y_max <= 8'd0;
            confirm_count <= 3'd0;
            O_valid <= 1'b0; O_count <= 16'd0;
        end else if (I_user) begin
            // Commit the frame accumulated before this USER.  The first
            // frame only primes the memory and cannot report motion.
            if (candidate) begin
                if (confirm_count < CONFIRM) confirm_count <= confirm_count + 3'd1;
                if ((confirm_count + 3'd1) >= CONFIRM) begin
                    O_valid <= 1'b1;
                    O_x_min <= {x_min,3'b000};
                    O_y_min <= {y_min,3'b000};
                    O_x_max <= ({x_max,3'b000} + 11'd7);
                    O_y_max <= ({y_max,3'b000} + 10'd7);
                    O_count <= count;
                    O_toggle <= ~O_toggle;
                end
            end else begin
                confirm_count <= 3'd0;
                O_valid <= 1'b0;
                O_count <= 16'd0;
            end

            // The first frame only primes BRAM.  Enable comparisons after a
            // complete frame has been received, at the second USER pulse.
            if (frame_started) have_previous <= 1'b1;
            frame_started <= 1'b1;
            count <= 16'd0;
            x_min <= 9'h1ff; x_max <= 9'd0;
            y_min <= 8'hff; y_max <= 8'd0;
            // AXI video commonly asserts USER together with the first DE
            // pixel.  Consume that pixel explicitly so column zero is not
            // lost from the 4x4 sampling grid.  Some VTC revisions pulse
            // USER during blanking; in that case the first DE cycle below
            // starts at x=0 and is sampled normally.
            if (I_de) begin
                x <= 11'd1; y <= 10'd0;
            end else begin
                x <= 11'd0; y <= 10'd0;
            end
        end else if (I_de) begin
            // First consume the delayed BRAM read, then schedule this pixel.
            if (moving_sample) begin
                if (rd_x < x_min) x_min <= rd_x;
                if (rd_x > x_max) x_max <= rd_x;
                if (rd_y < y_min) y_min <= rd_y;
                if (rd_y > y_max) y_max <= rd_y;
                if (count != 16'hffff) count <= count + 16'd1;
            end

            if (I_last) begin
                x <= 11'd0;
                if (y != 10'd719) y <= y + 10'd1;
            end else if (x != 11'd1279) begin
                x <= x + 11'd1;
            end
        end
    end

    // Timing inputs are intentionally present in the interface so the block
    // can be connected directly beside the HDMI mixer.  Pixel framing uses
    // DE/USER/LAST, matching the existing VTC stream and avoiding dependence
    // on HS/VS polarity in different TD IP revisions.
    wire unused_timing = I_vsync ^ I_hsync;

endmodule
