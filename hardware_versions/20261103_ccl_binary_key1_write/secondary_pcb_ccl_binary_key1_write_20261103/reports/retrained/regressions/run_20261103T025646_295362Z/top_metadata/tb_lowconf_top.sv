`timescale 1ns/1ps
module tb_cnn_named_top;
reg clk=0, rst_n=0, key1_n=1;
always #4 clk=~clk;
reg [1:0] purpose=0, color=0, shape=0;
reg done=0, valid=0, current=0;
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
    @(negedge clk);key1_n=0;
    repeat(6)step;
    @(negedge clk);key1_n=1;
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
    force dut.vision_cancel=cancel_frame;force dut.vision_job_cancel=0;
    force dut.vision_start=0;force dut.vision_busy=0;force dut.vision_teach_good=0;
    force dut.maze_done=0;force dut.cfg_apply=config_apply;force dut.job_status_ready=1;
    force dut.key4_press=task_reset;
    force dut.copy_busy=0;force dut.copy_recovery=0;force dut.copy_uart_owner=0;
    force dut.report_ready=rep_ready;force dut.report_busy=rep_busy;
    force dut.report_done=rep_done;force dut.report_error=0;
    force dut.report_recovery_required=0;force dut.report_state=0;
    force dut.report_lines=0;force dut.report_error_code=0;
    force dut.grbl_test_start=0;force dut.uart_link_ready=1;
    force dut.uart_rt_ready=1;force dut.uart_rt_done=0;force dut.uart_idle_pulse=0;
    force dut.profile_valid=1;force dut.result_job_id=32'd88;
    force dut.pcb_checked=1;force dut.pcb_status=1;force dut.pcb_good=1;
    force dut.defect_count=0;force dut.defect_boxes=0;force dut.defect_kinds=0;
    repeat(4)step;rst_n=1;history_quiet;
    // This metadata-only bench forces the application reset. The separate
    // KEY3 top test exercises the real 2.5M-cycle startup lock and held keys.
    dut.key1_lock=0;
    check(dut.cnn_cache_valid===0,"reset invalidates cache");
    result(1,1,87,120,300,40,180,1);
    check(dut.cnn_cache_valid && dut.cnn_cache_class==1 && dut.cnn_cache_confidence==87,
          "ordinary result caches class and confidence");
    check(dut.cnn_cache_box=={224'd0,16'd110,16'd210},
          "ordinary result caches exact image centre");
    @(negedge clk);color=3;shape=3;conf=250;bx0=700;bx1=900;by0=500;by1=600;valid=0;
    repeat(5)step;
    check(dut.cnn_cache_valid && dut.cnn_cache_class==1 && dut.cnn_cache_confidence==87 && dut.cnn_cache_box=={224'd0,16'd110,16'd210},
          "next incomplete frame cannot change accepted cache");
    press_key1;
    check(dut.report_cnn_mode && dut.report_cnn_class==1 && dut.report_cnn_confidence==87 &&
          dut.report_judgement==2 && dut.report_defect_count==1 && dut.report_source==0,
          "physical KEY1 admits cached named report with confidence");
    check(dut.report_defect_boxes=={224'd0,16'd110,16'd210} &&
          dut.u_reporter.I_cnn_confidence==87 && dut.u_reporter.I_defect_boxes=={224'd0,16'd110,16'd210},
          "report leaf receives confidence and image center only (210,110)");
    @(negedge clk);rep_busy=1;
    result(2,2,199,501,800,101,402,1);
    check(dut.cnn_cache_class==5 && dut.cnn_cache_confidence==199 && dut.cnn_cache_box=={224'd0,16'd251,16'd650},
          "latest completed ordinary result refreshes cache");
    check(dut.report_cnn_class==1 && dut.report_cnn_confidence==87 &&
          dut.report_defect_boxes=={224'd0,16'd110,16'd210},
          "active report snapshot is stable while cache advances");
    @(negedge clk);network_online=0;cancel_frame=1;
    repeat(4)step;
    check_empty("offline event clears ordinary cache metadata");
    check(dut.key1_job_active && dut.key1_job_protected && dut.u_reporter.I_abort===0 &&
          dut.report_cnn_class==1 && dut.report_cnn_confidence==87 &&
          dut.report_defect_boxes=={224'd0,16'd110,16'd210},
          "accepted KEY1 report survives Ethernet loss and ordinary frame cancel");
    @(negedge clk);network_online=1;cancel_frame=0;history_quiet;
    retire;
    result(2,2,199,501,800,101,402,1);
    @(negedge clk);current=1;step;@(negedge clk);current=0;
    check(dut.report_cnn_mode && dut.report_cnn_class==5 && dut.report_cnn_confidence==199 &&
          dut.report_job==42 && dut.report_source==2 && dut.report_defect_boxes=={224'd0,16'd251,16'd650},
          "Type20 current request snapshots same latest metadata contract");
    step;retire;
    result(3,3,211,0,1279,0,719,1);
    check(dut.cnn_cache_box=={224'd0,16'd359,16'd639},
          "odd full-frame center sums floor to (639,359) without overflow");
    result(3,3,213,1000,1279,600,719,1);
    check(dut.cnn_cache_box=={224'd0,16'd659,16'd1139},
          "center sums exceed source coordinate widths without overflow");
    result(0,0,0,0,0,0,0,0);
    check(!dut.cnn_cache_valid && dut.cnn_cache_class==0 && dut.cnn_cache_confidence==0,
          "completed no-target result invalidates stale target");
    press_key1;
    check(!dut.report_pending && !dut.key1_job_active,
          "KEY1 after no target does not start writing");
    retire;
    // A briefly held temporal identity is valid but explicitly uncertain.
    // The writer must preserve the published confidence zero, never reuse an
    // earlier nonzero score or downgrade the held class to stale no-target.
    result(2,2,0,501,800,101,402,1);
    press_key1;
    check(dut.report_cnn_mode && dut.report_cnn_class==5 && dut.report_cnn_confidence==0 &&
          dut.report_judgement==2 && dut.report_defect_boxes=={224'd0,16'd251,16'd650},
          "held identity snapshot preserves class and explicit confidence zero");
    retire;
    result(3,3,231,100,500,90,400,1);
    @(negedge clk);purpose=1;
    repeat(3)step;
    check(dut.cnn_history_clear===1,"PCB mode requests ordinary identity history clear");
    check_empty("mode switch clears ordinary cache before PCB completion");
    result(1,1,12,11,22,33,44,1);
    check_empty("PCB completion cannot repopulate ordinary CNN cache");
    check(!dut.report_pending && !dut.key1_job_active && dut.pcb_report_cache_valid &&
          dut.pcb_report_cache_job==88 && dut.pcb_report_cache_judgement==1,
          "PCB completion caches result without starting a report");
    press_key1;
    check(!dut.report_cnn_mode && dut.report_source==0 && dut.report_job==88 && dut.report_judgement==1,
          "PCB-mode KEY1 writes the cached PCB result");
    retire;
    @(negedge clk);purpose=0;history_quiet;
    result(1,3,88,120,300,40,180,1);
    @(negedge clk);session=64'd124;
    repeat(3)step;
    check_empty("HELLO session change clears complete cached metadata");
    history_quiet;
    result(3,2,91,1000,1279,600,719,1);
    @(negedge clk);config_apply=1;
    repeat(3)step;
    check_empty("configuration apply clears complete cached metadata");
    @(negedge clk);config_apply=0;history_quiet;
    result(1,2,92,1000,1279,600,719,1);
    @(negedge clk);task_reset=1;step;
    @(negedge clk);task_reset=0;repeat(3)step;
    check_empty("KEY4 task reset clears complete cached metadata");
    repeat(12)step;history_quiet;
    result(3,1,93,1000,1279,600,719,1);
    @(negedge clk);rst_n=0;step;
    check_empty("FPGA reset clears complete cached metadata");
    @(negedge clk);rst_n=1;history_quiet;
    // The clear reason arrives before its registered history-clear pulse.
    // Remote admission on that first edge must not read the old cache.
    result(1,1,94,120,300,40,180,1);
    @(negedge clk);network_online=0;current=1;#1;
    check(!dut.cnn_history_clear && dut.cnn_history_reason && dut.cnn_cache_valid && dut.cnn_cache_confidence==94,
          "offline first-edge stale-cache hazard precedes registered history clear");
    step;
    check(dut.report_cnn_mode && dut.report_judgement==0 && dut.report_defect_count==0 &&
          dut.report_cnn_class==0 && dut.report_cnn_confidence==0 && dut.report_defect_boxes==0,
          "offline first edge and remote request cannot snapshot stale target");
    @(negedge clk);current=0;
    check_empty("same-edge clear also invalidates original cache");
    @(negedge clk);network_online=1;history_quiet;retire;
    result(3,3,95,1000,1279,600,719,1);
    @(negedge clk);session=64'd125;current=1;#1;
    check(!dut.cnn_history_clear && dut.cnn_history_reason && dut.cnn_cache_valid && dut.cnn_cache_confidence==95,
          "session first-edge stale-cache hazard precedes registered history clear");
    step;
    check(dut.report_cnn_mode && dut.report_judgement==0 && dut.report_defect_count==0 &&
          dut.report_cnn_class==0 && dut.report_cnn_confidence==0 && dut.report_defect_boxes==0,
          "session first edge and remote request cannot snapshot stale target");
    check_empty("session first edge clears original cache metadata");
    @(negedge clk);current=0;history_quiet;retire;
    result(2,3,96,501,800,101,402,1);
    previous_local_id=dut.key1_report_id;
    // Generate the actual synchronized physical KEY1 pulse, then make cfg
    // apply arrive before the very first edge that could consume that pulse.
    @(negedge clk);key1_n=0;
    repeat(3)step;
    @(negedge clk);config_apply=1;#1;
    check(dut.key1_report_pulse && !dut.cnn_history_clear && dut.cnn_history_reason &&
          dut.cnn_cache_valid && !dut.key1_local_admit,
          "configuration first edge gates actual physical KEY1 pulse before registered clear");
    step;
    check(!dut.report_pending && dut.key1_report_id==previous_local_id && !dut.key1_job_active,
          "configuration first edge cannot admit physical KEY1 using old target");
    check_empty("configuration first edge clears original cache metadata");
    @(negedge clk);config_apply=0;key1_n=1;history_quiet;
    check(errors==0,"all production-top metadata assertions");
    baseline_checks=checks;
    if(baseline_checks!=45 || errors!=0)
        $fatal(1,"original 45 assertions failed count=%0d errors=%0d",baseline_checks,errors);

    // Full-top collision A: admission must use the old complete cached result
    // while a new inference atomically replaces the live cache on the same edge.
    result(1,1,87,120,300,40,180,1);
    @(negedge clk);remote_job=32'd43;current=1;done=1;
    color=2;shape=2;conf=199;bx0=501;bx1=800;by0=101;by1=402;valid=1;
    step;
    check(dut.report_pending && dut.report_cnn_mode && dut.report_job==43 &&
          dut.report_cnn_class==1 && dut.report_cnn_confidence==87 &&
          dut.report_judgement==2 && dut.report_defect_count==1 &&
          dut.report_defect_boxes=={224'd0,16'd110,16'd210},
          "same-edge inference and remote admission snapshot old complete metadata");
    check(dut.cnn_cache_valid && dut.cnn_cache_class==5 && dut.cnn_cache_confidence==199 &&
          dut.cnn_cache_box=={224'd0,16'd251,16'd650},
          "same-edge inference atomically publishes new centre and metadata to cache");
    @(negedge clk);current=0;done=0;
    step;retire;

    // Full-top collision B: hold the report-ready handshake briefly, then
    // change HELLO/session before admission. The cache clears while the
    // already latched pending report retains its independent old-session data.
    // No frame cancel is driven in this controlled-leaf scenario.
    result(3,2,133,100,500,90,400,1);
    @(negedge clk);remote_job=32'd44;rep_ready=0;current=1;
    step;
    check(dut.report_pending && dut.u_reporter.I_job_valid && dut.report_job==44 &&
          dut.report_cnn_class==8 && dut.report_cnn_confidence==133 &&
          dut.report_defect_boxes=={224'd0,16'd245,16'd300},
          "ready stall retains a complete pending report before cache clear");
    @(negedge clk);current=0;session=64'd126;
    step;
    check(!dut.cnn_cache_valid && dut.cnn_cache_class==0 && dut.cnn_cache_confidence==0 &&
          dut.cnn_cache_box==256'd0,
          "session clear during pending ready stall invalidates the live cache");
    check(dut.report_pending && dut.u_reporter.I_job_valid && dut.report_session==125 &&
          dut.report_job==44 && dut.report_cnn_class==8 && dut.report_cnn_confidence==133 &&
          dut.report_defect_boxes=={224'd0,16'd245,16'd300},
          "pending snapshot survives live-cache clear without taking zero metadata");
    @(negedge clk);step;
    check(dut.report_pending && dut.report_admit_age==2 && dut.report_cnn_class==8 &&
          dut.report_cnn_confidence==133 && dut.report_defect_boxes=={224'd0,16'd245,16'd300},
          "pending data remains unchanged throughout the bounded ready stall");
    @(negedge clk);rep_ready=1;rep_busy=1;
    step;
    check(!dut.report_pending && dut.report_cnn_class==8 && dut.report_cnn_confidence==133 &&
          dut.report_defect_boxes=={224'd0,16'd245,16'd300},
          "ready acceptance clears pending while retaining the accepted report snapshot");
    retire;

    // These values are the configured pipeline's exact published score domain.
    result(2,2,7,501,800,101,402,1);
    check(dut.cnn_cache_valid&&dut.cnn_cache_class==5&&dut.cnn_cache_confidence==7,
          "LOWCONF_TOP_CACHE_RETAINS_REAL_SCORE7");
    press_key1;
    check(dut.report_cnn_mode&&dut.report_cnn_class==5&&dut.report_cnn_confidence==7&&
          dut.report_judgement==2&&dut.report_defect_boxes=={224'd0,16'd251,16'd650}&&
          dut.u_reporter.I_cnn_confidence==7,
          "LOWCONF_KEY1_CLASS_CENTER_CONF7_SNAPSHOT");
    @(negedge clk);rep_busy=1;
    result(3,3,1,120,300,40,180,1);
    check(dut.report_cnn_class==5&&dut.report_cnn_confidence==7&&
          dut.report_defect_boxes=={224'd0,16'd251,16'd650},
          "LOWCONF_ACTIVE_REPORT_CANNOT_CHANGE_TO_NEW_RESULT");
    retire;press_key1;
    check(dut.report_cnn_class==9&&dut.report_cnn_confidence==1&&dut.report_judgement==2&&
          dut.report_defect_boxes=={224'd0,16'd110,16'd210},
          "LOWCONF_KEY1_CLASS_CENTER_CONF1_SNAPSHOT");
    retire;
    result(3,3,0,120,300,40,180,1);press_key1;
    check(dut.report_cnn_class==9&&dut.report_cnn_confidence==0&&dut.report_judgement==2,
          "LOWCONF_HELD_IDENTITY_CONF0_IS_NOT_UPGRADED");
    retire;
    result(0,0,0,0,0,0,0,0);press_key1;
    check(!dut.report_pending&&!dut.key1_job_active,
          "LOWCONF_KEY1_NO_TARGET_DOES_NOT_START_WRITING");
    retire;
    $display("PASS LOWCONF_TOP_METADATA_DIRECTED");

    if(errors!=0)$fatal(1,"TOP_METADATA_FAIL checks=%0d errors=%0d",checks,errors);
    $display("CENTER_CACHE_FULL_TOP_COUNTS baseline=%0d added=%0d total=%0d",baseline_checks,checks-baseline_checks,checks);
    $display("PASS CNN_NAMED_TOP_ALL checks=%0d",checks);$finish;
end
initial begin #200000;$fatal(1,"top metadata timeout");end
endmodule
