`timescale 1ns/1ps
// Explicit physical banking. No asynchronous large-array read and no RAM reset.
// Read latency is two rising clocks from a stable raddr to q. The caller uses
// an additional dispatch clock, so vendor RAM simulation and hardware agree.
module doc_stroke_bram #(
    parameter integer WIDTH=1,parameter integer BANK_ADDR=14,
    parameter integer BANKS=7,parameter integer ADDR=17
)(
    input wire clk,input wire we,input wire [ADDR-1:0] waddr,
    input wire [WIDTH-1:0] wdata,input wire [ADDR-1:0] raddr,
    output reg [WIDTH-1:0] q
);
    localparam integer SEL=(ADDR>BANK_ADDR)?ADDR-BANK_ADDR:1;
    wire [WIDTH-1:0] bank_q [0:BANKS-1];
    reg [SEL-1:0] read_bank;
    genvar g;
    generate for(g=0;g<BANKS;g=g+1) begin:bank
`ifdef DOC_BEHAVIORAL_RAM
        // Test-only model has the same two-clock contract as the physical RAM.
        reg [WIDTH-1:0] mem [0:(1<<BANK_ADDR)-1];
        reg [WIDTH-1:0] rq;
        always @(posedge clk) begin
            if(we && (waddr>>BANK_ADDR)==g) mem[waddr[BANK_ADDR-1:0]]<=wdata;
            if((raddr>>BANK_ADDR)==g)rq<=mem[raddr[BANK_ADDR-1:0]];
        end
        assign bank_q[g]=rq;
`else
        PH1P_LOGIC_ERAM #(
            .DATA_WIDTH_A(WIDTH),.DATA_WIDTH_B(WIDTH),
            .ADDR_WIDTH_A(BANK_ADDR),.ADDR_WIDTH_B(BANK_ADDR),
            .DATA_DEPTH_A(1<<BANK_ADDR),.DATA_DEPTH_B(1<<BANK_ADDR),
            .MODE("DP"),.REGMODE_A("NOREG"),.REGMODE_B("NOREG"),
            .WRITEMODE_A("NORMAL"),.WRITEMODE_B("NORMAL"),
            .IMPLEMENT("20K(FAST)"),.ECC_ENCODE("DISABLE"),.ECC_DECODE("DISABLE"),
            .CLKMODE("ASYNC"),.SSROVERCE("DISABLE"),
            .OREGSET_A("RESET"),.OREGSET_B("RESET"),
            .RESETMODE_A("ASYNC"),.RESETMODE_B("ASYNC"),
            .ASYNC_RESET_RELEASE_A("ASYNC"),.ASYNC_RESET_RELEASE_B("ASYNC")
        ) ram(
            .dia(wdata),.addra(waddr[BANK_ADDR-1:0]),.cea(1'b1),.ocea(1'b0),
            .clka(clk),.wea(we && (waddr>>BANK_ADDR)==g),.rsta(1'b0),.bea(1'b0),
            .dib({WIDTH{1'b0}}),.addrb(raddr[BANK_ADDR-1:0]),.ceb((raddr>>BANK_ADDR)==g),.oceb(1'b0),
            .clkb(clk),.web(1'b0),.rstb(1'b0),.beb(1'b0),
            .dob(bank_q[g]),.doa(),.ecc_sbiterr(),.ecc_dbiterr(),
            .ecc_sbiterrinj(1'b0),.ecc_dbiterrinj(1'b0)
        );
`endif
    end endgenerate
    always @(posedge clk) begin
        read_bank<=raddr>>BANK_ADDR;
        if(read_bank<BANKS) q<=bank_q[read_bank];else q<={WIDTH{1'b0}};
    end
endmodule
