`timescale 1ns/1ps
// Boundary-only wrapper test. The CNN arithmetic is forced to frozen integer
// results; this test exercises only the asymmetric publication policy.
module tb_margin_policy;
  reg clk=0; always #4 clk=~clk;
  reg rst_n=0,start=0,cancel=0,frame_valid=1,model_valid=1;
  reg [31:0] job_id=0; reg [2:0] ccl_count=1; reg [255:0] boxes=0;
  reg ccl_overflow=0,ccl_truncated=0,pixel_ready=0,pixel_valid=0; reg [7:0] pixel_y8=0;
  wire busy,frame_lock,done,result_valid,no_target; wire [1:0] status; wire [15:0] error;
  wire [7:0] reason; wire bbox_valid,suspect_valid; wire [63:0] suspect_box;
  wire [10:0] xmin,xmax; wire [9:0] ymin,ymax; wire [11:0] detail_score; wire [7:0] score; wire [15:0] margin;
  wire [15:0] outline_support; wire pixel_request; wire [10:0] pixel_x; wire [9:0] pixel_y;
  wire ws_we,ws_wbank,ws_rd_bank; wire [14:0] ws_waddr,ws_rd_addr; wire [15:0] ws_wdata; wire [15:0] ws_rd_data=0;
  wire signed [15:0] mac_a; wire signed [7:0] mac_w; wire signed [23:0] mac_product_ext=0; wire [7:0] phase; wire [47:0] cycles;
  pcb_ccl_binary_core #(
    .WEIGHTS_MEM("D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_airwalk_stroke_cont_20261113/model/experiments/conv4_4/weights.mem"),
    .BIASES_MEM("D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_airwalk_stroke_cont_20261113/model/experiments/conv4_4/biases.mem"),
    .SUSPECT_CONST_MEM("D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_airwalk_stroke_cont_20261113/model/suspect/mad_negative_constants.mem"),
    .MARGIN_MIN(32),.GOOD_PASS_MARGIN_MIN(192)) dut(
    .clk(clk),.rst_n(rst_n),.start(start),.cancel(cancel),.frame_valid(frame_valid),.model_valid(model_valid),.job_id(job_id),
    .I_ccl_count(ccl_count),.I_ccl_boxes(boxes),.I_ccl_overflow(ccl_overflow),.I_ccl_truncated(ccl_truncated),
    .done(done),.result_valid(result_valid),.no_target(no_target),.status(status),.error(error),.reason(reason),
    .bbox_valid(bbox_valid),.suspect_valid(suspect_valid),.suspect_box(suspect_box),.xmin(xmin),.xmax(xmax),.ymin(ymin),.ymax(ymax),
    .detail_score(detail_score),.classifier_score(score),.classifier_margin(margin),.outline_support(outline_support),
    .pixel_request(pixel_request),.pixel_x(pixel_x),.pixel_y(pixel_y),.pixel_ready(pixel_ready),.pixel_valid(pixel_valid),.pixel_y8(pixel_y8),
    .ws_we(ws_we),.ws_wbank(ws_wbank),.ws_waddr(ws_waddr),.ws_wdata(ws_wdata),.ws_rd_bank(ws_rd_bank),.ws_rd_addr(ws_rd_addr),.ws_rd_data(ws_rd_data),
    .mac_a(mac_a),.mac_w(mac_w),.mac_product_ext(mac_product_ext),.phase(phase),.cycles(cycles));
  task check(input integer cls,input integer m,input integer exp_status,input integer exp_reason,input string label);
    begin
      dut.state=5'd12; dut.core_enable=1'b1;
      force dut.core_done=1'b1; force dut.core_class=cls[1:0]; force dut.core_margin=m[15:0];
      force dut.core_score=8'd100; force dut.core_sat=16'd0; force dut.core_suspect_valid=1'b0;
      @(posedge clk); #1;
      if(status!==exp_status[1:0] || reason!==exp_reason[7:0]) begin
        $display("MARGIN_POLICY_FAIL %s class=%0d margin=%0d status=%0d reason=%0d",label,cls,m,status,reason);$fatal;
      end
      $display("MARGIN_POLICY_PASS %s class=%0d margin=%0d status=%0d reason=%0d",label,cls,m,status,reason);
      release dut.core_done; release dut.core_class; release dut.core_margin; release dut.core_score; release dut.core_sat; release dut.core_suspect_valid;
    end
  endtask
  initial begin
    repeat(3) @(negedge clk); rst_n=1; repeat(2) @(negedge clk);
    check(0,31,2,3,"GOOD_31_REVIEW");
    check(0,191,2,3,"GOOD_191_REVIEW");
    check(0,192,0,1,"GOOD_192_PASS");
    check(1,31,2,3,"BAD_31_REVIEW");
    check(1,32,1,2,"BAD_32_FAIL");
    check(1,65535,1,2,"BAD_MAX_FAIL");
    check(0,65535,0,1,"GOOD_MAX_PASS");
    $display("MARGIN_POLICY_GOLDEN_PASS tests=7");$finish;
  end
endmodule
