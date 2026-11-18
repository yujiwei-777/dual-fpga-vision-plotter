`timescale 1ns/1ps
module tb_robust_transport;
wire R_idle_done;
reg clk=0;
reg rst_n=0;
reg I_doc_owner=0;
reg I_report_claim=0;
reg link_ready=0;
wire tx_ready;
reg tx_done=0;
wire rt_ready;
reg [7:0] rx_data=0;
reg rx_valid=0;
reg rx_error=0;
wire [7:0] tx_data;
wire tx_valid;
wire [7:0] rt_data;
wire rt_valid;
reg R_start=0;
reg R_clear=0;
reg R_abort=0;
reg R_stop=0;
reg R_rearm=0;
reg R_cancel=0;
reg R_fault=0;
reg R_reset_job=0;
reg R_profile_valid=0;
reg [7:0] R_fault_code=0;
reg [511:0] R_line=0;
reg [6:0] R_length=0;
reg R_line_valid=0;
reg R_line_last=0;
reg R_finish=0;
wire R_available;
wire R_line_ready;
wire R_line_done;
wire R_busy;
wire R_done;
wire R_error;
wire R_cancelled;
wire R_recovery_required;
wire [7:0] R_error_code;
wire [31:0] R_acked_lines;
wire [2:0] R_job_state;
wire R_rt_done;
reg R_fmt_start=0;
reg [1:0] R_fmt_kind=0;
reg [15:0] R_fmt_x=0;
reg [15:0] R_fmt_y=0;
reg [15:0] R_fmt_z=0;
reg [15:0] R_fmt_feed=0;
reg [15:0] R_fmt_pwm=0;
wire [511:0] R_fmt_line;
wire [6:0] R_fmt_length;
wire R_fmt_done;
wire R_fmt_busy;
reg D_start=0;
reg D_clear=0;
reg D_abort=0;
reg D_stop=0;
reg D_rearm=0;
reg D_cancel=0;
reg D_fault=0;
reg D_reset_job=0;
reg D_profile_valid=0;
reg [7:0] D_fault_code=0;
reg [511:0] D_line=0;
reg [6:0] D_length=0;
reg D_line_valid=0;
reg D_line_last=0;
reg D_finish=0;
wire D_available;
wire D_line_ready;
wire D_line_done;
wire D_busy;
wire D_done;
wire D_error;
wire D_cancelled;
wire D_recovery_required;
wire [7:0] D_error_code;
wire [31:0] D_acked_lines;
wire [2:0] D_job_state;
wire D_rt_done;
reg D_fmt_start=0;
reg [1:0] D_fmt_kind=0;
reg [15:0] D_fmt_x=0;
reg [15:0] D_fmt_y=0;
reg [15:0] D_fmt_z=0;
reg [15:0] D_fmt_feed=0;
reg [15:0] D_fmt_pwm=0;
wire [511:0] D_fmt_line;
wire [6:0] D_fmt_length;
wire D_fmt_done;
wire D_fmt_busy;
always #5 clk=~clk;
grbl_shared_transport_candidate #(.CLK_HZ(1000),
 .REPORT_ACK_TIMEOUT_CYCLES(400),.REPORT_STATUS_TIMEOUT_CYCLES(200),
 .DOC_STATUS_MS(200),.DOC_FINAL_MS(2000),.DOC_PROGRESS_MS(1000),.DOC_JOB_MS(4000)) dut(.*);
integer checks=0,errors=0,cases=0,case_errors=0;
integer tx_lines=0,queries=0,holds=0,resets=0,done_events=0;
integer byte_delay=0;reg uart_busy=0;
string case_name="initial",serial_line="";
always @(posedge clk)begin
 tx_done<=0;
 if(!rst_n)begin uart_busy<=0;byte_delay<=0;tx_lines<=0;queries<=0;holds<=0;resets<=0;done_events<=0;serial_line="";end
 else begin
  if(R_done)done_events<=done_events+1;
  if(uart_busy)begin
   if(byte_delay==0)begin uart_busy<=0;tx_done<=1;end
   else byte_delay<=byte_delay-1;
  end else if(rt_valid&&rt_ready)begin
   uart_busy<=1;byte_delay<=2;
   if(rt_data=="?")queries<=queries+1;
   if(rt_data=="!")holds<=holds+1;
   if(rt_data==8'h18)resets<=resets+1;
  end else if(tx_valid&&tx_ready)begin
   uart_busy<=1;byte_delay<=2;
   if(tx_data==10)begin tx_lines<=tx_lines+1;serial_line="";end
   else serial_line={serial_line,string'(tx_data)};
  end
 end
end
assign tx_ready=!uart_busy;
assign rt_ready=!uart_busy;
task tick;begin @(posedge clk);#1;end endtask
task check(input bit good,input string message);begin
 checks=checks+1;
 if(!good)begin errors=errors+1;$display("CHECK_FAIL %s: %s",case_name,message);end
end endtask
task start_case(input string name);begin
 @(negedge clk);rst_n=0;I_doc_owner=0;I_report_claim=0;
 R_start=0;R_clear=0;R_abort=0;R_stop=0;R_rearm=0;R_line_valid=0;
 D_start=0;D_clear=0;D_reset_job=0;D_rearm=0;D_cancel=0;D_fault=0;
 rx_valid=0;rx_error=0;link_ready=1;R_profile_valid=1;D_profile_valid=1;
 case_name=name;case_errors=errors;repeat(4)tick;
 @(negedge clk);rst_n=1;repeat(5)tick;
end endtask
task end_case;begin
 cases=cases+1;
 if(errors==case_errors)$display("CASE_PASS %s",case_name);
end endtask
// Returns on the negedge after newline: the parser Alarm pulse is live and
// the transport consumes it on the next posedge. Start/clear can coincide.
task receive(input string text);begin
 for(integer k=0;k<text.len();k=k+1)begin
  @(negedge clk);rx_valid=1;rx_data=text[k];tick;
 end
 @(negedge clk);rx_valid=0;
end endtask
task wait_state(input integer target,input integer bound);integer n;begin
 n=0;while(dut.state!=target&&n<bound)begin tick;n=n+1;end
 check(dut.state==target,$sformatf("state %0d not reached (at %0d)",target,dut.state));
 // Real UART reception follows its transmitted '?' by many clocks. Allow
 // the registered parser-clear pulse to retire before supplying byte one.
 repeat(2)tick;
end endtask
task check_lock;begin
 check(R_recovery_required&&dut.owner_valid&&!dut.owner_doc,"Alarm must retain report recovery ownership");
 check(!D_busy&&!D_line_ready&&!R_line_ready,"Alarm must not expose a producer motion slot");
 check(tx_lines==0&&done_events==0,"Alarm must not transmit or complete a motion line");
end endtask
task alarm_and_latch;begin receive("ALARM:1\n");tick;repeat(3)tick;end endtask
task transmit_last_line;begin
 @(negedge clk);I_report_claim=1;R_start=1;tick;
 @(negedge clk);R_start=0;wait_state(1,20);
 @(negedge clk);R_line=512'h303947;R_length=3;R_line_last=1;R_line_valid=1;tick;
 @(negedge clk);R_line_valid=0;wait_state(4,100);
 receive("ok\n");repeat(6)tick;
 check(R_acked_lines==1&&done_events==1&&!R_recovery_required&&!R_error,"last ok must complete exactly once");
 check(tx_lines==1,"one complete G90 line only");
end endtask
initial begin
 start_case("unowned_idle_alarm");alarm_and_latch;check_lock;
 check(R_error&&R_error_code==5,"idle Alarm must report response fault");end_case;

 start_case("owned_report_idle_alarm");I_report_claim=1;repeat(3)tick;
 alarm_and_latch;check_lock;end_case;

 start_case("doc_prepare_alarm");I_doc_owner=1;repeat(3)tick;
 check(dut.owner_valid&&dut.owner_doc,"document preparation owns transport");
 alarm_and_latch;check_lock;end_case;

 start_case("alarm_same_edge_report_start_clear");receive("ALARM:2\n");
 I_report_claim=1;R_start=1;R_clear=1;tick;
 @(negedge clk);R_start=0;R_clear=0;repeat(4)tick;check_lock;end_case;

 start_case("alarm_same_edge_doc_start_clear");I_doc_owner=1;repeat(3)tick;
 receive("ALARM:3\n");D_start=1;D_clear=1;R_clear=1;tick;
 @(negedge clk);D_start=0;D_clear=0;R_clear=0;repeat(4)tick;check_lock;
 check(queries==0,"Alarm must suppress simultaneous document-start query");end_case;

 start_case("clear_and_idle_cannot_rearm_alarm");alarm_and_latch;
 R_clear=1;tick;@(negedge clk);R_clear=0;receive("<Idle|MPos:0,0,0>\n");repeat(3)tick;
 R_start=1;I_report_claim=1;tick;@(negedge clk);R_start=0;repeat(5)tick;
 check_lock;end_case;

 start_case("repeat_alarm_stays_locked");alarm_and_latch;
 receive("ALARM:4\n");repeat(4)tick;check_lock;
 check(R_error&&R_error_code==5,"repeated Alarm remains a response fault");end_case;

 start_case("key4_requires_fresh_hold_and_idle");alarm_and_latch;
 // Follow the actual realtime stop/reset/query state machine, without force.
 R_stop=1;tick;@(negedge clk);R_stop=0;wait_state(16,100);
 receive("<Hold:1|MPos:0,0,0>\n");repeat(4)tick;
 check(R_recovery_required&&resets==0,"decelerating Hold:1 cannot reset or unlock");
 receive("<Hold:0|MPos:0,0,0>\n");wait_state(21,100);
 check(holds==1&&resets==1&&queries==2,"KEY4 must send ! ? Ctrl-X ? exactly once");
 receive("<Run|MPos:0,0,0>\n");repeat(4)tick;
 check(R_recovery_required,"post-reset non-Idle status cannot unlock");
 receive("<Idle|MPos:0,0,0>\n");repeat(5)tick;
 check(!R_recovery_required&&!R_error,"fresh post-reset Idle unlocks");
 I_doc_owner=0;transmit_last_line;end_case;

 start_case("post_reset_alarm_rejects_late_idle");R_stop=1;tick;
 @(negedge clk);R_stop=0;wait_state(16,100);receive("<Hold:0|MPos:0,0,0>\n");wait_state(21,100);
 receive("<Alarm|MPos:0,0,0>\n");repeat(4)tick;
 receive("<Idle|MPos:0,0,0>\n");repeat(4)tick;
 check(R_recovery_required&&R_error,"post-reset Alarm must lock despite a later unsolicited Idle");end_case;

 start_case("key4_without_fresh_idle_times_out");R_stop=1;tick;
 @(negedge clk);R_stop=0;wait_state(16,100);
 receive("<Idle|MPos:0,0,0>\n");wait_state(21,100);
 repeat(220)tick;
 check(R_recovery_required&&R_error&&R_error_code==4,"missing post-reset Idle locks on timeout");
 check(done_events==0&&tx_lines==0,"safety timeout cannot complete or draw");end_case;

 start_case("normal_last_ok_no_idle_poll");transmit_last_line;
 check(queries==0&&holds==0&&resets==0,"normal last-ok completion needs no final Idle query");end_case;

 start_case("reset_still_locks_idle");receive("Grbl 1.1h ['$' for help]\n");repeat(4)tick;check_lock;
 check(R_error_code==9,"existing Reset fault code unchanged");end_case;

 if(errors!=0)$fatal(1,"ROBUST_TRANSPORT_FAIL cases=%0d checks=%0d errors=%0d",cases,checks,errors);
 $display("ROBUST_TRANSPORT_PASS cases=%0d checks=%0d",cases,checks);$finish;
end
initial begin #1000000;$fatal(1,"transport test global timeout");end
endmodule
