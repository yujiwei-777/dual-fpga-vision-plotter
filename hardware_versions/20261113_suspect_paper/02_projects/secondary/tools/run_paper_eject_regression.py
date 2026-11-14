"""Current production reporter/transport/page maintenance, byte-level regression."""
from pathlib import Path
from datetime import datetime, timezone
import importlib.util, json, shutil, sys
ROOT=Path(__file__).resolve().parents[1]
helper=ROOT/'tools/run_retrained_preserved_regressions.py'
spec=importlib.util.spec_from_file_location('paper_helper',helper)
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
out=ROOT/'reports/paper_eject'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
r=h.Run(ROOT,out);r.pin(Path(__file__),helper)
error=None
try:
    rom=ROOT/'model/suspect/report_text_tokens.mem';r.pin(rom)
    staged=out.parent/'model/suspect/report_text_tokens.mem';staged.parent.mkdir(parents=True,exist_ok=True)
    if staged.exists():assert h.sha(staged)==h.sha(rom)
    else:shutil.copyfile(rom,staged)
    declarations=h.top_declarations(r)
    names=['pll','PLL','secondary_ddr_wrapper','reset_sync','hxa_ddr_store','uiudp_stack',
      'vision_pixel_reader','vision_pipeline','hxa_config_store','hxa_secondary_link',
      'grbl_uart_port','grbl_reporter_shared_candidate','grbl_shared_transport_candidate',
      'doc_copy_pipeline_shared_candidate','rgmii_interface']
    stubs=out/'top_interfaces.sv'
    stubs.write_text('\n'.join(declarations[n]+'\nendmodule\n' for n in names)+
        '\nmodule PH1P_LOGIC_BUFG(input i,output o);assign o=i;endmodule\n')
    r.sim('metadata',[stubs,ROOT/'01_rtl/secondary_top.v',ROOT/'tests/paper_eject/tb_operator_metadata.sv'],
        'tb_operator_metadata','OPERATOR_METADATA_PASS',novopt=True)
    r.sim('key2',[ROOT/'01_rtl/secondary_top.v',ROOT/'tests/paper_eject/tb_key2_operator.sv'],
        'tb_key2_operator','KEY2_OPERATOR_PASS')
    files=[ROOT/'01_rtl'/x for x in ('grbl_reporter_shared_candidate.v',
        'grbl_shared_transport_candidate.v','grbl_line_formatter.v','grbl_response_parser.v','grbl_vector_font_rom.v')]
    r.sim('robust_transport',[ROOT/'01_rtl'/x for x in ('grbl_shared_transport_candidate.v','grbl_line_formatter.v','grbl_response_parser.v')]+[ROOT/'tests/paper_eject/tb_robust_transport.sv'],
        'tb_robust_transport','ROBUST_TRANSPORT_PASS')
    r.sim('paper',files+[ROOT/'tests/paper_eject/tb_paper_eject.sv'],
        'tb_paper_eject','PAPER_EJECT_PASS')
except Exception as exc:error=str(exc)
r.limits=['Physical roller direction, traction, usable travel and pen mechanics NOT_RUN.',
  'Paper confirmation walks the configured Y30..Y267 bounds with an anchored Y148.50 centre; +/-20mm loading tolerance leaves 10..287mm physical margins. The local writing limit is 237mm and the UI occupied budget is 227mm.',
  'GRBL ok acknowledges accepted command; only maintenance requires an independent fresh Idle.',
  'Y+297.00mm follows existing downward newline convention; PAPER_FEED_CMM is compile-time configurable.',
  'No Ethernet cancellation dependency, no movement replay. Physical network/ESP32 buffering requires hardware validation.']
result=r.finish(error)
print(json.dumps(dict(status=result['status'],report=str(out/'RESULTS.json'),error=error)))
raise SystemExit(0 if result['status']=='PASS' else 1)
