"""Portable directed RTL checks. No tool/license or hardware download included."""
from pathlib import Path
from datetime import datetime,timezone
import argparse,subprocess,json,re,os,hashlib
ROOT=Path(__file__).resolve().parent
def main():
 ap=argparse.ArgumentParser();ap.add_argument('--sim-bin',type=Path,required=True);ap.add_argument('--output',type=Path,required=True)
 a=ap.parse_args();out=a.output.resolve()
 if out.exists() or out.is_relative_to(ROOT):raise SystemExit('Choose a new output directory outside the delivery')
 out.mkdir(parents=True);rows=[];hashes={}
 ext='.exe' if os.name=='nt' else ''
 def cmd(label,args,marker=None):
  log=out/(label+'.log')
  with log.open('w',encoding='utf-8') as f:c=subprocess.run(list(map(str,args)),cwd=out,stdout=f,stderr=subprocess.STDOUT,timeout=180)
  text=log.read_text(encoding='utf-8',errors='replace')
  ok=c.returncode==0 and not re.search(r'\*\* (?:Error|Fatal):',text) and (marker is None or marker in text)
  rows.append(dict(name=label,status='PASS' if ok else 'FAIL',log=str(log),sha256=hashlib.sha256(log.read_bytes()).hexdigest().upper()))
  print(label,rows[-1]['status'],flush=True)
  if not ok:raise RuntimeError(str(log))
 def test(group,files,cases,inc=None):
  for f in files:hashes[str(f.relative_to(ROOT))]=hashlib.sha256(f.read_bytes()).hexdigest().upper()
  cmd(group+'_vlib',[a.sim_bin/('vlib'+ext),group+'_lib'])
  cmd(group+'_lint',[a.sim_bin/('vlog'+ext),'-sv','-lint','-work',group+'_lib',*(['+incdir+'+str(inc)] if inc else []),*files])
  for top,params,marker in cases:
   label=group+'_'+top+'_'+str(len(rows))
   cmd(label,[a.sim_bin/('vsim'+ext),'-batch','-quiet','-lib',group+'_lib',top,*params,'-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'],marker)
 error=None
 try:
  main=ROOT/'02_projects/main';hdl=main/'01_rtl/imgq_gain_m/main/user_source/hdl_source'
  test('main',[hdl/n for n in ('osd_operator_decimal_snapshot.v','osd_compact_panel.v','osd_compact_font_rom.v','operator_ui_text.v')]+
   [main/'tests/portable/tb_multicoord.sv',main/'reports/multicoord/20261118T075112_749182Z/tb_multicoord_pixels.sv'],
   [('tb_multicoord',[],'MULTICOORD_PASS'),('tb_multicoord_pixels',[],'MULTICOORD_PIXEL_PIPELINE_PASS')],hdl)
  sec=ROOT/'02_projects/secondary'
  test('uart',[sec/'01_rtl/grbl_uart.v',sec/'01_rtl/grbl_response_parser.v',sec/'tests/paper_unlimited/tb_uart_idle_monitor.sv',sec/'tests/paper_unlimited/tb_uart_startup_retry.sv'],
   [('tb_uart_idle_monitor',['-gCASE_ID='+str(i)],'UART_IDLE_MONITOR_PASS') for i in range(8)]+
   [('tb_uart_startup_retry',['-gCASE_ID='+str(i)],'UART_STARTUP_RETRY_PASS') for i in range(10)])
 except Exception as e:error=repr(e)
 result=dict(status='PASS' if error is None else 'FAIL',steps=rows,error=error,source_hashes=hashes,hardware='NOT_RUN',scope='20 directed cases only; not full system or physical signoff.')
 (out/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
 if error:raise SystemExit(error)
 print('PORTABLE_SMOKE_PASS cases=20 hardware=NOT_RUN')
if __name__=='__main__':main()
