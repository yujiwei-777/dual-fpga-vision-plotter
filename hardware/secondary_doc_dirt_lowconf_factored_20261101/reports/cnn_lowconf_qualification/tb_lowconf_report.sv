`timescale 1ns/1ps
module tb_cnn_named_report;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, job_valid=0, cnn_mode=1, local_test=0,stop=0;
    reg expected_error=0,safety_mode=0;
    reg [31:0] job_id=0;
    reg [15:0] cnn_class=0;
    reg [7:0] confidence=0;
    reg [1:0] judgement=2;
    reg [255:0] boxes=0;
    wire ready,busy,done,error,recovery,tx_valid,rt_valid;
    wire [7:0] error_code,tx_data,rt_data;
    wire [31:0] acked;
    reg tx_done=0,rx_valid=0;
    reg [7:0] rx_data=0;
    integer trace_fd,gcode_fd,meta_fd,active_job=0,line_count=0,done_count=0;
    integer ack_delay=0,rt_count=0,start_lines,start_done;
    integer rx_read=0,rx_write=0,query_count=0,safety_fd;
    reg [7:0] responses[0:65535];
    reg [7:0] realtime_log[0:15];
    string line="";
    grbl_reporter #(.CLK_HZ(1000),.ACK_TIMEOUT_CYCLES(1000),
        .STATUS_TIMEOUT_CYCLES(1000),.MAZE_ENABLE(0),.AUTO_NEWLINE(1)) dut(
        .I_clk(clk),.I_rst_n(rst_n),.I_clear(1'b0),.I_abort(1'b0),.I_stop(stop),.I_rearm(1'b0),
        .I_job_valid(job_valid),.I_job_id(job_id),.I_session_id(64'd77),.I_job_source(3'd1),
        .I_judgement(judgement),.I_defect_count(3'd0),.I_defect_boxes(boxes),.I_defect_kinds(8'd0),
        .I_maze_mode(1'b0),.I_maze_status(2'd0),.I_maze_steps(9'd0),.I_maze_start(8'd0),
        .I_maze_goal(8'd0),.I_maze_endpoint(8'd0),.I_maze_directions(512'd0),.I_maze_walls(1024'd0),
        .O_job_ready(ready),.O_busy(busy),.O_done(done),.O_error(error),.O_error_code(error_code),
        .O_acked_lines(acked),.O_job_state(),.O_recovery_required(recovery),
        .O_rt_data(rt_data),.O_rt_valid(rt_valid),.I_rt_ready(1'b1),.O_rt_done(),
        .I_link_ready(1'b1),.I_profile_valid(1'b1),.I_pen_pwm_mode(1'b0),
        .I_origin_x_cmm(16'd1000),.I_origin_y_cmm(16'd1000),
        .I_work_x_cmm(16'd19000),.I_work_y_cmm(16'd29700),.I_step_cmm(8'd60),
        .I_pen_up_cmm(-16'sd120),.I_pen_down_cmm(16'sd500),.I_pen_up_pwm(16'd0),.I_pen_down_pwm(16'd1000),
        .I_travel_feed(16'd7000),.I_draw_feed(16'd3000),.I_pen_feed(16'd1200),
        .O_tx_data(tx_data),.O_tx_valid(tx_valid),.I_tx_ready(1'b1),.I_tx_done(tx_done),
        .I_rx_data(rx_data),.I_rx_valid(rx_valid),.I_rx_error(1'b0),
        .I_cnn_mode(cnn_mode),.I_cnn_class(cnn_class),.I_cnn_confidence(confidence),.I_local_test(local_test));

    task enqueue(input string text);
        integer i;
        begin for(i=0;i<text.len();i=i+1)begin responses[rx_write]=text.getc(i);rx_write=rx_write+1;end end
    endtask
    always @(posedge clk) begin
        tx_done<=0;rx_valid<=0;
        if(!rst_n)begin ack_delay=0;line="";rx_read=0;rx_write=0;end
        else begin
            if(tx_valid)begin
                tx_done<=1;
                if(tx_data==10)begin
                    $fdisplay(gcode_fd,"%0d|%s",active_job,line);
                    line="";line_count=line_count+1;ack_delay=8;enqueue("ok\012");
                end else line={line,tx_data};
            end
            if(ack_delay>0)ack_delay=ack_delay-1;
            else if(rx_read<rx_write)begin
                rx_data<=responses[rx_read];rx_valid<=1;rx_read=rx_read+1;
            end
            if(done)done_count=done_count+1;
            if(rt_valid)begin
                if(!safety_mode)$fatal(1,"normal task emitted realtime query");
                realtime_log[rt_count]=rt_data;rt_count=rt_count+1;tx_done<=1;ack_delay=8;
                if(rt_data=="?")begin
                    if(query_count==0)enqueue("<Hold:0|MPos:0,0,0>\012");
                    else enqueue("<Idle|MPos:0,0,0>\012");
                    query_count=query_count+1;
                end
            end
            if(error&&!expected_error)$fatal(1,"report error %0d for job %0d",error_code,active_job);
        end
    end
    always @(negedge clk)begin
        if(rst_n && dut.state==62)
            $fdisplay(trace_fd,"%0d|%0d|%0d|%0d",active_job,dut.report_line,dut.glyph_index,dut.decoded_char);
    end
    task reset_dut;
        begin
            @(negedge clk);rst_n=0;job_valid=0;stop=0;expected_error=0;safety_mode=0;
            repeat(5)@(negedge clk);rst_n=1;
            repeat(8)@(negedge clk);
        end
    endtask
    task reject_full_page;
        integer timeout;
        begin
            @(negedge clk);active_job=34;job_id=34;cnn_class=4;confidence=66;
            judgement=2;cnn_mode=1;local_test=0;boxes={224'd0,16'd110,16'd210};
            repeat(3)@(negedge clk);
            if(!ready)$fatal(1,"page preflight admission unavailable");
            start_lines=line_count;expected_error=1;job_valid=1;
            @(negedge clk);job_valid=0;timeout=0;
            while(!error&&timeout<1000)begin @(negedge clk);timeout=timeout+1;end
            repeat(5)@(negedge clk);
            if(!error||error_code!=12||line_count!=start_lines||busy||dut.newline_offset_cmm!=26780)
                $fatal(1,"page exhaustion emitted command or failed wrong");
            $fdisplay(safety_fd,"CAPACITY|13|14|12|0|26780");
            $display("PASS 13 complete CNN reports fit; 14th rejected before any command");
        end
    endtask
    task stop_final_text_line;
        integer timeout,old_rt;
        begin
            @(negedge clk);active_job=35;job_id=35;cnn_class=4;confidence=66;
            judgement=2;cnn_mode=1;local_test=0;boxes={224'd0,16'd110,16'd210};
            repeat(3)@(negedge clk);
            if(!ready)$fatal(1,"stop test admission unavailable");
            safety_mode=1;query_count=0;old_rt=rt_count;start_done=done_count;
            job_valid=1;@(negedge clk);job_valid=0;
            wait(dut.report_line==2 && tx_valid);
            @(negedge clk);stop=1;start_lines=line_count;
            @(negedge clk);stop=0;
            timeout=0;
            while(busy&&timeout<10000)begin @(negedge clk);timeout=timeout+1;end
            repeat(20)@(negedge clk);
            if(timeout>=10000||recovery||error||done_count!=start_done||line_count!=start_lines)
                $fatal(1,"stop final text line failed or emitted extra commands");
            if(rt_count-old_rt!=4||realtime_log[old_rt]!="!"||realtime_log[old_rt+1]!="?"||
               realtime_log[old_rt+2]!=24||realtime_log[old_rt+3]!="?")
                $fatal(1,"stop/reset/fresh-status sequence mismatch");
            $fdisplay(safety_fd,"STOP|2|4|0|0|0");
            $display("PASS stop during CONF line: no new G-code, no DONE, Hold/reset/fresh Idle verified");
        end
    endtask
    task run_job(input integer ident,input integer cls,input integer conf,input integer valid_target,
                 input integer is_cnn,input integer test_square,input integer mutate);
        integer timeout,start_offset;
        begin
            @(negedge clk);
            active_job=ident;job_id=ident;cnn_class=cls;confidence=conf;cnn_mode=is_cnn;local_test=test_square;
            judgement=valid_target;boxes={224'd0,16'd110,16'd210};
            if(ident==12)boxes={224'd0,16'd359,16'd639};
            repeat(3)@(negedge clk);
            timeout=0;
            while(!ready && timeout<100)begin @(negedge clk);timeout=timeout+1;end
            if(!ready)$fatal(1,"job not admitted %0d",ident);
            start_offset=dut.newline_offset_cmm;start_lines=line_count;start_done=done_count;
            job_valid=1;@(negedge clk);job_valid=0;
            if(mutate)begin cnn_class=9;confidence=1;boxes=0;judgement=0;end
            timeout=0;
            while((busy || done_count==start_done) && timeout<500000)begin @(negedge clk);timeout=timeout+1;end
            if(timeout>=500000)$fatal(1,"job timeout %0d",ident);
            repeat(3)@(negedge clk);
            if(recovery || acked!=line_count-start_lines)$fatal(1,"ack/recovery mismatch job %0d",ident);
            $fdisplay(meta_fd,"%0d|%0d|%0d|%0d|%0d|%0d|%0d|%0d|%0d",ident,cls,conf,valid_target,is_cnn,test_square,
                start_offset,dut.newline_offset_cmm,line_count-start_lines);
            $display("PASS job %0d class %0d, %0d acknowledged lines",ident,cls,line_count-start_lines);
        end
    endtask
    integer c;
    initial begin
        trace_fd=$fopen("glyph_trace.txt","w");gcode_fd=$fopen("gcode.txt","w");meta_fd=$fopen("jobmeta.txt","w");
        safety_fd=$fopen("safety_trace.txt","w");
        reset_dut;run_job(401,1,7,2,1,0,0);
        reset_dut;run_job(402,2,7,2,1,0,0);
        reset_dut;run_job(403,3,7,2,1,0,0);
        reset_dut;run_job(404,4,7,2,1,0,0);
        reset_dut;run_job(405,5,7,2,1,0,0);
        reset_dut;run_job(406,6,7,2,1,0,0);
        reset_dut;run_job(407,7,7,2,1,0,0);
        reset_dut;run_job(408,8,7,2,1,0,0);
        reset_dut;run_job(409,9,7,2,1,0,0);
        reset_dut;run_job(410,5,1,2,1,0,0);
        reset_dut;run_job(411,5,0,2,1,0,0);
        reset_dut;run_job(412,5,100,2,1,0,0);
        $fclose(trace_fd);$fclose(gcode_fd);$fclose(meta_fd);$fclose(safety_fd);
        $display("PASS LOWCONF_NAMED_REPORT_12");$finish;
    end
    initial begin #1000000000;$fatal(1,"global timeout");end
endmodule
