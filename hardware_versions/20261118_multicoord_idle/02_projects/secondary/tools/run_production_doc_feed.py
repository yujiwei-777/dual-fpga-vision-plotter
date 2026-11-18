"""Actual image -> planner -> KEY1 -> shared GRBL production crop/feed miter."""
from pathlib import Path
from datetime import datetime,timezone
import importlib.util,sys,json,re
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
def mod(n,p):
 s=importlib.util.spec_from_file_location(n,p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
h=mod('prodfeedhelper',ROOT/'tools/run_retrained_preserved_regressions.py')
c=mod('prodfeedcurrent',ROOT/'tests/operator_ui/run_doc_current_integrated.py')
out=ROOT/'reports/production_doc_feed'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ');out.mkdir(parents=True)
runs={};error=None
try:
 top=ROOT/'01_rtl/secondary_top.v'
 text=h.read(top)
 assert "FIXED_DRAW_FEED=16'd5000" in text
 assert '.DOC_CENTER80_ENABLE(1),.DOC_DRAW_FEED(5000)' in text
 for label in ('masked_control','production'):
  rr=h.Run(ROOT,out/label);rr.pin(Path(__file__),h.__file__,c.__file__,c.TEMPLATE,top)
  fixture=rr.out/'source_y.mem'
  data=bytearray([255])*921600
  # Two distinct open strokes fully inside the requested central window.
  for yy in range(220,232):
   for xx in range(320,400):data[yy*1280+xx]=40
  for yy in range(220,280):
   for xx in range(320,332):data[yy*1280+xx]=40
  for yy in range(360,372):
   for xx in range(640,704):data[yy*1280+xx]=24
  if label=='production':
   for yy in range(720):
    for xx in range(1280):
     if not(128<=xx<=1151 and 72<=yy<=647):data[yy*1280+xx]=0
  fixture.write_text(''.join('%02x\n'%v for v in data),encoding='ascii')
  bench=c.bench(ROOT,True)
  if label=='production':
   bench=bench.replace('.PLANNER_OPT_PASSES(0),.EXTERNAL_ADMISSION_GUARD(1)', '.PLANNER_OPT_PASSES(0),.EXTERNAL_ADMISSION_GUARD(1),.DOC_CENTER80_ENABLE(1),.DOC_DRAW_FEED(5000)')
  tb=rr.out/'tb_doc_key1_integrated.sv';tb.write_text(bench,encoding='ascii')
  files=[ROOT/'01_rtl'/x for x in ['doc_copy_pipeline_shared_candidate.v','doc_image_frontend.v','doc_stroke_planner.v','doc_stroke_bram.v','doc_machine_map.v','doc_grbl_plotter_shared_candidate.v','grbl_shared_transport_candidate.v','grbl_response_parser.v','grbl_line_formatter.v']]
  rr.pin(*files,tb,fixture);lib=rr.out/'rtl_lib'
  rr.cmd('vlib',[h.SIM/'vlib.exe',lib])
  rr.cmd('lint',[h.SIM/'vlog.exe','-sv','-lint','-work',lib,'+define+DOC_BEHAVIORAL_RAM','+define+CONFIRM',*files,tb])
  log=rr.cmd('simulation',[h.SIM/'vsim.exe','-batch','-syncio','-voptargs=+acc','-lib',lib.name,'tb_doc_key1_integrated','-do','onerror {quit -code 2}; onbreak {quit -code 3}; run -all; quit -code 0'],'DOC_KEY1_INTEGRATED_PASS',timeout=1200)
  gcode=h.read(rr.out/'gcode.txt').splitlines()
  counts={'xy':0,'z':0,'travel':0}
  for line in gcode:
   if line.startswith('G1 X'):
    assert line.endswith('F05000' if label=='production' else 'F03000'),line;counts['xy']+=1
   elif line.startswith('G1 Z'):
    assert line.endswith('F01200'),line;counts['z']+=1
   elif line.startswith('G0 X'):
    assert line.endswith('F07000'),line;counts['travel']+=1
  assert all(counts.values()),counts
  rr.scope.append(dict(test='actual cropped source, prepared KEY1 and feed-specific Gcode',records=re.findall(r'DOC_KEY1_INTEGRATED_PASS[^\r\n]*',log),feed_counts=counts))
  runs[label]=dict(result=rr.finish(),gcode=gcode)
  assert runs[label]['result']['status']=='PASS'
 assert (out/'masked_control/draw_points.txt').read_bytes()==(out/'production/draw_points.txt').read_bytes(),'crop remapped source coordinates'
 assert [x.replace('F05000','F03000') for x in runs['production']['gcode']]==runs['masked_control']['gcode'],'command behavior beyond draw feed changed'
except Exception as e:error=repr(e)
v=dict(status='PASS' if error is None else 'FAIL',runs=runs,error=error,hardware_status='NOT_RUN',assertions=['top production parameter5000 and center80 pinned','raw outerblack production vs premasked fullframe control yields identical committed points','same Gcode except XY5000; travel7000 and Z1200 unchanged','actual image/planner freshKEY1/transport/parser/formatter noforced boundary'])
h.dump(out/'RESULTS.json',v)
print(json.dumps(dict(status=v['status'],report=str(out/'RESULTS.json'),error=error)),flush=True)
raise SystemExit(0 if error is None else 1)
