// Resource-safe local rule classifier.  The colour detector supplies the
// measured occupancy class (TRI=1, CIRC=2, SQR=3) and area.  This module keeps
// the historical CNN result interface so the rest of the HDMI/network path
// remains unchanged, but it does no convolution and allocates no frame RAM.
// class_id: 1..9 = RED/GREEN/BLUE x TRI/CIRC/SQR, 0 = NONE.
module cnn_feature_classifier (
    input wire I_clk, input wire I_rst_n, input wire I_enable,
    input wire I_frame_toggle, input wire I_target_valid,
    input wire [1:0] I_color, input wire [1:0] I_shape,
    input wire [23:0] I_area,
    output reg [3:0] O_class_id, output reg [7:0] O_confidence,
    output reg [3:0] O_conf_tens, output reg [3:0] O_conf_ones,
    output reg O_valid, output reg O_result_toggle
);
    reg toggle_d;
    reg [31:0] area_score;
    reg [3:0] class_calc;
    reg [7:0] conf_calc;
    always @(posedge I_clk or negedge I_rst_n) begin
      if(!I_rst_n) begin
        toggle_d<=1'b0; O_class_id<=4'd0; O_confidence<=8'd0;
        O_conf_tens<=4'd0; O_conf_ones<=4'd0;
        O_valid<=1'b0; O_result_toggle<=1'b0;
      end else if(I_frame_toggle != toggle_d) begin
        toggle_d <= I_frame_toggle;
        // The detector encoding is RED=1, GREEN=2, BLUE=3 and
        // TRI=1, CIRC=2, SQR=3.  Map directly to nine rule classes.
        if(I_enable && I_target_valid && (I_color>=2'd1) && (I_color<=2'd3) &&
           (I_shape>=2'd1) && (I_shape<=2'd3)) begin
          class_calc = ((({2'd0,I_color} - 4'd1) << 1) +
                        ({2'd0,I_color} - 4'd1)) + I_shape;
          area_score = I_area >> 10;
          conf_calc = (area_score >= 32'd45) ? 8'd100 : (8'd55 + area_score[7:0]);
          O_class_id <= class_calc;
          O_confidence <= conf_calc;
          O_conf_tens <= (conf_calc >= 8'd100) ? 4'd0 : (conf_calc / 10);
          O_conf_ones <= (conf_calc >= 8'd100) ? 4'd0 : (conf_calc % 10);
          O_valid <= (conf_calc >= 8'd55);
        end else begin
          O_class_id <= 4'd0; O_confidence <= 8'd0;
          O_conf_tens <= 4'd0; O_conf_ones <= 4'd0; O_valid <= 1'b0;
        end
        O_result_toggle <= ~O_result_toggle;
      end
    end
endmodule
