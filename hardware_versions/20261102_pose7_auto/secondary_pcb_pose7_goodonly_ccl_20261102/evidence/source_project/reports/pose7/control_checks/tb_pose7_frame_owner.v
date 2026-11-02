`timescale 1ns/1ps
module tb_pose7_frame_owner;
 reg clk=0;always #4 clk=~clk;
 reg rst_n=0,start=0,auto_busy=0,cancel=0,teach_good=0,auto_done=0,auto_cancel_seen=0;
 reg [6:0] state=0;reg [1:0] purpose=1,purpose_q=1;
 reg pcb_ccl_pending=0,reader_ready=1,reader_request=0;
 wire pcb_frame_lock,processing_rst_n;integer checks=0;
 pose7_frame_owner_probe dut(.*);
 task tick;begin @(posedge clk);#1;end endtask
 task check;input ok;input [255:0]msg;begin checks=checks+1;if(ok!==1'b1)begin $display("OWNER_FAIL %0s",msg);$fatal(1);end end endtask
 initial begin
  repeat(3)tick;rst_n=1;tick;check(!pcb_frame_lock,"reset owner clear");
  @(negedge clk);cancel=1;start=1;tick;check(!pcb_frame_lock&&!processing_rst_n,"cancelled start not admitted");
  @(negedge clk);cancel=0;tick;check(pcb_frame_lock&&processing_rst_n,"accepted frame owns lock");
  @(negedge clk);start=0;state=4;cancel=1;repeat(5)begin tick;check(pcb_frame_lock&&processing_rst_n,"cancel cannot async clear owner");end
  @(negedge clk);state=82;pcb_ccl_pending=1;reader_ready=0;repeat(10)begin tick;check(pcb_frame_lock,"outstanding CCL keeps frame");end
  @(negedge clk);pcb_ccl_pending=0;reader_ready=1;tick;check(!pcb_frame_lock&&!processing_rst_n,"safe drain clears raw owner");
  @(negedge clk);state=0;cancel=0;start=1;tick;check(pcb_frame_lock,"second task admissible");
  @(negedge clk);start=0;state=81;auto_busy=1;auto_done=0;cancel=1;auto_cancel_seen=1;tick;check(pcb_frame_lock,"core drain keeps frame");
  @(negedge clk);auto_done=1;auto_busy=0;tick;check(!pcb_frame_lock,"core safe done releases cancelled frame");
  @(negedge clk);cancel=0;auto_cancel_seen=0;auto_done=0;state=0;start=1;tick;
  @(negedge clk);start=0;state=33;tick;check(!pcb_frame_lock,"normal finish releases frame");
  $display("POSE7_FRAME_OWNER_PASS checks=%0d",checks);$finish;
 end
 initial begin #100000;$fatal(1,"owner watchdog");end
endmodule
