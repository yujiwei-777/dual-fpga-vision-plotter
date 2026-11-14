`timescale 1ns/1ps
// Capture one-clock producer pulses. Metadata remains in the producer's
// existing task-owned registers until its completion or cancellation drain.
// Dispatch itself is registered: service ready cannot form a combinational
// loop through its simultaneous-start fault detector.
module pcb_combined_service_dispatch_candidate(
    input wire I_clk,I_rst_n,I_cancel,
    input wire [6:0] I_request,I_done,
    input wire I_service_ready,
    output wire [6:0] O_start,O_pending,O_inflight,
    output wire O_busy,
    output reg O_fault
);
    reg [6:0] pending,dispatch,inflight;
    wire collision=|(I_request&(pending|dispatch|inflight));
    assign O_start=dispatch&{7{!I_cancel}};
    assign O_pending=pending|dispatch;
    assign O_inflight=inflight;
    assign O_busy=|(pending|dispatch|inflight);
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin pending<=0;dispatch<=0;inflight<=0;O_fault<=0;end
        else begin
            O_fault<=0;
            if(I_cancel)begin pending<=0;dispatch<=0;inflight<=0;end
            else if(collision)begin
                pending<=0;dispatch<=0;inflight<=0;O_fault<=1;
            end else begin
                dispatch<=0;
                inflight<=(inflight|dispatch)&~I_done;
                if(dispatch==0&&I_service_ready&&pending!=0)begin
                    dispatch<=pending;pending<=I_request;
                end else pending<=pending|I_request;
            end
        end
    end
endmodule
