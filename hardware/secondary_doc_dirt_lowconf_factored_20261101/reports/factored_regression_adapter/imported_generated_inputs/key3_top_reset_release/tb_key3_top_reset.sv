`timescale 1ns/1ps
module tb_key3_top_reset;
reg clk=0,key1=1,key2=1,key3=1,key4=1;
always #10 clk=~clk;
integer checks=0,errors=0,reset_edges=0;
secondary_top dut(.I_sys_clk(clk),.I_sw2(1'b0),.I_key1_n(key1),.I_key2_n(key2),
    .I_key3_n(key3),.I_key4_n(key4),.I_rgmii_rxd(4'd0),.I_rgmii_rx_ctl(1'b0),
    .I_rgmii_rxc(clk),.I_uart_rx(1'b1),.I_esp_link_ready(1'b0));
// Accelerate only the two button timers. The separate supervisor suite runs
// the exact production 1,000,000-cycle KEY3 setting as well.
defparam dut.u_board_reset.DEBOUNCE_CYCLES=4;
defparam dut.u_key2_test.CLK_HZ=200;
task step;begin @(posedge clk);#1;end endtask
task check(input bit pass,input string message);begin
    checks=checks+1;
    if(!pass)begin errors=errors+1;$display("FAIL %s",message);end
    else $display("PASS %s",message);
end endtask
always @(negedge dut.board_release)reset_edges=reset_edges+1;
task settle_boot;begin
    repeat(16)step;
    check(dut.board_release===1 && dut.rst125_n===1 && dut.store_rstddr_n===1,
          "release restarts both modeled PLLs and synchronizes application domains");
end endtask
task assert_key3;begin
    @(negedge clk);key3=0;
    // Seed live state at the final pre-reset edge. These are deposits, not
    // forced reset outputs: the production reset branches must clear them.
    wait(dut.u_board_reset.key_sample===0 && dut.u_board_reset.stable_count==3);
    @(negedge clk);
    dut.cnn_cache_valid=1;dut.cnn_cache_class=7;dut.cnn_cache_confidence=99;
    dut.cnn_cache_center_x=333;dut.cnn_cache_center_y=222;
    dut.report_pending=1;dut.key2_report_pending=1;
    dut.report_cnn_class=7;dut.report_job=32'd1234;
    dut.u_key1_job_guard.O_active=1;
    dut.u_reporter.newline_offset_cmm=16'd2500;
    dut.u_reporter.u_stream.recovery_required=1;
    dut.u_link.online=1;dut.u_link.session_id=64'h123456789abcdef0;
    dut.u_link.frame_active=1;dut.u_link.completed_valid=1;
    @(negedge dut.board_release);#1;
    check(dut.rst125_n===0 && dut.store_rst125_n===0 && dut.store_rstddr_n===0,
          "KEY3 asynchronously asserts both application reset domains");
    check(dut.u_eth_pll.reset===1 && dut.u_ddr_ref_pll.reset===1 && dut.u_ddr.I_sys_rst_n===0,
          "KEY3 asserts Ethernet PLL, DDR reference PLL and DDR IP reset");
    check(dut.O_phy_rst===0 && dut.rgmii_rx_rst_n===0 && dut.stack_reset===1,
          "PHY, receive synchronizer and MAC reset follow whole-board reset");
    check(dut.u_vision.rst_n===0 && dut.u_copy.rst_n===0 && dut.u_configuration.I_rst_n===0 &&
          dut.u_link.rst_n===0 && dut.u_store.rst_n===0 && dut.u_store.ddr_rst_n===0,
          "CNN/PCB, document, configuration, HXA and both DDR mailbox ends receive reset");
    check(dut.cnn_cache_valid===0 && dut.cnn_cache_class==0 && dut.cnn_cache_confidence==0 &&
          dut.cnn_cache_center_x==0 && dut.cnn_cache_center_y==0,
          "reset invalidates classification cache and center coordinates");
    check(dut.report_pending===0 && dut.key2_report_pending===0 && dut.report_job==0 &&
          dut.key1_job_active===0 && dut.key2_local_active===0,
          "reset clears pending jobs and accepted local job ownership");
    check(dut.u_link.online===0 && dut.u_link.session_id==0 && dut.u_link.frame_active===0 &&
          dut.u_link.completed_valid===0 && dut.u_link.vision_start===0,
          "real HXA reset invalidates session, partial frame and completed-frame validity");
    check(dut.u_reporter.newline_offset_cmm==0 && dut.report_recovery_required===0 &&
          dut.report_busy===0 && dut.uart_link_ready===0 && dut.O_uart_tx===1,
          "real reporter cursor resets and UART restarts closed and idle high");
end endtask
initial begin
    // Deterministic inactive image/physical models; HXA and report/UART reset
    // state run in the real RTL rather than being forced by the test.
    force dut.udp_busy=0;force dut.rx_valid=0;force dut.rx_data=0;force dut.rx_len=0;
    force dut.rx_source_port=16'd6002;force dut.ip_error=0;force dut.mac_error=0;
    force dut.gmii_rx_clk=clk;force dut.phy_link_raw=1;
    force dut.wr_ready=1;force dut.wr_idle=1;force dut.rd_ready=1;force dut.rd_valid=0;force dut.rd_data=0;
    force dut.normal_busy=0;force dut.normal_done=0;force dut.normal_reader_request=0;
    force dut.normal_reader_invalidate=0;force dut.color_word_active=0;force dut.normal_rd_req=0;
    force dut.copy_busy=0;force dut.copy_done=0;force dut.copy_recovery=0;force dut.copy_uart_owner=0;
    force dut.copy_status_valid=0;force dut.copy_reader_request=0;force dut.copy_reader_invalidate=0;
    force dut.copy_tx_valid=0;force dut.copy_rt_valid=0;force dut.copy_rearm=0;
    force dut.station_valid=0;force dut.station_header=0;force dut.cfg_apply=0;
    force dut.cfg_ack=0;force dut.cfg_error=0;force dut.profile_valid=1;
    repeat(4)step;
    force dut.por_count=20'hfffff;
    step;release dut.por_count;
    settle_boot;
    check(dut.uart_link_ready===0 && dut.u_reporter.I_rearm===0,
          "boot does not treat KEY3 as GRBL rearm or assume UART ready");
    assert_key3;
    repeat(50)step;
    check(dut.board_release===0 && dut.rst125_n===0,
          "long KEY3 hold keeps all application logic reset without restart loops");
    @(negedge clk);key3=1;
    settle_boot;
    repeat(100)step;
    check(dut.report_pending===0 && dut.key2_report_pending===0 && !dut.key1_job_active &&
          !dut.report_busy && dut.report_tx_valid===0 && dut.copy_task===0 && dut.u_link.vision_start===0,
          "release does not restore cached report, old G-code or completed image transaction");
    // Keys held across reset must not be converted into a new print request.
    @(negedge clk);key1=0;key2=0;
    assert_key3;
    @(negedge clk);key3=1;
    settle_boot;
    // Wait through the actual 2.5M-cycle KEY1 lock, rather than bypassing it.
    repeat(2500020)step;
    check(dut.key1_report_pulse===0 && dut.key2_report_start===0 && !dut.key2_local_active &&
          !dut.report_pending && !dut.key2_report_pending,
          "KEY1/KEY2 held through reset do not start jobs after boot lock expires");
    @(negedge clk);key1=1;key2=1;
    repeat(12)step;
    check(dut.u_key2_test.key_debounced===1,
          "debounced release rearms KEY2 after whole-board reset");
    // KEY4 retains its independent task-reset input and does not reset DDR.
    force dut.key4_db_count=22'd2500000;
    @(negedge clk);key4=0;
    repeat(5)step;
    release dut.key4_db_count;
    check(dut.board_release===1 && dut.rst125_n===1,
          "KEY4 still affects task reset rather than whole-board reset");
    check(reset_edges>=2,"two physical KEY3 presses each produce one board reset");
    if(errors)$fatal(1,"KEY3_TOP_RESET_FAIL checks=%0d errors=%0d",checks,errors);
    $display("PASS KEY3_TOP_RESET_ALL checks=%0d",checks);$finish;
end
initial begin #100000000;$fatal(1,"KEY3 top reset timeout");end
endmodule
