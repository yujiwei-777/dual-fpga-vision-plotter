// Minimal UART TX (8N1) for on-board text debug.  Idle-high, LSB-first,
// start(0) + 8 data + stop(1).  Parameterised clock.
module uart_tx #(
    parameter CLK_HZ = 100000000,
    parameter BAUD   = 115200
)(
    input       clk,
    input       rst_n,
    input [7:0] tx_byte,
    input       tx_start,
    output reg  tx,          // serial line (idle = 1)
    output wire tx_busy
);
    localparam integer DIV = CLK_HZ / BAUD;
    reg [15:0] cnt;
    reg [3:0]  bitcnt;
    reg [9:0]  shift;
    reg        send;

    assign tx_busy = send | (bitcnt != 0);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx <= 1'b1; cnt <= 16'd0; bitcnt <= 4'd0; shift <= 10'd0; send <= 1'b0;
        end else if (!send) begin
            tx <= 1'b1;
            if (tx_start) begin
                shift  <= {1'b1, tx_byte, 1'b0};   // stop,data,start
                send   <= 1'b1;
                cnt    <= 16'd0;
                bitcnt <= 4'd0;
            end
        end else begin
            if (cnt == DIV - 1) begin
                cnt <= 16'd0;
                tx  <= shift[0];
                shift <= {1'b1, shift[9:1]};
                bitcnt <= bitcnt + 4'd1;
                if (bitcnt == 4'd9) send <= 1'b0;
            end else begin
                cnt <= cnt + 16'd1;
            end
        end
    end
endmodule
