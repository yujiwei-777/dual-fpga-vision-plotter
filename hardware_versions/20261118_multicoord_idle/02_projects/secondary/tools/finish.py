"""Wait for current route, then run exact physical signoff and gated bitgen."""
from pathlib import Path
import json,subprocess,sys,time
ROOT=Path(__file__).resolve().parents[1]
BUILD=Path('E:/codex_secondary_plotter_idle_preflight_20261118_r2')
def put(o):(ROOT/'reports/COMPLETION.json').write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
state={'status':'WAITING_BUILD','hardware_status':'NOT_RUN','build':str(BUILD)};put(state)
while True:
    failed=[]
    for phase in ('syn','place','route'):
        p=BUILD/'logs'/(phase+'.json')
        if p.exists():
            v=json.loads(p.read_text(encoding='utf-8'))
            if v['status']=='FAILED_TOOL_INVOCATION':failed.append(phase)
    if failed:state.update(status='BUILD_FAILED',phases=failed);put(state);sys.exit(1)
    p=BUILD/'logs/route.json'
    if p.exists() and json.loads(p.read_text(encoding='utf-8'))['status']=='PASS_TOOL_INVOCATION':break
    time.sleep(5)
gate=ROOT/'reports/airwalk_signoff'/BUILD.name/'FUNCTIONAL_GATE.json'
for action in ('readonly','bitgen'):
    state.update(status='RUNNING_'+action.upper());put(state)
    cmd=[sys.executable,'-B',str(ROOT/'tools/signoff_airwalk.py'),action]
    if action=='bitgen':cmd+=['--gate',str(gate)]
    log=ROOT/'reports'/(action+'_launcher.log')
    with log.open('xb') as f:cp=subprocess.run(cmd,cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
    if cp.returncode:state.update(status=action.upper()+'_FAILED',log=str(log));put(state);sys.exit(1)
receipt=json.loads((BUILD/'signoff/bitgen/BITGEN_RECEIPT.json').read_text(encoding='utf-8'))
state.update(status='PASS_DIAGNOSTIC_NOT_RUN',bit=receipt['artifact'])
put(state);print(json.dumps(state,ensure_ascii=False),flush=True)
