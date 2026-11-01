from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '02_sim/vector_reset_r2'
OUT.mkdir(exist_ok=True)
SIM = Path('E:/model/win64')
env = os.environ.copy()
env.update(MGLS_LICENSE_FILE=str(SIM / 'LICENSE.TXT'), LM_LICENSE_FILE=str(SIM / 'LICENSE.TXT'))
prior_path = ROOT / '02_sim/vector_reset_regression/RESULTS.json'
prior = json.loads(prior_path.read_text())
assert prior['status'] == 'PASS'
(OUT / 'PRIOR_RESULTS.json').write_text(json.dumps(prior, indent=2))

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()

def run(name, args):
    p = subprocess.run([a.as_posix() if isinstance(a, Path) else str(a) for a in args], cwd=ROOT, env=env, text=True,
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    (OUT / (name + '.log')).write_text(p.stdout)
    if p.returncode or re.search(r'\*\*\s+(?:Error|Fatal):', p.stdout):
        raise SystemExit(name + ' failed:\n' + p.stdout[-3000:])
    return p.stdout

run('prepare_top_control', [sys.executable, ROOT / 'tools/prepare_top_pending_test.py'])
source = [ROOT / x for x in (ROOT / 'lint_full.f').read_text().splitlines() if x.strip()]
tops = {
    'tb_grbl_vector_completion': 'PASS VECTOR_COMPLETION_ALL',
    'tb_grbl_key2_last_ok_ctrl': 'PASS KEY2 repeated presses',
    'tb_grbl_reporter_key1_vector': 'PASS KEY1 single-line vector',
    'tb_grbl_completion_priority': 'PASS KEY4 priority',
    'tb_grbl_key1_job_guard': 'PASS KEY1 job guard:',
}
benches = [ROOT / '02_sim' / (name + '.sv') for name in tops if name != 'tb_grbl_key1_job_guard']
benches += [ROOT / 'shared/tests/tb_grbl_key1_job_guard.sv', ROOT / '02_sim/testmodels/ph1p_logic_eram_stub.sv']
inputs = set(Path(p) for p in prior['input_hashes'])
inputs.update(benches)
inputs.update([ROOT / '02_sim/tb_secondary_key2_reset_pending.sv',
               OUT / 'secondary_top_leaf_stubs.sv', ROOT / 'tools/prepare_top_pending_test.py', Path(__file__)])
before = {str(p.resolve()): sha(p) for p in inputs}
run('vlib', [SIM / 'vlib.exe', OUT / 'work'])
run('lint_full', [SIM / 'vlog.exe', '-sv', '-lint', '-work', OUT / 'work', *source, *benches])
tests = {}
for name, marker in tops.items():
    text = run(name, [SIM / 'vsim.exe', '-c', '-quiet', '-lib', OUT / 'work', name, '-do', 'run -all; quit -f'])
    assert marker in text, name + ' missing pass marker'
    tests[name] = {'status': 'PASS', 'evidence': 'RERUN_R2',
                   'checks': [line.strip('# ') for line in text.splitlines() if 'PASS' in line]}
    print(name + ': PASS', flush=True)
run('top_vlib', [SIM / 'vlib.exe', OUT / 'topwork'])
run('top_compile', [SIM / 'vlog.exe', '-sv', '-lint', '-work', OUT / 'topwork',
                    OUT / 'secondary_top_leaf_stubs.sv', ROOT / '01_rtl/secondary_top.v',
                    ROOT / '02_sim/tb_secondary_key2_reset_pending.sv'])
text = run('tb_secondary_key2_reset_pending', [SIM / 'vsim.exe', '-c', '-quiet', '-lib', OUT / 'topwork',
                  'tb_secondary_key2_reset_pending', '-do', 'run -all; quit -f'])
assert 'PASS production-top KEY4 clears pending' in text
tests['tb_secondary_key2_reset_pending'] = {
    'status': 'PASS', 'evidence': 'RERUN_R2',
    'scope': 'Production top pending/controller/reset/admission with test-only leaf interfaces; not a DDR/UART/inference simulation',
    'checks': [line.strip('# ') for line in text.splitlines() if 'PASS' in line],
}
print('tb_secondary_key2_reset_pending: PASS', flush=True)
text = run('integer_reference', [sys.executable, ROOT / 'tools/check_vector_reference.py'])
tests['integer_reference'] = {'status': 'PASS', 'evidence': 'RERUN_R2', 'checks': [text.strip()]}

# These independent benches instantiate neither secondary_top nor grbl_streamer.
# Retain their exact original logs and input hashes, checking every other
# previously hashed input is still byte-identical. Do not label them rerun.
changed = {str(ROOT / '01_rtl/grbl_streamer.v'), str(ROOT / '01_rtl/secondary_top.v'),
           str(ROOT / '02_sim/tb_grbl_completion_priority.sv')}
unchanged = {p: h for p, h in prior['input_hashes'].items() if p not in changed}
assert all(sha(Path(p)) == h for p, h in unchanged.items()), 'unexpected dependency changed'
for name in ['tb_doc_grbl_plotter_last_ok', 'tb_hxa_job_cancel_classification', 'tb_pcb_fullboard_binary_conv4_4']:
    tests[name] = dict(prior['tests'][name])
    tests[name].update(evidence='REUSED_UNCHANGED_DEPENDENCIES',
                       prior_results=str(prior_path),
                       prior_log=str(prior_path.parent / (name + '.log')),
                       dependency_hash_audit='all prior hashed inputs except explicit top/streamer/priority test changes are identical')
    print(name + ': original PASS retained; dependencies unchanged', flush=True)
after = {str(p.resolve()): sha(p) for p in inputs}
assert after == before, 'inputs changed during R2 validation'
summary = {
    'status': 'PASS', 'revision': 'r2_key4_priority_and_pending',
    'baseline_bit_sha256': prior['baseline_bit_sha256'], 'input_hashes': before,
    'tests': tests, 'protected_source_model_invariants': prior['protected_source_model_invariants'],
    'prior_results': str(prior_path), 'hardware_status': 'NOT_RUN',
    'ordinary_cnn_inference': prior['ordinary_cnn_inference'],
    'formal_bit': 'NOT_GENERATED; fresh routed R2 release gates pending',
}
(OUT / 'RESULTS.json').write_text(json.dumps(summary, indent=2))
print('PASS R2 KEY4 priority/pending control with scoped regression and explicit unchanged evidence')
