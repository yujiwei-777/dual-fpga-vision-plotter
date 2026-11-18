"""Full 102400-bit source-address golden, outside-black, stalls and cancel tests."""
from pathlib import Path
from datetime import datetime,timezone
import importlib.util,json,sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
s=importlib.util.spec_from_file_location('centerhelper',ROOT/'tools/run_retrained_preserved_regressions.py');h=importlib.util.module_from_spec(s);s.loader.exec_module(h)
out=ROOT/'reports/doc_center80'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
r=h.Run(ROOT,out);error=None
try:
 r.pin(Path(__file__),h.__file__)
 tb=ROOT/'tests/doc_center80/tb_doc_center80.sv';src=ROOT/'01_rtl/doc_image_frontend.v';r.pin(tb,src)
 lib=out/'rtl_lib';r.cmd('vlib',[h.SIM/'vlib.exe',lib]);r.cmd('lint',[h.SIM/'vlog.exe','-sv','-lint','-work',lib,src,tb])
 for name,center in [('crop_pattern',1),('crop_outerblack',1),('default_fullframe',0)]:
  def value(x,y):
   if name=='crop_outerblack':return 0
   kind=((x//4)*3+(y//4)*7)%8;idx=(y%4)*4+x%4
   if name=='crop_pattern' and not(128<=x<=1151 and 72<=y<=647):return 0
   if kind==0:return 20
   if kind==1:return 20 if idx==0 else 240
   if kind==2:return 20 if idx>=14 else 240
   if kind==3:return 20 if idx==15 else 240
   if kind==4:return 112 if idx<2 else 240
   if kind==5:return (112 if idx==0 else 113) if idx<2 else 240
   if kind==6:return 255
   return 70 if idx in (5,10) else 210
  data=bytes(value(x,y) for y in range(720) for x in range(1280))
  source=out/(name+'_source.mem');source.write_text(''.join('%02x\n'%v for v in data),encoding='ascii')
  expected=[]
  def sample(x,y):return data[max(0,min(719,y))*1280+max(0,min(1279,x))]
  for oy in range(320):
   for ox in range(320):
    on=70<=oy<=249 and (not center or (32<=ox<=287 and 88<=oy<=231))
    if not on:expected.append(0);continue
    sy=(oy-70)*4;sx=ox*4
    vals=sorted(sample(sx+dx,sy+dy) for dy in range(4) for dx in range(4))
    bit=vals[1]<=112
    if ox>=288 and 182<=oy<=249:
     bg=sum(sample(sx+dx,sy+dy) for dy in (-10,-2,6,14) for dx in (-10,-2,6,14))
     bit=bit and vals[1]+12<=((bg+8)>>4)
    expected.append(int(bit))
  exp=out/(name+'_expected.mem');exp.write_text(''.join(str(v)+'\n' for v in expected),encoding='ascii');r.pin(source,exp)
  log=r.cmd(name,[h.SIM/'vsim.exe','-batch','-syncio','-quiet','-lib',lib.name,'tb_doc_center80','-gCENTER='+str(center),'+SOURCE='+source.as_posix(),'+EXPECTED='+exp.as_posix(),'-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'],'DOC_CENTER80_PASS',timeout=900)
  r.scope.append(dict(test=name,records=[x for x in log.splitlines() if 'DOC_CENTER80_PASS' in x],expected_bits=102400,source_window=[128,1151,72,647] if center else [0,1279,0,719]))
except Exception as e:error=repr(e)
r.limits=['Behavioral pixel response with stalls; actual frontend RTL. Physical DDR timing and optics need hardware tests.']
v=r.finish(error);print(json.dumps(dict(status=v['status'],report=str(out/'RESULTS.json'),error=error)),flush=True)
raise SystemExit(0 if v['status']=='PASS' else 1)
