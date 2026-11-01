// Low-resource 2x2 neutral-block AWB for the SC500CS BGGR RAW10 stream.
//
// The stream is four 10-bit pixels per beat.  For BGGR, an even row is
// B,Gr,B,Gr and the following odd row is Gb,R,Gb,R.  One line of the even
// row is retained at a fixed horizontal sampling phase; when the odd row
// arrives each sampled beat yields two complete 2x2 blocks.  Only neutral,
// mid-level blocks in the central image window contribute to the frame
// estimate.  The pixel path remains RAW10 and is protected by a one-entry
// elastic AXI stream register.
`timescale 1ns/1ps

module awb_raw10_bggr_neutral2x2 #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer PIX_PER_BEAT = 4,
    parameter integer ROI_X0 = 160,
    parameter integer ROI_X1 = 1120,
    parameter integer ROI_Y0 = 90,
    parameter integer ROI_Y1 = 630,
    parameter integer DARK_MIN = 32,
    parameter integer SAT_MAX = 1000,
    parameter integer MIN_BLOCKS = 128,
    // Keep one sampled beat every eight beats.  This is enough to provide
    // more than 128 neutral blocks in the central 960x540 window while
    // reducing the Bayer row store from 640 to 80 entries.
    parameter integer STAT_DECIM = 8,
    parameter [19:0] AWB_STEP = 20'h00200
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
    localparam integer SAMPLE_BEATS = (BEATS_PER_LINE + STAT_DECIM - 1) / STAT_DECIM;
    localparam integer BEAT_W = (BEATS_PER_LINE <= 2) ? 1 : $clog2(BEATS_PER_LINE);
    localparam integer SLOT_W = (SAMPLE_BEATS <= 2) ? 1 : $clog2(SAMPLE_BEATS);
    localparam integer ROW_W = (IMG_HEIGHT <= 2) ? 1 : $clog2(IMG_HEIGHT);
    localparam [19:0] GAIN_ONE = 20'h10000;
    localparam [19:0] GAIN_MIN = 20'h0c000; // 0.75
    localparam [19:0] GAIN_MAX = 20'h18000; // 1.50

    reg valid_r, user_r, last_r;
    reg [39:0] data_r;
    // Stage one registers the RAW beat and its frame phase.  The gain
    // multiply then runs in the following cycle, separating gain state
    // from the output timing endpoint.
    reg stage1_valid_r, stage1_user_r, stage1_last_r, stage1_row_r;
    reg [39:0] stage1_data_r;
    reg [19:0] stage1_gain_r, stage1_gain_b;
    reg row_parity_r;
    reg [ROW_W-1:0] row_idx_r;
    reg [BEAT_W-1:0] beat_idx_r;
    reg frame_bad_r;
    // Keep the sampled even row in block RAM; inferring flip-flops here
    // consumes the last routing margin of the 35P device.
    (* ram_style = "block", ramstyle = "block" *) reg [39:0] even_row_mem [0:SAMPLE_BEATS-1];

    reg [31:0] sum_r, sum_g, sum_b;
    reg [19:0] block_count;
    reg [19:0] gain_r, gain_b;
    // Gain estimates are prepared at frame end and committed at SOF.
    // This keeps the long frame-stat comparator away from the pixel
    // gain registers and avoids a sum*gain multiplier cone.
    reg [19:0] pending_gain_r, pending_gain_b;

    wire in_fire = I_tvalid && I_tready;
    wire row_for_input = I_tuser ? 1'b0 : row_parity_r;
    wire [ROW_W-1:0] row_for_input_idx = I_tuser ? {ROW_W{1'b0}} : row_idx_r;
    wire [BEAT_W-1:0] beat_for_input = I_tuser ? {BEAT_W{1'b0}} : beat_idx_r;
    wire beat_shape_ok = (I_tlast == (beat_for_input == BEATS_PER_LINE-1));
    wire beat_is_sample = ((beat_for_input % STAT_DECIM) == 0);
    wire [SLOT_W-1:0] sample_slot = beat_for_input / STAT_DECIM;

    wire [9:0] p0 = I_tdata[9:0];
    wire [9:0] p1 = I_tdata[19:10];
    wire [9:0] p2 = I_tdata[29:20];
    wire [9:0] p3 = I_tdata[39:30];

    function [10:0] absdiff10;
        input [9:0] a;
        input [9:0] b;
        begin
            absdiff10 = (a >= b) ? ({1'b0,a} - {1'b0,b}) :
                                    ({1'b0,b} - {1'b0,a});
        end
    endfunction

    function [9:0] gain_pixel;
        input [9:0] pixel;
        input [19:0] gain;
        reg [29:0] product;
        reg [29:0] scaled;
        begin
            product = pixel * gain;
            scaled = (product + 30'd32768) >> 16;
            gain_pixel = (scaled > 30'd1023) ? 10'd1023 : scaled[9:0];
        end
    endfunction

    wire [39:0] even_word = even_row_mem[sample_slot];
    wire [9:0] eb0 = even_word[9:0];
    wire [9:0] eg0 = even_word[19:10];
    wire [9:0] eb1 = even_word[29:20];
    wire [9:0] eg1 = even_word[39:30];
    wire [10:0] g0_sum = {1'b0,eg0} + {1'b0,p0};
    wire [10:0] g1_sum = {1'b0,eg1} + {1'b0,p2};
    wire [9:0] g0 = g0_sum[10:1];
    wire [9:0] g1 = g1_sum[10:1];
    wire [10:0] g0_q2 = {3'd0,g0[9:2]};
    wire [10:0] g0_q4 = {5'd0,g0[9:4]};
    wire [10:0] g1_q2 = {3'd0,g1[9:2]};
    wire [10:0] g1_q4 = {5'd0,g1[9:4]};
    wire [10:0] bg0_raw = g0_q2 + g0_q4;
    wire [10:0] bg1_raw = g1_q2 + g1_q4;
    wire [10:0] lim_rg0 = (g0_q2 > 11'd16) ? g0_q2 : 11'd16;
    wire [10:0] lim_bg0 = (bg0_raw > 11'd16) ? bg0_raw : 11'd16;
    wire [10:0] lim_rg1 = (g1_q2 > 11'd16) ? g1_q2 : 11'd16;
    wire [10:0] lim_bg1 = (bg1_raw > 11'd16) ? bg1_raw : 11'd16;
    wire [10:0] x_base = beat_for_input * 11'd4;
    wire [10:0] block_y = row_for_input_idx - 1'b1;

    wire pair0_window = row_for_input && beat_is_sample && (row_for_input_idx != 0) &&
                         (x_base >= ROI_X0) && (x_base < ROI_X1) &&
                         (block_y >= ROI_Y0) && (block_y < ROI_Y1);
    wire pair1_window = row_for_input && beat_is_sample && (row_for_input_idx != 0) &&
                         ((x_base + 11'd2) >= ROI_X0) &&
                         ((x_base + 11'd2) < ROI_X1) &&
                         (block_y >= ROI_Y0) && (block_y < ROI_Y1);
    wire pair0_ok = pair0_window && (g0 >= DARK_MIN) && (g0 < SAT_MAX) &&
                    (eb0 < SAT_MAX) && (p0 < SAT_MAX) && (p1 < SAT_MAX) &&
                    (absdiff10(p1,g0) <= lim_rg0) && (absdiff10(eb0,g0) <= lim_bg0);
    wire pair1_ok = pair1_window && (g1 >= DARK_MIN) && (g1 < SAT_MAX) &&
                    (eb1 < SAT_MAX) && (p2 < SAT_MAX) && (p3 < SAT_MAX) &&
                    (absdiff10(p3,g1) <= lim_rg1) && (absdiff10(eb1,g1) <= lim_bg1);
    wire [1:0] add_count = {1'b0,pair1_ok} + {1'b0,pair0_ok};
    wire [10:0] add_r_pair = (pair0_ok ? {1'b0,p1} : 11'd0) +
                                (pair1_ok ? {1'b0,p3} : 11'd0);
    wire [10:0] add_b_pair = (pair0_ok ? {1'b0,eb0} : 11'd0) +
                                (pair1_ok ? {1'b0,eb1} : 11'd0);
    wire [10:0] add_g_pair = (pair0_ok ? {1'b0,g0} : 11'd0) +
                                (pair1_ok ? {1'b0,g1} : 11'd0);
    wire [31:0] add_r = {21'd0,add_r_pair};
    wire [31:0] add_b = {21'd0,add_b_pair};
    wire [31:0] add_g = {21'd0,add_g_pair};
    wire [31:0] sum_r_eff = sum_r + {21'd0,add_r_pair};
    wire [31:0] sum_g_eff = sum_g + {21'd0,add_g_pair};
    wire [31:0] sum_b_eff = sum_b + {21'd0,add_b_pair};
    wire [20:0] count_eff = {1'b0,block_count} + add_count;
    wire frame_end = in_fire && I_tlast && beat_shape_ok && !frame_bad_r &&
                     ((IMG_HEIGHT == 1) ? I_tuser :
                      (row_for_input_idx == IMG_HEIGHT-1));
    // Each accepted 2x2 block contributes one R, one B and one G.
    // Compare unscaled means at frame end; the gain changes only by
    // AWB_STEP, so this direction-only estimator removes 32x20
    // multipliers from the MIPI clock path.
    wire [32:0] g_ref = {1'b0,sum_g_eff};
    // Compare coarse upper bits.  The AWB update is only one step per
    // frame, so sub-percent precision is unnecessary and would add
    // a full-width carry chain to the MIPI clock.
    wire r_below_g = (sum_r_eff[31:7] < sum_g_eff[31:7]);
    wire b_below_g = (sum_b_eff[31:7] < sum_g_eff[31:7]);
    wire r_above_g = (sum_r_eff[31:7] > sum_g_eff[31:7]);
    wire b_above_g = (sum_b_eff[31:7] > sum_g_eff[31:7]);
    wire enough = (count_eff >= MIN_BLOCKS);

    // BGGR phase: even rows are B/Gr, odd rows are Gb/R.  Stage one
    // captures the gain selected at SOF; stage two performs the four
    // pixel multiplies from registered operands.
    wire [9:0] s1_p0 = stage1_data_r[9:0];
    wire [9:0] s1_p1 = stage1_data_r[19:10];
    wire [9:0] s1_p2 = stage1_data_r[29:20];
    wire [9:0] s1_p3 = stage1_data_r[39:30];
    wire [9:0] q0 = stage1_row_r ? gain_pixel(s1_p0, GAIN_ONE) : gain_pixel(s1_p0, stage1_gain_b);
    wire [9:0] q1 = stage1_row_r ? gain_pixel(s1_p1, stage1_gain_r) : gain_pixel(s1_p1, GAIN_ONE);
    wire [9:0] q2 = stage1_row_r ? gain_pixel(s1_p2, GAIN_ONE) : gain_pixel(s1_p2, stage1_gain_b);
    wire [9:0] q3 = stage1_row_r ? gain_pixel(s1_p3, stage1_gain_r) : gain_pixel(s1_p3, GAIN_ONE);
    wire [39:0] scaled_word = {q3,q2,q1,q0};
    wire output_slot_ready = ~valid_r | O_tready;
    wire stage1_ready = ~stage1_valid_r | output_slot_ready;
    assign I_tready = stage1_ready;
    assign O_tvalid = valid_r;
    assign O_tuser = user_r;
    assign O_tlast = last_r;
    assign O_tdata = data_r;

    integer mi;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            valid_r <= 1'b0;
            user_r <= 1'b0;
            last_r <= 1'b0;
            data_r <= 40'd0;
            stage1_valid_r <= 1'b0;
            stage1_user_r <= 1'b0;
            stage1_last_r <= 1'b0;
            stage1_row_r <= 1'b0;
            stage1_data_r <= 40'd0;
            stage1_gain_r <= GAIN_ONE;
            stage1_gain_b <= GAIN_ONE;
            row_parity_r <= 1'b0;
            row_idx_r <= {ROW_W{1'b0}};
            beat_idx_r <= {BEAT_W{1'b0}};
            frame_bad_r <= 1'b0;
            sum_r <= 32'd0;
            sum_g <= 32'd0;
            sum_b <= 32'd0;
            block_count <= 20'd0;
            gain_r <= GAIN_ONE;
            gain_b <= GAIN_ONE;
            pending_gain_r <= GAIN_ONE;
            pending_gain_b <= GAIN_ONE;
        end else begin
            // Move stage one to the output whenever the output slot is
            // free or accepted.  Stage one and output can advance in
            // the same cycle for a continuous stream.
            if (output_slot_ready) begin
                valid_r <= stage1_valid_r;
                if (stage1_valid_r) begin
                    user_r <= stage1_user_r;
                    last_r <= stage1_last_r;
                    data_r <= scaled_word;
                end
            end
            if (stage1_ready) begin
                stage1_valid_r <= I_tvalid;
                if (I_tvalid) begin
                    stage1_user_r <= I_tuser;
                    stage1_last_r <= I_tlast;
                    stage1_row_r <= row_for_input;
                    stage1_data_r <= I_tdata;
                    stage1_gain_r <= I_tuser ? pending_gain_r : gain_r;
                    stage1_gain_b <= I_tuser ? pending_gain_b : gain_b;
                end
            end
            if (in_fire) begin
                if (I_tuser)
                    frame_bad_r <= !beat_shape_ok;
                else if (!beat_shape_ok)
                    frame_bad_r <= 1'b1;
                if (frame_end)
                    frame_bad_r <= 1'b0;
                if (!row_for_input && beat_is_sample)
                    even_row_mem[sample_slot] <= I_tdata;

                if (I_tuser) begin
                    row_idx_r <= (I_tlast && (IMG_HEIGHT > 1)) ? {{(ROW_W-1){1'b0}},1'b1} : {ROW_W{1'b0}};
                    row_parity_r <= (I_tlast && (IMG_HEIGHT > 1));
                    beat_idx_r <= (BEATS_PER_LINE <= 1) ? {BEAT_W{1'b0}} :
                                  {{(BEAT_W-1){1'b0}},1'b1};
                    // The previous frame estimate is committed at SOF.
                    gain_r <= pending_gain_r;
                    gain_b <= pending_gain_b;
                    sum_r <= add_r;
                    sum_g <= add_g;
                    sum_b <= add_b;
                    block_count <= add_count;
                end else if (frame_end) begin
                    sum_r <= 32'd0;
                    sum_g <= 32'd0;
                    sum_b <= 32'd0;
                    block_count <= 20'd0;
                    row_idx_r <= {ROW_W{1'b0}};
                    row_parity_r <= 1'b0;
                    beat_idx_r <= {BEAT_W{1'b0}};
                end else begin
                    sum_r <= sum_r_eff;
                    sum_g <= sum_g_eff;
                    sum_b <= sum_b_eff;
                    block_count <= count_eff[19:0];
                    if (I_tlast) begin
                        row_idx_r <= row_idx_r + 1'b1;
                        row_parity_r <= ~row_parity_r;
                        beat_idx_r <= {BEAT_W{1'b0}};
                    end else begin
                        beat_idx_r <= beat_idx_r + 1'b1;
                    end
                end

                if (frame_end && enough && (sum_g_eff != 0)) begin
                    if (r_below_g)
                        pending_gain_r <= (gain_r <= GAIN_MAX-AWB_STEP) ? gain_r + AWB_STEP : GAIN_MAX;
                    else if (r_above_g)
                        pending_gain_r <= (gain_r >= GAIN_MIN+AWB_STEP) ? gain_r - AWB_STEP : GAIN_MIN;
                    if (b_below_g)
                        pending_gain_b <= (gain_b <= GAIN_MAX-AWB_STEP) ? gain_b + AWB_STEP : GAIN_MAX;
                    else if (b_above_g)
                        pending_gain_b <= (gain_b >= GAIN_MIN+AWB_STEP) ? gain_b - AWB_STEP : GAIN_MIN;
                end
            end
        end
    end
endmodule
