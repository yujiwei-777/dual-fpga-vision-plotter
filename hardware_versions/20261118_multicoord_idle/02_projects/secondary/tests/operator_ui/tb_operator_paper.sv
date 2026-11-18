`timescale 1ns/1ps
// Real reporter + shared transport + formatter + response parser. No fake ACK
// bypass: every ok/Alarm/Reset enters the production byte-level parser.
module tb_operator_paper;
reg clk=0;always #5 clk=~clk;
reg frame_reset=0;wire [15:0] rebased_y;
reg new_page=0,page_safe=1,doc_reserve=0;
wire[15:0]page_used,page_remaining,page_generation;wire page_full;wire[7:0]page_result;
reg rst_n=0,clear=0,stop=0,abort_job=0,rearm=0,job_valid=0,local_test=1,cnn=0,link_ready=1;
reg [31:0] job_id=0; reg [1:0] judgement=1;
reg rx_valid=0,rx_error=0;reg [7:0] rx_data=0;
wire job_ready,busy,done,error,recovery;
wire [7:0] error_code;wire [31:0] acked;wire [2:0] job_state;
reg tx_done=0,uart_busy=0;integer uart_delay=0;
wire tx_ready=!uart_busy,rt_ready=!uart_busy;
wire [7:0] tx_data,rt_data;wire tx_valid,rt_valid;
integer tx_lines=0,read_line=0,done_events=0,queries=0,holds=0,resets=0,scenarios=0;
string lines[0:4095];string serial_line="";string case_name="initial";
wire  S_start;
wire  S_clear;
wire  S_abort;
wire  S_stop;
wire  S_rearm;
wire  S_cancel;
wire  S_fault;
wire  S_reset_job;
wire  S_profile_valid;
wire [7:0] S_fault_code;
wire [511:0] S_line;
wire [6:0] S_length;
wire  S_line_valid;
wire  S_line_last;
wire  S_finish;
wire  S_available;
wire  S_line_ready;
wire  S_line_done;
wire  S_busy;
wire  S_done;
wire  S_error;
wire  S_cancelled;
wire  S_recovery_required;
wire [7:0] S_error_code;
wire [31:0] S_acked_lines;
wire [2:0] S_job_state;
wire  S_rt_done;
wire  X_start;
wire [1:0] X_kind;
wire [15:0] X_x;
wire [15:0] X_y;
wire [15:0] X_z;
wire [15:0] X_feed;
wire [15:0] X_pwm;
wire [511:0] X_line;
wire [6:0] X_length;
wire  X_done;
wire  X_busy;
grbl_reporter_shared_candidate #(.CLK_HZ(1000),.MAZE_ENABLE(0),.AUTO_NEWLINE(1),.KEY2_REZERO(1),.PCB_SUSPECT_ENABLE(1),.PCB_SUSPECT_CENTER_INPUT(1)) reporter(
  .I_work_frame_reset(frame_reset),.O_rebased_y_cmm(rebased_y),
  .I_new_page(new_page),.I_page_safe(page_safe),.I_doc_reserve(doc_reserve),
  .O_page_used_cmm(page_used),.O_page_remaining_cmm(page_remaining),
  .O_page_generation(page_generation),.O_page_result(page_result),.O_page_full(page_full),
  .I_maze_goal(8'd0),.I_maze_endpoint(8'd0),.I_pen_up_cmm(-16'sd120),.I_pen_down_cmm(16'sd120),
  .I_clk(clk),
  .I_rst_n(rst_n),
  .I_clear(clear),
  .I_abort(abort_job),
  .I_stop(stop),
  .I_rearm(rearm),
  .I_job_valid(job_valid),
  .I_job_id(job_id),
  .I_session_id(64'd1),
  .I_job_source(3'd1),
  .I_judgement(judgement),
  .I_defect_count(3'd0),
  .I_defect_boxes(256'd0),
  .I_maze_mode(1'b0),
  .I_maze_status(2'd0),
  .I_maze_steps(9'd0),
  .I_maze_start(8'd0),
  .I_maze_directions(512'd0),
  .I_maze_walls(1024'd0),
  .O_job_ready(job_ready),
  .O_busy(busy),
  .O_done(done),
  .O_error(error),
  .O_error_code(error_code),
  .O_acked_lines(acked),
  .O_job_state(job_state),
  .O_recovery_required(recovery),
  .O_rt_data(),
  .O_rt_valid(),
  .I_rt_ready(rt_ready),
  .O_rt_done(),
  .I_link_ready(link_ready),
  .I_profile_valid(1'b1),
  .I_pen_pwm_mode(1'b0),
  .I_origin_x_cmm(16'd1000),
  .I_origin_y_cmm(16'd1000),
  .I_work_x_cmm(16'd21000),
  .I_work_y_cmm(16'd29700),
  .I_step_cmm(8'd100),
  .I_pen_up_pwm(16'd1000),
  .I_pen_down_pwm(16'd1500),
  .I_travel_feed(16'd3000),
  .I_draw_feed(16'd1200),
  .I_pen_feed(16'd600),
  .O_tx_data(),
  .O_tx_valid(),
  .I_tx_ready(tx_ready),
  .I_tx_done(tx_done),
  .I_rx_data(rx_data),
  .I_rx_valid(rx_valid),
  .I_rx_error(rx_error),
  .I_defect_kinds(8'd0),
  .I_cnn_mode(cnn),
  .I_cnn_class(16'd1),
  .I_cnn_confidence(8'd37),
  .I_local_test(local_test),
  .S_start(S_start),
  .S_clear(S_clear),
  .S_abort(S_abort),
  .S_stop(S_stop),
  .S_rearm(S_rearm),
  .S_cancel(S_cancel),
  .S_fault(S_fault),
  .S_reset_job(S_reset_job),
  .S_profile_valid(S_profile_valid),
  .S_fault_code(S_fault_code),
  .S_line(S_line),
  .S_length(S_length),
  .S_line_valid(S_line_valid),
  .S_line_last(S_line_last),
  .S_finish(S_finish),
  .S_available(S_available),
  .S_line_ready(S_line_ready),
  .S_line_done(S_line_done),
  .S_busy(S_busy),
  .S_done(S_done),
  .S_error(S_error),
  .S_cancelled(S_cancelled),
  .S_recovery_required(S_recovery_required),
  .S_error_code(S_error_code),
  .S_acked_lines(S_acked_lines),
  .S_job_state(S_job_state),
  .S_rt_done(S_rt_done),
  .X_start(X_start),
  .X_kind(X_kind),
  .X_x(X_x),
  .X_y(X_y),
  .X_z(X_z),
  .X_feed(X_feed),
  .X_pwm(X_pwm),
  .X_line(X_line),
  .X_length(X_length),
  .X_done(X_done),
  .X_busy(X_busy)
);
// Soft ACK expiry now queries status without replay; shorten the independent
// absolute hard bound so lost-ok cases remain finite and retain their checks.
grbl_shared_transport_candidate #(.CLK_HZ(1000),.REPORT_ACK_TIMEOUT_CYCLES(1000),.REPORT_STATUS_TIMEOUT_CYCLES(2000),
 .REPORT_ACK_HARD_MS(1050),.REPORT_ACK_POLL_MS(20)) transport(
  .clk(clk),
  .rst_n(rst_n),
  .I_doc_owner(1'b0),
  .I_report_claim(busy||job_valid||recovery),
  .link_ready(link_ready),
  .tx_ready(tx_ready),
  .tx_done(tx_done),
  .rt_ready(rt_ready),
  .rx_data(rx_data),
  .rx_valid(rx_valid),
  .rx_error(rx_error),
  .tx_data(tx_data),
  .tx_valid(tx_valid),
  .rt_data(rt_data),
  .rt_valid(rt_valid),
  .R_start(S_start),
  .R_clear(S_clear),
  .R_abort(S_abort),
  .R_stop(S_stop),
  .R_rearm(S_rearm),
  .R_cancel(S_cancel),
  .R_fault(S_fault),
  .R_reset_job(S_reset_job),
  .R_profile_valid(S_profile_valid),
  .R_fault_code(S_fault_code),
  .R_line(S_line),
  .R_length(S_length),
  .R_line_valid(S_line_valid),
  .R_line_last(S_line_last),
  .R_finish(S_finish),
  .R_available(S_available),
  .R_line_ready(S_line_ready),
  .R_line_done(S_line_done),
  .R_busy(S_busy),
  .R_done(S_done),
  .R_error(S_error),
  .R_cancelled(S_cancelled),
  .R_recovery_required(S_recovery_required),
  .R_error_code(S_error_code),
  .R_acked_lines(S_acked_lines),
  .R_job_state(S_job_state),
  .R_rt_done(S_rt_done),
  .R_fmt_start(X_start),
  .R_fmt_kind(X_kind),
  .R_fmt_x(X_x),
  .R_fmt_y(X_y),
  .R_fmt_z(X_z),
  .R_fmt_feed(X_feed),
  .R_fmt_pwm(X_pwm),
  .R_fmt_line(X_line),
  .R_fmt_length(X_length),
  .R_fmt_done(X_done),
  .R_fmt_busy(X_busy),
  .D_start('0),
  .D_clear('0),
  .D_abort('0),
  .D_stop('0),
  .D_rearm('0),
  .D_cancel('0),
  .D_fault('0),
  .D_reset_job('0),
  .D_profile_valid('0),
  .D_fault_code('0),
  .D_line('0),
  .D_length('0),
  .D_line_valid('0),
  .D_line_last('0),
  .D_finish('0),
  .D_available(),
  .D_line_ready(),
  .D_line_done(),
  .D_busy(),
  .D_done(),
  .D_error(),
  .D_cancelled(),
  .D_recovery_required(),
  .D_error_code(),
  .D_acked_lines(),
  .D_job_state(),
  .D_rt_done(),
  .D_fmt_start('0),
  .D_fmt_kind('0),
  .D_fmt_x('0),
  .D_fmt_y('0),
  .D_fmt_z('0),
  .D_fmt_feed('0),
  .D_fmt_pwm('0),
  .D_fmt_line(),
  .D_fmt_length(),
  .D_fmt_done(),
  .D_fmt_busy()
);

task fail(input string why);begin
 $display("KEY2_ZERO_FAIL case=%s reporter_state=%0d transport_state=%0d tx_lines=%0d read_line=%0d cursor=%0d acked=%0d error=%0d code=%0d %s",case_name,reporter.state,transport.state,tx_lines,read_line,reporter.newline_offset_cmm,acked,error,error_code,why);
 $fatal(1,"KEY2 regression failed");end endtask
task tick(input integer n);begin repeat(n)@(negedge clk);end endtask
task pass;begin scenarios++;$display("KEY2_ZERO_CASE_PASS %s",case_name);end endtask
always @(posedge clk)begin
 if(!rst_n)begin uart_busy<=0;uart_delay<=0;tx_done<=0;serial_line="";end
 else begin
  tx_done<=0;
  if(done)done_events++;
  if(uart_busy)begin
   if(uart_delay==0)begin uart_busy<=0;tx_done<=1;end
   else uart_delay<=uart_delay-1;
  end else if(tx_valid&&tx_ready)begin
   uart_busy<=1;uart_delay<=2;
   if(tx_data==10)begin lines[tx_lines]=serial_line;tx_lines++;
    $display("GCODE case=%s line=%0d text=%s",case_name,tx_lines,serial_line);serial_line="";end
   else serial_line={serial_line,string'(tx_data)};
  end else if(rt_valid&&rt_ready)begin
   uart_busy<=1;uart_delay<=2;
   if(rt_data==8'h3f)queries++;
   if(rt_data==8'h21)holds++;
   if(rt_data==8'h18)resets++;
  end
 end
end
task send_rx(input string text);begin
 for(integer k=0;k<text.len();k++)begin @(negedge clk);rx_data=text.getc(k);rx_valid=1;end
 @(negedge clk);rx_valid=0;tick(1);
end endtask
task reset_case;begin
 @(negedge clk);rst_n=0;frame_reset=0;new_page=0;page_safe=1;doc_reserve=0;job_valid=0;stop=0;abort_job=0;clear=0;rearm=0;rx_valid=0;link_ready=1;
 tick(4);tx_lines=0;read_line=0;done_events=0;queries=0;holds=0;resets=0;rst_n=1;tick(8);
end endtask
task start_job(input bit test_mode,input bit cnn_mode);integer n;begin
 local_test=test_mode;cnn=cnn_mode;job_id++;tick(2);n=0;
 while(!job_ready&&n<200)begin tick(1);n++;end
 if(!job_ready)fail("job not ready");job_valid=1;tick(1);job_valid=0;
end endtask
task wait_line;integer n;begin
 n=0;while(tx_lines<=read_line&&n<50000)begin tick(1);n++;end
 if(tx_lines<=read_line)fail("UART line timeout");
 n=0;while(transport.state!=transport.R_ACK&&n<30)begin tick(1);n++;end
 if(transport.state!=transport.R_ACK)fail("no ACK wait after transmitted line");
 tick(2);
end endtask
task ack_line;begin wait_line();send_rx("ok\n");read_line++;tick(2);end endtask
task wait_done;integer n;begin
 n=0;while(done_events==0&&n<100)begin tick(1);n++;end
 if(done_events!=1||error||recovery)fail("expected clean single done");tick(5);
 if(reporter.newline_offset_cmm!=0)fail("KEY2 cursor not zero after final ACK");
end endtask
task wait_return;begin
 for(integer k=0;k<12;k++)ack_line();
 wait_line();
 if(tx_lines!=13||lines[12]!="G0 X000.00 Y035.00 F03000")fail("return must be machine X0 Y35");
 if(S_line_last)fail("return prematurely marked final");
end endtask
task normal_key2(input bit second);integer q0,r0;begin
 r0=rebased_y;start_job(1,0);q0=queries;wait_return();
 tick(20);if(tx_lines!=13||done_events!=0)fail("G92 or DONE before return ACK");
 send_rx("ok\n");read_line++;tick(2);wait_line();
 if(tx_lines!=14||lines[13]!="G92 X0 Y0")fail("missing final G92 X0 Y0");
 if(!S_line_last)fail("G92 not final");
 tick(20);if(rebased_y!=r0)fail("physical offset advanced before G92 ACK");if(done_events!=0||tx_lines!=14)fail("DONE before G92 ACK or line replay");
 send_rx("ok\n");read_line++;wait_done();
 if(rebased_y!=r0+3500)fail("G92 acknowledged offset not accumulated");
 if(acked!=14||queries!=q0)fail("normal KEY2 ACK count/query mismatch");
 if(second&&lines[4]!="G0 X190.00 Y010.00 F03000")fail("second KEY2 inherited prior cursor");
end endtask
initial begin
 case_name="two_KEY2_ACK_gated_X0_Y35_rezero";reset_case();normal_key2(0);
 // Keep the real work-coordinate change and reporter cursor across jobs.
 tx_lines=0;read_line=0;done_events=0;normal_key2(1);pass();
 case_name="return_lost_ok_no_G92_no_replay";reset_case();start_job(1,0);wait_return();tick(1100);
 if(!error||!recovery||error_code!=3||tx_lines!=13||done_events!=0)fail("return lost ok unsafe");
 if(reporter.newline_offset_cmm!=2500||rebased_y!=0)fail("return failure changed offset or did not reserve extent");pass();
 case_name="G92_lost_ok_no_done_no_replay";reset_case();start_job(1,0);wait_return();send_rx("ok\n");read_line++;wait_line();tick(1100);
 if(!error||!recovery||error_code!=3||tx_lines!=14||done_events!=0)fail("G92 lost ok unsafe");
 if(reporter.newline_offset_cmm!=2500||rebased_y!=0)fail("G92 failure prematurely changed frame/cursor");pass();
 case_name="KEY4_stop_before_return_ACK";reset_case();start_job(1,0);wait_return();stop=1;tick(1);stop=0;tick(30);
 send_rx("<Hold:0|MPos:0,0,0>\n");tick(100);
 if(tx_lines!=13||done_events!=0||!recovery||holds==0)fail("KEY4 stop emitted rebase or unlocked");pass();
 case_name="Alarm_before_return_ACK";reset_case();start_job(1,0);wait_return();send_rx("ALARM:1\n");tick(20);
 if(!error||!recovery||tx_lines!=13||done_events!=0)fail("Alarm allowed rebase");pass();
 case_name="Reset_before_return_ACK";reset_case();start_job(1,0);wait_return();send_rx("Grbl 1.1h ['$' for help]\n");tick(20);
 if(!error||!recovery||error_code!=9||tx_lines!=13||done_events!=0)fail("Reset allowed rebase");pass();
 case_name="PCB_report_retains_old_newline_no_G92";reset_case();start_job(0,0);
 begin integer n;n=0;while(done_events==0&&n<1500)begin ack_line();n++;end
 if(done_events!=1||error||recovery||reporter.newline_offset_cmm==0)fail("PCB newline changed");
 for(integer k=0;k<tx_lines;k++)if(lines[k]=="G92 X0 Y0")fail("PCB emitted KEY2 rebase");
 if(lines[tx_lines-1].substr(0,9)!="G0 X190.00")fail("PCB normal mirrored return changed");end
 pass();
 case_name="CNN_report_retains_old_newline_no_G92";reset_case();judgement=2;start_job(0,1);
 begin integer n;n=0;while(done_events==0&&n<1500)begin ack_line();n++;end
 if(done_events!=1||error||recovery||reporter.newline_offset_cmm==0)fail("CNN newline changed");
 for(integer k=0;k<tx_lines;k++)if(lines[k]=="G92 X0 Y0")fail("CNN emitted KEY2 rebase");
 if(lines[tx_lines-1].substr(0,9)!="G0 X190.00")fail("CNN normal mirrored return changed");end
 pass();
 case_name="eight_KEY2_page_budget_then_ninth_rejected";reset_case();
 for(integer job=0;job<8;job++)begin
  tx_lines=0;read_line=0;done_events=0;normal_key2(job!=0);
 end
 if(rebased_y!=28000)fail("eight KEY2 accumulated Y is not 280mm");
 done_events=0;start_job(1,0);tick(200);
 if(!error||error_code!=12||tx_lines!=14||done_events!=0||rebased_y!=28000)fail("ninth KEY2 not safely rejected");
 pass();
 case_name="PCB_CNN_at_rebased_page_bottom_rejected";
 clear=1;tick(1);clear=0;tick(5);start_job(0,0);tick(200);
 if(!error||error_code!=12||tx_lines!=14||rebased_y!=28000)fail("PCB report escaped rebased page budget");
 clear=1;tick(1);clear=0;tick(5);start_job(0,1);tick(200);
 if(!error||error_code!=12||tx_lines!=14||rebased_y!=28000)fail("CNN report escaped rebased page budget");
 pass();
 case_name="fresh_work_frame_reset_preserves_physical_paper_offset";reset_case();normal_key2(0);
 frame_reset=1;tick(1);frame_reset=0;tick(5);
 if(rebased_y!=0||reporter.newline_offset_cmm!=3500||tx_lines!=14)fail("frame reset lost consumed paper or emitted motion");
 tx_lines=0;read_line=0;done_events=0;start_job(1,0);
 for(integer k=0;k<12;k++)ack_line();wait_line();
 if(lines[4]!="G0 X190.00 Y045.00 F03000"||lines[12]!="G0 X000.00 Y070.00 F03000")fail("post-reset G54 cursor not preserved");
 ack_line();wait_line();if(lines[13]!="G92 X0 Y0")fail("post-reset missing rebase");ack_line();wait_done();
 if(rebased_y!=7000)fail("post-reset physical offset incorrect");pass();
 case_name="KEY4_stop_while_G92_unacknowledged";reset_case();start_job(1,0);wait_return();ack_line();wait_line();
 if(lines[13]!="G92 X0 Y0")fail("G92 pending precondition missing");
 stop=1;tick(1);stop=0;tick(30);send_rx("<Hold:0|MPos:0,0,0>\n");tick(100);
 if(tx_lines!=14||done_events!=0||!recovery||holds==0||rebased_y!=0)fail("KEY4 during G92 unlocked/replayed/rebased");pass();
 case_name="Alarm_while_G92_unacknowledged";reset_case();start_job(1,0);wait_return();ack_line();wait_line();
 send_rx("ALARM:1\n");tick(30);
 if(!error||!recovery||tx_lines!=14||done_events!=0||rebased_y!=0)fail("Alarm during G92 unsafe");pass();
 case_name="Reset_while_G92_unacknowledged";reset_case();start_job(1,0);wait_return();ack_line();wait_line();
 send_rx("Grbl 1.1h ['$' for help]\n");tick(30);
 if(!error||!recovery||error_code!=9||tx_lines!=14||done_events!=0||rebased_y!=0)fail("Reset during G92 unsafe");pass();
 case_name="UART_link_ready_drop_while_G92_unacknowledged";reset_case();start_job(1,0);wait_return();ack_line();wait_line();
 link_ready=0;tick(30);
 if(!error||!recovery||error_code!=2||tx_lines!=14||done_events!=0||rebased_y!=0)fail("UART link ready loss during G92 unsafe");
 link_ready=1;tick(50);
 if(!recovery||tx_lines!=14||done_events!=0||rebased_y!=0||job_ready)fail("UART ready return auto-rearmed or replayed G92");pass();

 case_name="paper_initial_safe_height_and_document_reservation";reset_case();
 if(page_used!=0||page_remaining!=23700||page_generation!=0)fail("wrong initial 237mm occupied paper budget");
 doc_reserve=1;tick(1);doc_reserve=0;tick(3);
 if(page_used!=11188||page_remaining!=11512||tx_lines!=0)fail("doc acceptance not conservatively reserved without motion");
 doc_reserve=1;tick(1);doc_reserve=0;tick(3);
 if(page_used!=11188)fail("repeated document admission rewound occupied page");pass();
 case_name="new_page_clean_frame_resets_only_paper_no_motion";
 new_page=1;tick(1);new_page=0;tick(3);
 if(page_result!=1||page_used!=0||page_generation!=1||tx_lines!=0||queries||resets)fail("new page changed machine or failed");pass();
 case_name="new_page_rejected_while_job_busy_no_deferred_clear";reset_case();start_job(1,0);wait_line();
 new_page=1;tick(1);new_page=0;tick(3);
 if(page_result!=2||page_generation!=0)fail("busy new page was not rejected");
 while(done_events==0)ack_line();tick(5);
 if(page_used!=3500||page_generation!=0)fail("busy new page deferred into later job completion");pass();
 case_name="new_page_cannot_forget_acknowledged_G92";
 new_page=1;tick(1);new_page=0;tick(3);
 if(page_result!=4||rebased_y!=3500||page_used!=3500||page_generation!=0)fail("new page bypassed G92 physical offset");
 frame_reset=1;tick(1);frame_reset=0;tick(3);
 if(rebased_y!=0||page_used!=3500||page_remaining!=19200)fail("actual frame reset changed physical occupied paper");
 new_page=1;tick(1);new_page=0;tick(3);
 if(page_result!=1||page_generation!=1||page_used!=0||page_remaining!=23700||tx_lines!=14)fail("explicit new page after frame reset failed");pass();
 case_name="unsafe_new_page_not_replayed_when_safe";
 doc_reserve=1;tick(1);doc_reserve=0;page_safe=0;new_page=1;tick(1);new_page=0;tick(3);page_safe=1;tick(10);
 if(page_result!=3||page_generation!=1||page_used!=11188||tx_lines!=14)fail("unsafe page clear deferred/replayed");pass();

 case_name="document_commit_wins_simultaneous_new_page";reset_case();
 doc_reserve=1;new_page=1;tick(1);doc_reserve=0;new_page=0;tick(3);
 if(page_result!=2||page_used!=11188||page_generation!=0||tx_lines!=0)fail("new page erased accepted document reservation");
 tick(20);if(page_used!=11188||page_generation!=0)fail("simultaneous rejected request replayed");pass();
 $display("OPERATOR_PAPER_PASS cases=%0d",scenarios);$finish;
end
initial begin #1000000000;$fatal(1,"global timeout");end
endmodule
