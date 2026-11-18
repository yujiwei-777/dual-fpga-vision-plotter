`timescale 1ns/1ps
// Exact area-average gray input for the GOOD-only locator. Standalone until
// the locator/registration/coverage chain is qualified and integrated.
// The source endpoint must drain before reset/rearm. Cancellation drains any
// accepted request; a timed-out endpoint locks until reset, never reuses it.
// Workspace has an unconditional synchronous write port, without backpressure.
module pcb_gray_coarse_capture #(
    parameter integer COARSE_W=128,
    parameter integer COARSE_H=72,
    parameter integer BLOCK_SIDE=10,
    parameter integer SOURCE_W=1280,
    parameter integer SOURCE_H=720,
    parameter integer WORD_BASE=8192,
    parameter integer WAIT_TIMEOUT=4096
) (
    input wire I_clk,I_rst_n,I_start,I_cancel,I_frame_valid,
    output wire O_pixel_request,
    output reg [10:0] O_pixel_x,
    output reg [9:0] O_pixel_y,
    input wire I_pixel_ready,I_pixel_valid,
    input wire [7:0] I_pixel_y8,
    output reg O_ws_we,
    output reg [14:0] O_ws_waddr,
    output reg [15:0] O_ws_wdata,
    output wire O_busy,
    output reg O_done,O_fault,
    output reg [3:0] O_error,
    output reg [19:0] O_samples,
    output reg [13:0] O_pixels_written
);
    localparam IDLE=0,REQUEST=1,RESPONSE=2,DIVIDE=3,STORE=4,
               ADVANCE=5,FENCE=6,DRAIN=7,LOCKED=8;
    localparam integer DENOM=BLOCK_SIDE*BLOCK_SIDE;
    localparam integer COUNT=COARSE_W*COARSE_H;
    localparam integer VALID_CONFIG=(COARSE_W>0 && COARSE_W<=256 && COARSE_H>0 && COARSE_H<=256 &&
        BLOCK_SIDE>0 && BLOCK_SIDE<=10 && COUNT<16384 && COUNT%2==0 &&
        COARSE_W*BLOCK_SIDE==SOURCE_W && COARSE_H*BLOCK_SIDE==SOURCE_H &&
        SOURCE_W<=1280 && SOURCE_H<=720 && WAIT_TIMEOUT>0 &&
        WORD_BASE>=8192 && WORD_BASE+(COUNT/2)<=18432);
    reg [3:0] state;
    reg [7:0] coarse_x,coarse_y;
    reg [3:0] block_x,block_y;
    reg [10:0] base_x;
    reg [9:0] base_y;
    reg [14:0] sum,numerator,quotient;
    reg [7:0] remainder;
    reg [3:0] divide_bit;
    reg [7:0] even_pixel,average;
    reg [31:0] wait_count;
    wire transfer=O_pixel_request && I_pixel_ready;
    wire response=(state==RESPONSE && I_pixel_valid) || (transfer && I_pixel_valid);
    wire [8:0] trial={remainder,numerator[14]};
    wire [15:0] rounded={1'b0,sum}+{8'd0,I_pixel_y8}+(DENOM/2);
    assign O_busy=state!=IDLE;
    assign O_pixel_request=state==REQUEST && !I_cancel && !I_start;

    task fault;
        input [3:0] code;
        begin
            O_fault<=1;O_error<=code;O_done<=1;O_ws_we<=0;
            state<=LOCKED;
        end
    endtask

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            state<=IDLE;coarse_x<=0;coarse_y<=0;block_x<=0;block_y<=0;
            base_x<=0;base_y<=0;O_pixel_x<=0;O_pixel_y<=0;
            sum<=0;numerator<=0;quotient<=0;remainder<=0;divide_bit<=0;
            even_pixel<=0;average<=0;wait_count<=0;
            O_ws_we<=0;O_ws_waddr<=0;O_ws_wdata<=0;
            O_done<=0;O_fault<=0;O_error<=0;O_samples<=0;O_pixels_written<=0;
        end else begin
            O_done<=0;O_ws_we<=0;
            if(state==LOCKED) begin
                // A source timeout leaves endpoint ownership uncertain.
                // Neither start nor cancel may silently unlock it.
                state<=LOCKED;
            end else if(I_cancel || (I_start && state!=IDLE)) begin
                O_fault<=1;O_error<=I_cancel ? 4'd2 : 4'd3;
                wait_count<=0;
                if((state==RESPONSE || state==DRAIN) && !I_pixel_valid) state<=DRAIN;
                else begin state<=IDLE;O_done<=1;end
            end else case(state)
                IDLE:if(I_start) begin
                    O_fault<=0;O_error<=0;O_samples<=0;O_pixels_written<=0;
                    coarse_x<=0;coarse_y<=0;block_x<=0;block_y<=0;
                    base_x<=0;base_y<=0;O_pixel_x<=0;O_pixel_y<=0;
                    sum<=0;wait_count<=0;
                    if(!VALID_CONFIG || !I_frame_valid) begin
                        O_fault<=1;O_error<=4'd1;O_done<=1;
                    end else state<=REQUEST;
                end
                REQUEST,RESPONSE:begin
                    if(response) begin
                        O_samples<=O_samples+20'd1;wait_count<=0;
                        if(block_x==BLOCK_SIDE-1 && block_y==BLOCK_SIDE-1) begin
                            numerator<=rounded[14:0];quotient<=0;remainder<=0;
                            divide_bit<=14;state<=DIVIDE;
                        end else begin
                            sum<=sum+{7'd0,I_pixel_y8};
                            if(block_x==BLOCK_SIDE-1) begin
                                block_x<=0;block_y<=block_y+4'd1;
                                O_pixel_x<=base_x;O_pixel_y<=O_pixel_y+10'd1;
                            end else begin block_x<=block_x+4'd1;O_pixel_x<=O_pixel_x+11'd1;end
                            state<=REQUEST;
                        end
                    end else if(state==REQUEST && transfer) begin
                        state<=RESPONSE;wait_count<=0;
                    end else if(wait_count>=WAIT_TIMEOUT-1) fault(4'd4);
                    else wait_count<=wait_count+32'd1;
                end
                DIVIDE:begin
                    numerator<={numerator[13:0],1'b0};
                    if(trial>=DENOM) begin
                        remainder<=trial-DENOM;quotient<={quotient[13:0],1'b1};
                    end else begin remainder<=trial[7:0];quotient<={quotient[13:0],1'b0};end
                    if(divide_bit==0) begin
                        average<={quotient[6:0],trial>=DENOM};state<=STORE;
                    end else divide_bit<=divide_bit-4'd1;
                end
                STORE:begin
                    O_pixels_written<=O_pixels_written+14'd1;
                    if(!O_pixels_written[0]) even_pixel<=average;
                    else begin
                        O_ws_we<=1;
                        O_ws_waddr<=WORD_BASE+O_pixels_written[13:1];
                        O_ws_wdata<={average,even_pixel};
                    end
                    if(O_pixels_written==COUNT-1) state<=FENCE;
                    else state<=ADVANCE;
                end
                ADVANCE:begin
                    block_x<=0;block_y<=0;sum<=0;wait_count<=0;
                    if(coarse_x==COARSE_W-1) begin
                        coarse_x<=0;coarse_y<=coarse_y+8'd1;base_x<=0;
                        base_y<=base_y+BLOCK_SIDE;
                        O_pixel_x<=0;O_pixel_y<=base_y+BLOCK_SIDE;
                    end else begin
                        coarse_x<=coarse_x+8'd1;base_x<=base_x+BLOCK_SIDE;
                        O_pixel_x<=base_x+BLOCK_SIDE;O_pixel_y<=base_y;
                    end
                    state<=REQUEST;
                end
                FENCE:begin
                    // The last registered write commits on this edge.
                    O_done<=1;state<=IDLE;
                end
                DRAIN:begin
                    if(I_pixel_valid) begin O_done<=1;state<=IDLE;end
                    else if(wait_count>=WAIT_TIMEOUT-1) fault(4'd5);
                    else wait_count<=wait_count+32'd1;
                end
                default:fault(4'd15);
            endcase
        end
    end
endmodule
