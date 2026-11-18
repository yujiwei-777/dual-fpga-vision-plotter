`timescale 1ns/1ps
module tb_doc_total_ack;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,start=0,points_done=0,point_valid=0;
reg [8:0]point_x=0,point_y=70;
reg point_start=0,point_end=0,point_dot=0;
wire point_ready,busy,done,error,recovery_required;
wire [31:0]acked,total;wire total_valid;
wire [7:0]tx_data,rt_data;wire tx_valid,rt_valid;
reg tx_done=0,rx_valid=0;reg [7:0]rx_data=0;
integer cycles=0,lines=0,acks=0,queries=0,line_bytes=0;
reg [511:0]last_line=0;reg [63:0]reply=0;
integer reply_i=0,reply_len=0,delay_count=0;
wire tx_ready=(cycles%5!=0);
wire mapper_start;reg mapper_done=0;
wire S_start;
wire S_clear;
wire S_abort;
wire S_stop;
wire S_rearm;
wire S_cancel;
wire S_fault;
wire S_reset_job;
wire S_profile_valid;
wire [7:0] S_fault_code;
wire [511:0] S_line;
wire [6:0] S_length;
wire S_line_valid;
wire S_line_last;
wire S_finish;
wire S_available;
wire S_line_ready;
wire S_line_done;
wire S_busy;
wire S_done;
wire S_error;
wire S_cancelled;
wire S_recovery_required;
wire [7:0] S_error_code;
wire [31:0] S_acked_lines;
wire [2:0] S_job_state;
wire S_rt_done;
wire X_start;
wire [1:0] X_kind;
wire [15:0] X_x;
wire [15:0] X_y;
wire [15:0] X_z;
wire [15:0] X_feed;
wire [15:0] X_pwm;
wire [511:0] X_line;
wire [6:0] X_length;
wire X_done;
wire X_busy;
doc_grbl_plotter_shared_candidate #(.CLK_HZ(1000),.EXTERNAL_MAPPER(1)) dut(
 .clk(clk),.rst_n(rst_n),.start(start),.cancel(1'b0),.rearm(1'b0),.reset_job(1'b0),
 .point_valid(point_valid),.point_x(point_x),.point_y(point_y),
 .point_start(point_start),.point_end(point_end),.point_dot(point_dot),.points_done(points_done),
 .point_ready(point_ready),.busy(busy),.done(done),.error(error),.recovery_required(recovery_required),
 .acked_lines(acked),.link_ready(1'b1),.mapper_start(mapper_start),.mapper_x(),.mapper_y(),
 .tx_data(),.tx_valid(),.tx_ready(tx_ready),.tx_done(tx_done),.rx_data(rx_data),.rx_valid(rx_valid),.rx_error(1'b0),
 .rt_data(),.rt_valid(),.rt_ready(1'b1),.error_code(),.job_state(),.cancelled(),
 .mapper_x_cmm(16'd1000),.mapper_y_cmm(16'd1000),.mapper_done(mapper_done),
 .airwalk(1'b0),.total_lines(total),.total_valid(total_valid),.S_start(S_start),.S_clear(S_clear),.S_abort(S_abort),.S_stop(S_stop),.S_rearm(S_rearm),.S_cancel(S_cancel),.S_fault(S_fault),.S_reset_job(S_reset_job),.S_profile_valid(S_profile_valid),.S_fault_code(S_fault_code),.S_line(S_line),.S_length(S_length),.S_line_valid(S_line_valid),.S_line_last(S_line_last),.S_finish(S_finish),.S_available(S_available),.S_line_ready(S_line_ready),.S_line_done(S_line_done),.S_busy(S_busy),.S_done(S_done),.S_error(S_error),.S_cancelled(S_cancelled),.S_recovery_required(S_recovery_required),.S_error_code(S_error_code),.S_acked_lines(S_acked_lines),.S_job_state(S_job_state),.S_rt_done(S_rt_done),.X_start(X_start),.X_kind(X_kind),.X_x(X_x),.X_y(X_y),.X_z(X_z),.X_feed(X_feed),.X_pwm(X_pwm),.X_line(X_line),.X_length(X_length),.X_done(X_done),.X_busy(X_busy));
grbl_shared_transport_candidate #(.CLK_HZ(1000),.DOC_QUERY_MS(500),.DOC_PROGRESS_MS(10000)) trx(
 .clk(clk),.rst_n(rst_n),.I_doc_owner(busy),.I_report_claim(1'b0),.link_ready(1'b1),
 .tx_ready(tx_ready),.tx_done(tx_done),.rt_ready(1'b1),.rx_data(rx_data),.rx_valid(rx_valid),.rx_error(1'b0),
 .tx_data(tx_data),.tx_valid(tx_valid),.rt_data(rt_data),.rt_valid(rt_valid),.D_start(S_start),
 .D_clear(S_clear),
 .D_abort(S_abort),
 .D_stop(S_stop),
 .D_rearm(S_rearm),
 .D_cancel(S_cancel),
 .D_fault(S_fault),
 .D_reset_job(S_reset_job),
 .D_profile_valid(S_profile_valid),
 .D_fault_code(S_fault_code),
 .D_line(S_line),
 .D_length(S_length),
 .D_line_valid(S_line_valid),
 .D_line_last(S_line_last),
 .D_finish(S_finish),
 .D_available(S_available),
 .D_line_ready(S_line_ready),
 .D_line_done(S_line_done),
 .D_busy(S_busy),
 .D_done(S_done),
 .D_error(S_error),
 .D_cancelled(S_cancelled),
 .D_recovery_required(S_recovery_required),
 .D_error_code(S_error_code),
 .D_acked_lines(S_acked_lines),
 .D_job_state(S_job_state),
 .D_rt_done(S_rt_done),
 .D_fmt_start(X_start),
 .D_fmt_kind(X_kind),
 .D_fmt_x(X_x),
 .D_fmt_y(X_y),
 .D_fmt_z(X_z),
 .D_fmt_feed(X_feed),
 .D_fmt_pwm(X_pwm),
 .D_fmt_line(X_line),
 .D_fmt_length(X_length),
 .D_fmt_done(X_done),
 .D_fmt_busy(X_busy),
 .R_start('0),
 .R_clear('0),
 .R_abort('0),
 .R_stop('0),
 .R_rearm('0),
 .R_cancel('0),
 .R_fault('0),
 .R_reset_job('0),
 .R_profile_valid('0),
 .R_fault_code('0),
 .R_line('0),
 .R_length('0),
 .R_line_valid('0),
 .R_line_last('0),
 .R_finish('0),
 .R_available(),
 .R_line_ready(),
 .R_line_done(),
 .R_idle_done(),
 .R_busy(),
 .R_done(),
 .R_error(),
 .R_cancelled(),
 .R_recovery_required(),
 .R_error_code(),
 .R_acked_lines(),
 .R_job_state(),
 .R_rt_done(),
 .R_fmt_start('0),
 .R_fmt_kind('0),
 .R_fmt_x('0),
 .R_fmt_y('0),
 .R_fmt_z('0),
 .R_fmt_feed('0),
 .R_fmt_pwm('0),
 .R_fmt_line(),
 .R_fmt_length(),
 .R_fmt_done(),
 .R_fmt_busy());
task tick(input integer n);repeat(n)@(negedge clk);endtask
task begin_task;
 begin
  lines=0;acks=0;queries=0;points_done=0;
  start=1;tick(1);start=0;tick(2);
  if(total_valid)$fatal(1,"old total survived accepted start");
 end
endtask
task point(input bit first,last,dot);
 begin
  point_start=first;point_end=last;point_dot=dot;point_valid=1;
  while(!point_ready)tick(1);
  tick(1);point_valid=0;point_x=point_x+10;
 end
endtask
task finish_task(input integer expected);
 begin
  points_done=1;
  wait(done);tick(3);
  if(error||recovery_required||busy||!total_valid||total!=expected||acked!=expected||lines!=expected||acks!=expected||queries!=1)
   $fatal(1,"completion mismatch exp=%0d total=%0d acked=%0d lines=%0d acks=%0d q=%0d",expected,total,acked,lines,acks,queries);
  if(last_line[79:0]!==80'h30302e30313058203047)$fatal(1,"final command not return G0 X010.00: %h",last_line[79:0]);
  tick(10);if(busy)$fatal(1,"task replayed");
 end
endtask
initial begin
 tick(5);rst_n=1;tick(5);
 begin_task();point(1,0,0);point(0,1,0);finish_task(8);
 begin_task();point(1,1,1);finish_task(8);
 begin_task();finish_task(4);
 $display("DOC_TOTAL_ACK_PASS cases=3 normal_dot_empty delayed_ack_no_final_idle");$finish;
end
always @(posedge clk)begin
 cycles<=cycles+1;tx_done<=0;rx_valid<=0;mapper_done<=mapper_start;
 if(cycles>50000)$fatal(1,"watchdog state=%0d",dut.state);
 if(rst_n)begin
  if(error)$fatal(1,"transport fault");
  if(rt_valid)begin
   queries=queries+1;tx_done<=1;
   if(lines||rt_data!=8'h3f||reply_len)$fatal(1,"unexpected status query after initial safety check");
   reply=64'h0a3e7c656c64493c;reply_i=0;reply_len=8;delay_count=8;
  end
  if(tx_valid&&tx_ready)begin
   tx_done<=1;
   if(tx_data==10)begin
    lines=lines+1;line_bytes=0;
    if(reply_len)$fatal(1,"multiple commands in flight");
    reply=64'h0a6b6f;reply_i=0;reply_len=3;delay_count=30;
   end else begin
    if(line_bytes==0)last_line=0;
    last_line[line_bytes*8+:8]=tx_data;line_bytes=line_bytes+1;
   end
  end
  if(delay_count>0)delay_count=delay_count-1;
  else if(reply_len>0)begin
   rx_valid<=1;rx_data<=reply[reply_i*8+:8];
   if(reply_i==2&&reply[7:0]=="o")acks=acks+1;
   reply_i=reply_i+1;reply_len=reply_len-1;delay_count=3;
  end
  if(busy && total_valid && total!=acks)$fatal(1,"total published before all ACKs");
 end
end
endmodule
