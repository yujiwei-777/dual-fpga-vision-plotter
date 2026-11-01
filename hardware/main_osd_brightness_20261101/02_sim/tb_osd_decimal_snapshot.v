`timescale 1ns/1ps
module tb_osd_decimal_snapshot;
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,frame_start=0;
 reg [15:0] frame_number=0;reg [10:0] target_x=0;reg [9:0] target_y=0;reg [23:0] target_area=0;
 wire [19:0] frame_bcd;wire [15:0] target_x_bcd,target_y_bcd;wire [23:0] area_bcd;
 wire [75:0] packed_out={frame_bcd,target_x_bcd,target_y_bcd,area_bcd};
 osd_decimal_snapshot dut(.clk(clk),.rst_n(rst_n),.frame_start(frame_start),.frame_number(frame_number),.target_x(target_x),.target_y(target_y),.target_area(target_area),.frame_bcd(frame_bcd),.target_x_bcd(target_x_bcd),.target_y_bcd(target_y_bcd),.area_bcd(area_bcd));
 integer checks=0;reg [75:0] previous;integer i;
 task await_commit;input [75:0] old_value,new_value;integer n;begin
   for(n=1;n<=96;n=n+1)begin
     @(posedge clk);#1;checks=checks+1;
     if(packed_out!==(n==96?new_value:old_value))begin
       $display("FAIL atomic commit cycle=%0d actual=%h old=%h new=%h",n,packed_out,old_value,new_value);$fatal(1);
     end
   end
 end endtask
 task job;input [15:0] f;input [10:0] x;input [9:0] y;input [23:0] a;input [75:0] expected;reg [75:0] old_value;begin
   old_value=packed_out;@(negedge clk);frame_start=1;frame_number=f;target_x=x;target_y=y;target_area=a;
   @(posedge clk);#1;
   @(negedge clk);frame_start=0;frame_number=16'd43210;target_x=11'd777;target_y=10'd333;target_area=24'd123;
   await_commit(old_value,expected);
   repeat(7)begin @(posedge clk);#1;if(packed_out!==expected)$fatal(1,"output changed outside frame");checks=checks+1;end
 end endtask
 initial begin
   repeat(3)@(negedge clk);rst_n=1;
   job(16'd65535,11'd1280,10'd720,24'd921600,{20'h65535,16'h1280,16'h0720,24'h921600});
   job(0,0,0,0,76'd0);
   job(16'd65535,11'd2047,10'd1023,24'd999999,{20'h65535,16'h2047,16'h1023,24'h999999});
   job(16'd12345,11'd1,10'd2,24'hffffff,{20'h12345,16'h0001,16'h0002,24'h999999});
   // Restart while busy: no partial result from the abandoned job may escape.
   previous=packed_out;@(negedge clk);frame_start=1;frame_number=16'd11111;target_x=11'd111;target_y=10'd111;target_area=24'd111111;
   @(negedge clk);frame_start=0;
   repeat(30)begin @(posedge clk);#1;if(packed_out!==previous)$fatal(1,"abandoned partial commit");checks=checks+1;end
   @(negedge clk);frame_start=1;frame_number=16'd22222;target_x=11'd222;target_y=10'd222;target_area=24'd222222;
   @(posedge clk);#1;@(negedge clk);frame_start=0;
   await_commit(previous,{20'h22222,16'h0222,16'h0222,24'h222222});
   // Consecutive frame_start pulses restart the converter; the last sample wins.
   previous=packed_out;@(negedge clk);frame_start=1;frame_number=16'd33333;target_x=333;target_y=333;target_area=333333;
   @(negedge clk);frame_number=16'd44444;target_x=444;target_y=444;target_area=444444;
   @(negedge clk);frame_number=16'd55555;target_x=555;target_y=555;target_area=555555;
   @(posedge clk);#1;@(negedge clk);frame_start=0;
   await_commit(previous,{20'h55555,16'h0555,16'h0555,24'h555555});
   $display("PASS decimal snapshot checks=%0d zero/max/legal720p/saturation/held-input/restart/atomic-commit",checks);$finish;
 end
endmodule
