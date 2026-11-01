// Read-only camera-domain snapshot mailbox for AWB diagnostics.
// The requester toggles req once, waits for the returned ack through two
// receiver synchronizers plus two settling clocks, then captures data.
// The source holds the entire bus until the next request.  Camera/video
// signals have no dependency on this mailbox or the Ethernet consumer.
module awb_diag_mailbox #(
    parameter integer WIDTH = 224
) (
    input wire I_clk_src,
    input wire I_rst_n,
    input wire I_req_async,
    input wire [WIDTH-1:0] I_frame_data,
    output reg O_ack,
    output reg [WIDTH-1:0] O_data
);
    // Common asynchronous assertion includes the diagnostic network reset;
    // release is synchronized locally even if the MIPI clock starts late.
    (* ASYNC_REG = "TRUE", dont_touch = "true" *) reg rst_s1, rst_s2;
    always @(posedge I_clk_src or negedge I_rst_n) begin
        if (!I_rst_n) begin rst_s1 <= 1'b0; rst_s2 <= 1'b0; end
        else begin rst_s1 <= 1'b1; rst_s2 <= rst_s1; end
    end
    (* ASYNC_REG = "TRUE", dont_touch = "true" *) reg req_s1, req_s2;
    always @(posedge I_clk_src or negedge rst_s2) begin
        if (!rst_s2) begin
            req_s1 <= 1'b0;
            req_s2 <= 1'b0;
            O_ack <= 1'b0;
            O_data <= {WIDTH{1'b0}};
        end else begin
            req_s1 <= I_req_async;
            req_s2 <= req_s1;
            if (req_s2 != O_ack) begin
                O_data <= I_frame_data;
                O_ack <= req_s2;
            end
        end
    end
endmodule
