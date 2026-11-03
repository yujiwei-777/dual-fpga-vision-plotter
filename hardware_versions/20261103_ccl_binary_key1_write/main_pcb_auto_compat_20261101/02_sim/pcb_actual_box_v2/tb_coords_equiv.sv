`timescale 1ns/1ps
module tb_coords_equiv;
 reg S_multi_px_valid=0,S_pcb_window_on=0;
 reg [511:0] S_multi_px_boxes=0;
 reg [10:0] S_multi_cx=0,S_show_x0=0,S_show_x1=0,S_show_cx=0;
 reg [9:0] S_multi_cy=0,S_show_y0=0,S_show_y1=0,S_show_cy=0;
`include "actual_coords.vh"
 wire [10:0] old_x0=S_pcb_window_on?S_show_x0:(S_multi_px_valid?S_multi_px_boxes[10:0]:S_show_x0);
 wire [10:0] old_x1=S_pcb_window_on?S_show_x1:(S_multi_px_valid?S_multi_px_boxes[42:32]-11'd1:S_show_x1);
 wire [10:0] old_cx=S_pcb_window_on?S_show_cx:(S_multi_px_valid?S_multi_cx:S_show_cx);
 wire [9:0] old_y0=S_pcb_window_on?S_show_y0:(S_multi_px_valid?S_multi_px_boxes[25:16]:S_show_y0);
 wire [9:0] old_y1=S_pcb_window_on?S_show_y1:(S_multi_px_valid?S_multi_px_boxes[57:48]-10'd1:S_show_y1);
 wire [9:0] old_cy=S_pcb_window_on?S_show_cy:(S_multi_px_valid?S_multi_cy:S_show_cy);
 integer i,j,k,checks=0;
 reg [31:0] rng=32'h50781113;
 function [31:0] step(input [31:0] x);begin step=(x<<1)^{32{x[31]}}&32'h04c11db7;end endfunction
 task check;begin #1;checks=checks+1;
  if({S_box_x0,S_box_x1,S_box_cx,S_box_y0,S_box_y1,S_box_cy}!=={old_x0,old_x1,old_cx,old_y0,old_y1,old_cy})
   $fatal(1,"coordinate mux mismatch check=%0d pcb=%b multi=%b",checks,S_pcb_window_on,S_multi_px_valid);
 end endtask
 initial begin
  for(i=0;i<100000;i=i+1)begin
   rng=step(rng);S_show_x0=rng;S_show_x1=rng>>11;S_show_cx=rng>>21;
   rng=step(rng);S_show_y0=rng;S_show_y1=rng>>10;S_show_cy=rng>>20;
   rng=step(rng);S_multi_px_boxes[31:0]=rng;
   rng=step(rng);S_multi_px_boxes[63:32]=rng;S_multi_cx=rng;S_multi_cy=rng>>11;
   for(j=0;j<2;j=j+1)for(k=0;k<2;k=k+1)begin S_pcb_window_on=j;S_multi_px_valid=k;check();end
  end
  // Boundary and underflow behavior must remain bit-exact even on invalid boxes.
  for(i=0;i<3;i=i+1)begin
   S_multi_px_boxes=(i==0)?512'd0:(i==1)?{512{1'b1}}:512'd1;
   for(j=0;j<2;j=j+1)for(k=0;k<2;k=k+1)begin S_pcb_window_on=j;S_multi_px_valid=k;check();end
  end
  $display("PASS six-coordinate mux equivalence checks=%0d random_seed=50781113",checks);$finish;
 end
endmodule
