"""Index current successful regression receipts against the immutable build."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json
ROOT=Path(__file__).resolve().parents[1]
BUILD=Path('E:/codex_secondary_paper_unlimited_autoconnect_20261118_r1')
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def load(p): return json.loads(Path(p).read_text(encoding='utf-8-sig'))
gate=ROOT/'reports/airwalk_signoff'/BUILD.name/'FUNCTIONAL_GATE.json'
value=load(gate)
assert value['status']=='PASS_CURRENT_FUNCTIONAL_GATE'
manifest=BUILD/'SOURCE_MANIFEST.json'
assert sha(manifest)==value['source_manifest_sha256']
checked={}
for rel,row in load(manifest)['files'].items():
 if rel.startswith(('01_rtl/','shared/','04_pin/','model/','main/')):
  assert sha(ROOT/rel)==sha(BUILD/rel)==row['sha256']
  checked[rel]=row['sha256']
receipts={}
for name,row in value['groups'].items():
 assert sha(row['path'])==row['sha256']
 assert load(row['path'])['status'].startswith('PASS')
 receipts[name]={'path':row['path'],'sha256':row['sha256']}
summary={
 'status':'PASS_CURRENT_SECONDARY_REPEAT_REGRESSIONS',
 'generated_utc':datetime.now(timezone.utc).isoformat(),
 'source_root':str(ROOT),'build':str(BUILD),
 'source_manifest':{'path':str(manifest),'sha256':sha(manifest)},
 'functional_gate':{'path':str(gate),'sha256':sha(gate)},
 'current_production_files_checked':len(checked),
 'production_inputs':checked,'receipts':receipts,
 'findings':[
  'Readonly control reproduces stale local KEY1 ownership after pre-start admission refusal error10; current full top releases it and admits a following KEY1 without reset.',
  'Real reporter/shared transport targeted scenarios preserve Alarm/Reset/UART safety locks and prohibit status-only completion or duplicate-ID movement replay.',
  'Actual top completion chain and production UART model complete consecutive CNN, fresh PCB inspections and KEY2 reports without a normal final Idle query or reset.',
  'Ordinary CNN/PCB/DDR/reader/HXA FIFO and CRC, cached snapshot, document mapper and total ACK, paper handling and no-SUSPECT paper contracts pass against this source freeze.'
 ],
 'limitations':[
  'Successful-writing hardware lock symptom has not been reproduced; admission error10 is a proven defect but cannot be claimed as the only hardware cause.',
  'Real recovery faults, paper full, waiting for paper confirmation and consumed PCB results remain intentional blockers.',
  'Source-bound functional validation does not replace routed setup/hold, DRC, physical capacity, read-only import or bit generation.',
  'Physical machine, roller, UART signal integrity and 125MHz device behavior remain NOT_RUN.'
 ],
 'hardware_status':'NOT_RUN','bitgen_allowed':False
}
out=ROOT/'reports/WRITE_REPEAT_VALIDATION.json'
out.write_text(json.dumps(summary,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'status':summary['status'],'report':str(out),'sha256':sha(out),'checked':len(checked)}))
