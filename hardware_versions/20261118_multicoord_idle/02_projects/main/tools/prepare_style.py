"""Prepare independent main style freeze; source baselines remain readonly."""
from pathlib import Path
import hashlib,json,re,shutil,subprocess,sys,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'main_doc_center80_cartoon_paperfree_20261118'
BUILD=Path('E:/codex_main_cnn_multicoord_20261118_r1')
RUN=Path('01_rtl/imgq_gain_m/main/td_project_display_noise_v8')
NAME='camera_to_dsi_display_720p60_cnn_multibox'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def put(p,o):Path(p).write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert not BUILD.exists()
# Preserve exact bytes of pinned readonly validator (the baseline source is LF-normalized).
shutil.copy2(BASE/'tools/summarize_readonly.py',ROOT/'tools/summarize_readonly.py')
def rebase(root):
 run=root/RUN
 for ext in ('.al','.prj'):
  p=run/(NAME+ext);t=p.read_text(encoding='utf-8-sig');t=re.sub(r'&(?!#?\w+;)','&amp;',t);t=re.sub(r'(<\/?[A-Za-z_][\w:]*)::',lambda m:m[1]+'_TD_DOUBLE_COLON_',t)
  tree=ET.fromstring(t);tree.set('Path',run.as_posix());ET.indent(tree)
  p.write_text('<?xml version="1.0" encoding="UTF-8"?>\n'+ET.tostring(tree,encoding='unicode').replace('_TD_DOUBLE_COLON_','::')+'\n',encoding='utf-8')
 cp=subprocess.run([sys.executable,'-B',str(root/'tools/td_release_audit.py'),'snapshot','--root',str(root),'--run',str(run),'--name',NAME,'--al',str(run/(NAME+'.al')),'--config',str(root/'tools/release_audit_config.json'),'--output',str(run/'source_snapshot.json')],capture_output=True,text=True)
 assert cp.returncode==0,cp.stdout+cp.stderr
 assert json.loads((run/'source_snapshot.json').read_text(encoding='utf-8-sig'))['passed']
rebase(ROOT);BUILD.mkdir()
for d in ('01_rtl','04_pin','tools','tests'):shutil.copytree(ROOT/d,BUILD/d,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
(BUILD/'audits').mkdir();shutil.copy2(ROOT/'tools/summarize_readonly.py',BUILD/'audits/summarize_readonly.py');rebase(BUILD)
records={p.relative_to(BUILD).as_posix():dict(sha256=sha(p),bytes=p.stat().st_size) for d in ('01_rtl','04_pin','tools','tests') for p in sorted((BUILD/d).rglob('*')) if p.is_file()}
put(BUILD/'SOURCE_MANIFEST.json',dict(schema='main-doc-center80-cartoon-paperfree-source-v1',files=records))
plan=dict(status='PREPARED',source_root=str(ROOT),build_root=str(BUILD),source_manifest_sha256=sha(BUILD/'SOURCE_MANIFEST.json'),phase_runner_sha256=sha(ROOT/'tools/run_build_phases.py'),limits_strict_less_than=dict(slice=95,eram=90,dsp=95),hardware_status='NOT_RUN',bitgen_allowed=False)
put(BUILD/'BUILD_PLAN.json',plan);put(ROOT/'reports/BUILD_PLAN.json',plan)
assert all(sha(p)==v for p,v in json.loads((ROOT/'baseline_reference/PROTECTED_INPUTS.json').read_text(encoding='utf-8')).items())
print(json.dumps(plan,ensure_ascii=False))
