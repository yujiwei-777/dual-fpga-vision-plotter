"""Continue the fresh build through read-only signoff and gated publication."""
from pathlib import Path
from datetime import datetime,timezone
import json,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[1]
BUILD=Path('E:/codex_main_cnn_multicoord_20261118_r1')
def put(o):(ROOT/'reports/COMPLETION.json').write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
state={'status':'WAITING_BUILD','hardware_status':'NOT_RUN','build':str(BUILD)};put(state)
while True:
    current=json.loads((BUILD/'logs/CURRENT.json').read_text(encoding='utf-8'))
    if current['status']=='FAILED':state.update(status='BUILD_FAILED',phase=current['phase']);put(state);sys.exit(1)
    if current.get('phase')=='route' and current['status']=='COMPLETE':break
    time.sleep(5)
for phase,cmd in [('AUDIT',[sys.executable,'-B',str(ROOT/'tools/audit_current_route.py'),'--attempt','r1']),
    ('BITGEN',[sys.executable,'-B',str(ROOT/'tools/release.py'),'--acceptance',str(BUILD/'audits/route_acceptance_r1/CURRENT_ROUTE_ACCEPTANCE.json')])]:
    state.update(status='RUNNING_'+phase);put(state)
    log=ROOT/'reports'/(phase.lower()+'_launcher.log')
    with log.open('xb') as f:cp=subprocess.run(cmd,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
    if cp.returncode:state.update(status=phase+'_FAILED',log=str(log));put(state);sys.exit(1)
receipt=json.loads((ROOT/'artifacts/RELEASE_REPORT.json').read_text(encoding='utf-8'))
state.update(status=receipt['status'],bit=receipt['bit'],timing_ns=receipt['timing_ns'],resources=receipt['resources'])
put(state);print(json.dumps(state,ensure_ascii=False),flush=True)
