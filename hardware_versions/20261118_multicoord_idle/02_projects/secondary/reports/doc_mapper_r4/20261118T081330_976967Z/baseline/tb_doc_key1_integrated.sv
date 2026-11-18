
`timescale 1ns/1ps
module tb_doc_key1_integrated;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,start=0,cancel=0,rearm=0,reset_job=0,write_start=0;
wire busy,done,recovery_required,uart_owner,pixel_request,pixel_invalidate;
wire [10:0]pixel_x;wire [9:0]pixel_y;
wire [15:0]edge_count;wire [11:0]path_count;wire [13:0]point_count;
wire write_waiting;
wire [7:0]tx_data,rt_data;wire tx_valid,rt_valid;
reg tx_done=0,rx_valid=0;reg[7:0]rx_data=0;
reg pixel_valid=0,pending=0;reg[7:0]pixel_luma=0;
integer cycle=0,latency=0,address=0,requests=0;
wire pixel_ready=!pending&&(cycle%13!=5);
wire tx_ready=(cycle%7!=1)&&(cycle%11!=2);
wire rt_ready=cycle%7!=3;
reg[7:0]source_y[0:921599];
integer fh,points2,tx_bytes=0,lines=0,queries=0;
integer reply_delay=0,reply_i=0,reply_len=0,i,n1=0,n2=0;
reg[255:0]reply=0;
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
doc_copy_pipeline_shared_candidate #(.PLANNER_OPT_PASSES(0),.EXTERNAL_ADMISSION_GUARD(1)) dut(
 .clk(clk),.rst_n(rst_n),.start(start),.cancel(cancel),.rearm(rearm),.reset_job(reset_job),
 .write_start(write_start),.write_waiting(write_waiting),
 .admission_inhibit(1'b0),.job_id(32'h11223344),.paper_width_px(16'd0),
 .busy(busy),.done(done),.recovery_required(recovery_required),.status_ready(1'b1),
 .pixel_request(pixel_request),.pixel_invalidate(pixel_invalidate),.pixel_x(pixel_x),.pixel_y(pixel_y),
 .pixel_ready(pixel_ready),.pixel_valid(pixel_valid),.pixel_luma(pixel_luma),
 .tx_ready(tx_ready),.tx_done(tx_done),.rx_data(rx_data),.rx_valid(rx_valid),.rx_error(1'b0),
 .link_ready(1'b1),.rt_ready(rt_ready),.uart_owner(uart_owner),
 .edge_count(edge_count),.path_count(path_count),.point_count(point_count),
 .S_start(S_start),.S_clear(S_clear),.S_abort(S_abort),.S_stop(S_stop),.S_rearm(S_rearm),.S_cancel(S_cancel),.S_fault(S_fault),.S_reset_job(S_reset_job),.S_profile_valid(S_profile_valid),.S_fault_code(S_fault_code),.S_line(S_line),.S_length(S_length),.S_line_valid(S_line_valid),.S_line_last(S_line_last),.S_finish(S_finish),.S_available(S_available),.S_line_ready(S_line_ready),.S_line_done(S_line_done),.S_busy(S_busy),.S_done(S_done),.S_error(S_error),.S_cancelled(S_cancelled),.S_recovery_required(S_recovery_required),.S_error_code(S_error_code),.S_acked_lines(S_acked_lines),.S_job_state(S_job_state),.S_rt_done(S_rt_done),.X_start(X_start),.X_kind(X_kind),.X_x(X_x),.X_y(X_y),.X_z(X_z),.X_feed(X_feed),.X_pwm(X_pwm),.X_line(X_line),.X_length(X_length),.X_done(X_done),.X_busy(X_busy));
grbl_shared_transport_candidate transport(
 .clk(clk),.rst_n(rst_n),.I_doc_owner(uart_owner||busy),.I_report_claim(1'b0),
 .link_ready(1'b1),.tx_ready(tx_ready),.tx_done(tx_done),.rt_ready(rt_ready),
 .rx_data(rx_data),.rx_valid(rx_valid),.rx_error(1'b0),
 .tx_data(tx_data),.tx_valid(tx_valid),.rt_data(rt_data),.rt_valid(rt_valid),
 .D_start(S_start),
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

// Observe the real registered request at its accepting edge. No RTL is forced.
integer metric_requests=0,metric_completions=0,metric_start_cycle=0;
integer metric_min_latency=1000,metric_max_latency=0,metric_latency=0;
reg metric_pending=0;
reg [8:0] metric_resume=0;
reg [31:0] metric_result=0;
reg [32:0] metric_square=0;
always @(posedge clk)begin
 if(rst_n)begin
  if(dut.metric_start)begin
   if(metric_pending||dut.u_planner.state!==dut.u_planner.DIST0||
      dut.u_machine_map.state!==dut.u_machine_map.ST_IDLE||dut.mapper_start||dut.metric_done)
    $fatal(1,"distance request not accepted in planner DIST0/mapper IDLE");
   metric_pending=1;metric_requests=metric_requests+1;metric_start_cycle=cycle;
  end
  if(metric_pending&&dut.u_planner.state!==dut.u_planner.DIST0)
   $fatal(1,"planner left DIST0 before distance completion");
  if(dut.metric_done)begin
   if(!metric_pending||dut.u_planner.state!==dut.u_planner.DIST0||dut.metric_busy)
    $fatal(1,"unexpected or missed distance completion");
   metric_latency=cycle-metric_start_cycle;
   if(metric_latency!=30)$fatal(1,"distance latency %0d expected 30",metric_latency);
   if(metric_latency<metric_min_latency)metric_min_latency=metric_latency;
   if(metric_latency>metric_max_latency)metric_max_latency=metric_latency;
   metric_resume=dut.u_planner.dist_return;
   metric_result=dut.metric_distance;metric_square=dut.metric_squared;
   metric_pending=0;metric_completions=metric_completions+1;
   #1;
   if(dut.u_planner.state!==metric_resume||dut.u_planner.dist_result!==metric_result||
      dut.u_planner.dist_square!==metric_square)
    $fatal(1,"distance completion not captured before planner resumed");
  end
 end
end

task tick(input integer n);repeat(n)@(negedge clk);endtask
task press;begin write_start=1;tick(1);write_start=0;end endtask
initial begin
 $readmemh("source_y.mem",source_y);
 fh=$fopen("gcode.txt","w");points2=$fopen("draw_points.txt","w");
 tick(5);rst_n=1;tick(4);start=1;tick(1);start=0;
`ifdef CONFIRM
 press(); // During real source-image acquisition: never queue this press.
 wait(write_waiting||done);tick(4);
 if(done||!busy||dut.public_state!=7||!dut.u_planner.prepared||n2!=0||tx_bytes!=0)
   $fatal(1,"prepared document did not wait without emitting points or G-code");
 tick(1000);
 if(!write_waiting||tx_bytes||n2)$fatal(1,"early KEY1 caused automatic writing");
 press();tick(4);
