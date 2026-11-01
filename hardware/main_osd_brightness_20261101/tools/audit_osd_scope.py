"""Compare copied baseline inputs and record the permitted display-only delta."""
import csv
import hashlib
import json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent / 'main_osd_large_font_20261030'
HDL = '01_rtl/imgq_gain_m/main/user_source/hdl_source/'
ALLOWED = {HDL + name for name in ('hdmi_mixer.v', 'design_top_wrapper.v', 'osd_large_font_rom.v', 'pcb_status_large_text.v', 'result_overlay.v', 'hxa_multibox_overlay.v')}
NEW = [HDL + name for name in ('osd_compact_font_rom.v', 'osd_compact_panel.v', 'osd_decimal_snapshot.v', 'osd_compact_glyphs.vh')]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def main():
    checked, changed, errors = [], [], []
    with (ROOT / 'tools/baseline_sources.csv').open(encoding='utf-8-sig', newline='') as fp:
        for row in csv.DictReader(fp):
            rel = Path(row['Path']).relative_to(BASE).as_posix()
            p = ROOT / rel
            item = {'path': rel, 'baseline_sha256': row['SHA256'], 'sha256': sha(p) if p.is_file() else None}
            checked.append(item)
            if not p.is_file(): errors.append('Missing baseline input: ' + rel)
            elif item['sha256'] != row['SHA256']:
                changed.append(rel)
                if rel not in ALLOWED: errors.append('Non-OSD baseline input changed: ' + rel)
            if p.is_file() and p.stat().st_nlink != 1: errors.append('Input has multiple hardlinks: ' + rel)
            if not p.resolve().is_relative_to(ROOT): errors.append('Resolved input escapes copy: ' + rel)
            for ancestor in [p, *p.parents]:
                if ancestor.exists() and getattr(ancestor.stat(follow_symlinks=False), 'st_file_attributes', 0) & 0x400:
                    errors.append('Reparse point in input path: ' + str(ancestor))
                if ancestor == ROOT: break
    new = []
    for rel in NEW:
        p = ROOT / rel
        new.append({'path': rel, 'sha256': sha(p) if p.is_file() else None})
        if not p.is_file(): errors.append('New OSD source missing: ' + rel)
    result = {'passed': not errors, 'baseline_count': len(checked), 'changed': changed, 'errors': errors, 'baseline_files': checked, 'new_files': new, 'scope': 'Source isolation and display-only delta; not a claim of completed simulation or hardware verification.'}
    out = ROOT / 'reports/osd_source_scope.json'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps({k: result[k] for k in ('passed', 'baseline_count', 'changed', 'errors')}, indent=2))
    return int(bool(errors))
if __name__ == '__main__':
    raise SystemExit(main())
