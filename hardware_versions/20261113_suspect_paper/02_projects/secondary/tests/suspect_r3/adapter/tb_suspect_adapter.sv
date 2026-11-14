
`timescale 1ns/1ps
module tb_suspect_adapter;
 reg clk=0;always #4 clk=~clk;
 reg rst=0,start=0,cancel=0;wire busy,lock,done,valid,bbox,sv;wire[1:0]status;wire[63:0]sb;
 wire signed[15:0]ma;wire signed[7:0]mw;wire signed[23:0]mp=ma*mw;
 integer g,tests=0,n,leftx,rightx,topy,bottomy,ex0,ey0,ex1,ey1;
 reg[2:0]count=1;
 pcb_ccl_binary_core #(.WEIGHTS_MEM("D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_suspect_robust_20261111/model/experiments/conv4_4/weights.mem"),.BIASES_MEM("D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_suspect_robust_20261111/model/experiments/conv4_4/biases.mem"),.SUSPECT_CONST_MEM("D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_suspect_robust_20261111/model/suspect/mad_negative_constants.mem"))dut(
  .clk(clk),.rst_n(rst),.start(start),.cancel(cancel),.frame_valid(1'b1),.model_valid(1'b1),.job_id(32'd7),
  .I_ccl_count(count),.I_ccl_boxes(256'h003c0078000a0014),.I_ccl_overflow(1'b0),.I_ccl_truncated(1'b0),
  .busy(busy),.frame_lock(lock),.done(done),.result_valid(valid),.status(status),.bbox_valid(bbox),
  .suspect_valid(sv),.suspect_box(sb),.pixel_ready(1'b0),.pixel_valid(1'b0),.pixel_y8(8'd0),
  .ws_rd_data(16'd0),.mac_a(ma),.mac_w(mw),.mac_product_ext(mp));
 task fail(input string s);begin $display("SUSPECT_ADAPTER_FAIL grid%0d state%0d %s",g,dut.state,s);$fatal;end endtask
 task reset;begin rst=0;start=0;cancel=0;repeat(4)@(negedge clk);rst=1;repeat(3)@(negedge clk);end endtask
 task enter;begin
  dut.state=12;dut.core_enable=1;dut.xmin=160;dut.xmax=960;dut.ymin=80;dut.ymax=480;
  dut.roi_width=800;dut.roi_height=400;
 end endtask
 task complete;begin #1;
  n=0;while(!done&&n<32)begin
   if(!lock)fail("ownership dropped before wrapper done");
   @(negedge clk);n=n+1;
  end
  if(!done||busy||lock)fail("completion/ownership");
 end endtask
 task forcedone(input integer cls,input integer margin);begin
  force dut.core_done=1;force dut.core_class=cls;force dut.core_margin=margin;
  force dut.core_score=8'd100;force dut.core_sat=0;force dut.core_suspect_valid=1;force dut.core_suspect_grid=g;
 end endtask
 task unforce;begin
  release dut.core_done;release dut.core_class;release dut.core_margin;release dut.core_score;
  release dut.core_sat;release dut.core_suspect_valid;release dut.core_suspect_grid;
 end endtask
 initial begin
  for(g=0;g<16;g=g+1)begin
   reset();enter();forcedone(1,100);complete();
   leftx=160+(g%4)*200;rightx=leftx+200;topy=80+(g/4)*100;bottomy=topy+100;
   ex0=leftx-100;if(ex0<160)ex0=160;ex1=rightx+100;if(ex1>960)ex1=960;
   ey0=topy-50;if(ey0<80)ey0=80;ey1=bottomy+50;if(ey1>480)ey1=480;
   if(!sv||!valid||!bbox||status!=1||sb[15:0]!=ex0||sb[31:16]!=ey0||sb[47:32]!=ex1||sb[63:48]!=ey1)fail("2x exact mapped half-open box");
   unforce();tests=tests+1;
  end
  // A subsequent accepted no-target task clears the previous stored region.
  count=0;start=1;@(negedge clk);start=0;complete();
  if(sv||sb||status!=2||bbox)fail("no-target retained old box");tests=tests+1;
  reset();enter();forcedone(0,100);complete();if(sv||sb||status!=0)fail("PASS emitted region");unforce();tests=tests+1;
  reset();enter();forcedone(1,31);complete();if(sv||sb||status!=2)fail("REVIEW emitted region");unforce();tests=tests+1;
  reset();enter();forcedone(3,100);complete();if(sv||sb||valid||bbox||status!=3)fail("invalid classifier emitted region");unforce();tests=tests+1;
  reset();enter();forcedone(1,100);force dut.core_score=8'bxxxxxxxx;complete();
  if(sv||sb||valid||bbox||status!=3)fail("unknown classifier emitted region");unforce();tests=tests+1;
  reset();enter();forcedone(1,100);@(negedge clk);unforce();cancel=1;@(negedge clk);cancel=0;
  if(sv||sb||valid||busy||lock)fail("cancel during mapping retained region");tests=tests+1;
  reset();enter();dut.classifier.state=14;dut.classifier.busy=1;dut.classifier.winner=1;
  dut.classifier.best_logit=100;dut.classifier.logit_margin=100;
  repeat(250)@(negedge clk);if(!busy||!lock||done)fail("postpass ownership");
  cancel=1;@(negedge clk);cancel=0;
  if(sv||sb||valid||busy||lock||dut.classifier.busy)fail("cancel during serial postpass");tests=tests+1;
  repeat(4)@(negedge clk);count=0;start=1;@(negedge clk);start=0;complete();
  if(sv||sb||status!=2||bbox)fail("cancel/reentry stale region");tests=tests+1;
  $display("SUSPECT_ADAPTER_GOLDEN_PASS tests=%0d",tests);$finish;
 end
endmodule