`endif
 wait(done);tick(5);
 if(dut.public_state!=4||recovery_required||n2==0||S_acked_lines!=lines)
   $fatal(1,"real pipeline completion failed state=%0d error=%0d points=%0d lines=%0d acked=%0d",
            dut.public_state,dut.public_error,n2,lines,S_acked_lines);
`ifdef CONFIRM
 if(write_waiting)$fatal(1,"completed task still waiting");
 press();tick(20);if(busy)$fatal(1,"old document replayed after completion");
`endif
 $fclose(fh);$fclose(points2);
 $display("DOC_KEY1_INTEGRATED_PASS points=%0d lines=%0d queries=%0d requests=%0d cycles=%0d",n2,lines,queries,requests,cycle);

 if(metric_pending||metric_requests==0||metric_requests!=metric_completions)
  $fatal(1,"distance request/completion imbalance req=%0d done=%0d pending=%0d",metric_requests,metric_completions,metric_pending);
 $display("DOC_MAPPER_HANDSHAKE_PASS requests=%0d completions=%0d min_latency=%0d max_latency=%0d",metric_requests,metric_completions,metric_min_latency,metric_max_latency);
 $finish;
end
always @(posedge clk)begin
 cycle<=cycle+1;pixel_valid<=0;
 if(rst_n)begin
  if(pixel_request&&pixel_ready)begin
   if(pixel_x>1279||pixel_y>719)$fatal(1,"source pixel outside frame");
   address=pixel_y*1280+pixel_x;latency=2+cycle%3;pending<=1;requests=requests+1;
  end else if(pending)begin
   if(latency>0)latency=latency-1;
   else begin pixel_luma<=source_y[address];pixel_valid<=1;pending<=0;end
  end
  if(dut.point_valid&&dut.point_ready)begin

   begin
    $fdisplay(points2,"%06x",{dut.point_dot,dut.point_end,dut.point_start,dut.point_y,dut.point_x});n2=n2+1;
   end
  end
 end
 if(cycle>170000000)$fatal(1,"pipeline watchdog state=%0d planner=%0d",dut.state,dut.u_planner.state);
end
// Abstract UART byte acceptance/completion and real parser replies. A '?' is
// answered with Idle; each complete line has exactly one delayed ok.
always @(posedge clk)begin
 tx_done<=0;rx_valid<=0;
 if(rst_n)begin
  if(tx_valid&&tx_ready)begin
   tx_done<=1;tx_bytes=tx_bytes+1;
   if(tx_data==10)begin
    $fwrite(fh,"\n");lines=lines+1;
    if(reply_len)$fatal(1,"multiple motion commands in flight");
    reply=0;reply[7:0]="o";reply[15:8]="k";reply[23:16]=10;
    reply_i=0;reply_len=3;reply_delay=8;
   end else $fwrite(fh,"%c",tx_data);
  end
  if(rt_valid&&rt_ready)begin
   tx_done<=1;queries=queries+1;
   if(rt_data!=8'h3f||reply_len)$fatal(1,"unexpected realtime command");
   reply=0;reply[7:0]="<";reply[15:8]="I";reply[23:16]="d";reply[31:24]="l";reply[39:32]="e";
   reply[47:40]="|";reply[55:48]=">";reply[63:56]=10;
   reply_i=0;reply_len=8;reply_delay=8;
  end
  if(reply_delay>0)reply_delay=reply_delay-1;
  else if(reply_len>0)begin
   rx_valid<=1;rx_data<=reply[reply_i*8+:8];reply_i=reply_i+1;reply_len=reply_len-1;reply_delay=2;
  end
 end
end
endmodule
