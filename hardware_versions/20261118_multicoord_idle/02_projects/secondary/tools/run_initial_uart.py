from pathlib import Path
from datetime import datetime,timezone
import importlib.util,json,os,re,subprocess,hashlib
ROOT=Path(__file__).resolve().parents[1]
SIM=Path('E:/model/win64');OUT=ROOT/'reports/initial_uart'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ');OUT.mkdir(parents=True)
files=[ROOT/'01_rtl/grbl_uart.v',ROOT/'01_rtl/grbl_response_parser.v',ROOT/'tests/paper_unlimited/tb_uart_safety_review.sv',ROOT/'tests/paper_unlimited/tb_uart_retry_boundary.sv']
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
hashes={str(p):sha(p) for p in files+[Path(__file__)]}
env=dict(os.environ,LM_LICENSE_FILE=str(SIM/'LICENSE.TXT'),MGLS_LICENSE_FILE=str(SIM/'LICENSE.TXT'));steps=[]
def run(name,cmd,marker=None):
 log=OUT/(name+'.log')
 with log.open('xb') as f:cp=subprocess.run(list(map(str,cmd)),cwd=OUT,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=90)
 text=log.read_text(encoding='utf-8',errors='replace');good=cp.returncode==0 and not re.search(r'\*\*\s+(?:Error|Fatal):',text) and (marker is None or marker in text)
 steps.append(dict(name=name,command=list(map(str,cmd)),passed=bool(good),log=str(log),log_sha256=sha(log)))
 print(name,good,text[-600:],flush=True)
 assert good,name
error=None
try:
 run('vlib',[SIM/'vlib.exe','audit_lib'])
 run('lint',[SIM/'vlog.exe','-sv','-lint','-work','audit_lib',*files])
 for case in range(10):
  run('safety'+str(case),[SIM/'vsim.exe','-batch','-quiet','-lib','audit_lib','tb_uart_safety_review','-gCASE_ID='+str(case),'-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'],'UART_SAFETY_REVIEW_PASS')
 for case in range(3):
  run('late'+str(case),[SIM/'vsim.exe','-batch','-quiet','-lib','audit_lib','tb_uart_retry_boundary','-gCASE_ID='+str(case),'-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'],'UART_RETRY_BOUNDARY_PASS')
 # Real wire timing is swept before, at, and after the U_STATUS timeout.
 for timer in range(7738,7755):
  run('timeout'+str(timer),[SIM/'vsim.exe','-batch','-quiet','-lib','audit_lib','tb_uart_retry_boundary','-gCASE_ID=3','-gSEND_TIMER='+str(timer),'-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'],'UART_RETRY_BOUNDARY_PASS')
except Exception as e:error=repr(e)
drift=[p for p,h in hashes.items() if sha(p)!=h]
v=dict(status='PASS' if not error and not drift else 'FAIL',source_hashes=hashes,source_drift=drift,steps=steps,error=error,hardware_status='NOT_RUN')
(OUT/'RESULTS.json').write_text(json.dumps(v,indent=2)+'\n',encoding='utf-8')
(ROOT/'reports/INITIAL_UART_LATEST.json').write_text(json.dumps(dict(status=v['status'],report=str(OUT/'RESULTS.json')),indent=2)+'\n',encoding='utf-8')
print(json.dumps(dict(status=v['status'],report=str(OUT/'RESULTS.json'))),flush=True)
raise SystemExit(0 if v['status']=='PASS' else 1)
