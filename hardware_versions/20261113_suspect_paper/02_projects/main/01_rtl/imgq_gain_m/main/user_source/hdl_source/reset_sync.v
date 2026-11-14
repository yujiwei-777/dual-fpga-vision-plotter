// Small technology independent reset synchronizer used by the Ethernet PLL
// branch.  Assertion is asynchronous; release is synchronized to I_clk.
module reset_sync (
    input  wire I_clk,
    input  wire I_async_rst_n,
    output wire O_rst_n
);
    reg [1:0] sync_ff;
    always @(posedge I_clk or negedge I_async_rst_n) begin
        if (!I_async_rst_n)
            sync_ff <= 2'b00;
        else
            sync_ff <= {sync_ff[0],1'b1};
    end
    assign O_rst_n = sync_ff[1];
endmodule
