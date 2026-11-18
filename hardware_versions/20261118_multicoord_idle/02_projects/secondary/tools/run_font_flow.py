"""Compare real report G-code ink segments with corner joining off and on."""
from pathlib import Path
from datetime import datetime,timezone
import importlib.util,json,re,shutil
ROOT=Path(__file__).resolve().parents[1]
def module(n,p):
 s=importlib.util.spec_from_file_location(n,p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
h=module('flow_helper',ROOT/'tools/run_retrained_preserved_regressions.py')
template=module('flow_template',ROOT/'tools/run_suspect_report_regression.py')
out=ROOT/'reports/font_flow'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
r=h.Run(ROOT,out);error=None
tail=r'''
task complete_report;integer n;begin
 n=0;while(done_events==0&&n<500000)begin
  if(tx_lines>read_line)ack_line();else tick(1);n++;
 end
 tick(8);if(done_events!=1||error||recovery||busy)fail("no final ACK completion");
 if(queries!=0||paper_mark_moves!=0)fail("unexpected query or paper marker");
 $display("FLOW_TEXT case=%s row0=%s|row1=%s|row2=%s|cursor=%0d",case_name,printed[0],printed[1],printed[2],reporter.newline_offset_cmm);
end endtask
always @(posedge clk)if(rst_n&&reporter.state==62&&reporter.font_pen_down)
 fail("pen stayed down across glyph boundary");
integer c;
initial begin
 for(c=0;c<3;c++)begin
  reset_case();case_name=$sformatf("pcb%0d",c);judgement=c;input_count=0;input_kinds=0;
  start_job(0,0);complete_report();
 end
 for(c=1;c<=9;c++)begin
  reset_case();case_name=$sformatf("cnn%0d",c);cnn_class=c;cnn_conf=(c==1)?0:((c==9)?255:c*10);
  input_count=1;input_boxes={224'd0,16'd360,16'd640};input_kinds=3;
  start_job(0,1);complete_report();
 end
 $display("FONT_FLOW_GCODE_PASS cases=12");$finish;
end
initial begin #1000000000;$fatal(1,"flow watchdog");end
endmodule
'''
try:
 r.pin(__file__,ROOT/'tools/run_retrained_preserved_regressions.py',ROOT/'tools/run_suspect_report_regression.py',ROOT/'02_sim/key2_zero/tb_key2_zero.sv')
 rom=ROOT/'model/suspect/report_text_tokens.mem';r.pin(rom)
 staged=out.parent/'model/suspect/report_text_tokens.mem';staged.parent.mkdir(parents=True,exist_ok=True)
 if not staged.exists():shutil.copyfile(rom,staged)
 assert h.sha(rom)==h.sha(staged)
 r.pin(staged)
 observations=[]
 for join in (0,1):
  bench=out/('tb_flow_'+str(join)+'.sv');template.make_bench(bench,True)
  text=bench.read_text();text=text[:text.index('task complete_report;')]+tail
  text=text.replace('.KEY2_REZERO(1)',f'.KEY2_REZERO(1),.FONT_JOIN_CORNERS({join})')
  bench.write_text(text)
  files=[ROOT/'01_rtl'/n for n in ('grbl_reporter_shared_candidate.v','grbl_shared_transport_candidate.v','grbl_line_formatter.v','grbl_response_parser.v','grbl_vector_font_rom.v')]
  log=r.sim('flow'+str(join),files+[bench],'tb_suspect_report','FONT_FLOW_GCODE_PASS cases=12')
  cases={}
  for name,line in re.findall(r'GCODE case=(\w+) line=\d+ text=([^\r\n]*)',log):cases.setdefault(name,[]).append(line)
  summaries=re.findall(r'FLOW_TEXT case=([^\r\n]*)',log)
  assert len(cases)==12 and len(summaries)==12
  rows={}
  for name,lines in cases.items():
   pen=False;x=y=None;ink=[];downs=0
   for line in lines:
    if line.startswith('G1 Z'):
     z=float(re.search(r'Z([+-]?\d+\.\d+)',line)[1]);pen=z>0
     if pen:downs+=1
    elif line.startswith(('G0 X','G1 X')):
     xx=float(re.search(r'X([+-]?\d+\.\d+)',line)[1]);yy=float(re.search(r'Y([+-]?\d+\.\d+)',line)[1])
     if line.startswith('G1 X'):
      assert pen and x is not None and y is not None,(name,line)
      ink.append([x,y,xx,yy])
     else:assert not pen,(name,'pen-down rapid',line)
     x,y=xx,yy
   assert not pen
   rows[name]=dict(lines=len(lines),pen_down_cycles=downs,ink=ink)
  observations.append(dict(join=join,cases=rows,text=summaries))
 assert observations[0]['text']==observations[1]['text'],'Report text or newline changed'
 reductions={}
 for name,old in observations[0]['cases'].items():
  new=observations[1]['cases'][name]
  assert old['ink']==new['ink'] and len(new['ink'])>0,(name,'ink segment mismatch')
  assert new['lines']<old['lines'] and new['pen_down_cycles']<old['pen_down_cycles']
  reductions[name]=dict(draw_segments=len(new['ink']),old_lines=old['lines'],new_lines=new['lines'],old_pen_cycles=old['pen_down_cycles'],new_pen_cycles=new['pen_down_cycles'])
 r.scope.append(dict(result='Identical directed ink segments, text and newline; no pen-down rapid or glyph-boundary joining.',reductions=reductions))
 (out/'COMPARISON.json').write_text(json.dumps(dict(observations=observations,reductions=reductions),indent=2)+'\n')
 r.limits=['Actual reporter/shared formatter/parser with byte-handshaked GRBL ACK model, not physical motors.',
  'Fixed F5000 and 100 ms pen settle unchanged; mechanical duration improvement requires hardware verification.']
except Exception as exc:error=repr(exc)
v=r.finish(error)
(ROOT/'reports/FONT_FLOW_LATEST.json').write_text(json.dumps(dict(status=v['status'],report=str(out/'RESULTS.json')),indent=2)+'\n')
print(json.dumps(dict(status=v['status'],report=str(out/'RESULTS.json'),error=error)))
raise SystemExit(0 if v['status']=='PASS' else 1)
