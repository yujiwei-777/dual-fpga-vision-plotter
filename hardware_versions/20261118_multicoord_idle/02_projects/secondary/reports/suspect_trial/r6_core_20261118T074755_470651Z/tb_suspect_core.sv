
`timescale 1ns/1ps
module tb_suspect_core;
reg clk=0;always #4 clk=~clk;
reg rst=0,start=0,we=0;reg[13:0]addr=0;reg[7:0]gray=0;
wire busy,done,sv;wire[1:0]cls;wire[7:0]score;wire[15:0]margin,sat;wire[3:0]grid;
wire wwe,wb,rb;wire[14:0]wa,ra;wire[15:0]wd,rd;wire signed[15:0]ma;wire signed[7:0]mw;wire signed[23:0]mp;
wire bbusy,bdone;wire[1:0]bcls;wire[7:0]bscore;wire[15:0]bmargin,bsat;
pcb_fullboard_spatial96 #(.WEIGHTS_MEM("D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_suspect_robust_20261111/model/experiments/conv4_4/weights.mem"),.BIASES_MEM("D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_suspect_robust_20261111/model/experiments/conv4_4/biases.mem"),.USE_SHARED_WORKSPACE(1),.EXTERNAL_MAC(1),
 .HEAD_CLASSES(2),.C1_CHANNELS(4),.C2_CHANNELS(4),.C1_SHIFT(7),.C2_SHIFT(7),.HEAD_SHIFT(8),
 .SUSPECT_ENABLE(1),.SUSPECT_CONST_MEM("D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_suspect_robust_20261111/model/suspect/mad_negative_constants.mem"))dut(
 .clk(clk),.rst_n(rst),.start(start),.pixel_we(we),.pixel_addr(addr),.pixel_gray(gray),
 .busy(busy),.done(done),.class_id(cls),.score(score),.margin(margin),.saturation_count(sat),
 .ws_we(wwe),.ws_wbank(wb),.ws_waddr(wa),.ws_wdata(wd),.ws_rd_bank(rb),.ws_rd_addr(ra),.ws_rd_data(rd),
 .mac_a(ma),.mac_w(mw),.mac_product_ext(mp),.suspect_valid(sv),.suspect_grid(grid));
pcb_fullboard_spatial96_r5 #(.WEIGHTS_MEM("D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_suspect_robust_20261111/model/experiments/conv4_4/weights.mem"),.BIASES_MEM("D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_suspect_robust_20261111/model/experiments/conv4_4/biases.mem"),.USE_SHARED_WORKSPACE(0),.EXTERNAL_MAC(0),
 .HEAD_CLASSES(2),.C1_CHANNELS(4),.C2_CHANNELS(4),.C1_SHIFT(7),.C2_SHIFT(7),.HEAD_SHIFT(8),.SUSPECT_ENABLE(0))baseline(
 .clk(clk),.rst_n(rst),.start(start),.pixel_we(we),.pixel_addr(addr),.pixel_gray(gray),
 .busy(bbusy),.done(bdone),.class_id(bcls),.score(bscore),.margin(bmargin),.saturation_count(bsat),.ws_rd_data(16'd0),.mac_product_ext(24'sd0));
vision_shared_mac mac(.pcb_select(1'b1),.cnn_a(16'sd0),.cnn_w(8'sd0),.pcb_a(ma),.pcb_w(mw),.pcb_product(mp));
vision_workspace_goodonly ws(.clk(clk),.purpose(2'd1),.cnn_shape_we(1'b0),.cnn_shape_waddr(12'd0),.cnn_shape_wdata(16'd0),
 .cnn_f1_we(1'b0),.cnn_f1_waddr(13'd0),.cnn_f1_wdata(16'd0),.cnn_f2_we(1'b0),.cnn_f2_waddr(12'd0),.cnn_f2_wdata(16'd0),
 .cnn_rd_sel(2'd0),.cnn_rd_addr(13'd0),.pcb_we(wwe),.pcb_wbank(wb),.pcb_waddr(wa),.pcb_wdata(wd),.pcb_rd_bank(rb),.pcb_rd_addr(ra),.pcb_rd_data(rd));
integer cycles=0,post_start,base_done,tests=0,i,waited,expected_class,expected_margin,expected_score,expected_sat,expected_grid,expected_valid;
integer pooling_checks=0,grid_checks=0,full=0,checks=0,baseline_seen=0;
reg[7:0]roi[0:9215];reg[15:0]f1[0:9215],f2[0:2303],pool[0:63];reg[31:0]logits[0:1],scores[0:15];
string name;
task fail(input string msg);begin $display("SUSPECT_CORE_FAIL %s cycle%0d state%0d phase%0d %s",name,cycles,dut.state,dut.phase,msg);$fatal;end endtask
always@(posedge clk)begin
 cycles=cycles+1;
 if(checks)begin
  if(full&&wwe&&dut.state==3&&wd!==f1[wa])fail("conv1 changed");
  if(full&&wwe&&dut.state==6&&wd!==f2[wa])fail("conv2 changed");
  if(dut.state==9&&dut.phase==0&&dut.pool_value!==$signed({1'b0,pool[dut.hindex]}))fail("head pool mismatch");
  if(dut.state==15&&dut.phase==0)begin
   if(dut.pool_value!==$signed({1'b0,pool[dut.hindex]}))fail("suspect pooled feature mismatch");
   pooling_checks=pooling_checks+1;
  end
  if(dut.state==16)begin if(dut.acc!==$signed({1'b0,scores[dut.hindex[3:0]]}))fail("grid score mismatch");grid_checks=grid_checks+1;end
  if(dut.state==14)post_start=cycles;
  if(full&&bdone)begin
   baseline_seen=1;base_done=cycles;
   if(bcls!==expected_class[1:0]||bscore!==expected_score[7:0]||bmargin!==expected_margin[15:0]||bsat!==expected_sat[15:0])fail("baseline numeric fixture mismatch");
  end
 end
end
task reset;begin checks=0;rst=0;start=0;we=0;repeat(4)@(negedge clk);rst=1;repeat(3)@(negedge clk);end endtask
task load(input string label);begin
 name=label;$readmemh({label,"_f2.mem"},f2);$readmemh({label,"_pool.mem"},pool);$readmemh({label,"_scores.mem"},scores);
 `include "cases.svh"
