// Exact positive NCC^2 Q30 normalizer. No combinational /, *, sqrt or DSP.
// score=floor((C*C<<30)/(VI*VT)); N=256 statistics supplied by the caller.
// Legal N=256 uint8 statistics bound |C|,VI,VT by 1065369600.
// The two products and restoring division use one split 32-bit add/sub path.
// Positive legal calls take exactly 400 busy clocks. Degenerate variance,
// invalid bounds and Cauchy violations return invalid, never a trusted score.
module pcb_ncc_normalize_serial (
    input wire I_clk,
    input wire I_rst_n,
    input wire I_start,
    input wire I_cancel,
    input wire signed [32:0] I_covariance,
    input wire [31:0] I_variance_i,
    input wire [31:0] I_variance_t,
    output wire O_busy,
    output reg O_done,
    output reg O_result_valid,
    output reg O_positive,
    output reg [30:0] O_score2_q30,
    output reg [3:0] O_error, //1 zero variance;2 numeric bounds;3 Cauchy;4 busy start
    output reg [15:0] O_cycles
);
    localparam [2:0] IDLE=0, MUL_LO=1, MUL_HI=2, MUL_END=3,
                     DIV_LO=4, DIV_HI=5, DIV_COMMIT=6;
    localparam [31:0] STAT_MAX=32'd1065369600;
    reg [2:0] state;
    reg product_phase;
    reg [31:0] variance_i,variance_t;
    reg [63:0] mul_acc,mul_shift,square,denominator;
    reg [31:0] mul_bits;
    reg [5:0] mul_bit;
    reg [31:0] low_result,high_result;
    reg low_carry,high_borrow;
    reg [89:0] dividend;
    reg [63:0] remainder;
    reg [30:0] quotient;
    reg [6:0] div_bit;
    reg quotient_overflow;

    wire [32:0] mul_low_sum={1'b0,mul_acc[31:0]}+
                          (mul_bits[0]?{1'b0,mul_shift[31:0]}:33'd0);
    wire [32:0] mul_high_sum={1'b0,mul_acc[63:32]}+
                           (mul_bits[0]?{1'b0,mul_shift[63:32]}:33'd0)+low_carry;
    wire [63:0] shifted_remainder={remainder[62:0],dividend[89]};
    wire [32:0] div_low_diff={1'b0,shifted_remainder[31:0]}-{1'b0,denominator[31:0]};
    wire [32:0] div_high_diff={1'b0,shifted_remainder[63:32]}-
                            {1'b0,denominator[63:32]}-low_carry;
    wire [30:0] next_quotient={quotient[29:0],!high_borrow};
    wire cauchy_violation=(square[63:32]>mul_acc[63:32]) ||
                         ((square[63:32]==mul_acc[63:32]) && square[31:0]>mul_acc[31:0]);
    assign O_busy=state!=IDLE;

    task fail;
        input [3:0] code;
        begin
            state<=IDLE;O_done<=1;O_result_valid<=0;O_positive<=0;
            O_score2_q30<=0;O_error<=code;
        end
    endtask

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=IDLE;product_phase<=0;variance_i<=0;variance_t<=0;
            mul_acc<=0;mul_shift<=0;mul_bits<=0;mul_bit<=0;square<=0;denominator<=0;
            low_result<=0;high_result<=0;low_carry<=0;high_borrow<=0;
            dividend<=0;remainder<=0;quotient<=0;div_bit<=0;quotient_overflow<=0;
            O_done<=0;O_result_valid<=0;O_positive<=0;O_score2_q30<=0;O_error<=0;O_cycles<=0;
        end else begin
            O_done<=0;
            if(I_cancel) begin
                state<=IDLE;O_result_valid<=0;O_positive<=0;O_score2_q30<=0;O_error<=0;O_cycles<=0;
            end else if(I_start && state!=IDLE) begin
                fail(4'd4);
            end else begin
                if(state!=IDLE) O_cycles<=O_cycles+16'd1;
                case(state)
                    IDLE:if(I_start) begin
                        O_result_valid<=0;O_positive<=0;O_score2_q30<=0;O_error<=0;O_cycles<=0;
                        if(I_variance_i==0 || I_variance_t==0) fail(4'd1);
                        else if(I_variance_i>STAT_MAX || I_variance_t>STAT_MAX ||
                                I_covariance>$signed({1'b0,STAT_MAX})) fail(4'd2);
                        else if(I_covariance<=0) begin
                            O_done<=1;O_result_valid<=1;O_positive<=0;
                        end else begin
                            variance_i<=I_variance_i;variance_t<=I_variance_t;
                            mul_acc<=0;mul_shift<={32'd0,I_covariance[31:0]};
                            mul_bits<=I_covariance[31:0];mul_bit<=0;product_phase<=0;
                            state<=MUL_LO;
                        end
                    end
                    MUL_LO:begin
                        low_result<=mul_low_sum[31:0];low_carry<=mul_low_sum[32];state<=MUL_HI;
                    end
                    MUL_HI:begin
                        mul_acc<={mul_high_sum[31:0],low_result};
                        mul_shift<={mul_shift[62:0],1'b0};mul_bits<={1'b0,mul_bits[31:1]};
                        if(mul_bit==31) state<=MUL_END;
                        else begin mul_bit<=mul_bit+6'd1;state<=MUL_LO;end
                    end
                    MUL_END:begin
                        if(!product_phase) begin
                            square<=mul_acc;dividend<={mul_acc[59:0],30'd0};
                            mul_acc<=0;mul_shift<={32'd0,variance_i};mul_bits<=variance_t;
                            mul_bit<=0;product_phase<=1;state<=MUL_LO;
                        end else if(cauchy_violation) fail(4'd3);
                        else begin
                            denominator<=mul_acc;remainder<=0;quotient<=0;
                            div_bit<=89;quotient_overflow<=0;state<=DIV_LO;
                        end
                    end
                    DIV_LO:begin
                        low_result<=div_low_diff[31:0];low_carry<=div_low_diff[32];state<=DIV_HI;
                    end
                    DIV_HI:begin
                        high_result<=div_high_diff[31:0];high_borrow<=div_high_diff[32];state<=DIV_COMMIT;
                    end
                    DIV_COMMIT:begin
                        remainder<=high_borrow?shifted_remainder:{high_result,low_result};
                        dividend<={dividend[88:0],1'b0};quotient<=next_quotient;
                        quotient_overflow<=quotient_overflow || quotient[30];
                        if(div_bit==0) begin
                            if(quotient_overflow || quotient[30]) fail(4'd2);
                            else begin
                                state<=IDLE;O_done<=1;O_result_valid<=1;O_positive<=1;
                                O_score2_q30<=next_quotient;O_error<=0;
                            end
                        end else begin div_bit<=div_bit-7'd1;state<=DIV_LO;end
                    end
                    default:fail(4'd2);
                endcase
            end
        end
    end
endmodule
