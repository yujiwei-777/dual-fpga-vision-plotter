"""Run six fresh release suites; area proof is independently orchestrated."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'reports/compact_regression_commands'
JOBS = (
    ('top', 'run_cnn_top_regression.py', ()),
    ('key3', 'run_key3_top_reset.py', ('--output', '02_sim/key3_top_reset_release')),
    ('pcb', 'run_cnn_named_pcb_regression.py', ()),
    ('report', 'run_cnn_named_report_regression.py', ()),
    ('cnn_core', 'run_cnn_stability_core.py', ()),
    ('stroke', 'run_stroke_split_regression.py', ('--output', '02_sim/stroke_release')),
)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def main():
    OUT.mkdir(exist_ok=False)
    records = []
    for name, runner, extra in JOBS:
        command = [sys.executable, str(ROOT / 'tools' / runner), *extra]
        before = sha(ROOT / 'tools' / runner)
        print('START ' + name, flush=True)
        with (OUT / (name+'.log')).open('x', encoding='utf-8') as stream:
            result = subprocess.run(command, cwd=ROOT, stdin=subprocess.DEVNULL,
                stdout=stream, stderr=subprocess.STDOUT, timeout=5400,
                creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        assert before == sha(ROOT / 'tools' / runner)
        record = {'name': name, 'command': command, 'returncode': result.returncode,
            'runner_sha256': before, 'log_sha256': sha(OUT/(name+'.log'))}
        with (OUT/(name+'_command.json')).open('x', encoding='utf-8') as stream:
            json.dump(record, stream, indent=2)
        assert result.returncode == 0, str(OUT/(name+'.log'))
        records.append(record)
        print('DONE ' + name, flush=True)
    with (OUT/'RESULTS.json').open('x', encoding='utf-8') as stream:
        json.dump({'status': 'PASS_SIX_FRESH_COMMANDS_RETURNED_ZERO', 'records': records,
            'limits': 'Per-suite strict regression gates still mandatory; no physical acceptance.',
            'hardware_status': 'NOT_RUN'}, stream, indent=2)


if __name__ == '__main__':
    main()
