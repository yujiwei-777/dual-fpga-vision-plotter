`timescale 1ns/1ps
module tb_common_write_completion;
reg clk=0,rst_n=0,key1_n=1,key2_n=1;
always #4 clk=~clk;
reg [1:0] purpose=0;
reg infer_done=0;
reg [31:0] result_id=100;
reg uart_busy=0,tx_done=0,rx_valid=0;
reg [7:0] rx_data=0;
wire tx_ready=!uart_busy;
integer byte_age=0,rx_wait=0,rx_index=0;
integer errors=0,checks=0,done_events=0,key1_accepts=0,key2_accepts=0;
integer tx_lines=0,queries=0,last_done=0,case_count=0;
integer before_key2_offset;
integer xy_feed_checks=0,z_feed_checks=0,travel_feed_checks=0;
string serial_line="";
secondary_top dut(.I_sys_clk(clk),.I_sw2(1'b0),.I_key1_n(key1_n),
 .I_key2_n(key2_n),.I_key3_n(1'b1),.I_key4_n(1'b1),
 .I_rgmii_rxd(4'd0),.I_rgmii_rx_ctl(1'b0),.I_rgmii_rxc(clk),
 .I_uart_rx(1'b1),.I_esp_link_ready(1'b1));
defparam dut.u_key1_action.DEBOUNCE_CYCLES=2;
defparam dut.u_key1_action.LONG_PRESS_CYCLES=40;
defparam dut.u_key2_test.DEBOUNCE_CYCLES=2;
defparam dut.u_key2_test.LONG_PRESS_CYCLES=40;

always @(posedge clk)begin
 tx_done<=0;rx_valid<=0;
 if(!rst_n)begin uart_busy<=0;byte_age<=0;rx_wait<=0;rx_index<=0;end
 else begin
  if(dut.report_done)done_events<=done_events+1;
  if(dut.key1_local_job_accept)key1_accepts<=key1_accepts+1;
  if(dut.key2_report_accept)key2_accepts<=key2_accepts+1;
  if(uart_busy)begin
   if(byte_age==0)begin uart_busy<=0;tx_done<=1;end
   else byte_age<=byte_age-1;
  end else if(dut.ps_rt_valid&&tx_ready)begin
   uart_busy<=1;byte_age<=2;queries<=queries+1;
   $display("UNEXPECTED_RT byte=%h",dut.ps_rt_data);
  end else if(dut.ps_tx_valid&&tx_ready)begin
   uart_busy<=1;byte_age<=2;
   if(dut.ps_tx_data==10)begin
    if(serial_line.substr(0,3)=="G1 X")begin
     if(serial_line.substr(serial_line.len()-6,serial_line.len()-1)!="F05000")$fatal(1,"production XY feed not5000: %s",serial_line);
     xy_feed_checks++;
    end
    if(serial_line.substr(0,3)=="G1 Z")begin
     if(serial_line.substr(serial_line.len()-6,serial_line.len()-1)!="F01200")$fatal(1,"production Z feed changed: %s",serial_line);
     z_feed_checks++;
    end
    if(serial_line.substr(0,3)=="G0 X")begin
     if(serial_line.substr(serial_line.len()-6,serial_line.len()-1)!="F07000")$fatal(1,"production travel feed changed: %s",serial_line);
     travel_feed_checks++;
    end
    tx_lines<=tx_lines+1;rx_wait<=12;rx_index<=1;
    serial_line="";
   end else serial_line={serial_line,string'(dut.ps_tx_data)};
  end
  if(rx_index!=0)begin
   if(rx_wait!=0)rx_wait<=rx_wait-1;
   else begin
    rx_valid<=1;rx_wait<=2;
    case(rx_index)
     1:begin rx_data<="o";rx_index<=2;end
     2:begin rx_data<="k";rx_index<=3;end
     3:begin rx_data<=10;rx_index<=0;end
    endcase
   end
  end
 end
end
task step;begin @(posedge clk);#1;end endtask
task tick(input integer n);begin repeat(n)step;end endtask
task check(input bit ok,input string message);begin
 checks++;
 if(!ok)begin
  errors++;$display("FAIL CHAIN %s top_pending=%b guard=%b rbusy=%b ready=%b rerr=%b code=%d rec=%b kt=%d ts=%d owner=%b/%b page=%d",
   message,dut.report_pending,dut.key1_job_active,dut.report_busy,dut.report_ready,
   dut.report_error,dut.report_error_code,dut.report_recovery_required,
   dut.u_key2_test.state,dut.u_plot_transport.state,dut.u_plot_transport.owner_valid,
   dut.u_plot_transport.owner_doc,dut.page_used_cmm);
 end else $display("PASS CHAIN %s",message);
end endtask
task result(input integer id);begin
 @(negedge clk);result_id=id;infer_done=1;step;
 @(negedge clk);infer_done=0;tick(5);
end endtask
task press1;begin
 @(negedge clk);key1_n=0;tick(6);
 @(negedge clk);key1_n=1;tick(8);
end endtask
task press2;begin
 @(negedge clk);key2_n=0;tick(6);
 @(negedge clk);key2_n=1;tick(8);
end endtask
task complete(input string name);integer n;begin
 n=0;while(done_events==last_done&&!dut.report_error&&n<500000)begin step;n++;end
 tick(15);case_count++;
 check(done_events==last_done+1,{name," exactly one final ACK completion"});
 check(!dut.report_busy&&!dut.report_pending&&!dut.key1_job_active&&!dut.key2_local_active&&
  !dut.key2_report_pending&&!dut.report_recovery_required&&!dut.report_error,
  {name," clears all top/report/KEY1/KEY2 task locks"});
 check(!dut.u_plot_transport.owner_valid&&dut.u_plot_transport.state==0,
  {name," releases quiescent shared UART owner"});
 check(queries==0,{name," issues no normal-completion status/stop/reset"});
 last_done=done_events;
end endtask
initial begin
 force dut.clk125=clk;force dut.rst125_n=rst_n;
 force dut.vision_purpose=purpose;force dut.normal_done=infer_done;
 force dut.color_id=1;force dut.shape_id=1;force dut.confidence=8'd37;
 force dut.x0=11'd120;force dut.x1=11'd300;force dut.y0=10'd40;force dut.y1=10'd180;
 force dut.target_valid=1;force dut.result_job_id=result_id;
 force dut.grbl_current_start=0;force dut.grbl_current_job_id=32'd42;
 force dut.grbl_test_start=0;force dut.grbl_test_job_id=0;
 force dut.session_id=64'd123;force dut.online=1;
 force dut.vision_cancel=0;force dut.vision_job_cancel=0;
 force dut.vision_start=0;force dut.vision_busy=0;force dut.vision_teach_good=0;
 force dut.maze_done=0;force dut.cfg_apply=0;force dut.job_status_ready=1;
 force dut.copy_busy=0;force dut.copy_recovery=0;force dut.copy_uart_owner=0;
 force dut.copy_write_waiting=0;force dut.copy_draw_admitted=0;
 force dut.copy_operator_job=0;force dut.copy_operator_state=0;force dut.copy_operator_error=0;
 force dut.copy_operator_acked=0;force dut.copy_total_lines=0;force dut.copy_total_valid=0;force dut.copy_airwalk_active=0;
 force dut.ps_d_S_start=0;force dut.ps_d_S_clear=0;force dut.ps_d_S_abort=0;
 force dut.ps_d_S_stop=0;force dut.ps_d_S_rearm=0;force dut.ps_d_S_cancel=0;
 force dut.ps_d_S_fault=0;force dut.ps_d_S_reset_job=0;force dut.ps_d_S_finish=0;
 force dut.ps_d_S_line_valid=0;force dut.ps_d_X_start=0;
 force dut.operator_snapshot_take=0;force dut.operator_preview_capable=0;
 force dut.pcb_reason=2;force dut.teach_code=0;
 force dut.pcb_checked=1;force dut.pcb_status=1;force dut.pcb_good=0;
 force dut.defect_count=0;force dut.defect_boxes=0;force dut.defect_kinds=0;
 force dut.uart_link_ready=1;force dut.uart_tx_ready=tx_ready;force dut.uart_tx_done=tx_done;
 force dut.uart_rt_ready=tx_ready;force dut.uart_rt_done=0;force dut.uart_idle_pulse=0;
 force dut.uart_rx_valid=rx_valid;force dut.uart_rx_data=rx_data;force dut.uart_rx_error=0;
 tick(4);rst_n=1;tick(15);result(100);
 check(dut.key1_can_start,"CNN result arms KEY1 before first report");
 press1;complete("CNN first");
 check(dut.key1_can_start,"CNN cached current result re-arms KEY1 after done");
 press1;complete("CNN second");
 check(key1_accepts==2,"two CNN KEY1 jobs accepted without reset");
 purpose=1;tick(6);result(200);press1;complete("PCB first");
 check(!dut.key1_can_start&&!dut.pcb_report_cache_valid,"PCB consumes one inference without replay");
 result(201);press1;complete("PCB second");
 check(key1_accepts==4,"new PCB result re-arms second KEY1 without reset");
 press2;complete("KEY2 first");before_key2_offset=dut.report_rebased_y_cmm;
 press2;complete("KEY2 second");
 check(key2_accepts==2,"consecutive physical KEY2 jobs admitted without reset");
 check(dut.report_rebased_y_cmm==0,
  "second KEY2 preserves accumulated paper use and advances 35mm from local Y10");
 check(xy_feed_checks>0&&z_feed_checks>0&&travel_feed_checks>0,"production CNN PCB KEY2 F5000 XY, F1200 Z and F7000 travel checked");
 $display("PRODUCTION_REPORT_FEED_PASS xy=%0d z=%0d travel=%0d",xy_feed_checks,z_feed_checks,travel_feed_checks);
 if(errors)$fatal(1,"COMMON_WRITE_COMPLETION_FAIL cases=%0d checks=%0d errors=%0d",case_count,checks,errors);
 $display("COMMON_WRITE_COMPLETION_PASS cases=%0d checks=%0d lines=%0d key1=%0d key2=%0d",case_count,checks,tx_lines,key1_accepts,key2_accepts);$finish;
end
initial begin #20000000;$fatal(1,"common chain timeout");end
endmodule
