"""Fail closed on post-freeze source drift; does not change any build input."""
import hashlib
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / '01_rtl/imgq_gain_m/main/td_project_compact_v2'
def main():
    obj = json.loads((RUN / 'source_snapshot.json').read_text(encoding='utf-8-sig'))
    errors = []
    if not obj['passed']:
        errors.append('Original snapshot was rejected')
    for item in obj['files']:
        p = Path(item['path'])
        if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest().upper() != item['sha256']:
            errors.append('Frozen input drift: ' + str(p))
    print(json.dumps({'passed': not errors, 'errors': errors}, indent=2))
    return int(bool(errors))
if __name__ == '__main__':
    raise SystemExit(main())
