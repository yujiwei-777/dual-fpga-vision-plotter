"""Independent source-only build; remove all PCB suspect presentation."""
from pathlib import Path
import hashlib,json,re,shutil,subprocess,sys,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'main_pcb_no_suspect_text_20261116'
CONTROL=ROOT.parent/'main_pcb_suspect_center_20261113'
BUILD=Path('E:/codex_pcb_no_suspect_main_20261116_r1')
HDL=Path('01_rtl/imgq_gain_m/main/user_source/hdl_source')
RUN=Path('01_rtl/imgq_gain_m/main/td_project_display_noise_v8')
NAME='camera_to_dsi_display_720p60_cnn_multibox'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def put(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def plain(p):
 for q in [p,*p.rglob('*')]:
  s=q.lstat()
  assert not q.is_symlink() and not getattr(s,'st_file_attributes',0)&0x400 and (not q.is_file() or s.st_nlink==1),str(q)
assert not (ROOT/'01_rtl').exists() and not BUILD.exists()
protected=json.loads((BASE/'baseline_reference/PROTECTED_INPUTS.json').read_text())
for d in ('01_rtl','04_pin','artifacts'):
 for p in (BASE/d).rglob('*'):
  if p.is_file():protected[str(p)]=sha(p)
for d in ('01_rtl','04_pin','tests'):
 plain(BASE/d);shutil.copytree(BASE/d,ROOT/d,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
for d in ('reports','artifacts','baseline_reference'):(ROOT/d).mkdir(exist_ok=True)
for p in (BASE/'tools').rglob('*'):
 if p.is_file() and '__pycache__' not in p.parts and p.suffix!='.pyc':
  target=ROOT/'tools'/p.relative_to(BASE/'tools');target.parent.mkdir(parents=True,exist_ok=True)
  if p.suffix in ('.py','.json','.tcl','.txt'):
   t=p.read_text(encoding='utf-8-sig').replace('codex_pcb_no_suspect_text_main_20261116_r1',BUILD.name).replace('main_pcb_no_suspect_text_20261116',ROOT.name)
   target.write_text(t,encoding='utf-8')
  else:shutil.copy2(p,target)
put(ROOT/'baseline_reference/PROTECTED_INPUTS.json',protected)
p=ROOT/HDL/'hdmi_mixer.v';t=p.read_text(encoding='utf-8')
a=t.index('    wire S_suspect_in=');b=t.index('    // Motion box:',a)
t=t[:a]+"    // Suspected-region graphics retired; retain the ordinary whole-board overlay.\n    wire S_suspect_hit=1'b0;\n\n"+t[b:]
t=t.replace(".pcb_suspect(I_pcb_suspect===1'b1)",".pcb_suspect(1'b0)")
p.write_text(t,encoding='utf-8',newline='\n')
p=ROOT/HDL/'operator_ui_text.v';t=p.read_text(encoding='utf-8')
assert t.count('2:if(data[4])key=26;')==1
t=t.replace('2:if(data[4])key=26;','2:key=56; // PCB report has no suspected-position row.')
p.write_text(t,encoding='utf-8',newline='\n')
changes=[]
for d in ('01_rtl','04_pin'):
 for p in (ROOT/d).rglob('*'):
  if p.is_file() and p.suffix not in ('.al','.prj') and p.name!='source_snapshot.json' and sha(p)!=sha(CONTROL/p.relative_to(ROOT)):changes.append(p.relative_to(ROOT).as_posix())
put(ROOT/'BASELINE.json',dict(baseline=str(CONTROL),immediate_baseline=str(BASE),changes=sorted(changes),scope='Remove PCB suspect text, region/cross and coordinate row; retain whole-board bbox and verdict, ordinary CNN and controls.',hardware_status='NOT_RUN'))
def rebase(root):
 run=root/RUN
 for ext in ('.al','.prj'):
  p=run/(NAME+ext);t=p.read_text(encoding='utf-8-sig')
  t=re.sub(r'&(?!#?\w+;)','&amp;',t);t=re.sub(r'(<\/?[A-Za-z_][\w:]*)::',lambda m:m[1]+'_TD_DOUBLE_COLON_',t)
  tree=ET.fromstring(t);tree.set('Path',run.as_posix());ET.indent(tree)
  p.write_text('<?xml version="1.0" encoding="UTF-8"?>\n'+ET.tostring(tree,encoding='unicode').replace('_TD_DOUBLE_COLON_','::')+'\n',encoding='utf-8')
 cp=subprocess.run([sys.executable,'-B',str(root/'tools/td_release_audit.py'),'snapshot','--root',str(root),'--run',str(run),'--name',NAME,'--al',str(run/(NAME+'.al')),'--config',str(root/'tools/release_audit_config.json'),'--output',str(run/'source_snapshot.json')],capture_output=True,text=True)
 assert cp.returncode==0,cp.stdout+cp.stderr
 assert json.loads((run/'source_snapshot.json').read_text(encoding='utf-8-sig'))['passed']
# Tests and release scripts are adapted separately before the freeze action.
put(ROOT/'reports/PREPARED_SOURCE.json',dict(status='SOURCE_ONLY_READY',changes=sorted(changes)))
assert all(sha(p)==v for p,v in protected.items())
print('SOURCE_ONLY_READY',sorted(changes))
