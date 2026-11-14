// No-Type11-observation copy of frozen r3.
// Global AWB sampling, ratios, targets and pixel pipeline are unchanged.
// OBS_* parameters are retained only for source-interface compatibility.
// Four-lane BGGR RAW10 gray-world AWB.  All state is in I_clk/I_rst_n.
// A sampled even row stores B/Gr and the original pre-LSC saturation mask;
// the adjacent odd row contributes Gb/R.  Every accepted block contributes
// one R, one mean G and one B.  There is deliberately no chromaticity gate.
// The elastic pixel pipeline is independent of the EOF serial divider.
`timescale 1ns/1ps
module awb_raw10_bggr_grayworld #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer PIX_PER_BEAT = 4,
    parameter integer STAT_DECIM = 8,
    parameter integer DARK_MIN = 32,
    parameter integer MIN_BLOCKS = 128,
    parameter [19:0] AWB_STEP = 20'h00200,
    parameter [19:0] AWB_DEADBAND = 20'h00100,
    parameter integer OBS_X0 = 576,
    parameter integer OBS_X1 = 704,
    parameter integer OBS_Y0 = 296,
    parameter integer OBS_Y1 = 424
) (
    input wire I_clk,
    input wire I_rst_n,
    input wire I_tvalid,
    output wire I_tready,
    input wire I_tuser,
    input wire I_tlast,
    input wire [39:0] I_tdata,
    // Bit n accompanies lane n.  Generated before LSC at BLC64 >= 936.
    input wire [3:0] I_sat_mask,
    output wire O_tvalid,
    input wire O_tready,
    output wire O_tuser,
    output wire O_tlast,
    output wire [39:0] O_tdata,
    output wire [223:0] O_awb_diag
);
    localparam integer BEATS_PER_LINE = IMG_WIDTH / PIX_PER_BEAT;
    localparam integer SAMPLE_BEATS = (BEATS_PER_LINE+STAT_DECIM-1)/STAT_DECIM;
    localparam integer BEAT_W = (BEATS_PER_LINE <= 2) ? 1 : $clog2(BEATS_PER_LINE);
    localparam integer ROW_W = (IMG_HEIGHT <= 2) ? 1 : $clog2(IMG_HEIGHT);
    localparam integer SLOT_W = (SAMPLE_BEATS <= 2) ? 1 : $clog2(SAMPLE_BEATS);
    localparam [19:0] GAIN_ONE = 20'h10000;
    localparam [19:0] GAIN_MIN = 20'h0c000;
    localparam [19:0] GAIN_MAX = 20'h24000;
    // Complete, well-shaped frames have a provable finite sample budget.
    // A malformed frame stops accumulating, so this budget is also valid
    // under truncated lines, late EOLs and interrupted SOFs.
    localparam integer MAX_BLOCKS = SAMPLE_BEATS * 2 * (IMG_HEIGHT/2);
    localparam integer SUM_W = ($clog2(MAX_BLOCKS*1023+1) < 3) ?
                                3 : $clog2(MAX_BLOCKS*1023+1);
    localparam integer COUNT_W = (MAX_BLOCKS <= 1) ? 1 : $clog2(MAX_BLOCKS+1);
    localparam integer NUM_W = SUM_W+16;
    localparam integer REM_W = SUM_W+1;
    localparam integer DIV_LOW_W = (REM_W+1)/2;
    localparam integer DIV_HIGH_W = REM_W-DIV_LOW_W;
    // Preserve r1's EOF-to-pending publication deadline, including a SOF
    // that interrupts the shortened divider. This is control-only padding.
    localparam integer PUBLISH_PAD = (NUM_W<48)?4*(48-NUM_W):0;
    localparam integer PAD_W = (PUBLISH_PAD<=1)?1:$clog2(PUBLISH_PAD+1);
    // This compatibility port contains no observer state.
    assign O_awb_diag = 224'd0;

    reg valid_r, user_r, last_r;
    reg [39:0] data_r;
    reg stage1_valid_r, stage1_user_r, stage1_last_r, stage1_row_r;
    reg [39:0] stage1_data_r;
    reg [19:0] stage1_gain_r, stage1_gain_b;
    reg [19:0] stage1_color_gain;
    reg [19:0] gain_r, gain_b, pending_gain_r, pending_gain_b;
    reg [ROW_W-1:0] row_idx_r;
    reg [BEAT_W-1:0] beat_idx_r;
    reg row_parity_r, frame_started_r, frame_bad_r;
    (* ram_style = "block", ramstyle = "block" *)
    reg [43:0] even_row_mem [0:SAMPLE_BEATS-1];
    reg [SUM_W-1:0] sum_r, sum_g, sum_b;
    reg [COUNT_W-1:0] block_count;

    wire output_slot_ready = ~valid_r | O_tready;
    wire stage1_ready = ~stage1_valid_r | output_slot_ready;
    assign I_tready = stage1_ready;
    assign O_tvalid = valid_r;
    assign O_tdata = data_r;
    assign O_tuser = user_r;
    assign O_tlast = last_r;
    wire in_fire = I_tvalid && I_tready;
    wire row_for_input = I_tuser ? 1'b0 : row_parity_r;
    wire [ROW_W-1:0] row_for_input_idx = I_tuser ? {ROW_W{1'b0}} : row_idx_r;
    wire [BEAT_W-1:0] beat_for_input = I_tuser ? {BEAT_W{1'b0}} : beat_idx_r;
    wire beat_shape_ok = (I_tlast == (beat_for_input == BEATS_PER_LINE-1));
    wire beat_is_sample = ((beat_for_input % STAT_DECIM) == 0);
    wire [SLOT_W-1:0] sample_slot = beat_for_input / STAT_DECIM;
    wire current_frame_ok = (I_tuser || (frame_started_r && !frame_bad_r)) && beat_shape_ok;
    wire terminal_beat = in_fire && I_tlast && (row_for_input_idx == IMG_HEIGHT-1);
    wire frame_end = terminal_beat && current_frame_ok;

    wire [9:0] p0 = I_tdata[9:0];
    wire [9:0] p1 = I_tdata[19:10];
    wire [9:0] p2 = I_tdata[29:20];
    wire [9:0] p3 = I_tdata[39:30];
    wire [43:0] even_word = even_row_mem[sample_slot];
    wire [9:0] eb0 = even_word[9:0];
    wire [9:0] eg0 = even_word[19:10];
    wire [9:0] eb1 = even_word[29:20];
    wire [9:0] eg1 = even_word[39:30];
    wire [10:0] g0_sum = {1'b0,eg0} + {1'b0,p0};
    wire [10:0] g1_sum = {1'b0,eg1} + {1'b0,p2};
    wire [9:0] g0 = g0_sum[10:1];
    wire [9:0] g1 = g1_sum[10:1];
    wire pair_window = row_for_input && beat_is_sample &&
                       (row_for_input_idx != 0) && current_frame_ok;
    wire pair0_ok = pair_window && (g0 >= DARK_MIN) &&
                    !(|even_word[41:40]) && !(|I_sat_mask[1:0]);
    wire pair1_ok = pair_window && (g1 >= DARK_MIN) &&
                    !(|even_word[43:42]) && !(|I_sat_mask[3:2]);
    wire [1:0] add_count = {1'b0,pair0_ok} + {1'b0,pair1_ok};
    wire [10:0] add_r = (pair0_ok ? {1'b0,p1} : 11'd0) + (pair1_ok ? {1'b0,p3} : 11'd0);
    wire [10:0] add_g = (pair0_ok ? {1'b0,g0} : 11'd0) + (pair1_ok ? {1'b0,g1} : 11'd0);
    wire [10:0] add_b = (pair0_ok ? {1'b0,eb0} : 11'd0) + (pair1_ok ? {1'b0,eb1} : 11'd0);
    wire [SUM_W-1:0] sum_r_eff = sum_r + add_r;
    wire [SUM_W-1:0] sum_g_eff = sum_g + add_g;
    wire [SUM_W-1:0] sum_b_eff = sum_b + add_b;
    wire [COUNT_W:0] count_eff = {1'b0,block_count} + add_count;
    wire enough = count_eff >= MIN_BLOCKS;

    function [9:0] gain_pixel;
        input [9:0] pixel;
        input [19:0] gain;
        reg [29:0] product;
        reg [30:0] rounded;
        begin
            product = pixel * gain;
            rounded = {1'b0,product} + 31'd32768;
            gain_pixel = (rounded[30:16] > 15'd1023) ? 10'd1023 : rounded[25:16];
        end
    endfunction
    // Select the two colored lanes before multiplication.  Greens are
    // exact bypasses; synthesis needs two multipliers rather than four.
    wire [9:0] s1_p0 = stage1_data_r[9:0];
    wire [9:0] s1_p1 = stage1_data_r[19:10];
    wire [9:0] s1_p2 = stage1_data_r[29:20];
    wire [9:0] s1_p3 = stage1_data_r[39:30];
    wire [9:0] q_color0 = gain_pixel(stage1_row_r ? s1_p1 : s1_p0, stage1_color_gain);
    wire [9:0] q_color1 = gain_pixel(stage1_row_r ? s1_p3 : s1_p2, stage1_color_gain);
    wire [39:0] scaled_word = stage1_row_r ? {q_color1,s1_p2,q_color0,s1_p0} :
                                                            {s1_p3,q_color1,s1_p1,q_color0};

    // Shared restoring divider.  Each quotient bit uses two <=18-bit
    // subtraction stages.  No 32x20 multiply or combinational division
    // is inserted into the video path.  R/B results are published together.
    localparam [2:0] CALC_IDLE=3'd0, CALC_DIV_LO=3'd1, CALC_DIV_HI=3'd2,
                     CALC_FINISH=3'd3, CALC_UPDATE=3'd4, CALC_WAIT=3'd5;
    reg [2:0] calc_state;
    reg [PAD_W-1:0] publish_wait;
    reg calc_blue;
    reg [5:0] calc_bit;
    reg [NUM_W-1:0] calc_numerator;
    reg [19:0] calc_quotient;
    reg calc_quotient_overflow;
    reg [REM_W-1:0] calc_remainder;
    wire [SUM_W-1:0] calc_denominator = calc_blue ? sum_b : sum_r;
    reg calc_input_bit;
    // Remainder is unchanged across DIV_LO, so only its new bit
    // needs a register before DIV_HI reconstructs the trial.
    wire [REM_W-1:0] calc_trial = {calc_remainder[SUM_W-1:0],calc_input_bit};
    reg [DIV_LOW_W:0] calc_low_difference;
    reg [19:0] calc_target_r, calc_target_b;
    wire [REM_W-1:0] divide_trial = {calc_remainder[SUM_W-1:0],calc_numerator[NUM_W-1]};
    wire [DIV_HIGH_W:0] divide_hi_difference = {1'b0,calc_trial[REM_W-1:DIV_LOW_W]} -
                                        {2'b0,calc_denominator[SUM_W-1:DIV_LOW_W]} -
                                        {{DIV_HIGH_W{1'b0}},calc_low_difference[DIV_LOW_W]};
    wire [REM_W-1:0] denominator_half_ceil = {2'b0,calc_denominator[SUM_W-1:1]} +
                                       {{SUM_W{1'b0}},calc_denominator[0]};
    wire ratio_round = calc_remainder >= denominator_half_ceil;
    function [19:0] clip_ratio;
        input [19:0] quotient;
        input overflow;
        input round_up;
        reg [20:0] rounded;
        begin
            rounded = {1'b0,quotient[19:0]} + {{20{1'b0}},round_up};
            if (overflow || (rounded > {1'b0,GAIN_MAX})) clip_ratio = GAIN_MAX;
            else if (rounded < {1'b0,GAIN_MIN}) clip_ratio = GAIN_MIN;
            else clip_ratio = rounded[19:0];
        end
    endfunction
    function [19:0] slew_gain;
        input [19:0] base;
        input [19:0] target;
        reg [19:0] difference;
        begin
            if (target > base) begin
                difference = target-base;
                slew_gain = (difference <= AWB_DEADBAND) ? base :
                            ((difference > AWB_STEP) ? base+AWB_STEP : target);
            end else begin
                difference = base-target;
                slew_gain = (difference <= AWB_DEADBAND) ? base :
                            ((difference > AWB_STEP) ? base-AWB_STEP : target);
            end
        end
    endfunction
    // One physical slew cone serves R at B_FINISH and B at UPDATE.
    // The finished quotient is no longer needed after B_FINISH,
    // so it holds R's slew result through the publication padding.
    wire slew_select_blue = calc_state == CALC_UPDATE;
    wire [19:0] shared_slew_result = slew_gain(
        slew_select_blue ? gain_b : gain_r,
        slew_select_blue ? calc_target_b : calc_target_r);
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            pending_gain_r <= GAIN_ONE;
            pending_gain_b <= GAIN_ONE;
            calc_state <= CALC_IDLE;
            publish_wait <= {PAD_W{1'b0}};
            calc_blue <= 1'b0;
            calc_bit <= 6'd0;
            calc_numerator <= {NUM_W{1'b0}};
            calc_quotient <= 20'd0;
                    calc_quotient_overflow <= 1'b0;
            calc_remainder <= {REM_W{1'b0}};
            calc_input_bit <= 1'b0;
            calc_low_difference <= {(DIV_LOW_W+1){1'b0}};
            calc_target_r <= GAIN_ONE;
            calc_target_b <= GAIN_ONE;
        end else if (in_fire && I_tuser) begin
            // A result not ready before SOF cannot change this frame.
            calc_state <= CALC_IDLE;
        end else begin
            case (calc_state)
                CALC_IDLE: if (frame_end && enough && (sum_r_eff != 0) &&
                               (sum_b_eff != 0) && (sum_g_eff != 0)) begin
                    calc_numerator <= {sum_g_eff,16'd0};
                    calc_quotient <= 20'd0;
                    calc_quotient_overflow <= 1'b0;
                    calc_remainder <= {REM_W{1'b0}};
                    calc_blue <= 1'b0;
                    calc_bit <= 6'd0;
                    calc_state <= CALC_DIV_LO;
                end
                CALC_DIV_LO: begin
                    calc_input_bit <= calc_numerator[NUM_W-1];
                    calc_low_difference <= {1'b0,divide_trial[DIV_LOW_W-1:0]} -
                                           {1'b0,calc_denominator[DIV_LOW_W-1:0]};
                    calc_numerator <= {calc_numerator[NUM_W-2:0],1'b0};
                    calc_state <= CALC_DIV_HI;
                end
                CALC_DIV_HI: begin
                    if (divide_hi_difference[DIV_HIGH_W]) calc_remainder <= calc_trial;
                    else calc_remainder <= {divide_hi_difference[DIV_HIGH_W-1:0],calc_low_difference[DIV_LOW_W-1:0]};
                    calc_quotient <= {calc_quotient[18:0],!divide_hi_difference[DIV_HIGH_W]};
                    calc_quotient_overflow <= calc_quotient_overflow | calc_quotient[19];
                    if (calc_bit == NUM_W-1) calc_state <= CALC_FINISH;
                    else begin
                        calc_bit <= calc_bit + 1'b1;
                        calc_state <= CALC_DIV_LO;
                    end
                end
                CALC_FINISH: begin
                    if (!calc_blue) begin
                        calc_target_r <= clip_ratio(calc_quotient,calc_quotient_overflow,ratio_round);
                        calc_numerator <= {sum_g,16'd0};
                        calc_quotient <= 20'd0;
                    calc_quotient_overflow <= 1'b0;
                        calc_remainder <= {REM_W{1'b0}};
                        calc_bit <= 6'd0;
                        calc_blue <= 1'b1;
                        calc_state <= CALC_DIV_LO;
                    end else begin
                        calc_target_b <= clip_ratio(calc_quotient,calc_quotient_overflow,ratio_round);
                        calc_quotient <= shared_slew_result;
                        if (PUBLISH_PAD!=0) begin
                            publish_wait <= PUBLISH_PAD;
                            calc_state <= CALC_WAIT;
                        end else calc_state <= CALC_UPDATE;
                    end
                end
                CALC_WAIT: begin
                    if (publish_wait<=1) calc_state <= CALC_UPDATE;
                    else publish_wait <= publish_wait-1'b1;
                end
                CALC_UPDATE: begin
                    // R's slew result reuses the completed quotient scratch.
                    pending_gain_r <= calc_quotient;
                    pending_gain_b <= shared_slew_result;
                    calc_state <= CALC_IDLE;
                end
                default: calc_state <= CALC_IDLE;
            endcase
        end
    end

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
            stage1_color_gain <= GAIN_ONE;
            gain_r <= GAIN_ONE;
            gain_b <= GAIN_ONE;
            row_idx_r <= {ROW_W{1'b0}};
            row_parity_r <= 1'b0;
            beat_idx_r <= {BEAT_W{1'b0}};
            frame_started_r <= 1'b0;
            frame_bad_r <= 1'b0;
            sum_r <= {SUM_W{1'b0}};
            sum_g <= {SUM_W{1'b0}};
            sum_b <= {SUM_W{1'b0}};
            block_count <= {COUNT_W{1'b0}};
        end else begin
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
                    stage1_color_gain <= row_for_input ?
                        (I_tuser ? pending_gain_r : gain_r) :
                        (I_tuser ? pending_gain_b : gain_b);
                end
            end
            if (in_fire) begin
                if (!row_for_input && beat_is_sample && current_frame_ok)
                    even_row_mem[sample_slot] <= {I_sat_mask,I_tdata};
                if (I_tuser) begin
                    gain_r <= pending_gain_r;
                    gain_b <= pending_gain_b;
                    frame_started_r <= 1'b1;
                    frame_bad_r <= !beat_shape_ok;
                    row_idx_r <= (I_tlast && IMG_HEIGHT > 1) ? {{(ROW_W-1){1'b0}},1'b1} : {ROW_W{1'b0}};
                    row_parity_r <= I_tlast && IMG_HEIGHT > 1;
                    beat_idx_r <= (I_tlast || BEATS_PER_LINE <= 1) ? {BEAT_W{1'b0}} : {{(BEAT_W-1){1'b0}},1'b1};
                    sum_r <= {SUM_W{1'b0}};
                    sum_g <= {SUM_W{1'b0}};
                    sum_b <= {SUM_W{1'b0}};
                    block_count <= {COUNT_W{1'b0}};
                end else begin
                    if (!beat_shape_ok) frame_bad_r <= 1'b1;
                    if (frame_started_r) begin
                        sum_r <= sum_r_eff;
                        sum_g <= sum_g_eff;
                        sum_b <= sum_b_eff;
                        block_count <= count_eff[COUNT_W-1:0];
                    end
                    if (I_tlast) begin
                        beat_idx_r <= {BEAT_W{1'b0}};
                        if (row_idx_r < IMG_HEIGHT-1) row_idx_r <= row_idx_r + 1'b1;
                        row_parity_r <= ~row_parity_r;
                    end else if (beat_idx_r < BEATS_PER_LINE-1) beat_idx_r <= beat_idx_r + 1'b1;
                end
                if (terminal_beat) begin
                    frame_started_r <= 1'b0;
                    row_idx_r <= {ROW_W{1'b0}};
                    row_parity_r <= 1'b0;
                    beat_idx_r <= {BEAT_W{1'b0}};
                    // The non-SOF accumulation above captured this
                    // terminal beat's effective sums. Hold them for
                    // the second ratio instead of duplicating G/B.
                    // frame_started_r=0 prevents any further updates;
                    // the next SOF clears sums and aborts calculation.
                    block_count <= {COUNT_W{1'b0}};
                end
            end
        end
    end
endmodule
