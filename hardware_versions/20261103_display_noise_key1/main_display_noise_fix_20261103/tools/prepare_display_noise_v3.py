"""Preserve failed attempt 2 and prepare an unfrozen third build run.

Does not edit product RTL, constraints, the failed run, or simulation evidence.
"""
from datetime import datetime, timezone
import argparse
import json
from pathlib import Path
import re
import shutil

from display_noise_paths import ROOT, BASE, NAME, obj, read, sha, put


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--resume-preparation', action='store_true')
    resume = parser.parse_args().resume_preparation
    old = ROOT / '01_rtl/imgq_gain_m/main/td_project_display_noise_v2'
    new = old.with_name('td_project_display_noise_v3')
    backup = ROOT / 'reports/attempt2_rtl'
    evidence = ROOT / 'reports/attempt2_evidence'
    if not resume and any(path.exists() for path in (new, backup, evidence)):
        raise ValueError('Refusing to overwrite attempt backups or prepared run')
    if resume and ((new / 'source_snapshot.json').exists() or (new / '.read_design.begin.f').exists()):
        raise ValueError('Cannot resume preparation of a frozen or started run')
    frozen = obj(old / 'source_snapshot.json')
    expected = {str(Path(item['path']).resolve()).casefold(): item['sha256']
                for item in frozen['files']}
    rels = [
        '01_rtl/imgq_gain_m/main/user_source/hdl_source/design_top_wrapper.v',
        '01_rtl/imgq_gain_m/main/user_source/hdl_source/a4_display_spatial_h1.v',
        '01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/display_tone_96.v',
    ]
    for rel in rels:
        path = ROOT / rel
        checked = backup / path.name if resume else path
        if sha(checked) != expected[str(path.resolve()).casefold()]:
            raise ValueError('Current product no longer matches v2 snapshot: ' + rel)
    if not (old / '.opt_place.error.f').exists() or (old / '.opt_place.end.f').exists():
        raise ValueError('Expected an unsuccessful attempt 2 placement')
    backup.mkdir(parents=True, exist_ok=resume)
    evidence.mkdir(parents=True, exist_ok=resume)
    rtl_rows = []
    for rel in rels:
        source = ROOT / rel
        target = backup / source.name
        if not resume:
            shutil.copy2(source, target)
        if sha(target) != expected[str(source.resolve()).casefold()]:
            raise ValueError('Backup byte mismatch')
        rtl_rows.append({'source': str(source), 'backup': str(target),
                         'sha256': sha(target), 'v2_snapshot_sha256': expected[str(source.resolve()).casefold()]})
    preserved = []
    for source in sorted(old.iterdir()):
        if not source.is_file():
            continue
        item = {'path': str(source), 'sha256': sha(source), 'bytes': source.stat().st_size}
        if source.suffix in {'.log', '.logw', '.area', '.timing', '.json', '.status', '.qor', '.f'}:
            target = evidence / source.name
            shutil.copy2(source, target)
            if sha(target) != item['sha256']:
                raise ValueError('Failure evidence byte mismatch')
            item['preserved_copy'] = str(target)
        preserved.append(item)
    put(backup / 'manifest.json', {'passed': True, 'snapshot': str(old / 'source_snapshot.json'),
        'snapshot_sha256': sha(old / 'source_snapshot.json'), 'files': rtl_rows,
        'hardware_status': 'NOT_RUN'})
    new.mkdir(parents=True, exist_ok=resume)
    prepared = []
    for filename in [NAME + '.al', 'osd_compact_glyphs.vh',
                     'run_display_noise_synth.tcl', 'run_display_noise_place.tcl',
                     'run_display_noise_route.tcl']:
        source, target = old / filename, new / filename
        original = source.read_bytes()
        if filename.endswith('.al'):
            if target.exists() and target.read_bytes() != original.replace(old.name.encode(), new.name.encode()):
                shutil.copy2(target, evidence / 'rejected_initial_v3_al_newline_conversion.bin')
            target.write_bytes(original.replace(old.name.encode(), new.name.encode()))
            if target.read_bytes().replace(new.name.encode(), old.name.encode()) != original:
                raise ValueError('AL changed beyond run path')
        else:
            shutil.copy2(source, target)
            if target.read_bytes() != original:
                raise ValueError('Run Tcl/glyph changed')
        prepared.append({'path': str(target), 'sha256': sha(target)})
    baseline_run = BASE / '01_rtl/imgq_gain_m/main/td_project_pcb_auto_v2'
    baseline_area = read(baseline_run / (NAME + '_phy.area'))
    baseline_gate = read(baseline_run / (NAME + '_gate.area'))
    attempt_gate = read(old / (NAME + '_gate.area'))
    counts = lambda text: {k: int(v) for k, v in re.findall(r'^#(slice\*?|eram|dsp)\s+(\d+)', text, re.M)}
    initial = lambda text: [dict(zip(['luts', 'seqs', 'mslices', 'lslices', 'pads', 'brams', 'dsps'], map(int, row)))
        for row in re.findall(r'(\d+) luts, (\d+) seqs, (\d+) mslices, (\d+) lslices, (\d+) pads, (\d+) brams, (\d+) dsps', text)]
    baseline_log = read(baseline_run / 'place.log')
    failure_log = read(old / 'place.log')
    baseline_capacity = obj(BASE / '02_sim/pcb_compat_readonly/physical_capacity/physical_capacity_validation.json')
    report = {
        'generated_utc': datetime.now(timezone.utc).isoformat(),
        'attempt2_status': 'FAILED_PLACEMENT_NO_ROUTE_NO_BITGEN',
        'failure_messages': [line for line in failure_log.splitlines() if 'PHY-7027' in line or 'PHY-9002' in line],
        'exact_field_excess': None,
        'field_limit_caveat': 'TD prints LUTL utilization rounded to 1.00 and SLICEL field overflow, but does not print an exact excess. Listed preliminary models are not final placed Slice counts. Baseline also emitted PHY-7027 in later successful placement phases; current PHY-9002 and error marker are the hard failure.',
        'attempt2_preliminary_gate_resources': counts(attempt_gate),
        'baseline_preliminary_gate_resources': counts(baseline_gate),
        'baseline_final_placed_resources': counts(baseline_area),
        'attempt2_placement_model_reports': initial(failure_log),
        'baseline_placement_model_reports': initial(baseline_log),
        'baseline_successful_physical_capacity': {k: baseline_capacity[k] for k in ['capacities', 'used', 'free', 'expected_model_counts']},
        'baseline_slice_count': 19715, 'strict_95pct_maximum_slice_count': 20155,
        'baseline_slice_addition_budget_to_strict_95pct': 440,
        'attempt2_inputs': preserved,
        'original_rtl_backups': rtl_rows,
        'v3_run': str(new), 'v3_status': 'PREPARED_UNFROZEN_NOT_RUN',
        'v3_files': prepared, 'constraints_changed': False,
        'product_rtl_modified_by_this_tool': False, 'hardware_status': 'NOT_RUN',
    }
    put(ROOT / 'reports/attempt2_failure_and_v3_preparation.json', report)
    print(json.dumps({'rtl_backup_matches_v2_snapshot': True, 'v3_run': str(new),
                      'v3_status': report['v3_status'], 'preserved_attempt2_files': len(preserved),
                      'baseline_strict_slice_headroom': 440}, indent=2))


if __name__ == '__main__':
    main()
