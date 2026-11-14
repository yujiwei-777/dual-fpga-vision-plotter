`timescale 1ns/1ps
// Integrated owner6 RF context candidate; runtime qualification pending.
// Borrows the existing private RF, ALU32 and R32. Only old_value is numerical
// storage added here. The caller holds command/slot/increment/choice until done.
// INIT=0, MINUS=1, PLUS=2, RESOLVE=3, SPILL=4, RESTORE=5.
// RESOLVE choice: 0=old, 1=minus, 2=keep the plus already in RF.
// SPILL/RESTORE are legal only between a retired WARP and raw geometry, with
// no other RF user. Physical90..123 are dead WARP scratch and raw never writes
// them. This temporary copy stays inside the EXISTING RF, not a second bank.
module pcb_fine_persistent_rf_context_candidate(
    input wire clk,rst_n,I_cancel,I_fault,I_grant,I_cmd_valid,
    input wire I_epoch_start,I_coarse_loaded,I_released,
    input wire [2:0] I_command,I_slot,
    input wire [1:0] I_choice,
    input wire signed [25:0] I_increment,
    output wire O_cmd_ready,O_busy,O_retiring,
    output reg O_done,
    output reg [1:0] O_error,
    output reg O_fine_present,O_coarse_present,O_spilled,O_dirty,
    output reg [6:0] O_rf_a_addr,O_rf_b_addr,
    output reg O_rf_we,
    output reg [15:0] O_rf_wdata,
    input wire [15:0] I_rf_a_data,I_rf_b_data,
    input wire [31:0] I_r,
    output reg O_r_we,
    output reg [31:0] O_r_data,O_alu_a,O_alu_b,
    output reg O_alu_carry,
    input wire [32:0] I_alu_sum
);
    localparam IDLE=0,INIT_WRITE=1,OLD_WAIT=2,OLD_CAPTURE=3,EXEC=4,
        WRITE_LOW=5,WRITE_HIGH=6,COPY_WAIT=7,COPY_CAPTURE=8,COPY_WRITE=9,
        FINISH=10,RETIRE=11;
    reg [3:0] state;
    reg [2:0] command;
    reg [5:0] index;
    reg [2:0] coarse_number;
    reg [1:0] coarse_limb;
    reg signed [25:0] old_value;
    reg old_valid;
    wire [31:0] old32={{6{old_value[25]}},old_value};
    wire [31:0] step32={{6{I_increment[25]}},I_increment};
    wire subtract=command==1 || (command==3 && I_choice==1);
    wire [6:0] parameter_low=7'd8+{3'd0,I_slot,1'b0};
    wire restoring=command==5;
    wire fine_limb=index<16;
    wire [6:0] copy_source=fine_limb?
        (restoring?7'd90+index:7'd8+index):restoring?
        7'd106+3*coarse_number+(coarse_limb==3?2:coarse_limb):
        7'd24+4*coarse_number+coarse_limb;
    wire [6:0] copy_destination=restoring?
        (fine_limb?7'd8+index:7'd24+4*coarse_number+coarse_limb):7'd90+index;
    assign O_cmd_ready=state==IDLE&&I_grant&&!I_cancel&&!I_fault&&!I_epoch_start;
    assign O_busy=state!=IDLE;
    assign O_retiring=state==RETIRE;
    always @*begin
        O_rf_a_addr=0;O_rf_b_addr=0;O_rf_we=0;O_rf_wdata=0;
        O_r_we=0;O_r_data=I_r;O_alu_a=old32;
        O_alu_b=subtract?~step32:step32;O_alu_carry=subtract;
        case(state)
            INIT_WRITE:begin
                O_rf_a_addr=7'd8+index;O_rf_we=1;
                // Initial vector [6291456,0,0,0,3145728,0,0,0].
                O_rf_wdata=index==1?16'd96:index==9?16'd48:16'd0;
            end
            OLD_WAIT,OLD_CAPTURE:begin
                O_rf_a_addr=parameter_low;O_rf_b_addr=parameter_low+1'b1;
            end
            EXEC:begin
                O_r_we=1;
                O_r_data=command==3&&I_choice==0?old32:I_alu_sum[31:0];
            end
            WRITE_LOW,WRITE_HIGH:begin
                O_rf_a_addr=parameter_low+(state==WRITE_HIGH);O_rf_we=1;
                O_rf_wdata=state==WRITE_LOW?I_r[15:0]:{{6{I_r[25]}},I_r[25:16]};
            end
            COPY_WAIT,COPY_CAPTURE:begin
                O_rf_a_addr=copy_source;
                if(state==COPY_CAPTURE)begin
                    O_r_we=1;
                    O_r_data=restoring&&!fine_limb&&coarse_limb==3?
                        {32{I_rf_a_data[7]}}:{16'd0,I_rf_a_data};
                end
            end
            COPY_WRITE:begin O_rf_a_addr=copy_destination;O_rf_we=1;O_rf_wdata=I_r[15:0];end
            default:begin end
        endcase
        if(I_cancel||I_fault||I_epoch_start||!I_grant)begin O_rf_we=0;O_r_we=0;end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin state<=IDLE;command<=0;index<=0;coarse_number<=0;coarse_limb<=0;
            old_value<=0;old_valid<=0;O_done<=0;O_error<=0;
            O_fine_present<=0;O_coarse_present<=0;O_spilled<=0;O_dirty<=0;end
        else begin
            O_done<=0;
            if(state==RETIRE)begin
                if(I_cancel||I_fault||I_epoch_start||(!I_grant&&!I_released))begin
                    O_error<=I_cancel?2'd1:2'd3;old_valid<=0;
                    O_fine_present<=0;O_coarse_present<=0;O_spilled<=0;O_dirty<=1;
                end
                if(I_released)begin O_done<=1;state<=IDLE;end
            end else if(I_cancel || I_fault || (state!=IDLE&&(!I_grant||I_epoch_start)))begin
                if(state!=IDLE)O_error<=I_cancel?2'd1:2'd3;
                // Completion waits for release even on an abort. No pending
                // external memory transaction exists in this bounded helper.
                O_done<=0;if(state!=IDLE)state<=RETIRE;
                old_valid<=0;O_fine_present<=0;O_coarse_present<=0;O_spilled<=0;O_dirty<=1;
            end else if(I_epoch_start)begin
                O_error<=0;old_valid<=0;O_fine_present<=0;O_coarse_present<=0;O_spilled<=0;O_dirty<=0;
            end else begin
              if(I_coarse_loaded&&!O_dirty&&!O_spilled)O_coarse_present<=1;
              case(state)
                IDLE:if(I_cmd_valid&&O_cmd_ready)begin
                    command<=I_command;index<=0;coarse_number<=0;coarse_limb<=0;O_error<=0;
                    if(O_dirty || ((I_command==1 || I_command==2 || I_command==3) && I_slot>5))begin
                        O_error<=2;state<=FINISH;
                    end
                    else case(I_command)
                        0:if(O_spilled)begin O_error<=2;state<=FINISH;end
                          else begin old_valid<=0;O_fine_present<=0;state<=INIT_WRITE;end
                        1:if(!O_fine_present||O_spilled||old_valid)begin O_error<=2;state<=FINISH;end
                          else state<=OLD_WAIT;
                        2:if(old_valid&&O_fine_present&&!O_spilled)state<=EXEC;else begin O_error<=2;state<=FINISH;end
                        3:if(!old_valid||!O_fine_present||O_spilled||I_choice==3)begin O_error<=2;state<=FINISH;end
                          else if(I_choice==2)begin old_valid<=0;state<=FINISH;end
                          else state<=EXEC;
                        4:if(old_valid||!O_fine_present||!O_coarse_present||O_spilled)begin O_error<=2;state<=FINISH;end
                          else state<=COPY_WAIT;
                        5:if(old_valid||!O_spilled)begin O_error<=2;state<=FINISH;end else state<=COPY_WAIT;
                        default:begin O_error<=2;state<=FINISH;end
                    endcase
                end
                INIT_WRITE:if(index==15)state<=FINISH;else index<=index+1'b1;
                OLD_WAIT:state<=OLD_CAPTURE;
                OLD_CAPTURE:begin old_value<={I_rf_b_data[9:0],I_rf_a_data};old_valid<=1;state<=EXEC;end
                EXEC:state<=WRITE_LOW;
                WRITE_LOW:state<=WRITE_HIGH;
                WRITE_HIGH:begin if(command==3)old_valid<=0;state<=FINISH;end
                COPY_WAIT:state<=COPY_CAPTURE;
                COPY_CAPTURE:state<=COPY_WRITE;
                COPY_WRITE:if(index==(restoring?39:33))state<=FINISH;
                    else begin
                        index<=index+1'b1;state<=COPY_WAIT;
                        if(!fine_limb)begin
                            if(coarse_limb==(restoring?3:2))begin coarse_limb<=0;coarse_number<=coarse_number+1'b1;end
                            else coarse_limb<=coarse_limb+1'b1;
                        end
                    end
                FINISH:begin
                    state<=RETIRE;
                    if(O_error!=0)begin O_dirty<=1;O_fine_present<=0;O_coarse_present<=0;O_spilled<=0;old_valid<=0;end
                    else case(command)
                        0:O_fine_present<=1;
                        4:begin O_fine_present<=0;O_coarse_present<=0;O_spilled<=1;end
                        5:begin O_fine_present<=1;O_coarse_present<=1;O_spilled<=0;end
                        default:begin end
                    endcase
                end
                default:begin O_error<=3;old_valid<=0;state<=RETIRE;
                    O_dirty<=1;O_fine_present<=0;O_coarse_present<=0;O_spilled<=0;end
              endcase
            end
        end
    end
endmodule
