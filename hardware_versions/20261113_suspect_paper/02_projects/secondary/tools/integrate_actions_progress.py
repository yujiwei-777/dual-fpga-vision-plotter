from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'01_rtl/secondary_top.v'
s=p.read_text()
start=s.index('    reg key1_meta,key1_sync,key1_d;')
end=s.index('    // KEY3 is handled',start)
s=s[:start]+'''    wire copy_busy;
    wire key1_short_pulse,key1_airwalk_pulse,key1_fresh_press,key1_held;
    wire key1_can_start;
    wire key1_report_pulse=key1_short_pulse&&!copy_busy;
    wire key1_report_action=(key1_short_pulse||key1_airwalk_pulse)&&!copy_busy;
    secondary_key1_action_ctrl u_key1_action(
        .clk(clk125),.rst_n(rst125_n),.key_n(I_key1_n),
        .can_start(key1_can_start),.context_id(vision_purpose),
        .inhibit(key4_reset_active||key4_press||vision_job_cancel||vision_start),
        .short_pulse(key1_short_pulse),.airwalk_pulse(key1_airwalk_pulse),
        .press_pulse(key1_fresh_press),.held(key1_held));
''' +s[end:]
s=s.replace('wire copy_write_start=key1_fresh_press&&copy_write_waiting','wire copy_write_start=key1_short_pulse&&copy_write_waiting')
insert='''    wire copy_airwalk_start=key1_airwalk_pulse&&copy_write_waiting&&(page_used_cmm==0)&&
        !vision_job_cancel&&!copy_prepare_cancel&&!key4_reset_active&&!key4_stop&&!key4_press&&
        !key2_new_page&&!report_busy;
'''
s=s.replace('    assign key4_copy_reset=',insert+'    assign key4_copy_reset=',1)
s=s.replace('    wire [31:0] copy_operator_job,copy_operator_acked;',
'''    wire [31:0] copy_operator_job,copy_operator_acked,copy_total_lines;
    wire copy_total_valid,copy_airwalk_active,copy_airwalk_done;
''')
s=s.replace('.operator_job_id(copy_operator_job),.operator_acked_lines(copy_operator_acked),',
'''.airwalk_start(copy_airwalk_start),.airwalk_done(copy_airwalk_done),
        .operator_total_lines(copy_total_lines),.operator_total_valid(copy_total_valid),
        .operator_airwalk(copy_airwalk_active),
        .operator_job_id(copy_operator_job),.operator_acked_lines(copy_operator_acked),''')
s=s.replace('    wire [31:0] report_lines;wire [2:0] report_state;',
'''    wire [31:0] report_lines,report_total_lines;
    wire report_total_valid,report_airwalk_active;
    reg report_airwalk;
    wire [2:0] report_state;''')
s=s.replace('wire key1_local_admit=key1_report_pulse','wire key1_local_admit=key1_report_action')
s=s.replace('wire pcb_key1_admit=key1_report_pulse','wire pcb_key1_admit=key1_report_action')
s=s.replace('    wire key1_local_job_accept=',
'''    assign key1_can_start=copy_write_waiting ?
        ((page_used_cmm==0)&&!report_busy&&!report_pending&&!report_recovery_required&&
         !copy_recovery&&!key4_reset_active&&!key4_stop&&uart_link_ready) :
        (key1_report_slot_available&&profile_valid&&uart_link_ready&&
         (!operator_preview_capable||preview_locked)&&
         ((vision_purpose==0&&cnn_cache_result_valid&&cnn_cache_valid&&!cnn_cache_invalid)||
          (vision_purpose==1&&pcb_report_cache_valid&&!pcb_report_cache_invalid)));
    wire key1_local_job_accept=''',1)
s=s.replace('.O_acked_lines(report_lines),.O_job_state(report_state),',
'''.O_acked_lines(report_lines),.O_job_state(report_state),
        .I_airwalk(report_airwalk),.O_total_lines(report_total_lines),
        .O_total_valid(report_total_valid),.O_airwalk_active(report_airwalk_active),''')
s=s.replace('cnn_cache_result_valid<=0;preview_locked<=0;',
            'cnn_cache_result_valid<=0;preview_locked<=0;report_airwalk<=0;',1)
s=s.replace('            if(key1_local_job_accept||',
            '            if((key1_local_job_accept&&!key1_airwalk_pulse)||',1)
s=s.replace('end else if(pcb_key1_admit&&key1_local_job_accept)begin',
            'end else if(pcb_key1_admit&&key1_local_job_accept&&!key1_airwalk_pulse)begin',1)
s=s.replace('                if(grbl_test_start)begin',
            '                if(grbl_test_start)begin\n                    report_airwalk<=0;',1)
s=s.replace('                if(key2_report_start)begin',
            '                if(key2_report_start)begin\n                    report_airwalk<=0;',1)
s=s.replace('                if(grbl_current_start||key1_local_admit||pcb_key1_admit)begin',
'''                if(grbl_current_start||key1_local_admit||pcb_key1_admit)begin
                    report_airwalk<=(key1_local_admit||pcb_key1_admit)&&key1_airwalk_pulse;''',1)
s=s.replace('                if(maze_done&&maze_task)begin',
            '                if(maze_done&&maze_task)begin\n                    report_airwalk<=0;',1)
s=s.replace('!grbl_test_start&&!grbl_current_start&&!maze_done&&!vision_start&&!key1_fresh_press)',
            '!grbl_test_start&&!grbl_current_start&&!maze_done&&!vision_start&&!key1_fresh_press&&!key1_held)')
s=s.replace('    // OPR1 bytes34..43 are reserved zero in this resource-constrained\n    // profile. Detailed UART ACK/recovery state remains local and unchanged.',
'''    // OPR1 progress extension: byte36 flags,37 phase,38..39 ACK count,
    // 40..41 total; unsigned little endian. Counts saturate for the UI only.
    // This is accepted G-code progress, never physical motion completion.
    wire progress_doc=operator_doc_active;
    wire progress_owner=progress_doc||operator_report_active;
    wire [31:0] progress_ack=progress_doc?copy_operator_acked:report_lines;
    wire [31:0] progress_total=progress_doc?copy_total_lines:report_total_lines;
    wire progress_known=progress_doc?copy_total_valid:report_total_valid;
    wire progress_dry=progress_doc?copy_airwalk_active:report_airwalk_active;
    wire [7:0] progress_phase=progress_doc?{5'd0,copy_operator_state}:{5'd0,report_state};
    wire [15:0] progress_ack_ui=(|progress_ack[31:16])?16'hffff:progress_ack[15:0];
    wire [15:0] progress_total_ui=(|progress_total[31:16])?16'hffff:progress_total[15:0];''')
s=s.replace('    assign operator_status_data[319:288]=32\'d0;\n    assign operator_status_data[351:320]=32\'d0;',
'''    assign operator_status_data[295:288]={3'd0,progress_owner&&operator_recovery,
        1'b0,progress_owner&&progress_dry,progress_owner&&progress_known,progress_owner};
    assign operator_status_data[303:296]=progress_owner?progress_phase:8'd0;
    assign operator_status_data[319:304]=progress_owner?progress_ack_ui:16'd0;
    assign operator_status_data[335:320]=(progress_owner&&progress_known)?progress_total_ui:16'd0;
    assign operator_status_data[351:336]=16'd0;''')
p.write_text(s)
print(p)
