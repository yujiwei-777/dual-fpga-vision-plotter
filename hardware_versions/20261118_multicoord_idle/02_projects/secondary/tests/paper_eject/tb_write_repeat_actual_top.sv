`timescale 1ns/1ps
// Real secondary_top admission/pending/cache/guard logic. Only peripheral
// outputs are controlled; no admission predicate, pending register, cache or
// guard state is forced or deposited.
module tb_write_repeat_actual_top;
parameter EXPECT_STUCK=0;
reg clk=0,rst_n=0,key1_n=1;
always #4 clk=~clk;
reg [1:0] purpose=0,color=1,shape=1;
reg done=0,valid=1;
reg rep_ready=0,rep_busy=0,rep_done=0,rep_recovery=0;
reg explicit_cancel=0;
reg [31:0] result_id=88;
integer errors=0,checks=0,accepts=0,handshakes=0,protected_cycles=0;
integer before_accepts;
secondary_top dut(.I_sys_clk(clk),.I_sw2(1'b0),.I_key1_n(key1_n),
 .I_key2_n(1'b1),.I_key3_n(1'b1),.I_key4_n(1'b1),
 .I_rgmii_rxd(4'd0),.I_rgmii_rx_ctl(1'b0),.I_rgmii_rxc(clk),
 .I_uart_rx(1'b1),.I_esp_link_ready(1'b1));
defparam dut.u_key1_action.DEBOUNCE_CYCLES=2;
defparam dut.u_key1_action.LONG_PRESS_CYCLES=40;
always @(posedge clk)if(rst_n)begin
 if(dut.key1_local_job_accept)accepts<=accepts+1;
 if(dut.report_pending&&dut.key1_job_active)protected_cycles<=protected_cycles+1;
 // Controlled reporter handshake is a peripheral output model. The actual
 // top produces report_job_valid and clears its pending register itself.
 if(dut.report_job_valid&&rep_ready)begin
  handshakes<=handshakes+1;rep_busy<=1;
 end
end
task step;begin @(posedge clk);#1;end endtask
task tick(input integer n);begin repeat(n)step;end endtask
task check(input bit ok,input string message);begin
 checks=checks+1;
 if(!ok)begin errors=errors+1;$display("FAIL ACTUAL_TOP %s",message);end
 else $display("PASS ACTUAL_TOP %s",message);
end endtask
task result(input integer id);begin
 @(negedge clk);result_id=id;done=1;step;
 @(negedge clk);done=0;tick(3);
end endtask
task press_key1;begin
 @(negedge clk);key1_n=0;tick(6);
 @(negedge clk);key1_n=1;tick(8);
end endtask
task finish_job;begin
 @(negedge clk);rep_busy=0;rep_done=1;step;
 @(negedge clk);rep_done=0;tick(4);
end endtask
initial begin
 force dut.clk125=clk;force dut.rst125_n=rst_n;
 force dut.vision_purpose=purpose;force dut.normal_done=done;
 force dut.color_id=color;force dut.shape_id=shape;force dut.confidence=8'd37;
 force dut.x0=11'd120;force dut.x1=11'd300;force dut.y0=10'd40;force dut.y1=10'd180;
 force dut.target_valid=valid;force dut.result_job_id=result_id;
 force dut.grbl_current_start=0;force dut.grbl_current_job_id=32'd42;
 force dut.grbl_test_start=0;force dut.grbl_test_job_id=0;
 force dut.session_id=64'd123;force dut.online=1;
 force dut.vision_cancel=0;force dut.vision_job_cancel=explicit_cancel;
 force dut.vision_start=0;force dut.vision_busy=0;force dut.vision_teach_good=0;
 force dut.maze_done=0;force dut.cfg_apply=0;force dut.job_status_ready=0;
 force dut.copy_busy=0;force dut.copy_recovery=0;force dut.copy_uart_owner=0;
 force dut.copy_write_waiting=0;force dut.copy_draw_admitted=0;
 force dut.copy_operator_job=0;force dut.copy_operator_state=0;force dut.copy_operator_error=0;
 force dut.copy_operator_acked=0;force dut.copy_total_lines=0;force dut.copy_total_valid=0;force dut.copy_airwalk_active=0;
 force dut.report_page_maintenance=0;force dut.report_ready=rep_ready;force dut.report_busy=rep_busy;
 force dut.report_done=rep_done;force dut.report_error=0;
 force dut.report_recovery_required=rep_recovery;force dut.report_state=0;
 force dut.paper_confirm_armed=0;force dut.paper_confirm_active=0;
 force dut.report_total_lines=0;force dut.report_total_valid=0;force dut.report_airwalk_active=0;
 force dut.report_lines=0;force dut.report_error_code=0;
 force dut.uart_link_ready=1;force dut.uart_rt_ready=1;force dut.uart_rt_done=0;force dut.uart_idle_pulse=0;
 force dut.profile_valid=1;force dut.operator_snapshot_take=0;force dut.operator_preview_capable=0;
 force dut.pcb_reason=2;force dut.teach_code=0;
 force dut.page_used_cmm=0;force dut.page_remaining_cmm=23700;force dut.page_generation=0;
 force dut.page_result=0;force dut.page_full=0;
 force dut.pcb_checked=1;force dut.pcb_status=1;force dut.pcb_good=0;
 force dut.defect_count=0;force dut.defect_boxes=0;force dut.defect_kinds=0;
 tick(4);rst_n=1;tick(10);
 check(dut.key1_report_slot_available&&!dut.key1_job_active,"reset releases actual top owner and slot");
 result(88);
 check(dut.cnn_cache_result_valid&&dut.cnn_cache_valid&&dut.key1_can_start,
       "actual top caches peripheral inference and arms physical KEY1");
 press_key1;tick(5);
 check(accepts==1&&protected_cycles>0,"actual physical KEY1 owns pending before timeout");
 check(!dut.report_pending&&dut.job_status_valid&&dut.job_status_data[47:40]==10&&handshakes==0,
       "actual pending timeout reports error10 and never handshakes");
 if(EXPECT_STUCK)begin
  check(dut.key1_job_active&&!dut.key1_report_slot_available,
        "readonly actual top reproduces orphaned KEY1 owner");
  press_key1;tick(4);
  check(accepts==1&&dut.key1_job_active,"readonly next physical KEY1 remains blocked without reset");
  if(errors)$fatal(1,"ACTUAL_TOP_CONTROL_FAIL checks=%0d errors=%0d",checks,errors);
  $display("WRITE_REPEAT_ACTUAL_TOP_CONTROL_PASS checks=%0d",checks);$finish;
 end
 check(!dut.key1_job_active&&dut.key1_report_slot_available,
       "fixed actual timeout releases guard without any register force");
 rep_ready=1;tick(3);press_key1;tick(3);
 check(accepts==2&&handshakes==1&&rep_busy&&dut.key1_job_active&&!dut.report_pending&&dut.report_job==2,
       "next physical KEY1 accepted and handshakes without reset");
 check(dut.report_snapshot_id==88&&dut.report_cnn_class==1&&dut.report_cnn_confidence==37&&
       dut.report_center=={10'd110,11'd210},"second admission retains actual cached snapshot");
 finish_job;
 check(!dut.key1_job_active&&dut.key1_report_slot_available,"normal peripheral done releases actual owner");
 press_key1;tick(3);
 check(accepts==3&&handshakes==2&&dut.key1_job_active&&dut.report_job==3,
       "consecutive physical KEY1 normal task needs no reset");
 finish_job;rep_recovery=1;tick(3);before_accepts=accepts;
 check(!dut.key1_report_slot_available&&!dut.key1_can_start,"real top recovery wire blocks slot and key arming");
 press_key1;tick(3);
 check(accepts==before_accepts&&!dut.report_pending&&!dut.key1_job_active&&handshakes==2,
       "recovery lock prevents motion admission and is not cleared by timeout fix");
 rep_recovery=0;tick(4);press_key1;tick(3);
 check(accepts==4&&handshakes==3&&dut.key1_job_active,"fresh physical press works after controlled peripheral recovery");
 finish_job;
 // PCB uses a one-shot cache. A declined snapshot is not replayed: a new
 // inference must arrive before the subsequent physical press.
 purpose=1;tick(6);rep_ready=0;result(200);press_key1;tick(5);
 check(accepts==5&&!dut.report_pending&&!dut.key1_job_active&&!dut.pcb_report_cache_valid&&
       dut.job_status_data[47:40]==10,"PCB timeout releases owner and consumes only its admitted inference");
 check(!dut.key1_can_start,"PCB refusal cannot replay consumed cached inference");
 rep_ready=1;result(201);press_key1;tick(3);
 check(accepts==6&&handshakes==4&&dut.key1_job_active&&dut.report_job==201&&
       dut.report_snapshot_id==201&&!dut.report_cnn_mode,"new PCB result writes after refusal without board reset");
 finish_job;
 check(!dut.key1_job_active&&!dut.report_pending,"final actual top owner clean");
 if(errors)$fatal(1,"ACTUAL_TOP_FIXED_FAIL checks=%0d errors=%0d",checks,errors);
 $display("WRITE_REPEAT_ACTUAL_TOP_FIXED_PASS checks=%0d",checks);$finish;
end
initial begin #200000;$fatal(1,"actual top timeout");end
endmodule
