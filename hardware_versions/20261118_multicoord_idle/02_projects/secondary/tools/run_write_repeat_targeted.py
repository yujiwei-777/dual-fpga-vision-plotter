"""Targeted KEY1 admission cleanup regression against readonly control and fix.

Uses source-extracted current top predicates and real guard, reporter, shared
transport, formatter, parser and font ROM. External vision/cache inputs and the
UART byte handshake are controlled. No production RTL or physical DB is edited.
"""
from pathlib import Path
from datetime import datetime, timezone
import importlib.util, json, re, shutil, sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'secondary_pcb_no_suspect_lite_20261116'

def mod(name,path):
 spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

def statement(s,begin):
 a=s.index(begin);return s[a:s.index(';',a)+1]

def make(path,design,expect_stuck,r):
 template=mod('report_template_'+path.parent.name,ROOT/'tools/run_suspect_report_regression.py')
 template.make_bench(path,True)
 body=path.read_text(encoding='utf-8');body=body[:body.index('task start_job(')]+body[body.index('task wait_line;',body.index('task start_job(')):]
 body=body[:body.index('initial begin\n case_name=')]
 # The old direct-producer task is deliberately removed: all job requests now
 # pass through the source-extracted top's local admission and pending logic.
 body=body.replace('clear=0,stop=0,abort_job=0,rearm=0,job_valid=0,local_test=0', 'stop=0,abort_job=0,rearm=0,local_test=0')
 body=body.replace('job_valid=0;','').replace('clear=0;','').replace('clear=1;','')
 body=body.replace('reg [31:0] job_id=0;', 'wire [31:0] job_id;')
 body=body.replace('.I_step_cmm(8\'d100)', '.I_step_cmm(probe_step)')
 body=body.replace('.I_job_source(3\'d1)', '.I_job_source(3\'d0)')
 body=body.replace(".I_doc_owner(1'b0)",'.I_doc_owner(doc_owner_input)')
 body=body.replace(".D_fmt_start('0)",'.D_fmt_start(doc_fmt_start)')
 body=body.replace(".D_fmt_feed('0)",".D_fmt_feed(16'd3000)")
 top=design/'01_rtl/secondary_top.v';r.pin(top)
 s=top.read_text(encoding='utf-8-sig')
 predicates='\n'.join(statement(s,x) for x in [
  '    wire key1_report_slot_available=', '    wire key1_local_admit=',
  '    wire pcb_key1_admit=', '    wire key1_local_job_accept='])
 if '    wire report_admit_failed=' in s:predicates+='\n'+statement(s,'    wire report_admit_failed=')
 a=s.index('    grbl_key1_job_guard u_key1_job_guard(');guard=s[a:s.index(';',a)+1]
 a=s.index('                if(report_admit_failed)begin') if 'if(report_admit_failed)begin' in s else s.index('                if(report_pending&&report_admit_age>=3&&!report_busy&&!report_ready)begin')
 b=s.index('\n                end',a)+len('\n                end');timeout=s[a:b]
 ready_clear=statement(s,'            if(report_pending&&report_ready)')
 age_a=s.index('            if(!report_pending)report_admit_age<=0;');age_b=s.index('\n',s.index('else if(report_admit_age<7)',age_a));age=s[age_a:age_b]
 # Complete top eligibility predicate is preserved. Controlled source/cache
 # inputs isolate this control regression from image inference arithmetic.
 probe=r'''
localparam EXPECT_STUCK=@@EXPECT@@;
wire clk125=clk,rst125_n=rst_n;
reg vision_busy=0,key4_reset_active=0,key4_stop=0,key2_local_active=0,key2_new_page=0;
reg copy_busy=0,copy_recovery=0,vision_start=0,normal_done=0,target_valid=1;
reg operator_preview_capable=0,preview_locked=1;
reg cnn_cache_result_valid=1,cnn_cache_valid=1,cnn_cache_invalid=0;
reg pcb_report_cache_valid=1,pcb_report_cache_invalid=0,pcb_report_result=0;
reg [1:0] vision_purpose=0;
reg key1_report_action=0,profile_valid=1;
wire uart_link_ready=link_ready;
wire report_ready=job_ready,report_busy=busy,report_done=done,report_error=error;
wire report_recovery_required=recovery;
wire vision_job_cancel=abort_job,key4_press=stop;
reg report_pending=0,report_clear=0;
reg [2:0] report_admit_age=0;
reg [31:0] report_job=0,request_id=1;
wire key1_job_active,key1_job_protected;
wire [7:0] report_error_code=error_code;
reg [95:0] job_status_data=0;reg job_status_valid=0;
wire clear=report_clear;
wire job_valid=report_pending&&!key4_reset_active&&!key4_stop;
assign job_id=report_job;
reg [7:0] probe_step=100;
reg doc_owner_input=0,doc_fmt_start=0;
@@PREDICATES@@
@@GUARD@@
always @(posedge clk)begin
 if(!rst_n)begin report_pending<=0;report_clear<=0;report_admit_age<=0;report_job<=0;job_status_data<=0;job_status_valid<=0;end
 else begin
  report_clear<=0;
@@READY_CLEAR@@
@@AGE@@
  if(vision_job_cancel||key4_press)report_pending<=0;
  else begin
@@TIMEOUT@@
   if(key1_local_job_accept)begin
    report_job<=request_id;report_clear<=1;report_pending<=1;
   end
  end
 end
end
task key1_request(input integer id);
begin
 request_id=id;tick(2);
 if(!key1_report_slot_available)fail("KEY1 source slot unavailable before request");
 key1_report_action=1;tick(1);key1_report_action=0;
 if(!key1_job_active||!report_pending)fail("KEY1 admission did not protect pending snapshot");
end endtask
task clean_controls;
begin
 key1_report_action=0;probe_step=100;doc_owner_input=0;doc_fmt_start=0;
 vision_busy=0;copy_busy=0;copy_recovery=0;vision_start=0;normal_done=0;
 key4_reset_active=0;key4_stop=0;operator_preview_capable=0;preview_locked=1;
 reset_case();input_count=0;input_boxes=0;input_kinds=0;judgement=1;cnn=0;
end endtask
task finish_unique(input integer id);
begin
 done_events=0;key1_request(id);complete_report();tick(8);
 if(key1_job_active||report_pending||!key1_report_slot_available)fail("normal last-ok failed to release KEY1 slot");
end endtask
task check_rejection;
begin
 tick(15);
 if(report_pending||!job_status_valid||job_status_data[47:40]!=10||busy||tx_lines!=0)fail("pre-start refusal did not terminate with error10/no motion");
 if(EXPECT_STUCK)begin
  if(!key1_job_active||key1_report_slot_available)fail("control no longer reproduces stale lock");
  $display("WRITE_REPEAT_BASELINE_REPRODUCED pending0 error10 active1 next_KEY1_slot0");
 end else if(key1_job_active||!key1_report_slot_available)fail("fixed refusal did not release KEY1 owner");
end endtask
initial begin
 case_name="actual_reporter_profile_refusal";clean_controls();probe_step=0;tick(8);key1_request(1);check_rejection();pass();
 if(EXPECT_STUCK)begin
  $display("WRITE_REPEAT_CONTROL_PASS known_stale_lock_reproduced=1");$finish;
 end
 probe_step=100;tick(8);case_name="next_unique_KEY1_no_reset";finish_unique(2);pass();
 case_name="consecutive_unique_KEY1_normal_done";finish_unique(3);pass();
 case_name="busy_and_unsolicited_Hold_Idle_cannot_release_owner";
 done_events=0;key1_request(4);wait_line();tick(20);
 if(!busy||!key1_job_active||report_pending)fail("busy report falsely hit pre-start timeout");
 send_rx("<Hold:0|MPos:0,0,0>\n");send_rx("<Idle|MPos:0,0,0>\n");tick(5);
 if(!busy||!key1_job_active||done_events!=0)fail("status released in-flight task without ok");
 complete_report();tick(5);if(key1_job_active)fail("normal done retained owner");pass();
 case_name="actual_shared_doc_formatter_owner_quiescence";clean_controls();
 doc_owner_input=1;tick(3);doc_fmt_start=1;tick(1);doc_fmt_start=0;doc_owner_input=0;
 if(!transport.owner_valid||!transport.owner_doc||!transport.fmt_busy)fail("no live prior document formatter epoch");
 key1_request(5);tick(15);
 if(report_pending||key1_job_active||job_status_data[47:40]!=10||tx_lines!=0)fail("owner contention retained KEY1 or emitted motion");
 begin integer n;n=0;while((transport.owner_valid||transport.fmt_busy)&&n<200)begin tick(1);n++;end
 if(transport.owner_valid||transport.fmt_busy)fail("shared owner failed to release at quiescence");end
 finish_unique(6);pass();
 case_name="duplicate_report_id_refusal_then_unique";
 done_events=0;key1_request(6);tick(15);
 if(report_pending||key1_job_active||job_status_data[47:40]!=10||done_events!=0)fail("duplicate request remained locked or replayed");
 finish_unique(7);pass();
 case_name="Alarm_recovery_not_cleared";clean_controls();key1_request(8);wait_line();send_rx("ALARM:1\n");tick(15);
 if(!error||!recovery||key1_job_active||key1_report_slot_available||done_events!=0)fail("Alarm safety lock changed");pass();
 case_name="Reset_recovery_not_cleared";clean_controls();key1_request(9);wait_line();send_rx("Grbl 1.1h ['$' for help]\n");tick(15);
 if(!error||!recovery||error_code!=9||key1_job_active||key1_report_slot_available||done_events!=0)fail("Reset safety lock changed");pass();
 case_name="UART_loss_recovery_not_cleared";clean_controls();key1_request(10);wait_line();link_ready=0;tick(15);link_ready=1;tick(10);
 if(!error||!recovery||key1_job_active||key1_report_slot_available||done_events!=0)fail("UART safety lock changed");pass();
 case_name="explicit_cancel_pending_releases_owner";clean_controls();probe_step=0;tick(8);key1_request(11);abort_job=1;tick(1);abort_job=0;tick(5);
 if(report_pending||key1_job_active)fail("explicit cancel retained pending owner");pass();
 $display("WRITE_REPEAT_TARGETED_PASS cases=%0d",scenarios);$finish;
end
initial begin #1000000000;$fatal(1,"targeted regression timeout");end
endmodule
'''
 for a,b in [('@@EXPECT@@',str(int(expect_stuck))),('@@PREDICATES@@',predicates),('@@GUARD@@',guard),('@@READY_CLEAR@@',ready_clear),('@@AGE@@',age),('@@TIMEOUT@@',timeout)]:probe=probe.replace(a,b)
 body=body.replace('module tb_suspect_report;', 'module tb_write_repeat;')
 # All original bench signals are declared before the extra top predicates,
 # preventing implicit forward nets. Source extraction remains verbatim.
 early='''wire clear,job_valid;
reg [7:0] probe_step=100;
reg doc_owner_input=0,doc_fmt_start=0;
'''
 body=body.replace('reg frame_reset=0,paper_confirm=0;',early+'\nreg frame_reset=0,paper_confirm=0;')
 probe=probe.replace('wire clear=report_clear;','assign clear=report_clear;').replace('wire job_valid=','assign job_valid=')
 probe=probe.replace('reg [7:0] probe_step=100;\nreg doc_owner_input=0,doc_fmt_start=0;','')
 body=body+'\n'+probe
 path.write_text(body,encoding='utf-8')

