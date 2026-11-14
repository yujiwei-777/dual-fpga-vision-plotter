`timescale 1ns/1ps
// Frozen v3b16-patch gray outline geometry. Shared RAM/stats/NCC have one owner
// for a complete transaction, including cancellation drain. This controller
// never uses a PCB anomaly score to rescue unreliable geometry.
module pcb_outline_geometry_controller #(
    parameter integer WAIT_TIMEOUT=1000000,
    parameter integer ABORT_TIMEOUT=100000,
    parameter [14:0] CANONICAL_BASE=15'd8192,
    parameter [14:0] OUTLINE_BASE=15'd6284,
    parameter [14:0] DESCRIPTOR_BASE=15'd6636
)(
    input wire I_clk,I_rst_n,I_start,I_cancel,
    input wire I_board_convex,I_board_inside_safe_frame,
    output wire O_ready,O_idle,O_engine_cancel,
    output reg O_done,O_result_valid,O_registration_valid,O_outline_complete,
    output reg [3:0] O_error,
    output reg [15:0] O_support_mask,
    output reg O_patch_done,
    output reg [3:0] O_patch_index,
    output reg O_patch_best_valid,O_patch_supported,
    output reg [30:0] O_patch_best_score2_q30,
    output reg signed [1:0] O_patch_best_dx,O_patch_best_dy,
    output wire O_ram_request,O_ram_bank,
    output wire [14:0] O_ram_addr,
    input wire I_ram_ready,I_ram_valid,I_ram_idle,
    input wire [15:0] I_ram_data,
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
    localparam IDLE=0,DESC_REQ=1,DESC_WAIT=2,DESC_CHECK=3,SHIFT_INIT=4,
        STATS_START=5,IMAGE_REQ=6,IMAGE_WAIT=7,REFERENCE_REQ=8,REFERENCE_WAIT=9,
        SUBMIT=10,STEP_X=11,STEP_Y=12,STATS_WAIT=13,NORM_START=14,NORM_WAIT=15,
        SHIFT_END=16,PATCH_END=17,FINISH=18,DRAIN=19,LOCKED=20;
    reg [4:0] state;
    reg [3:0] patch,descriptor_word,shift_index;
    reg [7:0] descriptor_index,descriptor_kind,x0,y0,x1,y1,nx,ny;
    reg [15:0] reference_offset,sample_count,reference_sum,reserved;
    reg [31:0] reference_variance,threshold;
    reg [5:0] sample_index;
    reg [2:0] column,row;
    reg [7:0] x,y,x_remainder,y_remainder;
    reg [7:0] observed,reference;
    reg best_valid;
    reg [30:0] best_score;
    reg signed [1:0] best_dx,best_dy;
    reg board_convex,board_inside,pending;
    reg [31:0] wait_count;

    function signed [1:0] shift_x;
        input [3:0] index;
        begin case(index)
            2,5,7:shift_x=-2'sd1;
            3,6,8:shift_x=2'sd1;
            default:shift_x=2'sd0;
        endcase end
    endfunction
    function signed [1:0] shift_y;
        input [3:0] index;
        begin case(index)
            1,5,6:shift_y=-2'sd1;
            4,7,8:shift_y=2'sd1;
            default:shift_y=2'sd0;
        endcase end
    endfunction
    wire signed [9:0] image_x=$signed({2'b00,x})+shift_x(shift_index);
    wire signed [9:0] image_y=$signed({2'b00,y})+shift_y(shift_index);
    wire coordinates_valid=image_x>=0 && image_x<192 && image_y>=0 && image_y<96;
    wire [9:0] reference_byte=reference_offset[9:0]+{4'd0,sample_index};
    wire [14:0] image_row_words={2'd0,image_y[6:0],6'd0}+{3'd0,image_y[6:0],5'd0};
    wire [7:0] x_den=nx-8'd1;
    wire [7:0] y_den=ny-8'd1;
    wire ram_accept=O_ram_request && I_ram_ready;
    wire ram_response=I_ram_valid && (pending || ram_accept);
    wire engines_idle=I_ram_idle && !pending && !I_stats_busy && !I_norm_busy;
    wire descriptor_valid=descriptor_index=={4'd0,patch} && descriptor_kind==(patch<4 ? 0:1) &&
        x0>=1 && x1<=190 && y0>=1 && y1<=94 && x0<x1 && y0<y1 &&
        (patch<4 ? (nx==8 && ny==8 && sample_count==64) :
          (((nx==8 && ny==4)||(nx==4 && ny==8)) && sample_count==32)) &&
        {1'b0,reference_offset}+(patch<4 ? 17'd64:17'd32)<=17'd640 &&
        reference_sum!=0 && reference_variance>=32'd16384 &&
        threshold!=0 && threshold<=32'd1073741824 && reserved==0;
    wire patch_supported=best_valid && best_score>0 && {1'b0,best_score}>=threshold;
    wire [2:0] corners={2'd0,O_support_mask[0]}+{2'd0,O_support_mask[1]}+
                       {2'd0,O_support_mask[2]}+{2'd0,O_support_mask[3]};
    wire [3:0] edges={3'd0,O_support_mask[4]}+{3'd0,O_support_mask[5]}+{3'd0,O_support_mask[6]}+
        {3'd0,O_support_mask[7]}+{3'd0,O_support_mask[8]}+{3'd0,O_support_mask[9]}+
        {3'd0,O_support_mask[10]}+{3'd0,O_support_mask[11]}+{3'd0,O_support_mask[12]}+
        {3'd0,O_support_mask[13]}+{3'd0,O_support_mask[14]}+{3'd0,O_support_mask[15]};
    wire [4:0] total={2'd0,corners}+{1'd0,edges};
    wire [2:0] top={2'd0,O_support_mask[0]}+{2'd0,O_support_mask[1]}+
        {2'd0,O_support_mask[4]}+{2'd0,O_support_mask[5]}+{2'd0,O_support_mask[6]}+{2'd0,O_support_mask[7]};
    wire [2:0] bottom={2'd0,O_support_mask[2]}+{2'd0,O_support_mask[3]}+
        {2'd0,O_support_mask[8]}+{2'd0,O_support_mask[9]}+{2'd0,O_support_mask[10]}+{2'd0,O_support_mask[11]};
    wire left=O_support_mask[0]||O_support_mask[2]||O_support_mask[12]||O_support_mask[13];
    wire right=O_support_mask[1]||O_support_mask[3]||O_support_mask[14]||O_support_mask[15];
    wire q0=O_support_mask[0]||O_support_mask[4]||O_support_mask[5]||O_support_mask[12];
    wire q1=O_support_mask[1]||O_support_mask[6]||O_support_mask[7]||O_support_mask[14];
    wire q2=O_support_mask[2]||O_support_mask[8]||O_support_mask[9]||O_support_mask[13];
    wire q3=O_support_mask[3]||O_support_mask[10]||O_support_mask[11]||O_support_mask[15];

    assign O_idle=state==IDLE && engines_idle;
    assign O_ready=O_idle && !I_cancel;
    assign O_engine_cancel=state==DRAIN || state==LOCKED;
    assign O_ram_request=(state==DESC_REQ || state==IMAGE_REQ || state==REFERENCE_REQ) && !I_cancel;
    assign O_ram_bank=state!=IMAGE_REQ && state!=IMAGE_WAIT;
    assign O_ram_addr=(state==DESC_REQ || state==DESC_WAIT) ? DESCRIPTOR_BASE+{7'd0,patch,3'd0}+{8'd0,patch,2'd0}+descriptor_word :
        (state==IMAGE_REQ || state==IMAGE_WAIT) ? CANONICAL_BASE+image_row_words+{8'd0,image_x[7:1]} :
        OUTLINE_BASE+{6'd0,reference_byte[9:1]};
    assign O_stats_start=state==STATS_START && !I_stats_busy && !I_cancel;
    assign O_stats_count_log2=patch<4 ? 4'd6:4'd5;
    assign O_stats_sample_valid=state==SUBMIT && !I_cancel;
    assign O_stats_i=observed;
    assign O_stats_t=reference;
    assign O_norm_start=state==NORM_START && !I_norm_busy && !I_cancel;
    assign O_norm_covariance=I_covariance;
    assign O_norm_variance_i=I_variance_i;
    assign O_norm_variance_t=I_variance_t;

    task drain;
        input [3:0] code;
        begin O_result_valid<=0;O_registration_valid<=0;O_outline_complete<=0;O_error<=code;
              wait_count<=0;state<=DRAIN;end
    endtask
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;patch<=0;descriptor_word<=0;shift_index<=0;
            descriptor_index<=0;descriptor_kind<=0;x0<=0;y0<=0;x1<=0;y1<=0;nx<=0;ny<=0;
            reference_offset<=0;sample_count<=0;reference_sum<=0;reference_variance<=0;threshold<=0;reserved<=0;
            sample_index<=0;column<=0;row<=0;x<=0;y<=0;x_remainder<=0;y_remainder<=0;
            observed<=0;reference<=0;best_valid<=0;best_score<=0;best_dx<=0;best_dy<=0;
            board_convex<=0;board_inside<=0;pending<=0;wait_count<=0;
            O_done<=0;O_result_valid<=0;O_registration_valid<=0;O_outline_complete<=0;O_error<=0;
            O_support_mask<=0;O_patch_done<=0;O_patch_index<=0;O_patch_best_valid<=0;O_patch_supported<=0;
            O_patch_best_score2_q30<=0;O_patch_best_dx<=0;O_patch_best_dy<=0;
        end else begin
            O_done<=0;O_patch_done<=0;
            if(ram_accept)pending<=1;
            if(ram_response)pending<=0;
            if(state==LOCKED)state<=LOCKED;
            else if(I_cancel && state!=IDLE && state!=DRAIN)drain(4'd1);
            else if(I_start && state!=IDLE && state!=DRAIN)drain(4'd2);
            else case(state)
                IDLE:if(I_start && O_ready)begin
                    board_convex<=I_board_convex;board_inside<=I_board_inside_safe_frame;
                    O_result_valid<=0;O_registration_valid<=0;O_outline_complete<=0;O_error<=0;O_support_mask<=0;
                    patch<=0;descriptor_word<=0;wait_count<=0;state<=DESC_REQ;
                end
                DESC_REQ,DESC_WAIT:if(ram_response)begin
                    case(descriptor_word)
                        0:begin descriptor_index<=I_ram_data[7:0];descriptor_kind<=I_ram_data[15:8];end
                        1:begin x0<=I_ram_data[7:0];y0<=I_ram_data[15:8];end
                        2:begin x1<=I_ram_data[7:0];y1<=I_ram_data[15:8];end
                        3:begin nx<=I_ram_data[7:0];ny<=I_ram_data[15:8];end
                        4:reference_offset<=I_ram_data;
                        5:sample_count<=I_ram_data;
                        6:reference_sum<=I_ram_data;
                        7:reference_variance[15:0]<=I_ram_data;
                        8:reference_variance[31:16]<=I_ram_data;
                        9:threshold[15:0]<=I_ram_data;
                        10:threshold[31:16]<=I_ram_data;
                        11:reserved<=I_ram_data;
                    endcase
                    wait_count<=0;
                    if(descriptor_word==11)state<=DESC_CHECK;
                    else begin descriptor_word<=descriptor_word+4'd1;state<=DESC_REQ;end
                end else if(wait_count>=WAIT_TIMEOUT-1)drain(4'd3);
                else begin wait_count<=wait_count+32'd1;if(ram_accept)state<=DESC_WAIT;end
                DESC_CHECK:if(!descriptor_valid)drain(4'd4);
                else begin shift_index<=0;best_valid<=0;best_score<=0;best_dx<=0;best_dy<=0;state<=SHIFT_INIT;end
                SHIFT_INIT:begin
                    sample_index<=0;column<=0;row<=0;x<=x0;y<=y0;
                    x_remainder<=x_den>>1;y_remainder<=y_den>>1;
                    wait_count<=0;state<=STATS_START;
                end
                STATS_START:if(!I_stats_busy)begin wait_count<=0;state<=IMAGE_REQ;end
                else if(wait_count>=WAIT_TIMEOUT-1)drain(4'd3);
                else wait_count<=wait_count+32'd1;
                IMAGE_REQ,IMAGE_WAIT:if(!coordinates_valid)drain(4'd5);
                else if(ram_response)begin
                    observed<=image_x[0]?I_ram_data[15:8]:I_ram_data[7:0];wait_count<=0;state<=REFERENCE_REQ;
                end else if(wait_count>=WAIT_TIMEOUT-1)drain(4'd3);
                else begin wait_count<=wait_count+32'd1;if(ram_accept)state<=IMAGE_WAIT;end
                REFERENCE_REQ,REFERENCE_WAIT:if(ram_response)begin
                    reference<=reference_byte[0]?I_ram_data[15:8]:I_ram_data[7:0];wait_count<=0;state<=SUBMIT;
                end else if(wait_count>=WAIT_TIMEOUT-1)drain(4'd3);
                else begin wait_count<=wait_count+32'd1;if(ram_accept)state<=REFERENCE_WAIT;end
                SUBMIT:if(I_stats_ready)begin
                    wait_count<=0;
                    if({10'd0,sample_index}+16'd1==sample_count)state<=STATS_WAIT;
                    else begin
                        sample_index<=sample_index+6'd1;
                        if({5'd0,column}+8'd1==nx)begin
                            column<=0;row<=row+3'd1;x<=x0;x_remainder<=x_den>>1;
                            y_remainder<=y_remainder+(y1-y0);state<=STEP_Y;
                        end else begin column<=column+3'd1;x_remainder<=x_remainder+(x1-x0);state<=STEP_X;end
                    end
                end else if(wait_count>=WAIT_TIMEOUT-1)drain(4'd3);
                else wait_count<=wait_count+32'd1;
                STEP_X:if(x_remainder>=x_den)begin x_remainder<=x_remainder-x_den;x<=x+8'd1;end
                else state<=IMAGE_REQ;
                STEP_Y:if(y_remainder>=y_den)begin y_remainder<=y_remainder-y_den;y<=y+8'd1;end
                else state<=IMAGE_REQ;
                STATS_WAIT:if(I_stats_done)begin
                    wait_count<=0;
                    if(!I_stats_valid || I_variance_t!={4'd0,reference_variance})drain(4'd6);
                    else if(I_covariance<=0 || I_variance_i==0)state<=SHIFT_END;
                    else state<=NORM_START;
                end else if(wait_count>=WAIT_TIMEOUT-1)drain(4'd3);
                else wait_count<=wait_count+32'd1;
                NORM_START:if(!I_norm_busy)begin wait_count<=0;state<=NORM_WAIT;end
                else if(wait_count>=WAIT_TIMEOUT-1)drain(4'd3);
                else wait_count<=wait_count+32'd1;
                NORM_WAIT:if(I_norm_done)begin
                    wait_count<=0;
                    if(!I_norm_valid || I_norm_error!=0)drain(4'd7);
                    else begin
                        if(I_norm_positive && I_norm_score2_q30>0 && (!best_valid || I_norm_score2_q30>best_score))begin
                            best_valid<=1;best_score<=I_norm_score2_q30;
                            best_dx<=shift_x(shift_index);best_dy<=shift_y(shift_index);
                        end
                        state<=SHIFT_END;
                    end
                end else if(wait_count>=WAIT_TIMEOUT-1)drain(4'd3);
                else wait_count<=wait_count+32'd1;
                SHIFT_END:if(shift_index==8)state<=PATCH_END;
                else begin shift_index<=shift_index+4'd1;state<=SHIFT_INIT;end
                PATCH_END:begin
                    O_support_mask[patch]<=patch_supported;O_patch_done<=1;O_patch_index<=patch;
                    O_patch_best_valid<=best_valid;O_patch_best_score2_q30<=best_score;
                    O_patch_best_dx<=best_dx;O_patch_best_dy<=best_dy;O_patch_supported<=patch_supported;
                    if(patch==15)state<=FINISH;
                    else begin patch<=patch+4'd1;descriptor_word<=0;state<=DESC_REQ;end
                end
                FINISH:begin
                    O_done<=1;O_result_valid<=1;O_error<=0;O_outline_complete<=&O_support_mask;
                    O_registration_valid<=board_convex && board_inside && total>=12 && corners>=2 &&
                        top>=3 && bottom>=3 && left && right && q0 && q1 && q2 && q3;
                    state<=IDLE;
                end
                DRAIN:if(engines_idle)begin O_done<=1;state<=IDLE;end
                else if(wait_count>=ABORT_TIMEOUT-1)begin O_done<=1;O_error<=4'd9;state<=LOCKED;end
                else wait_count<=wait_count+32'd1;
                default:begin O_done<=1;O_result_valid<=0;O_error<=4'd15;state<=LOCKED;end
            endcase
        end
    end
endmodule
