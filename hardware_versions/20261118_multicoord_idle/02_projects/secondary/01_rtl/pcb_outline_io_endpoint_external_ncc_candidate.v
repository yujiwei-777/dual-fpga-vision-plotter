`timescale 1ns/1ps
// Reports-only production-shaped IO28 endpoint, not yet integrated/qualified.
// A/B must remain stable from acceptance through response/drain, as provided
// by the engine's existing operand banks. No duplicate numerical input bank.
// One RAM request in flight. A canceled accepted read drains before reuse.
// Stats completion is sticky because firmware may observe it after its pulse.
module pcb_outline_io_endpoint_external_ncc_candidate #(
    parameter integer WAIT_TIMEOUT=1000000,
    parameter integer ABORT_TIMEOUT=100000
)(
    input wire clk,rst_n,begin_job,cancel,
    input wire request_valid,
    output wire request_ready,
    input wire [8:0] command,
    input wire [31:0] arg_a,arg_b,
    output wire response_valid,
    input wire response_ready,
    output reg [31:0] return_data,
    output wire busy,idle,locked,
    output reg fault,
    output reg [3:0] error,
    output wire ram_request,ram_bank,
    output wire [14:0] ram_address,
    input wire ram_ready,ram_valid,ram_idle,
    input wire [15:0] ram_data,
    output wire stats_start,stats_cancel,
    output wire [3:0] stats_count_log2,
    output wire sample_valid,
    output wire [7:0] sample_i,sample_t,
    input wire sample_ready,stats_busy,stats_done,stats_valid,
    input wire [3:0] stats_error,
    input wire signed [35:0] covariance,
    input wire [35:0] variance_i,variance_t,
    // The shared normalizer reads the persistent stats moment outputs.
    // Keep exclusive stats/NCC ownership for the entire firmware job.
    output wire ncc_start,ncc_cancel,
    input wire ncc_busy,ncc_done,ncc_valid,ncc_positive,
    input wire [30:0] ncc_score,
    input wire [3:0] ncc_error
);
    localparam IDLE=0,RAM_REQUEST=1,RAM_WAIT=2,STATS_START=3,
        SAMPLE=4,STATS_WAIT=5,RESPONSE=6,DRAIN=7,LOCKED=8,NCC_START=9,NCC_WAIT=10;
    localparam integer CW=(WAIT_TIMEOUT>ABORT_TIMEOUT?WAIT_TIMEOUT:ABORT_TIMEOUT)>1?
        $clog2((WAIT_TIMEOUT>ABORT_TIMEOUT?WAIT_TIMEOUT:ABORT_TIMEOUT)+1):1;
    reg [3:0] state;
    reg [CW-1:0] wait_count;
    reg ram_pending,stats_seen,stats_good;
    wire accept=request_valid&&request_ready;
    wire ram_accept=ram_request&&ram_ready;
    wire ram_response=ram_valid&&(ram_pending||ram_accept);
    wire services_idle=ram_idle&&!ram_valid&&!ram_pending&&!stats_busy&&!ncc_busy;
    wire ram_args_ok=arg_a<=1&&arg_b<=32767&&
        (arg_a==0?(arg_b>=8192&&arg_b<=17407):
            ((arg_b>=6284&&arg_b<=6603)||(arg_b>=6636&&arg_b<=6827)));
    wire moments_args_ok=arg_a<6&&arg_b==0&&stats_seen&&stats_good;
    wire abort_now=cancel||(begin_job&&(state!=IDLE||!services_idle));

    assign request_ready=state==IDLE&&!cancel&&!begin_job&&!fault;
    assign response_valid=state==RESPONSE&&!abort_now;
    assign busy=state!=IDLE||ram_pending||stats_busy||ncc_busy;
    assign idle=state==IDLE&&services_idle;
    assign locked=state==LOCKED;
    assign ram_request=state==RAM_REQUEST&&!abort_now;
    assign ram_bank=arg_a[0];
    assign ram_address=arg_b[14:0];
    assign stats_start=state==STATS_START&&!stats_busy&&!abort_now;
    assign stats_cancel=abort_now||state==DRAIN||state==LOCKED;
    assign ncc_start=state==NCC_START&&!ncc_busy&&!abort_now;
    assign ncc_cancel=abort_now||state==DRAIN||state==LOCKED;
    assign stats_count_log2=arg_a[3:0];
    assign sample_valid=state==SAMPLE&&!abort_now;
    assign sample_i=arg_a[7:0];
    assign sample_t=arg_b[7:0];

    task fail_and_drain;
        input [3:0] code;
        begin fault<=1;error<=code;wait_count<=0;state<=DRAIN;end
    endtask

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;wait_count<=0;ram_pending<=0;stats_seen<=0;stats_good<=0;
            fault<=0;error<=0;return_data<=0;
        end else begin
            if(ram_accept)ram_pending<=1;
            if(ram_response)ram_pending<=0;
            if(stats_done)begin stats_seen<=1;stats_good<=stats_valid&&stats_error==0;end
            if(state==LOCKED)state<=LOCKED;
            else if(abort_now&&state!=DRAIN&&(state!=IDLE||!services_idle||begin_job))begin
                if(begin_job&&!cancel)fail_and_drain(4'd2);
                else begin state<=DRAIN;wait_count<=0;stats_seen<=0;stats_good<=0;end
            end else case(state)
                IDLE:begin
                    wait_count<=0;
                    // A level-held cancel must not manufacture a fresh
                    // IDLE->DRAIN transaction after all accepted work drains.
                    if(cancel)begin stats_seen<=0;stats_good<=0;end
                    if(begin_job&&services_idle)begin
                        fault<=0;error<=0;stats_seen<=0;stats_good<=0;return_data<=0;
                    end
                    if(accept)case(command)
                        0:if(!ram_args_ok)fail_and_drain(4'd5);
                          else state<=RAM_REQUEST;
                        1:if((arg_a!=5&&arg_a!=6)||arg_b!=0||stats_busy)fail_and_drain(4'd6);
                          else begin stats_seen<=0;stats_good<=0;state<=STATS_START;end
                        2:if(arg_a>255||arg_b>255||!stats_busy)fail_and_drain(4'd6);
                          else state<=SAMPLE;
                        3:if(!moments_args_ok)fail_and_drain(4'd6);
                          else begin
                              case(arg_a[2:0])
                                  0:return_data<=covariance[31:0];
                                  1:return_data<={{28{covariance[35]}},covariance[35:32]};
                                  2:return_data<=variance_i[31:0];
                                  3:return_data<={28'd0,variance_i[35:32]};
                                  4:return_data<=variance_t[31:0];
                                  5:return_data<={28'd0,variance_t[35:32]};
                              endcase
                              state<=RESPONSE;
                          end
                        4:if(arg_a!=0||arg_b!=0)fail_and_drain(4'd6);
                          else state<=STATS_WAIT;
                        5:if(arg_a!=0||arg_b!=0||!stats_seen||!stats_good||
                             stats_busy||ncc_busy)fail_and_drain(4'd7);
                          else state<=NCC_START;
                        default:fail_and_drain(4'd15);
                    endcase
                end
                RAM_REQUEST,RAM_WAIT:begin
                    if(ram_response)begin return_data<={16'd0,ram_data};state<=RESPONSE;wait_count<=0;end
                    else if(wait_count>=WAIT_TIMEOUT-1)fail_and_drain(4'd3);
                    else begin wait_count<=wait_count+1'b1;if(ram_accept)state<=RAM_WAIT;end
                end
                STATS_START:if(!stats_busy)begin return_data<=0;state<=RESPONSE;wait_count<=0;end
                    else if(wait_count>=WAIT_TIMEOUT-1)fail_and_drain(4'd3);
                    else wait_count<=wait_count+1'b1;
                SAMPLE:if(!stats_busy)fail_and_drain(4'd6);
                    else if(sample_ready)begin return_data<=0;state<=RESPONSE;wait_count<=0;end
                    else if(wait_count>=WAIT_TIMEOUT-1)fail_and_drain(4'd3);
                    else wait_count<=wait_count+1'b1;
                STATS_WAIT:if(stats_seen)begin return_data<=stats_good?32'd1:32'd0;state<=RESPONSE;wait_count<=0;end
                    else if(wait_count>=WAIT_TIMEOUT-1)fail_and_drain(4'd3);
                    else wait_count<=wait_count+1'b1;
                // NCC_START advances on the sole start edge, including
                // the normalizer's one-cycle nonpositive/error cases.
                NCC_START:if(!ncc_busy)begin state<=NCC_WAIT;wait_count<=0;end
                    else if(wait_count>=WAIT_TIMEOUT-1)fail_and_drain(4'd3);
                    else wait_count<=wait_count+1'b1;
                NCC_WAIT:if(ncc_done)begin
                        if(!ncc_valid||ncc_error!=0)fail_and_drain(4'd7);
                        else begin return_data<=ncc_positive?{1'b0,ncc_score}:32'd0;
                            state<=RESPONSE;wait_count<=0;end
                    end else if(wait_count>=WAIT_TIMEOUT-1)fail_and_drain(4'd3);
                    else wait_count<=wait_count+1'b1;
                RESPONSE:if(response_ready)begin state<=IDLE;wait_count<=0;end
                    else if(wait_count>=WAIT_TIMEOUT-1)fail_and_drain(4'd3);
                    else wait_count<=wait_count+1'b1;
                DRAIN:if(services_idle)begin state<=IDLE;stats_seen<=0;stats_good<=0;end
                    else if(wait_count>=ABORT_TIMEOUT-1)begin fault<=1;error<=4'd9;state<=LOCKED;end
                    else wait_count<=wait_count+1'b1;
                default:begin fault<=1;error<=4'd15;state<=LOCKED;end
            endcase
        end
    end
endmodule
