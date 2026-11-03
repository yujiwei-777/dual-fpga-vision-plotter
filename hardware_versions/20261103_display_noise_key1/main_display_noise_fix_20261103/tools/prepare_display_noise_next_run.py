"""Preserve one failed placement and prepare the next unfrozen build run.

Does not edit product RTL, constraints, active tool RUN, or simulation paths.
"""
import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil

from display_noise_paths import ROOT, NAME, obj, read, sha, put


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--failed-attempt', required=True, type=int)
    args = parser.parse_args()
    attempt, following = args.failed_attempt, args.failed_attempt + 1
    if attempt < 3:
        raise ValueError('Earlier attempts already have their own preserved history')
    parent = ROOT / '01_rtl/imgq_gain_m/main'
    old = parent / f'td_project_display_noise_v{attempt}'
    new = parent / f'td_project_display_noise_v{following}'
    backup = ROOT / f'reports/attempt{attempt}_rtl'
    evidence = ROOT / f'reports/attempt{attempt}_evidence'
    if any(p.exists() for p in (new, backup, evidence)):
        raise ValueError('Refusing to overwrite prepared runs or failure backups')
    snapshot = old / 'source_snapshot.json'
    frozen = obj(snapshot)
    if frozen.get('passed') is not True:
        raise ValueError('Failed run must still have an accepted prebuild snapshot')
    expected = {str(Path(row['path']).resolve()).casefold(): row['sha256'] for row in frozen['files']}
    rels = [
        '01_rtl/imgq_gain_m/main/user_source/hdl_source/design_top_wrapper.v',
        '01_rtl/imgq_gain_m/main/user_source/hdl_source/a4_display_spatial_h1.v',
        '01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/display_tone_96.v',
    ]
    for rel in rels:
        p = ROOT / rel
        if sha(p) != expected[str(p.resolve()).casefold()]:
            raise ValueError('Product has changed before failure backup: ' + rel)
    if not (old / '.opt_place.error.f').is_file() or (old / '.opt_place.end.f').exists():
        raise ValueError('Expected an unsuccessful completed placement attempt')
    backup.mkdir(parents=True)
    evidence.mkdir(parents=True)
    rtl = []
    for rel in rels:
        p, target = ROOT / rel, backup / Path(rel).name
        shutil.copy2(p, target)
        digest = expected[str(p.resolve()).casefold()]
        if sha(target) != digest:
            raise ValueError('Frozen RTL backup byte mismatch')
        rtl.append({'source': str(p), 'backup': str(target), 'sha256': digest,
                    'snapshot_sha256': digest})
    put(backup / 'manifest.json', {'passed': True, 'snapshot': str(snapshot),
        'snapshot_sha256': sha(snapshot), 'files': rtl, 'hardware_status': 'NOT_RUN'})
    preserved = []
    for p in sorted(old.iterdir()):
        if not p.is_file():
            continue
        row = {'path': str(p), 'sha256': sha(p), 'bytes': p.stat().st_size}
        if p.suffix in {'.log', '.logw', '.area', '.timing', '.json', '.status', '.qor', '.f'}:
            target = evidence / p.name
            shutil.copy2(p, target)
            if sha(target) != row['sha256']:
                raise ValueError('Failure evidence byte mismatch')
            row['preserved_copy'] = str(target)
        preserved.append(row)
    new.mkdir()
    prepared = []
    for filename in [NAME + '.al', 'osd_compact_glyphs.vh',
                     'run_display_noise_synth.tcl', 'run_display_noise_place.tcl',
                     'run_display_noise_route.tcl']:
        original, target = (old / filename).read_bytes(), new / filename
        if filename.endswith('.al'):
            target.write_bytes(original.replace(old.name.encode(), new.name.encode()))
            if target.read_bytes().replace(new.name.encode(), old.name.encode()) != original:
                raise ValueError('AL changed beyond run path')
        else:
            shutil.copy2(old / filename, target)
            if target.read_bytes() != original:
                raise ValueError('Tcl or glyph include changed')
        prepared.append({'path': str(target), 'sha256': sha(target)})
    log = read(old / 'place.log')
    area = read(old / (NAME + '_gate.area'))
    report = {
        'generated_utc': datetime.now(timezone.utc).isoformat(),
        'failed_attempt': attempt, 'status': 'FAILED_PLACEMENT_NO_ROUTE_NO_BITGEN',
        'failure_messages': [line for line in log.splitlines() if 'PHY-7027' in line or 'PHY-9002' in line],
        'preliminary_gate_counts': {k: int(v) for k, v in re.findall(r'^#(slice\*?|eram|dsp|lut|reg)\s+(\d+)', area, re.M)},
        'preliminary_caveat': 'Gate Slice* and intermediate physical model counts are not final placed resources. Exact SLICEL field excess is not printed. No resource/timing threshold changed.',
        'placement_model_reports': [dict(zip(['luts', 'seqs', 'mslices', 'lslices', 'pads', 'brams', 'dsps'], map(int, row)))
            for row in re.findall(r'(\d+) luts, (\d+) seqs, (\d+) mslices, (\d+) lslices, (\d+) pads, (\d+) brams, (\d+) dsps', log)],
        'original_rtl_backups': rtl, 'failed_run_inputs': preserved,
        'next_run': str(new), 'next_run_status': 'PREPARED_UNFROZEN_NOT_RUN',
        'next_run_files': prepared, 'constraints_changed': False,
        'product_rtl_modified_by_this_tool': False, 'hardware_status': 'NOT_RUN',
    }
    put(ROOT / f'reports/attempt{attempt}_failure_and_v{following}_preparation.json', report)
    print(json.dumps({'passed': True, 'rtl_backup_matches_snapshot': True,
        'preserved_failed_run_files': len(preserved), 'next_run': str(new),
        'next_run_status': report['next_run_status']}, indent=2))


if __name__ == '__main__':
    main()
