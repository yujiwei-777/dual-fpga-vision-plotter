`timescale 1ns/1ps
// Shared exact moments for N=32,64,256 or1024 uint8 sample pairs.
// Cov=N*sum(I*T)-sum(I)*sum(T); VI/VT analogously. No centering, rounding,
// truncation, probability conversion or NCC acceptance threshold is applied.
// Only one external combinational unsigned8x8 multiplier is required. The
// three final18x18 products reuse one eighteen-bit serial add/carry datapath.
module pcb_gray_ncc_statistics #(
    parameter integer SAMPLE_TIMEOUT=100000
) (
    input wire I_clk,I_rst_n,I_start,I_cancel,
    input wire [3:0] I_count_log2,
    input wire I_sample_valid,
    output wire O_sample_ready,
    input wire [7:0] I_sample_i,I_sample_t,
    output reg [7:0] O_mul_a,O_mul_b,
    input wire [15:0] I_mul_product,
    output wire O_busy,
    output reg O_done,O_valid,
    output reg [3:0] O_error,
    output reg signed [35:0] O_covariance,
    output reg [35:0] O_variance_i,O_variance_t,
    output reg [10:0] O_samples
);
    localparam IDLE=0,WAIT_SAMPLE=1,II=2,TT=3,IT=4,
               MULT_INIT=5,MULT_LO=6,MULT_HI=7,MULT_END=8,FINISH=9;
    reg [3:0] state,count_log2;
    reg [10:0] target;
    reg [7:0] sample_i,sample_t;
    reg [17:0] sum_i,sum_t;
    reg [25:0] sum_ii,sum_tt,sum_it;
    reg [1:0] phase;
    reg [4:0] bit_index;
    reg [17:0] mul_bits;
    reg [35:0] mul_shift,mul_acc;
    reg [17:0] low_part;
    reg carry;
    reg [31:0] wait_count;
    wire [17:0] alu_a=state==MULT_LO ? mul_acc[17:0] : mul_acc[35:18];
    wire [17:0] alu_b=!mul_bits[0] ? 18'd0 : state==MULT_LO ? mul_shift[17:0] : mul_shift[35:18];
    wire [18:0] alu_sum={1'b0,alu_a}+{1'b0,alu_b}+(state==MULT_HI && carry);
    wire [35:0] scaled_ii={10'd0,sum_ii}<<count_log2;
    wire [35:0] scaled_tt={10'd0,sum_tt}<<count_log2;
    wire [35:0] scaled_it={10'd0,sum_it}<<count_log2;
    assign O_busy=state!=IDLE;
    assign O_sample_ready=state==WAIT_SAMPLE && !I_start && !I_cancel;
    always @* begin
        O_mul_a=sample_i;O_mul_b=sample_i;
        if(state==TT)begin O_mul_a=sample_t;O_mul_b=sample_t;end
        else if(state==IT)begin O_mul_a=sample_i;O_mul_b=sample_t;end
    end
    task fail;
        input [3:0] code;
        begin state<=IDLE;O_done<=1;O_valid<=0;O_error<=code;end
    endtask
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;count_log2<=0;target<=0;sample_i<=0;sample_t<=0;
            sum_i<=0;sum_t<=0;sum_ii<=0;sum_tt<=0;sum_it<=0;phase<=0;
            bit_index<=0;mul_bits<=0;mul_shift<=0;mul_acc<=0;low_part<=0;carry<=0;wait_count<=0;
            O_done<=0;O_valid<=0;O_error<=0;O_covariance<=0;O_variance_i<=0;O_variance_t<=0;O_samples<=0;
        end else begin
            O_done<=0;
            if(state!=IDLE && I_cancel)fail(4'd2);
            else if(state!=IDLE && I_start)fail(4'd3);
            else case(state)
                IDLE:if(I_start && !I_cancel)begin
                    O_valid<=0;O_error<=0;O_samples<=0;O_covariance<=0;O_variance_i<=0;O_variance_t<=0;
                    sum_i<=0;sum_t<=0;sum_ii<=0;sum_tt<=0;sum_it<=0;wait_count<=0;phase<=0;
                    count_log2<=I_count_log2;target<=11'd1<<I_count_log2;
                    if(I_count_log2!=5 && I_count_log2!=6 && I_count_log2!=8 && I_count_log2!=10)fail(4'd1);
                    else state<=WAIT_SAMPLE;
                end
                WAIT_SAMPLE:begin
                    if(I_sample_valid && O_sample_ready)begin
                        sample_i<=I_sample_i;sample_t<=I_sample_t;
                        sum_i<=sum_i+I_sample_i;sum_t<=sum_t+I_sample_t;
                        wait_count<=0;state<=II;
                    end else if(wait_count>=SAMPLE_TIMEOUT-1)fail(4'd4);
                    else wait_count<=wait_count+32'd1;
                end
                II:begin sum_ii<=sum_ii+I_mul_product;state<=TT;end
                TT:begin sum_tt<=sum_tt+I_mul_product;state<=IT;end
                IT:begin
                    sum_it<=sum_it+I_mul_product;O_samples<=O_samples+11'd1;
                    if(O_samples+11'd1==target)begin phase<=0;state<=MULT_INIT;end
                    else state<=WAIT_SAMPLE;
                end
                MULT_INIT:begin
                    mul_acc<=0;bit_index<=0;
                    mul_shift<=phase==1 ? {18'd0,sum_t}:{18'd0,sum_i};
                    mul_bits<=phase==0 ? sum_i:sum_t;
                    state<=MULT_LO;
                end
                MULT_LO:begin low_part<=alu_sum[17:0];carry<=alu_sum[18];state<=MULT_HI;end
                MULT_HI:begin
                    mul_acc<={alu_sum[17:0],low_part};
                    mul_shift<={mul_shift[34:0],1'b0};mul_bits<={1'b0,mul_bits[17:1]};
                    if(bit_index==17)state<=MULT_END;
                    else begin bit_index<=bit_index+5'd1;state<=MULT_LO;end
                end
                MULT_END:begin
                    if(phase==0)O_variance_i<=scaled_ii-mul_acc;
                    else if(phase==1)O_variance_t<=scaled_tt-mul_acc;
                    else O_covariance<=$signed(scaled_it)-$signed(mul_acc);
                    if(phase==2)state<=FINISH;
                    else begin phase<=phase+2'd1;state<=MULT_INIT;end
                end
                FINISH:begin O_done<=1;O_valid<=1;O_error<=0;state<=IDLE;end
                default:fail(4'd15);
            endcase
        end
    end
endmodule
