"""Publish current CNN candidates using the exact frozen confidence ROM."""
from pathlib import Path
from datetime import datetime, timezone
import argparse, importlib.util, json, shutil, sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--run',type=Path,default=Path('E:/codex_pcb_runtime_fix_secondary_20261111_r1'))
RUN=parser.parse_args().run.resolve()
helper=ROOT/'tools/run_retrained_preserved_regressions.py'
s=importlib.util.spec_from_file_location('current_publication_r6',helper)
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
OUT=ROOT/'reports/suspect_trial'/('r6_publication_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
r=m.Run(ROOT,OUT)
rom=ROOT/'model/suspect/confidence_0_100.mem'
staged=OUT.parent/'model/suspect/confidence_0_100.mem'
staged.parent.mkdir(parents=True,exist_ok=True)
if staged.exists():assert m.sha(staged)==m.sha(rom)
else:shutil.copy2(rom,staged)
assert m.sha(rom)==m.sha(staged)==m.sha(RUN/'model/suspect/confidence_0_100.mem')
r.pin(helper,Path(__file__),RUN/'SOURCE_MANIFEST.json',rom,staged)
error=None
try:m.publication(r)
except Exception as exc:error=repr(exc)
result=r.finish(error)
print(json.dumps(dict(status=result['status'],report=str(OUT/'RESULTS.json'),sha256=m.sha(OUT/'RESULTS.json'))))
raise SystemExit(0 if result['status']=='PASS' else 1)
