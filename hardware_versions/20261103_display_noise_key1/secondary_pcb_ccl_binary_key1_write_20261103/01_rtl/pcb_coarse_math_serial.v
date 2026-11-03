// Small setup engine for coarse pose offsets. One shared 32-bit carry path.
// op0: signed64 a+b; op1: signed64 a * unsigned10 factor (bounded caller);
// op2: floor((a + 93600*2^29)/(93600*2^30)), result must fit signed8.
// op3: nearest-even(a/549362067696 + integer), a nonnegative, floor(a/L)<128;
//      b[0] supplies the existing whole-integer parity. Returns increment0..127.
// Products and additions are two's-complement modulo64; pose input bounds
// prove no arithmetic overflow. No combinational multiplier or divider.
module pcb_coarse_math_serial (
    input wire I_clk,I_rst_n,I_start,I_cancel,
    input wire [1:0] I_op,
    input wire signed [63:0] I_a,I_b,
    input wire [9:0] I_factor,
    output wire O_busy,
    output reg O_done,O_valid,
    output reg signed [63:0] O_result,
    output reg [3:0] O_error
);
    localparam [3:0] IDLE=0,MLO=1,MHI=2,DADDLO=3,DADDHI=4,
                     DABSLO=5,DABSHI=6,DSUBLO=7,DSUBHI=8,DCOMMIT=9;
    localparam [63:0] DEN=64'd100502234726400,HALF=64'd50251117363200;
    localparam [63:0] AFFINE_DEN=64'd549362067696;
    reg [3:0] state,rounds;
    reg [63:0] acc,shift,temp,remainder,divisor,rounded;
    reg [9:0] bits_left;
    reg carry,negative,div_nearest,integer_parity;
    reg [6:0] quotient;
    reg [2:0] div_bit;
    reg [31:0] alu_a,alu_b;
    reg alu_carry;
    wire [32:0] alu_sum={1'b0,alu_a}+{1'b0,alu_b}+alu_carry;
    wire [63:0] final_remainder=carry?temp:remainder;
    wire [6:0] final_q=quotient | (carry?7'd1:7'd0);
    wire [7:0] signed_q=negative? (8'd0-{1'b0,final_q}-(final_remainder!=0)):{1'b0,final_q};
    wire [63:0] selected_den=div_nearest?AFFINE_DEN:DEN;
    wire round_up=((final_remainder<<1)>AFFINE_DEN) ||
                  (((final_remainder<<1)==AFFINE_DEN) && (final_q[0]^integer_parity));
    wire [7:0] rounded_q={1'b0,final_q}+round_up;
    assign O_busy=state!=IDLE;
    always @* begin
        alu_a=0;alu_b=0;alu_carry=0;
        case(state)
            MLO:begin alu_a=acc[31:0];alu_b=bits_left[0]?shift[31:0]:32'd0;end
            MHI:begin alu_a=acc[63:32];alu_b=bits_left[0]?shift[63:32]:32'd0;alu_carry=carry;end
            DADDLO:begin alu_a=acc[31:0];alu_b=div_nearest?32'd0:HALF[31:0];end
            DADDHI:begin alu_a=acc[63:32];alu_b=div_nearest?32'd0:HALF[63:32];alu_carry=carry;end
            DABSLO:begin alu_a=negative?~rounded[31:0]:rounded[31:0];alu_carry=negative;end
            DABSHI:begin alu_a=negative?~rounded[63:32]:rounded[63:32];alu_carry=carry;end
            DSUBLO:begin alu_a=remainder[31:0];alu_b=~divisor[31:0];alu_carry=1;end
            DSUBHI:begin alu_a=remainder[63:32];alu_b=~divisor[63:32];alu_carry=carry;end
            default:begin end
        endcase
    end
    task fail;
        input [3:0] code;
        begin state<=IDLE;O_done<=1;O_valid<=0;O_result<=0;O_error<=code;end
    endtask
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=IDLE;rounds<=0;acc<=0;shift<=0;temp<=0;remainder<=0;
            divisor<=0;rounded<=0;bits_left<=0;carry<=0;negative<=0;div_nearest<=0;integer_parity<=0;
            quotient<=0;div_bit<=0;O_done<=0;O_valid<=0;O_result<=0;O_error<=0;
        end else begin
            O_done<=0;
            if(I_cancel) begin state<=IDLE;O_valid<=0;O_result<=0;O_error<=0;end
            else if(I_start && state!=IDLE) fail(4'd2);
            else case(state)
                IDLE:if(I_start) begin
                    O_valid<=0;O_error<=0;
                    case(I_op)
                        0:begin acc<=I_a;shift<=I_b;bits_left<=1;rounds<=0;state<=MLO;end
                        1:begin acc<=0;shift<=I_a;bits_left<=I_factor;rounds<=9;state<=MLO;end
                        2:begin acc<=I_a;div_nearest<=0;integer_parity<=0;state<=DADDLO;end
                        3:begin
                            if(I_a[63]) fail(4'd1);
                            else begin acc<=I_a;div_nearest<=1;integer_parity<=I_b[0];state<=DADDLO;end
                        end
                    endcase
                end
                MLO:begin temp[31:0]<=alu_sum[31:0];carry<=alu_sum[32];state<=MHI;end
                MHI:begin
                    acc<={alu_sum[31:0],temp[31:0]};
                    if(rounds==0) begin
                        state<=IDLE;O_done<=1;O_valid<=1;O_result<={alu_sum[31:0],temp[31:0]};
                    end else begin rounds<=rounds-4'd1;shift<={shift[62:0],1'b0};bits_left<={1'b0,bits_left[9:1]};state<=MLO;end
                end
                DADDLO:begin temp[31:0]<=alu_sum[31:0];carry<=alu_sum[32];state<=DADDHI;end
                DADDHI:begin rounded<={alu_sum[31:0],temp[31:0]};negative<=alu_sum[31];state<=DABSLO;end
                DABSLO:begin temp[31:0]<=alu_sum[31:0];carry<=alu_sum[32];state<=DABSHI;end
                DABSHI:begin
                    remainder<={alu_sum[31:0],temp[31:0]};divisor<=selected_den<<6;
                    quotient<=0;div_bit<=6;state<=DSUBLO;
                end
                DSUBLO:begin temp[31:0]<=alu_sum[31:0];carry<=alu_sum[32];state<=DSUBHI;end
                DSUBHI:begin temp[63:32]<=alu_sum[31:0];carry<=alu_sum[32];state<=DCOMMIT;end
                DCOMMIT:begin
                    remainder<=final_remainder;
                    if(carry) quotient[div_bit]<=1;
                    if(div_bit==0) begin
                        if(final_remainder>=selected_den || (div_nearest && rounded_q[7])) fail(4'd3);
                        else begin
                            state<=IDLE;O_done<=1;O_valid<=1;
                            O_result<=div_nearest?{56'd0,rounded_q}:{{56{signed_q[7]}},signed_q};
                        end
                    end else begin divisor<={1'b0,divisor[63:1]};div_bit<=div_bit-3'd1;state<=DSUBLO;end
                end
                default:fail(4'd1);
            endcase
        end
    end
endmodule
