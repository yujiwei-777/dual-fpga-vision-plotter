from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,os,re,subprocess
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/idle_monitor'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ');OUT.mkdir(parents=True)
SIM=Path('E:/model/win64');env=dict(os.environ,LM_LICENSE_FILE=str(SIM/'LICENSE.TXT'),MGLS_LICENSE_FILE=str(SIM/'LICENSE.TXT'))
files=[ROOT/'01_rtl/grbl_uart.v',ROOT/'01_rtl/grbl_response_parser.v',ROOT/'tests/paper_unlimited/tb_uart_idle_monitor.sv']
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
hashes={str(p):sha(p) for p in files+[Path(__file__)]};steps=[];error=None
def run(name,args,marker=None):
 log=OUT/(name+'.log')
 with log.open('xb') as f:cp=subprocess.run(list(map(str,args)),cwd=OUT,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=90)
 t=log.read_text(errors='replace');ok=cp.returncode==0 and not re.search(r'\*\* (?:Error|Fatal):',t) and (marker is None or marker in t)
 steps.append(dict(name=name,passed=ok,log=str(log),sha256=sha(log),command=list(map(str,args))))
 print(name,ok,t[-450:],flush=True);assert ok,str(log)
try:
 run('vlib',[SIM/'vlib.exe','rtl_lib'])
 run('lint',[SIM/'vlog.exe','-sv','-lint','-work','rtl_lib',*files])
 for i in range(8):run('case'+str(i),[SIM/'vsim.exe','-batch','-quiet','-lib','rtl_lib','tb_uart_idle_monitor','-gCASE_ID='+str(i),'-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'],'UART_IDLE_MONITOR_PASS')
except Exception as e:error=repr(e)
drift=[p for p,h in hashes.items() if sha(p)!=h]
r=dict(status='PASS' if not error and not drift else 'FAIL',source_hashes=hashes,steps=steps,source_drift=drift,error=error,hardware_status='NOT_RUN')
(OUT/'RESULTS.json').write_text(json.dumps(r,indent=2)+'\n')
(ROOT/'reports/IDLE_MONITOR_LATEST.json').write_text(json.dumps(dict(status=r['status'],report=str(OUT/'RESULTS.json')),indent=2)+'\n')
raise SystemExit(0 if r['status']=='PASS' else 1)
