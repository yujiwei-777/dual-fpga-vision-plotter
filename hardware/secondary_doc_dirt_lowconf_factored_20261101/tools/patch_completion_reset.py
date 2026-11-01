from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

p=ROOT/'01_rtl/grbl_streamer.v';s=p.read_text()
s=s.replace('REARM_QUERY=19,REARM_WAIT=20,REARM_STATUS=21;', 'REARM_QUERY=19,REARM_WAIT=20,REARM_STATUS=21,DONE_PENDING=22;')
s=s.replace('else if(O_busy && I_stop && state<STOP_DRAIN)begin', 'else if(I_stop && (state<STOP_DRAIN || state==DONE_PENDING))begin')
s=s.replace('state<=STOP_DRAIN;stop_fault<=0;parser_clear<=1;', 'state<=STOP_DRAIN;stop_fault<=0;parser_clear<=1;recovery_required<=1;O_error<=0;O_error_code<=0;')
a=s.index('                            if(last_line)begin')
b=s.index('                            end else state<=LINE;',a)+len('                            end else state<=LINE;')
s=s[:a]+'''                            if(last_line)begin
                                // All normal report paths complete on the
                                // last line ACK. The extra state exposes the
                                // updated ACK counter before O_done pulses.
                                state<=DONE_PENDING;recovery_required<=0;
                            end else state<=LINE;'''+s[b:]
s=s.replace('                    OLD_STATUS:begin', '''                    DONE_PENDING:begin
                        O_done<=1;state<=IDLE;recovery_required<=0;O_error<=0;O_error_code<=0;
                        parser_clear<=1;
                    end
                    OLD_STATUS:begin''')
s=s.replace('STOP_RESET_WAIT:if(I_tx_done)begin state<=IDLE;recovery_required<=1;O_done<=0;end', '''STOP_RESET_WAIT:if(I_tx_done)begin
                        // KEY4 is a safe task reset, not a raw FPGA/POR
                        // reset. Clear/rearm only after a new post-Ctrl-X
                        // Idle status; unknown or Alarm remains locked.
                        state<=REARM_QUERY;recovery_required<=1;O_done<=0;
                        parser_clear<=1;response_timer<=0;
                    end''')
p.write_text(s)

p=ROOT/'01_rtl/doc_grbl_streamer.v';s=p.read_text()
s=s.replace('input wire clk,rst_n,start,cancel,rearm,fault,', 'input wire clk,rst_n,start,cancel,rearm,fault,reset_job,')
s=s.replace('reg first_query,final_idle_seen,stop_seen,query_is_start;', 'reg first_query,final_idle_seen,stop_seen,query_is_start,reset_pending;\n    wire reset_request=(reset_job===1\'b1);')
s=s.replace('first_query<=0;final_idle_seen<=0;stop_seen<=0;query_is_start<=0;', 'first_query<=0;final_idle_seen<=0;stop_seen<=0;query_is_start<=0;reset_pending<=0;')
s=s.replace('if(busy && !cancelling && (cancel || normal_fault))begin', 'if(reset_request || (busy && !cancelling && (cancel || normal_fault)))begin')
s=s.replace('cancel_fault<=!cancel;status_pending<=0;', 'cancel_fault<=!cancel&&!reset_request;reset_pending<=reset_request;status_pending<=0;')
s=s.replace('if(cancel)error_code<=0;', 'if(cancel||reset_request)error_code<=0;')
a=s.index('                        end else if(finish)begin')
b=s.index('                        end\n                    end',a)+len('                        end')
s=s[:a]+'''                        end else if(finish)begin
                            // Producer asserts finish only after the final
                            // line_done. Every line, including return/newline,
                            // has therefore received its own GRBL ok.
                            done<=1;state<=IDLE;terminal_state<=4;
                            recovery_required<=0;error_code<=0;
                            status_pending<=0;parser_clear<=1;
                        end'''+s[b:]
s=s.replace('''                        if(cancel_fault)begin error<=1;terminal_state<=5;end
                        else begin cancelled<=1;terminal_state<=6;end''', '''                        if(reset_pending)begin
                            // A task reset reuses the confirmed stop/reset
                            // sequence, then requires fresh post-reset Idle.
                            state<=R_QUERY;recovery_required<=1;query_ms<=0;response_ms<=0;
                        end else if(cancel_fault)begin error<=1;terminal_state<=5;end
                        else begin cancelled<=1;terminal_state<=6;end''')
s=s.replace('if(p_idle)begin recovery_required<=0;parser_clear<=1;state<=IDLE;end', '''if(p_idle)begin
                                recovery_required<=0;parser_clear<=1;state<=IDLE;error_code<=0;
                                if(reset_pending)begin cancelled<=1;terminal_state<=6;reset_pending<=0;end
                            end''')
p.write_text(s)

p=ROOT/'01_rtl/doc_grbl_plotter.v';s=p.read_text()
s=s.replace('input wire clk,rst_n,start,cancel,rearm,', 'input wire clk,rst_n,start,cancel,rearm,reset_job,')
s=s.replace('.clk(clk),.rst_n(rst_n),.start(start),.cancel(cancel),.rearm(rearm),', '.clk(clk),.rst_n(rst_n),.start(start),.cancel(cancel),.rearm(rearm),.reset_job(reset_job),')
s=s.replace('if(cancel || error || cancelled || done)', 'if(cancel || reset_job===1\'b1 || error || cancelled || done)')
p.write_text(s)

