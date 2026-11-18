`timescale 1ns/1ps
module tb_operator_metadata;
reg clk=0, rst_n=0, key1_n=1;
always #4 clk=~clk;
reg [1:0] purpose=0, color=0, shape=0;
reg done=0, valid=0, current=0;
reg take=0,new_job=0,explicit_cancel=0,capable=1;
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
initial begin
    force dut.clk125=clk;force dut.rst125_n=rst_n;
    force dut.vision_purpose=purpose;force dut.normal_done=done;
    force dut.color_id=color;force dut.shape_id=shape;force dut.confidence=conf;
    force dut.x0=bx0;force dut.x1=bx1;force dut.y0=by0;force dut.y1=by1;
    force dut.target_valid=valid;force dut.grbl_current_start=current;
    force dut.grbl_current_job_id=remote_job;force dut.session_id=session;force dut.online=network_online;
    force dut.vision_cancel=cancel_frame;force dut.vision_job_cancel=explicit_cancel;
    force dut.vision_start=new_job;force dut.vision_busy=0;force dut.vision_teach_good=0;
    force dut.maze_done=0;force dut.cfg_apply=config_apply;force dut.job_status_ready=1;
    force dut.key4_press=task_reset;
    force dut.copy_busy=0;force dut.copy_recovery=0;force dut.copy_uart_owner=0;
    force dut.report_page_maintenance=1'b0;force dut.report_ready=rep_ready;force dut.report_busy=rep_busy;
    force dut.report_done=rep_done;force dut.report_error=0;
    force dut.report_recovery_required=0;force dut.report_state=0;
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

    repeat(4)step;rst_n=1;history_quiet;dut.key1_lock=0;
    check(dut.operator_status_data[31:0]==32'h3152504f&&dut.operator_status_data[39:32]==1&&
          !dut.operator_status_data[40]&&dut.operator_status_data[383:368]==0,"OPR1 layout and initial invalid");
    result(1,1,7,120,300,40,180,1);step;
    check(dut.operator_status_data[40]&&dut.operator_status_data[135:128]==1&&
          dut.operator_status_data[143:136]==7&&dut.operator_status_data[175:160]==210&&
          dut.operator_status_data[191:176]==110&&dut.operator_status_data[95:64]==88,
          "low confidence preview uses actual class score exact centre and result ID");
    press_key1;check(!dut.report_pending&&!dut.key1_job_active,"KEY1 cannot write before snapshot take");retire;
    take=1;step;take=0;step;check(dut.preview_locked,"metadata take locks pending snapshot");
    result_id=89;result(3,3,99,600,900,400,600,1);step;
    check(dut.cnn_cache_class==1&&dut.cnn_cache_confidence==7&&dut.cnn_cache_job==88&&
          dut.operator_status_data[175:160]==210,"new valid frame cannot overwrite locked preview");
    result(0,0,0,0,0,0,0,0);step;
    check(!dut.preview_locked&&!dut.operator_status_data[40]&&dut.operator_status_data[175:160]==0,
          "current no-target clears old preview and snapshot lock");
    result_id=90;result(2,3,12,100,300,80,200,1);step;take=1;step;take=0;step;
    press_key1;rep_busy=1;step;
    check(dut.report_snapshot_id==90&&dut.report_cnn_class==6&&dut.report_cnn_confidence==12&&
          dut.report_center=={10'd140,11'd200},"KEY1 admitted exact frozen preview");
    check(dut.operator_status_data[41]&&dut.operator_status_data[95:64]==90&&
          dut.operator_status_data[143:136]==12,"active metadata selects independent accepted snapshot");
    network_online=0;session=124;cancel_frame=1;result_id=91;result(3,1,90,700,900,500,600,1);step;
    check(dut.report_snapshot_id==90&&dut.report_center=={10'd140,11'd200}&&
          dut.key1_job_protected&&!dut.u_reporter.I_abort,"network and new frame cannot change accepted writing");
    network_online=1;cancel_frame=0;retire;
    purpose=1;repeat(6)step;result_id=100;pcb_status_now=1;pcb_good_now=0;reason=2;detail=0;
    source_count=1;source_kinds=3;source_boxes={192'd0,16'd100,16'd300,16'd20,16'd100};
    result(0,0,30,80,500,10,400,1);step;take=1;step;take=0;step;
    check(dut.operator_status_data[55:48]==2&&dut.operator_status_data[151:144]==2&&
          dut.operator_status_data[159:152]==2&&dut.operator_status_data[44]&&
          dut.operator_status_data[175:160]==200&&dut.operator_status_data[191:176]==60,
          "PCB FAIL preview pairs reason judgement and SUSPECT centre");
    pcb_status_now=0;pcb_good_now=1;step;
    check(dut.operator_status_data[151:144]==2&&dut.operator_status_data[44],
          "pending PCB verdict uses frozen cache rather than changing live classifier outputs");
    press_key1;rep_busy=1;step;
    check(dut.report_pcb_reason==2&&dut.report_snapshot_id==100&&dut.report_suspect&&
          dut.report_center=={10'd60,11'd200},"PCB KEY1 accepts frozen suspect and reason");
    new_job=1;step;new_job=0;reason=4;detail=16'h0201;pcb_checked_now=0;pcb_status_now=2;
    result_id=101;result(0,0,0,0,0,0,0,0);step;
    check(dut.operator_status_data[41]&&dut.operator_status_data[159:152]==2&&
          dut.operator_status_data[95:64]==100,"new no-target PCB does not alter accepted report metadata");
    retire;step;
    check(!dut.operator_status_data[40]&&!dut.operator_status_data[44]&&
          dut.operator_status_data[175:160]==0&&dut.operator_status_data[159:152]==4&&
          dut.pcb_cache_detail==16'h0201&&dut.operator_status_data[351:272]==80'd0&&dut.operator_status_data[151:144]==3,
          "no-target REVIEW clears old suspect; raw local error retained and transport diagnostics reserved zero");
    new_job=1;step;new_job=0;step;
    check(dut.operator_status_data[159:152]==0&&!dut.operator_status_data[40],"new PCB task clears diagnostic preview");
    purpose=0;capable=0;repeat(6)step;result_id=111;result(1,2,5,40,200,20,120,1);step;
    check(!dut.preview_locked&&dut.operator_status_data[47],"legacy peer retains local KEY1 ready without UI capability");
    press_key1;rep_busy=1;step;
    check(dut.key1_job_protected&&dut.report_snapshot_id==111&&dut.report_cnn_class==2,
          "legacy non-Type21 peer admits original local KEY1 cached result");retire;
    page_used=3500;page_remaining=19200;step;
    check(dut.operator_status_data[239:224]==0&&dut.operator_status_data[255:240]==0,
          "paper used and remaining fields remain zero");
    // Maintenance ownership must cover the pulse-to-busy handoff.
    page_used=0;rep_busy=0;step;
    force dut.key2_new_page=1'b1;
    force dut.key1_report_pulse=1'b1;force dut.key1_report_action=1'b1;force dut.key1_fresh_press=1'b1;
    force dut.copy_write_waiting=1'b1;
    step;
    check(!dut.key1_local_admit&&!dut.pcb_key1_admit&&!dut.copy_write_start&&
          dut.report_network_protected&&!dut.report_pending&&!dut.key1_job_active,
          "page request pulse fences KEY1 and document admission and protects network handoff");
    check(dut.operator_status_data[41]&&!dut.operator_status_data[40]&&!dut.operator_status_data[47]&&
          dut.operator_status_data[55:48]==0&&dut.operator_status_data[191:64]==0,
          "page request handoff shows busy with no old report or ready preview");
    force dut.key1_report_pulse=1'b0;force dut.key1_report_action=1'b0;force dut.key1_fresh_press=1'b0;
    force dut.copy_write_waiting=1'b0;force dut.key2_new_page=1'b0;step;
    force dut.report_page_maintenance=1'b1;rep_busy=1;rep_done=1;
    force dut.report_lines=32'd7;force dut.report_state=3'd2;
    repeat(2)step;
    check(!dut.job_status_valid,
          "maintenance ACK and DONE never reuse the last report job status");
    check(dut.operator_status_data[41]&&!dut.operator_status_data[40]&&!dut.operator_status_data[47]&&
          !dut.operator_status_data[44]&&dut.operator_status_data[55:48]==0&&
          dut.operator_status_data[63:56]==2&&dut.operator_status_data[191:64]==0,
          "active maintenance clears old names coordinates verdict snapshot and job while keeping busy");
    rep_done=0;rep_busy=0;force dut.report_page_maintenance=1'b0;step;
    if(errors)$fatal(1,"OPERATOR_METADATA_FAIL checks=%0d errors=%0d",checks,errors);
    $display("OPERATOR_METADATA_PASS checks=%0d",checks);$finish;
end
initial begin #200000;$fatal(1,"operator metadata timeout");end
endmodule

