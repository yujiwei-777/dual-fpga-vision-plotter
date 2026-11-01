// Resource-bounded ROI rule classifier.  The streaming interface is retained
// for compatibility, but classification is deterministic and uses only colour
// moments plus occupancy.  Shape IDs are TRI=1, CIRC=2, SQR=3 and class IDs
// are colour-major: RED 1..3, GREEN 4..6, BLUE 7..9; 0 means NONE.
module tiny_cnn_6class #(
    parameter integer PIXELS = 1024,
    parameter [7:0] MIN_CONF = 8'd55
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_enable,
    input  wire        I_valid,
    input  wire        I_start,
    input  wire        I_last,
    input  wire [23:0] I_data,
    output reg         O_busy,
    output reg         O_done,
    output reg  [3:0]  O_class_id,
    output reg  [7:0]  O_confidence,
    output reg         O_result_toggle
);
    reg [10:0] count;
    reg [31:0] sum_r,sum_g,sum_b;
    reg [15:0] active_count;
    reg [31:0] score_r,score_g,score_b;
    reg [31:0] best_score,second_score;
    reg [3:0] best_class;
    reg [31:0] margin;
    reg [7:0] conf_calc;
    reg [31:0] sumr_work,sumg_work,sumb_work;
    reg [15:0] active_work;
    reg [3:0] shape_class;
    wire [7:0] r=I_data[23:16], g=I_data[15:8], b=I_data[7:0];
    wire active = (r>8'd32)||(g>8'd32)||(b>8'd32);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            count<=0; sum_r<=0; sum_g<=0; sum_b<=0; active_count<=0;
            score_r<=0; score_g<=0; score_b<=0; best_score<=0; second_score<=0;
            best_class<=0; margin<=0; conf_calc<=0;
            O_busy<=0; O_done<=0; O_class_id<=0; O_confidence<=0; O_result_toggle<=0;
        end else begin
            O_done <= 1'b0;
            if (I_start && I_enable) begin
                O_busy<=1'b1; count<=0; sum_r<=0; sum_g<=0; sum_b<=0; active_count<=0;
            end
            // Accept the first ROI pixel on the same cycle as I_start.  This
            // avoids dropping pixel 0 when roi_sampler asserts start+valid.
            if (I_valid && (O_busy || (I_start && I_enable))) begin
                sumr_work = (I_start && I_enable) ? {24'd0,r} : (sum_r + r);
                sumg_work = (I_start && I_enable) ? {24'd0,g} : (sum_g + g);
                sumb_work = (I_start && I_enable) ? {24'd0,b} : (sum_b + b);
                active_work = (I_start && I_enable) ? (active ? 16'd1 : 16'd0) : (active_count + (active ? 1'b1 : 1'b0));
                sum_r <= sumr_work; sum_g <= sumg_work; sum_b <= sumb_work;
                active_count <= active_work;
                count <= count + 1'b1;
                if (I_last || count == PIXELS-1) begin
                    // Dominant-channel energy picks the colour.  Occupancy
                    // maps to the same relaxed geometric classes as the live
                    // target detector: sparse TRI, medium CIRC, dense SQR.
                    score_r = sumr_work; score_g = sumg_work; score_b = sumb_work;
                    if (active_work >= ((PIXELS*7)/8)) shape_class=4'd3;
                    else if (active_work >= ((PIXELS*4)/8)) shape_class=4'd2;
                    else shape_class=4'd1;
                    if ((score_r>=score_g)&&(score_r>=score_b)) begin best_score=score_r; best_class=shape_class; second_score=(score_g>=score_b)?score_g:score_b; end
                    else if (score_g>=score_b) begin best_score=score_g; best_class=shape_class+4'd3; second_score=(score_r>=score_b)?score_r:score_b; end
                    else begin best_score=score_b; best_class=shape_class+4'd6; second_score=(score_r>=score_g)?score_r:score_g; end
                    margin = (best_score>second_score)?(best_score-second_score):0;
                    conf_calc = (margin > 32'd65535) ? 8'd100 : (margin[15:8] > 8'd100 ? 8'd100 : margin[15:8]);
                    if (!I_enable || conf_calc < MIN_CONF) begin O_class_id<=0; O_confidence<=conf_calc; end
                    else begin O_class_id<=best_class; O_confidence<=conf_calc; end
                    O_done<=1'b1; O_result_toggle<=~O_result_toggle; O_busy<=1'b0;
                end
            end
        end
    end
endmodule
