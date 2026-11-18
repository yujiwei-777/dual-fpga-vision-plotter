"""Full-frame pixel comparison for the real two-clock document guide."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,subprocess,os,re
ROOT=Path(__file__).resolve().parents[1]
BUILD=Path('E:/codex_main_cnn_multicoord_20261118_r1')
BASE=ROOT.parent/'main_cartoon_paperfree_20261118'
REL=Path('01_rtl/imgq_gain_m/main/user_source/hdl_source/doc_copy_overlay.v')
SIM=Path('E:/model/win64')
OUT=ROOT/'reports/guide_validation'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
OUT.mkdir(parents=True)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def put(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
inputs={}
def bind(p):p=Path(p).resolve();inputs[str(p)]=sha(p);return p
for rel,row in json.loads((BUILD/'SOURCE_MANIFEST.json').read_text())['files'].items():assert sha(BUILD/rel)==row['sha256']
source=bind(ROOT/REL);assert sha(source)==sha(bind(BUILD/REL))
control=OUT/'doc_copy_overlay_control.v';control.write_bytes(bind(BASE/REL).read_bytes().replace(b'module doc_copy_overlay(',b'module doc_copy_overlay_control(',1));bind(control)
bench=bind(ROOT/'tests/tb_doc_center80_guide.sv');bind(__file__)
env=dict(os.environ,LM_LICENSE_FILE=str(SIM/'LICENSE.TXT'),MGLS_LICENSE_FILE=str(SIM/'LICENSE.TXT'))
steps=[]
for name,cmd in [('vlib',[SIM/'vlib.exe','rtl_lib']),('vlog',[SIM/'vlog.exe','-sv','-lint','-work','rtl_lib',source,control,bench]),('simulation',[SIM/'vsim.exe','-batch','-quiet','-lib','rtl_lib','tb_doc_center80_guide','-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'])]:
    log=OUT/(name+'.log')
    with log.open('x') as f:cp=subprocess.run(list(map(str,cmd)),cwd=OUT,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=300)
    t=log.read_text(errors='replace');assert cp.returncode==0 and not re.search(r'\*\* (?:Error|Fatal):',t),t[-4000:]
    steps.append(dict(exit_code=cp.returncode,log=str(log),sha256=sha(log)))
assert 'DOC_CENTER80_GUIDE_PASS' in t,t[-3000:]
assert all(sha(p)==h for p,h in inputs.items())
result=dict(status='PASS',source_manifest_sha256=sha(BUILD/'SOURCE_MANIFEST.json'),inputs=inputs,steps=steps,hardware_status='NOT_RUN')
put(OUT/'RESULT.json',result);put(ROOT/'reports/GUIDE_VALIDATION_LATEST.json',dict(path=str(OUT/'RESULT.json'),sha256=sha(OUT/'RESULT.json')))
print(t[t.index('DOC_CENTER80_GUIDE_PASS'):].splitlines()[0],flush=True)
