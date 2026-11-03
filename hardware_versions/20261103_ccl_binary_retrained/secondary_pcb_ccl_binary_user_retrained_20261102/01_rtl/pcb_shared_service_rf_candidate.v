`timescale 1ns/1ps
// One physical 128x16 private RF. A is read/write; B is a reserved read port.
// Both reads have one registered clock of latency. No RF reset/clear logic.
module pcb_shared_service_rf_candidate(
    input wire I_clk,
    input wire [6:0] I_a_addr,
    input wire I_a_we,
    input wire [15:0] I_a_wdata,
    output reg [15:0] O_a_rdata,
    input wire [6:0] I_b_addr,
    output reg [15:0] O_b_rdata
);
    (* ram_style="bram" *) reg [15:0] memory[0:127] /* synthesis syn_ramstyle="block_ram" */;
    always @(posedge I_clk) begin
        if(I_a_we)memory[I_a_addr]<=I_a_wdata;
        O_a_rdata<=memory[I_a_addr];
        O_b_rdata<=memory[I_b_addr];
    end
endmodule