def main():
 h=mod('retained_write_repeat',ROOT/'tools/run_retrained_preserved_regressions.py')
 stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ');parent=ROOT/'reports/write_repeat_targeted'/stamp
 results=[]
 for name,design,expect in [('readonly_control',BASE,True),('current_fixed',ROOT,False)]:
  out=parent/name;r=h.Run(design,out);error=None
  try:
   r.pin(Path(__file__),ROOT/'tools/run_retrained_preserved_regressions.py',ROOT/'tools/run_suspect_report_regression.py',ROOT/'02_sim/key2_zero/tb_key2_zero.sv')
   bench=out/'tb_write_repeat.sv';make(bench,design,expect,r)
   rom=design/'model/suspect/report_text_tokens.mem';staged=out.parent/'model/suspect/report_text_tokens.mem';staged.parent.mkdir(parents=True,exist_ok=True)
   if staged.exists():assert h.sha(staged)==h.sha(rom)
   else:shutil.copy2(rom,staged)
   r.pin(rom,staged)
   files=[design/'01_rtl'/n for n in ('secondary_top.v','grbl_reporter_shared_candidate.v','grbl_shared_transport_candidate.v','grbl_line_formatter.v','grbl_response_parser.v','grbl_vector_font_rom.v')]+[bench]
   marker='WRITE_REPEAT_CONTROL_PASS known_stale_lock_reproduced=1' if expect else 'WRITE_REPEAT_TARGETED_PASS cases=10'
   log=r.sim('write_repeat',files,'tb_write_repeat',marker)
   r.scope.append(dict(test='actual top eligibility/timeout/guard wiring extracted without predicate modification; real reporter/shared formatter/parser/UART ACK',records=re.findall(r'(?:WRITE_REPEAT|SUSPECT_REPORT_CASE_PASS)[^\r\n]*',log)))
   r.limits+=['External vision/cache/purpose signals controlled; not full FPGA top or real controller.','The owner-quiescence case controls preceding document formatter reservation; it proves rejection cleanup and next ownership, not occurrence frequency in hardware.','No reset, recovery or physical paper cursor policy is removed; real controller/board status remains NOT_RUN.']
  except Exception as e:error=repr(e)
  result=r.finish(error);results.append(dict(name=name,path=str(out/'RESULTS.json'),status=result['status'],error=error));print(json.dumps(results[-1]),flush=True)
  if error:break
 summary=dict(status='PASS' if len(results)==2 and all(x['status']=='PASS' for x in results) else 'FAIL',results=results,hardware='NOT_RUN')
 (parent/'SUMMARY.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n')
 print(json.dumps(dict(status=summary['status'],summary=str(parent/'SUMMARY.json'))),flush=True)
 return 0 if summary['status']=='PASS' else 1

if __name__=='__main__':raise SystemExit(main())
