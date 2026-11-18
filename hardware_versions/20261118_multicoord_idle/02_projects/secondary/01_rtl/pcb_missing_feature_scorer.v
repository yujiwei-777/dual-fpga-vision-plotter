`timescale 1ns/1ps
// Standalone v5 DETAIL feature-loss scorer; NOT a complete PCB classifier.
// Upstream must provide registered 192x96 contrast-neighborhood observations
// and frozen expected8 in row-major order. This module does NOT calculate
// registration, 7x7/3x3 contrast, neighborhood max, or a corner/geometry check.
// DETAIL_PASS means only that no supported feature loss exceeded threshold.
// I_start is a one-cycle pulse. I_last must accompany accepted sample 18431.
// Samples offered while !O_ready are not transfers and are ignored.
module pcb_missing_feature_scorer (
    input  wire               I_clk,
    input  wire               I_rst_n,
    input  wire               I_start,
    input  wire               I_cancel,
    input  wire [15:0]        I_threshold,
    input  wire               I_frame_valid,
    input  wire               I_registration_valid,
    input  wire               I_valid,
    output wire               O_ready,
    input  wire [7:0]         I_observed_contrast,
    input  wire [7:0]         I_expected_contrast,
    input  wire               I_last,
    output wire               O_busy,
    output reg                O_done,
    output reg                O_result_valid,
    output reg  [1:0]         O_status, // 0 DETAIL_PASS,1 DETAIL_FAIL,2 DETAIL_REVIEW
    output reg  [2:0]         O_error,  // 0 none,1 early last,2 missing last,3 busy start
    output reg  [11:0]        O_score,
    output reg  [10:0]        O_peak_tile,
    output reg  [22:0]        O_total_loss,
    output reg  [14:0]        O_changed_pixels,
    output reg  [14:0]        O_samples
);
    localparam IDLE=2'd0, SAMPLE=2'd1, ACCUMULATE=2'd2;
    reg [1:0] state;
    reg [15:0] threshold_saved;
    reg inputs_valid;
    reg [7:0] x;
    reg [6:0] y;
    reg [5:0] tile_column;
    reg [10:0] tile_row_base;
    // Only the current 4-row strip is retained: 48 x 12 = 576 bits.
    reg [11:0] tile_sum [0:47];
    reg [7:0] loss_saved;
    reg last_saved;
    reg [11:0] maximum;
    reg [10:0] peak;
    reg [22:0] total;
    reg [14:0] changed;
    reg [14:0] samples;

    // The producer supplies the frozen model observed() output: unsigned8
    // neighborhood maximum already clamped to 0..255. Negative contrast is
    // handled upstream. expected=0 is inactive and always produces zero loss.
    wire [7:0] loss = I_expected_contrast > I_observed_contrast ?
                      I_expected_contrast-I_observed_contrast : 8'd0;
    wire first_in_tile = (y[1:0]==0 && x[1:0]==0);
    wire final_in_tile = (y[1:0]==3 && x[1:0]==3);
    wire [11:0] accumulated = (first_in_tile ? 12'd0 : tile_sum[tile_column]) +
                              {4'd0,loss_saved};
    wire replace_maximum = final_in_tile && accumulated > maximum;
    wire [11:0] next_maximum = replace_maximum ? accumulated : maximum;
    wire [10:0] next_peak = replace_maximum ?
                           tile_row_base + {5'd0,tile_column} : peak;
    wire final_sample = (samples==15'd18431);
    assign O_ready = (state==SAMPLE) && !I_cancel && !I_start;
    assign O_busy = (state!=IDLE);

    // Never expose a partial score as a valid measurement after protocol error.
    // Consumers must inspect result_valid, status and error together.
    task finish_error;
        input [2:0] error_code;
        input [14:0] accepted_samples;
        begin
            state<=IDLE; O_done<=1'b1; O_result_valid<=1'b1;
            O_status<=2'd2; O_error<=error_code;
            O_score<=0; O_peak_tile<=0; O_total_loss<=0;
            O_changed_pixels<=0; O_samples<=accepted_samples;
        end
    endtask

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            state<=IDLE; threshold_saved<=0; inputs_valid<=0;
            x<=0; y<=0; tile_column<=0; tile_row_base<=0;
            loss_saved<=0; last_saved<=0; maximum<=0; peak<=0;
            total<=0; changed<=0; samples<=0;
            O_done<=0; O_result_valid<=0; O_status<=2'd2; O_error<=0;
            O_score<=0; O_peak_tile<=0; O_total_loss<=0;
            O_changed_pixels<=0; O_samples<=0;
            // No global tile-array reset: first pixel overwrites EVERY tile
            // slot before any earlier frame contents can affect its sum.
        end else begin
            O_done<=1'b0;
            if (I_cancel) begin
                state<=IDLE; O_result_valid<=0; O_status<=2'd2; O_error<=0;
                O_score<=0; O_peak_tile<=0; O_total_loss<=0;
                O_changed_pixels<=0; O_samples<=0;
            end else if (I_start && state!=IDLE) begin
                finish_error(3'd3,samples);
            end else if (I_start) begin
                state<=SAMPLE; threshold_saved<=I_threshold;
                inputs_valid<=I_frame_valid && I_registration_valid;
                x<=0; y<=0; tile_column<=0; tile_row_base<=0;
                maximum<=0; peak<=0; total<=0; changed<=0; samples<=0;
                O_result_valid<=0; O_status<=2'd2; O_error<=0;
                O_score<=0; O_peak_tile<=0; O_total_loss<=0;
                O_changed_pixels<=0; O_samples<=0;
            end else if (state==SAMPLE && I_valid) begin
                loss_saved<=loss; last_saved<=I_last;
                state<=ACCUMULATE;
            end else if (state==ACCUMULATE) begin
                if (last_saved && !final_sample) begin
                    finish_error(3'd1,samples+15'd1);
                end else if (final_sample && !last_saved) begin
                    finish_error(3'd2,samples+15'd1);
                end else begin
                    tile_sum[tile_column]<=accumulated;
                    maximum<=next_maximum; peak<=next_peak;
                    total<=total+{15'd0,loss_saved};
                    changed<=changed+(loss_saved!=0);
                    samples<=samples+15'd1;
                    if (final_sample) begin
                        state<=IDLE; O_done<=1'b1; O_result_valid<=1'b1;
                        O_status<=!inputs_valid ? 2'd2 :
                                  ({4'd0,next_maximum}>threshold_saved ? 2'd1 : 2'd0);
                        O_error<=0; O_score<=next_maximum; O_peak_tile<=next_peak;
                        O_total_loss<=total+{15'd0,loss_saved};
                        O_changed_pixels<=changed+(loss_saved!=0);
                        O_samples<=15'd18432;
                    end else begin
                        state<=SAMPLE;
                        if (x==8'd191) begin
                            x<=0; y<=y+7'd1; tile_column<=0;
                            if (y[1:0]==3) tile_row_base<=tile_row_base+11'd48;
                        end else begin
                            x<=x+8'd1;
                            if (x[1:0]==3) tile_column<=tile_column+6'd1;
                        end
                    end
                end
            end
        end
    end
endmodule
