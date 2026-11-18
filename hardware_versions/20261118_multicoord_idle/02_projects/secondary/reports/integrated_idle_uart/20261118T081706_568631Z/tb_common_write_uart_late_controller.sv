`timescale 1ns/1ps
module tb_common_write_uart;
reg clk=0,rst_n=0,key1_n=1,key2_n=1;
always #4 clk=~clk;
reg [1:0] purpose=0;
reg infer_done=0;
reg [31:0] result_id=100;
reg serial_rx=1;
integer boot_queries=0,boot_holds=0,boot_resets=0;
bit boot_ready=0;
bit peer_reply=1,peer_receiving=0;
localparam integer BOOT_CASE=2;
integer expected_boot_holds,expected_boot_resets;
localparam integer BIT_TICKS=4;
integer errors=0,checks=0,done_events=0,key1_accepts=0,key2_accepts=0;
integer tx_lines=0,queries=0,last_done=0,case_count=0;
integer before_key2_offset;
string serial_line="";
integer idle_lines, idle_holds, idle_resets, idle_queries, runtime_start_queries;
task malformed;begin
 @(negedge clk);serial_rx=0;repeat(BIT_TICKS*11)@(negedge clk);
 serial_rx=1;repeat(BIT_TICKS*4)@(negedge clk);
end endtask
task await_idle_certificate;integer n;begin
 n=0;while(!dut.u_uart.idle_certified&&n<50000)begin step;n++;end
 check(dut.u_uart.idle_certified,"fresh idle monitor certifies quiescent actual top path");
end endtask
task idle_fault_then_recover(input string label);integer n;begin
 await_idle_certificate;
 peer_reply=0;
 while(peer_receiving)step;
 tick(100);
 idle_lines=tx_lines;idle_holds=boot_holds;idle_resets=boot_resets;
 malformed;tick(3);
 check(!dut.uart_link_ready,{label," framing fault fences command bytes"});
 tick(12000);
 check(!dut.uart_link_ready,{label," silence never clears fault"});
 check(!dut.report_recovery_required&&!dut.copy_recovery&&!dut.u_plot_transport.owner_valid,
  {label," idle receive-only fault creates no task/recovery owner lock"});
 check(tx_lines==idle_lines&&boot_holds==idle_holds&&boot_resets==idle_resets,
  {label," sends no motion, hold or reset while requalifying"});
 peer_reply=1;n=0;
 while(!dut.uart_link_ready&&n<50000)begin step;n++;end
 check(dut.uart_link_ready,{label," recovers from fresh serial Idle without KEY3 or KEY4"});
 check(tx_lines==idle_lines&&boot_holds==idle_holds&&boot_resets==idle_resets,
  {label," recovery does not replay G-code or reset controller"});
end endtask
secondary_top dut(.I_sys_clk(clk),.I_sw2(1'b0),.I_key1_n(key1_n),
 .I_key2_n(key2_n),.I_key3_n(1'b1),.I_key4_n(1'b1),
 .I_rgmii_rxd(4'd0),.I_rgmii_rx_ctl(1'b0),.I_rgmii_rxc(clk),
 .I_uart_rx(serial_rx),.I_esp_link_ready(1'b1));
defparam dut.u_key1_action.DEBOUNCE_CYCLES=2;
defparam dut.u_key1_action.LONG_PRESS_CYCLES=40;
defparam dut.u_key2_test.DEBOUNCE_CYCLES=2;
defparam dut.u_key2_test.LONG_PRESS_CYCLES=40;

defparam dut.u_uart.CLK_HZ=4000;
defparam dut.u_uart.BAUD=1000;
defparam dut.u_uart.PROBE_INTERVAL_CYCLES=1000;
defparam dut.u_uart.IDLE_POLL_INTERVAL_CYCLES=2000;
always @(posedge clk)if(rst_n)begin
 if(dut.report_done)done_events<=done_events+1;
 if(dut.key1_local_job_accept)key1_accepts<=key1_accepts+1;
 if(dut.key2_report_accept)key2_accepts<=key2_accepts+1;
end
task send_byte(input reg [7:0] value);begin
 @(negedge clk);serial_rx=0;repeat(BIT_TICKS)@(negedge clk);
 for(integer j=0;j<8;j++)begin serial_rx=value[j];repeat(BIT_TICKS)@(negedge clk);end
 serial_rx=1;repeat(BIT_TICKS)@(negedge clk);
end endtask
task receive(input string message);begin
 peer_receiving=1;repeat(5)@(negedge clk);
 for(integer k=0;k<message.len();k++)send_byte(message[k]);
 peer_receiving=0;
end endtask
reg [7:0] incoming;
initial begin
 forever begin
  @(negedge dut.O_uart_tx);
  repeat(BIT_TICKS+BIT_TICKS/2)@(negedge clk);
  for(integer i=0;i<8;i++)begin
   incoming[i]=dut.O_uart_tx;repeat(BIT_TICKS)@(negedge clk);
  end
  if(dut.O_uart_tx!==1)$fatal(1,"controller sees missing UART stop bit");
  if(incoming=="?")begin
   if(boot_ready)queries++;
   else boot_queries++;
   if(peer_reply)receive("<Idle|MPos:0,0,0>\n");
  end else if(incoming=="!")begin boot_holds++;end
  else if(incoming==8'h18)begin boot_resets++;end
  else if(incoming==10)begin tx_lines++;serial_line="";receive("ok\n");end
  else serial_line={serial_line,string'(incoming)};
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
 n=0;while(done_events==last_done&&!dut.report_error&&n<5000000)begin step;n++;end
 tick(15);case_count++;
 check(done_events==last_done+1,{name," exactly one final ACK completion"});
 check(!dut.report_busy&&!dut.report_pending&&!dut.key1_job_active&&!dut.key2_local_active&&
  !dut.key2_report_pending&&!dut.report_recovery_required&&!dut.report_error,
  {name," clears all top/report/KEY1/KEY2 task locks"});
 check(!dut.u_plot_transport.owner_valid&&dut.u_plot_transport.state==0,
  {name," releases quiescent shared UART owner"});
 check(boot_holds==expected_boot_holds&&boot_resets==expected_boot_resets,
  {name," does not hold/reset after normal completion"});
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
 tick(4);if(BOOT_CASE==2)peer_reply=0;rst_n=1;
 if(BOOT_CASE==1)malformed;
 if(BOOT_CASE==2)begin
  tick(18000);check(!dut.uart_link_ready&&tx_lines==0,
   "late controller remains fenced during initial silence");peer_reply=1;
 end
 begin integer n;n=0;while(!dut.uart_link_ready&&n<100000)begin step;n++;end
 check(dut.uart_link_ready&&boot_holds>=1&&boot_resets==1&&boot_queries>=2&&
  (BOOT_CASE!=0||(boot_holds==1&&boot_queries==2)),
  "actual UART boot guard establishes hold-reset-fresh-Idle session");
 end
 boot_ready=1;tick(15);result(100);
 expected_boot_holds=boot_holds;expected_boot_resets=boot_resets;
 check(!dut.report_recovery_required&&!dut.copy_recovery,
  "initial safe retries do not leak recovery locks into task owners");
 await_idle_certificate;
 idle_lines=tx_lines;idle_queries=queries;
 tick(160000);
 check(dut.uart_link_ready&&queries>idle_queries+20&&tx_lines==idle_lines,
  "long idle keeps actual top path ready with only read-only status probes");
 idle_fault_then_recover("before first write");
 check(dut.key1_can_start,"CNN result arms KEY1 before first report");
 press1;complete("CNN first");
 check(dut.key1_can_start,"CNN cached current result re-arms KEY1 after done");
 idle_fault_then_recover("between CNN jobs");
 press1;complete("CNN second");
 check(key1_accepts==2,"two CNN KEY1 jobs accepted without reset");
 purpose=1;tick(6);result(200);press1;complete("PCB first");
 check(!dut.key1_can_start&&!dut.pcb_report_cache_valid,"PCB consumes one inference without replay");
 result(201);press1;complete("PCB second");
 check(key1_accepts==4,"new PCB result re-arms second KEY1 without reset");
 idle_fault_then_recover("before KEY2");
 for(integer j=0;j<12;j++)begin
  press2;complete($sformatf("KEY2 sequence %0d",j));
  check(dut.report_rebased_y_cmm==0&&dut.page_used_cmm==0&&dut.page_remaining_cmm==0&&!dut.page_full,
    "paper budget stays absent after KEY2 G92");
 end
 check(key2_accepts==12,"twelve consecutive physical KEY2 jobs admitted without reset");
 if(errors)$fatal(1,"INTEGRATED_IDLE_UART_FAIL cases=%0d checks=%0d errors=%0d",case_count,checks,errors);
 $display("INTEGRATED_IDLE_UART_PASS cases=%0d checks=%0d lines=%0d key1=%0d key2=%0d",case_count,checks,tx_lines,key1_accepts,key2_accepts);$finish;
end
initial begin #200000000;$fatal(1,"common chain timeout");end
endmodule
