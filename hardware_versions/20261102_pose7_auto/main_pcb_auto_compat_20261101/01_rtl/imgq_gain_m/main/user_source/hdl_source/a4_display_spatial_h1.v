// HDMI display-only causal 2-tap spatial filter.
//
// The filter keeps the complete RGB8 range and averages the current pixel
// with the previous pixel on the same line. It needs no frame store or DDR
// read and does not alter the timing markers. This deliberately small filter
// keeps the display path within the baseline placement envelope; CNN/ROI
// input remains connected to the unfiltered source.
module a4_display_spatial_h1 #(
    parameter integer ENABLE = 1,
    parameter integer EDGE_TH = 24
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_vsync,
    input  wire        I_hsync,
    input  wire        I_de,
    input  wire        I_user,
    input  wire        I_last,
    input  wire [23:0] I_data,
    output wire        O_vsync,
    output wire        O_hsync,
    output wire        O_de,
    output wire        O_user,
    output wire        O_last,
    output wire [23:0] O_data
);
    reg [23:0] S_prev1;
    reg        S_line_valid;

    function [7:0] F_avg2;
        input [7:0] a;
        input [7:0] b;
        begin
            // Equivalent to round((a+b)/2), using a 7-bit adder per input.
            F_avg2 = {1'b0,a[7:1]} + {1'b0,b[7:1]} +
                     {7'd0,(a[0] | b[0])};
        end
    endfunction

    // One signed subtract per channel avoids the compare/two-subtract/mux
    // structure of an absolute-difference implementation.
    wire signed [8:0] S_delta_r = $signed({1'b0,S_prev1[23:16]}) -
                                  $signed({1'b0,I_data[23:16]});
    wire signed [8:0] S_delta_g = $signed({1'b0,S_prev1[15:8]}) -
                                  $signed({1'b0,I_data[15:8]});
    wire signed [8:0] S_delta_b = $signed({1'b0,S_prev1[7:0]}) -
                                  $signed({1'b0,I_data[7:0]});
    wire signed [8:0] S_edge_limit = EDGE_TH;
    wire S_edge_ok = (S_delta_r >= -S_edge_limit) && (S_delta_r <= S_edge_limit) &&
                     (S_delta_g >= -S_edge_limit) && (S_delta_g <= S_edge_limit) &&
                     (S_delta_b >= -S_edge_limit) && (S_delta_b <= S_edge_limit);
    wire S_use_filter = (ENABLE != 0) && I_de && !I_user && S_line_valid && S_edge_ok;
    wire [7:0] S_r = S_use_filter ? F_avg2(S_prev1[23:16], I_data[23:16]) : I_data[23:16];
    wire [7:0] S_g = S_use_filter ? F_avg2(S_prev1[15:8],  I_data[15:8])  : I_data[15:8];
    wire [7:0] S_b = S_use_filter ? F_avg2(S_prev1[7:0],   I_data[7:0])   : I_data[7:0];

    assign O_vsync = I_vsync;
    assign O_hsync = I_hsync;
    assign O_de    = I_de;
    assign O_user  = I_user;
    assign O_last  = I_last;
    assign O_data  = {S_r, S_g, S_b};

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            S_prev1      <= 24'd0;
            S_line_valid <= 1'b0;
        end else if (I_de) begin
            if (I_user) begin
                S_prev1      <= I_data;
                S_line_valid <= 1'b0;
            end else begin
                S_prev1 <= I_data;
                S_line_valid <= !I_last;
            end
        end
    end
endmodule
