`timescale 1ns/1ps
// Independent area experiment. Same exact moment interface as the serial
// reference. One registered unsigned 18x18 multiplier serves all products;
// the legacy external 8x8 product port is retained for harness compatibility.
// The owner may observe moment outputs only when O_valid && O_done.
module pcb_gray_ncc_statistics_dsp #(
    parameter integer SAMPLE_TIMEOUT=100000
) (
    input wire I_clk,I_rst_n,I_start,I_cancel,
    input wire [3:0] I_count_log2,
    input wire I_sample_valid,
    output wire O_sample_ready,
    input wire [7:0] I_sample_i,I_sample_t,
    output wire [7:0] O_mul_a,O_mul_b,
    input wire [15:0] I_mul_product,
    output wire O_busy,
    output reg O_done,O_valid,
    output reg [3:0] O_error,
    output reg signed [35:0] O_covariance,
    output reg [35:0] O_variance_i,O_variance_t,
    output reg [10:0] O_samples
);
    localparam IDLE=0,WAIT_SAMPLE=1,PRODUCT_WAIT=2,ACCUMULATE=3,
               FINAL_INIT=4,FINAL_WAIT=5,FINAL_LOW=6,FINAL_HIGH=7,FINISH=8;
    localparam integer WAIT_WIDTH=SAMPLE_TIMEOUT>1?$clog2(SAMPLE_TIMEOUT):1;
    reg [3:0] state,count_log2;
    reg [1:0] phase;
    reg [10:0] target;
    reg [7:0] sample_i,sample_t;
    reg [17:0] sum_i,sum_t;
    reg [25:0] sum_ii,sum_tt,sum_it;
    reg [17:0] mul_a,mul_b;
    // No asynchronous reset on the DSP pipeline register. Every use follows
    // an explicit settling state; stale/reset products are never consumed.
    reg [35:0] product;
    always @(posedge I_clk) product <= mul_a * mul_b;
    reg [17:0] difference_low;
    reg carry;
    reg [WAIT_WIDTH-1:0] wait_count;
    wire [25:0] selected_sum=phase==0?sum_ii:phase==1?sum_tt:sum_it;
    reg [35:0] scaled_sum;
    always @* begin
        case(count_log2)
            4'd5:scaled_sum={5'd0,selected_sum,5'd0};
            4'd6:scaled_sum={4'd0,selected_sum,6'd0};
            4'd8:scaled_sum={2'd0,selected_sum,8'd0};
            4'd10:scaled_sum={selected_sum,10'd0};
            default:scaled_sum=0;
        endcase
    end
    wire [18:0] subtract_sum = state==FINAL_LOW ?
        ({1'b0,scaled_sum[17:0]}+{1'b0,~product[17:0]}+19'd1):
        ({1'b0,scaled_sum[35:18]}+{1'b0,~product[35:18]}+carry);
    // A single accumulator adder, selected before the arithmetic.
    wire [25:0] accumulated_sum=selected_sum+{10'd0,product[15:0]};
    assign O_mul_a=sample_i;
    assign O_mul_b=sample_t;
    assign O_busy=state!=IDLE;
    assign O_sample_ready=state==WAIT_SAMPLE && !I_start && !I_cancel;
    task fail;
        input [3:0] code;
        begin state<=IDLE;O_done<=1;O_valid<=0;O_error<=code;end
    endtask
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=IDLE;count_log2<=0;phase<=0;target<=0;
            sample_i<=0;sample_t<=0;sum_i<=0;sum_t<=0;
            sum_ii<=0;sum_tt<=0;sum_it<=0;mul_a<=0;mul_b<=0;
            difference_low<=0;carry<=0;wait_count<=0;
            O_done<=0;O_valid<=0;O_error<=0;O_covariance<=0;
            O_variance_i<=0;O_variance_t<=0;O_samples<=0;
        end else begin
            O_done<=0;
            if(state!=IDLE && I_cancel) fail(4'd2);
            else if(state!=IDLE && I_start) fail(4'd3);
            else case(state)
                IDLE:if(I_start && !I_cancel)begin
                    O_valid<=0;O_error<=0;O_samples<=0;
                    O_covariance<=0;O_variance_i<=0;O_variance_t<=0;
                    sum_i<=0;sum_t<=0;sum_ii<=0;sum_tt<=0;sum_it<=0;
                    wait_count<=0;phase<=0;count_log2<=I_count_log2;
                    target<=11'd1<<I_count_log2;
                    if(I_count_log2!=5 && I_count_log2!=6 &&
                       I_count_log2!=8 && I_count_log2!=10) fail(4'd1);
                    else state<=WAIT_SAMPLE;
                end
                WAIT_SAMPLE:begin
                    if(I_sample_valid && O_sample_ready)begin
                        sample_i<=I_sample_i;sample_t<=I_sample_t;
                        sum_i<=sum_i+I_sample_i;sum_t<=sum_t+I_sample_t;
                        mul_a<={10'd0,I_sample_i};mul_b<={10'd0,I_sample_i};
                        phase<=0;wait_count<=0;state<=PRODUCT_WAIT;
                    end else if(wait_count>=SAMPLE_TIMEOUT-1) fail(4'd4);
                    else wait_count<=wait_count+1'b1;
                end
                PRODUCT_WAIT:state<=ACCUMULATE;
                ACCUMULATE:begin
                    if(phase==0)begin
                        sum_ii<=accumulated_sum;
                        mul_a<={10'd0,sample_t};mul_b<={10'd0,sample_t};
                        phase<=1;state<=PRODUCT_WAIT;
                    end else if(phase==1)begin
                        sum_tt<=accumulated_sum;
                        mul_a<={10'd0,sample_i};mul_b<={10'd0,sample_t};
                        phase<=2;state<=PRODUCT_WAIT;
                    end else begin
                        sum_it<=accumulated_sum;O_samples<=O_samples+1'b1;
                        if(O_samples+11'd1==target)begin phase<=0;state<=FINAL_INIT;end
                        else state<=WAIT_SAMPLE;
                    end
                end
                FINAL_INIT:begin
                    mul_a<=phase==1?sum_t:sum_i;
                    mul_b<=phase==0?sum_i:sum_t;
                    state<=FINAL_WAIT;
                end
                FINAL_WAIT:state<=FINAL_LOW;
                FINAL_LOW:begin
                    difference_low<=subtract_sum[17:0];carry<=subtract_sum[18];
                    state<=FINAL_HIGH;
                end
                FINAL_HIGH:begin
                    if(phase==0)O_variance_i<={subtract_sum[17:0],difference_low};
                    else if(phase==1)O_variance_t<={subtract_sum[17:0],difference_low};
                    else O_covariance<={subtract_sum[17:0],difference_low};
                    if(phase==2)state<=FINISH;
                    else begin phase<=phase+1'b1;state<=FINAL_INIT;end
                end
                FINISH:begin O_done<=1;O_valid<=1;O_error<=0;state<=IDLE;end
                default:fail(4'd15);
            endcase
        end
    end
endmodule
