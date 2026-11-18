`timescale 1ns/1ps
module tb_pose7_top_control;
 reg clk125=0;always #4 clk125=~clk125;
 reg rst125_n=0,vision_start=0,vision_cancel=0,vision_done=0,vision_job_cancel=0;
 reg [1:0] vision_purpose=0;
 reg copy_busy=0,copy_image_lock=0,pcb_frame_lock=0;
 reg copy_reader_request=0,shared_reader_ready=0,shared_reader_valid=0,key4_copy_reset=0;
 reg report_pending=0,key2_report_pending=0,report_busy=0,key1_job_protected=0,key2_local_active=0;
 reg key4_press=0,key4_reset_active=0,key4_report_reset=0;
 wire owner_copy,frame_locked,pixel_pending,reader_reset_n,report_abort,report_clear_pending,report_stop,copy_cancel,read_allowed;
 wire [1:0] locked_purpose;
 integer checks=0;
 pose7_top_control_probe dut(.*);
 task tick;begin @(posedge clk125);#1;end endtask
 task check;input ok;input [255:0] label_text;begin
   checks=checks+1;if(ok!==1'b1)begin $display("FAIL %0s check=%0d t=%0t",label_text,checks,$time);$fatal(1);end
 end endtask
 task claim_doc;begin
   @(negedge clk125);vision_purpose=2;vision_start=1;vision_done=0;vision_cancel=0;vision_job_cancel=0;
   copy_busy=0;copy_image_lock=0;shared_reader_valid=0;shared_reader_ready=1;tick;
   check(owner_copy&&locked_purpose==2,"doc admission owns reader");
   @(negedge clk125);vision_start=0;copy_busy=1;copy_image_lock=1;tick;
 end endtask
 initial begin
   repeat(3)tick;rst125_n=1;tick;
   // PCB/local/remote reports retain their immutable accepted snapshot.
   vision_cancel=1;report_pending=1;#1;
   check(!report_abort&&!report_clear_pending,"network cancel during pending");
   report_pending=0;report_busy=1;#1;
   check(!report_abort&&!report_clear_pending,"network cancel during busy");
   report_busy=0;key2_report_pending=1;#1;
   check(!report_abort&&!report_clear_pending,"network cancel KEY2 pending");
   key2_report_pending=0;key1_job_protected=1;#1;
   check(!report_abort,"network cancel KEY1 protected");
   vision_job_cancel=1;#1;
   check(report_abort&&report_clear_pending&&copy_cancel,"explicit cancel still effective");
   vision_job_cancel=0;key4_press=1;key4_report_reset=1;#1;
   check(report_stop&&report_clear_pending,"KEY4 still stops report");
   key4_press=0;key4_report_reset=0;key1_job_protected=0;vision_cancel=0;
   claim_doc;
   @(negedge clk125);copy_reader_request=1;shared_reader_ready=1;tick;
   check(pixel_pending&&frame_locked,"accepted pixel owns frame");
   @(negedge clk125);copy_reader_request=0;shared_reader_ready=0;vision_cancel=1;tick;
   check(owner_copy&&frame_locked&&reader_reset_n&&!copy_cancel,"network loss retains acquisition");
   // Explicit cancel stops new requests, but cannot discard an outstanding read.
   @(negedge clk125);vision_job_cancel=1;copy_busy=0;copy_image_lock=0;vision_done=1;copy_reader_request=1;#1;
   check(!read_allowed&&copy_cancel,"explicit cancel fences request");tick;
   check(owner_copy&&frame_locked&&reader_reset_n,"done before drain retains owner");
   @(negedge clk125);vision_done=0;copy_reader_request=0;vision_job_cancel=0;shared_reader_valid=1;shared_reader_ready=1;tick;
   check(!pixel_pending&&owner_copy,"response drains before owner release");
   @(negedge clk125);shared_reader_valid=0;vision_cancel=0;tick;
   check(!frame_locked&&!owner_copy,"drained cancel releases owner");
   claim_doc;
   @(negedge clk125);copy_image_lock=0;copy_busy=0;vision_done=1;tick;
   check(!owner_copy&&!frame_locked,"normal local completion releases");
   @(negedge clk125);vision_done=0;
   claim_doc;
   @(negedge clk125);copy_reader_request=1;shared_reader_ready=1;tick;
   @(negedge clk125);copy_reader_request=0;shared_reader_ready=0;copy_image_lock=0;copy_busy=0;vision_job_cancel=1;vision_cancel=1;vision_done=1;tick;
   @(negedge clk125);vision_done=0;
   repeat(32)begin tick;check(owner_copy&&pixel_pending&&frame_locked&&reader_reset_n,"missing response cannot unlock");end
   // Raw board reset is the escape from an unconfirmed DDR transaction.
   @(negedge clk125);rst125_n=0;tick;
   check(!owner_copy&&!pixel_pending,"raw reset clears ownership");
   @(negedge clk125);rst125_n=1;vision_cancel=1;vision_job_cancel=0;pcb_frame_lock=1;tick;
   check(frame_locked&&reader_reset_n,"PCB frame lock preserves reader");
   $display("POSE7_TOP_CONTROL_PASS checks=%0d",checks);$finish;
 end
 initial begin #100000;$fatal(1,"control watchdog");end
endmodule
