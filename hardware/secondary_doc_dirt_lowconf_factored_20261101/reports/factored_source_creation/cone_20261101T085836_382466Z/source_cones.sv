`timescale 1ns/1ps
module abstract_parent #(
 parameter integer CNN_LOWCONF_OUTPUT=0,
 parameter integer COLOR_MARGIN_MIN=0,
 parameter integer TRIANGLE_MARGIN_MIN=31,
 parameter integer CIRCLE_MARGIN_MIN=28,
 parameter integer SQUARE_MARGIN_MIN=77
)(input clk, rst_n, seed, enable,
 input shape_reject_saved, low_samples, color_below, shape_below,
 input [7:0] minimum_cnn_margin,
 input [7:0] flags_seed,
 output reg [7:0] confidence_margin, multi_flags);

always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin confidence_margin<=0; multi_flags<=0; end
 else if(seed) begin confidence_margin<=8'hA7; multi_flags<=flags_seed; end
 else if(enable) begin
                        if(shape_reject_saved || low_samples || color_below ||
                           shape_below)begin
                            multi_flags[6]<=1'b1;
                            confidence_margin<=((CNN_LOWCONF_OUTPUT != 0) &&
                                !shape_reject_saved && !low_samples) ?
                                minimum_cnn_margin : 8'd0;
                        end else confidence_margin<=minimum_cnn_margin;
 end
end
endmodule

module abstract_factored #(
 parameter integer CNN_LOWCONF_OUTPUT=0,
 parameter integer COLOR_MARGIN_MIN=0,
 parameter integer TRIANGLE_MARGIN_MIN=31,
 parameter integer CIRCLE_MARGIN_MIN=28,
 parameter integer SQUARE_MARGIN_MIN=77
)(input clk, rst_n, seed, enable,
 input shape_reject_saved, low_samples, color_below, shape_below,
 input [7:0] minimum_cnn_margin,
 input [7:0] flags_seed,
 output reg [7:0] confidence_margin, multi_flags);
    // Separate hard eligibility from the unchanged soft-margin diagnostic.
    wire cnn_hard_reject=shape_reject_saved || low_samples;
    wire cnn_soft_reject=color_below ||
        shape_below;

always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin confidence_margin<=0; multi_flags<=0; end
 else if(seed) begin confidence_margin<=8'hA7; multi_flags<=flags_seed; end
 else if(enable) begin
                        if(cnn_hard_reject || cnn_soft_reject)
                            multi_flags[6]<=1'b1;
                        if(CNN_LOWCONF_OUTPUT != 0)
                            confidence_margin<=cnn_hard_reject ? 8'd0 : minimum_cnn_margin;
                        else
                            confidence_margin<=(cnn_hard_reject || cnn_soft_reject) ?
                                8'd0 : minimum_cnn_margin;
 end
end
endmodule

module numeric_parent #(
 parameter integer CNN_LOWCONF_OUTPUT=0,
 parameter integer COLOR_MARGIN_MIN=0,
 parameter integer TRIANGLE_MARGIN_MIN=31,
 parameter integer CIRCLE_MARGIN_MIN=28,
 parameter integer SQUARE_MARGIN_MIN=77
)(input clk, rst_n, seed, enable,
 input shape_reject_saved,
 input [19:0] color_samples_saved,
 input [1:0] shape_saved,
 input [7:0] color_margin_saved, shape_margin_saved,
 input [7:0] flags_seed,
 output reg [7:0] confidence_margin, multi_flags);
    wire [7:0] minimum_cnn_margin=(color_margin_saved<shape_margin_saved) ? color_margin_saved : shape_margin_saved;
    // cnn_core emits one-based shape IDs: 1=triangle, 2=cylinder, 3=cube.
    // Threshold lookup must use that same protocol domain.
    wire [7:0] selected_shape_threshold=(shape_saved==1) ? TRIANGLE_MARGIN_MIN :
        (shape_saved==2) ? CIRCLE_MARGIN_MIN : SQUARE_MARGIN_MIN;

always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin confidence_margin<=0; multi_flags<=0; end
 else if(seed) begin confidence_margin<=8'hA7; multi_flags<=flags_seed; end
 else if(enable) begin
                        if(shape_reject_saved || color_samples_saved<8 || color_margin_saved<COLOR_MARGIN_MIN ||
                           shape_margin_saved<selected_shape_threshold)begin
                            multi_flags[6]<=1'b1;
                            confidence_margin<=((CNN_LOWCONF_OUTPUT != 0) &&
                                !shape_reject_saved && color_samples_saved>=8) ?
                                minimum_cnn_margin : 8'd0;
                        end else confidence_margin<=minimum_cnn_margin;
 end
end
endmodule

module numeric_factored #(
 parameter integer CNN_LOWCONF_OUTPUT=0,
 parameter integer COLOR_MARGIN_MIN=0,
 parameter integer TRIANGLE_MARGIN_MIN=31,
 parameter integer CIRCLE_MARGIN_MIN=28,
 parameter integer SQUARE_MARGIN_MIN=77
)(input clk, rst_n, seed, enable,
 input shape_reject_saved,
 input [19:0] color_samples_saved,
 input [1:0] shape_saved,
 input [7:0] color_margin_saved, shape_margin_saved,
 input [7:0] flags_seed,
 output reg [7:0] confidence_margin, multi_flags);
    wire [7:0] minimum_cnn_margin=(color_margin_saved<shape_margin_saved) ? color_margin_saved : shape_margin_saved;
    // cnn_core emits one-based shape IDs: 1=triangle, 2=cylinder, 3=cube.
    // Threshold lookup must use that same protocol domain.
    wire [7:0] selected_shape_threshold=(shape_saved==1) ? TRIANGLE_MARGIN_MIN :
        (shape_saved==2) ? CIRCLE_MARGIN_MIN : SQUARE_MARGIN_MIN;
    // Separate hard eligibility from the unchanged soft-margin diagnostic.
    wire cnn_hard_reject=shape_reject_saved || color_samples_saved<8;
    wire cnn_soft_reject=color_margin_saved<COLOR_MARGIN_MIN ||
        shape_margin_saved<selected_shape_threshold;

always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin confidence_margin<=0; multi_flags<=0; end
 else if(seed) begin confidence_margin<=8'hA7; multi_flags<=flags_seed; end
 else if(enable) begin
                        if(cnn_hard_reject || cnn_soft_reject)
                            multi_flags[6]<=1'b1;
                        if(CNN_LOWCONF_OUTPUT != 0)
                            confidence_margin<=cnn_hard_reject ? 8'd0 : minimum_cnn_margin;
                        else
                            confidence_margin<=(cnn_hard_reject || cnn_soft_reject) ?
                                8'd0 : minimum_cnn_margin;
 end
end
endmodule
