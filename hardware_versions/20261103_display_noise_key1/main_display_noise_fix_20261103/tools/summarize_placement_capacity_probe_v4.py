"""Record bounded read-only architecture probe findings, including query errors."""
import json
from pathlib import Path
import re

from display_noise_paths import ROOT, BASE, read, sha, put


def main():
    probe = ROOT / '02_sim/placement_capacity_probe_v4'
    manifest = json.loads(read(probe / 'input_manifest.json'))
    unchanged = all(sha(row['source']) == row['source_sha256'] and
                    sha(row['target']) == row['target_sha256'] for row in manifest['copies'])
    if not unchanged or sha(probe / 'run.tcl') != manifest['script_sha256']:
        raise ValueError('Probe changed an original or independent copied input')
    log = read(probe / 'console.log')
    outcomes = [{'query': name, 'catch': int(code)} for name, code in
                re.findall(r'^PROBE_QUERY_CATCH (\S+) (\d+) RESULT=', log, re.M)]
    counts = {}
    for kind, expected in [('Plb', 1638), ('Pmb', 1014)]:
        text = read(probe / ('arch_' + kind + '.txt'))
        cells = re.findall(r'<s[01]x\d+y\d+, x(\d+)y(\d+)>', text)
        if len(cells) != expected or len(set(cells)) != expected:
            raise ValueError('Incomplete/duplicate architecture location census')
        counts[kind] = {'tiles': expected, 'slots_per_tile': 8, 'slots': 8 * expected}
    area = read(probe / 'imported_gate_verbose.area')
    old = Path(manifest['source_run']) / 'camera_to_dsi_display_720p60_cnn_multibox_gate.area'
    parse_area = lambda text: {key: int(value) for key, value in
                              re.findall(r'^#(slice\*?|lut|reg|mslice|lslice|eram|dsp)\s+(\d+)', text, re.M)}
    baseline = BASE / '02_sim/pcb_compat_readonly/physical_capacity/physical_capacity_validation.json'
    baseline_capacity = json.loads(read(baseline))
    files = [p for p in probe.iterdir() if p.is_file()]
    result = {
        'status': 'READONLY_QUERY_COMPLETED_WITH_UNSUPPORTED_QUERY_ERRORS_RETAINED',
        'all_original_and_copied_inputs_unchanged': unchanged,
        'no_place_route_bitgen_or_parameter_override': True,
        'queries': outcomes,
        'unsupported_queries': [q['query'] for q in outcomes if q['catch']],
        'exact_adverse_diagnostics': [line for line in log.splitlines()
                                      if re.search(r'ERROR:|CRITICAL-WARNING:|FATAL:', line)],
        'architecture_location_census': counts,
        'eight_slot_proof': str(ROOT / 'tools/physical_capacity/report_named_tiles.log'),
        'actual_gate_parameters': {'map_mode': 'auto', 'pack_effort': 'medium'},
        'original_gate_report_estimates': parse_area(read(old)),
        'same_gate_db_reimport_report_estimates': parse_area(area),
        'estimate_limitation': 'The same gate DB produces a different recomputed Slice*/LUT estimate on reimport. Neither estimate certifies actual final physical occupancy or the exact internal GP field excess.',
        'baseline_final_physical_capacity': {
            key: baseline_capacity[key] for key in
            ('expected_slices', 'placed_model_by_physical_tile', 'capacities', 'used', 'free')},
        'packing_conclusion': 'Successful baseline proves LSLICE in both Plb and Pmb. Pmb being memory-capable does not mean its free slots are a separate freely switchable SLICEL field budget. GP prints rounded LUTL utilization 1.00 and does not expose exact excess through the supported architecture queries used here.',
        'documented_next_strategy': 'Fresh synthesis with gate pack_effort high is public ALL-family behavior. It must run pack/optimize_gate and cannot be substituted by placing the unchanged V4 gate DB.',
        'evidence': [{'path': str(p), 'sha256': sha(p), 'bytes': p.stat().st_size}
                     for p in sorted(files)],
        'hardware_status': 'NOT_RUN',
    }
    put(ROOT / 'reports/placement_capacity_probe_v4.json', result)
    print(json.dumps({k: result[k] for k in
                      ('status', 'all_original_and_copied_inputs_unchanged',
                       'unsupported_queries', 'architecture_location_census',
                       'original_gate_report_estimates', 'same_gate_db_reimport_report_estimates')}, indent=2))


if __name__ == '__main__':
    main()
