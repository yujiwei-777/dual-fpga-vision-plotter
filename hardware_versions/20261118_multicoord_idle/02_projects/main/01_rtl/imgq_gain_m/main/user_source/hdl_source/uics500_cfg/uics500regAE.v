`timescale 1ns / 1ps

// SC500CS V1.8 tables2-3/2-5 and section2.3: manual AE/AG/DG.
// Group0 holds the complete command and applies it at the sensor frame
// boundary (0x3800=0x40, 0x3817[3:0]=0). O_ae_cfg_done only indicates
// I2C completion; AE waits ADJ_FRAMES before using another measurement.
module uics500regAE #(
    parameter integer DG_MAX_Q7 = 256
) (
    input wire [8:0] REG_INDEX,
    output reg [31:0] REG_DATA,
    output wire [8:0] REG_SIZE,
    input wire [15:0] I_AE,
    input wire [15:0] I_AG,
    // Q7: 128=1x, 256=2x diagnostic cap. Fine resolution is 1/128.
    input wire [8:0] I_DG
);
    wire [8:0] dg_q7 = (I_DG < 9'd128) ? 9'd128 :
                       ((I_DG > DG_MAX_Q7) ? DG_MAX_Q7 : I_DG);
    wire [7:0] dg_coarse = (dg_q7 == 9'd256) ? 8'h01 : 8'h00;
    wire [7:0] dg_fine = (dg_q7 == 9'd256) ? 8'h80 : dg_q7[7:0];
    assign REG_SIZE = 9'd11;
    always @* begin
        case (REG_INDEX)
            9'd0: REG_DATA = {16'h3e03,8'h0b};
            9'd1: REG_DATA = {16'h3800,8'h00};
            9'd2: REG_DATA = {16'h3e00,4'h0,I_AE[15:12]};
            9'd3: REG_DATA = {16'h3e01,I_AE[11:4]};
            9'd4: REG_DATA = {16'h3e02,I_AE[3:0],4'h0};
            9'd5: REG_DATA = {16'h3e08,I_AG[15:8]};
            9'd6: REG_DATA = {16'h3e09,I_AG[7:0]};
            9'd7: REG_DATA = {16'h3e06,dg_coarse};
            9'd8: REG_DATA = {16'h3e07,dg_fine};
            9'd9: REG_DATA = {16'h3800,8'h10};
            9'd10: REG_DATA = {16'h3800,8'h40};
            default: REG_DATA = 32'd0;
        endcase
    end
endmodule
