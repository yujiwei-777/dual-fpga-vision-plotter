// Integrated affine6 persistent-RF scheduler candidate; runtime qualification pending.
// The context owns numerical fine values; no parallel parameter output.
`timescale 1ns/1ps
// Bounded v1c coordinate-descent scheduler. The external objective owns ALL
// numeric sampling, geometry guards and positive-C Q30 correlation arithmetic.
// This module alone never validates PCB geometry or declares PCB PASS.
// Job IDs must not be reused while stale tagged objective responses can exist.
module pcb_refinement_search_persistent_rf_affine6 #(
    parameter integer EVAL_TIMEOUT=10000000,
    parameter integer ABORT_TIMEOUT=100000
) (
    input wire I_clk,I_rst_n,I_start,I_cancel,
    input wire [16:0] I_job_id,
    output wire O_eval_valid,
    input wire I_eval_ready,
    output wire [26:0] O_eval_tag,
    output wire O_eval_div2,
    output wire O_context_valid,O_context_cancel,
    input wire I_context_ready,I_context_busy,I_context_done,
    input wire [1:0] I_context_error,
    output wire [2:0] O_context_command,O_context_slot,
    output wire [1:0] O_context_choice,
    output wire signed [25:0] O_context_increment,
    output wire O_eval_cancel,
    input wire I_eval_idle,I_eval_done,I_eval_score_valid,
    input wire [3:0] I_eval_error,
    input wire [26:0] I_eval_tag,
    input wire [30:0] I_eval_score2_q30,
    output wire O_busy,
    output reg O_done,O_result_valid,O_fault,
    output reg [3:0] O_error,
    output reg [3:0] O_objective_error,
    output reg [9:0] O_evaluations,
    output reg [30:0] O_final_score2_q30
);
    localparam IDLE=0,REQUEST=1,WAIT=2,ENTER_PARAM=3,SWEEP_END=4,
               NEXT_STEP=5,FINISH=6,DRAIN=7,LOCKED=8,CONTEXT_REQUEST=9,CONTEXT_WAIT=10,AFTER_RESOLVE=11;
    reg [3:0] state;
    // Nine step sizes, <=6 sweeps and six affine slots are unchanged from R1.
    // The conservative affine bound is +/-12951552; RF values stay signed32.
    // No perspective parameter participates in the affine6 schedule.
    localparam integer PARAM_BITS=26;
    function integer counter_bits;
        input integer limit;
        integer remaining;
        begin counter_bits=1;remaining=limit-1;
            while(remaining>1)begin counter_bits=counter_bits+1;remaining=remaining>>1;end
        end
    endfunction
    localparam integer WAIT_LIMIT=(EVAL_TIMEOUT>ABORT_TIMEOUT)?EVAL_TIMEOUT:ABORT_TIMEOUT;
    localparam integer WAIT_BITS=counter_bits(WAIT_LIMIT);
    reg [2:0] context_command;
    reg [1:0] context_choice;
    reg [3:0] context_return;
    reg [16:0] job_id;
    reg [9:0] eval_index;
    reg level,initial_eval,plus_trial,current_valid,minus_valid,minus_better,sweep_changed;
    reg [30:0] current_score,minus_score;
    reg [2:0] step_index,sweep_index,parameter_index;
    reg [WAIT_BITS-1:0] wait_count;
    reg [3:0] abort_error;
    wire [2:0] slot=parameter_index==0 ? 3'd2 : parameter_index==1 ? 3'd5 :
                    parameter_index==2 ? 3'd0 : parameter_index==3 ? 3'd4 :
                    parameter_index==4 ? 3'd1 : 3'd3;
    reg signed [PARAM_BITS-1:0] increment;
    always @* begin
        if(!level)case(step_index)
            0:increment=524288;1:increment=262144;2:increment=131072;default:increment=65536;
        endcase
        else case(step_index)
            0:increment=65536;1:increment=32768;2:increment=16384;3:increment=8192;default:increment=4096;
        endcase
    end
    assign O_context_valid=state==CONTEXT_REQUEST&&!I_start&&!I_cancel;
    assign O_context_cancel=state==DRAIN||state==LOCKED;
    assign O_context_command=context_command;
    assign O_context_choice=context_choice;
    assign O_context_slot=slot;
    assign O_context_increment=increment;
    task call_context;
        input [2:0] command;
        input [1:0] choice;
        input [3:0] next_state;
        begin context_command<=command;context_choice<=choice;context_return<=next_state;
            wait_count<=0;state<=CONTEXT_REQUEST;end
    endtask
    assign O_busy=state!=IDLE;
    assign O_eval_valid=state==REQUEST && !I_start && !I_cancel;
    assign O_eval_tag={job_id,eval_index};
    assign O_eval_div2=!level;
    assign O_eval_cancel=state==DRAIN || state==LOCKED;
    wire accepted=O_eval_valid && I_eval_ready;
    wire response=I_eval_done && I_eval_tag==O_eval_tag &&
                  (state==WAIT || accepted);
    wire score_ok=I_eval_score_valid && I_eval_score2_q30<=31'h40000000;
    // Minus trials compare the incumbent; plus trials compare the
    // winning minus/incumbent. Only one comparison can be consumed per reply.
    wire [30:0] reference_score=plus_trial?minus_score:current_score;
    wire reference_valid=plus_trial?minus_valid:current_valid;
    wire beats_reference=score_ok && (!reference_valid || I_eval_score2_q30>reference_score);
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;job_id<=0;eval_index<=0;level<=0;initial_eval<=0;plus_trial<=0;
            current_valid<=0;minus_valid<=0;minus_better<=0;sweep_changed<=0;
            current_score<=0;minus_score<=0;step_index<=0;sweep_index<=0;parameter_index<=0;
            context_command<=0;context_choice<=0;context_return<=0;wait_count<=0;abort_error<=0;
            O_done<=0;O_result_valid<=0;O_fault<=0;O_error<=0;O_objective_error<=0;O_evaluations<=0;O_final_score2_q30<=0;
        end else begin
            O_done<=0;
            if(state==LOCKED)state<=LOCKED;
            else if(state!=IDLE && state!=DRAIN && (I_cancel || I_start))begin
                abort_error<=I_cancel ? 4'd2 : 4'd3;
                O_result_valid<=0;wait_count<=0;state<=DRAIN;
            end else case(state)
                IDLE:if(I_start && !I_cancel)begin
                    job_id<=I_job_id;eval_index<=0;O_evaluations<=0;
                    level<=0;step_index<=0;sweep_index<=0;parameter_index<=0;sweep_changed<=0;
                    initial_eval<=1;current_valid<=0;current_score<=0;wait_count<=0;
                    O_result_valid<=0;O_fault<=0;O_error<=0;O_objective_error<=0;O_final_score2_q30<=0;call_context(0,0,REQUEST);
                end
                REQUEST,WAIT:begin
                    if(accepted)O_evaluations<=O_evaluations+10'd1;
                    if(response)begin
                        eval_index<=eval_index+10'd1;wait_count<=0;
                        // A hard objective fault invalidates this whole job, even
                        // after a valid incumbent. Never reinterpret it as a weak trial.
                        if(I_eval_error!=0 || (I_eval_score_valid && I_eval_score2_q30>31'h40000000))begin
                            O_objective_error<=I_eval_error!=0 ? I_eval_error : 4'd14;
                            abort_error<=4'd7;O_result_valid<=0;current_valid<=0;
                            wait_count<=0;state<=DRAIN;
                        end else if(initial_eval)begin
                            current_valid<=score_ok;current_score<=score_ok ? I_eval_score2_q30 : 31'd0;
                            initial_eval<=0;state<=ENTER_PARAM;
                        end else if(!plus_trial)begin
                            minus_better<=beats_reference;
                            minus_valid<=beats_reference ? 1'b1 : current_valid;
                            minus_score<=beats_reference ? I_eval_score2_q30 : current_score;
                            plus_trial<=1;call_context(2,0,REQUEST);
                        end else begin
                            if(beats_reference)begin
                                current_score<=I_eval_score2_q30;
                                current_valid<=1;sweep_changed<=1;
                            end else begin
                                if(minus_better)sweep_changed<=1;
                                current_score<=minus_score;current_valid<=minus_valid;
                            end
                            call_context(3,beats_reference?2:minus_better?1:0,AFTER_RESOLVE);
                        end
                    end else if(wait_count>=EVAL_TIMEOUT-1)begin
                        abort_error<=4'd4;O_result_valid<=0;wait_count<=0;state<=DRAIN;
                    end else begin
                        wait_count<=wait_count+1'b1;
                        if(accepted)state<=WAIT;
                    end
                end
                ENTER_PARAM:begin plus_trial<=0;call_context(1,0,REQUEST);end
                AFTER_RESOLVE:begin
                    if(parameter_index==5)state<=SWEEP_END;
                    else begin parameter_index<=parameter_index+3'd1;state<=ENTER_PARAM;end
                end
                CONTEXT_REQUEST,CONTEXT_WAIT:begin
                    if(I_context_done&&(state==CONTEXT_WAIT||(O_context_valid&&I_context_ready)))begin
                        wait_count<=0;
                        if(I_context_error!=0)begin abort_error<=8;O_result_valid<=0;state<=DRAIN;end
                        else state<=context_return;
                    end else if(wait_count>=EVAL_TIMEOUT-1)begin
                        abort_error<=4;O_result_valid<=0;wait_count<=0;state<=DRAIN;
                    end else begin
                        wait_count<=wait_count+1'b1;
                        if(O_context_valid&&I_context_ready)state<=CONTEXT_WAIT;
                    end
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
                    if(I_eval_idle&&!I_context_busy)begin
                        O_done<=1;O_fault<=1;O_error<=abort_error;O_result_valid<=0;state<=IDLE;
                    end else if(wait_count>=ABORT_TIMEOUT-1)begin
                        O_done<=1;O_fault<=1;O_error<=4'd6;O_result_valid<=0;state<=LOCKED;
                    end else wait_count<=wait_count+1'b1;
                end
                default:begin
                    O_done<=1;O_fault<=1;O_error<=4'd15;O_result_valid<=0;state<=LOCKED;
                end
            endcase
        end
    end
endmodule
