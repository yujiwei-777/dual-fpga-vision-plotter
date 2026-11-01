"""Archive exact reviewed test bytes into the independent compact root.

No existing file is overwritten. Original source and evidence files are read
only. The archive records the original absolute path and its local equivalent.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent / 'proof_evidence'
HOOK = ROOT / '04_pin/clocktrace_sclk/prove_key3_supervisor_clocktrace.tcl'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def require(value, reason):
    if not value:
        raise RuntimeError(reason)


def create(path, content):
    require(path.resolve().is_relative_to(ROOT) and not path.exists(),
            'Archive output must be new and inside the independent root')
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('xb') as stream:
        stream.write(content)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('report', type=Path)
    args = parser.parse_args()
    origin_report = args.report.resolve()
    data = json.loads(origin_report.read_text(encoding='utf-8-sig'))
    require(data.get('passed') is True and data.get('hook_sha256') == sha(HOOK),
            'Final report does not name the applied reviewed hook')
    require(not OUT.exists(), 'Never overwrite an evidence archive')
    local_report = OUT / 'RESULTS.json'
    create(local_report, origin_report.read_bytes())
    records, copies = [], {}
    pins = {local_report.relative_to(ROOT).as_posix(): sha(local_report)}
    for group in ('input_sha256', 'evidence_sha256'):
        require(isinstance(data.get(group), dict) and data[group], 'Missing exact test evidence list')
        for origin, expected in data[group].items():
            path = Path(origin).resolve()
            require(path.is_file() and sha(path) == expected,
                    'Original test evidence changed: ' + str(path))
            if path in copies:
                local = copies[path]
            elif path.is_relative_to(ROOT):
                local = path
                copies[path] = local
            elif path == Path(data['hook_path']).resolve():
                require(sha(HOOK) == expected, 'Applied hook differs from tested candidate')
                local = HOOK
                copies[path] = local
            else:
                local = OUT / 'external' / (f'{len(copies):03d}_' + path.name)
                create(local, path.read_bytes())
                copies[path] = local
            relative = local.relative_to(ROOT).as_posix()
            require(sha(local) == expected, 'Local archive copy differs')
            pins[relative] = expected
            records.append({'group': group, 'origin': origin, 'local': relative, 'sha256': expected})
    manifest = OUT / 'ARCHIVE_MANIFEST.json'
    value = {'passed': True, 'report_origin': str(origin_report),
             'report_local': local_report.relative_to(ROOT).as_posix(),
             'report_sha256': sha(local_report), 'files': records,
             'archive_script_sha256': sha(Path(__file__)),
             'scope': 'Exact copies of mocked-proof source/evidence; no physical acceptance.'}
    create(manifest, (json.dumps(value, indent=2) + '\n').encode('utf-8'))
    pins[manifest.relative_to(ROOT).as_posix()] = sha(manifest)
    # Include the archiving procedure too; its digest is already in the
    # manifest, so it cannot be silently replaced after review.
    pins[Path(__file__).relative_to(ROOT).as_posix()] = sha(Path(__file__))
    print(json.dumps({'hook_sha256': sha(HOOK),
                      'PROOF_TEST_REPORT': local_report.relative_to(ROOT).as_posix(),
                      'PROOF_ARCHIVE_MANIFEST': manifest.relative_to(ROOT).as_posix(),
                      'PROOF_TEST_INPUTS': pins}, indent=2))


if __name__ == '__main__':
    main()
