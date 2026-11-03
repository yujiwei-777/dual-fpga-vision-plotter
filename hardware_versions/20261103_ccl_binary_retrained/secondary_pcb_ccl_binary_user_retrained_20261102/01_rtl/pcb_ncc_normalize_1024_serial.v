// Exact positive NCC squared, Q30, for up to 1024 unsigned-eight-bit samples.
// The theoretical covariance/variance bound is 17045913600, not a 32-bit value.
// One eighteen-bit carry datapath handles both 36x36 products and 102/72 divide.
// Valid positive requests take exactly 800 busy clocks. No DSP is inferred.
module pcb_ncc_normalize_1024_serial (
    input wire I_clk,
    input wire I_rst_n,
    input wire I_start,
    input wire I_cancel,
    input wire signed [35:0] I_covariance,
    input wire [35:0] I_variance_i,
    input wire [35:0] I_variance_t,
    output wire O_busy,
    output reg O_done,
    output reg O_result_valid,
    output reg O_positive,
    output reg [30:0] O_score2_q30,
    output reg [3:0] O_error,
    output reg [15:0] O_cycles
);
    localparam [3:0] IDLE=0, M0=1, M1=2, M2=3, M3=4, MEND=5,
                     D0=6, D1=7, D2=8, D3=9, DCOMMIT=10;
    localparam [35:0] STAT_MAX=36'd17045913600;
    reg [3:0] state;
    reg product_phase,carry;
    reg [35:0] variance_i,variance_t,mul_bits;
    reg [71:0] mul_acc,mul_shift,square,denominator,temp;
    reg [5:0] mul_bit;
    reg [101:0] dividend;
    reg [71:0] remainder;
    reg [30:0] quotient;
    reg [6:0] div_bit;
    reg quotient_overflow;
    reg [17:0] alu_a,alu_b;
    reg alu_carry;
    wire [18:0] alu_sum={1'b0,alu_a}+{1'b0,alu_b}+alu_carry;
    wire [71:0] shifted_remainder={remainder[70:0],dividend[101]};
    wire [30:0] next_quotient={quotient[29:0],carry};
    wire cauchy_violation=square>mul_acc;
    assign O_busy=state!=IDLE;

    // Each operation uses the same bounded-width add/subtract carry path.
    always @* begin
        alu_a=0;alu_b=0;alu_carry=0;
        case(state)
            M0:begin alu_a=mul_acc[17:0];alu_b=mul_bits[0]?mul_shift[17:0]:18'd0;end
            M1:begin alu_a=mul_acc[35:18];alu_b=mul_bits[0]?mul_shift[35:18]:18'd0;alu_carry=carry;end
            M2:begin alu_a=mul_acc[53:36];alu_b=mul_bits[0]?mul_shift[53:36]:18'd0;alu_carry=carry;end
            M3:begin alu_a=mul_acc[71:54];alu_b=mul_bits[0]?mul_shift[71:54]:18'd0;alu_carry=carry;end
            D0:begin alu_a=shifted_remainder[17:0];alu_b=~denominator[17:0];alu_carry=1;end
            D1:begin alu_a=shifted_remainder[35:18];alu_b=~denominator[35:18];alu_carry=carry;end
            D2:begin alu_a=shifted_remainder[53:36];alu_b=~denominator[53:36];alu_carry=carry;end
            D3:begin alu_a=shifted_remainder[71:54];alu_b=~denominator[71:54];alu_carry=carry;end
            default:begin end
        endcase
    end

    task fail;
        input [3:0] code;
        begin
            state<=IDLE;O_done<=1;O_result_valid<=0;O_positive<=0;
            O_score2_q30<=0;O_error<=code;
        end
    endtask

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=IDLE;product_phase<=0;carry<=0;
            variance_i<=0;variance_t<=0;mul_bits<=0;mul_acc<=0;mul_shift<=0;
            square<=0;denominator<=0;temp<=0;mul_bit<=0;dividend<=0;
            remainder<=0;quotient<=0;div_bit<=0;quotient_overflow<=0;
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
                                I_covariance>$signed(STAT_MAX) ||
                                I_covariance<-$signed(STAT_MAX)) fail(4'd2);
                        else if(I_covariance<=0) begin O_done<=1;O_result_valid<=1;end
                        else begin
                            variance_i<=I_variance_i;variance_t<=I_variance_t;
                            mul_acc<=0;mul_shift<={36'd0,I_covariance};
                            mul_bits<=I_covariance;mul_bit<=0;product_phase<=0;state<=M0;
                        end
                    end
                    M0:begin temp[17:0]<=alu_sum[17:0];carry<=alu_sum[18];state<=M1;end
                    M1:begin temp[35:18]<=alu_sum[17:0];carry<=alu_sum[18];state<=M2;end
                    M2:begin temp[53:36]<=alu_sum[17:0];carry<=alu_sum[18];state<=M3;end
                    M3:begin
                        mul_acc<={alu_sum[17:0],temp[53:0]};
                        mul_shift<={mul_shift[70:0],1'b0};mul_bits<={1'b0,mul_bits[35:1]};
                        if(mul_bit==35) state<=MEND;
                        else begin mul_bit<=mul_bit+6'd1;state<=M0;end
                    end
                    MEND:begin
                        if(!product_phase) begin
                            square<=mul_acc;dividend<={mul_acc,30'd0};
                            mul_acc<=0;mul_shift<={36'd0,variance_i};mul_bits<=variance_t;
                            mul_bit<=0;product_phase<=1;state<=M0;
                        end else if(cauchy_violation) fail(4'd3);
                        else begin
                            denominator<=mul_acc;remainder<=0;quotient<=0;
                            div_bit<=101;quotient_overflow<=0;state<=D0;
                        end
                    end
                    D0:begin temp[17:0]<=alu_sum[17:0];carry<=alu_sum[18];state<=D1;end
                    D1:begin temp[35:18]<=alu_sum[17:0];carry<=alu_sum[18];state<=D2;end
                    D2:begin temp[53:36]<=alu_sum[17:0];carry<=alu_sum[18];state<=D3;end
                    D3:begin temp[71:54]<=alu_sum[17:0];carry<=alu_sum[18];state<=DCOMMIT;end
                    DCOMMIT:begin
                        remainder<=carry?temp:shifted_remainder;
                        dividend<={dividend[100:0],1'b0};quotient<=next_quotient;
                        quotient_overflow<=quotient_overflow || quotient[30];
                        if(div_bit==0) begin
                            if(quotient_overflow || quotient[30]) fail(4'd2);
                            else begin
                                state<=IDLE;O_done<=1;O_result_valid<=1;O_positive<=1;
                                O_score2_q30<=next_quotient;O_error<=0;
                            end
                        end else begin div_bit<=div_bit-7'd1;state<=D0;end
                    end
                    default:fail(4'd2);
                endcase
            end
        end
    end
endmodule
