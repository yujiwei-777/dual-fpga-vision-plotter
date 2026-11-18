"""Reconcile fresh retained suites and test the zero-region paper contract."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,importlib.util,json,shutil,sys
ROOT=Path(__file__).resolve().parents[1]
BUILD=Path('E:/codex_secondary_write_repeat_fix_20261117_r1')
OLD=ROOT/'reports/preserved_airwalk_r4/20261116T054828_894471Z'
RETRY=ROOT/'reports/pipeline_retirement_retry'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def put(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def module(name,p):
 s=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
out=ROOT/'reports/no_suspect_paper'/stamp
h=module('retained_no_suspect_paper',ROOT/'tools/run_retrained_preserved_regressions.py')
report=module('report_template',ROOT/'tools/run_suspect_report_regression.py')
r=h.Run(ROOT,out);r.pin(Path(__file__),ROOT/'tools/run_suspect_report_regression.py',ROOT/'tools/run_retrained_preserved_regressions.py')
error=None
try:
 bench=out/'tb_suspect_report.sv';report.make_bench(bench,True)
 text=bench.read_text(encoding='utf-8');text=text[:text.index('initial begin\n case_name=')]
 text+=r'''
integer i,j;reg[31:0] expected_height;
initial begin
 reset_case();expected_height=0;
 for(i=0;i<3;i++)begin
  clear_history();judgement=i;input_count=0;input_boxes=0;input_kinds=0;
  start_job(0,0);complete_report();expected_height=expected_height+1100;
  if(printed[1]!=""||printed[2]!=""||reporter.suspect_job)fail("zero-region PCB emitted position text");
  if(reporter.newline_offset_cmm!=expected_height)fail("PCB title consumed more than11mm");
  if((i==0&&printed[0]!="PCB 0001 REVIEW")||(i==1&&printed[0]!="PCB 0002 PASS")||(i==2&&printed[0]!="PCB 0003 FAIL"))fail("PCB title/verdict changed");
  pass();
 end
 clear_history();judgement=2;input_count=0;input_boxes=0;input_kinds=0;
 start_job(0,0);complete_report();
 if(printed[0]!="PCB 0004 FAIL"||printed[1]!=""||printed[2]!=""||reporter.newline_offset_cmm!=4400)fail("repeated title-only FAIL/newline mismatch");pass();
 reset_case();judgement=2;input_count=1;input_boxes={224'd0,16'd240,16'd640};input_kinds=3;start_job(0,1);complete_report();
 if(printed[0]!="GREEN CIRCLE  "||printed[1]!="X0640 Y0240"||printed[2]!="CONF 003")fail("CNN actual centre/confidence changed");pass();
 $display("NO_SUSPECT_PAPER_PASS cases=%0d title_height_mm=11",scenarios);$finish;
end
initial begin #1000000000;$fatal(1,"global timeout");end
endmodule
'''
 bench.write_text(text,encoding='utf-8')
 rom=ROOT/'model/suspect/report_text_tokens.mem';staged=out.parent/'model/suspect/report_text_tokens.mem'
 staged.parent.mkdir(parents=True,exist_ok=True)
 if staged.exists():assert sha(staged)==sha(rom)
 else:shutil.copy2(rom,staged)
 r.pin(rom,staged)
 sources=[ROOT/'01_rtl'/n for n in ('grbl_reporter_shared_candidate.v','grbl_shared_transport_candidate.v','grbl_line_formatter.v','grbl_response_parser.v','grbl_vector_font_rom.v')]+[bench]
 r.sim('no_suspect_paper',sources,'tb_suspect_report','NO_SUSPECT_PAPER_PASS cases=5')
 r.scope.append(dict(contract='Integrated count0 from actual pipeline publication boundary; PCB title+verdict only,11mm each, real formatter/UART ACK, no terminal Idle, CNN centre and actual low confidence retained.'))
except Exception as e:error=repr(e)
paper=r.finish(error)
assert paper['status']=='PASS',error
v=load(OLD/'RESULTS.json');retry=load(RETRY/'RESULTS.json')
assert v['status']=='FAIL' and retry['status']=='PASS'
failed=[row for row in v['commands'] if row['status']!='PASS'];assert len(failed)==1 and failed[0]['label']=='pcb_pipeline_adapter_sharehold'
assert 'Test output must stay inside candidate reports' in (OLD/'pcb_pipeline_adapter_sharehold.log').read_text()
for result in retry['suite_results']:assert result['status']=='PASS' and not result['source_drift']
for row in v['commands']:
 if row['label']=='pcb_pipeline_adapter_sharehold':
  row.clear();row.update(label='pcb_pipeline_adapter_sharehold',status='PASS',returncode=0,command=['direct retry: run_current.py pipeline adapter sharehold'],receipts=[dict(path=str(RETRY/'RESULTS.json'),sha256=sha(RETRY/'RESULTS.json'),status='PASS')])
v['status']='PASS_CURRENT_R4_PRESERVED';v['reconciled_by']=dict(path=str(Path(__file__)),sha256=sha(__file__))
v['retry_explanation']='First pipeline job failed before RTL execution due output-directory assertion; standalone current-freeze pipeline/adapter/sharehold all passed. Other ten fresh successful jobs are retained without repetition. Original failed receipt remains unchanged.'
target=ROOT/'reports/preserved_airwalk_r4'/('reconciled_'+stamp);target.mkdir()
put(target/'RESULTS.json',v)
print(json.dumps(dict(status=v['status'],preserved=str(target/'RESULTS.json'),paper=str(out/'RESULTS.json'))))
