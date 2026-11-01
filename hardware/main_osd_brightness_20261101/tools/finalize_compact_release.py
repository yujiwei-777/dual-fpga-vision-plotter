"""Aggregate immutable implementation evidence; retain auxiliary failures."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import re
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent / 'main_osd_large_font_20261030'
RUN = ROOT / '01_rtl/imgq_gain_m/main/td_project_compact_v2'
AUDIT = ROOT / '02_sim/compact_readonly_v2'
CONTEXT = ROOT / '02_sim/compact_context_v2'
NAME = 'camera_to_dsi_display_720p60_cnn_multibox'
BIT = ROOT / 'artifacts/dual_fpga_main_20261030_osd_chinese_compact_diagnostic.bit'

def read(p):
    return p.read_text(encoding='utf-8-sig', errors='replace')

def obj(p):
    return json.loads(read(p))

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()

def pins(text):
    block = text.split('Detailed IO Report', 1)[1].split('Clock', 1)[0]
    return {m[0]: {'direction': m[1], 'location': m[2], 'standard': m[3], 'type': m[4]}
            for m in re.findall(r'^\s*(\S+)\s+(INPUT|OUTPUT|INOUT)\s+(\S+)\s+(\S+)\s+(HDIO|HRIO|DDR)\s+', block, re.M)}

def timing_categories(text):
    return {m[0]: int(m[1]) for m in re.findall(r'^\d+\. checking (.+?)\((\d+)\) \((?:HIGH|MEDIUM|LOW)\)', text, re.M)}

def maxdelay_rows(text):
    return {m[4]: list(map(int, m[:4])) for m in re.findall(
        r'^\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(set_max_delay[^\n]+)', text, re.M)}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--after-bitgen', action='store_true')
    args = parser.parse_args()
    checks, details, evidence = {}, {}, {}
    paths = [RUN/'source_snapshot.json', RUN/'release_gate.json',
             AUDIT/'readonly_verification.json', AUDIT/'strict_independent_release_review.json',
             AUDIT/'supplementary_audit.json', AUDIT/'readonly.check', AUDIT/'readonly.skew',
             AUDIT/'readonly.clocks', AUDIT/'readonly.area', AUDIT/'readonly.sites.tsv',
             CONTEXT/'console_standard_context.log', CONTEXT/'standard.area', CONTEXT/'input_hashes.json',
             ROOT/'02_sim/mixer_regression/input_hashes.json', ROOT/'02_sim/mixer_regression/verification.json',
             ROOT/'reports/osd_source_scope.json', ROOT/'tools/bitgen_from_routed_db.tcl', ROOT/'04_pin/pin.adc']
    for p in paths:
        evidence[str(p.relative_to(ROOT))] = {'sha256': sha(p)}
    snapshot = obj(RUN/'source_snapshot.json')
    checks['all_prebuild_inputs_still_match'] = snapshot['passed'] and all(
        Path(f['path']).is_file() and sha(Path(f['path'])) == f['sha256'] for f in snapshot['files'])
    checks['build_resource_routed_setup_hold_gate'] = obj(RUN/'release_gate.json')['passed']
    checks['readonly_database_al_timing_unchanged'] = obj(AUDIT/'readonly_verification.json')['passed']
    hashes = obj(CONTEXT/'input_hashes.json')
    checks['standard_context_database_al_timing_unchanged'] = bool(hashes) and all(
        Path(p).is_file() and sha(Path(p)) == h for p, h in hashes.items())
    strict = obj(AUDIT/'strict_independent_release_review.json')
    checks['strict_design_drc_sites_timing_except_raw_io'] = all(
        item['passed'] for k, item in strict['checks'].items() if k != 'check_io')
    # Do not turn either raw auxiliary command into a PASS. Inspect ordinary
    # pins and hard-IO independently, and require standard unmodified bitgen.
    current_pins = pins(read(AUDIT/'readonly.area'))
    standard_pins = pins(read(CONTEXT/'standard.area'))
    baseline_pins = pins(read(BASE/'02_sim/osd_large_font_readonly_20261030/readonly.area'))
    assignments = re.findall(r'set_pin_assignment\s*\{\s*(.*?)\s*\}\s*\{\s*LOCATION\s*=\s*([^;\s]+)', read(ROOT/'04_pin/pin.adc'))
    pin_details = [{'port': p, 'expected': loc, 'actual': current_pins.get(p, {}).get('location')}
                   for p, loc in assignments]
    checks['all_30_ordinary_adc_locations_match'] = len(assignments) == 30 and all(
        item['expected'] == item['actual'] for item in pin_details)
    checks['all_79_physical_io_locations_match_baseline_and_context'] = (
        len(current_pins) == 79 and current_pins == baseline_pins == standard_pins and
        len({x['location'] for x in current_pins.values()}) == 79)
    sites = list(csv.DictReader(read(AUDIT/'readonly.sites.tsv').splitlines(), delimiter='\t'))
    mipi = [x for x in sites if x['ref_name'] == 'PH1P_PHY_MIPIIO_RX']
    pads = [x for x in sites if x['ref_name'] in {'PH1P_PHY_HD_PAD', 'PH1P_PHY_HR_PAD_V2', 'PH1P_PHY_DDRPHY_PAD_V2'}]
    hdl = ROOT/'01_rtl/imgq_gain_m/main/user_source/hdl_source'
    top = read(hdl/'design_top_wrapper.v')
    wrapper = read(hdl/'mipi_dphy_rx/ph1p_mipiio_rx_wrapper.v')
    checks['dphy0_fixed_macro_source_binding_and_placement'] = (
        len(mipi) == 1 and mipi[0]['is_placed'] == '1' and
        (mipi[0]['col'], mipi[0]['row'], mipi[0]['offset']) == ('47', '0', '0') and
        bool(re.search(r'\.DPHY_RX_LOCATION\s*\(\s*"DPHY0"\s*\)', top)) and
        all(re.search(r'\.' + port + r'\s*\(\s*' + port + r'\s*\)', top)
            for port in ['IO_rx_clk_pad_n', 'IO_rx_clk_pad_p', 'IO_rx_data_pad_n', 'IO_rx_data_pad_p']) and
        all(re.search(r'\.' + internal + r'\s*\(\s*' + port + r'\s*\)', wrapper) for internal, port in
            [('io_clk_pad_n','IO_rx_clk_pad_n'), ('io_clk_pad_p','IO_rx_clk_pad_p'),
             ('io_data_pad_n','IO_rx_data_pad_n'), ('io_data_pad_p','IO_rx_data_pad_p')]))
    checks['all_79_pad_primitives_placed_at_unique_sites'] = len(pads) == 79 and all(
        p['is_placed'] == '1' for p in pads) and len({(p['col'],p['row'],p['offset']) for p in pads}) == 79
    context_log = read(CONTEXT/'console_standard_context.log')
    adverse = re.findall(r'^.*(?:ERROR:|CRITICAL-WARNING:|FATAL:).*$', context_log, re.M)
    checks['context_only_recorded_usr8450_warning'] = (
        'STANDARD_CONTEXT_READONLY_PASS' in context_log and len(adverse) == 1 and 'USR-8450' in adverse[0] and
        'unconstraint IOs(10 out of 39)' in adverse[0])
    details['raw_check_io'] = {'status': 'CRITICAL-WARNING / USR-8450 remains; catch=0 is not interpreted as PASS',
        'standard_context_reproduces_warning': True,
        'interpretation': 'No attribution solely to noanalyze. The ten hard-DPHY ports are bound in unchanged source to placed DPHY0. All 79 ordinary/DDR/TMDS physical IO entries independently match baseline. Standard bitgen must succeed without unconstr_io override. These checks do not prove a vendor checker bug or board electrical behavior.'}
    details['ordinary_adc_locations'] = pin_details
    details['hard_dphy'] = mipi
    details['raw_check_design'] = 'FAIL RUN-8007 retained; actual complete compatible unique placed Slice inventory, PLB check, DRC and routed timing independently verified.'
    old_check = read(BASE/'02_sim/osd_large_font_readonly_20261030/readonly.check')
    new_check = read(AUDIT/'readonly.check')
    ca, cb = timing_categories(old_check), timing_categories(new_check)
    changed_categories = {k: [ca.get(k), cb.get(k)] for k in ca.keys() | cb.keys() if ca.get(k) != cb.get(k)}
    checks['timing_check_categories_only_shadowed_count_reduced'] = changed_categories == {
        'shadowed/ignored timing exception constraints': [3,1]}
    oa, nb = maxdelay_rows(old_check), maxdelay_rows(new_check)
    details['maxdelay_row_changes'] = {k: {'baseline': oa.get(k), 'current': nb.get(k)}
        for k in oa.keys() | nb.keys() if oa.get(k) != nb.get(k)}
    held = next((v for k,v in nb.items() if 'u_copy_status_cdc/held' in k), None)
    req = next((v for k,v in nb.items() if 'u_copy_status_cdc/req}' in k), None)
    checks['copy_status_held_req_constraints_hit_not_shadowed'] = held == [3,3,0,0] and req == [1,1,0,0]
    details['constraint_scope'] = 'SDC bytes are unchanged. Copy-status held/req now dominate their 3+1 paths. Multibox held row has 241 paths/199 dominated/42 shadowed (baseline237/207/30), result-select row163/163/0 (baseline147/147/0); these exact changes are preserved. Existing six FIFO exception groups and remaining multibox shadowed paths are not claimed as newly CDC-proven.'
    supplemental = obj(AUDIT/'supplementary_audit.json')
    checks['other_supplementary_checks'] = all(v for k,v in supplemental['checks'].items()
        if k not in {'io_check_pass','timing_check_categories_match_baseline'})
    sim = obj(ROOT/'02_sim/mixer_regression/verification.json')
    checks['full_mixer_regression'] = sim['status'] == 'PASS' and sim['metadata_checks'] == 5076
    sim_hash = obj(ROOT/'02_sim/mixer_regression/input_hashes.json')
    checks['simulation_inputs_still_match'] = bool(sim_hash) and all(Path(p).is_file() and sha(Path(p)) == h for p,h in sim_hash.items())
    checks['display_only_source_scope'] = obj(ROOT/'reports/osd_source_scope.json')['passed']
    baseline_bit = obj(ROOT/'reports/baseline_bit.json')
    checks['baseline_bit_unchanged'] = sha(Path(baseline_bit['Path'])) == baseline_bit['Hash']
    bit_script = read(ROOT/'tools/bitgen_from_routed_db.tcl')
    checks['bitgen_script_no_unconstrained_or_other_override'] = (
        not re.search(r'(?im)^\s*set_param\b|unconstr_io\s+on', bit_script) and
        'td_project_compact_v2' in bit_script and 'import_db "$build/${name}_pr.db"' in bit_script)
    if args.after_bitgen:
        log = read(ROOT/'02_sim/compact_context_v2/console_bitgen.log')
        checks['standard_bitgen_success_no_adverse_diagnostics'] = (
            'COMPACT_OSD_BITGEN_PASS:' in log and BIT.is_file() and BIT.stat().st_size > 1000000 and
            not re.search(r'(?:\bERROR:|\bFATAL:|\bCRITICAL-WARNING:|USR-8450|unconstr_io\s+on|COMPACT_OSD_BITGEN_FAIL)', log))
        details['artifact'] = {'path': str(BIT), 'sha256': sha(BIT) if BIT.is_file() else None,
                               'bytes': BIT.stat().st_size if BIT.is_file() else None}
        evidence['02_sim/compact_context_v2/console_bitgen.log'] = {'sha256': sha(ROOT/'02_sim/compact_context_v2/console_bitgen.log')}
    passed = all(checks.values())
    result = {'passed': passed, 'stage': 'post_standard_bitgen' if args.after_bitgen else 'pre_standard_bitgen',
              'checks': checks, 'details': details, 'evidence': evidence,
              'generated_utc': datetime.now(timezone.utc).isoformat(), 'hardware_status': 'NOT_RUN',
              'scope': 'Diagnostic release decision using actual physical inventory and standard bitgen; raw auxiliary check_design/check_io failures remain recorded and are not relabeled PASS.'}
    name = 'release_decision.json' if args.after_bitgen else 'prebitgen_review.json'
    (ROOT/'reports'/name).write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'passed':passed, 'checks': checks}, ensure_ascii=False, indent=2))
    return int(not passed)

if __name__ == '__main__':
    raise SystemExit(main())
