from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '02_sim/vector_reset_r4'
OUT.mkdir(exist_ok=True)
SIM = Path('E:/model/win64')
env = os.environ.copy()
env.update(MGLS_LICENSE_FILE=str(SIM / 'LICENSE.TXT'), LM_LICENSE_FILE=str(SIM / 'LICENSE.TXT'))
prior_path = ROOT / '02_sim/vector_reset_r3/RESULTS.json'
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
        raise SystemExit(name + ' failed:\n' + p.stdout[-4000:])
    return p.stdout

run('prepare_top_control', [sys.executable, ROOT / 'tools/prepare_top_pending_test.py', OUT])
run('prepare_equivalence', [sys.executable, ROOT / 'tools/prepare_r4_equivalence.py'])
source = [ROOT / x for x in (ROOT / 'lint_full.f').read_text().splitlines() if x.strip()]
tops = {
    'tb_grbl_vector_completion': 'PASS VECTOR_COMPLETION_ALL',
    'tb_doc_grbl_plotter_last_ok': 'PASS ALL DOC PLOTTER REGRESSIONS',
    'tb_grbl_key2_last_ok_ctrl': 'PASS KEY2 repeated presses',
    'tb_grbl_reporter_key1_vector': 'PASS KEY1 single-line vector',
    'tb_grbl_completion_priority': 'PASS KEY4 priority',
    'tb_grbl_key1_job_guard': 'PASS KEY1 job guard:',
}
benches = [ROOT / '02_sim' / (name + '.sv') for name in tops if name != 'tb_grbl_key1_job_guard']
benches += [ROOT / 'shared/tests/tb_grbl_key1_job_guard.sv', ROOT / '02_sim/testmodels/ph1p_logic_eram_stub.sv']
equivalence = [OUT / 'grbl_reporter_r3_ref.sv', OUT / 'grbl_reporter_r4_equiv.sv']
inputs = set(Path(p) for p in prior['input_hashes'])
inputs.update(source + benches + equivalence)
inputs.update([ROOT / '02_sim/tb_secondary_key2_reset_pending.sv', OUT / 'secondary_top_leaf_stubs.sv',
               ROOT / '02_sim/tb_grbl_job_source.sv', ROOT / 'tools/prepare_r4_equivalence.py',
               ROOT / 'tools/review_remote_physical.py', ROOT / 'tools/prepare_vector_tests.py', Path(__file__)])
before = {str(p.resolve()): sha(p) for p in inputs}
run('vlib', [SIM / 'vlib.exe', OUT / 'work'])
run('lint_full', [SIM / 'vlog.exe', '-sv', '-lint', '-work', OUT / 'work', *source, *benches, *equivalence])
tests = {}
for name, marker in tops.items():
    text = run(name, [SIM / 'vsim.exe', '-c', '-quiet', '-lib', OUT / 'work', name, '-do', 'run -all; quit -f'])
    assert marker in text, name + ' missing pass marker'
    tests[name] = {'status': 'PASS', 'evidence': 'RERUN_R4',
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
    'status': 'PASS', 'evidence': 'RERUN_R4',
    'scope': 'Production top pending/controller/reset/admission with test-only leaf interfaces; not DDR/UART/inference simulation',
    'checks': [line.strip('# ') for line in text.splitlines() if 'PASS' in line],
}
print('tb_secondary_key2_reset_pending: PASS', flush=True)

# Intentional source-namespace admission changes are run without the R3 miter.
run('source_vlib', [SIM / 'vlib.exe', OUT / 'sourcework'])
run('source_compile', [SIM / 'vlog.exe', '-sv', '-lint', '-work', OUT / 'sourcework',
    *source, ROOT / '02_sim/testmodels/ph1p_logic_eram_stub.sv', ROOT / '02_sim/tb_grbl_job_source.sv'])
text = run('tb_grbl_job_source', [SIM / 'vsim.exe', '-c', '-quiet', '-lib', OUT / 'sourcework',
    'tb_grbl_job_source', '-do', 'run -all; quit -f'])
assert 'PASS SOURCE_TAG' in text
tests['tb_grbl_job_source'] = {'status': 'PASS', 'evidence': 'RERUN_R4',
    'checks': [line.strip('# ') for line in text.splitlines() if 'PASS' in line]}
print('tb_grbl_job_source: PASS', flush=True)
text = run('integer_reference', [sys.executable, ROOT / 'tools/check_vector_reference.py'])
tests['integer_reference'] = {'status': 'PASS', 'evidence': 'RERUN_R4', 'checks': [text.strip()]}

changed = {str(ROOT / p) for p in [
    '01_rtl/grbl_reporter.v', '01_rtl/secondary_top.v', '01_rtl/doc_copy_pipeline.v',
    '01_rtl/doc_grbl_plotter.v', '02_sim/tb_grbl_vector_completion.sv',
    '02_sim/tb_grbl_reporter_key1_vector.sv', 'tools/prepare_vector_tests.py', 'tools/review_remote_physical.py']}
unchanged = {p: h for p, h in prior['input_hashes'].items() if p not in changed}
assert all(sha(Path(p)) == h for p, h in unchanged.items()), 'unexpected dependency changed'
for name in ['tb_hxa_job_cancel_classification', 'tb_pcb_fullboard_binary_conv4_4']:
    tests[name] = dict(prior['tests'][name])
    tests[name].update(evidence='REUSED_UNCHANGED_DEPENDENCIES', prior_results=str(prior_path),
        prior_log=str(prior_path.parent / (name + '.log')),
        dependency_hash_audit='all prior hashed inputs except explicit reporter/top/doc admission/comment/test-tool changes are identical')
    print(name + ': original PASS retained; dependencies unchanged', flush=True)
after = {str(p.resolve()): sha(p) for p in inputs}
assert after == before, 'inputs changed during R4 validation'
summary = {
    'status': 'PASS_CORE_PENDING_SHARED_RECOVERY_AND_TOP_SOURCE',
    'revision': 'r4_source_namespace_serial_endpoint_shared_uart_recovery',
    'baseline_bit_sha256': prior['baseline_bit_sha256'], 'input_hashes': before, 'tests': tests,
    'sequential_equivalence': 'All reporter public outputs compared each falling clock to frozen R3 under same-source actual RTL regression stimuli; separate cross-source test covers intentional difference; not formal proof',
    'protected_source_model_invariants': prior['protected_source_model_invariants'], 'prior_results': str(prior_path),
    'hardware_status': 'NOT_RUN', 'ordinary_cnn_inference': prior['ordinary_cnn_inference'],
    'formal_bit': 'NOT_GENERATED; fresh routed R4 release gates pending',
}
(OUT / 'RESULTS_CORE.json').write_text(json.dumps(summary, indent=2))
print('PASS R4 core reporter endpoint/source/reset/last-ok regression; shared-recovery/top-source aggregation pending')
