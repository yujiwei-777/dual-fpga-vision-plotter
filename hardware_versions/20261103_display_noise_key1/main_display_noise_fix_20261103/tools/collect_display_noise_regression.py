"""Collect real, hash-bound simulation results; never copy old PASS flags."""
import datetime
import json
import re
from pathlib import Path
import review_display_noise_release as review
from display_noise_paths import ROOT, RUN, put, sha, obj, read
from validate_display_equivalence_chain import validate as validate_equivalence_chain, validate_binding as validate_equivalence_binding


def main():
    errors = []
    logs = {}
    for rel, marker in review.REQUIRED_REGRESSION_LOGS.items():
        p = ROOT / rel
        text = read(p) if p.is_file() else ''
        logs[rel] = review.clean_simulation_log(text, marker)
        if not logs[rel]:
            errors.append('Missing/failed real simulation: ' + rel)
    def passed(rel):
        return logs.get(rel, False)
    def contains(rel, fragment):
        return passed(rel) and fragment in read(ROOT / rel)
    legacy = '02_sim/link_legacy_regression_v2/'
    packet = '02_sim/link_pcb_wait_v2/'
    box = '02_sim/pcb_actual_box_v2/'
    tone = obj(ROOT / 'reports/display_tone_rtl_regression.json')
    tone_ref = obj(ROOT / 'reports/display_tone_reference.json')
    spatial = obj(ROOT / '02_sim/display_noise/verification.json')
    contract = obj(ROOT / 'reports/display_functional_contract.json')
    chain = validate_equivalence_chain()
    put(ROOT / 'reports/display_equivalence_chain.json', chain)
    errors.extend(chain['errors'])
    checks = {
        'ordinary_cnn_stability': passed(legacy + 'ordinary_stability.log'),
        **{'startup_fault_' + str(i): passed(legacy + 'startup_fault_' + str(i) + '.log') for i in range(3)},
        'document_type15': passed(legacy + 'document_type15.log'),
        'legacy_lint_compile': passed(legacy + 'link_legacy_compile.log'),
        'pcb_packet_30s_current_downcounter': contains(packet + 'transcript_batch_final.log', 'timer preserved from 25000 to 25000'),
        'pcb_packet_compile': passed(packet + 'compile.log'),
        'pcb_30000ms_deadline': contains(packet + 'transcript_batch_final.log', 'elapsed_ms=30000'),
        'cnn_2000ms_deadline': contains(packet + 'transcript_batch_final.log', 'elapsed_ms=2000'),
        'heartbeat_250ms': contains(packet + 'transcript_batch_final.log', 'max_gap_ms=250'),
        'session_frame_job_filter': contains(packet + 'transcript_batch_final.log', 'wrong session/frame/job'),
        'cached_ack_keeps_deadline': contains(packet + 'transcript_batch_final.log', 'timer preserved from 25000 to 25000'),
        'mode_cancel': contains(packet + 'transcript_batch_final.log', 'mode change cancels active PCB task'),
        'real_lease_loss': contains(packet + 'transcript_batch_final.log', 'real 3 second peer loss'),
        'pcb_actual_box_status_cdc_13_checks': passed(box + 'transcript.log'),
        'pcb_actual_box_compile': passed(box + 'compile.log'),
        'key4_oneshot_hold_bounce': passed(box + 'key4_oneshot.log'),
        'coordinate_mux_equivalence_400012': passed(box + 'coordinate_equivalence.log'),
        'key4_equivalence_compile': passed(box + 'extra_compile.log'),
        'display_tone_fixed_tap_exhaustive': tone_ref.get('status') == 'PASS' and tone_ref.get('input_values') == 256,
        'display_tone_fixed_tap_stall_timing': passed('reports/display_tone_rtl_regression.log') and tone.get('baseline_fixed_tap_cycle_equivalence') is True,
        'spatial_reference_match': spatial.get('status') == 'PASS' and all(c.get('result') == 'PASS' for c in spatial.get('cases', [])) and len(spatial.get('cases', [])) == 11,
        'spatial_full_range_no_truncation': passed('02_sim/display_noise/rgb8_range/transcript.log'),
        'spatial_edges_motion_no_smear': passed('02_sim/display_noise/strong_edges/transcript.log'),
        'spatial_frame_line_boundaries': all(passed('02_sim/display_noise/' + name + '/transcript.log') for name in review.SPATIAL_CASES),
        'video_two_cycle_alignment': passed('02_sim/display_noise/full_720p/transcript.log'),
        'top_cnn_unchanged_input': contract.get('passed') is True,
        'ae_policy_unchanged': contract.get('passed') is True,
        'exact_spatial_implementation_equivalence_chain': chain['passed'],
    }
    snapshot = obj(RUN / 'source_snapshot.json')
    snapshot_hashes = {str(Path(f['path']).resolve()).casefold(): f['sha256'] for f in snapshot['files']}
    fixed = all(snapshot_hashes.get(str((ROOT / rel).resolve()).casefold()) == sha(ROOT / rel) for rel in review.REQUIRED_CURRENT_RTL)
    checks['current_rtl_hashes_match_all_tested_inputs'] = fixed
    if set(checks) != set(review.REQUIRED_REGRESSION_CHECKS):
        errors.append('Collector check names differ from required checks')
    for name, success in checks.items():
        if success is not True:
            errors.append('Failed check: ' + name)
    paths = {ROOT / rel for rel in review.REQUIRED_CURRENT_RTL + review.REQUIRED_ALGORITHM_INPUTS}
    paths.update(ROOT / rel for rel in review.REQUIRED_REGRESSION_LOGS)
    paths.update(Path(path) for path in chain['evidence'])
    paths.update([ROOT / 'reports/display_functional_contract.json', Path(__file__)])
    for d in ['link_legacy_regression_v2', 'link_pcb_wait_v2', 'pcb_actual_box_v2', 'display_tone']:
        paths.update(p for p in (ROOT / '02_sim' / d).iterdir() if p.is_file() and p.suffix in {'.sv', '.v', '.vh', '.hex', '.py', '.ps1'})
    paths.add(ROOT / '02_sim/display_noise/verification.json')
    result = {
        'passed': not errors, 'generated_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'checks': checks, 'errors': errors,
        'input_hashes': {p.resolve().as_posix(): sha(p) for p in sorted(paths)},
        'logs': [(ROOT / rel).resolve().as_posix() for rel in sorted(review.REQUIRED_REGRESSION_LOGS)],
        'hardware_status': 'NOT_RUN',
        'limitations': 'Behavioral models and frozen-source equality; no FPGA-board, sensor-noise, CNN accuracy or physical GRBL test. Motion algorithm is unchanged, but display tone can change its DDR source at input channel values 96..99.'}
    validation = review.validate_regression(result, snapshot=snapshot)
    binding = validate_equivalence_binding(result, chain)
    if not binding['passed']:
        result['passed'] = False
        result['errors'].extend(binding['errors'])
    if not validation['passed']:
        result['passed'] = False
        result['errors'].extend(validation['errors'])
    put(ROOT / 'reports/display_noise_regression.json', result)
    print(json.dumps({'passed': result['passed'], 'checks': len(checks), 'logs': len(logs), 'errors': result['errors']}, indent=2))
    return int(not result['passed'])


if __name__ == '__main__':
    raise SystemExit(main())
