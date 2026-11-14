// RAW-domain AE monitor for the SC500CS BGGR RAW10 stream.
//
// This is a side-band monitor. It consumes only accepted video beats and
// never backpressures or changes the pixel path. The mean uses the two real
// green samples in each four-pixel beat; it does not duplicate a green sample
// into the other colour positions. The fixed centre ROI excludes outside
// samples; accepted ROI samples have weight two, low samples weight one, and
// very dark samples are rejected. O_roi_all includes the dark ROI greens in
// both its sum and fixed complete-frame population; it is not subject luma.
//
// O_clip_pct is a bounded highlight guard in percent. Both the hard clip and
// bright-tail proxy are measured in the same centre ROI as the luma meter,
// using the same spatial weight (ROI pixels have weight two). The proxy is
// capped at BRIGHT_GUARD_MAX so it protects exposure before a large population
// reaches CLIP_TH without making one bright object force a step.
`timescale 1ns/1ps

module raw10_ae_stat #(
    parameter integer IMG_WIDTH        = 1280,
    parameter integer IMG_HEIGHT       = 720,
    parameter integer PIX_PER_BEAT     = 4,
    parameter integer CLIP_TH          = 944,
    parameter integer BRIGHT_TH        = 860,
    parameter integer DARK_TH          = 24,
    parameter integer LOW_TH           = 48,
    parameter integer BRIGHT_GUARD_MAX = 8
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tvalid,
    input  wire        I_tuser,
    input  wire        I_tlast,
    input  wire [39:0] I_tdata,
    output reg  [8:0] O_avg_luma,
    output reg  [8:0] O_clip_pct,
    output reg  [8:0] O_roi_all,
    output reg        O_frame_tgl
);

    localparam integer BEATS_PER_LINE = IMG_WIDTH / PIX_PER_BEAT;
    localparam integer TOTAL_PIXELS   = IMG_WIDTH * IMG_HEIGHT;
    localparam integer GREEN_PIXELS   = TOTAL_PIXELS / 2;
    localparam integer ROI_X0         = 160;
    localparam integer ROI_X1         = 1120; // exclusive: x=160..1119
    localparam integer ROI_Y0         = 90;
    localparam integer ROI_Y1         = 630;  // exclusive: y=90..629
    // The effective bounds make reduced-raster simulation useful while
    // evaluating to the fixed 1280x720 ROI above in production.
    localparam integer ROI_X0_E       = (IMG_WIDTH  > ROI_X0) ? ROI_X0 : 0;
    localparam integer ROI_X1_E       = (IMG_WIDTH  < ROI_X1) ? IMG_WIDTH : ROI_X1;
    localparam integer ROI_Y0_E       = (IMG_HEIGHT > ROI_Y0) ? ROI_Y0 : 0;
    localparam integer ROI_Y1_E       = (IMG_HEIGHT < ROI_Y1) ? IMG_HEIGHT : ROI_Y1;
    localparam integer ROI_PIXELS     = ((ROI_X1_E > ROI_X0_E) && (ROI_Y1_E > ROI_Y0_E)) ?
                                         ((ROI_X1_E-ROI_X0_E) * (ROI_Y1_E-ROI_Y0_E)) : 1;
    localparam integer ROI_GREEN_PIXELS = ROI_PIXELS / 2;
    localparam integer ROI_WEIGHT     = 2;
    localparam integer PCT_DENOM      = ((ROI_PIXELS * ROI_WEIGHT + 99) / 100) > 0 ?
                                         ((ROI_PIXELS * ROI_WEIGHT + 99) / 100) : 1;

    // Complete accepted720p frame bound; malformed frames never publish.
    localparam integer WSUM_W = (GREEN_PIXELS*2046 <= 1) ? 1 : $clog2(GREEN_PIXELS*2046+1);
    localparam integer WCNT_W = (GREEN_PIXELS*2 <= 1) ? 1 : $clog2(GREEN_PIXELS*2+1);
    localparam integer GSUM_W = (GREEN_PIXELS*1023 <= 1) ? 1 : $clog2(GREEN_PIXELS*1023+1);
    localparam integer GCNT_W = (GREEN_PIXELS <= 1) ? 1 : $clog2(GREEN_PIXELS+1);
    localparam integer PCNT_W = (ROI_PIXELS*ROI_WEIGHT <= 1) ? 1 :
                                 $clog2(ROI_PIXELS*ROI_WEIGHT+1);

    reg         frame_started;
    reg         frame_bad;
    reg         row_parity;
    reg [15:0]  line_count;
    reg [15:0]  beat_count;
    reg [WSUM_W-1:0]  weighted_sum;
    reg [WCNT_W-1:0]  weight_sum;
    reg [GSUM_W-1:0]  green_sum_all;
    reg [PCNT_W-1:0]  clip_count;
    reg [PCNT_W-1:0]  bright_count;

    reg [WSUM_W-1:0]  div_rem;
    reg [WCNT_W-1:0]  div_den;
    reg [10:0]  div_q;
    reg [8:0]   clip_q;
    reg [8:0]   clip_result;
    reg [8:0]   bright_q;
    reg [PCNT_W-1:0]  clip_div_start;
    reg [PCNT_W-1:0]  bright_div_start;
    reg [GSUM_W-1:0]  roi_div_start;
    reg [8:0]   avg_result;
    reg [8:0]   highlight_result;
    reg [2:0]   div_state;

    wire [9:0] p0 = I_tdata[9:0];
    wire [9:0] p1 = I_tdata[19:10];
    wire [9:0] p2 = I_tdata[29:20];
    wire [9:0] p3 = I_tdata[39:30];

    wire sof_fire = I_tvalid && I_tuser;

    // BGGR: even row B,Gr,B,Gr; odd row Gb,R,Gb,R.  A SOF beat always uses
    // phase/coordinates zero even when the preceding frame was malformed.
    wire row_for_sample = sof_fire ? 1'b0 : row_parity;
    wire [15:0] line_for_sample = sof_fire ? 16'd0 : line_count;
    wire [15:0] beat_for_sample = sof_fire ? 16'd0 : beat_count;
    wire [9:0] g_a = row_for_sample ? p0 : p1;
    wire [9:0] g_b = row_for_sample ? p2 : p3;
    wire [10:0] x_base = beat_for_sample * 4;
    wire center_y = (line_for_sample >= ROI_Y0_E) && (line_for_sample < ROI_Y1_E);
    wire roi0 = center_y && ((x_base     >= ROI_X0_E) && (x_base     < ROI_X1_E));
    wire roi1 = center_y && ((x_base + 1 >= ROI_X0_E) && (x_base + 1 < ROI_X1_E));
    wire roi2 = center_y && ((x_base + 2 >= ROI_X0_E) && (x_base + 2 < ROI_X1_E));
    wire roi3 = center_y && ((x_base + 3 >= ROI_X0_E) && (x_base + 3 < ROI_X1_E));
    wire center_a = row_for_sample ? roi0 : roi1;
    wire center_b = row_for_sample ? roi2 : roi3;

    function [1:0] sample_weight;
        input [9:0] sample;
        input       is_center;
        begin
            if (sample < DARK_TH)
                sample_weight = 2'd0;
            else if (sample < LOW_TH)
                sample_weight = 2'd1;
            else if (is_center)
                sample_weight = 2'd2;
            else
                sample_weight = 2'd1;
        end
    endfunction

    function [12:0] weighted_sample;
        input [9:0] sample;
        input [1:0] weight;
        begin
            case (weight)
                2'd2: weighted_sample = {2'b0, sample, 1'b0};
                2'd1: weighted_sample = {3'b0, sample};
                default: weighted_sample = 13'd0;
            endcase
        end
    endfunction

    // Green luma is strictly ROI-only. Outside-ROI samples must contribute
    // neither numerator nor denominator; dark ROI samples retain the legacy
    // reject/down-weight behaviour.
    wire [1:0] wa = center_a ? sample_weight(g_a, 1'b1) : 2'd0;
    wire [1:0] wb = center_b ? sample_weight(g_b, 1'b1) : 2'd0;
    // Parentheses around every term are intentional; ?: has lower precedence
    // than + in Verilog and an unparenthesised expression drops w0's terms.
    wire [13:0] weighted_beat = {1'b0, weighted_sample(g_a, wa)} +
                                {1'b0, weighted_sample(g_b, wb)};
    wire [2:0]  weight_beat = {1'b0,wa} + {1'b0,wb};
    wire [11:0] green_beat_all = {2'b0,(center_a ? g_a : 10'd0)} +
                                  {2'b0,(center_b ? g_b : 10'd0)};
    // Clip/bright use the same centre ROI and spatial weight as the luma
    // meter. A four-pixel beat can therefore contribute at most eight.
    wire [3:0]  clip_beat = ((roi0 && (p0 >= CLIP_TH)) ? 4'd2 : 4'd0) +
                             ((roi1 && (p1 >= CLIP_TH)) ? 4'd2 : 4'd0) +
                             ((roi2 && (p2 >= CLIP_TH)) ? 4'd2 : 4'd0) +
                             ((roi3 && (p3 >= CLIP_TH)) ? 4'd2 : 4'd0);
    wire [3:0]  bright_beat = ((roi0 && (p0 >= BRIGHT_TH)) ? 4'd2 : 4'd0) +
                               ((roi1 && (p1 >= BRIGHT_TH)) ? 4'd2 : 4'd0) +
                               ((roi2 && (p2 >= BRIGHT_TH)) ? 4'd2 : 4'd0) +
                               ((roi3 && (p3 >= BRIGHT_TH)) ? 4'd2 : 4'd0);

    wire beat_last = (beat_count == BEATS_PER_LINE-1);
    wire shape_ok  = (I_tlast == beat_last);
    wire [WSUM_W-1:0] weighted_sum_plus = weighted_sum + weighted_beat;
    wire [WCNT_W-1:0] weight_sum_plus   = weight_sum + weight_beat;
    wire [GSUM_W-1:0] green_all_plus    = green_sum_all + green_beat_all;
    wire [PCNT_W-1:0] clip_count_plus   = clip_count + clip_beat;
    wire [PCNT_W-1:0] bright_count_plus = bright_count + bright_beat;
    wire frame_end = I_tvalid && I_tlast && shape_ok && !frame_bad &&
                     (line_count == IMG_HEIGHT-1);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            frame_started   <= 1'b0;
            frame_bad       <= 1'b0;
            row_parity      <= 1'b0;
            line_count      <= 16'd0;
            beat_count      <= 16'd0;
            weighted_sum    <= 40'd0;
            weight_sum      <= 32'd0;
            green_sum_all   <= 40'd0;
            clip_count      <= 32'd0;
            bright_count    <= 32'd0;
            div_rem         <= 40'd0;
            div_den         <= 32'd0;
            div_q           <= 11'd0;
            clip_q          <= 9'd0;
            clip_result     <= 9'd0;
            bright_q        <= 9'd0;
            clip_div_start  <= 32'd0;
            bright_div_start<= 32'd0;
            roi_div_start   <= {GSUM_W{1'b0}};
            avg_result      <= 9'd0;
            highlight_result<= 9'd0;
            div_state       <= 3'd0;
            O_avg_luma      <= 9'd0;
            O_clip_pct      <= 9'd0;
            O_roi_all       <= 9'd0;
            O_frame_tgl     <= 1'b0;
        end else begin
            // State 1: mean divide. If all weighted ROI samples were rejected,
            // div_den is the ROI green population and div_rem is the ROI sum.
            if (div_state == 3'd1) begin
                if (div_rem >= div_den) begin
                    div_rem <= div_rem - div_den;
                    div_q   <= div_q + 1'b1;
                end else begin
                    avg_result <= (div_q > 11'd1020) ? 9'd255 : div_q[9:2];
                    clip_q     <= 9'd0;
                    div_rem    <= clip_div_start;
                    div_state  <= 3'd2;
                end
            end else if (div_state == 3'd2) begin
                // State 2 divides clip_count, never the brightness sum.
                if (div_rem >= PCT_DENOM) begin
                    div_rem <= div_rem - PCT_DENOM;
                    clip_q  <= clip_q + 1'b1;
                end else begin
                    clip_result <= clip_q;
                    bright_q    <= 9'd0;
                    div_rem     <= bright_div_start;
                    div_state   <= 3'd3;
                end
            end else if (div_state == 3'd3) begin
                if (div_rem >= PCT_DENOM) begin
                    div_rem  <= div_rem - PCT_DENOM;
                    bright_q <= bright_q + 1'b1;
                end else begin
                    if (clip_result >= ((bright_q > BRIGHT_GUARD_MAX) ?
                                        BRIGHT_GUARD_MAX : bright_q))
                        highlight_result <= clip_result;
                    else
                        highlight_result <= ((bright_q > BRIGHT_GUARD_MAX) ?
                                       BRIGHT_GUARD_MAX : bright_q);
                    // State 4 reuses the mean divider for the unfiltered ROI
                    // sum captured at frame end. The next frame may already
                    // be accumulating, so its live sum must not be used here.
                    div_rem   <= roi_div_start;
                    div_den   <= ROI_GREEN_PIXELS;
                    div_q     <= 11'd0;
                    div_state <= 3'd4;
                end
            end else if (div_state == 3'd4) begin
                if (div_rem >= div_den) begin
                    div_rem <= div_rem - div_den;
                    div_q   <= div_q + 1'b1;
                end else begin
                    // Publish every sideband from one complete valid frame
                    // together. Consumers capture the stable bus via toggle.
                    O_avg_luma <= avg_result;
                    O_clip_pct <= highlight_result;
                    O_roi_all  <= {1'b0, div_q[9:2]};
                    O_frame_tgl <= ~O_frame_tgl;
                    div_state   <= 3'd0;
                end
            end

            if (sof_fire) begin
                frame_started   <= 1'b1;
                frame_bad       <= 1'b0;
                row_parity      <= 1'b0;
                line_count      <= 16'd0;
                beat_count      <= 16'd0;
                weighted_sum    <= weighted_beat;
                weight_sum      <= weight_beat;
                green_sum_all   <= green_beat_all;
                clip_count      <= clip_beat;
                bright_count    <= bright_beat;
                if (BEATS_PER_LINE == 1) begin
                    if (!I_tlast || (IMG_HEIGHT != 1)) begin
                        frame_bad  <= 1'b1;
                        beat_count <= 16'd1;
                    end else begin
                        div_den <= (weight_beat != 0) ? weight_beat : ROI_GREEN_PIXELS;
                        div_rem <= (weight_beat != 0) ? weighted_beat : green_beat_all;
                        div_q <= 11'd0;
                        div_state <= 3'd1;
                        clip_div_start <= clip_beat;
                        bright_div_start <= bright_beat;
                        roi_div_start <= green_beat_all;
                        frame_started <= 1'b0;
                    end
                end else if (I_tlast) begin
                    frame_bad  <= 1'b1;
                    beat_count <= 16'd1;
                end else begin
                    beat_count <= 16'd1;
                end
            end else if (I_tvalid && frame_started) begin
                weighted_sum    <= weighted_sum_plus;
                weight_sum      <= weight_sum_plus;
                green_sum_all   <= green_all_plus;
                clip_count      <= clip_count_plus;
                bright_count    <= bright_count_plus;
                if (!shape_ok)
                    frame_bad <= 1'b1;

                if (I_tlast) begin
                    if (frame_end && (weight_sum_plus != 0 || ROI_GREEN_PIXELS != 0)) begin
                        div_den <= (weight_sum_plus != 0) ? weight_sum_plus : ROI_GREEN_PIXELS;
                        div_rem <= (weight_sum_plus != 0) ? weighted_sum_plus : green_all_plus;
                        div_q <= 11'd0;
                        div_state <= 3'd1;
                        frame_started <= 1'b0;
                        clip_q <= 9'd0;
                        clip_div_start <= clip_count_plus;
                        bright_div_start <= bright_count_plus;
                        roi_div_start <= green_all_plus;
                    end else begin
                        line_count <= line_count + 1'b1;
                        beat_count <= 16'd0;
                        row_parity <= ~row_parity;
                        if (line_count >= IMG_HEIGHT-1)
                            frame_bad <= 1'b1;
                    end
                end else begin
                    if (beat_last)
                        frame_bad <= 1'b1;
                    beat_count <= beat_count + 1'b1;
                end
            end
        end
    end
endmodule
