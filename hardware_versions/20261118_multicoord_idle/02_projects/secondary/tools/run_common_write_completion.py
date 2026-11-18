"""Current top and actual report/transport/UART completion regression.

Read-only production inputs; independent fresh libraries and current-source
receipts. Normal requests pass the real KEY1/KEY2 controls and task ownership.
"""
from pathlib import Path
from datetime import datetime, timezone
import importlib.util, json, re, shutil, sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
HELPER=ROOT/'tools/run_retrained_preserved_regressions.py'
spec=importlib.util.spec_from_file_location('completion_helper',HELPER)
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
OUT=ROOT/'reports/common_write_completion'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
r=h.Run(ROOT,OUT)
error=None
try:
 r.pin(Path(__file__),HELPER)
 declarations=h.top_declarations(r)
 names=['pll','PLL','secondary_ddr_wrapper','reset_sync','hxa_ddr_store','uiudp_stack',
   'vision_pixel_reader','vision_pipeline','hxa_config_store','hxa_secondary_link',
   'doc_copy_pipeline_shared_candidate','rgmii_interface']
 stubs=OUT/'controlled_peripheral_interfaces.sv'
 stubs.write_text('\n'.join(declarations[n]+'\nendmodule\n' for n in names)+
  '\nmodule PH1P_LOGIC_BUFG(input i,output o);assign o=i;endmodule\n',encoding='utf-8')
 rom=ROOT/'model/suspect/report_text_tokens.mem'
 r.pin(rom)
 staged=OUT.parent/'model/suspect/report_text_tokens.mem'
 staged.parent.mkdir(parents=True,exist_ok=True)
 if staged.exists(): assert h.sha(staged)==h.sha(rom)
 else: shutil.copyfile(rom,staged)
 src=ROOT/'tests/paper_eject/tb_common_write_completion.sv'
 files=[ROOT/'01_rtl'/x for x in ('secondary_top.v','grbl_uart.v','grbl_reporter_shared_candidate.v',
  'grbl_shared_transport_candidate.v','grbl_line_formatter.v','grbl_response_parser.v',
  'grbl_vector_font_rom.v')]
 log=r.sim('actual_chain',[stubs,*files,src],
  'tb_common_write_completion','COMMON_WRITE_COMPLETION_PASS',novopt=True)
 r.scope.append(dict(test='Actual top physical KEY1/KEY2 with production reporter, transport, formatter and parser',
  records=re.findall(r'(?:PASS CHAIN|COMMON_WRITE_COMPLETION_PASS)[^\r\n]*',log)))
 physical=ROOT/'tests/paper_eject/tb_common_write_uart.sv'
 log=r.sim('actual_uart_chain',[stubs,*files,physical],
  'tb_common_write_uart','COMMON_WRITE_UART_PASS',novopt=True)
 r.scope.append(dict(test='Same completion chain with production UART port and 8N1 controller model',
  records=re.findall(r'(?:PASS CHAIN|COMMON_WRITE_UART_PASS)[^\r\n]*',log)))
 r.limits=['Inference, DDR, network and nonrelevant document interface are controlled peripherals.',
  'No pending, owner, reporter, transport, ACK or completion register is forced or deposited.',
  'KEY1/KEY2 debounce and hold limits shortened only; report data and paper accounting remain production values.',
  'First test controls UART byte handshake. Second test uses production UART at CLK_HZ/BAUD=460800/115200.',
  'Physical UART signal integrity and actual GRBL responses remain NOT_RUN.',
  'Positive-flow simulation does not establish the cause of hardware recovery faults.']
except Exception as exc:error=repr(exc)
result=r.finish(error)
summary=dict(status=result['status'],report=str(OUT/'RESULTS.json'),error=error)
h.dump(ROOT/'reports/common_write_completion/LATEST.json',summary)
print(json.dumps(summary),flush=True)
raise SystemExit(0 if result['status']=='PASS' else 1)
