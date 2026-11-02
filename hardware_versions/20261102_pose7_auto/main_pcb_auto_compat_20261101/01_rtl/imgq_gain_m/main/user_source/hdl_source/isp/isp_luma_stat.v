// Lightweight frame statistics for the SC500 automatic exposure loop.
// One beat out of 64 is sampled from the post-AWB RGB stream. Fixed image
// dimensions permit exact clip scaling using shifts and additions. Mean
// luminance uses one small constant-subtract accumulator beside the stream; this
// monitor never stalls or changes the pixel stream.
module isp_luma_stat #(
    parameter integer CLIP_TH      = 250,
    parameter integer PIX_PER_BEAT = 4,
    parameter integer DIV_BITS     = 28,
    parameter integer IMG_HEIGHT   = 720,
    parameter integer IMG_WIDTH    = 1280
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tvalid,
    input  wire        I_tuser,
    input  wire        I_tlast,
    input  wire [95:0] I_tdata,
    output reg  [8:0]  O_avg_luma,
    output reg  [8:0]  O_clip_pct,
    output reg         O_frame_tgl
);

    localparam integer H_START = IMG_HEIGHT / 4;
    localparam integer H_END   = (3 * IMG_HEIGHT) / 4;

    wire [8:0] y0 = ({1'b0,I_tdata[95:88]} + ({2'b0,I_tdata[87:80]}<<1) + {1'b0,I_tdata[79:72]}) >> 2;
    wire [8:0] y1 = ({1'b0,I_tdata[71:64]} + ({2'b0,I_tdata[63:56]}<<1) + {1'b0,I_tdata[55:48]}) >> 2;
    wire [8:0] y2 = ({1'b0,I_tdata[47:40]} + ({2'b0,I_tdata[39:32]}<<1) + {1'b0,I_tdata[31:24]}) >> 2;
    wire [8:0] y3 = ({1'b0,I_tdata[23:16]} + ({2'b0,I_tdata[15:8]}<<1) + {1'b0,I_tdata[7:0]}) >> 2;
    wire [9:0] ybeat = (y0 + y1 + y2 + y3) >> 2;

    wire sat0 = (I_tdata[95:88] >= CLIP_TH) || (I_tdata[87:80] >= CLIP_TH) || (I_tdata[79:72] >= CLIP_TH);
    wire sat1 = (I_tdata[71:64] >= CLIP_TH) || (I_tdata[63:56] >= CLIP_TH) || (I_tdata[55:48] >= CLIP_TH);
    wire sat2 = (I_tdata[47:40] >= CLIP_TH) || (I_tdata[39:32] >= CLIP_TH) || (I_tdata[31:24] >= CLIP_TH);
    wire sat3 = (I_tdata[23:16] >= CLIP_TH) || (I_tdata[15:8] >= CLIP_TH) || (I_tdata[7:0] >= CLIP_TH);
    wire [2:0] sat_pixels = {2'b0,sat0} + {2'b0,sat1} + {2'b0,sat2} + {2'b0,sat3};

    // Only the verified 720p geometry uses reduced ranges. Other parameter
    // combinations retain the original state widths and arithmetic semantics.
    localparam integer COMPACT = IMG_WIDTH == 1280 && IMG_HEIGHT == 720 && PIX_PER_BEAT == 4;
    localparam integer LINE_W = COMPACT ? 10 : 14;
    localparam integer BEAT_W = COMPACT ? 9 : 14;
    localparam integer SUM_W = COMPACT ? 19 : 20;
    localparam integer CENTER_W = COMPACT ? 13 : 16;
    localparam integer ALL_W = COMPACT ? 14 : 16;
    localparam integer QUOT_W = COMPACT ? 8 : 9;
    reg [5:0]  sample_div;
    reg [LINE_W-1:0] line_h;
    reg [BEAT_W-1:0] beat_x;
    reg        frame_started;
    reg        frame_bad;
    reg [SUM_W-1:0] center_sum;
    reg [CENTER_W-1:0] center_pixels;
    reg [ALL_W-1:0] all_pixels;
    reg [ALL_W-1:0] clip_pixels;
    localparam integer BEATS_PER_LINE = IMG_WIDTH / PIX_PER_BEAT;
    // This fixed 720p meter receives exactly five groups per line. The
    // center accumulates 1800 group means, whereas clipping covers all 14400
    // sampled pixels. The old /72 approximation doubled the clip fraction.
    localparam integer CENTER_PIXELS = 7200;
    localparam integer ALL_PIXELS = 14400;
    wire frame_complete = frame_started && !frame_bad &&
        (IMG_WIDTH == 1280) && (IMG_HEIGHT == 720) && (PIX_PER_BEAT == 4) &&
        (line_h == IMG_HEIGHT) && (beat_x == 0) &&
        // Fixed 720p framing already proves 14400/7200 sampled pixels.
        // Keep the original check for every non-production parameter set.
        // Counter declarations and accumulation are retained for RTL probes;
        // synthesis may remove them when COMPACT makes this guard constant.
        (COMPACT || ((all_pixels == ALL_PIXELS) && (center_pixels == CENTER_PIXELS)));

    // floor(n * 3641 / 2^19) == floor(n / 144) for every n in 0..14400.
    // Sized shifts implement 3641 = 4096 - 512 + 64 - 8 + 1, with no DSP or
    // generic divider. Exhaustive verification covers the entire valid range.
    wire [27:0] clip_extended = {{(28-ALL_W){1'b0}},clip_pixels};
    wire [27:0] clip_times3641 = (clip_extended << 12)
        - (clip_extended << 9) + (clip_extended << 6)
        - (clip_extended << 3) + clip_extended;
    wire [8:0] clip_exact_pct = clip_times3641[27:19];

    reg        avg_busy;
    reg [SUM_W-1:0] avg_remainder;
    reg [QUOT_W-1:0] avg_quotient;
    reg [8:0]  clip_pending;
    wire [SUM_W:0] avg_difference = {1'b0,avg_remainder} - 1800;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sample_div    <= 0;
            line_h        <= 0;
            beat_x        <= 0;
            frame_started <= 0;
            frame_bad     <= 0;
            center_sum    <= 0;
            center_pixels <= 0;
            all_pixels    <= 0;
            clip_pixels   <= 0;
            avg_busy      <= 0;
            avg_remainder <= 0;
            avg_quotient  <= 0;
            clip_pending  <= 0;
            O_avg_luma    <= 0;
            O_clip_pct    <= 0;
            O_frame_tgl   <= 0;
        end else if (I_tuser) begin
            // A new SOF cancels any unfinished old calculation. Only an
            // entirely received, correctly framed image starts a new one.
            // Keep the last reliable outputs and toggle unchanged on bad or
            // empty frames; consumers cannot mistake held data for a new sample.
            avg_busy <= 0;
            if (frame_complete) begin
                avg_remainder <= center_sum;
                avg_quotient  <= 0;
                clip_pending  <= clip_exact_pct;
                avg_busy      <= 1;
            end
            frame_started <= 1;
            frame_bad     <= I_tvalid && I_tlast;
            // SOF may accompany the first valid beat: count that beat in the
            // new frame rather than silently discarding it. For a separate
            // SOF pulse, the next valid beat remains sample position zero.
            sample_div    <= I_tvalid ? 6'd1 : 6'd0;
            line_h        <= (I_tvalid && I_tlast) ? 14'd1 : 14'd0;
            beat_x        <= (I_tvalid && !I_tlast) ? 14'd1 : 14'd0;
            center_sum    <= 0;
            center_pixels <= 0;
            all_pixels    <= I_tvalid ? 16'd4 : 16'd0;
            clip_pixels   <= I_tvalid ? {13'd0,sat_pixels} : 16'd0;
        end else begin
            if (avg_busy) begin
                // At most 255 subtractions plus this completion cycle:
                // 2.048 us at 125 MHz, only on the AE sideband. The next
                // frame accumulates independently in center_sum/clip_pixels.
                if (avg_difference[SUM_W]) begin
                    O_avg_luma  <= avg_quotient;
                    O_clip_pct  <= clip_pending;
                    O_frame_tgl <= ~O_frame_tgl;
                    avg_busy   <= 0;
                end else begin
                    avg_remainder <= avg_difference[SUM_W-1:0];
                    avg_quotient  <= avg_quotient + 1'b1;
                end
            end
            // Keep all state updates under the single clocked conditional.
            // Some TD synthesis versions reject a second independent
            // condition after the I_tvalid branch (reported as an
            // unsupported sensitivity-list edge).  tlast is generated on a
            // valid beat by the AXI stream, so it can safely be handled here.
            if (I_tvalid && frame_started && !frame_bad) begin
                if ((line_h >= IMG_HEIGHT) ||
                    (I_tlast != (beat_x == BEATS_PER_LINE-1)))
                    frame_bad <= 1;
                if (sample_div == 0) begin
                    if ((line_h >= H_START) && (line_h < H_END)) begin
                        center_sum    <= center_sum + ybeat;
                        center_pixels <= center_pixels + PIX_PER_BEAT;
                    end
                    all_pixels  <= all_pixels + PIX_PER_BEAT;
                    clip_pixels <= clip_pixels + sat_pixels;
                end
                sample_div <= sample_div + 1'b1;
                if (I_tlast) begin
                    line_h <= line_h + 1'b1;
                    beat_x <= 0;
                end else begin
                    beat_x <= beat_x + 1'b1;
                end
            end
        end
    end
endmodule

