"""Full secondary_top control supplement with controlled peripheral interfaces.

Never extracts or substitutes admission predicates, pending/cache registers,
KEY1 controller or guard. Both the readonly control and frozen candidate are
compiled as entire secondary_top.v files in fresh simulation libraries.
"""
from pathlib import Path
from datetime import datetime, timezone
import importlib.util, json, re, sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'secondary_pcb_no_suspect_lite_20261116'
HELPER=ROOT/'tools/run_retrained_preserved_regressions.py'
spec=importlib.util.spec_from_file_location('actual_top_helper',HELPER)
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)

def main():
 parent=ROOT/'reports/write_repeat_actual_top'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
 results=[]
 for name,design,expect in [('readonly_control',BASE,True),('current_fixed',ROOT,False)]:
  out=parent/name;r=h.Run(design,out);error=None
  try:
   r.pin(Path(__file__),HELPER)
   declarations=h.top_declarations(r)
   names=['pll','PLL','secondary_ddr_wrapper','reset_sync','hxa_ddr_store','uiudp_stack',
    'vision_pixel_reader','vision_pipeline','hxa_config_store','hxa_secondary_link',
    'grbl_uart_port','grbl_reporter_shared_candidate','grbl_shared_transport_candidate',
    'doc_copy_pipeline_shared_candidate','rgmii_interface']
   stubs=out/'controlled_peripheral_interfaces.sv'
   stubs.write_text('\n'.join(declarations[n]+'\nendmodule\n' for n in names)+
    '\nmodule PH1P_LOGIC_BUFG(input i,output o);assign o=i;endmodule\n',encoding='utf-8')
   source=ROOT/'tests/paper_eject/tb_write_repeat_actual_top.sv';r.pin(source)
   bench=out/'tb_write_repeat_actual_top.sv'
   bench.write_text(h.read(source).replace('parameter EXPECT_STUCK=0;',f'parameter EXPECT_STUCK={int(expect)};'),encoding='utf-8')
   marker='WRITE_REPEAT_ACTUAL_TOP_CONTROL_PASS' if expect else 'WRITE_REPEAT_ACTUAL_TOP_FIXED_PASS'
   log=r.sim('actual_top',[stubs,design/'01_rtl/secondary_top.v',bench],
    'tb_write_repeat_actual_top',marker,novopt=True)
   r.scope.append(dict(test='Full secondary_top physical KEY1, actual cache, pending timeout and guard',
    records=re.findall(r'(?:PASS ACTUAL_TOP|WRITE_REPEAT_ACTUAL_TOP)[^\r\n]*',log)))
   r.limits+=['Full top admission/cache/pending/guard control tested, but peripheral inference, reporter, UART and network outputs are controlled interfaces.',
    'Only clock/reset and peripheral outputs are forced. No admission predicate, pending/cache register, guard state or KEY1 pulse is forced or deposited.',
    'GRBL transport, owner quiescence and recovery creation are covered separately by retained real reporter/transport regressions. This test proves top wiring preserves its recovery input lock.',
    'Only KEY1 debounce/long-press parameters are shortened; physical GRBL/ESP32 and hardware remain NOT_RUN.']
  except Exception as exc:error=repr(exc)
  result=r.finish(error)
  row=dict(name=name,path=str(out/'RESULTS.json'),status=result['status'],error=error)
  results.append(row);print(json.dumps(row),flush=True)
  if error:break
 summary=dict(status='PASS' if len(results)==2 and all(x['status']=='PASS' for x in results) else 'FAIL',
  results=results,hardware='NOT_RUN',summary=str(parent/'SUMMARY.json'))
 h.dump(parent/'SUMMARY.json',summary)
 h.dump(ROOT.parent/'audit_write_repeat_20261117/ACTUAL_TOP_RESULT.json',summary)
 print(json.dumps(summary),flush=True)
 return 0 if summary['status']=='PASS' else 1

if __name__=='__main__':raise SystemExit(main())
