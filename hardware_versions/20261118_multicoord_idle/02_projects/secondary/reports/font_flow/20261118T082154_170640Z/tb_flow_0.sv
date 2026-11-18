`timescale 1ns/1ps
// Real reporter + shared transport + formatter + response parser. No fake ACK
// bypass: every ok/Alarm/Reset enters the production byte-level parser.
module tb_suspect_report;
reg clk=0;always #5 clk=~clk;
reg [2:0] input_count=1;reg [255:0] input_boxes=0;reg [7:0] input_kinds=3;
reg [7:0] cnn_conf=3;reg [15:0] cnn_class=5;
string printed[0:2];integer paper_mark_moves=0;
reg frame_reset=0,paper_confirm=0;wire [15:0] rebased_y;
reg rst_n=0,clear=0,stop=0,abort_job=0,rearm=0,job_valid=0,local_test=0,cnn=0,link_ready=1;
reg [31:0] job_id=0; reg [1:0] judgement=1;
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
grbl_reporter_shared_candidate #(.CLK_HZ(1000),.MAZE_ENABLE(0),.AUTO_NEWLINE(1),.KEY2_REZERO(1),.FONT_JOIN_CORNERS(0),.PCB_SUSPECT_ENABLE(1),.PCB_SUSPECT_CENTER_INPUT(1),.PAPER_LOAD_FIRST_ROW_CMM(3000),.PAPER_LOAD_CENTER_Y_CMM(14850),.PAPER_LOAD_LAST_ROW_CMM(26700),.PAPER_LOCAL_Y_LIMIT_CMM(23700)) reporter(
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
  .I_job_source(3'd1),
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
 @(negedge clk);rst_n=0;frame_reset=0;paper_confirm=0;job_valid=0;stop=0;abort_job=0;clear=0;rearm=0;rx_valid=0;link_ready=1;
 tick(4);tx_lines=0;read_line=0;done_events=0;queries=0;holds=0;resets=0;printed[0]="";printed[1]="";printed[2]="";paper_mark_moves=0;rst_n=1;tick(8);
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


task complete_report;integer n;begin
 n=0;while(done_events==0&&n<500000)begin
  if(tx_lines>read_line)ack_line();else tick(1);n++;
 end
 tick(8);if(done_events!=1||error||recovery||busy)fail("no final ACK completion");
 if(queries!=0||paper_mark_moves!=0)fail("unexpected query or paper marker");
 $display("FLOW_TEXT case=%s row0=%s|row1=%s|row2=%s|cursor=%0d",case_name,printed[0],printed[1],printed[2],reporter.newline_offset_cmm);
end endtask
always @(posedge clk)if(rst_n&&reporter.state==62&&reporter.font_pen_down)
 fail("pen stayed down across glyph boundary");
integer c;
initial begin
 for(c=0;c<3;c++)begin
  reset_case();case_name=$sformatf("pcb%0d",c);judgement=c;input_count=0;input_kinds=0;
  start_job(0,0);complete_report();
 end
 for(c=1;c<=9;c++)begin
  reset_case();case_name=$sformatf("cnn%0d",c);cnn_class=c;cnn_conf=(c==1)?0:((c==9)?255:c*10);
  input_count=1;input_boxes={224'd0,16'd360,16'd640};input_kinds=3;
  start_job(0,1);complete_report();
 end
 $display("FONT_FLOW_GCODE_PASS cases=12");$finish;
end
initial begin #1000000000;$fatal(1,"flow watchdog");end
endmodule
