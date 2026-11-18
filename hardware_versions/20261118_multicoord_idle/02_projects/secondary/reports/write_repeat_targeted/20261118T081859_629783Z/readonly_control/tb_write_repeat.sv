`timescale 1ns/1ps
// Real reporter + shared transport + formatter + response parser. No fake ACK
// bypass: every ok/Alarm/Reset enters the production byte-level parser.
module tb_write_repeat;
reg clk=0;always #5 clk=~clk;
reg [2:0] input_count=1;reg [255:0] input_boxes=0;reg [7:0] input_kinds=3;
reg [7:0] cnn_conf=3;reg [15:0] cnn_class=5;
string printed[0:2];integer paper_mark_moves=0;
wire clear,job_valid;
reg [7:0] probe_step=100;
reg doc_owner_input=0,doc_fmt_start=0;

reg frame_reset=0,paper_confirm=0;wire [15:0] rebased_y;
reg rst_n=0,stop=0,abort_job=0,rearm=0,local_test=0,cnn=0,link_ready=1;
wire [31:0] job_id; reg [1:0] judgement=1;
reg rx_valid=0,rx_error=0;reg [7:0] rx_data=0;
wire job_ready,busy,done,error,recovery;
wire paper_confirm_armed,paper_confirm_active;
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
grbl_reporter_shared_candidate #(.CLK_HZ(1000),.MAZE_ENABLE(0),.AUTO_NEWLINE(1),.KEY2_REZERO(1),.PCB_SUSPECT_ENABLE(1),.PCB_SUSPECT_CENTER_INPUT(1),.PAPER_LOAD_FIRST_ROW_CMM(3000),.PAPER_LOAD_CENTER_Y_CMM(14850),.PAPER_LOAD_LAST_ROW_CMM(26700),.PAPER_LOCAL_Y_LIMIT_CMM(23700)) reporter(
  .I_work_frame_reset(frame_reset),.O_rebased_y_cmm(rebased_y),
  .I_paper_confirm(paper_confirm),.O_paper_confirm_armed(paper_confirm_armed),.O_paper_confirm_active(paper_confirm_active),
  .I_new_page(1'b0),.I_page_safe(1'b1),.I_doc_reserve(1'b0),
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
  .I_job_source(3'd0),
  .I_judgement(judgement),
  .I_defect_count(input_count),
  .I_defect_boxes(input_boxes),
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
  .I_step_cmm(probe_step),
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
  .I_defect_kinds(input_kinds),
  .I_cnn_mode(cnn),
  .I_cnn_class(cnn_class),
  .I_cnn_confidence(cnn_conf),
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
  .I_doc_owner(doc_owner_input),
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
  .D_fmt_start(doc_fmt_start),
  .D_fmt_kind('0),
  .D_fmt_x('0),
  .D_fmt_y('0),
  .D_fmt_z('0),
  .D_fmt_feed(16'd3000),
  .D_fmt_pwm('0),
  .D_fmt_line(),
  .D_fmt_length(),
  .D_fmt_done(),
  .D_fmt_busy()
);

task fail(input string why);begin
 $display("SUSPECT_REPORT_FAIL case=%s reporter_state=%0d transport_state=%0d tx_lines=%0d read_line=%0d cursor=%0d acked=%0d error=%0d code=%0d %s",case_name,reporter.state,transport.state,tx_lines,read_line,reporter.newline_offset_cmm,acked,error,error_code,why);
 $fatal(1,"KEY2 regression failed");end endtask
task tick(input integer n);begin repeat(n)@(negedge clk);end endtask
task pass;begin scenarios++;$display("SUSPECT_REPORT_CASE_PASS %s",case_name);end endtask
always @(posedge clk)begin
 if(!rst_n)begin uart_busy<=0;uart_delay<=0;tx_done<=0;serial_line="";end
 else begin
  tx_done<=0;
  if(done)done_events++;
  if(reporter.state==62 && reporter.report_line<=2)
   printed[reporter.report_line]={printed[reporter.report_line],string'(reporter.decoded_char)};
  if(reporter.state==43)paper_mark_moves++;
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
 @(negedge clk);rst_n=0;frame_reset=0;paper_confirm=0;stop=0;abort_job=0;rearm=0;rx_valid=0;link_ready=1;
 tick(4);tx_lines=0;read_line=0;done_events=0;queries=0;holds=0;resets=0;printed[0]="";printed[1]="";printed[2]="";paper_mark_moves=0;rst_n=1;tick(8);
end endtask
task wait_line;integer n;begin
 n=0;while(tx_lines<=read_line&&n<50000)begin tick(1);n++;end
 if(tx_lines<=read_line)fail("UART line timeout");
 n=0;while(transport.state!=transport.R_ACK&&n<30)begin tick(1);n++;end
 if(transport.state!=transport.R_ACK)fail("no ACK wait after transmitted line");
 tick(2);
end endtask
task ack_line;begin wait_line();send_rx("ok\n");read_line++;tick(2);end endtask
task paper_confirm_loaded;integer n;begin
 if(!paper_confirm_armed)fail("paper confirmation was not armed");
 tx_lines=0;read_line=0;done_events=0;paper_confirm=1;tick(1);paper_confirm=0;
 ack_line();if(lines[0]!="G90")fail("paper confirm missing G90");
 ack_line();if(lines[1]!="G1 Z-001.20 F00600")fail("paper confirm missing pen lift");
 ack_line();if(lines[2]!="G92 Y148.50")fail("paper confirm missing centre anchor");
 ack_line();if(lines[3]!="G0 Y30.00")fail("paper confirm missing first row");
 ack_line();if(lines[4]!="G0 Y267.00")fail("paper confirm missing far boundary");
 ack_line();if(lines[5]!="G0 Y30.00")fail("paper confirm missing return to first row");
 n=0;while(transport.state!=transport.R_PAPER_STATUS&&n<500)begin tick(1);n++;end
 if(transport.state!=transport.R_PAPER_STATUS)fail("paper confirm missing fresh Idle query");
 send_rx("<Idle|MPos:0,30,0>\n");wait_line();
 if(lines[read_line]!="G92 Y0")fail("paper confirm missing final Y zero");
 ack_line();tick(5);
 if(paper_confirm_armed||paper_confirm_active||error||recovery)fail("paper confirm did not finish cleanly");
end endtask

task complete_report;integer n,q0;begin
 n=0;q0=queries;
 while(done_events==0 && n<300000)begin
  if(tx_lines>read_line)begin ack_line();n++;end
  else begin tick(1);n++;end
 end
 tick(8);
 if(done_events!=1||error||recovery||busy)fail("report did not finish after final ok");
 if(queries!=q0)fail("normal completion polled Idle");
 if(paper_mark_moves!=0)fail("suspect produced a paper defect marker");
end endtask
task clear_history;begin
 tick(1);tick(5);
 printed[0]="";printed[1]="";printed[2]="";done_events=0;paper_mark_moves=0;
end endtask
task suspect_input;begin
 judgement=2;input_count=1;input_kinds=3;
 input_boxes={224'd0,16'd40,16'd120};
end endtask


localparam EXPECT_STUCK=1;
wire clk125=clk,rst125_n=rst_n;
reg vision_busy=0,key4_reset_active=0,key4_stop=0,key2_local_active=0,key2_new_page=0;
reg copy_busy=0,copy_recovery=0,vision_start=0,normal_done=0,target_valid=1;
reg operator_preview_capable=0,preview_locked=1;
reg cnn_cache_result_valid=1,cnn_cache_valid=1,cnn_cache_invalid=0;
reg pcb_report_cache_valid=1,pcb_report_cache_invalid=0,pcb_report_result=0;
reg [1:0] vision_purpose=0;
reg key1_report_action=0,profile_valid=1;
wire uart_link_ready=link_ready;
wire report_ready=job_ready,report_busy=busy,report_done=done,report_error=error;
wire report_recovery_required=recovery;
wire vision_job_cancel=abort_job,key4_press=stop;
reg report_pending=0,report_clear=0;
reg [2:0] report_admit_age=0;
reg [31:0] report_job=0,request_id=1;
wire key1_job_active,key1_job_protected;
wire [7:0] report_error_code=error_code;
reg [95:0] job_status_data=0;reg job_status_valid=0;
assign clear=report_clear;
assign job_valid=report_pending&&!key4_reset_active&&!key4_stop;
assign job_id=report_job;

    wire key1_report_slot_available=!vision_busy&&!key4_reset_active&&!key4_stop&&
        !report_busy&&!report_pending&&!key2_local_active&&!key2_new_page&&!key1_job_active&&
        !copy_busy&&!copy_recovery&&!report_recovery_required&&
        !paper_confirm_armed&&!paper_confirm_active;
    wire key1_local_admit=key1_report_action&&(!operator_preview_capable||preview_locked)&&cnn_cache_result_valid&&cnn_cache_valid&&!cnn_cache_invalid&&
        !normal_done&&(vision_purpose==2'd0)&&key1_report_slot_available;
    wire pcb_key1_admit=key1_report_action&&(!operator_preview_capable||preview_locked)&&pcb_report_cache_valid&&
        !pcb_report_cache_invalid&&!pcb_report_result&&!vision_start&&
        (vision_purpose==2'd1)&&key1_report_slot_available;
    wire key1_local_job_accept=(key1_local_admit||pcb_key1_admit)&&profile_valid&&uart_link_ready;
    grbl_key1_job_guard u_key1_job_guard(.I_clk(clk125),.I_rst_n(rst125_n),
        .I_accept(key1_local_job_accept),.I_explicit_cancel(vision_job_cancel||key4_press),
        .I_done(report_done),.I_error(report_error),.O_active(key1_job_active),
        .O_protected(key1_job_protected));
always @(posedge clk)begin
 if(!rst_n)begin report_pending<=0;report_clear<=0;report_admit_age<=0;report_job<=0;job_status_data<=0;job_status_valid<=0;end
 else begin
  report_clear<=0;
            if(report_pending&&report_ready)report_pending<=0;
            if(!report_pending)report_admit_age<=0;
            else if(report_admit_age<7)report_admit_age<=report_admit_age+1'b1;
  if(vision_job_cancel||key4_press)report_pending<=0;
  else begin
                if(report_pending&&report_admit_age>=3&&!report_busy&&!report_ready)begin
                    report_pending<=0;
                    job_status_data<={32'd0,16'd0,(!profile_valid?8'd1:!uart_link_ready?8'd2:report_error?report_error_code:8'd10),8'd5,report_job};
                    job_status_valid<=1;
                end
   if(key1_local_job_accept)begin
    report_job<=request_id;report_clear<=1;report_pending<=1;
   end
  end
 end
end
task key1_request(input integer id);
begin
 request_id=id;tick(2);
 if(!key1_report_slot_available)fail("KEY1 source slot unavailable before request");
 key1_report_action=1;tick(1);key1_report_action=0;
 if(!key1_job_active||!report_pending)fail("KEY1 admission did not protect pending snapshot");
end endtask
task clean_controls;
begin
 key1_report_action=0;probe_step=100;doc_owner_input=0;doc_fmt_start=0;
 vision_busy=0;copy_busy=0;copy_recovery=0;vision_start=0;normal_done=0;
 key4_reset_active=0;key4_stop=0;operator_preview_capable=0;preview_locked=1;
 reset_case();input_count=0;input_boxes=0;input_kinds=0;judgement=1;cnn=0;
end endtask
task finish_unique(input integer id);
begin
 done_events=0;key1_request(id);complete_report();tick(8);
 if(key1_job_active||report_pending||!key1_report_slot_available)fail("normal last-ok failed to release KEY1 slot");
end endtask
task check_rejection;
begin
 tick(15);
 if(report_pending||!job_status_valid||job_status_data[47:40]!=10||busy||tx_lines!=0)fail("pre-start refusal did not terminate with error10/no motion");
 if(EXPECT_STUCK)begin
  if(!key1_job_active||key1_report_slot_available)fail("control no longer reproduces stale lock");
  $display("WRITE_REPEAT_BASELINE_REPRODUCED pending0 error10 active1 next_KEY1_slot0");
 end else if(key1_job_active||!key1_report_slot_available)fail("fixed refusal did not release KEY1 owner");
end endtask
initial begin
 case_name="actual_reporter_profile_refusal";clean_controls();probe_step=0;tick(8);key1_request(1);check_rejection();pass();
 if(EXPECT_STUCK)begin
  $display("WRITE_REPEAT_CONTROL_PASS known_stale_lock_reproduced=1");$finish;
 end
 probe_step=100;tick(8);case_name="next_unique_KEY1_no_reset";finish_unique(2);pass();
 case_name="consecutive_unique_KEY1_normal_done";finish_unique(3);pass();
 case_name="busy_and_unsolicited_Hold_Idle_cannot_release_owner";
 done_events=0;key1_request(4);wait_line();tick(20);
 if(!busy||!key1_job_active||report_pending)fail("busy report falsely hit pre-start timeout");
 send_rx("<Hold:0|MPos:0,0,0>\n");send_rx("<Idle|MPos:0,0,0>\n");tick(5);
 if(!busy||!key1_job_active||done_events!=0)fail("status released in-flight task without ok");
 complete_report();tick(5);if(key1_job_active)fail("normal done retained owner");pass();
 case_name="actual_shared_doc_formatter_owner_quiescence";clean_controls();
 doc_owner_input=1;tick(3);doc_fmt_start=1;tick(1);doc_fmt_start=0;doc_owner_input=0;
 if(!transport.owner_valid||!transport.owner_doc||!transport.fmt_busy)fail("no live prior document formatter epoch");
 key1_request(5);tick(15);
 if(report_pending||key1_job_active||job_status_data[47:40]!=10||tx_lines!=0)fail("owner contention retained KEY1 or emitted motion");
 begin integer n;n=0;while((transport.owner_valid||transport.fmt_busy)&&n<200)begin tick(1);n++;end
 if(transport.owner_valid||transport.fmt_busy)fail("shared owner failed to release at quiescence");end
 finish_unique(6);pass();
 case_name="duplicate_report_id_refusal_then_unique";
 done_events=0;key1_request(6);tick(15);
 if(report_pending||key1_job_active||job_status_data[47:40]!=10||done_events!=0)fail("duplicate request remained locked or replayed");
 finish_unique(7);pass();
 case_name="Alarm_recovery_not_cleared";clean_controls();key1_request(8);wait_line();send_rx("ALARM:1\n");tick(15);
 if(!error||!recovery||key1_job_active||key1_report_slot_available||done_events!=0)fail("Alarm safety lock changed");pass();
 case_name="Reset_recovery_not_cleared";clean_controls();key1_request(9);wait_line();send_rx("Grbl 1.1h ['$' for help]\n");tick(15);
 if(!error||!recovery||error_code!=9||key1_job_active||key1_report_slot_available||done_events!=0)fail("Reset safety lock changed");pass();
 case_name="UART_loss_recovery_not_cleared";clean_controls();key1_request(10);wait_line();link_ready=0;tick(15);link_ready=1;tick(10);
 if(!error||!recovery||key1_job_active||key1_report_slot_available||done_events!=0)fail("UART safety lock changed");pass();
 case_name="explicit_cancel_pending_releases_owner";clean_controls();probe_step=0;tick(8);key1_request(11);abort_job=1;tick(1);abort_job=0;tick(5);
 if(report_pending||key1_job_active)fail("explicit cancel retained pending owner");pass();
 $display("WRITE_REPEAT_TARGETED_PASS cases=%0d",scenarios);$finish;
end
initial begin #1000000000;$fatal(1,"targeted regression timeout");end
endmodule
