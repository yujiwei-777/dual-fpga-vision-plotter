`timescale 1ns/1ps
// Actual current top KEY1 synchronizer/admission + actual document controller.
// Image/planner/plotter/peripheral leaves are controlled boundary stimuli;
// full arithmetic/DDR/UART integration belongs to the separate integrated suite.
module tb_operator_document;
reg clk=0;always #5 clk=~clk;
reg rst_n=0,key1_n=1,start=0,cancel_job=0,key4=0,net_cancel=0,online=1;
reg [1:0] purpose=2;
reg image_done=0,prepared=0,plan_error=0,plot_busy=0,plot_done=0,blocked=0;
reg status_ready=1;reg [31:0] old_acks=0;reg [15:0] occupied=0;integer reserve_events=0;
integer emits=0,plots=0,confirms=0,checks=0,scenarios=0,status7=0;
string scenario="initial";
secondary_top dut(.I_sys_clk(clk),.I_sw2(1'b0),.I_key1_n(key1_n),.I_key2_n(1'b1),.I_key3_n(1'b1),.I_key4_n(1'b1),.I_rgmii_rxd(4'd0),.I_rgmii_rx_ctl(1'b0),.I_rgmii_rxc(clk),.I_uart_rx(1'b1),.I_esp_link_ready(1'b1),.O_rgmii_txd(),.O_rgmii_tx_ctl(),.O_rgmii_txc(),.O_phy_rst(),.O_uart_tx(),.ddr_addr(),.ddr_ba(),.ddr_cke(),.ddr_odt(),.ddr_cs_n(),.ddr_ck_p(),.ddr_ck_n(),.ddr_ras_n(),.ddr_cas_n(),.ddr_we_n(),.ddr_dm(),.ddr_dqs_p(),.ddr_dqs_n(),.ddr_dq(),.O_led());
defparam dut.u_key1_action.DEBOUNCE_CYCLES=2;
defparam dut.u_key1_action.LONG_PRESS_CYCLES=40;
// One simulation cycle = one controller millisecond. The 30,000 ms boundary
// is unchanged; only the production controller timebase is accelerated.
defparam dut.u_copy.CLK_HZ=1000;
always @(posedge clk)if(rst_n)begin
 if(dut.u_copy.emit_start)emits++;
 if(dut.u_copy.plot_start)plots++;
 if(dut.copy_draw_admitted)reserve_events++;
 if(dut.copy_write_start)confirms++;
 if(dut.copy_status_valid&&status_ready&&dut.copy_status_data[39:32]==7)begin
  status7++;
  if(dut.copy_status_data[47:40]!==0||dut.copy_status_data[95:64]!==0)$fatal(1,"WAIT status error/lines not zero");
 end
end
task tick(input integer n);begin repeat(n)@(negedge clk);end endtask
task check(input bit ok,input string why);begin checks++;if(!ok)begin
 $display("DOC_FRESH_KEY1_FAIL scenario=%s state=%0d prepared=%0d key_sync=%b%b%b arm=%b pend=%b elig=%b long=%b can=%b wait=%b short=%b start=%b lock=%0d emit=%0d plots=%0d %s",scenario,dut.u_copy.state,prepared,dut.u_key1_action.key_sync,dut.u_key1_action.key_sample,dut.u_key1_action.key_debounced,dut.u_key1_action.armed,dut.u_key1_action.press_pending,dut.u_key1_action.eligible,dut.u_key1_action.long_sent,dut.key1_can_start,dut.copy_write_waiting,dut.key1_short_pulse,dut.copy_write_start,dut.key1_lock,emits,plots,why);$fatal(1,"fresh KEY1 boundary failure");end end endtask
task pass;begin scenarios++;$display("DOC_FRESH_KEY1_CASE_PASS %s",scenario);end endtask
task reset_case;begin
 @(negedge clk);rst_n=0;key1_n=1;start=0;cancel_job=0;key4=0;net_cancel=0;online=1;purpose=2;
 image_done=0;prepared=0;plan_error=0;plot_busy=0;plot_done=0;blocked=0;status_ready=1;old_acks=0;
 tick(4);emits=0;plots=0;confirms=0;status7=0;occupied=0;reserve_events=0;rst_n=1;tick(4);dut.key1_lock=0;
end endtask
task start_plan;begin
 start=1;tick(1);start=0;tick(2);check(dut.u_copy.state==1,"document IMAGE not entered");
 image_done=1;tick(1);image_done=0;tick(1);check(dut.u_copy.state==2,"document PLAN not entered");
end endtask
task enter_wait;integer e0,p0;begin e0=emits;p0=plots;prepared=1;tick(1);prepared=0;tick(2);
 check(dut.copy_write_waiting&&dut.copy_busy&&!dut.copy_uart_owner,"WAIT keeps job, no UART owner");
 check(emits==e0&&plots==p0,"WAIT started motion without KEY1");end endtask
task release_key;begin key1_n=1;tick(5);dut.key1_lock=0;end endtask
// A short KEY1 action is intentionally emitted on release so the same
// physical press can be distinguished from the long paper-load confirmation.
task fresh_press;begin key1_n=0;tick(5);key1_n=1;tick(5);end endtask
task complete_draw;begin plot_busy=1;tick(3);plot_busy=0;plot_done=1;tick(1);plot_done=0;tick(3);check(!dut.copy_busy,"document did not complete");end endtask
initial begin
 force dut.clk125=clk;force dut.rst125_n=rst_n;
 force dut.vision_start=start;force dut.vision_purpose=purpose;force dut.vision_job_id=32'd701;
 force dut.vision_cancel=net_cancel;force dut.vision_job_cancel=cancel_job;force dut.online=online;
 // The packet-link leaf is controlled in this admission-only bench. Its new
 // explicit preparation-discard output must be inactive, never floating Z.
 // Actual Type11 packet/discard races are tested in the paired reentry suite.
 force dut.copy_prepare_cancel=0;
 force dut.page_used_cmm=occupied;force dut.page_remaining_cmm=23700-occupied;
 force dut.page_full=0;force dut.page_result=0;force dut.page_generation=0;
 force dut.operator_preview_capable=0;force dut.operator_snapshot_take=0;
 force dut.key4_press=key4;force dut.key4_stop=0;force dut.key4_reset_active=0;
 force dut.normal_busy=0;force dut.normal_done=0;force dut.pcb_frame_lock=0;
 force dut.report_page_maintenance=1'b0;force dut.report_busy=0;force dut.report_ready=0;force dut.report_error=0;force dut.report_recovery_required=blocked;
 force dut.key2_local_active=0;force dut.key2_new_page=0;force dut.key1_job_active=0;
 force dut.copy_recovery=0;force dut.copy_uart_owner=0;force dut.paper_confirm_armed=0;force dut.paper_confirm_active=0;
 force dut.vision_busy=0;
 force dut.uart_link_ready=1;force dut.profile_valid=1;force dut.cfg_apply=0;force dut.grbl_current_start=0;force dut.grbl_test_start=0;
 force dut.copy_status_ready=status_ready;
 force dut.u_copy.S_available=1;force dut.u_copy.image_done=image_done;force dut.u_copy.image_error=0;
 force dut.u_copy.plan_prepared=prepared;force dut.u_copy.plan_error=plan_error;force dut.u_copy.plan_error_code=8'h48;
 force dut.u_copy.plan_done=0;force dut.u_copy.plan_busy=0;
 force dut.u_copy.plot_busy=plot_busy;force dut.u_copy.plot_done=plot_done;force dut.u_copy.plot_error=0;force dut.u_copy.plot_cancelled=0;force dut.u_copy.plot_state=0;force dut.u_copy.recovery_required=0;force dut.u_copy.acked_lines=old_acks;
 scenario="early_planning_press_discarded_held_then_fresh";reset_case();start_plan();fresh_press();
 check(confirms==0,"press during PLAN became confirm");enter_wait();tick(30010);
 check(dut.copy_write_waiting&&emits==0&&plots==0,"held earlier KEY1 or 30s wait started/aborted job");
 check(status7>=100&&dut.u_copy.prep_ms<30000,"WAIT status heartbeat/prepare timeout broken");
 release_key();fresh_press();tick(3);check(emits==1&&plots==1&&confirms==1,"fresh WAIT KEY1 did not launch exactly once");
 tick(30);check(emits==1&&plots==1,"held KEY1 retriggered DRAW");complete_draw();pass();
 scenario="prepared_same_edge_as_KEY1_not_deferred";reset_case();start_plan();
 key1_n=0;tick(5);check(dut.key1_fresh_press,"same-edge stimulus failed");prepared=1;
 tick(1);prepared=0;tick(4);
 check(dut.copy_write_waiting&&emits==0&&plots==0&&confirms==0,"PLAN completion edge queued KEY1 into WAIT");
 release_key();fresh_press();tick(2);check(emits==1&&plots==1,"fresh next press not accepted");pass();
 scenario="WAIT_key_bounce_lock_no_duplicate";reset_case();start_plan();enter_wait();fresh_press();tick(3);
 key1_n=1;tick(5);key1_n=0;tick(5);check(emits==1&&plots==1&&confirms==1,"bounce duplicated start");pass();
 scenario="cancel_same_edge_as_confirm_wins";reset_case();start_plan();enter_wait();key1_n=0;tick(2);cancel_job=1;tick(1);cancel_job=0;tick(4);
 check(!dut.copy_busy&&emits==0&&plots==0&&confirms==0,"explicit cancel lost to KEY1");pass();
 scenario="KEY4_same_edge_as_confirm_wins";reset_case();start_plan();enter_wait();key1_n=0;tick(2);key4=1;tick(1);key4=0;tick(4);
 check(!dut.copy_busy&&emits==0&&plots==0&&confirms==0,"KEY4 lost to KEY1");pass();
 scenario="ethernet_cancel_during_WAIT_retains_plan";reset_case();start_plan();enter_wait();online=0;net_cancel=1;tick(10);
 check(dut.copy_write_waiting&&emits==0&&plots==0,"ordinary network cancel terminated accepted prepared task");
 fresh_press();tick(3);check(emits==1&&plots==1,"offline fresh KEY1 unable to confirm accepted plan");pass();
 scenario="admission_fault_and_plan_error_cannot_draw";reset_case();start_plan();enter_wait();blocked=1;tick(3);
 check(!dut.copy_busy&&emits==0&&plots==0&&dut.u_copy.public_state==5&&dut.u_copy.public_error==8'h61,"WAIT shared recovery lock did not reject");
 reset_case();start_plan();enter_wait();plan_error=1;tick(3);
 check(!dut.copy_busy&&emits==0&&plots==0&&dut.u_copy.public_state==5&&dut.u_copy.public_error==8'h48,"WAIT plan error did not reject");pass();
 scenario="no_old_held_key_carries_to_next_task";reset_case();start_plan();enter_wait();fresh_press();tick(3);complete_draw();
 old_acks=17;start_plan();enter_wait();tick(300);check(emits==1&&plots==1&&confirms==1,"held key confirmed second task");
 release_key();fresh_press();tick(2);check(emits==2&&plots==2&&confirms==2,"new press did not confirm second task");pass();
 scenario="DRAW_done_same_edge_KEY1_cannot_spill_into_CNN";reset_case();start_plan();enter_wait();fresh_press();tick(3);plot_busy=1;release_key();
 key1_n=0;tick(5);check(dut.key1_fresh_press,"DRAW done same-edge stimulus failed");plot_busy=0;plot_done=1;tick(1);plot_done=0;purpose=0;tick(2);
 check(!dut.key1_report_pulse&&!dut.report_pending&&emits==1&&plots==1,"document busy edge escaped as delayed CNN request");pass();
 scenario="ordinary_CNN_KEY1_cache_write_preserved";reset_case();purpose=0;
 force dut.cnn_cache_invalid=0;force dut.cnn_cache_result_valid=1;force dut.cnn_cache_valid=1;force dut.cnn_cache_class=16'd5;force dut.cnn_cache_confidence=8'd7;force dut.cnn_cache_center_x=11'd123;force dut.cnn_cache_center_y=10'd234;
 fresh_press();tick(1);
 check(dut.report_pending&&dut.report_cnn_mode&&dut.report_cnn_class==5&&dut.report_cnn_confidence==7,"ordinary CNN cached KEY1 report blocked/changed");
 check(!dut.copy_busy&&emits==0&&plots==0,"CNN KEY1 started document pipeline");pass();
 scenario="PCB_KEY1_cache_write_preserved";reset_case();purpose=1;
 force dut.pcb_report_cache_invalid=0;force dut.pcb_report_result=0;force dut.pcb_report_cache_valid=1;force dut.pcb_report_cache_job=32'd88;force dut.pcb_report_cache_judgement=2'd1;force dut.pcb_report_cache_defect_count=0;force dut.pcb_report_cache_boxes=0;force dut.pcb_report_cache_kinds=0;
 fresh_press();tick(1);
 check(dut.report_pending&&!dut.report_cnn_mode&&dut.report_job==88&&dut.report_judgement==1,"PCB cached KEY1 report blocked/changed");
 check(!dut.copy_busy&&emits==0&&plots==0,"PCB KEY1 started document pipeline");pass();

 release dut.cnn_cache_invalid;release dut.cnn_cache_result_valid;release dut.cnn_cache_valid;release dut.cnn_cache_class;
 release dut.cnn_cache_confidence;release dut.cnn_cache_center_x;release dut.cnn_cache_center_y;
 release dut.pcb_report_cache_invalid;release dut.pcb_report_result;release dut.pcb_report_cache_valid;
 release dut.pcb_report_cache_job;release dut.pcb_report_cache_judgement;release dut.pcb_report_cache_defect_count;
 release dut.pcb_report_cache_boxes;release dut.pcb_report_cache_kinds;
 scenario="prior_report_does_not_block_document_KEY1";reset_case();occupied=3500;start_plan();enter_wait();
 check(dut.operator_status_data[55:48]==3&&dut.operator_status_data[63:56]==1&&dut.operator_status_data[40]&&
       !dut.operator_status_data[42]&&dut.operator_status_data[47],"document preview must be ready despite prior report");
 check(dut.operator_status_data[255:224]==0,"paper used/remaining metadata must be zero");
 fresh_press();tick(3);check(emits==1&&plots==1&&confirms==1&&reserve_events==1,
       "prior report cannot block fixed-coordinate document KEY1");pass();
 $display("OPERATOR_DOCUMENT_PASS cases=%0d checks=%0d",scenarios,checks);$finish;
end
initial begin #100000000;$fatal(1,"fresh KEY1 global timeout");end
endmodule
