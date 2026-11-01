"""Aggregate R4 core, production-top source, and shared-recovery evidence."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '02_sim/vector_reset_r4'
SIM = Path('E:/model/win64')
env = os.environ.copy()
env.update(MGLS_LICENSE_FILE=str(SIM / 'LICENSE.TXT'), LM_LICENSE_FILE=str(SIM / 'LICENSE.TXT'))

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()

def run(label, command):
    p = subprocess.run([v.as_posix() if isinstance(v, Path) else str(v) for v in command], cwd=ROOT,
        env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    (OUT / (label + '.log')).write_text(p.stdout)
    if p.returncode or re.search(r'\*\*\s+(Error|Fatal):', p.stdout):
        raise SystemExit(label + ' failed:\n' + p.stdout[-5000:])
    return p.stdout

core = json.loads((OUT / 'RESULTS_CORE.json').read_text())
shared_path = ROOT / '02_sim/top_doc_shared_recovery_r4/RESULTS.json'
shared = json.loads(shared_path.read_text())
assert core['status'].startswith('PASS_CORE') and shared['status'] == 'PASS'
inputs = dict(core['input_hashes'])
for p, digest in shared['input_hashes'].items():
    assert p not in inputs or inputs[p] == digest, 'overlapping test input mismatch: ' + p
    inputs[p] = digest
extra = [ROOT / p for p in ['02_sim/tb_top_report_source.sv', 'tools/run_top_doc_shared_recovery.py']]
extra.append(Path(__file__))
inputs.update({str(p.resolve()): sha(p) for p in extra})
assert all(sha(Path(p)) == digest for p, digest in inputs.items()), 'R4 validated inputs changed before aggregation'
run('top_source_compile', [SIM / 'vlog.exe', '-sv', '-lint', '-work', OUT / 'topwork',
    ROOT / '02_sim/tb_top_report_source.sv'])
text = run('tb_top_report_source', [SIM / 'vsim.exe', '-c', '-quiet', '-lib', OUT / 'topwork',
    'tb_top_report_source', '-do', 'run -all; quit -f'])
assert 'PASS TOP_SOURCE' in text
assert all(sha(Path(p)) == digest for p, digest in inputs.items()), 'R4 validated inputs changed during final check'
core['status'] = 'PASS'
core['input_hashes'] = inputs
core['tests']['tb_top_report_source'] = {'status':'PASS','evidence':'RERUN_R4',
    'scope':'Production top source/ID/pending latches with controlled physical/inference/reporter leaves',
    'checks':[line.strip('# ') for line in text.splitlines() if 'PASS' in line]}
core['tests']['tb_top_doc_shared_recovery'] = {'status':'PASS','evidence':'RERUN_R4',
    'scope':shared['scope'],'checks':shared['checks'],'results':str(shared_path),
    'results_sha256':sha(shared_path)}
core['duplicate_scope'] = 'Last accepted (source, session, job) key only, matching prior one-entry duplicate cache lifetime; no permanent cross-session exactly-once claim.'
(OUT / 'RESULTS.json').write_text(json.dumps(core, indent=2))
print('PASS R4 FULL: core same-source per-cycle equivalence, 5 source tags, top wiring, shared UART recovery, KEY3/KEY4/last-ok/newline')
print('Frozen validation inputs:', len(inputs))