end endtask
task awaitdone;begin
 waited=0;while(!done&&waited<1800000)begin @(negedge clk);waited=waited+1;end
 if(!done)fail("timeout");
 if(cls!==expected_class[1:0]||score!==expected_score[7:0]||margin!==expected_margin[15:0])fail("class/score/margin changed");
 if(sv!==expected_valid[0]||(sv&&grid!==expected_grid[3:0]))fail("suspect grid/valid");
 if(full&&(dut.logits[0]!==logits[0][19:0]||dut.logits[1]!==logits[1][19:0]))fail("integer golden logits mismatch");
 if(full&&(!(baseline_seen||bdone)||sat!==bsat||cls!==bcls||score!==bscore||margin!==bmargin||dut.logits[0]!==baseline.logits[0]||dut.logits[1]!==baseline.logits[1]))fail("baseline logits/saturation mismatch");
 if(expected_class==1&&expected_margin>=32)begin
  if(pooling_checks!=64||grid_checks!=16)fail("postpass did not serially cover64pool/16grid");
  if(cycles-post_start!=7121)fail($sformatf("post latency got%0d",cycles-post_start));
 end else if(pooling_checks||grid_checks)fail("PASS/REVIEW ran postpass");
 tests=tests+1;$display("SUSPECT_CORE_PASS %s class%0d margin%0d suspect%0d grid%0d postcycles%0d",name,cls,margin,sv,grid,cycles-post_start);
 checks=0;@(negedge clk);
end endtask
task synthetic(input string label);begin
 reset();load(label);full=0;pooling_checks=0;grid_checks=0;
 for(i=0;i<2304;i=i+1)ws.bank1[i]=f2[i];
 dut.winner=expected_class;dut.best_logit=expected_score;dut.logit_margin=expected_margin;dut.state=14;dut.busy=1;
 checks=1;awaitdone();
end endtask
task realcase(input string label);begin
 reset();load(label);$readmemh({label,"_roi.mem"},roi);$readmemh({label,"_f1.mem"},f1);$readmemh({label,"_logits.mem"},logits);
 full=1;baseline_seen=0;pooling_checks=0;grid_checks=0;
 for(i=0;i<9216;i=i+1)begin addr=i;gray=roi[i];we=1;@(negedge clk);end
 we=0;start=1;checks=1;@(negedge clk);start=0;awaitdone();
end endtask
initial begin
 `include "calls.svh"
 // A reset during a partly completed pass must fence all old output.
 reset();load("all_zero");for(i=0;i<2304;i=i+1)ws.bank1[i]=f2[i];
 dut.winner=1;dut.logit_margin=100;dut.state=14;dut.busy=1;
 repeat(250)@(negedge clk);if(!busy)fail("postpass lost ownership");
 rst=0;@(negedge clk);if(sv||busy||done)fail("reset failed to clear");
 $display("SUSPECT_CORE_GOLDEN_PASS tests=%0d",tests);$finish;
end
endmodule
