`timescale 1ns/1ps
// Reports-only sampler host. The producer retains fine/coarse packets while
// busy. Only point/flags are captured here; one shared engine owns its RF.
// Retiring separates engine completion from public sampler completion: the
// latter is published only after the service has safely released its owner.
module pcb_warp_host_external_candidate #(
    parameter integer WARP_ENTRY=1237,
    parameter integer WATCHDOG=2000000
)(
    input wire I_clk,I_rst_n,I_start,I_cancel,I_released,
    input wire [7:0] I_x,input wire [6:0] I_y,
    input wire I_use_fine,I_apply_coarse,I_half_image,
    input wire [255:0] I_fine,input wire [239:0] I_coarse,
    output wire O_ready,O_busy,O_retiring,
    output reg O_done,O_valid,O_sample_complete,
    output reg [3:0] O_error,O_tap_inside,
    output reg [8:0] O_diagnostic_error,
    output reg [7:0] O_gray,
    output reg signed [31:0] O_project_x_q16,O_project_y_q16,
    output reg signed [63:0] O_source_x_q28,O_source_y_q28,
    output wire O_engine_cancel,O_engine_host_write,O_engine_start,O_engine_emit_ready,
    output wire [5:0] O_engine_host_index,
    output reg [31:0] O_engine_host_data,
    output wire [15:0] O_engine_entry,
    input wire I_engine_busy,I_engine_done,I_engine_valid,I_engine_host_ready,I_engine_host_done,
    input wire [8:0] I_engine_status,I_engine_error,I_engine_emit_tag,
    input wire I_engine_emit_valid,
    input wire [31:0] I_engine_emit_d,I_engine_emit_a,I_engine_emit_b,
    input wire I_uop_busy,I_uop_done,I_uop_valid,I_uop_complete,
    input wire [3:0] I_uop_error,I_uop_taps,
    input wire [7:0] I_uop_gray
);
    localparam IDLE=0,LOAD=1,LOAD_WAIT=2,KICK=3,RUN=4,DRAIN=5,RETIRE=6,LOCKED=7;
    localparam integer TIMER_BITS=WATCHDOG>1?$clog2(WATCHDOG):1;
    reg [2:0] state;
    reg [4:0] load_index;
    reg [7:0] point_x;reg [6:0] point_y;reg [2:0] flags;
    reg [1:0] emit_count;
    reg malformed,uop_seen,uop_good,result_good;
    reg [8:0] pending_error;
    reg [TIMER_BITS-1:0] clocks;
    wire abort_now=I_cancel||(I_start&&state!=IDLE)||
        (state!=IDLE&&state!=DRAIN&&state!=RETIRE&&state!=LOCKED&&clocks>=WATCHDOG-1);
    wire [2:0] coarse_index=(load_index-5'd11)>>1;
    wire [39:0] coarse_word=I_coarse[40*coarse_index+:40];
    wire tag6_shape=I_engine_emit_d<=1023&&
        (I_engine_emit_a&32'hff00f0cf)==0&&I_engine_emit_a[4]&&
        I_engine_emit_b[31:8]==0&&uop_seen&&uop_good&&
        I_engine_emit_a[23:16]==O_gray&&I_engine_emit_a[11:8]==O_tap_inside&&
        I_engine_emit_a[5]==O_sample_complete;
    wire emit_shape=(emit_count==0&&I_engine_emit_tag==4)||
        (emit_count==1&&I_engine_emit_tag==5)||
        (emit_count==2&&I_engine_emit_tag==6&&tag6_shape);
    function [3:0] error_map;
        input [8:0] code;
        begin case(code)
            0:error_map=0;9'h104:error_map=4;9'h108:error_map=6;
            9'h109:error_map=7;9'h10a:error_map=8;
            default:error_map=code[8:4]==5'h12 ? code[3:0]:4'd15;
        endcase end
    endfunction
    assign O_ready=state==IDLE&&!I_engine_busy&&!I_cancel;
    assign O_busy=state!=IDLE;
    assign O_retiring=state==RETIRE;
    assign O_engine_cancel=abort_now||state==DRAIN||state==LOCKED;
    // LOAD/KICK fencing is required even though the arithmetic uop is idle.
    assign O_engine_host_write=state==LOAD&&!abort_now;
    assign O_engine_start=state==KICK&&!abort_now;
    assign O_engine_emit_ready=state==RUN&&!abort_now;
    assign O_engine_entry=WARP_ENTRY[15:0];
    assign O_engine_host_index=load_index<3?{1'b0,load_index}:{1'b0,load_index}+6'd1;
    always @*begin
        O_engine_host_data=0;
        if(load_index==0)O_engine_host_data={24'd0,point_x};
        else if(load_index==1)O_engine_host_data={25'd0,point_y};
        else if(load_index==2)O_engine_host_data={29'd0,flags};
        else if(load_index<11)O_engine_host_data=I_fine[32*(load_index-3)+:32];
        else if(load_index[0])O_engine_host_data=coarse_word[31:0];
        else O_engine_host_data={{24{coarse_word[39]}},coarse_word[39:32]};
    end
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;load_index<=0;point_x<=0;point_y<=0;flags<=0;emit_count<=0;
            malformed<=0;uop_seen<=0;uop_good<=0;result_good<=0;pending_error<=0;clocks<=0;
            O_done<=0;O_valid<=0;O_sample_complete<=0;O_error<=0;O_diagnostic_error<=0;
            O_tap_inside<=0;O_gray<=0;O_project_x_q16<=0;O_project_y_q16<=0;
            O_source_x_q28<=0;O_source_y_q28<=0;
        end else begin
            O_done<=0;O_valid<=0;
            if(state!=IDLE&&state!=DRAIN&&state!=RETIRE&&state!=LOCKED)clocks<=clocks+1'b1;
            if(state!=IDLE&&state!=DRAIN&&state!=RETIRE&&state!=LOCKED&&abort_now)begin
                pending_error<=I_cancel?9'h104:I_start?9'h108:9'h109;
                result_good<=0;O_sample_complete<=0;state<=DRAIN;
            end else case(state)
                IDLE:begin
                    if(I_cancel)O_sample_complete<=0;
                    else if(I_start&&O_ready)begin
                        point_x<=I_x;point_y<=I_y;flags<={I_half_image,I_apply_coarse,I_use_fine};
                        load_index<=0;emit_count<=0;malformed<=0;uop_seen<=0;uop_good<=0;
                        result_good<=0;pending_error<=0;clocks<=0;
                        O_sample_complete<=0;O_tap_inside<=0;O_gray<=0;O_error<=0;O_diagnostic_error<=0;
                        state<=LOAD;
                    end
                end
                LOAD:if(I_engine_host_ready)state<=LOAD_WAIT;
                LOAD_WAIT:if(I_engine_host_done)begin
                    if(load_index==22)state<=KICK;
                    else begin load_index<=load_index+1'b1;state<=LOAD;end
                end
                KICK:state<=RUN;
                RUN:begin
                    if(I_uop_done)begin
                        uop_seen<=1;uop_good<=I_uop_valid&&I_uop_error==0&&!I_uop_busy;
                        O_gray<=I_uop_gray;O_sample_complete<=I_uop_complete;O_tap_inside<=I_uop_taps;
                    end
                    if(I_engine_emit_valid)begin
                        if(!emit_shape)malformed<=1;
                        else begin
                            emit_count<=emit_count+1'b1;
                            case(emit_count)
                                0:begin O_source_x_q28<={I_engine_emit_a,I_engine_emit_d};O_source_y_q28[31:0]<=I_engine_emit_b;end
                                1:begin O_source_y_q28[63:32]<=I_engine_emit_d;O_project_x_q16<=I_engine_emit_a;O_project_y_q16<=I_engine_emit_b;end
                                default:begin end
                            endcase
                        end
                    end
                    if(I_engine_done)begin
                        if(I_engine_busy||I_uop_busy)begin
                            O_error<=error_map(I_engine_error);O_diagnostic_error<=I_engine_error;
                            O_done<=1;O_sample_complete<=0;state<=LOCKED;
                        end else begin
                            result_good<=I_engine_valid&&I_engine_error==0&&I_engine_status==0&&
                                uop_seen&&uop_good&&emit_count==3&&!malformed;
                            pending_error<=I_engine_error!=0?I_engine_error:
                                (!I_engine_valid||I_engine_status!=0||!uop_seen||!uop_good||emit_count!=3||malformed)?9'h10a:9'd0;
                            state<=RETIRE;
                        end
                    end
                end
                DRAIN:if(!I_engine_busy&&!I_uop_busy)state<=RETIRE;
                RETIRE:begin
                    if(I_cancel||I_start)begin
                        result_good<=0;pending_error<=I_cancel?9'h104:9'h108;
                    end
                    if(I_released)begin
                        O_done<=1;O_valid<=result_good&&!I_cancel&&!I_start;
                        O_error<=I_cancel?4'd4:I_start?4'd6:error_map(pending_error);
                        O_diagnostic_error<=I_cancel?9'h104:I_start?9'h108:pending_error;
                        if(!result_good||I_cancel||I_start)O_sample_complete<=0;
                        state<=IDLE;
                    end
                end
                LOCKED:begin O_sample_complete<=0;end
                default:begin pending_error<=9'h1ff;result_good<=0;state<=DRAIN;end
            endcase
        end
    end
endmodule
