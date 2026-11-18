`timescale 1ns/1ps
module tb_suspect_key1_snapshot;
reg clk=0, rst_n=0, key1_n=1;
always #4 clk=~clk;
reg [1:0] purpose=0, color=0, shape=0;
reg done=0, valid=0, current=0;
reg [2:0] source_count=0;reg [255:0] source_boxes=0;reg [7:0] source_kinds=0;
reg pcb_good_now=0;reg [2:0] pcb_status_now=1;reg new_job=0,explicit_cancel=0;
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
    @(negedge clk);key1_n=0;
    repeat(8)step;
    @(negedge clk);key1_n=1;
    repeat(10)step;
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
    force dut.paper_confirm_armed=1'b0;force dut.paper_confirm_active=1'b0;force dut.copy_write_waiting=1'b0;force dut.copy_prepare_cancel=1'b0;force dut.report_page_maintenance=1'b0;force dut.report_ready=rep_ready;force dut.report_busy=rep_busy;
    force dut.report_done=rep_done;force dut.report_error=0;
    force dut.report_recovery_required=0;force dut.report_state=0;
    force dut.report_lines=0;force dut.report_error_code=0;
    force dut.grbl_test_start=0;force dut.uart_link_ready=1;
    force dut.uart_rt_ready=1;force dut.uart_rt_done=0;force dut.uart_idle_pulse=0;
    force dut.profile_valid=1;force dut.result_job_id=32'd88;
    force dut.pcb_checked=1;force dut.pcb_status=pcb_status_now;force dut.pcb_good=pcb_good_now;
    force dut.defect_count=source_count;force dut.defect_boxes=source_boxes;force dut.defect_kinds=source_kinds;

    // Retain the legacy-peer snapshot contract. Capable-peer preview locking
    // is independently exercised by tb_operator_metadata on the same DUT.
    force dut.operator_preview_capable=1'b0;force dut.operator_snapshot_take=1'b0;

    repeat(4)step;rst_n=1;repeat(5)step;dut.key1_lock=0;
    purpose=1;repeat(4)step;
    source_boxes={192'd0,16'd42,16'd122,16'd39,16'd119};
    source_count=1;source_kinds=3;pcb_good_now=0;pcb_status_now=1;
    result(0,0,0,100,500,20,400,1);
    check(dut.pcb_report_cache_valid&&dut.pcb_report_cache_job==88&&
          dut.pcb_report_cache_judgement==2&&dut.pcb_report_cache_defect_count==1&&
          dut.pcb_report_cache_boxes=={16'd40,16'd120}&&dut.pcb_report_cache_kinds==3&&
          dut.vision_result[511:256]==source_boxes,
          "FAIL caches coherent original-frame SUSPECT centre without auto writing");
    check(!dut.report_pending&&!dut.key1_job_active,"inspection never auto writes");
    press_key1;
    check(!dut.report_cnn_mode&&dut.report_job==88&&dut.report_judgement==2&&
          dut.report_defect_count==1&&dut.report_defect_boxes=={224'd0,16'd40,16'd120}&&dut.report_defect_kinds==3&&
          dut.u_reporter.I_defect_boxes=={224'd0,16'd40,16'd120}&&dut.u_reporter.I_defect_kinds==3&&
          dut.u_reporter.PCB_SUSPECT_CENTER_INPUT==1,
          "KEY1 snapshot passes same centre and SUSPECT tag to reporter");
    check(!dut.pcb_report_cache_valid,"accepted cache is consumed once");
    @(negedge clk);rep_busy=1;source_boxes={192'd0,16'd500,16'd900,16'd400,16'd700};source_kinds=0;source_count=0;
    network_online=0;session=64'd124;cancel_frame=1;repeat(6)step;
    check(dut.report_defect_boxes=={224'd0,16'd40,16'd120}&&
          dut.report_defect_count==1&&dut.report_defect_kinds==3&&
          dut.key1_job_protected&&dut.u_reporter.I_abort===0,
          "accepted SUSPECT snapshot survives live changes Ethernet loss and frame cancel");
    @(negedge clk);network_online=1;cancel_frame=0;retire;
    press_key1;
    check(!dut.report_pending&&!dut.key1_job_active,"repeated KEY1 cannot replay consumed PCB result");
    retire;
    pcb_good_now=1;pcb_status_now=0;source_count=0;source_boxes=0;source_kinds=0;
    result(0,0,0,100,500,20,400,1);
    check(dut.pcb_report_cache_judgement==1&&dut.pcb_report_cache_defect_count==0&&
          dut.pcb_report_cache_boxes==0&&dut.pcb_report_cache_kinds==0,
          "PASS atomically clears old SUSPECT snapshot");
    press_key1;check(dut.report_judgement==1&&dut.report_defect_count==0&&
          dut.report_defect_boxes==0&&dut.report_defect_kinds==0,"PASS KEY1 never inherits old SUSPECT");retire;
    pcb_good_now=0;pcb_status_now=2;
    result(0,0,0,100,500,20,400,1);press_key1;
    check(dut.report_judgement==0&&dut.report_defect_count==0&&dut.report_defect_boxes==0,
          "REVIEW KEY1 has no suspect");retire;
    pcb_status_now=1;source_count=1;source_kinds=3;source_boxes={192'd0,16'd42,16'd122,16'd39,16'd119};
    result(0,0,0,100,500,20,400,1);
    @(negedge clk);new_job=1;step;@(negedge clk);new_job=0;
    check(!dut.pcb_report_cache_valid&&dut.pcb_report_cache_boxes==0,
          "new image transaction clears cached old region before completion");
    press_key1;check(!dut.report_pending&&!dut.key1_job_active,"KEY1 before new completion cannot print stale region");retire;
    result(0,0,0,100,500,20,400,1);purpose=0;repeat(3)step;
    check(!dut.pcb_report_cache_valid&&dut.pcb_report_cache_boxes==0,"mode change clears cached PCB region");
    purpose=1;repeat(3)step;result(0,0,0,100,500,20,400,1);
    result(0,0,0,0,0,0,0,0);
    check(!dut.pcb_report_cache_valid&&dut.pcb_report_cache_boxes==0,"no-target completion clears cached PCB region");
    for(integer invalid=0;invalid<3;invalid=invalid+1)begin
        case(invalid)
            0:source_boxes={192'd0,16'd721,16'd1281,16'd39,16'd119};
            1:source_boxes={192'd0,16'd39,16'd119,16'd42,16'd122};
            default:source_boxes={192'd0,16'd42,16'd122,16'd42,16'd122};
        endcase
        result(0,0,0,100,500,20,400,1);
        check(dut.pcb_report_cache_valid&&dut.pcb_report_cache_judgement==2&&
              dut.pcb_report_cache_defect_count==0&&dut.pcb_report_cache_boxes==0,
              "invalid/outside/zero-area source region never enters compressed centre cache");
        press_key1;
        check(dut.report_judgement==2&&dut.report_defect_count==0&&
              dut.report_defect_boxes==0&&dut.report_defect_kinds==0,
              "invalid region retains FAIL title but sends no suspect coordinate");retire;
    end
    source_boxes={192'd0,16'd42,16'd122,16'd39,16'd119};
    result(0,0,0,100,500,20,400,1);explicit_cancel=1;step;explicit_cancel=0;
    check(!dut.pcb_report_cache_valid&&dut.pcb_report_cache_boxes==0,"explicit job cancel clears cached region");
    result(0,0,0,100,500,20,400,1);task_reset=1;step;task_reset=0;
    check(!dut.pcb_report_cache_valid&&dut.pcb_report_cache_boxes==0,"KEY4 reset clears cached region");
    if(errors!=0)$fatal(1,"SUSPECT_KEY1_SNAPSHOT_FAIL checks=%0d errors=%0d",checks,errors);
    $display("SUSPECT_KEY1_SNAPSHOT_PASS checks=%0d",checks);$finish;
end
initial begin #200000;$fatal(1,"SUSPECT KEY1 metadata timeout");end
endmodule
