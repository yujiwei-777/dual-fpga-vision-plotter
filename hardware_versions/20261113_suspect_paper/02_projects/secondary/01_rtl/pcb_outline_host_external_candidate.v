`timescale 1ns/1ps
// Reports-only outline firmware host. Numerical state remains in shared RF;
// only the public mask/flags and validation/ownership control live here.
module pcb_outline_host_external_candidate #(
    parameter integer OUTLINE_ENTRY=782,
    parameter [31:0] WATCHDOG=32'd2000000000
)(
    input wire I_clk,I_rst_n,I_start,I_cancel,I_released,
    input wire I_board_convex,I_board_inside,
    output wire O_ready,O_busy,O_retiring,O_endpoint_begin,O_engine_cancel,
    output reg O_done,O_valid,O_registration,O_complete,
    output reg [15:0] O_mask,
    output reg [3:0] O_error,
    output reg [8:0] O_diagnostic_error,
    output wire O_engine_host_write,O_engine_start,O_engine_emit_ready,
    output wire [5:0] O_engine_host_index,
    output wire [31:0] O_engine_host_data,
    output wire [15:0] O_engine_entry,
    input wire I_engine_busy,I_engine_done,I_engine_valid,I_engine_host_ready,I_engine_host_done,
    input wire [8:0] I_engine_status,I_engine_error,I_engine_emit_tag,
    input wire I_engine_emit_valid,
    input wire [31:0] I_engine_emit_d,I_engine_emit_a,I_engine_emit_b,
    input wire I_endpoint_idle,I_endpoint_fault,I_endpoint_locked,
    input wire [3:0] I_endpoint_error
);
    localparam IDLE=0,LOAD=1,LOAD_WAIT=2,KICK=3,RUN=4,DRAIN=5,RETIRE=6,LOCKED=7;
    reg [2:0] state;
    reg [1:0] flags;
    reg [4:0] patch_count;
    reg final_seen,malformed,result_good;
    reg [8:0] pending_error;
    reg [30:0] clocks;
    wire abort_now=I_cancel||(I_start&&state!=IDLE)||
        (state!=IDLE&&state!=DRAIN&&state!=RETIRE&&state!=LOCKED&&clocks>=WATCHDOG-1);
    wire patch_shape=I_engine_emit_tag==2&&!final_seen&&patch_count<16&&
        I_engine_emit_d=={27'd0,patch_count}&&I_engine_emit_a<=32'h40000000&&
        I_engine_emit_b[31:6]==0&&I_engine_emit_b[3:2]!=2&&I_engine_emit_b[5:4]!=2&&
        (!I_engine_emit_b[1]||(I_engine_emit_b[0]&&I_engine_emit_a!=0))&&
        (I_engine_emit_b[0]?(I_engine_emit_a!=0):(I_engine_emit_a==0&&I_engine_emit_b==0));
    wire final_shape=I_engine_emit_tag==3&&!final_seen&&patch_count==16&&
        I_engine_emit_d=={16'd0,O_mask}&&I_engine_emit_a<=1&&I_engine_emit_b<=1&&
        I_engine_emit_b[0]==(O_mask==16'hffff)&&(!I_engine_emit_a[0]||flags==3);
    function [3:0] error_map;
        input [8:0] code;
        begin case(code)
            0:error_map=0;9'h104:error_map=1;9'h108:error_map=2;
            9'h109:error_map=3;9'h10a:error_map=15;
            default:error_map=code[8:4]==5'h13 ? code[3:0]:(code<=15?code[3:0]:4'd15);
        endcase end
    endfunction
    assign O_ready=state==IDLE&&!I_engine_busy&&I_endpoint_idle&&!I_cancel;
    assign O_busy=state!=IDLE;
    assign O_retiring=state==RETIRE;
    assign O_endpoint_begin=I_start&&O_ready;
    assign O_engine_cancel=abort_now||state==DRAIN||state==LOCKED;
    assign O_engine_host_write=state==LOAD&&!abort_now;
    assign O_engine_host_index=6'd45;
    assign O_engine_host_data={30'd0,flags};
    assign O_engine_start=state==KICK&&!abort_now;
    assign O_engine_entry=OUTLINE_ENTRY[15:0];
    assign O_engine_emit_ready=state==RUN&&!abort_now&&!I_endpoint_fault;
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;flags<=0;patch_count<=0;final_seen<=0;malformed<=0;
            result_good<=0;pending_error<=0;clocks<=0;O_done<=0;O_valid<=0;
            O_registration<=0;O_complete<=0;O_mask<=0;O_error<=0;O_diagnostic_error<=0;
        end else begin
            O_done<=0;O_valid<=0;
            if(state!=IDLE&&state!=DRAIN&&state!=RETIRE&&state!=LOCKED)clocks<=clocks+1'b1;
            if(state!=IDLE&&state!=DRAIN&&state!=RETIRE&&state!=LOCKED&&abort_now)begin
                pending_error<=I_cancel?9'h104:I_start?9'h108:9'h109;
                result_good<=0;O_registration<=0;O_complete<=0;state<=DRAIN;
            end else case(state)
                IDLE:begin
                    if(I_cancel)begin O_registration<=0;O_complete<=0;end
                    else if(I_start&&O_ready)begin
                        flags<={I_board_inside,I_board_convex};patch_count<=0;final_seen<=0;
                        malformed<=0;result_good<=0;pending_error<=0;clocks<=0;O_mask<=0;
                        O_registration<=0;O_complete<=0;O_error<=0;O_diagnostic_error<=0;state<=LOAD;
                    end
                end
                LOAD:if(I_engine_host_ready)state<=LOAD_WAIT;
                LOAD_WAIT:if(I_engine_host_done)state<=KICK;
                KICK:state<=RUN;
                RUN:begin
                    if(I_endpoint_fault)begin
                        pending_error<=9'h130|{5'd0,I_endpoint_error};result_good<=0;state<=DRAIN;
                    end else begin
                        if(I_engine_emit_valid)begin
                            if(patch_shape)begin
                                if(I_engine_emit_b[1])O_mask[patch_count[3:0]]<=1;
                                patch_count<=patch_count+1'b1;
                            end else if(final_shape)begin
                                final_seen<=1;O_registration<=I_engine_emit_a[0];O_complete<=I_engine_emit_b[0];
                            end else malformed<=1;
                        end
                        if(I_engine_done)begin
                            result_good<=I_engine_valid&&I_engine_error==0&&I_engine_status==0&&
                                patch_count==16&&final_seen&&!malformed;
                            pending_error<=I_engine_error!=0?I_engine_error:
                                (!I_engine_valid||I_engine_status!=0||patch_count!=16||!final_seen||malformed)?9'h10a:9'd0;
                            state<=RETIRE;
                        end
                    end
                end
                DRAIN:if(I_endpoint_locked)begin
                    O_done<=1;O_error<=9;O_diagnostic_error<=pending_error;state<=LOCKED;
                end else if(!I_engine_busy&&I_endpoint_idle)state<=RETIRE;
                RETIRE:begin
                    if(I_cancel||I_start)begin result_good<=0;pending_error<=I_cancel?9'h104:9'h108;end
                    if(I_released)begin
                        O_done<=1;O_valid<=result_good&&!I_cancel&&!I_start;
                        O_error<=I_cancel?1:I_start?2:error_map(pending_error);
                        O_diagnostic_error<=I_cancel?9'h104:I_start?9'h108:pending_error;
                        if(!result_good||I_cancel||I_start)begin O_registration<=0;O_complete<=0;end
                        state<=IDLE;
                    end
                end
                LOCKED:begin O_registration<=0;O_complete<=0;end
                default:begin pending_error<=9'h1ff;result_good<=0;state<=DRAIN;end
            endcase
        end
    end
endmodule
