`timescale 1ns/1ps
module tb_pose7_ccl_frames;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,start=0,pcb_mode=1,pixel_valid=0;
 reg [23:0] pixel_rgb=0;reg [7:0] pixel_luma=255;
 wire pixel_ready,busy,done,overflow,truncated;
 wire [2:0] count;wire [255:0] boxes;wire [15:0] largest_area;wire [1:0] largest_color;wire [63:0] areas;
 integer gx,gy,cases=0,watch;
 edge_roi_ccl_shared_pcb_candidate dut(.clk(clk),.rst_n(rst_n),.start(start),.width(9'd160),.height(8'd90),
   .min_area(16'd12),.filter_shape(1'b1),.pcb_mode(pcb_mode),.pixel_valid(pixel_valid),.pixel_rgb(pixel_rgb),.pixel_luma(pixel_luma),
   .pixel_ready(pixel_ready),.busy(busy),.done(done),.overflow(overflow),.count(count),.boxes(boxes),.largest_area(largest_area),.largest_color(largest_color),.areas(areas),.truncated(truncated));
 task check;input ok;input [255:0]label_text;begin if(ok!==1'b1)begin $display("CCL_FAIL %0s case=%0d",label_text,cases);$fatal(1);end end endtask
 task run_frame;input integer pattern;begin
   cases=cases+1;@(negedge clk);pcb_mode=(pattern!=4);start=1;@(negedge clk);start=0;
   for(gy=0;gy<90;gy=gy+1)for(gx=0;gx<160;gx=gx+1)begin
      while(!pixel_ready)@(negedge clk);
      pixel_valid=1;pixel_rgb=0;pixel_luma=255;
      if(pattern==1 && gx>=20 && gx<100 && gy>=20 && gy<60)pixel_luma=40;
      if(pattern==2 && gx<80 && gy>=20 && gy<60)pixel_luma=40;
      if(pattern==3 && ((gx+gy)%2)==0)pixel_luma=0;
      if(pattern==4 && gx>=20 && gx<100 && gy>=20 && gy<60)begin pixel_rgb=24'hff0000;pixel_luma=255;end
      @(negedge clk);
   end
   pixel_valid=0;watch=0;
   while(!done && watch<1000000)begin @(negedge clk);watch=watch+1;end
   check(done,"frame completed");
   case(pattern)
    0:check(count==0&&!overflow&&boxes==0,"blank clears candidate");
    1,4:begin
       check(count==1&&!overflow&&!truncated,"one interior candidate");
       check(boxes[63:0]=={16'd60,16'd100,16'd20,16'd20},"half-open box packing");
       check(largest_area==3200&&areas[15:0]==3200,"largest candidate area");
    end
    2:begin
       check(count==1&&!overflow,"boundary candidate available");
       check(boxes[63:0]=={16'd60,16'd80,16'd20,16'd0},"boundary box passed to core");
    end
    3:check(overflow,"provisional label overflow explicit");
   endcase
   $display("CCL_FRAME_PASS pattern=%0d count=%0d overflow=%0d box0=%h area=%0d",pattern,count,overflow,boxes[63:0],largest_area);
   @(negedge clk);
 end endtask
 initial begin repeat(3)@(negedge clk);rst_n=1;run_frame(0);run_frame(1);run_frame(2);run_frame(3);run_frame(4);$display("POSE7_CCL_FRAMES_PASS cases=%0d",cases);$finish;end
 initial begin #100000000;$fatal(1,"CCL watchdog");end
endmodule
