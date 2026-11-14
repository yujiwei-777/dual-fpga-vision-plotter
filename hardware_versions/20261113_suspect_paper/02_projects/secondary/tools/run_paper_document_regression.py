"""Current top + actual document controller KEY1/occupied-page regression."""
from pathlib import Path
from datetime import datetime, timezone
import importlib.util,json,re
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('paper_document_helper',ROOT/'tools/run_retrained_preserved_regressions.py')
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
out=ROOT/'reports/paper_document'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
r=h.Run(ROOT,out);r.pin(Path(__file__),ROOT/'tools/run_retrained_preserved_regressions.py')
error=None
try:
 dec=h.top_declarations(r)
 names=['pll','PLL','secondary_ddr_wrapper','reset_sync','hxa_ddr_store','uiudp_stack',
      'vision_pixel_reader','vision_pipeline','hxa_config_store','hxa_secondary_link',
      'grbl_uart_port','grbl_reporter_shared_candidate','grbl_shared_transport_candidate','rgmii_interface']
 extra=[]
 for name in ['doc_image_frontend','doc_stroke_planner','doc_grbl_plotter_shared_candidate','doc_machine_map']:
  src=ROOT/'01_rtl'/(name+'.v');r.pin(src)
  code=re.sub(r'/\*.*?\*/|//[^\n]*','',h.read(src),flags=re.S)
  m=re.search(r'\bmodule\s+'+name+r'\b',code)
  extra.append(code[m.start():code.index(';',m.end())+1]+'\nendmodule\n')
 stubs=out/'document_interfaces.sv'
 stubs.write_text('\n'.join(dec[n]+'\nendmodule\n' for n in names)+'\n'.join(extra)+
    '\nmodule PH1P_LOGIC_BUFG(input i,output o);assign o=i;endmodule\n')
 r.sim('document',[stubs,ROOT/'01_rtl/secondary_top.v',ROOT/'01_rtl/doc_copy_pipeline_shared_candidate.v',
    ROOT/'tests/paper_eject/tb_operator_document.sv'],'tb_operator_document','OPERATOR_DOCUMENT_PASS',novopt=True)
except Exception as exc:error=str(exc)
r.limits=['Top and document state/admission are actual current RTL; planner, plotter, physical peripherals are boundary stubs.',
    'No claim of real image/path accuracy or physical DDR/UART validation; unchanged data path has separate regression.']
v=r.finish(error);print(json.dumps(dict(status=v['status'],report=str(out/'RESULTS.json'),error=error)))
raise SystemExit(0 if v['status']=='PASS' else 1)
