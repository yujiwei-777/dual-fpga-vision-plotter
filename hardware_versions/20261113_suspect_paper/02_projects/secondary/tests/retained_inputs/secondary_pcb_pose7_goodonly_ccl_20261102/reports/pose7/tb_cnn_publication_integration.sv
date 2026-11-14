`timescale 1ns/1ps
// Reuses the controlled-leaf method in run_cnn_stability_pipeline.py.
// The current production pipeline, packed stabilizer and publication FSM are
// real. Only CCL/CNN/unused PCB datapath outputs are controlled. No pipeline
// state, candidate bank, tracking metadata or final result is forced.
module tb_cnn_publication_integration;
reg clk=0; always #4 clk=~clk;
reg rst_n=0,start=0,cancel=0,history_clear=0,cfg_commit=0;
reg [1:0] shape=2;
reg [7:0] score=200;
reg hard_reject=0,overflow=0;
reg [2:0] candidate_count=1;
reg [255:0] candidate_boxes={192'd0,16'd60,16'd80,16'd20,16'd40};
reg [31:0] job=0;
wire request,busy,done,valid;
wire [31:0] result_job;
wire [1:0] color_id,shape_id;
wire [7:0] confidence,flags;
wire [2:0] count;
wire [511:0] boxes;
wire [10:0] x0,x1;
wire [9:0] y0,y1;
integer checks=0,completions=0,starts=0,before_count,before_starts,boundary;
reg [511:0] raw_snapshot;
reg [7:0] order_snapshot;

vision_pipeline #(.PCB_GOODONLY_AUTO(1),.CNN_LOWCONF_OUTPUT(1),
 .EXTERNAL_READER(1),.LOCAL_CNN_ENABLE(1),.PCB_ENABLE(1),.SHARED_WORKSPACE(1)) dut(
 .clk(clk),.rst_n(rst_n),.start(start),.purpose(2'd0),.teach_good(1'b0),
 .cancel(cancel),.job_id(job),.word_ready(1'b0),.word_valid(1'b0),.word_data(128'd0),
 .cfg_we(1'b0),.cfg_addr(15'd0),.cfg_data(8'd0),.cfg_commit(cfg_commit),
 .busy(busy),.done(done),.result_job_id(result_job),.color_id(color_id),.shape_id(shape_id),
 .confidence(confidence),.valid(valid),.x0(x0),.x1(x1),.y0(y0),.y1(y1),
 .multi_count(count),.multi_boxes(boxes),.multi_flags(flags),
 .ext_reader_ready(1'b1),.ext_reader_valid(request),.ext_reader_rgb(24'hc02020),
 .ext_reader_luma(8'd90),.ext_reader_request(request),.history_clear(history_clear));

always @(posedge clk)if(rst_n)begin
 if(done)completions<=completions+1;
 if(dut.stable_start)starts<=starts+1;
end
task step;begin @(posedge clk);#1;end endtask
task check(input bit ok,input string message);begin
 checks=checks+1;if(!ok)$fatal(1,"CNN_PUBLICATION_FAIL job=%0d state=%0d %s",job,dut.state,message);
end endtask
task launch;begin
 @(negedge clk);job=job+1;start=1;step;@(negedge clk);start=0;
end endtask
task finish_job;integer ticks;begin
 ticks=0;while(!done&&ticks<300000)begin step;ticks=ticks+1;end
 check(done&&result_job==job&&!busy,"current job retires exactly once");
 check(valid==(count!=0)&&flags[0]==valid&&flags[7]==!valid,"Type18/compatibility validity agree");
 if(valid)begin
  check(boxes[79:64]==(color_id-1)*3+shape_id&&boxes[87:80]==confidence,"primary class/confidence agree");
  check(boxes[15:0]==x0&&boxes[31:16]==y0&&boxes[47:32]==x1&&boxes[63:48]==y1,"primary bbox agrees");
 end
 step;
end endtask
task run_frame;begin launch;finish_job;end endtask
task expect_current(input integer cls,input integer conf,input bit uncertain);begin
 check(valid&&count==1&&color_id==1&&shape_id==cls&&confidence==conf,"current class/actual confidence visible");
 check(x0==candidate_boxes[15:0]*8&&y0==candidate_boxes[31:16]*8&&
       x1==candidate_boxes[47:32]*8&&y1==candidate_boxes[63:48]*8,"bbox comes from this observation");
 check(boxes[127:96]==64000&&flags[6]==uncertain,"current area and uncertainty preserved");
end endtask
task expect_empty;begin
 check(!valid&&count==0&&boxes==0&&confidence==0&&color_id==0&&shape_id==0,"empty result has no old box/class/confidence");
end endtask
task clear_history;begin
 @(negedge clk);history_clear=1;step;@(negedge clk);history_clear=0;step;
end endtask
task reset_fixture;begin
 @(negedge clk);candidate_count=1;shape=2;score=200;hard_reject=0;overflow=0;
 candidate_boxes={192'd0,16'd60,16'd80,16'd20,16'd40};
end endtask

initial begin
 force dut.cc_ready=1'b1;force dut.cc_busy=1'b0;force dut.cc_done=1'b1;
 force dut.cc_overflow=overflow;force dut.cc_count=candidate_count;force dut.cc_boxes=candidate_boxes;
 force dut.cc_areas=64'd1000;force dut.cc_truncated=1'b0;
 force dut.cnn_busy=1'b0;force dut.cnn_done=dut.cnn_start;
 force dut.cnn_background_reject=hard_reject;force dut.cnn_color=2'd1;force dut.cnn_shape=shape;
 force dut.cnn_color_conf=8'd255;force dut.cnn_shape_conf=score;
 force dut.auto_busy=1'b0;
 repeat(4)step;rst_n=1;repeat(3)step;
 run_frame;expect_current(2,78,1); // First observation, current bbox immediately.
 run_frame;expect_current(2,78,1);
 run_frame;expect_current(2,78,0); // Third consecutive observation confirms.
 @(negedge clk);shape=3;score=210;candidate_boxes={192'd0,16'd60,16'd81,16'd20,16'd41};
 run_frame;expect_current(2,82,1); // HOLD1 retains name, moves bbox and score.
 @(negedge clk);score=220;candidate_boxes={192'd0,16'd61,16'd81,16'd21,16'd41};
 run_frame;expect_current(2,86,1); // HOLD2.
 @(negedge clk);score=230;candidate_boxes={192'd0,16'd61,16'd82,16'd21,16'd42};
 run_frame;expect_current(3,90,0); // Changed class confirms on its third observation.
 @(negedge clk);shape=2;score=19;
 run_frame;expect_current(3,7,1); // Soft low margin remains visible, actual score.
 @(negedge clk);score=0;
 run_frame;expect_current(3,0,1);
 run_frame;expect_current(2,0,1); // Zero score does not become confidence.
 @(negedge clk);candidate_count=0;
 run_frame;expect_empty;run_frame;expect_empty;run_frame;expect_empty;
 reset_fixture;run_frame;expect_current(2,78,1); // Missing observation broke streak.
 @(negedge clk);hard_reject=1;
 run_frame;expect_empty; // Tests retained hard-reject branch, not learned background capability.
 reset_fixture;
 @(negedge clk);candidate_boxes={192'd0,16'd60,16'd170,16'd20,16'd40};
 run_frame;expect_empty; // Native x1=1360 is malformed.
 @(negedge clk);candidate_boxes={192'd0,16'd100,16'd80,16'd20,16'd40};
 run_frame;expect_empty; // Native y1=800 is malformed.
 @(negedge clk);candidate_boxes={192'd0,16'd60,16'd30,16'd20,16'd40};
 run_frame;expect_empty; // Reversed x endpoints.
 reset_fixture;
 // Before ownership transfer, clear must preserve raw input and restart once.
 launch;wait(dut.stable_emit_begin);@(negedge clk);history_clear=1;
 raw_snapshot=dut.multi_boxes;order_snapshot=dut.raw_slot_order;
 repeat(3)step;
 check(!dut.stable_raw_released&&dut.multi_boxes==raw_snapshot&&dut.raw_slot_order==order_snapshot,
       "clear before begin preserves raw source for restart");
 @(negedge clk);history_clear=0;finish_job;expect_current(2,78,1);
 // After begin/slot/done, source cannot be reread as fresh observations.
 for(boundary=0;boundary<3;boundary=boundary+1)begin
  launch;
  if(boundary==0)begin wait(dut.stable_emit_begin);step;end
  else if(boundary==1)begin wait(dut.stable_emit_valid);step;end
  else wait(dut.stable_done);
  check(dut.stable_raw_released,"raw source ownership released");
  before_starts=starts;
  @(negedge clk);history_clear=1;step;@(negedge clk);history_clear=0;
  finish_job;expect_empty;
  check(starts==before_starts,"post-release clear cannot restart destroyed source");
  run_frame;expect_current(2,78,1);
 end
 // Clear on final publication and completion edges must suppress cache refill.
 launch;wait(dut.state==dut.MULTI_PUBLISH);@(negedge clk);history_clear=1;step;
 @(negedge clk);history_clear=0;finish_job;expect_empty;
 run_frame;expect_current(2,78,1);
 launch;wait(dut.state==dut.FINISH);@(negedge clk);history_clear=1;step;
 check(done,"completion-edge clear still retires job");expect_empty;
 @(negedge clk);history_clear=0;step;
 run_frame;expect_current(2,78,1);
 // Destructive cancel and cfg commit invalidate confirmation and cannot ghost.
 before_count=completions;launch;wait(dut.stable_busy);
 @(negedge clk);cancel=1;step;check(!busy&&!done,"cancel aborts current job");
 @(negedge clk);cancel=0;repeat(4)step;
 check(completions==before_count,"cancel emits no late completion");
 run_frame;expect_current(2,78,1);
 @(negedge clk);cfg_commit=1;step;@(negedge clk);cfg_commit=0;
 run_frame;expect_current(2,78,1);
 $display("PASS CNN_PUBLICATION_INTEGRATION checks=%0d jobs=%0d starts=%0d",checks,completions,starts);
 $finish;
end
initial begin #1000000000;$fatal(1,"CNN_PUBLICATION_FAIL global watchdog");end
endmodule
