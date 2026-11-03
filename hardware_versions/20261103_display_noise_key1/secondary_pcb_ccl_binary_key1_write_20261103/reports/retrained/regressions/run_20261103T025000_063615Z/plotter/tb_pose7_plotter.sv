`timescale 1ns/1ps
// Unit regression for the inherited shared UART transport. Network acceptance
// and top-level HXA cancellation routing require separate integrated tests.
module tb_pose7_plotter;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,doc_owner=0,report_claim=0,link_ready=1;
    reg tx_enable=1,tx_done=0,rx_valid=0,rx_error=0;
    reg [7:0] rx_data=0;
    wire [7:0] tx_data,rt_data;
    wire tx_valid,rt_valid;
    reg uart_busy=0;
    integer uart_delay=0,tx_bytes=0,tx_lines=0,queries=0,holds=0,resets=0;
    wire tx_ready=tx_enable&&!uart_busy;
    wire rt_ready=!uart_busy;
    reg R_start=0,R_clear=0,R_abort=0,R_stop=0,R_rearm=0,R_cancel=0,R_fault=0,R_reset_job=0;
    reg [511:0] R_line=0;reg [6:0] R_length=0;reg R_line_valid=0,R_line_last=0,R_finish=0;
    wire R_available,R_line_ready,R_line_done,R_busy,R_done,R_error,R_cancelled,R_recovery_required;
    wire [7:0] R_error_code;wire [31:0] R_acked_lines;wire [2:0] R_job_state;wire R_rt_done;
    reg D_start=0,D_clear=0,D_abort=0,D_stop=0,D_rearm=0,D_cancel=0,D_fault=0,D_reset_job=0;
    reg [511:0] D_line=0;reg [6:0] D_length=0;reg D_line_valid=0,D_line_last=0,D_finish=0;
    wire D_available,D_line_ready,D_line_done,D_busy,D_done,D_error,D_cancelled,D_recovery_required;
    wire [7:0] D_error_code;wire [31:0] D_acked_lines;wire [2:0] D_job_state;wire D_rt_done;
    reg R_fmt_start=0,D_fmt_start=0;
    wire [511:0] R_fmt_line,D_fmt_line;wire [6:0] R_fmt_length,D_fmt_length;
    wire R_fmt_done,D_fmt_done,R_fmt_busy,D_fmt_busy;
    grbl_shared_transport_candidate #(.CLK_HZ(1000),.REPORT_ACK_TIMEOUT_CYCLES(200),
        .REPORT_STATUS_TIMEOUT_CYCLES(1000),.DOC_QUERY_MS(500),.DOC_STATUS_MS(1000),
        .DOC_FINAL_MS(10000),.DOC_PROGRESS_MS(300),.DOC_JOB_MS(200000)) dut(
        .clk(clk),.rst_n(rst_n),.I_doc_owner(doc_owner),.I_report_claim(report_claim),
        .link_ready(link_ready),.tx_ready(tx_ready),.tx_done(tx_done),.rt_ready(rt_ready),
        .rx_data(rx_data),.rx_valid(rx_valid),.rx_error(rx_error),.tx_data(tx_data),.tx_valid(tx_valid),.rt_data(rt_data),.rt_valid(rt_valid),
        .R_start(R_start),.R_clear(R_clear),.R_abort(R_abort),.R_stop(R_stop),.R_rearm(R_rearm),.R_cancel(R_cancel),
        .R_fault(R_fault),.R_reset_job(R_reset_job),.R_profile_valid(1'b1),.R_fault_code(8'h55),
        .R_line(R_line),.R_length(R_length),.R_line_valid(R_line_valid),.R_line_last(R_line_last),.R_finish(R_finish),
        .R_available(R_available),.R_line_ready(R_line_ready),.R_line_done(R_line_done),.R_busy(R_busy),.R_done(R_done),
        .R_error(R_error),.R_cancelled(R_cancelled),.R_recovery_required(R_recovery_required),.R_error_code(R_error_code),
        .R_acked_lines(R_acked_lines),.R_job_state(R_job_state),.R_rt_done(R_rt_done),
        .R_fmt_start(R_fmt_start),.R_fmt_kind(2'd0),.R_fmt_x(16'd1000),.R_fmt_y(16'd1000),.R_fmt_z(16'd0),.R_fmt_feed(16'd3000),.R_fmt_pwm(16'd1000),
        .R_fmt_line(R_fmt_line),.R_fmt_length(R_fmt_length),.R_fmt_done(R_fmt_done),.R_fmt_busy(R_fmt_busy),
        .D_start(D_start),.D_clear(D_clear),.D_abort(D_abort),.D_stop(D_stop),.D_rearm(D_rearm),.D_cancel(D_cancel),
        .D_fault(D_fault),.D_reset_job(D_reset_job),.D_profile_valid(1'b1),.D_fault_code(8'h66),
        .D_line(D_line),.D_length(D_length),.D_line_valid(D_line_valid),.D_line_last(D_line_last),.D_finish(D_finish),
        .D_available(D_available),.D_line_ready(D_line_ready),.D_line_done(D_line_done),.D_busy(D_busy),.D_done(D_done),
        .D_error(D_error),.D_cancelled(D_cancelled),.D_recovery_required(D_recovery_required),.D_error_code(D_error_code),
        .D_acked_lines(D_acked_lines),.D_job_state(D_job_state),.D_rt_done(D_rt_done),
        .D_fmt_start(D_fmt_start),.D_fmt_kind(2'd0),.D_fmt_x(16'd1000),.D_fmt_y(16'd1000),.D_fmt_z(16'd0),.D_fmt_feed(16'd3000),.D_fmt_pwm(16'd1000),
        .D_fmt_line(D_fmt_line),.D_fmt_length(D_fmt_length),.D_fmt_done(D_fmt_done),.D_fmt_busy(D_fmt_busy));
    string case_name="initial";
    integer scenarios=0;
    task fail(input string message);
        begin $display("PLOTTER_FAIL case=%s state=%0d %s",case_name,dut.state,message);$fatal(1,"shared transport regression failed");end
    endtask
    task pass;
        begin scenarios=scenarios+1;$display("PLOTTER_CASE_PASS name=%s",case_name);end
    endtask
    always @(posedge clk)begin
        if(!rst_n)begin uart_busy<=0;uart_delay<=0;tx_done<=0;end
        else begin
            tx_done<=0;
            if(uart_busy)begin
                if(uart_delay==0)begin uart_busy<=0;tx_done<=1;end
                else uart_delay<=uart_delay-1;
            end else if(tx_valid&&tx_ready)begin
                uart_busy<=1;uart_delay<=2;tx_bytes=tx_bytes+1;
                if(tx_data==8'h0a)tx_lines=tx_lines+1;
            end else if(rt_valid&&rt_ready)begin
                uart_busy<=1;uart_delay<=2;
                if(rt_data==8'h3f)queries=queries+1;
                if(rt_data==8'h21)holds=holds+1;
                if(rt_data==8'h18)resets=resets+1;
            end
            if(R_busy&&D_busy)fail("both producers own shared transport");
        end
    end
    task tick(input integer count);begin repeat(count)@(negedge clk);end endtask
    task send_rx(input string text);
        begin
            for(integer j=0;j<text.len();j=j+1)begin
                @(negedge clk);rx_data=text.getc(j);rx_valid=1;
            end
            // One propagation cycle exposes parser pulses to the transport
            // without swallowing its one-cycle normal-completion pulse.
            @(negedge clk);rx_valid=0;tick(1);
        end
    endtask
    task reset_transport;
        begin
            @(negedge clk);rst_n=0;R_start=0;R_clear=0;R_stop=0;R_rearm=0;R_abort=0;
            D_start=0;D_reset_job=0;D_rearm=0;D_cancel=0;doc_owner=0;report_claim=0;
            R_line_valid=0;D_line_valid=0;D_finish=0;link_ready=1;tx_enable=1;rx_valid=0;
            tick(3);rst_n=1;tick(3);
        end
    endtask
    task wait_state(input integer target,input integer limit);
        integer n;
        begin n=0;while(dut.state!=target&&n<limit)begin tick(1);n=n+1;end
            if(dut.state!=target)fail($sformatf("wait state %0d timeout",target));end
    endtask
    task start_report;
        integer n;
        begin
            report_claim=1;n=0;
            while(!R_available&&n<100)begin tick(1);n=n+1;end
            if(!R_available)fail("report not available");
            @(negedge clk);R_start=1;tick(1);R_start=0;wait_state(dut.R_LINE,20);
        end
    endtask
    task start_document;
        begin
            doc_owner=1;tick(3);D_start=1;tick(1);D_start=0;
            wait_state(dut.D_FINAL_STATUS,100);tick(3);send_rx("<Idle|MPos:0,0,0>\n");
            wait_state(dut.D_READY,30);
        end
    endtask
    task report_line(input string text,input bit last);
        begin
            if(!R_line_ready)fail("report producer sent without ready");
            R_line=0;for(integer j=0;j<text.len();j=j+1)R_line[j*8+:8]=text.getc(j);
            R_length=text.len();R_line_last=last;R_line_valid=1;tick(1);R_line_valid=0;
            wait_state(dut.R_ACK,500);tick(3);
        end
    endtask
    task document_line(input string text);
        begin
            if(!D_line_ready)fail("doc producer sent without ready");
            D_line=0;for(integer j=0;j<text.len();j=j+1)D_line[j*8+:8]=text.getc(j);
            D_length=text.len();D_line_valid=1;tick(1);D_line_valid=0;
            wait_state(dut.D_ACK_WAIT,500);tick(3);
        end
    endtask
    task check_report_done(input integer expected_acks,input integer initial_queries);
        integer n;
        begin
            n=0;while(!R_done&&n<20)begin tick(1);n=n+1;end
            if(!R_done||R_recovery_required||R_error||R_acked_lines!=expected_acks)fail("report final ok did not complete cleanly");
            if(queries!=initial_queries)fail("report normal completion queried final Idle");
            report_claim=0;tick(5);
        end
    endtask
    task normal_report(input string name,input bit hold_uart);
        integer q0,b0;reg[7:0] byte0;
        begin
            case_name=name;q0=queries;start_report();
            if(hold_uart)tx_enable=0;
            R_line=0;R_line[7:0]="G";R_line[15:8]="0";R_length=2;R_line_last=1;R_line_valid=1;tick(1);R_line_valid=0;
            if(hold_uart)begin
                wait_state(dut.R_SEND,20);b0=tx_bytes;byte0=tx_data;tick(20);
                if(tx_bytes!=b0||!tx_valid||tx_data!==byte0)fail("unaccepted UART byte advanced or disappeared");
                tx_enable=1;
            end
            // Withdraw producer claim only after acceptance. Registered owner
            // must keep this task; this is not an HXA end-to-end test.
            report_claim=0;
            wait_state(dut.R_ACK,100);tick(3);send_rx("ok\n");check_report_done(1,q0);pass();
        end
    endtask
    task rearm_report;
        begin
            report_claim=1;R_rearm=1;tick(1);R_rearm=0;wait_state(dut.R_REARM_STATUS,100);
            tick(3);if(!R_recovery_required)fail("rearm used stale machine state");
            send_rx("<Idle|MPos:0,0,0>\n");wait_state(dut.R_IDLE,30);
            if(R_recovery_required)fail("fresh Idle failed to rearm");report_claim=0;tick(5);
        end
    endtask
    initial begin
        reset_transport();normal_report("KEY2_first_final_ok_no_Idle",0);
        normal_report("KEY2_second_no_KEY3_uart_unaccepted_retry",1);
        case_name="CNN_PCB_multiline_ack_serialization";
        begin integer q0,b0;q0=queries;start_report();report_line("G0 X10 Y10",0);
            b0=tx_bytes;tick(10);if(tx_bytes!=b0)fail("new motion without prior ok");
            send_rx("ok\n");wait_state(dut.R_LINE,20);report_line("G1 X15 Y15",1);
            send_rx("ok\n");check_report_done(2,q0);pass();end
        case_name="DOC_final_ok_owner_withdrawal_no_final_Idle";
        begin integer q0,n;start_document();q0=queries;document_line("G1 X20 Y20");doc_owner=0;
            send_rx("ok\n");wait_state(dut.D_READY,20);
            if(D_acked_lines!=1)fail("doc ack count mismatch");
            D_finish=1;tick(1);D_finish=0;n=0;while(!D_done&&n<20)begin tick(1);n=n+1;end
            if(!D_done||D_recovery_required||D_error||queries!=q0)fail("doc final ok did not finish without Idle");
            tick(5);pass();end
        normal_report("KEY2_after_DOC_owner_switch",0);
        case_name="DOC_lost_ok_no_motion_replay_safe_stop";
        begin integer b0,l0;start_document();document_line("G1 X22 Y22");b0=tx_bytes;l0=tx_lines;
            wait_state(dut.D_C_STATUS,500);tick(3);
            if(!D_recovery_required||tx_bytes!=b0||tx_lines!=l0)fail("doc lost ok did not lock without motion replay");
            send_rx("<Hold:0|MPos:0,0,0>\n");wait_state(dut.D_IDLE,100);
            if(!D_recovery_required)fail("doc lost ok auto-rearmed");
            D_rearm=1;tick(1);D_rearm=0;wait_state(dut.D_R_STATUS,100);tick(3);
            send_rx("<Idle|MPos:0,0,0>\n");wait_state(dut.D_IDLE,30);
            if(D_recovery_required||tx_bytes!=b0)fail("doc recovery replayed old payload");
            doc_owner=0;tick(5);pass();end
        case_name="REPORT_lost_ok_no_motion_replay";
        begin integer b0,l0;start_report();report_line("G1 X25 Y25",1);b0=tx_bytes;l0=tx_lines;
            tick(220);if(!R_error||!R_recovery_required||R_error_code!=3)fail("lost ok did not lock");
            if(tx_bytes!=b0||tx_lines!=l0)fail("lost ok replayed motion");pass();rearm_report();end
        case_name="REPORT_KEY4_stop_Hold_reset_fresh_Idle";
        begin integer b0;start_report();report_line("G1 X30 Y30",1);R_stop=1;tick(1);R_stop=0;b0=tx_bytes;
            wait_state(dut.R_STOP_STATUS,100);tick(3);send_rx("<Hold:0|MPos:0,0,0>\n");
            wait_state(dut.R_REARM_STATUS,100);tick(3);
            if(!R_recovery_required)fail("KEY4 reset rearmed before fresh post-reset Idle");
            send_rx("<Idle|MPos:0,0,0>\n");wait_state(dut.R_IDLE,30);
            if(R_recovery_required||tx_bytes!=b0)fail("stop rearmed incorrectly or replayed payload");
            report_claim=0;tick(5);pass();end
        case_name="REPORT_Alarm_rearm_required";start_report();report_line("G1 X35 Y35",1);
        send_rx("ALARM:1\n");if(!R_error||!R_recovery_required)fail("Alarm not locked");pass();rearm_report();
        case_name="REPORT_Reset_invalidates_coordinates";start_report();report_line("G1 X40 Y40",1);
        send_rx("Grbl 1.1h ['$' for help]\n");if(!R_error||!R_recovery_required||R_error_code!=9)fail("Reset not locked");pass();rearm_report();
        case_name="REPORT_UART_ready_loss_is_fault";start_report();report_line("G1 X45 Y45",1);
        link_ready=0;tick(3);if(!R_error||!R_recovery_required||R_error_code!=2)fail("UART ready loss not locked");
        link_ready=1;pass();rearm_report();
        case_name="DOC_KEY4_reset_Hold_fresh_Idle";
        begin integer b0;start_document();document_line("G1 X50 Y50");D_reset_job=1;tick(1);D_reset_job=0;b0=tx_bytes;
            wait_state(dut.D_C_STATUS,100);tick(3);send_rx("<Hold:0|MPos:0,0,0>\n");
            wait_state(dut.D_R_STATUS,100);tick(3);if(!D_recovery_required)fail("doc reset bypassed fresh Idle");
            send_rx("<Idle|MPos:0,0,0>\n");wait_state(dut.D_IDLE,30);
            if(D_recovery_required||tx_bytes!=b0)fail("doc stop rearmed incorrectly or replayed payload");
            doc_owner=0;tick(5);pass();end
        normal_report("KEY2_after_DOC_stop_recovery",0);
        $display("POSE7_PLOTTER_REGRESSION_PASS cases=%0d lines=%0d queries=%0d holds=%0d resets=%0d",scenarios,tx_lines,queries,holds,resets);
        $finish;
    end
    initial begin #10000000;$fatal(1,"plotter global timeout");end
endmodule
