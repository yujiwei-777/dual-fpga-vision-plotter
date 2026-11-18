from pathlib import Path
from datetime import datetime,timezone
import importlib.util,json
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'tools/run_retrained_preserved_regressions.py'
s=importlib.util.spec_from_file_location('startup_helper',p);h=importlib.util.module_from_spec(s);s.loader.exec_module(h)
out=ROOT/'reports/startup_retry'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
r=h.Run(ROOT,out);error=None
try:
 r.pin(__file__,p)
 files=[ROOT/'01_rtl/grbl_uart.v',ROOT/'01_rtl/grbl_response_parser.v',ROOT/'tests/paper_unlimited/tb_uart_startup_retry.sv']
 r.pin(*files);r.cmd('vlib',[h.SIM/'vlib.exe','rtl_lib'])
 r.cmd('compile',[h.SIM/'vlog.exe','-sv','-lint','-work','rtl_lib',*files])
 for case in range(10):
  r.cmd('case'+str(case),[h.SIM/'vsim.exe','-batch','-quiet','-lib','rtl_lib','tb_uart_startup_retry','-gCASE_ID='+str(case),'-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'],'UART_STARTUP_RETRY_PASS')
 r.limits=['Real UART timing with scaled clock; startup-only noise and late stopped reply restart full handshake.',
  'Alarm, moving controller, error response and established-session faults remain locked; no blind $X/$H or motion replay.',
  'Physical failure cause unconfirmed without controller UART capture.']
except Exception as exc:error=repr(exc)
result=r.finish(error)
(ROOT/'reports/STARTUP_RETRY_LATEST.json').write_text(json.dumps(dict(status=result['status'],report=str(out/'RESULTS.json')),indent=2)+'\n')
print(json.dumps(dict(status=result['status'],error=error,report=str(out/'RESULTS.json'))))
raise SystemExit(0 if result['status']=='PASS' else 1)
