module PH1P_LOGIC_ERAM #(
    parameter integer DATA_WIDTH_A = 20,
    parameter integer DATA_WIDTH_B = DATA_WIDTH_A,
    parameter integer ADDR_WIDTH_A = 10,
    parameter integer ADDR_WIDTH_B = ADDR_WIDTH_A,
    parameter integer DATA_DEPTH_A = 2 ** ADDR_WIDTH_A,
    parameter integer DATA_DEPTH_B = 2 ** ADDR_WIDTH_B,
    parameter integer BYTE_ENABLE = 0,
    parameter integer BYTE_A = BYTE_ENABLE == 0 ? 1 : DATA_WIDTH_A / BYTE_ENABLE,
    parameter integer BYTE_B = BYTE_ENABLE == 0 ? 1 : DATA_WIDTH_B / BYTE_ENABLE,
    parameter MODE = "DP",
    parameter REGMODE_A = "NOREG",
    parameter REGMODE_B = "NOREG",
    parameter WRITEMODE_A = "NORMAL",
    parameter WRITEMODE_B = "NORMAL",
    parameter IMPLEMENT = "20K(FAST)",
    parameter ECC_ENCODE = "DISABLE",
    parameter ECC_DECODE = "DISABLE",
    parameter CLKMODE = "ASYNC",
    parameter SSROVERCE = "DISABLE",
    parameter OREGSET_A = "RESET",
    parameter OREGSET_B = "RESET",
    parameter RESETMODE_A = "ASYNC",
    parameter RESETMODE_B = "ASYNC",
    parameter ASYNC_RESET_RELEASE_A = "ASYNC",
    parameter ASYNC_RESET_RELEASE_B = "ASYNC"
)(
    input wire [DATA_WIDTH_A-1:0] dia,
    input wire [ADDR_WIDTH_A-1:0] addra,
    input wire cea, ocea, clka, wea, rsta,
    input wire [BYTE_A-1:0] bea,
    input wire [DATA_WIDTH_B-1:0] dib,
    input wire [ADDR_WIDTH_B-1:0] addrb,
    input wire ceb, oceb, clkb, web, rstb,
    input wire [BYTE_B-1:0] beb,
    input wire ecc_sbiterrinj, ecc_dbiterrinj,
    output reg [DATA_WIDTH_A-1:0] doa,
    output reg [DATA_WIDTH_B-1:0] dob,
    output wire ecc_sbiterr,
    output wire ecc_dbiterr
);
    reg [DATA_WIDTH_A-1:0] mem [0:DATA_DEPTH_A-1];
    assign ecc_sbiterr = 1'b0;
    assign ecc_dbiterr = 1'b0;

    always @(posedge clka) begin
        if (cea && wea)
            mem[addra] <= dia;
        if (cea)
            doa <= mem[addra];
    end

    always @(posedge clkb) begin
        if (ceb)
            dob <= mem[addrb];
    end
endmodule
