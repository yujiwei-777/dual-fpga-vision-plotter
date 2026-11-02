// Exact positive NCC squared, Q30, for up to 1024 unsigned-eight-bit pairs.
// Independent area variant: the original module is intentionally unchanged.
// STAT_MAX < 2^34 is checked before narrowing any operand. One 18-bit carry
// datapath performs both 34x34 products, the Cauchy check, and 98/68 division.
// Positive valid requests take exactly 768 busy clocks; no DSP is required.
// Product storage becomes denominator storage; multiplier shift storage becomes
// remainder storage. Initial VI/VT storage becomes subtraction scratch. The
// dividend shift register also collects quotient bits, without a quotient reg.
module pcb_ncc_normalize_1024_serial_v2 (
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
    localparam [3:0] IDLE=0,M0=1,M1=2,M2=3,M3=4,MEND=5,
        C0=6,C1=7,C2=8,C3=9,D0=10,D1=11,D2=12,D3=13,DCOMMIT=14;
    localparam [35:0] STAT_MAX=36'd17045913600;
    reg [3:0] state;
    reg product_phase,carry;
    reg [33:0] mul_bits;
    reg [67:0] accumulator;
    // Restoring division needs one extra trial-remainder bit above the
    // 68-bit denominator, even though each committed remainder fits 68 bits.
    reg [68:0] work,scratch;
    reg [5:0] mul_bit;
    reg [97:0] dividend;
    reg [6:0] div_bit;
    reg quotient_overflow;
    reg [17:0] alu_a,alu_b;
    reg alu_carry;
    wire [18:0] alu_sum={1'b0,alu_a}+{1'b0,alu_b}+alu_carry;
    wire [68:0] shifted_remainder={work[67:0],dividend[97]};
    wire quotient_high_bit=carry && div_bit>=7'd31;
    assign O_busy=state!=IDLE;

    always @* begin
        alu_a=0;alu_b=0;alu_carry=0;
        case(state)
            M0:begin alu_a=accumulator[17:0];alu_b=mul_bits[0]?work[17:0]:18'd0;end
            M1:begin alu_a=accumulator[35:18];alu_b=mul_bits[0]?work[35:18]:18'd0;alu_carry=carry;end
            M2:begin alu_a=accumulator[53:36];alu_b=mul_bits[0]?work[53:36]:18'd0;alu_carry=carry;end
            M3:begin alu_a={4'd0,accumulator[67:54]};alu_b=mul_bits[0]?{4'd0,work[67:54]}:18'd0;alu_carry=carry;end
            C0:begin alu_a=accumulator[17:0];alu_b=~dividend[47:30];alu_carry=1;end
            C1:begin alu_a=accumulator[35:18];alu_b=~dividend[65:48];alu_carry=carry;end
            C2:begin alu_a=accumulator[53:36];alu_b=~dividend[83:66];alu_carry=carry;end
            C3:begin alu_a={4'd0,accumulator[67:54]};alu_b=~{4'd0,dividend[97:84]};alu_carry=carry;end
            D0:begin alu_a=shifted_remainder[17:0];alu_b=~accumulator[17:0];alu_carry=1;end
            D1:begin alu_a=shifted_remainder[35:18];alu_b=~accumulator[35:18];alu_carry=carry;end
            D2:begin alu_a=shifted_remainder[53:36];alu_b=~accumulator[53:36];alu_carry=carry;end
            D3:begin alu_a={3'd0,shifted_remainder[68:54]};alu_b=~{4'd0,accumulator[67:54]};alu_carry=carry;end
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
        if(!I_rst_n)begin
            state<=IDLE;product_phase<=0;carry<=0;mul_bits<=0;
            accumulator<=0;work<=0;scratch<=0;mul_bit<=0;dividend<=0;
            div_bit<=0;quotient_overflow<=0;
            O_done<=0;O_result_valid<=0;O_positive<=0;O_score2_q30<=0;O_error<=0;O_cycles<=0;
        end else begin
            O_done<=0;
            if(I_cancel)begin
                state<=IDLE;O_result_valid<=0;O_positive<=0;O_score2_q30<=0;O_error<=0;O_cycles<=0;
            end else if(I_start && state!=IDLE)fail(4'd4);
            else begin
                if(state!=IDLE)O_cycles<=O_cycles+16'd1;
                case(state)
                    IDLE:if(I_start)begin
                        O_result_valid<=0;O_positive<=0;O_score2_q30<=0;O_error<=0;O_cycles<=0;
                        if(I_variance_i==0 || I_variance_t==0)fail(4'd1);
                        else if(I_variance_i>STAT_MAX || I_variance_t>STAT_MAX ||
                                I_covariance>$signed(STAT_MAX) || I_covariance<-$signed(STAT_MAX))fail(4'd2);
                        else if(I_covariance<=0)begin O_done<=1;O_result_valid<=1;end
                        else begin
                            scratch<={I_variance_t[33:0],I_variance_i[33:0]};
                            accumulator<=0;work<={34'd0,I_covariance[33:0]};
                            mul_bits<=I_covariance[33:0];mul_bit<=0;product_phase<=0;state<=M0;
                        end
                    end
                    M0:begin accumulator[17:0]<=alu_sum[17:0];carry<=alu_sum[18];state<=M1;end
                    M1:begin accumulator[35:18]<=alu_sum[17:0];carry<=alu_sum[18];state<=M2;end
                    M2:begin accumulator[53:36]<=alu_sum[17:0];carry<=alu_sum[18];state<=M3;end
                    M3:begin
                        accumulator[67:54]<=alu_sum[13:0];
                        work<={work[67:0],1'b0};mul_bits<={1'b0,mul_bits[33:1]};
                        if(mul_bit==33)state<=MEND;
                        else begin mul_bit<=mul_bit+6'd1;state<=M0;end
                    end
                    MEND:begin
                        if(!product_phase)begin
                            dividend<={accumulator,30'd0};
                            accumulator<=0;work<={34'd0,scratch[33:0]};mul_bits<=scratch[67:34];
                            mul_bit<=0;product_phase<=1;state<=M0;
                        end else state<=C0;
                    end
                    C0:begin carry<=alu_sum[18];state<=C1;end
                    C1:begin carry<=alu_sum[18];state<=C2;end
                    C2:begin carry<=alu_sum[18];state<=C3;end
                    C3:begin
                        if(!alu_sum[18])fail(4'd3);
                        else begin work<=0;div_bit<=97;quotient_overflow<=0;state<=D0;end
                    end
                    D0:begin scratch[17:0]<=alu_sum[17:0];carry<=alu_sum[18];state<=D1;end
                    D1:begin scratch[35:18]<=alu_sum[17:0];carry<=alu_sum[18];state<=D2;end
                    D2:begin scratch[53:36]<=alu_sum[17:0];carry<=alu_sum[18];state<=D3;end
                    D3:begin scratch[68:54]<=alu_sum[14:0];carry<=alu_sum[18];state<=DCOMMIT;end
                    DCOMMIT:begin
                        work<=carry?scratch:shifted_remainder;
                        dividend<={dividend[96:0],carry};
                        quotient_overflow<=quotient_overflow || quotient_high_bit;
                        if(div_bit==0)begin
                            if(quotient_overflow || quotient_high_bit)fail(4'd2);
                            else begin
                                state<=IDLE;O_done<=1;O_result_valid<=1;O_positive<=1;
                                O_score2_q30<={dividend[29:0],carry};O_error<=0;
                            end
                        end else begin div_bit<=div_bit-7'd1;state<=D0;end
                    end
                    default:fail(4'd2);
                endcase
            end
        end
    end
endmodule
