`timescale 1ns/1ps
// Bounded v1c coordinate-descent scheduler. The external objective owns ALL
// numeric sampling, geometry guards and positive-C Q30 correlation arithmetic.
// This module alone never validates PCB geometry or declares PCB PASS.
// Job IDs must not be reused while stale tagged objective responses can exist.
module pcb_refinement_search #(
    parameter integer EVAL_TIMEOUT=10000000,
    parameter integer ABORT_TIMEOUT=100000
) (
    input wire I_clk,I_rst_n,I_start,I_cancel,
    input wire [16:0] I_job_id,
    output wire O_eval_valid,
    input wire I_eval_ready,
    output wire [26:0] O_eval_tag,
    output wire O_eval_div2,
    output wire [255:0] O_eval_parameters,
    output wire O_eval_cancel,
    input wire I_eval_idle,I_eval_done,I_eval_score_valid,
    input wire [26:0] I_eval_tag,
    input wire [30:0] I_eval_score2_q30,
    output wire O_busy,
    output reg O_done,O_result_valid,O_fault,
    output reg [3:0] O_error,
    output wire [255:0] O_parameters,
    output reg [9:0] O_evaluations,
    output reg [30:0] O_final_score2_q30
);
    localparam IDLE=0,REQUEST=1,WAIT=2,ENTER_PARAM=3,SWEEP_END=4,
               NEXT_STEP=5,FINISH=6,DRAIN=7,LOCKED=8;
    reg [3:0] state;
    reg signed [31:0] parameters[0:7];
    reg signed [31:0] trial_value;
    reg [16:0] job_id;
    reg [9:0] eval_index;
    reg level,initial_eval,plus_trial,current_valid,minus_valid,minus_better,sweep_changed;
    reg [30:0] current_score,minus_score;
    reg [2:0] step_index,sweep_index,parameter_index;
    reg [31:0] wait_count;
    reg [3:0] abort_error;
    wire [2:0] slot=parameter_index==0 ? 3'd2 : parameter_index==1 ? 3'd5 :
                    parameter_index==2 ? 3'd0 : parameter_index==3 ? 3'd4 :
                    parameter_index==4 ? 3'd1 : parameter_index==5 ? 3'd3 :
                    parameter_index==6 ? 3'd6 : 3'd7;
    reg signed [31:0] increment;
    always @* begin
        if(slot<6) begin
            if(!level)case(step_index)
                0:increment=524288;1:increment=262144;2:increment=131072;default:increment=65536;
            endcase
            else case(step_index)
                0:increment=65536;1:increment=32768;2:increment=16384;3:increment=8192;default:increment=4096;
            endcase
        end else begin
            if(!level)case(step_index)
                0:increment=1398101;1:increment=699050;2:increment=349525;default:increment=174762;
            endcase
            else case(step_index)
                0:increment=174762;1:increment=87381;2:increment=43690;3:increment=21845;default:increment=10922;
            endcase
        end
    end
    genvar i;
    generate for(i=0;i<8;i=i+1)begin:g_parameter_outputs
        assign O_parameters[32*i+:32]=parameters[i];
        assign O_eval_parameters[32*i+:32]=!initial_eval && slot==i ? trial_value : parameters[i];
    end endgenerate
    assign O_busy=state!=IDLE;
    assign O_eval_valid=state==REQUEST && !I_start && !I_cancel;
    assign O_eval_tag={job_id,eval_index};
    assign O_eval_div2=!level;
    assign O_eval_cancel=state==DRAIN || state==LOCKED;
    wire accepted=O_eval_valid && I_eval_ready;
    wire response=I_eval_done && I_eval_tag==O_eval_tag &&
                  (state==WAIT || accepted);
    wire score_ok=I_eval_score_valid && I_eval_score2_q30<=31'h40000000;
    wire beats_current=score_ok && (!current_valid || I_eval_score2_q30>current_score);
    wire beats_minus=score_ok && (!minus_valid || I_eval_score2_q30>minus_score);
    integer k;
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;job_id<=0;eval_index<=0;level<=0;initial_eval<=0;plus_trial<=0;
            current_valid<=0;minus_valid<=0;minus_better<=0;sweep_changed<=0;
            current_score<=0;minus_score<=0;step_index<=0;sweep_index<=0;parameter_index<=0;
            trial_value<=0;wait_count<=0;abort_error<=0;
            O_done<=0;O_result_valid<=0;O_fault<=0;O_error<=0;O_evaluations<=0;O_final_score2_q30<=0;
            for(k=0;k<8;k=k+1)parameters[k]<=0;
        end else begin
            O_done<=0;
            if(state==LOCKED)state<=LOCKED;
            else if(state!=IDLE && state!=DRAIN && (I_cancel || I_start))begin
                abort_error<=I_cancel ? 4'd2 : 4'd3;
                O_result_valid<=0;wait_count<=0;state<=DRAIN;
            end else case(state)
                IDLE:if(I_start && !I_cancel)begin
                    job_id<=I_job_id;eval_index<=0;O_evaluations<=0;
                    parameters[0]<=6291456;parameters[1]<=0;parameters[2]<=0;parameters[3]<=0;
                    parameters[4]<=3145728;parameters[5]<=0;parameters[6]<=0;parameters[7]<=0;
                    level<=0;step_index<=0;sweep_index<=0;parameter_index<=0;sweep_changed<=0;
                    initial_eval<=1;current_valid<=0;current_score<=0;wait_count<=0;
                    O_result_valid<=0;O_fault<=0;O_error<=0;O_final_score2_q30<=0;state<=REQUEST;
                end
                REQUEST,WAIT:begin
                    if(accepted)O_evaluations<=O_evaluations+10'd1;
                    if(response)begin
                        eval_index<=eval_index+10'd1;wait_count<=0;
                        if(initial_eval)begin
                            current_valid<=score_ok;current_score<=score_ok ? I_eval_score2_q30 : 31'd0;
                            initial_eval<=0;state<=ENTER_PARAM;
                        end else if(!plus_trial)begin
                            minus_better<=beats_current;
                            minus_valid<=beats_current ? 1'b1 : current_valid;
                            minus_score<=beats_current ? I_eval_score2_q30 : current_score;
                            trial_value<=parameters[slot]+increment;
                            plus_trial<=1;state<=REQUEST;
                        end else begin
                            if(beats_minus)begin
                                parameters[slot]<=trial_value;current_score<=I_eval_score2_q30;
                                current_valid<=1;sweep_changed<=1;
                            end else begin
                                if(minus_better)begin parameters[slot]<=parameters[slot]-increment;sweep_changed<=1;end
                                current_score<=minus_score;current_valid<=minus_valid;
                            end
                            if(parameter_index==7)state<=SWEEP_END;
                            else begin parameter_index<=parameter_index+3'd1;state<=ENTER_PARAM;end
                        end
                    end else if(wait_count>=EVAL_TIMEOUT-1)begin
                        abort_error<=4'd4;O_result_valid<=0;wait_count<=0;state<=DRAIN;
                    end else begin
                        wait_count<=wait_count+32'd1;
                        if(accepted)state<=WAIT;
                    end
                end
                ENTER_PARAM:begin
                    trial_value<=parameters[slot]-increment;
                    plus_trial<=0;wait_count<=0;state<=REQUEST;
                end
                SWEEP_END:begin
                    parameter_index<=0;
                    if(sweep_changed && sweep_index<5)begin
                        sweep_index<=sweep_index+3'd1;sweep_changed<=0;state<=ENTER_PARAM;
                    end else state<=NEXT_STEP;
                end
                NEXT_STEP:begin
                    sweep_index<=0;sweep_changed<=0;
                    if((!level && step_index<3) || (level && step_index<4))begin
                        step_index<=step_index+3'd1;state<=ENTER_PARAM;
                    end else if(!level)begin
                        level<=1;step_index<=0;initial_eval<=1;wait_count<=0;state<=REQUEST;
                    end else state<=FINISH;
                end
                FINISH:begin
                    O_done<=1;O_result_valid<=current_valid;O_fault<=!current_valid;
                    O_error<=current_valid ? 4'd0 : 4'd5;
                    O_final_score2_q30<=current_valid ? current_score : 31'd0;state<=IDLE;
                end
                DRAIN:begin
                    if(I_eval_idle)begin
                        O_done<=1;O_fault<=1;O_error<=abort_error;O_result_valid<=0;state<=IDLE;
                    end else if(wait_count>=ABORT_TIMEOUT-1)begin
                        O_done<=1;O_fault<=1;O_error<=4'd6;O_result_valid<=0;state<=LOCKED;
                    end else wait_count<=wait_count+32'd1;
                end
                default:begin
                    O_done<=1;O_fault<=1;O_error<=4'd15;O_result_valid<=0;state<=LOCKED;
                end
            endcase
        end
    end
endmodule
