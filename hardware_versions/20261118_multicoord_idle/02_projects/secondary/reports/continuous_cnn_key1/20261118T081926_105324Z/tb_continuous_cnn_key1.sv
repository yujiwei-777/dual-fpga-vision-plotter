`timescale 1ns/1ps
module tb_continuous_cnn_key1;
reg clk=0, rst_n=0, key1_n=1;
always #4 clk=~clk;
reg [1:0] purpose=0, color=0, shape=0;
reg done=0, valid=0, current=0;

reg take=0,new_job=0,explicit_cancel=0,capable=1,vision_running=0,recovery=0;
integer accepts=0,timeout_count=0;
localparam FIXED=1;
always @(posedge clk) if(!rst_n)accepts<=0; else if(dut.key1_local_job_accept)accepts<=accepts+1;

reg [31:0] result_id=88;
reg [2:0] source_count=0,pcb_status_now=1;
reg [255:0] source_boxes=0;reg[7:0]source_kinds=0,reason=0;reg[15:0]detail=0;
reg pcb_checked_now=1,pcb_good_now=0;
reg [15:0] page_used=0,page_remaining=23700;
reg [7:0] conf=0;
reg [10:0] bx0=0,bx1=0;
reg [9:0] by0=0,by1=0;
reg rep_busy=0,rep_done=0,rep_ready=1;
reg [31:0] remote_job=32'd42;
integer baseline_checks=0;
reg network_online=1,cancel_frame=0,config_apply=0,task_reset=0;
reg [63:0] session=64'd123;
integer errors=0,checks=0;
reg [31:0] previous_local_id;
secondary_top dut(.I_sys_clk(clk),.I_sw2(1'b0),.I_key1_n(key1_n),
    .I_key2_n(1'b1),.I_key3_n(1'b1),.I_key4_n(1'b1),
    .I_rgmii_rxd(4'd0),.I_rgmii_rx_ctl(1'b0),.I_rgmii_rxc(clk),
    .I_uart_rx(1'b1),.I_esp_link_ready(1'b1));
defparam dut.u_key1_action.DEBOUNCE_CYCLES=2;
defparam dut.u_key1_action.LONG_PRESS_CYCLES=40;
task step; begin @(posedge clk); #1; end endtask
task check(input bit ok,input string message);begin
    checks=checks+1;
    if(!ok)begin errors=errors+1;$display("FAIL %s",message);end
    else $display("PASS %s",message);
end endtask
task result(input [1:0] c,s,input [7:0] confidence,input [10:0] x0,x1,
            input [9:0] y0,y1,input bit target);begin
    @(negedge clk);color=c;shape=s;conf=confidence;bx0=x0;bx1=x1;by0=y0;by1=y1;valid=target;done=1;
    step;@(negedge clk);done=0;
end endtask
task press_key1;begin
    $display("KEY1_BEGIN purpose=%d can=%b armed=%b preview=%b slot=%b",purpose,dut.key1_can_start,dut.u_key1_action.armed,dut.preview_locked,dut.key1_report_slot_available);
    @(negedge clk);key1_n=0;
    repeat(6)step;
    $display("KEY1_HELD eligible=%b ctx=%d pending=%b can=%b long=%b",dut.u_key1_action.eligible,dut.u_key1_action.context_q,dut.u_key1_action.press_pending,dut.key1_can_start,dut.u_key1_action.long_sent);
    @(negedge clk);key1_n=1;
    repeat(8)step;
end endtask
task retire;begin
    @(negedge clk);rep_busy=0;rep_done=1;step;
    @(negedge clk);rep_done=0;
    repeat(3)step;
    // Avoid a 20 ms simulation delay between independent physical presses.
    // Debounce has already been exercised through the actual synchronizer.
    dut.key1_lock=0;
end endtask
task history_quiet;begin
    // History invalidation is registered. Drain the current reason and its
    // cache-clear cycle before publishing a fresh result.
    repeat(5)step;
    check(dut.cnn_history_clear===0,"history clear deasserts with stable ordinary session");
end endtask
task check_empty(input string reason);begin
    check(dut.cnn_cache_valid===0 && dut.cnn_cache_class==0 && dut.cnn_cache_confidence==0 &&
          dut.cnn_cache_box==256'd0 && dut.cnn_cache_center_x==0 && dut.cnn_cache_center_y==0,
          reason);
end endtask
task seed;begin
 rst_n=0;key1_n=1;new_job=0;vision_running=0;take=0;done=0;purpose=0;
 network_online=1;explicit_cancel=0;config_apply=0;task_reset=0;recovery=0;
 session=123;capable=1;rep_busy=0;rep_done=0;valid=0;
 repeat(4)step;rst_n=1;history_quiet;
 result(1,1,88,120,300,40,180,1);step;take=1;step;take=0;
 repeat(5)step;check(dut.preview_locked&&dut.key1_can_start,"seeded locked CNN result can start");
end endtask
task down;begin @(negedge clk);key1_n=0;repeat(6)step;end endtask
task up;begin @(negedge clk);key1_n=1;repeat(8)step;end endtask
task expect_snapshot;begin
 check(dut.report_cnn_mode&&dut.report_cnn_class==1&&dut.report_cnn_confidence==88&&
 dut.report_center_valid&&dut.report_center=={10'd110,11'd210},"accepted CNN snapshot contains original name confidence centre");
end endtask
task release_to_pulse;begin
 @(negedge clk);key1_n=1;timeout_count=0;
 while(!dut.key1_short_pulse&&timeout_count<20)begin step;timeout_count=timeout_count+1;end
 check(dut.key1_short_pulse,"physical release generated one short pulse");
end endtask

initial begin
    force dut.clk125=clk;force dut.rst125_n=rst_n;
    force dut.vision_purpose=purpose;force dut.normal_done=done;
    force dut.color_id=color;force dut.shape_id=shape;force dut.confidence=conf;
    force dut.x0=bx0;force dut.x1=bx1;force dut.y0=by0;force dut.y1=by1;
    force dut.target_valid=valid;force dut.grbl_current_start=current;
    force dut.grbl_current_job_id=remote_job;force dut.session_id=session;force dut.online=network_online;
    force dut.vision_cancel=cancel_frame;force dut.vision_job_cancel=explicit_cancel;
    force dut.vision_start=new_job;force dut.vision_busy=vision_running;force dut.vision_teach_good=0;
    force dut.maze_done=0;force dut.cfg_apply=config_apply;force dut.job_status_ready=1;
    force dut.key4_press=task_reset;
    force dut.copy_busy=0;force dut.copy_recovery=0;force dut.copy_uart_owner=0;
    force dut.report_page_maintenance=1'b0;force dut.report_ready=rep_ready;force dut.report_busy=rep_busy;
    force dut.report_done=rep_done;force dut.report_error=0;
    force dut.report_recovery_required=recovery;force dut.report_state=0;
    // The metadata bench replaces the real reporter with a generated stub.
    // Drive the newly added paper-confirmation outputs explicitly so the
    // top-level KEY1 admission equations never see an unconnected X.
    force dut.paper_confirm_armed=1'b0;force dut.paper_confirm_active=1'b0;
    force dut.report_total_lines=0;force dut.report_total_valid=0;force dut.report_airwalk_active=0;force dut.report_lines=0;force dut.report_error_code=0;
    force dut.grbl_test_start=0;force dut.uart_link_ready=1;
    force dut.uart_rt_ready=1;force dut.uart_rt_done=0;force dut.uart_idle_pulse=0;
    force dut.profile_valid=1;force dut.result_job_id=result_id;
    force dut.operator_snapshot_take=take;force dut.operator_preview_capable=capable;
    force dut.pcb_reason=reason;force dut.teach_code=detail;
    force dut.page_used_cmm=page_used;force dut.page_remaining_cmm=page_remaining;
    force dut.page_generation=16'd0;force dut.page_result=8'd0;force dut.page_full=0;
    force dut.copy_operator_job=0;force dut.copy_operator_state=0;force dut.copy_operator_error=0;
    force dut.copy_operator_acked=0;force dut.copy_total_lines=0;force dut.copy_total_valid=0;force dut.copy_airwalk_active=0;force dut.copy_write_waiting=0;force dut.copy_draw_admitted=0;
    force dut.pcb_checked=pcb_checked_now;force dut.pcb_status=pcb_status_now;force dut.pcb_good=pcb_good_now;
    force dut.defect_count=source_count;force dut.defect_boxes=source_boxes;force dut.defect_kinds=source_kinds;


    seed;press_key1;check(accepts==1,"idle short press accepts CNN write");expect_snapshot;
    seed;vision_running=1;press_key1;
    check(accepts==FIXED,"CNN inference already busy at press begins");if(FIXED)expect_snapshot;
    seed;down;vision_running=1;repeat(2)step;vision_running=0;repeat(2)step;up;
    check(accepts==FIXED,"new CNN busy interval during held KEY1");if(FIXED)expect_snapshot;
    seed;down;new_job=1;step;new_job=0;repeat(2)step;up;
    check(accepts==FIXED,"new ordinary frame during held KEY1");if(FIXED)expect_snapshot;
    seed;down;result_id=89;result(3,3,11,600,900,400,600,1);up;
    check(accepts==1,"valid new result during held key preserves admission");expect_snapshot;
    seed;down;release_to_pulse;
    @(negedge clk);done=1;step;@(negedge clk);done=0;repeat(5)step;
    check(accepts==FIXED,"valid completion coincident with short pulse");if(FIXED)expect_snapshot;
    seed;down;result(0,0,0,0,0,0,0,0);up;
    check(accepts==0&&!dut.cnn_cache_valid,"no-target while held cancels write and clears cache");
    seed;down;release_to_pulse;
    @(negedge clk);done=1;valid=0;step;@(negedge clk);done=0;repeat(5)step;
    check(accepts==0&&!dut.cnn_cache_valid,"no-target simultaneous with release cannot print stale result");
    seed;down;purpose=1;repeat(3)step;purpose=0;up;
    check(accepts==0,"mode change while held cannot defer CNN write");
    seed;down;explicit_cancel=1;step;explicit_cancel=0;up;
    check(accepts==0,"explicit cancel during held KEY1 cannot write");
    seed;down;session=124;repeat(3)step;up;
    check(accepts==0,"session change during held KEY1 clears stale result");
    seed;down;recovery=1;repeat(3)step;recovery=0;up;
    check(accepts==0,"real recovery interval during held KEY1 cancels eligibility");
    seed;down;rep_busy=1;repeat(3)step;rep_busy=0;up;
    check(accepts==0,"another report during held KEY1 cancels eligibility");
    seed;take=0;result(0,0,0,0,0,0,0,0);result(1,1,88,120,300,40,180,1);step;
    check(!dut.preview_locked,"fresh unsampled preview not falsely frozen");press_key1;
    check(accepts==0,"capable UI requires coherent sampled preview");
    seed;down;repeat(45)step;up;
    check(accepts==0&&!dut.paper_confirm_active,"long report KEY1 does not print or start paper load");
    if(errors)$fatal(1,"Continuous CNN KEY1 validation failed errors=%0d",errors);
    $display("CONTINUOUS_CNN_KEY1_VALIDATED fixed=%0d checks=%0d",FIXED,checks);$finish;
end
endmodule
