// Exact positive NCC squared Q30. Independent fractional-divider variant.
// The 36-bit guards, zero/negative-C handling and Cauchy error3 match original.
// One registered shared 34x34 multiplier computes C*C then VI*VT. Since the
// Cauchy guard proves C*C<=VI*VT, equality returns 1<<30 directly; otherwise
// remainder starts at C*C and exactly 30 fractional restoring steps produce
// floor((C*C<<30)/(VI*VT)). No 98-bit dividend or serial multiplier exists.
// Each trial remainder is 69 bits. Positive requests: 6 clocks if equal,
// otherwise exactly 156 clocks. Cauchy rejection: 6 clocks. DSP count is to be
// measured in TD; the RTL contains one shared 34x34 multiply expression.
module pcb_ncc_normalize_1024_fraction_v4 (
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
    localparam [3:0] IDLE=0,SQUARE=1,DENOM=2,C0=3,C1=4,C2=5,C3=6,
        D0=7,D1=8,D2=9,D3=10,DCOMMIT=11;
    localparam [35:0] STAT_MAX=36'd17045913600;
    reg [3:0] state;
    reg carry,comparison_zero;
    reg [67:0] denominator;
    reg [68:0] work,scratch;
    reg [4:0] rounds_left;
    wire [33:0] mul_a=state==IDLE?I_covariance[33:0]:work[33:0];
    wire [33:0] mul_b=state==IDLE?I_covariance[33:0]:work[67:34];
    reg [67:0] product;
    // At acceptance this captures C*C. On SQUARE it captures VI*VT from
    // pre-edge work, while work itself is overwritten with the fresh C*C.
    // The product register is deliberately not asynchronously reset.
    always @(posedge I_clk)product<=mul_a*mul_b;
    reg [17:0] alu_a,alu_b;
    reg alu_carry;
    wire [18:0] alu_sum={1'b0,alu_a}+{1'b0,alu_b}+alu_carry;
    wire [68:0] trial_remainder={work[67:0],1'b0};
    assign O_busy=state!=IDLE;

    always @*begin
        alu_a=0;alu_b=0;alu_carry=0;
        case(state)
            C0:begin alu_a=denominator[17:0];alu_b=~work[17:0];alu_carry=1;end
            C1:begin alu_a=denominator[35:18];alu_b=~work[35:18];alu_carry=carry;end
            C2:begin alu_a=denominator[53:36];alu_b=~work[53:36];alu_carry=carry;end
            C3:begin alu_a={4'd0,denominator[67:54]};alu_b=~{4'd0,work[67:54]};alu_carry=carry;end
            D0:begin alu_a=trial_remainder[17:0];alu_b=~denominator[17:0];alu_carry=1;end
            D1:begin alu_a=trial_remainder[35:18];alu_b=~denominator[35:18];alu_carry=carry;end
            D2:begin alu_a=trial_remainder[53:36];alu_b=~denominator[53:36];alu_carry=carry;end
            D3:begin alu_a={3'd0,trial_remainder[68:54]};alu_b=~{4'd0,denominator[67:54]};alu_carry=carry;end
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

    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;carry<=0;comparison_zero<=0;denominator<=0;work<=0;scratch<=0;rounds_left<=0;
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
                        else begin work<={1'b0,I_variance_t[33:0],I_variance_i[33:0]};state<=SQUARE;end
                    end
                    SQUARE:begin work<={1'b0,product};state<=DENOM;end
                    DENOM:begin denominator<=product;state<=C0;end
                    C0:begin carry<=alu_sum[18];comparison_zero<=alu_sum[17:0]==0;state<=C1;end
                    C1:begin carry<=alu_sum[18];comparison_zero<=comparison_zero && alu_sum[17:0]==0;state<=C2;end
                    C2:begin carry<=alu_sum[18];comparison_zero<=comparison_zero && alu_sum[17:0]==0;state<=C3;end
                    C3:begin
                        if(!alu_sum[18])fail(4'd3);
                        else if(comparison_zero && alu_sum[13:0]==0)begin
                            state<=IDLE;O_done<=1;O_result_valid<=1;O_positive<=1;O_score2_q30<=31'h40000000;
                        end else begin rounds_left<=30;state<=D0;end
                    end
                    D0:begin scratch[17:0]<=alu_sum[17:0];carry<=alu_sum[18];state<=D1;end
                    D1:begin scratch[35:18]<=alu_sum[17:0];carry<=alu_sum[18];state<=D2;end
                    D2:begin scratch[53:36]<=alu_sum[17:0];carry<=alu_sum[18];state<=D3;end
                    D3:begin scratch[68:54]<=alu_sum[14:0];carry<=alu_sum[18];state<=DCOMMIT;end
                    DCOMMIT:begin
                        work<=carry?scratch:trial_remainder;
                        O_score2_q30<={O_score2_q30[29:0],carry};
                        if(rounds_left==1)begin state<=IDLE;O_done<=1;O_result_valid<=1;O_positive<=1;O_error<=0;end
                        else begin rounds_left<=rounds_left-5'd1;state<=D0;end
                    end
                    default:fail(4'd2);
                endcase
            end
        end
    end
endmodule
