from pathlib import Path
from datetime import datetime,timezone
import importlib.util,json,shutil
ROOT=Path(__file__).resolve().parents[1];helper=ROOT/'tools/run_retrained_preserved_regressions.py'
s=importlib.util.spec_from_file_location('unlimited_helper',helper);h=importlib.util.module_from_spec(s);s.loader.exec_module(h)
out=ROOT/'reports/paper_unlimited'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ');r=h.Run(ROOT,out);error=None
try:
 r.pin(__file__,helper);rom=ROOT/'model/suspect/report_text_tokens.mem';r.pin(rom)
 staged=out.parent/'model/suspect/report_text_tokens.mem';staged.parent.mkdir(parents=True,exist_ok=True)
 if staged.exists():assert h.sha(staged)==h.sha(rom)
 else:shutil.copyfile(rom,staged)
 r.pin(staged)
 files=[ROOT/'01_rtl'/x for x in ('grbl_reporter_shared_candidate.v','grbl_shared_transport_candidate.v','grbl_line_formatter.v','grbl_response_parser.v','grbl_vector_font_rom.v')]
 r.sim('unlimited',files+[ROOT/'tests/paper_unlimited/tb_paper_unlimited.sv'],'tb_paper_unlimited','PAPER_UNLIMITED_PASS')
except Exception as exc:error=repr(exc)
r.limits=['Actual reporter+shared transport and real parsed ok bytes; UART8N1 exercised in separate real-top suite.','No machine physical motion/roller validation; NOT_RUN.']
v=r.finish(error);print(json.dumps(dict(status=v['status'],report=str(out/'RESULTS.json'),error=error)));raise SystemExit(0 if v['status']=='PASS' else 1)
