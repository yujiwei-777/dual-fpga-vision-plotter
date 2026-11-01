from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'02_sim/doc_plotter/tb_doc_grbl_plotter.sv'
s=p.read_text().replace('module tb_doc_grbl_plotter;', 'module tb_doc_grbl_plotter_last_ok;')
s=s.replace('reg rst_n=0,start=0,cancel=0,rearm=0;', 'reg rst_n=0,start=0,cancel=0,rearm=0,reset_job=0;')
s=s.replace('.clk(clk),.rst_n(rst_n),.start(start),.cancel(cancel),.rearm(rearm),', '.clk(clk),.rst_n(rst_n),.start(start),.cancel(cancel),.rearm(rearm),.reset_job(reset_job),')
s=s.replace('byte_wait<=3;rt_log[rt_count]=rt_data;rt_count=rt_count+1;', 'byte_wait<=3;rt_log[rt_count]=rt_data;rt_count=rt_count+1;\n                if(rt_data==24)enqueue("Grbl 1.1h [help]\\015\\012");')
a=s.index('        wait(dut.u_streamer.state==7);repeat(100)')
b=s.index('        $display("PASS ALL DOC PLOTTER REGRESSIONS");',a)
s=s[:a]+'''        wait_idle;
        if(dones!=2 || errors || acked_lines!=4 || line_count!=old_lines+4)$fatal(1,"new job after rearm");
        if(rt_count!=old_rt+2)$fatal(1,"normal document completion emitted final status query");
        $display("PASS empty document returns to X10/Y10 and finishes on final ok without Idle");
        // KEY4 task reset cancels motion, confirms stop, resets GRBL, then
        // automatically rearms only after a fresh post-reset Idle.
        auto_ack=1;auto_status=1;old_lines=line_count;old_rt=rt_count;
        pulse_start;wait(line_count==old_lines+1);
        @(negedge clk);reset_job=1;@(negedge clk);reset_job=0;
        wait_idle;
        if(recovery_required || cancels!=2)$fatal(1,"KEY4 did not finish safe task-reset/rearm");
        if(rt_log[old_rt+1]!="!" || rt_log[old_rt+2]!="?" || rt_log[old_rt+3]!=24 || rt_log[old_rt+4]!="?")$fatal(1,"KEY4 reset/Idle ordering");
        current_line="";q_read=q_write;
        pulse_start;finish_points;wait_idle;
        if(dones!=3 || recovery_required)$fatal(1,"document could not restart after KEY4");
        $display("PASS document KEY4 safe reset, fresh-Idle automatic rearm, next task");
        old_errors=errors;old_lines=line_count;auto_ack=0;
        pulse_start;wait(line_count==old_lines+1);
        enqueue("Grbl 1.1h [external reset]\\015\\012");wait_idle;
        if(errors!=old_errors+1 || !recovery_required || error_code!=8'h2d)$fatal(1,"external document Reset must lock and stop");
        $display("PASS external GRBL Reset stops old document and requires explicit recovery");
''' + s[b:]
(ROOT/'02_sim/tb_doc_grbl_plotter_last_ok.sv').write_text(s)

src=ROOT/'02_sim/doc_plotter/tb_grbl_reporter_key1.sv'
s=src.read_text().replace('module tb_grbl_reporter_key1;', 'module tb_grbl_reporter_key1_vector;')
s=s.replace('.CNN_MIRROR_X(1),','').replace('lines[0:255]','lines[0:2047]')
s=s.replace('.I_session_id(64\'d7),', '.I_session_id(64\'d7),.I_job_source(3\'d0),')
s=s.replace('.I_clear(1\'b0),.I_abort(reporter_abort),', '.I_clear(1\'b0),.I_abort(reporter_abort),.I_stop(1\'b0),.I_rearm(1\'b0),')
s=s.replace('if(line=="G0 X049.00 Y010.00 F07000")', 'if(line=="G0 X187.60 Y010.60 F07000")')
s=s.replace('if(line=="G1 X046.60 Y010.00 F03000")', 'if(line=="G1 X188.20 Y010.00 F03000")')
s=s.replace('raster CNN glyph mirror changed', 'single-line CNN glyph mirror mismatch')
s=s.replace('PASS KEY1 raster CNN report retained mirrored glyph coordinates', 'PASS KEY1 single-line vector CNN report retained mirrored glyph coordinates')
(ROOT/'02_sim/tb_grbl_reporter_key1_vector.sv').write_text(s)
print('prepared updated contract regressions')
