`timescale 1ns/1ps
// Serial rounded area reduction: half[y,x]=(sum canonical[2y:2y+2,2x:2x+2]+2)>>2.
// Canonical bank0[8192..17407], packed low-address byte in low8.
// Half words0..1023 ->bank0[17408..18431], words1024..2303 ->bank1[5004..6283].
// Fixed two-edge registered-read contract; no multipliers/dividers or new RAM.
module pcb_half_image_serial(
    input wire I_clk,I_rst_n,I_start,I_cancel,I_canonical_valid,
    output wire O_busy,
    output reg O_done,O_valid,O_fault,
    output reg [3:0] O_error,
    output wire O_ws_rd_bank,
    output reg [14:0] O_ws_rd_addr,
    input wire [15:0] I_ws_rd_data,
    output wire O_ws_we,
    output reg O_ws_wbank,
    output reg [14:0] O_ws_waddr,
    output reg [15:0] O_ws_wdata,
    output reg [12:0] O_pixels,
    output reg [13:0] O_reads
);
    localparam IDLE=0,TOP_ADDR=1,TOP_WAIT=2,TOP_DATA=3,BOTTOM_WAIT=4,BOTTOM_DATA=5,NEXT=6,FENCE=7;
    reg [2:0] state;
    reg [6:0] x;reg [5:0] y;
    reg [12:0] index;
    reg [8:0] top_sum;
    reg [7:0] even_pixel;
    reg we;
    wire [9:0] total={1'b0,top_sum}+{2'b0,I_ws_rd_data[7:0]}+{2'b0,I_ws_rd_data[15:8]}+10'd2;
    wire [7:0] average=total[9:2];
    wire [11:0] word_index=index[12:1];
    assign O_busy=state!=IDLE;
    assign O_ws_rd_bank=1'b0;
    assign O_ws_we=we&&!I_cancel&&!I_start;
    always @(posedge I_clk or negedge I_rst_n)begin
        if(!I_rst_n)begin
            state<=IDLE;x<=0;y<=0;index<=0;top_sum<=0;even_pixel<=0;we<=0;
            O_done<=0;O_valid<=0;O_fault<=0;O_error<=0;O_ws_rd_addr<=8192;
            O_ws_wbank<=0;O_ws_waddr<=17408;O_ws_wdata<=0;O_pixels<=0;O_reads<=0;
        end else begin
            O_done<=0;O_valid<=0;we<=0;
            if(state!=IDLE&&(I_cancel||I_start))begin
                O_done<=1;O_fault<=1;O_error<=I_cancel?4'd4:4'd6;state<=IDLE;
            end else case(state)
                IDLE:if(I_start&&!I_cancel)begin
                    O_fault<=0;O_error<=0;O_pixels<=0;O_reads<=0;x<=0;y<=0;index<=0;
                    if(!I_canonical_valid)begin O_fault<=1;O_error<=1;O_done<=1;end
                    else state<=TOP_ADDR;
                end
                TOP_ADDR:begin
                    O_ws_rd_addr<=15'd8192+({9'd0,y}<<7)+({9'd0,y}<<6)+{8'd0,x};state<=TOP_WAIT;
                end
                TOP_WAIT:state<=TOP_DATA;
                TOP_DATA:begin
                    top_sum<={1'b0,I_ws_rd_data[7:0]}+{1'b0,I_ws_rd_data[15:8]};
                    O_ws_rd_addr<=O_ws_rd_addr+15'd96;O_reads<=O_reads+1'b1;state<=BOTTOM_WAIT;
                end
                BOTTOM_WAIT:state<=BOTTOM_DATA;
                BOTTOM_DATA:begin
                    O_reads<=O_reads+1'b1;O_pixels<=O_pixels+1'b1;
                    if(!index[0])even_pixel<=average;
                    else begin
                        we<=1;O_ws_wdata<={average,even_pixel};
                        if(word_index<1024)begin O_ws_wbank<=0;O_ws_waddr<=15'd17408+word_index;end
                        else begin O_ws_wbank<=1;O_ws_waddr<=15'd5004+word_index-15'd1024;end
                    end
                    state<=NEXT;
                end
                NEXT:begin
                    if(index==4607)state<=FENCE;
                    else begin
                        index<=index+1'b1;
                        if(x==95)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
                        state<=TOP_ADDR;
                    end
                end
                FENCE:begin
                    O_done<=1;O_valid<=O_pixels==4608&&O_reads==9216;
                    O_fault<=O_pixels!=4608||O_reads!=9216;
                    if(O_pixels!=4608||O_reads!=9216)O_error<=8;
                    state<=IDLE;
                end
                default:begin O_done<=1;O_fault<=1;O_error<=15;state<=IDLE;end
            endcase
        end
    end
endmodule
