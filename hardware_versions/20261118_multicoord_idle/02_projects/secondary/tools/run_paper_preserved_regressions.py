"""Fresh preserved-function suites bound to the exact paper-eject r2 source snapshot."""
from pathlib import Path
from datetime import datetime,timezone
from concurrent.futures import ThreadPoolExecutor,as_completed
import hashlib,json,os,re,subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
WORKSPACE=ROOT.parent
RUN=Path('E:/codex_paper_eject_secondary_20261112_r2')
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
manifest=RUN/'SOURCE_MANIFEST.json'
frozen=json.loads(manifest.read_text(encoding='utf-8-sig'))['files']
pins={str(manifest):sha(manifest),str(Path(__file__).resolve()):sha(__file__)}
for rel,row in frozen.items():
 if not rel.startswith(('01_rtl/','shared/','04_pin/','model/','main/')):continue
 source=ROOT/rel
 assert source.is_file() and sha(source)==row['sha256'],rel
 assert sha(RUN/rel)==row['sha256'],rel
 pins[str(source)]=row['sha256'];pins[str(RUN/rel)]=row['sha256']
assert pins[str(ROOT/'01_rtl/secondary_top.v')]=='46CD200DB1D357584773809798110BB31E37E1C43994AA44F73DF092B089F83F'
out=ROOT/'reports/preserved_paper_r2'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ');out.mkdir(parents=True,exist_ok=False)
base=['--run',str(RUN)]
tests=ROOT/'tests'
jobs=[
 ('cnn_pcb_pipeline',tests/'suspect_r6/run_current.py',base+['ordinary','plotter','pipeline','adapter','sharehold']),
 ('pcb_core',tests/'suspect_r6/run_core.py',base),
 ('cnn_publication',tests/'suspect_r6/run_publication.py',base),
 ('top_controls',tests/'suspect_r6/run_current.py',base+['controls','reader','key3','hxa']),
 ('key1_snapshot',tests/'operator_ui/run_key1_retained_snapshot.py',[]),
 ('key2_consecutive',ROOT/'tools/run_doc_key1_key2_regression.py',['--suspect-center']),
 ('report_suspect',ROOT/'tools/run_suspect_report_regression.py',['--center-input']),
 ('doc_committed_snapshot',tests/'operator_ui/run_doc_current_integrated.py',[]),
 ('doc_math',tests/'suspect_r6/run_document.py',base),
 ('mode_reentry',WORKSPACE/'pcb_operator_update_20261112/secondary_functional/reentry/final.py',[]),
 ('draw_cancel_reentry',WORKSPACE/'pcb_operator_update_20261112/secondary_functional/reentry/review_draw_controls.py',[]),
 ('local_mac_fault',WORKSPACE/'pcb_operator_update_20261112/secondary_functional/reentry/review_local_mac.py',[]),
]
for _,path,_ in jobs:pins[str(path)]=sha(path)
env=dict(os.environ,LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT',MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT')
def execute(job):
 label,path,args=job;log=out/(label+'.log');cmd=[sys.executable,'-B',str(path),*args]
 with log.open('xb') as f:
  cp=subprocess.run(cmd,cwd=WORKSPACE,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=7200)
 text=log.read_text(encoding='utf-8-sig',errors='replace')
 passed=cp.returncode==0 and not re.search(r'Traceback \(most recent call last\)|\*\*\s+(?:Error|Fatal):',text)
 receipts=[]
 for line in text.splitlines():
  if line.startswith('CURRENT_SUITE_OUTPUT '):receipts.append(Path(line.split(' ',1)[1])/'RESULTS.json')
  try:v=json.loads(line)
  except Exception:continue
  if isinstance(v,dict):
   for key in ['report','result','output']:
    if isinstance(v.get(key),str) and Path(v[key]).is_file():receipts.append(Path(v[key]))
 actual=[dict(path=str(x),sha256=sha(x)) for x in sorted(set(receipts))]
 if passed and not actual:passed=False
 print(label+': '+('PASS' if passed else 'FAIL')+' '+str(log),flush=True)
 return dict(label=label,status='PASS' if passed else 'FAIL',returncode=cp.returncode,command=cmd,
  log=str(log),log_sha256=sha(log),receipts=actual)
rows=[]
with ThreadPoolExecutor(max_workers=3) as pool:
 fs=[pool.submit(execute,j) for j in jobs]
 for f in as_completed(fs):
  try:rows.append(f.result())
  except BaseException as e:rows.append(dict(status='FAIL',error=repr(e)))
  (out/'PROGRESS.json').write_text(json.dumps(rows,indent=2)+'\n')
drift=[p for p,h in pins.items() if not Path(p).is_file() or sha(p)!=h]
v=dict(status='PASS_CURRENT_PAPER_R2_PRESERVED' if not drift and all(x['status']=='PASS' for x in rows) else 'FAIL',
 source_manifest=dict(path=str(manifest),sha256=sha(manifest)),source_before=pins,source_drift=drift,
 commands=rows,hardware='NOT_RUN',localization_accuracy='EXPLORATORY_NOT_PASSED',
 limitations=['Current secondary is directly compiled; paired reentry uses unchanged delivered main HXA control as a read-only protocol stimulus.',
 'Archived frames are regression fixtures; no new model-accuracy or hardware mechanics claim.'])
target=out/'RESULTS.json';target.write_text(json.dumps(v,indent=2)+'\n')
print(json.dumps(dict(status=v['status'],report=str(target),sha256=sha(target))))
raise SystemExit(0 if v['status'].startswith('PASS') else 1)
