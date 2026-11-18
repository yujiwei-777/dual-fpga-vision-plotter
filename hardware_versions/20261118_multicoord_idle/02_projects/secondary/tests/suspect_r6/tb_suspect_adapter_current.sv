`timescale 1ns/1ps
// Current 48-port wrapper contract. Classifier outcomes are controlled here;
// the separate core/pipeline suites execute the actual model arithmetic.
module tb_suspect_adapter;
 reg clk=0;always #4 clk=~clk;
 reg rst=0,start=0,cancel=0;reg [2:0] count=1;
 wire busy,lock,done,valid,no_target,bbox,sv;
 wire [1:0] status;wire [15:0] error,margin_out,outline;
 wire [7:0] reason,score_out,phase;wire [63:0] sb;wire [47:0] cycles;
 wire [10:0] xmin,xmax,pixel_x;wire [9:0] ymin,ymax,pixel_y;
 wire [11:0] detail;wire request,ws_we,ws_bank,ws_read_bank;
 wire [14:0] ws_addr,ws_read_addr;wire [15:0] ws_data;
 wire signed [15:0] ma;wire signed [7:0] mw;
 wire signed [23:0] mp=ma*mw;
 integer g=0,tests=0,n,leftx,rightx,topy,bottomy,ex0,ey0,ex1,ey1;
 pcb_ccl_binary_core #(.SUSPECT_ENABLE(1),.WEIGHTS_MEM("@WEIGHTS@"),.BIASES_MEM("@BIASES@"),
  .SUSPECT_CONST_MEM("@SUSPECT@")) dut(
  .clk(clk),.rst_n(rst),.start(start),.cancel(cancel),.frame_valid(1'b1),.model_valid(1'b1),.job_id(32'd7),
  .I_ccl_count(count),.I_ccl_boxes(256'h003c0078000a0014),.I_ccl_overflow(1'b0),.I_ccl_truncated(1'b0),
  .busy(busy),.frame_lock(lock),.done(done),.result_valid(valid),.no_target(no_target),
  .status(status),.error(error),.reason(reason),.bbox_valid(bbox),.suspect_valid(sv),.suspect_box(sb),
  .xmin(xmin),.xmax(xmax),.ymin(ymin),.ymax(ymax),.detail_score(detail),
  .classifier_score(score_out),.classifier_margin(margin_out),.outline_support(outline),
  .pixel_request(request),.pixel_x(pixel_x),.pixel_y(pixel_y),
  .pixel_ready(1'b0),.pixel_valid(1'b0),.pixel_y8(8'd0),
  .ws_we(ws_we),.ws_wbank(ws_bank),.ws_waddr(ws_addr),.ws_wdata(ws_data),
  .ws_rd_bank(ws_read_bank),.ws_rd_addr(ws_read_addr),.ws_rd_data(16'd0),
  .mac_a(ma),.mac_w(mw),.mac_product_ext(mp),.phase(phase),.cycles(cycles));
 task fail(input string s);begin
  $display("SUSPECT_ADAPTER_FAIL grid%0d state%0d %s status=%0d reason=%0d error=%h valid=%b bbox=%b sv=%b box=%h",
   g,dut.state,s,status,reason,error,valid,bbox,sv,sb);$fatal;
 end endtask
 task reset;begin
  rst=0;start=0;cancel=0;count=1;repeat(4)@(negedge clk);rst=1;repeat(3)@(negedge clk);
 end endtask
 task enter;begin
  // Accept a real new task first: it must clear any previous suspect box.
  start=1;@(negedge clk);start=0;
  if(sv!==0||sb!==0)fail("accepted new task retained previous region");
  // Controlled classifier-completion boundary; ROI is the accepted CCL crop.
  dut.state=dut.CORE_WAIT;dut.core_enable=1;
  dut.xmin=160;dut.xmax=960;dut.ymin=80;dut.ymax=480;
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
  force dut.core_score=8'd100;force dut.core_sat=16'd0;
  force dut.core_suspect_valid=1;force dut.core_suspect_grid=g;
 end endtask
 task unforce;begin
  release dut.core_done;release dut.core_class;release dut.core_margin;release dut.core_score;
  release dut.core_sat;release dut.core_suspect_valid;release dut.core_suspect_grid;
 end endtask
 task seeded;begin
  reset();enter();forcedone(1,100);complete();
  if(!sv||sb==0)fail("stale-region seed did not publish FAIL");
  unforce();enter();
 end endtask
 task clear_region(input [1:0] expected_status,input [7:0] expected_reason,input bit expected_valid,input [15:0] expected_error);begin
  if(sv!==0||sb!==0||status!==expected_status||reason!==expected_reason||
     valid!==expected_valid||bbox!==expected_valid||error!==expected_error)
    fail("classification output and suspect clearing");
  tests=tests+1;
 end endtask
 initial begin
  if(dut.MARGIN_MIN!=32||dut.GOOD_PASS_MARGIN_MIN!=192)fail("unreviewed classifier margin policy");
  for(g=0;g<16;g=g+1)begin
   reset();enter();forcedone(1,100);complete();
   leftx=160+(g%4)*200;rightx=leftx+200;topy=80+(g/4)*100;bottomy=topy+100;
   ex0=leftx-100;if(ex0<160)ex0=160;ex1=rightx+100;if(ex1>960)ex1=960;
   ey0=topy-50;if(ey0<80)ey0=80;ey1=bottomy+50;if(ey1>480)ey1=480;
   if(!sv||!valid||!bbox||status!=1||reason!=2||error!=0||score_out!=100||margin_out!=100||
      sb[15:0]!=ex0||sb[31:16]!=ey0||sb[47:32]!=ex1||sb[63:48]!=ey1)
    fail("BAD mapped half-open box");
   unforce();tests=tests+1;
  end
  count=0;start=1;@(negedge clk);start=0;complete();
  if(sv||sb||status!=2||bbox||!valid||!no_target||reason!=4||error!=16'h0201)fail("no-target clears previous region");tests++;
  seeded();forcedone(0,192);complete();clear_region(0,1,1,0);unforce();
  seeded();forcedone(0,191);complete();clear_region(2,3,1,0);unforce();
  seeded();forcedone(0,100);complete();clear_region(2,3,1,0);unforce();
  seeded();forcedone(1,31);complete();clear_region(2,3,1,0);unforce();
  reset();enter();forcedone(1,32);complete();
  if(status!=1||reason!=2||!valid||!bbox||!sv||sb==0||error!=0)fail("BAD threshold32 retains FAIL region");tests++;unforce();
  seeded();forcedone(3,100);complete();clear_region(3,12,0,16'h0301);unforce();
  seeded();forcedone(1,100);force dut.core_score=8'bxxxxxxxx;complete();clear_region(3,12,0,16'h0301);unforce();
  seeded();forcedone(1,100);force dut.core_margin=16'hxxxx;complete();clear_region(3,12,0,16'h0301);unforce();
  seeded();forcedone(1,100);force dut.core_class=2'bxx;complete();clear_region(3,12,0,16'h0301);unforce();
  seeded();forcedone(1,100);force dut.core_sat=16'hxxxx;complete();clear_region(3,12,0,16'h0301);unforce();
  reset();enter();forcedone(1,100);@(negedge clk);unforce();cancel=1;@(negedge clk);cancel=0;
  if(sv||sb||valid||busy||lock||bbox)fail("cancel during mapping retained region");tests++;
  reset();enter();dut.classifier.state=dut.classifier.S_FINISH;dut.classifier.busy=1;dut.classifier.winner=1;
  dut.classifier.best_logit=100;dut.classifier.logit_margin=100;
  repeat(250)@(negedge clk);if(!busy||!lock||done)fail("postpass ownership");
  cancel=1;@(negedge clk);cancel=0;
  if(sv||sb||valid||busy||lock||dut.classifier.busy||bbox)fail("cancel during serial postpass");tests++;
  repeat(4)@(negedge clk);count=0;start=1;@(negedge clk);start=0;complete();
  if(sv||sb||status!=2||bbox||!valid||!no_target)fail("cancel/reentry stale region");tests++;
  $display("SUSPECT_ADAPTER_CURRENT_PASS tests=%0d good_pass_min=%0d bad_min=%0d",tests,dut.GOOD_PASS_MARGIN_MIN,dut.MARGIN_MIN);$finish;
 end
 initial begin #1000000;$fatal(1,"adapter watchdog");end
endmodule
