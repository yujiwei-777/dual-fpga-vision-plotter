`timescale 1ns/1ps
module tb_pcb_key1_report;
reg clk=0,rst_n=0,key1_n=1,key1_pulse=0;
always #4 clk=~clk;
reg [1:0] purpose=1,pcb_status=0,color=0,shape=0;
reg done=0,target=0,pcb_checked=0,pcb_good=0,current_start=0;
reg [2:0] defects=0;
reg [255:0] boxes=0;
reg [7:0] kinds=0;
reg [7:0] confidence=0;
reg frame_cancel=0,job_cancel=0,vision_start=0,key4=0;
reg [31:0] result_job=0,remote_job=32'd77;
reg reporter_ready=1,reporter_busy=0,reporter_done=0;
reg uart_ready=1,profile_ready=1;
integer errors=0,checks=0;

secondary_top dut(.I_sys_clk(clk),.I_sw2(1'b0),.I_key1_n(key1_n),
    .I_key2_n(1'b1),.I_key3_n(1'b1),.I_key4_n(1'b1),
    .I_rgmii_rxd(4'd0),.I_rgmii_rx_ctl(1'b0),.I_rgmii_rxc(clk),
    .I_uart_rx(1'b1),.I_esp_link_ready(1'b1));

task step;begin @(posedge clk);#1;end endtask
task check(input bit ok,input string message);begin
    checks=checks+1;
    if(!ok)begin errors=errors+1;$display("FAIL %s",message);end
    else $display("PASS %s",message);
end endtask
task complete_pcb(input [31:0] job,input [1:0] status,input bit has_target,
                  input bit checked,input bit good,input [2:0] ndef,
                  input [255:0] b,input [7:0] k);begin
    @(negedge clk);purpose=1;result_job=job;pcb_status=status;target=has_target;
    pcb_checked=checked;pcb_good=good;defects=ndef;boxes=b;kinds=k;done=1;
    step;@(negedge clk);done=0;
end endtask
task press_key1;begin
    @(negedge clk);key1_pulse=1;step;
    @(negedge clk);key1_pulse=0;repeat(3)step;
end endtask
task retire_report;begin
    @(negedge clk);reporter_busy=0;reporter_ready=1;reporter_done=1;
    step;@(negedge clk);reporter_done=0;repeat(3)step;
end endtask

initial begin
    force dut.clk125=clk;force dut.rst125_n=rst_n;
    force dut.key1_report_pulse=key1_pulse;
    force dut.vision_purpose=purpose;force dut.normal_done=done;
    force dut.target_valid=target;force dut.pcb_checked=pcb_checked;
    force dut.pcb_status=pcb_status;force dut.pcb_good=pcb_good;
    force dut.defect_count=defects;force dut.defect_boxes=boxes;
    force dut.defect_kinds=kinds;force dut.color_id=color;force dut.shape_id=shape;
    force dut.confidence=confidence;force dut.result_job_id=result_job;
    force dut.grbl_current_start=current_start;force dut.grbl_current_job_id=remote_job;
    force dut.session_id=64'd9;force dut.online=1'b1;force dut.cfg_apply=1'b0;
    force dut.vision_cancel=frame_cancel;force dut.vision_job_cancel=job_cancel;
    force dut.vision_start=vision_start;force dut.vision_busy=1'b0;
    force dut.vision_teach_good=1'b0;force dut.maze_done=1'b0;
    force dut.key4_press=key4;force dut.copy_busy=1'b0;force dut.copy_recovery=1'b0;
    force dut.copy_uart_owner=1'b0;force dut.report_ready=reporter_ready;
    force dut.report_busy=reporter_busy;force dut.report_done=reporter_done;
    force dut.report_error=1'b0;force dut.report_recovery_required=1'b0;
    force dut.report_state=3'd0;force dut.report_lines=32'd0;
    force dut.report_error_code=8'd0;force dut.grbl_test_start=1'b0;
    force dut.uart_link_ready=uart_ready;force dut.uart_rt_ready=1'b1;
    force dut.uart_rt_done=1'b0;force dut.uart_idle_pulse=1'b0;
    force dut.profile_valid=profile_ready;force dut.job_status_ready=1'b1;
    repeat(4)step;rst_n=1;repeat(6)step;dut.key1_lock=0;

    purpose=1;press_key1;
    check(!dut.report_pending&&!dut.pcb_report_cache_valid&&dut.key1_report_id==0,
          "KEY1 without a fresh PCB result does not start writing");

    // A physical KEY1 pulse on the same edge as a new PCB completion must
    // not consume the prior cache or race the cache write.
    @(negedge clk);purpose=1;result_job=32'd9;pcb_status=1;target=1;
    pcb_checked=1;pcb_good=1;defects=0;boxes=0;kinds=0;done=1;
    key1_pulse=1'b1;
    step;
    check(!dut.report_pending&&!dut.key1_job_active&&dut.pcb_report_cache_valid&&
          dut.pcb_report_cache_job==9,
          "same-cycle KEY1 waits for the just-completed PCB snapshot");
    @(negedge clk);done=0;key1_pulse=0;

    complete_pcb(32'd10,2'd0,1,1,1,3'd1,
        {224'd0,16'd20,16'd10},8'h12);
    check(dut.pcb_report_cache_valid && dut.pcb_report_cache_job==10 &&
          dut.pcb_report_cache_judgement==1 && dut.pcb_report_cache_defect_count==1,
          "PCB PASS is cached after completed inference");
    check(!dut.report_pending && !dut.report_busy && dut.report_source!=4,
          "PCB completion does not start writing before local KEY1");

    complete_pcb(32'd11,2'd1,1,1,0,3'd2,
        {192'd0,16'd44,16'd33,16'd22,16'd11},8'h24);
    check(dut.pcb_report_cache_valid && dut.pcb_report_cache_job==11 &&
          dut.pcb_report_cache_judgement==2 && dut.pcb_report_cache_defect_count==2 &&
          dut.pcb_report_cache_boxes=={192'd0,16'd44,16'd33,16'd22,16'd11} &&
          dut.pcb_report_cache_kinds==8'h24,
          "new PCB result atomically replaces older pending snapshot");
    uart_ready=0;
    press_key1;
    check(dut.pcb_report_cache_valid && dut.pcb_report_cache_job==11 &&
          !dut.report_pending && !dut.key1_job_active,
          "UART unavailable KEY1 preserves PCB snapshot without starting write");
    uart_ready=1;profile_ready=0;
    press_key1;
    check(dut.pcb_report_cache_valid && dut.pcb_report_cache_job==11 &&
          !dut.report_pending && !dut.key1_job_active,
          "invalid profile KEY1 preserves PCB snapshot without starting write");
    profile_ready=1;
    reporter_ready=0;reporter_busy=0;
    press_key1;
    check(dut.report_cnn_mode==0 && dut.report_source==0 && dut.report_job==11 &&
          dut.report_judgement==2 && dut.report_defect_count==2 &&
          dut.report_defect_boxes=={192'd0,16'd44,16'd33,16'd22,16'd11} &&
          dut.report_defect_kinds==8'h24,
          "KEY1 admits the exact latched PCB FAIL snapshot");
    check(!dut.pcb_report_cache_valid,"KEY1 consumes the admitted PCB snapshot");
    check(dut.key1_job_active && dut.report_pending,
          "accepted local PCB report enters protected report path");
    begin : duplicate_press
        reg [31:0] accepted_id;
        accepted_id=dut.key1_report_id;
        press_key1;
        check(dut.key1_report_id==accepted_id && dut.report_job==11 &&
              dut.report_defect_boxes=={192'd0,16'd44,16'd33,16'd22,16'd11},
              "additional KEY1 press cannot duplicate active PCB report");
    end

    // An explicit remote Type20 request remains a separate report trigger.
    retire_report;reporter_busy=0;reporter_ready=1;
    @(negedge clk);current_start=1;step;@(negedge clk);current_start=0;
    check(dut.report_pending && dut.report_source==2 && dut.report_cnn_mode,
          "explicit Type20 report trigger remains independent of local KEY1 mode gate");
    retire_report;

    // A new mode/job or no-target completion invalidates the old PCB result.
    complete_pcb(32'd12,2'd1,1,1,1,0,0,0);
    @(negedge clk);purpose=0;vision_start=1;step;
    @(negedge clk);vision_start=0;
    check(!dut.pcb_report_cache_valid,"starting a non-PCB task clears stale PCB snapshot");
    purpose=1;
    press_key1;
    check(!dut.report_pending && dut.key1_report_id==0,
          "returning to PCB purpose cannot write a prior-mode result");

    complete_pcb(32'd13,2'd1,1,1,1,0,0,0);
    complete_pcb(32'd14,2'd0,0,0,0,0,0,0);
    check(!dut.pcb_report_cache_valid,"no-target result invalidates prior PCB snapshot");
    press_key1;
    check(!dut.report_pending && dut.key1_report_id==0,
          "KEY1 after no target does not write stale PCB data");

    complete_pcb(32'd15,2'd2,1,1,0,0,0,0);
    check(dut.pcb_report_cache_valid && dut.pcb_report_cache_judgement==0,
          "PCB REVIEW result remains a reportable snapshot");
    @(negedge clk);job_cancel=1;step;@(negedge clk);job_cancel=0;
    check(!dut.pcb_report_cache_valid,"explicit task cancel clears pending PCB result");
    complete_pcb(32'd16,2'd1,1,1,1,0,0,0);
    @(negedge clk);key4=1;step;@(negedge clk);key4=0;repeat(12)step;
    check(!dut.pcb_report_cache_valid,"KEY4 clears pending PCB result");

    // CNN mode retains its original class/centre/confidence snapshot flow.
    retire_report;purpose=0;repeat(6)step;
    press_key1;
    check(!dut.report_pending&&!dut.key1_job_active,
          "CNN KEY1 before any valid result does not start writing");
    @(negedge clk);color=2;shape=3;confidence=77;target=1;done=1;
    force dut.x0=11;force dut.x1=31;force dut.y0=20;force dut.y1=40;
    step;@(negedge clk);done=0;
    check(dut.cnn_cache_valid && dut.cnn_cache_class==6 &&
          dut.cnn_cache_confidence==77,"ordinary CNN cache still captures class and confidence");
    press_key1;
    check(dut.report_cnn_mode && dut.report_cnn_class==6 &&
          dut.report_cnn_confidence==77 && dut.report_defect_boxes=={224'd0,16'd30,16'd21},
          "CNN purpose KEY1 still writes the cached CNN report");
    retire_report;
    @(negedge clk);target=0;done=1;step;@(negedge clk);done=0;
    press_key1;
    check(!dut.report_pending&&!dut.key1_job_active,
          "CNN no-target result cannot be printed from stale cached object data");

    if(errors!=0)$fatal(1,"PCB_KEY1_REPORT_FAIL checks=%0d errors=%0d",checks,errors);
    $display("PCB_KEY1_REPORT_PASS checks=%0d",checks);$finish;
end
endmodule
