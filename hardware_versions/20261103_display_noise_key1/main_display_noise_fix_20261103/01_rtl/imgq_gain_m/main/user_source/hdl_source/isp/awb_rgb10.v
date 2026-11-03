// RGB-domain AWB for a four-pixel-per-beat RGB10 stream.
//
// Lane packing is {R[9:0],G[9:0],B[9:0]} with lane 0 in bits [29:0],
// lane 1 in [59:30], lane 2 in [89:60], and lane 3 in [119:90].  The
// module intentionally keeps RGB10 throughout the data path.  It uses the
// same frame-boundary slew and 0.75..1.50 gain limits as the RAW AWB
// comparison, but performs neutral-pixel admission after demosaic.
`timescale 1ns/1ps

module awb_rgb10 #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer PIX_PER_BEAT = 4,
    parameter integer ROI_X0 = 160,
    parameter integer ROI_X1 = 1120,
    parameter integer ROI_Y0 = 90,
    parameter integer ROI_Y1 = 630,
    parameter integer DARK_MIN = 32,
    parameter integer SAT_MAX = 1000,
    parameter integer MIN_PIXELS = 128,
    parameter [19:0] AWB_STEP = 20'h00200
) (
    input  wire         I_clk,
    input  wire         I_rst_n,
    input  wire         I_tvalid,
    output wire         I_tready,
    input  wire         I_tuser,
    input  wire         I_tlast,
    input  wire [119:0] I_tdata,
    output wire         O_tvalid,
    input  wire         O_tready,
    output wire         O_tuser,
    output wire         O_tlast,
    output wire [119:0] O_tdata
);
    localparam integer BEATS_PER_LINE = IMG_WIDTH / PIX_PER_BEAT;
    localparam integer BEAT_W = (BEATS_PER_LINE <= 2) ? 1 : $clog2(BEATS_PER_LINE);
    localparam integer ROW_W = (IMG_HEIGHT <= 2) ? 1 : $clog2(IMG_HEIGHT);
    localparam [19:0] GAIN_ONE = 20'h10000;
    localparam [19:0] GAIN_MIN = 20'h0c000;
    localparam [19:0] GAIN_MAX = 20'h18000;

    reg valid_r, user_r, last_r;
    reg [119:0] data_r;
    reg [ROW_W-1:0] row_idx_r;
    reg [BEAT_W-1:0] beat_idx_r;
    reg frame_bad_r;
    reg [31:0] sum_r, sum_g, sum_b;
    reg [20:0] pixel_count;
    reg [19:0] gain_r, gain_b;

    wire in_fire = I_tvalid && I_tready;
    wire [ROW_W-1:0] row_for_input = I_tuser ? {ROW_W{1'b0}} : row_idx_r;
    wire [BEAT_W-1:0] beat_for_input = I_tuser ? {BEAT_W{1'b0}} : beat_idx_r;
    wire beat_shape_ok = (I_tlast == (beat_for_input == BEATS_PER_LINE-1));
    wire [11:0] x_base = beat_for_input * 12'd4;

    wire [9:0] r0 = I_tdata[29:20];
    wire [9:0] g0 = I_tdata[19:10];
    wire [9:0] b0 = I_tdata[9:0];
    wire [9:0] r1 = I_tdata[59:50];
    wire [9:0] g1 = I_tdata[49:40];
    wire [9:0] b1 = I_tdata[39:30];
    wire [9:0] r2 = I_tdata[89:80];
    wire [9:0] g2 = I_tdata[79:70];
    wire [9:0] b2 = I_tdata[69:60];
    wire [9:0] r3 = I_tdata[119:110];
    wire [9:0] g3 = I_tdata[109:100];
    wire [9:0] b3 = I_tdata[99:90];

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

    wire [10:0] lim0 = (g0[9:3] > 7'd10) ? {1'b0,g0[9:3]} : 11'd10;
    wire [10:0] lim1 = (g1[9:3] > 7'd10) ? {1'b0,g1[9:3]} : 11'd10;
    wire [10:0] lim2 = (g2[9:3] > 7'd10) ? {1'b0,g2[9:3]} : 11'd10;
    wire [10:0] lim3 = (g3[9:3] > 7'd10) ? {1'b0,g3[9:3]} : 11'd10;
    wire roi_y = (row_for_input >= ROI_Y0) && (row_for_input < ROI_Y1);
    wire roi0 = roi_y && ((x_base + 12'd0) >= ROI_X0) && ((x_base + 12'd0) < ROI_X1);
    wire roi1 = roi_y && ((x_base + 12'd1) >= ROI_X0) && ((x_base + 12'd1) < ROI_X1);
    wire roi2 = roi_y && ((x_base + 12'd2) >= ROI_X0) && ((x_base + 12'd2) < ROI_X1);
    wire roi3 = roi_y && ((x_base + 12'd3) >= ROI_X0) && ((x_base + 12'd3) < ROI_X1);
    wire v0 = roi0 && (g0 >= DARK_MIN) && (g0 < SAT_MAX) && (r0 < SAT_MAX) && (b0 < SAT_MAX) &&
              (absdiff10(r0,g0) <= lim0) && (absdiff10(b0,g0) <= lim0);
    wire v1 = roi1 && (g1 >= DARK_MIN) && (g1 < SAT_MAX) && (r1 < SAT_MAX) && (b1 < SAT_MAX) &&
              (absdiff10(r1,g1) <= lim1) && (absdiff10(b1,g1) <= lim1);
    wire v2 = roi2 && (g2 >= DARK_MIN) && (g2 < SAT_MAX) && (r2 < SAT_MAX) && (b2 < SAT_MAX) &&
              (absdiff10(r2,g2) <= lim2) && (absdiff10(b2,g2) <= lim2);
    wire v3 = roi3 && (g3 >= DARK_MIN) && (g3 < SAT_MAX) && (r3 < SAT_MAX) && (b3 < SAT_MAX) &&
              (absdiff10(r3,g3) <= lim3) && (absdiff10(b3,g3) <= lim3);
    wire [2:0] add_count = {2'd0,v0} + {2'd0,v1} + {2'd0,v2} + {2'd0,v3};
    wire [31:0] add_r = (v0 ? r0 : 0) + (v1 ? r1 : 0) + (v2 ? r2 : 0) + (v3 ? r3 : 0);
    wire [31:0] add_g = (v0 ? g0 : 0) + (v1 ? g1 : 0) + (v2 ? g2 : 0) + (v3 ? g3 : 0);
    wire [31:0] add_b = (v0 ? b0 : 0) + (v1 ? b1 : 0) + (v2 ? b2 : 0) + (v3 ? b3 : 0);
    wire [31:0] sum_r_eff = sum_r + add_r;
    wire [31:0] sum_g_eff = sum_g + add_g;
    wire [31:0] sum_b_eff = sum_b + add_b;
    wire [21:0] count_eff = {1'b0,pixel_count} + add_count;
    wire frame_end = in_fire && I_tlast && beat_shape_ok && !frame_bad_r &&
                     ((IMG_HEIGHT == 1) ? I_tuser : (row_for_input == IMG_HEIGHT-1));
    wire [32:0] g_ref = {1'b0,sum_g_eff};
    wire [51:0] r_track = sum_r_eff * gain_r;
    wire [51:0] b_track = sum_b_eff * gain_b;
    wire [32:0] r_track_q = r_track >> 16;
    wire [32:0] b_track_q = b_track >> 16;
    wire [32:0] deadband = g_ref >> 7;
    wire enough = (count_eff >= MIN_PIXELS);

    wire [9:0] q0r = gain_pixel(r0,gain_r);
    wire [9:0] q1r = gain_pixel(r1,gain_r);
    wire [9:0] q2r = gain_pixel(r2,gain_r);
    wire [9:0] q3r = gain_pixel(r3,gain_r);
    wire [9:0] q0b = gain_pixel(b0,gain_b);
    wire [9:0] q1b = gain_pixel(b1,gain_b);
    wire [9:0] q2b = gain_pixel(b2,gain_b);
    wire [9:0] q3b = gain_pixel(b3,gain_b);
    wire [119:0] scaled_word = {q3r,g3,q3b,q2r,g2,q2b,q1r,g1,q1b,q0r,g0,q0b};

    assign I_tready = ~valid_r | O_tready;
    assign O_tvalid = valid_r;
    assign O_tuser = user_r;
    assign O_tlast = last_r;
    assign O_tdata = data_r;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            valid_r <= 1'b0;
            user_r <= 1'b0;
            last_r <= 1'b0;
            data_r <= 120'd0;
            row_idx_r <= {ROW_W{1'b0}};
            beat_idx_r <= {BEAT_W{1'b0}};
            frame_bad_r <= 1'b0;
            sum_r <= 32'd0;
            sum_g <= 32'd0;
            sum_b <= 32'd0;
            pixel_count <= 21'd0;
            gain_r <= GAIN_ONE;
            gain_b <= GAIN_ONE;
        end else begin
            if (I_tready) begin
                valid_r <= I_tvalid;
                if (I_tvalid) begin
                    user_r <= I_tuser;
                    last_r <= I_tlast;
                    data_r <= scaled_word;
                end
            end
            if (in_fire) begin
                if (I_tuser)
                    frame_bad_r <= !beat_shape_ok;
                else if (!beat_shape_ok)
                    frame_bad_r <= 1'b1;
                if (frame_end)
                    frame_bad_r <= 1'b0;
                if (I_tuser) begin
                    row_idx_r <= (I_tlast && (IMG_HEIGHT > 1)) ? {{(ROW_W-1){1'b0}},1'b1} : {ROW_W{1'b0}};
                    beat_idx_r <= {BEAT_W{1'b0}};
                    sum_r <= add_r;
                    sum_g <= add_g;
                    sum_b <= add_b;
                    pixel_count <= add_count;
                end else if (frame_end) begin
                    row_idx_r <= {ROW_W{1'b0}};
                    beat_idx_r <= {BEAT_W{1'b0}};
                    sum_r <= 32'd0;
                    sum_g <= 32'd0;
                    sum_b <= 32'd0;
                    pixel_count <= 21'd0;
                end else begin
                    sum_r <= sum_r_eff;
                    sum_g <= sum_g_eff;
                    sum_b <= sum_b_eff;
                    pixel_count <= count_eff[20:0];
                    if (I_tlast) begin
                        row_idx_r <= row_idx_r + 1'b1;
                        beat_idx_r <= {BEAT_W{1'b0}};
                    end else begin
                        beat_idx_r <= beat_idx_r + 1'b1;
                    end
                end

                if (frame_end && enough && (sum_g_eff != 0)) begin
                    if (r_track_q + deadband < g_ref)
                        gain_r <= (gain_r <= GAIN_MAX-AWB_STEP) ? gain_r + AWB_STEP : GAIN_MAX;
                    else if (r_track_q > g_ref + deadband)
                        gain_r <= (gain_r >= GAIN_MIN+AWB_STEP) ? gain_r - AWB_STEP : GAIN_MIN;
                    if (b_track_q + deadband < g_ref)
                        gain_b <= (gain_b <= GAIN_MAX-AWB_STEP) ? gain_b + AWB_STEP : GAIN_MAX;
                    else if (b_track_q > g_ref + deadband)
                        gain_b <= (gain_b >= GAIN_MIN+AWB_STEP) ? gain_b - AWB_STEP : GAIN_MIN;
                end
            end
        end
    end
endmodule
