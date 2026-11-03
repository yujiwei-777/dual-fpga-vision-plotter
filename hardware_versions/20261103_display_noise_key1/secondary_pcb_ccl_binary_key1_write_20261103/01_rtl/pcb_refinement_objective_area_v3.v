`timescale 1ns/1ps
// Fine objective controller: corner guards ->1024 raw gray/reference pairs
// ->shared exact statistics ->shared positive NCC squared in Q30.
// Owner holds the fine coefficients unchanged from request acceptance until
// response or full cancellation drain. No result alone means PCB PASS.
// All shared engines and the RAM adapter must have one owner for the whole
// transaction. Reset must reset/drain the adapter and sampler together.
module pcb_refinement_objective_area_v3 #(
    parameter integer WAIT_TIMEOUT=1000000,
    parameter integer ABORT_TIMEOUT=100000,
    parameter [14:0] REFERENCE_BASE=15'd3852
) (
    input wire I_clk,I_rst_n,I_cancel,I_request_valid,
    output wire O_request_ready,
    input wire [26:0] I_request_tag,
    input wire I_div2,
    output wire O_idle,
    output reg O_done,O_score_valid,
    output reg [26:0] O_response_tag,
    output reg [30:0] O_score2_q30,
    output reg [3:0] O_error,
    output wire O_engine_cancel,
    output wire O_sample_start,
    output wire [7:0] O_sample_x,
    output wire [6:0] O_sample_y,
    output wire O_sample_half,
    input wire I_sample_busy,I_sample_done,I_sample_valid,
    input wire [3:0] I_sample_error,
    input wire [7:0] I_sample_gray,
    input wire signed [31:0] I_project_x_q16,I_project_y_q16,
    output wire O_reference_request,
    output wire O_reference_bank,
    output wire [14:0] O_reference_addr,
    input wire I_reference_ready,I_reference_valid,I_memory_idle,
    input wire [15:0] I_reference_data,
    output wire O_stats_start,
    output wire [3:0] O_stats_count_log2,
    output wire O_stats_sample_valid,
    output wire [7:0] O_stats_i,O_stats_t,
    input wire I_stats_ready,I_stats_busy,I_stats_done,I_stats_valid,
    input wire signed [35:0] I_covariance,
    input wire [35:0] I_variance_i,I_variance_t,
    output wire O_norm_start,
    output wire signed [35:0] O_norm_covariance,
    output wire [35:0] O_norm_variance_i,O_norm_variance_t,
    input wire I_norm_busy,I_norm_done,I_norm_valid,I_norm_positive,
    input wire [30:0] I_norm_score2_q30,
    input wire [3:0] I_norm_error
);
    localparam IDLE=0,STATS_START=1,ISSUE=2,SAMPLE_WAIT=3,REF_REQUEST=4,
               REF_WAIT=5,SUBMIT=6,STATS_WAIT=7,NORM_START=8,NORM_WAIT=9,
               FINISH=10,DRAIN=11,LOCKED=12;
    reg [3:0] state;
    reg div2,corners;
    reg [1:0] corner;
    reg [9:0] anchor;
    reg [7:0] observed,reference;
    reg pending_reference;
    function integer counter_bits;
        input integer limit;
        integer remaining;
        begin counter_bits=1;remaining=limit-1;
            while(remaining>1)begin counter_bits=counter_bits+1;remaining=remaining>>1;end
        end
    endfunction
    localparam integer WAIT_LIMIT=(WAIT_TIMEOUT>ABORT_TIMEOUT)?WAIT_TIMEOUT:ABORT_TIMEOUT;
    localparam integer WAIT_BITS=counter_bits(WAIT_LIMIT);
    reg [WAIT_BITS-1:0] wait_count;
    function [7:0] anchor_x;
        input [4:0] index;
        begin case(index)
            0:anchor_x=19;1:anchor_x=24;2:anchor_x=29;3:anchor_x=34;
            4:anchor_x=39;5:anchor_x=44;6:anchor_x=49;7:anchor_x=54;
            8:anchor_x=58;9:anchor_x=63;10:anchor_x=68;11:anchor_x=73;
            12:anchor_x=78;13:anchor_x=83;14:anchor_x=88;15:anchor_x=93;
            16:anchor_x=98;17:anchor_x=103;18:anchor_x=108;19:anchor_x=113;
            20:anchor_x=118;21:anchor_x=123;22:anchor_x=128;23:anchor_x=133;
            24:anchor_x=137;25:anchor_x=142;26:anchor_x=147;27:anchor_x=152;
            28:anchor_x=157;29:anchor_x=162;30:anchor_x=167;31:anchor_x=172;
        endcase end
    endfunction
    function [6:0] anchor_y;
        input [4:0] index;
        begin case(index)
            0:anchor_y=15;1:anchor_y=17;2:anchor_y=19;3:anchor_y=21;
            4:anchor_y=23;5:anchor_y=25;6:anchor_y=28;7:anchor_y=30;
            8:anchor_y=32;9:anchor_y=34;10:anchor_y=36;11:anchor_y=38;
            12:anchor_y=40;13:anchor_y=42;14:anchor_y=44;15:anchor_y=46;
            16:anchor_y=49;17:anchor_y=51;18:anchor_y=53;19:anchor_y=55;
            20:anchor_y=57;21:anchor_y=59;22:anchor_y=61;23:anchor_y=63;
            24:anchor_y=65;25:anchor_y=67;26:anchor_y=70;27:anchor_y=72;
            28:anchor_y=74;29:anchor_y=76;30:anchor_y=78;31:anchor_y=80;
        endcase end
    endfunction
    wire [7:0] corner_x=(corner==1 || corner==2) ? 8'd187 : 8'd4;
    wire [6:0] corner_y=corner[1] ? 7'd87 : 7'd8;
    // Integral Q16 boundaries permit exact signed-high-word comparisons.
    // Inclusive upper limits additionally require a zero fractional part at
    // equality. Negative values retain floor semantics through signed [31:16].
    wire signed [15:0] project_x_integer=$signed(I_project_x_q16[31:16]);
    wire signed [15:0] project_y_integer=$signed(I_project_y_q16[31:16]);
    wire signed [15:0] corner_x_min=(corner==1 || corner==2)?16'sd171:-16'sd12;
    wire signed [15:0] corner_x_max=(corner==1 || corner==2)?16'sd203:16'sd20;
    wire signed [15:0] corner_y_min=corner[1]?16'sd71:-16'sd8;
    wire signed [15:0] corner_y_max=corner[1]?16'sd103:16'sd24;
    wire corner_guard=project_x_integer>=corner_x_min && project_y_integer>=corner_y_min &&
        (project_x_integer<corner_x_max || (project_x_integer==corner_x_max && I_project_x_q16[15:0]==0)) &&
        (project_y_integer<corner_y_max || (project_y_integer==corner_y_max && I_project_y_q16[15:0]==0));
    wire anchor_guard=project_x_integer>=16'sd1 && project_y_integer>=16'sd1 &&
                      project_x_integer<16'sd190 && project_y_integer<16'sd94;
    wire reference_accept=O_reference_request && I_reference_ready;
    wire reference_response=I_reference_valid && (pending_reference || reference_accept);
    wire engines_idle=!I_sample_busy && !I_stats_busy && !I_norm_busy && I_memory_idle && !pending_reference;
    assign O_idle=state==IDLE && engines_idle;
    assign O_request_ready=O_idle && !I_cancel;
    assign O_engine_cancel=state==DRAIN || state==LOCKED;
    assign O_sample_start=state==ISSUE && !I_sample_busy && !I_cancel;
    assign O_sample_x=corners ? corner_x:anchor_x(anchor[4:0]);
    assign O_sample_y=corners ? corner_y:anchor_y(anchor[9:5]);
    assign O_sample_half=div2;
    assign O_reference_request=state==REF_REQUEST && !I_cancel;
    assign O_reference_bank=1'b1;
    assign O_reference_addr=REFERENCE_BASE+(div2?15'd0:15'd512)+{6'd0,anchor[9:1]};
    assign O_stats_start=state==STATS_START && !I_cancel;
    assign O_stats_count_log2=4'd10;
    assign O_stats_sample_valid=state==SUBMIT && !I_cancel;
    assign O_stats_i=observed;
    assign O_stats_t=reference;
    assign O_norm_start=state==NORM_START && !I_cancel;
    assign O_norm_covariance=I_covariance;
    assign O_norm_variance_i=I_variance_i;
    assign O_norm_variance_t=I_variance_t;
    task drain;
        input [3:0] code;
        begin O_score_valid<=0;O_score2_q30<=0;O_error<=code;wait_count<=0;state<=DRAIN;end
    endtask
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;div2<=0;corners<=1;corner<=0;anchor<=0;observed<=0;reference<=0;
            pending_reference<=0;wait_count<=0;O_done<=0;O_score_valid<=0;O_response_tag<=0;
            O_score2_q30<=0;O_error<=0;
        end else begin
            O_done<=0;
            if(reference_accept)pending_reference<=1;
            if(reference_response)pending_reference<=0;
            if(state==LOCKED)state<=LOCKED;
            else if(I_cancel && state!=IDLE && state!=DRAIN)drain(4'd1);
            else case(state)
                IDLE:if(I_request_valid && O_request_ready)begin
                    O_response_tag<=I_request_tag;div2<=I_div2;corners<=1;corner<=0;anchor<=0;
                    O_score_valid<=0;O_score2_q30<=0;O_error<=0;wait_count<=0;state<=STATS_START;
                end
                STATS_START:begin wait_count<=0;state<=ISSUE;end
                ISSUE:if(!I_sample_busy)begin wait_count<=0;state<=SAMPLE_WAIT;end
                else if(wait_count>=WAIT_TIMEOUT-1)drain(4'd3);
                else wait_count<=wait_count+1'b1;
                SAMPLE_WAIT:if(I_sample_done)begin
                    wait_count<=0;
                    // Endpoint error 2 is a normal rejected projective
                    // denominator trial, matching integer project(...)=None.
                    // All other sampler errors remain hard objective faults.
                    if(I_sample_error==4'd2)drain(4'd0);
                    else if(I_sample_error!=0)drain(4'd4);
                    else if(!I_sample_valid || (corners ? !corner_guard:!anchor_guard))drain(4'd0);
                    else if(corners)begin
                        if(corner==3)begin corners<=0;anchor<=0;end
                        else corner<=corner+2'd1;
                        state<=ISSUE;
                    end else begin observed<=I_sample_gray;state<=REF_REQUEST;end
                end else if(wait_count>=WAIT_TIMEOUT-1)drain(4'd3);
                else wait_count<=wait_count+1'b1;
                REF_REQUEST,REF_WAIT:if(reference_response)begin
                    reference<=anchor[0]?I_reference_data[15:8]:I_reference_data[7:0];
                    wait_count<=0;state<=SUBMIT;
                end else if(wait_count>=WAIT_TIMEOUT-1)drain(4'd3);
                else begin wait_count<=wait_count+1'b1;if(reference_accept)state<=REF_WAIT;end
                SUBMIT:if(I_stats_ready)begin
                    wait_count<=0;
                    if(anchor==1023)state<=STATS_WAIT;
                    else begin anchor<=anchor+10'd1;state<=ISSUE;end
                end else if(wait_count>=WAIT_TIMEOUT-1)drain(4'd3);
                else wait_count<=wait_count+1'b1;
                STATS_WAIT:if(I_stats_done)begin
                    wait_count<=0;
                    if(!I_stats_valid || I_variance_t!=(div2?36'd381122231:36'd729788860))drain(4'd5);
                    else if(I_covariance<=0 || I_variance_i==0)drain(4'd0);
                    else state<=NORM_START;
                end else if(wait_count>=WAIT_TIMEOUT-1)drain(4'd3);
                else wait_count<=wait_count+1'b1;
                NORM_START:begin wait_count<=0;state<=NORM_WAIT;end
                NORM_WAIT:if(I_norm_done)begin
                    if(!I_norm_valid || I_norm_error!=0)drain(4'd6);
                    else begin
                        O_score_valid<=I_norm_positive;O_score2_q30<=I_norm_score2_q30;
                        wait_count<=0;state<=FINISH;
                    end
                end else if(wait_count>=WAIT_TIMEOUT-1)drain(4'd3);
                else wait_count<=wait_count+1'b1;
                FINISH:begin O_done<=1;state<=IDLE;end
                DRAIN:if(engines_idle)begin O_done<=1;state<=IDLE;end
                else if(wait_count>=ABORT_TIMEOUT-1)begin O_done<=1;O_error<=4'd9;state<=LOCKED;end
                else wait_count<=wait_count+1'b1;
                default:begin O_done<=1;O_score_valid<=0;O_error<=4'd15;state<=LOCKED;end
            endcase
        end
    end
endmodule
