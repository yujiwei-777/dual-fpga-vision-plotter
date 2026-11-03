`timescale 1ns/1ps
// Isolated candidate, NOT connected to the production design.
// Fixed NCC micro-operation for the existing microengine's physical fabric:
// A/B/R/read_low/carry, one 32-bit ALU and registered unsigned 16x16 DSP.
// No arithmetic working-value registers or multiplier live in this sequencer.
// RF is synchronous true-dual-port 128x16 (A read/write, B read only).
// R2/3=signed64 covariance, R4/5=uint64 VI, R6/7=uint64 VT;
// inputs must be the sign/zero extension of the original 36-bit interface.
// R8=score, R9=positive, R10=error. Scratch RF words64..83 are exclusive.
module pcb_ncc_fast_uop_candidate(
    input wire clk,rst_n,start,cancel,
    output wire busy,
    output reg done,
    output reg [3:0] fault,
    output reg [6:0] rf_a_addr,rf_b_addr,
    output reg rf_we,
    output reg [15:0] rf_wdata,
    input wire [15:0] rf_a_data,rf_b_data,
    input wire [31:0] a,b,r,product,
    input wire [15:0] aux,
    input wire carry,
    input wire [32:0] alu_sum,
    output reg a_we,b_we,r_we,aux_we,carry_we,
    output reg [31:0] a_data,b_data,r_data,
    output reg [15:0] aux_data,
    output reg carry_data,
    output reg [31:0] alu_a,alu_b,
    output reg alu_carry
);
    localparam IDLE=0,LOAD_WAIT=1,LOAD_CAPTURE=2,GUARD_ZERO=3,
      ABS_LOW=4,ABS_HIGH=5,RANGE_LOW=6,RANGE_HIGH=7,NEXT_INPUT=8,
      GUARD_END=9,CLEAR=10,ROW_WAIT=11,ROW_CAPTURE=12,
      PAIR_WAIT=13,PAIR_CAPTURE=14,MUL_WAIT=15,MUL_ADD0=16,
      MUL_ADD1=17,MUL_STORE=18,MUL_CARRY=19,CMP_WAIT=20,
      CMP_CAPTURE=21,CMP_EXEC=22,DIV_WAIT=23,DIV_CAPTURE=24,
      DIV_EXEC=25,DIV_STORE=26,COPY_WAIT=27,COPY_CAPTURE=28,
      COPY_STORE=29,ROUND_END=30,RESULT_WRITE=31,FINISH=32;
    localparam [6:0] SQUARE=64,DENOM=69,REMAINDER=74,DIFFERENCE=79;
    // 17045913600 = 0x3f8040000. Keep the production 36-bit guard exactly.
    localparam [31:0] STAT_MAX_LOW=32'hf8040000;
    reg [5:0] state;
    reg [1:0] input_index,load_word,mul_i,mul_j;
    reg [2:0] limb,output_word;
    reg [4:0] rounds_left;
    reg zero_variance,range_bad,cov_positive,multiply_denominator;
    reg comparison_zero,shift_bit,copy_shift,copy_initial;
    reg result_positive;
    reg [3:0] result_error;
    wire [6:0] input_base=input_index==0?7'd8:input_index==1?7'd12:7'd4;
    wire [6:0] product_base=multiply_denominator?DENOM:SQUARE;
    wire [6:0] multiplicand_base=multiply_denominator?7'd8:7'd4;
    wire [6:0] multiplier_base=multiply_denominator?7'd12:7'd4;
    wire [2:0] product_limb={1'b0,mul_i}+{1'b0,mul_j};
    wire [31:0] next_score={{b[30:16],a[31:16]},carry};
    assign busy=state!=IDLE;

    always @* begin
        rf_a_addr=0;rf_b_addr=0;rf_we=0;rf_wdata=0;
        a_we=0;b_we=0;r_we=0;aux_we=0;carry_we=0;
        a_data=a;b_data=b;r_data=r;aux_data=aux;carry_data=carry;
        alu_a=0;alu_b=0;alu_carry=0;
        case(state)
            LOAD_WAIT,LOAD_CAPTURE:begin
                rf_a_addr=input_base+{5'd0,load_word};
                if(state==LOAD_CAPTURE)case(load_word)
                    0:begin a_we=1;a_data={a[31:16],rf_a_data};end
                    1:begin a_we=1;a_data={rf_a_data,a[15:0]};end
                    2:begin b_we=1;b_data={b[31:16],rf_a_data};end
                    3:begin b_we=1;b_data={rf_a_data,b[15:0]};end
                endcase
            end
            ABS_LOW:begin
                alu_b=~a;alu_carry=1;a_we=1;a_data=alu_sum[31:0];
                carry_we=1;carry_data=alu_sum[32];
            end
            ABS_HIGH:begin
                alu_b=~b;alu_carry=carry;b_we=1;b_data=alu_sum[31:0];
            end
            RANGE_LOW:begin
                alu_a=STAT_MAX_LOW;alu_b=~a;alu_carry=1;
                carry_we=1;carry_data=alu_sum[32];
            end
            RANGE_HIGH:begin alu_a=3;alu_b=~b;alu_carry=carry;end
            GUARD_END:begin r_we=1;r_data=0;end
            CLEAR:begin
                rf_a_addr=product_base+{4'd0,limb};rf_we=1;rf_wdata=0;
                aux_we=1;aux_data=0;
            end
            ROW_WAIT,ROW_CAPTURE:begin
                rf_a_addr=multiplicand_base+{5'd0,mul_i};
                if(state==ROW_CAPTURE)begin a_we=1;a_data={16'd0,rf_a_data};end
            end
            PAIR_WAIT,PAIR_CAPTURE:begin
                rf_a_addr=multiplier_base+{5'd0,mul_j};
                rf_b_addr=product_base+{4'd0,product_limb};
                if(state==PAIR_CAPTURE)begin b_we=1;b_data={rf_b_data,rf_a_data};end
            end
            MUL_ADD0:begin alu_a=product;alu_b={16'd0,b[31:16]};r_we=1;r_data=alu_sum[31:0];end
            MUL_ADD1:begin alu_a=r;alu_b={16'd0,aux};r_we=1;r_data=alu_sum[31:0];end
            MUL_STORE:begin
                rf_a_addr=product_base+{4'd0,product_limb};rf_we=1;rf_wdata=r[15:0];
                aux_we=1;aux_data=r[31:16];
            end
            MUL_CARRY:begin
                rf_a_addr=product_base+{5'd0,mul_i}+7'd3;
                rf_we=mul_i!=2;rf_wdata=aux;aux_we=1;aux_data=0;
                if(mul_i==2 && multiply_denominator)begin carry_we=1;carry_data=1;end
            end
            CMP_WAIT,CMP_CAPTURE:begin
                rf_a_addr=DENOM+{4'd0,limb};rf_b_addr=SQUARE+{4'd0,limb};
                if(state==CMP_CAPTURE)begin
                    a_we=1;a_data={16'd0,rf_a_data};b_we=1;b_data={16'd0,rf_b_data};
                end
            end
            CMP_EXEC:begin
                alu_a={16'd0,a[15:0]};alu_b={16'd0,~b[15:0]};alu_carry=carry;
                carry_we=1;carry_data=alu_sum[16];
                if(limb==4)begin
                    if(alu_sum[16] && comparison_zero && alu_sum[15:0]==0)begin r_we=1;r_data=32'h40000000;end
                    else if(!alu_sum[16])begin r_we=1;r_data=0;end
                    else begin a_we=1;a_data={16'd0,a[15:0]};b_we=1;b_data={16'd0,b[15:0]};end
                end
            end
            DIV_WAIT,DIV_CAPTURE:begin
                rf_a_addr=REMAINDER+{4'd0,limb};rf_b_addr=DENOM+{4'd0,limb};
                if(state==DIV_CAPTURE)begin
                    a_we=1;a_data={a[31:16],rf_a_data[14:0],shift_bit};
                    b_we=1;b_data={b[31:16],rf_b_data};
                end
            end
            DIV_EXEC:begin
                alu_a={16'd0,a[15:0]};alu_b={16'd0,~b[15:0]};alu_carry=carry;
                r_we=1;r_data=alu_sum[31:0];carry_we=1;carry_data=alu_sum[16];
            end
            DIV_STORE:begin rf_a_addr=DIFFERENCE+{4'd0,limb};rf_we=1;rf_wdata=r[15:0];end
            COPY_WAIT,COPY_CAPTURE:begin
                rf_a_addr=(copy_initial?SQUARE:carry?DIFFERENCE:REMAINDER)+{4'd0,limb};
                if(state==COPY_CAPTURE)begin
                    r_we=1;
                    r_data={16'd0,(copy_initial||carry)?rf_a_data:{rf_a_data[14:0],copy_shift}};
                end
            end
            COPY_STORE:begin
                rf_a_addr=REMAINDER+{4'd0,limb};rf_we=1;rf_wdata=r[15:0];
                if(limb==4 && copy_initial)begin carry_we=1;carry_data=1;end
            end
            ROUND_END:begin
                if(rounds_left==1)begin r_we=1;r_data=next_score;end
                else begin
                    a_we=1;a_data={next_score[15:0],a[15:0]};
                    b_we=1;b_data={next_score[31:16],b[15:0]};
                    carry_we=1;carry_data=1;
                end
            end
            RESULT_WRITE:begin
                rf_a_addr=7'd16+{4'd0,output_word};rf_we=1;
                case(output_word)
                    0:rf_wdata=r[15:0];
                    1:rf_wdata=r[31:16];
                    2:rf_wdata={15'd0,result_positive};
                    4:rf_wdata={12'd0,result_error};
                    default:rf_wdata=0;
                endcase
            end
            default:begin end
        endcase
        if(cancel || (start && busy))begin
            rf_we=0;a_we=0;b_we=0;r_we=0;aux_we=0;carry_we=0;
        end
    end

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;done<=0;fault<=0;input_index<=0;load_word<=0;mul_i<=0;mul_j<=0;
            limb<=0;output_word<=0;rounds_left<=0;zero_variance<=0;range_bad<=0;
            cov_positive<=0;multiply_denominator<=0;comparison_zero<=0;shift_bit<=0;
            copy_shift<=0;copy_initial<=0;result_positive<=0;result_error<=0;
        end else begin
            done<=0;
            if(cancel)begin state<=IDLE;fault<=0;end
            else if(start && busy)begin state<=IDLE;done<=1;fault<=4;end
            else case(state)
                IDLE:if(start)begin
                    input_index<=0;load_word<=0;zero_variance<=0;range_bad<=0;cov_positive<=0;
                    result_positive<=0;result_error<=0;fault<=0;output_word<=0;state<=LOAD_WAIT;
                end
                LOAD_WAIT:state<=LOAD_CAPTURE;
                LOAD_CAPTURE:if(load_word==3)state<=GUARD_ZERO;
                else begin load_word<=load_word+1'b1;state<=LOAD_WAIT;end
                GUARD_ZERO:begin
                    if(input_index!=2 && a==0 && b==0)zero_variance<=1;
                    if(input_index==2)cov_positive<=!b[31] && (a!=0 || b!=0);
                    state<=input_index==2 && b[31]?ABS_LOW:RANGE_LOW;
                end
                ABS_LOW:state<=ABS_HIGH;
                ABS_HIGH:state<=RANGE_LOW;
                RANGE_LOW:state<=RANGE_HIGH;
                RANGE_HIGH:begin if(!alu_sum[32])range_bad<=1;state<=NEXT_INPUT;end
                NEXT_INPUT:if(input_index==2)state<=GUARD_END;
                else begin input_index<=input_index+1'b1;load_word<=0;state<=LOAD_WAIT;end
                GUARD_END:begin
                    if(zero_variance || range_bad || !cov_positive)begin
                        result_error<=zero_variance?4'd1:range_bad?4'd2:4'd0;state<=RESULT_WRITE;
                    end else begin multiply_denominator<=0;limb<=0;mul_i<=0;mul_j<=0;state<=CLEAR;end
                end
                CLEAR:if(limb==4)begin limb<=0;state<=ROW_WAIT;end
                else limb<=limb+1'b1;
                ROW_WAIT:state<=ROW_CAPTURE;
                ROW_CAPTURE:state<=PAIR_WAIT;
                PAIR_WAIT:state<=PAIR_CAPTURE;
                PAIR_CAPTURE:state<=MUL_WAIT;
                MUL_WAIT:state<=MUL_ADD0;
                MUL_ADD0:state<=MUL_ADD1;
                MUL_ADD1:state<=MUL_STORE;
                MUL_STORE:if(mul_j==2)state<=MUL_CARRY;
                else begin mul_j<=mul_j+1'b1;state<=PAIR_WAIT;end
                MUL_CARRY:if(mul_i==2)begin
                    limb<=0;mul_i<=0;mul_j<=0;
                    if(!multiply_denominator)begin multiply_denominator<=1;state<=CLEAR;end
                    else begin comparison_zero<=1;state<=CMP_WAIT;end
                end else begin mul_i<=mul_i+1'b1;mul_j<=0;state<=ROW_WAIT;end
                CMP_WAIT:state<=CMP_CAPTURE;
                CMP_CAPTURE:state<=CMP_EXEC;
                CMP_EXEC:begin
                    comparison_zero<=comparison_zero && alu_sum[15:0]==0;
                    if(limb!=4)begin limb<=limb+1'b1;state<=CMP_WAIT;end
                    else if(!alu_sum[16])begin result_error<=3;state<=RESULT_WRITE;end
                    else if(comparison_zero && alu_sum[15:0]==0)begin result_positive<=1;state<=RESULT_WRITE;end
                    else begin limb<=0;copy_initial<=1;copy_shift<=0;state<=COPY_WAIT;end
                end
                DIV_WAIT:state<=DIV_CAPTURE;
                DIV_CAPTURE:begin shift_bit<=rf_a_data[15];state<=DIV_EXEC;end
                DIV_EXEC:state<=DIV_STORE;
                DIV_STORE:if(limb==4)begin limb<=0;copy_initial<=0;copy_shift<=0;state<=COPY_WAIT;end
                else begin limb<=limb+1'b1;state<=DIV_WAIT;end
                COPY_WAIT:state<=COPY_CAPTURE;
                COPY_CAPTURE:begin copy_shift<=rf_a_data[15];state<=COPY_STORE;end
                COPY_STORE:if(limb!=4)begin limb<=limb+1'b1;state<=COPY_WAIT;end
                else if(copy_initial)begin limb<=0;shift_bit<=0;rounds_left<=30;state<=DIV_WAIT;end
                else state<=ROUND_END;
                ROUND_END:if(rounds_left==1)begin result_positive<=1;state<=RESULT_WRITE;end
                else begin rounds_left<=rounds_left-1'b1;limb<=0;shift_bit<=0;state<=DIV_WAIT;end
                RESULT_WRITE:if(output_word==5)state<=FINISH;
                else output_word<=output_word+1'b1;
                FINISH:begin done<=1;state<=IDLE;end
                default:begin done<=1;fault<=15;state<=IDLE;end
            endcase
        end
    end
endmodule
