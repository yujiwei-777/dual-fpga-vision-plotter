// The camera/AWB stream cannot be backpressured. Buffer one row plus margin
// while CART drains the last row. At 720p the vertical blank must provide
// at least WIDTH/4+pipeline cycles; no whole-frame storage is allocated.
module style_input_fifo #(parameter integer DEPTH=512, parameter RAM_STYLE="bram")(
    input wire clk,rst_n,
    input wire [102:0] in_data,input wire in_valid,
    input wire out_ready,
    output reg [102:0] out_data,output reg out_valid,
    output reg overflow
);
    localparam AW=$clog2(DEPTH);
    (* ram_style=RAM_STYLE *) reg [102:0] mem[0:DEPTH-1];
    reg [AW-1:0] wr,rd;
    reg [AW:0] count;
    function [AW-1:0] ptr_next;
        input [AW-1:0] ptr;
        begin
            // DEPTH is allowed to be non-power-of-two so the live video
            // queue can be sized to one complete row plus a small margin
            // without paying for the next power-of-two worth of LUT RAM.
            ptr_next = (ptr == DEPTH-1) ? {AW{1'b0}} : ptr + 1'b1;
        end
    endfunction
    wire pop=(count!=0)&&(!out_valid||out_ready);
    wire push=in_valid && ((count<DEPTH)||pop);
    always @(posedge clk)begin
        if(rst_n)begin
            if(push)mem[wr]<=in_data;
            if(pop)out_data<=mem[rd];
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin wr<=0;rd<=0;count<=0;out_valid<=0;overflow<=0;end
        else begin
            if(in_valid&&!push)overflow<=1;
            if(push)wr<=ptr_next(wr);
            if(pop)rd<=ptr_next(rd);
            case({push,pop})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:count<=count;
            endcase
            if(!out_valid||out_ready)out_valid<=pop;
        end
    end
endmodule