p=ROOT/'01_rtl/doc_copy_pipeline.v';s=p.read_text()
s=s.replace('input wire clk,rst_n,start,cancel,rearm,', 'input wire clk,rst_n,start,cancel,rearm,reset_job,')
s=s.replace('wire children_cancel=cancel||abort_pulse;', "wire reset_request=(reset_job===1'b1);\n    wire children_cancel=cancel||abort_pulse||reset_request;")
s=s.replace('.cancel(children_cancel),.rearm(plot_rearm)', '.cancel(children_cancel),.rearm(plot_rearm),.reset_job(reset_request)')
s=s.replace('end else if(cancel&&state!=IDLE&&state!=ABORT)begin', 'end else if((cancel||reset_request)&&state!=IDLE&&state!=ABORT)begin')
p.write_text(s)

p=ROOT/'01_rtl/secondary_top.v';s=p.read_text()
s=s.replace('KEY4=C7 stop.', 'KEY4=C7 task reset.')
s=s.replace('wire key4_stop=~key4_sync;', '''// A debounced press requests one reset. The normal FPGA, DDR,
    // Ethernet, CNN and model reset domains are deliberately untouched.
    wire key4_stop=key4_press;
    reg key4_reset_active;
    reg [2:0] key4_reset_age;
    wire key4_copy_reset=key4_press&&(copy_uart_owner||copy_busy||copy_recovery);
    wire key4_report_reset=key4_press&&!key4_copy_reset;''')
s=s.replace('.start(vision_start&&copy_task&&!key4_stop)', '.start(vision_start&&copy_task&&!key4_reset_active&&!key4_stop)')
s=s.replace('.cancel(vision_cancel||key4_stop),.rearm(copy_rearm||key3_press)', '.cancel(vision_cancel),.reset_job(key4_copy_reset),.rearm(copy_rearm||key3_press)')
s=s.replace('wire report_job_valid=report_pending||key2_report_pending;', 'wire report_job_valid=(report_pending||key2_report_pending)&&!key4_reset_active&&!key4_stop;')
s=s.replace('wire key1_local_admit=key1_report_pulse&&', 'wire key1_local_admit=key1_report_pulse&&!key4_reset_active&&!key4_stop&&')
s=s.replace('.I_accept(key1_local_job_accept),.I_explicit_cancel(vision_job_cancel)', '.I_accept(key1_local_job_accept),.I_explicit_cancel(vision_job_cancel||key4_press)')
s=s.replace('.I_clk(clk125),.I_rst_n(rst125_n),.I_key_n(I_key2_n),', '.I_clk(clk125),.I_rst_n(rst125_n),.I_key_n(I_key2_n),.I_reset(key4_press),')
s=s.replace('.I_busy(vision_busy||report_busy||report_pending||copy_busy||copy_recovery||copy_uart_owner||cfg_apply)', '.I_busy(vision_busy||report_busy||report_pending||report_recovery_required||copy_busy||copy_recovery||copy_uart_owner||cfg_apply||key4_reset_active||key4_stop)')
s=s.replace('.I_stop(key4_stop),.I_rearm(key3_press)', '.I_stop(key4_report_reset),.I_rearm(key3_press)')
s=s.replace('if(key2_report_fail)key2_report_pending<=0;', '''if(key2_report_fail||report_error||report_recovery_required||key4_press)key2_report_pending<=0;''')
s=s.replace('if(vision_job_cancel||(vision_cancel&&!key2_local_active&&!key1_job_protected))begin', 'if(key4_press||key4_reset_active||vision_job_cancel||(vision_cancel&&!key2_local_active&&!key1_job_protected))begin')
s=s.replace('input wire I_clk,input wire I_rst_n,input wire I_key_n,', 'input wire I_clk,input wire I_rst_n,input wire I_key_n,input wire I_reset,')
s=s.replace('            case(state)\n                K_IDLE:', '''            if(I_reset===1'b1)begin state<=K_IDLE;O_job_fail<=1;wait_count<=0;end
            else case(state)
                K_IDLE:''')
# Keep KEY4's lock until all active stop/reset/rearm handshakes complete. A
# failure leaves recovery asserted and only KEY3 or another reset can retry.
needle='    reg [2:0] report_state_d;reg report_error_d;reg [31:0] report_lines_d;'
insert='''    always @(posedge clk125 or negedge rst125_n)begin
        if(!rst125_n)begin key4_reset_active<=0;key4_reset_age<=0;end
        else if(key4_press)begin key4_reset_active<=1;key4_reset_age<=0;end
        else if(key4_reset_active)begin
            if(key4_reset_age!=7)key4_reset_age<=key4_reset_age+1'b1;
            else if(!report_busy&&!copy_busy&&!copy_uart_owner&&!report_recovery_required&&!copy_recovery)key4_reset_active<=0;
        end
    end
'''
s=s.replace(needle,insert+needle)
s=s.replace('// ok and the final fresh Idle response is required.', '// ok; the last ok completes the report without a final Idle poll.')
p.write_text(s)
print('patched completion and safe task-reset control')
