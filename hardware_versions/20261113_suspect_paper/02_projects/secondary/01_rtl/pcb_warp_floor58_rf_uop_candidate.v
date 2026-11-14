`timescale 1ns/1ps
// Isolated component candidate. NOT connected to the production engine.
// Exact signed58/positive25 floor. All64-bit values live in the private RF.
// A=remainder, B=denominator, R=ALU result, aux=quotient digit are EXISTING
// engine registers. This sequencer adds no numerical working register bank.
// No multiply, divide, or new wide adder is inferred here. The shared engine
// supplies alu_sum={1'b0,alu_a}+{1'b0,alu_b}+alu_carry.
module pcb_warp_floor58_rf_uop_candidate #(
    parameter [6:0] NUMERATOR_BASE=7'd90,
    parameter [6:0] DENOMINATOR_BASE=7'd76,
    parameter [6:0] QUOTIENT_BASE=7'd102,
    parameter [6:0] ABSOLUTE_BASE=7'd94
) (
    input wire clk,rst_n,start,cancel,
    output wire busy,
    output reg done,
    output reg [3:0] fault,
    output reg [6:0] rf_a_addr,rf_b_addr,
    output reg rf_we,
    output reg [15:0] rf_wdata,
    input wire [15:0] rf_a_data,rf_b_data,
    input wire [31:0] a,b,r,
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
    localparam IDLE=0,SIGN_WAIT=1,SIGN_CAPTURE=2,DEN_WAIT=3,
      DEN_CAPTURE=4,DEN_GUARD=5,ABS_WAIT=6,ABS_CAPTURE=7,
      ABS_EXEC=8,ABS_STORE=9,DIV_SETUP=10,BIT_WAIT=11,
      BIT_CAPTURE=12,BIT_EXEC=13,QUOT_STORE=14,NEG_PREP=15,
      NEG_WAIT=16,NEG_CAPTURE=17,NEG_EXEC=18,NEG_STORE=19,FINISH=20;
    reg [4:0] state;
    reg [1:0] limb;
    reg [5:0] bit_index;
    reg negative,den_high;
    wire [6:0] numerator_word=NUMERATOR_BASE+{5'd0,limb};
    wire [6:0] absolute_word=ABSOLUTE_BASE+{5'd0,limb};
    wire [6:0] quotient_word=QUOTIENT_BASE+{5'd0,limb};
    assign busy=state!=IDLE;

    always @* begin
        rf_a_addr=0;rf_b_addr=0;rf_we=0;rf_wdata=0;
        a_we=0;b_we=0;r_we=0;aux_we=0;carry_we=0;
        a_data=a;b_data=b;r_data=r;aux_data=aux;carry_data=carry;
        alu_a=0;alu_b=0;alu_carry=0;
        case(state)
            SIGN_WAIT,SIGN_CAPTURE:rf_a_addr=NUMERATOR_BASE+7'd3;
            DEN_WAIT,DEN_CAPTURE:begin
                rf_a_addr=DENOMINATOR_BASE+{6'd0,den_high};
                if(state==DEN_CAPTURE)begin
                    b_we=1;b_data=den_high?{rf_a_data,b[15:0]}:{b[31:16],rf_a_data};
                end
            end
            DEN_GUARD:begin carry_we=1;carry_data=1;end
            ABS_WAIT,ABS_CAPTURE:begin
                rf_a_addr=numerator_word;
                if(state==ABS_CAPTURE)begin a_we=1;a_data={16'd0,rf_a_data};end
            end
            ABS_EXEC:begin
                alu_b={16'd0,~a[15:0]};alu_carry=carry;
                r_we=1;r_data=negative?alu_sum[31:0]:a;
                carry_we=1;carry_data=alu_sum[16];
            end
            ABS_STORE:begin rf_a_addr=absolute_word;rf_we=1;rf_wdata=r[15:0];end
            DIV_SETUP:begin a_we=1;a_data=0;aux_we=1;aux_data=0;end
            BIT_WAIT,BIT_CAPTURE:begin
                rf_a_addr=ABSOLUTE_BASE+{5'd0,bit_index[5:4]};
                if(state==BIT_CAPTURE)begin
                    a_we=1;a_data={a[30:0],rf_a_data[bit_index[3:0]]};
                end
            end
            BIT_EXEC:begin
                alu_a=a;alu_b=~b;alu_carry=1;
                a_we=1;a_data=alu_sum[32]?alu_sum[31:0]:a;
                r_we=1;r_data=alu_sum[31:0];
                carry_we=1;carry_data=alu_sum[32];
                aux_we=1;aux_data={aux[14:0],alu_sum[32]};
            end
            QUOT_STORE:begin
                rf_a_addr=QUOTIENT_BASE+{5'd0,bit_index[5:4]};
                rf_we=1;rf_wdata=aux;aux_we=1;aux_data=0;
            end
            NEG_PREP:begin carry_we=1;carry_data=a==0;end
            NEG_WAIT,NEG_CAPTURE:begin
                rf_a_addr=quotient_word;
                if(state==NEG_CAPTURE)begin a_we=1;a_data={16'd0,rf_a_data};end
            end
            NEG_EXEC:begin
                alu_b={16'd0,~a[15:0]};alu_carry=carry;
                r_we=1;r_data=alu_sum[31:0];carry_we=1;carry_data=alu_sum[16];
            end
            NEG_STORE:begin rf_a_addr=quotient_word;rf_we=1;rf_wdata=r[15:0];end
            default:begin end
        endcase
        if(cancel || (start && busy))begin
            rf_we=0;a_we=0;b_we=0;r_we=0;aux_we=0;carry_we=0;
        end
    end

    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;done<=0;fault<=0;limb<=0;bit_index<=0;negative<=0;den_high<=0;
        end else begin
            done<=0;
            if(cancel)begin state<=IDLE;fault<=0;end
            else if(start && busy)begin state<=IDLE;done<=1;fault<=4;end
            else case(state)
                IDLE:if(start)begin fault<=0;limb<=0;den_high<=0;state<=SIGN_WAIT;end
                SIGN_WAIT:state<=SIGN_CAPTURE;
                SIGN_CAPTURE:begin negative<=rf_a_data[15];state<=DEN_WAIT;end
                DEN_WAIT:state<=DEN_CAPTURE;
                DEN_CAPTURE:if(den_high)state<=DEN_GUARD;
                else begin den_high<=1;state<=DEN_WAIT;end
                DEN_GUARD:begin
                    if(b<32'd8388608 || b>32'd25165824)begin fault<=1;state<=FINISH;end
                    else begin limb<=0;state<=ABS_WAIT;end
                end
                ABS_WAIT:state<=ABS_CAPTURE;
                ABS_CAPTURE:state<=ABS_EXEC;
                ABS_EXEC:state<=ABS_STORE;
                ABS_STORE:begin
                    if(limb==3)begin
                        if(r[15:10]!=0)begin fault<=2;state<=FINISH;end
                        else begin bit_index<=57;state<=DIV_SETUP;end
                    end else begin limb<=limb+1'b1;state<=ABS_WAIT;end
                end
                DIV_SETUP:state<=BIT_WAIT;
                BIT_WAIT:state<=BIT_CAPTURE;
                BIT_CAPTURE:state<=BIT_EXEC;
                BIT_EXEC:if(bit_index[3:0]==0)state<=QUOT_STORE;
                else begin bit_index<=bit_index-1'b1;state<=BIT_WAIT;end
                QUOT_STORE:begin
                    // Generic58/25 inputs may use up to35 quotient bits.
                    if((bit_index[5:4]==3 && aux!=0) ||
                       (bit_index[5:4]==2 && aux[15:3]!=0))begin fault<=3;state<=FINISH;end
                    else if(bit_index==0)begin limb<=0;state<=negative?NEG_PREP:FINISH;end
                    else begin bit_index<=bit_index-1'b1;state<=BIT_WAIT;end
                end
                NEG_PREP:state<=NEG_WAIT;
                NEG_WAIT:state<=NEG_CAPTURE;
                NEG_CAPTURE:state<=NEG_EXEC;
                NEG_EXEC:state<=NEG_STORE;
                NEG_STORE:if(limb==3)state<=FINISH;
                else begin limb<=limb+1'b1;state<=NEG_WAIT;end
                FINISH:begin state<=IDLE;done<=1;end
                default:begin state<=IDLE;done<=1;fault<=15;end
            endcase
        end
    end
endmodule
