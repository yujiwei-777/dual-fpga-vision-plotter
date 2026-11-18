"""Run complementary fresh regressions without repeating the preserved suite."""
from pathlib import Path
from datetime import datetime, timezone
import argparse, hashlib, json, subprocess, sys

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/cnn_key1_complement'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
OUT.mkdir(parents=True)
JOBS=[
 ('document_integrated','tests/operator_ui/run_doc_mapper_integrated.py'),
 ('doc_total_ack','tests/run_doc_total_ack.py'),
 ('common_write','tools/run_common_write_completion.py'),
 ('paper_eject','tools/run_paper_eject_regression.py'),
 ('paper_document','tools/run_paper_document_regression.py'),
 ('paper_unlimited','tools/run_paper_unlimited.py'),
 ('no_suspect','tools/run_no_suspect_paper.py'),
 ('write_repeat','tools/run_write_repeat_targeted.py'),
 ('initial_uart','tools/run_initial_uart.py'),
 ('maintenance','tools/run_unlimited_maintenance.py'),
 ('center80','tools/run_doc_center80.py'),
 ('production_doc_feed','tools/run_production_doc_feed.py'),
 ('continuous_cnn_key1','tests/validate_continuous_key1.py'),
]
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
parser=argparse.ArgumentParser()
parser.add_argument('--start-at',default='document_integrated')
args=parser.parse_args()
assert args.start_at in [x[0] for x in JOBS]
JOBS=JOBS[[x[0] for x in JOBS].index(args.start_at):]
rows=[]
for label,rel in JOBS:
    script=ROOT/rel
    cmd=[sys.executable,'-B',str(script)]
    if label=='continuous_cnn_key1':cmd+=['--design',str(ROOT),'--expect-fixed']
    log=OUT/(label+'.log')
    with log.open('xb') as stream:
        cp=subprocess.run(cmd,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
    row=dict(label=label,returncode=cp.returncode,log=str(log),log_sha256=sha(log),command=cmd)
    rows.append(row)
    (OUT/'PROGRESS.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')
    print(label,cp.returncode,str(log),flush=True)
    if cp.returncode:raise SystemExit(cp.returncode)
(OUT/'RESULT.json').write_text(json.dumps(dict(status='PASS',commands=rows),indent=2)+'\n',encoding='utf-8')
print(json.dumps(dict(status='PASS',report=str(OUT/'RESULT.json'))),flush=True)
