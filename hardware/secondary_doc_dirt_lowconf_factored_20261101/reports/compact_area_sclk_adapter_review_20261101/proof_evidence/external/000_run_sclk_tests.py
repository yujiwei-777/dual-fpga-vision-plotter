"""Read-only Tcl object proof regression; never invokes TD or a simulator."""
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
PROJECT = HERE.parent / 'secondary_cnn_key3_stroke_compact_20261101'
HOOK = HERE / '04_pin/clocktrace_sclk/prove_key3_supervisor_clocktrace.tcl'
OLD_HARNESS = PROJECT / 'reports/key3_clocktrace_verification_20261031/clock_source/test_clocktrace_hook.tcl'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main():
    inputs = [Path(__file__).resolve(), HOOK, OLD_HARNESS, HERE / 'test_sclk_cases.tcl',
              *sorted((HERE / 'fixtures').glob('*.txt')),
              *sorted((HERE / '04_pin').glob('*.tcl')),
              *[PROJECT / '04_pin' / name for name in ['prove_key3_supervisor_clocktrace.tcl', 'apply_reset_exceptions.tcl', 'apply_cdc_exceptions.tcl']],
              Path('E:/td/arch/ph1p_macro.v'), Path('E:/td/template/verilog/Device-Primitive/PH1P/Clock/ph1p_clock.v'),
              Path('E:/td/doc/UG1310_PH1P_Libraries_Guide_for_HDL_Designs.pdf')]
    hashes = {str(path.resolve()): sha(path) for path in inputs}
    output = HERE / ('unit_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
    output.mkdir()
    old = OLD_HARNESS.read_text(encoding='utf-8')
    old = old.replace('set here [file dirname [file normalize [info script]]]', f'set here {{{(HERE / "fixtures").as_posix()}}}', 1)
    old = old.replace('set root [file join [file dirname $here] secondary_cnn_key3_stroke_release_20261031]', f'set root {{{HERE.as_posix()}}}', 1)
    old = old.replace('source [file join $root 04_pin prove_key3_supervisor_clocktrace.tcl]', 'source [file join $root 04_pin clocktrace_sclk prove_key3_supervisor_clocktrace.tcl]', 1)
    marker = 'set failed 0; set positive 0; set negative 0'
    assert old.count(marker) == 1
    old = old.replace(marker, (HERE / 'test_sclk_cases.tcl').read_text() + '\n' + marker, 1)
    script = output / 'generated_test.tcl'
    script.write_text(old, encoding='utf-8')
    tcl = shutil.which('tclsh') or shutil.which('tclsh86')
    assert tcl, 'A Tcl interpreter is required'
    result = subprocess.run([tcl, str(script)], cwd=output, capture_output=True, text=True, timeout=90)
    (output / 'stdout.log').write_text(result.stdout, encoding='utf-8')
    (output / 'stderr.log').write_text(result.stderr, encoding='utf-8')
    cases, summaries = [], []
    for line in result.stdout.splitlines():
        if line.startswith('RESULT '):
            cases.append(json.loads(line[7:]))
        elif line.startswith('SUMMARY '):
            summaries.append(json.loads(line[8:]))
    unchanged = all(sha(Path(path)) == digest for path, digest in hashes.items())
    proof_reports = list(output.glob('secondary_key3_*.rpt'))
    proofs_valid = len(proof_reports) == 3
    for path in proof_reports:
        text = path.read_text()
        proofs_valid &= (len(re.findall(r'^KEY3_REGISTER_PROVEN ', text, re.M)) == 26
                         and len(re.findall(r'^KEY3_STAGE_PROVEN ', text, re.M)) == 2
                         and len(re.findall(r'^KEY3_PROOF_PASS$', text, re.M)) == 1
                         and 'CLK=I_sys_clk' in text and 'REGISTER_COUNT=26' in text
                         and len(re.findall(r'^KEY3_REGISTER_PROVEN .*CLOCK_PROOF=.*SCLK_STATIC', text, re.M)) == 26)
    passed = (result.returncode == 0 and len(summaries) == 1 and summaries[0]['failed'] == 0
              and summaries[0]['cases'] == len(cases) and unchanged and proofs_valid)
    report = dict(passed=passed, hook_sha256=sha(HOOK), hook_path=str(HOOK.resolve()),
                  summary=summaries, cases=cases, input_sha256=hashes,
                  inputs_unchanged=unchanged, tcl_executable=tcl, tcl_exit_code=result.returncode,
                  full_supervisor_reports_valid=bool(proofs_valid),
                  evidence_sha256={str(path.resolve()): sha(path) for path in [script, output / 'stdout.log', output / 'stderr.log', *proof_reports]},
                  td_invoked=False, rtl_simulation_invoked=False, timing_exceptions_installed=False,
                  limits=['Pure Tcl mocked database; requires a separate live mapped/routed proof.',
                          'Original 26 register proof and original maximum trace depth are unchanged.'])
    report_path = output / 'RESULTS.json'
    report_path.write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(dict(passed=passed, summary=summaries, hook_sha256=report['hook_sha256'], report=str(report_path))))
    if not passed:
        print(result.stderr)
        print('\n'.join(line for line in result.stdout.splitlines() if any(word in line for word in ['HARNESS_ERROR', 'UNEXPECTED_REJECTION', 'MISSING_OR_WRONG_REJECTION'])))
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
