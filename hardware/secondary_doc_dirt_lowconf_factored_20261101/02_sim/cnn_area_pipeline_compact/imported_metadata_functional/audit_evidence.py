"""Read all completed RTL evidence; write a fresh immutable final audit."""
from pathlib import Path
import hashlib
import json
import re
import run_regression as regression

HERE = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def main():
    regression.verify()
    final = json.loads((HERE / 'RESULTS.json').read_text())
    assert final['status'] == 'PASS_SCRATCH_RTL_EXACT_CYCLE'
    for name,digest in final['evidence_sha256'].items():
        assert sha(HERE/name) == digest, name
    assert len(final['generic_miter_modes']) == 40
    assert len(final['lifecycle_modes']) == 10
    warnings = {}
    logs = sorted(HERE.glob('*.log'))
    assert len(logs) == 54, len(logs)
    for path in logs:
        text = path.read_text(errors='replace')
        assert not re.search(r'\*\*\s+(?:Error|Fatal):', text), path.name
        for line in text.splitlines():
            if '** Warning:' in line:
                match = re.search(r'\*\* Warning: \((?:vsim|vlog)-(\d+)\)', line)
                assert match and match[1] == '8891', (path.name,line)
                warnings[match[1]] = warnings.get(match[1],0)+1
    audit = {'status':'PASS_SEALED_EVIDENCE_AUDIT',
        'candidate_sha256':final['candidate_sha256'],
        'results_sha256':sha(HERE/'RESULTS.json'),
        'quick_results_sha256':sha(HERE/'QUICK_RESULTS.json'),
        'runner_sha256':sha(HERE/'run_regression.py'),
        'audit_runner_sha256':sha(__file__),
        'logs_checked':len(logs), 'accepted_warning_codes':warnings,
        'warning_8891_reason':'Unoptimized -novopt visibility used by original exact-cycle testbench',
        'all_result_evidence_hashes_verified':True,
        'all_inputs_and_origins_verified':True,
        'production_modified':False,'parent_candidate_modified':False,
        'hardware_status':'NOT_RUN'}
    with (HERE/'FINAL_AUDIT.json').open('x',encoding='utf-8',newline='\n') as stream:
        stream.write(json.dumps(audit,indent=2)+'\n')
    print(json.dumps(audit),flush=True)


if __name__=='__main__':
    main()
