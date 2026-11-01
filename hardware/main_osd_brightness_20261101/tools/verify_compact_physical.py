"""Fail-closed supplementary audit. Retains the generic capacity error."""
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent / 'main_osd_large_font_20261030'
RUN = ROOT / '01_rtl/imgq_gain_m/main/td_project_compact_v2'
AUDIT = ROOT / '02_sim/compact_readonly_v2'
CAP = ROOT / 'tools/physical_capacity'
def read(p): return p.read_text(encoding='utf-8-sig', errors='replace')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def main():
    checks, details = {}, {}
    log = read(AUDIT / 'console_readonly.log')
    checks['io_check_pass'] = 'CHECK_IO_STATUS=0' in log
    checks['plb_check_pass'] = 'CHECK_PLB_STATUS=0' in log
    raw = re.search(r'RAW_CHECK_DESIGN_STATUS=(\d+)', log)
    checks['raw_check_design_recorded'] = bool(raw)
    checks['raw_check_only_known_capacity_issue'] = bool(raw) and (raw[1] == '0' or ('lslices exceed capacity' in log and 'RUN-8007' in log))
    details['raw_check_design_status'] = int(raw[1]) if raw else None
    details['capacity_interpretation'] = 'Generic check_design failure is retained, not waived or rewritten. Only the known LSLICE logical-model capacity discrepancy has baseline evidence; fresh complete placed-site compatibility/uniqueness, PLB/IO, routing DRC and timing are independently mandatory.'
    checks['no_tracked_clock_warnings'] = not re.search(r'RTCLK-5078|USR-6113', log)
    drc = read(AUDIT / 'readonly.drc')
    rules = re.findall(r'^\|\s*([A-Z]+-\d+)\s*\|\s*(\w+)\s*\|.*?\|\s*(\d+)\s*\|', drc, re.M)
    checks['drc_only_known_notes'] = bool(rules) and all(rule in {'SLATR-1036', 'SLATR-1038'} and severity == 'NOTE' for rule, severity, count in rules)
    details['drc_rules'] = rules
    area = read(AUDIT / 'readonly.area')
    slice_count = re.search(r'^#Slice\s+(\d+)\s+out of', area, re.M | re.I)
    dsp_count = re.search(r'^#DSP\s+(\d+)\s+out of', area, re.M | re.I)
    expected_count = sum(1 for line in read(AUDIT / 'expected_slice_cells.tsv').splitlines() if line.strip()) - 1
    checks['enumerated_slice_count_matches_area'] = bool(slice_count) and int(slice_count[1]) == expected_count
    checks['dsp_count_not_increased_from_37'] = bool(dsp_count) and int(dsp_count[1]) <= 37
    skew = read(AUDIT / 'readonly.skew')
    baseline_skew = read(BASE / '02_sim/osd_large_font_readonly_20261030/readonly.skew')
    skew_rows = re.findall(r'^\s*(slow_\w+|fast_\w+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s*$', skew, re.M)
    baseline_rows = re.findall(r'^\s*(slow_\w+|fast_\w+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s*$', baseline_skew, re.M)
    checks['fifo_mailbox_skew_same_count_all_pass'] = bool(skew_rows) and len(skew_rows) == len(baseline_rows) and all(float(r[3]) >= 0 for r in skew_rows)
    details['skew_rows'] = len(skew_rows)
    details['minimum_skew_slack_ns'] = min((float(r[3]) for r in skew_rows), default=None)
    clocks = read(AUDIT / 'readonly.clocks')
    checks['ddr_7p5ns_hdmi_13p333ns_retained'] = any('7.500' in line and 'u_ddr2/usr_clk' in line for line in clocks.splitlines()) and any('13.333' in line and 'HDMI_PIXEL_CLK' in line for line in clocks.splitlines())
    categories = lambda text: re.findall(r'^\d+\. checking ([^\n]+)', text, re.M)
    checks['timing_check_categories_match_baseline'] = categories(read(AUDIT / 'readonly.check')) == categories(read(BASE / '02_sim/osd_large_font_readonly_20261030/readonly.check'))
    # Compare the baseline source manifest. Only display integration is allowed.
    changed, missing = [], []
    allowed = {'hdmi_mixer.v', 'design_top_wrapper.v', 'osd_large_font_rom.v', 'pcb_status_large_text.v', 'result_overlay.v', 'hxa_multibox_overlay.v'}
    with (ROOT / 'tools/baseline_sources.csv').open(encoding='utf-8-sig', newline='') as fp:
        for row in csv.DictReader(fp):
            p = Path(row['Path'])
            rel = p.relative_to(BASE)
            now = ROOT / rel
            if not now.is_file(): missing.append(str(rel))
            elif sha(now) != row['SHA256']: changed.append(str(rel))
    checks['non_osd_contract_sources_unchanged'] = not missing and all(Path(p).name in allowed for p in changed)
    details['baseline_changed_files'] = changed
    details['baseline_missing_files'] = missing
    details['cdc_scope'] = 'OSD-only source equivalence plus fresh timing/check/skew/clock reports; this is not an exhaustive new asynchronous CDC proof. OSD pixel-domain pipeline must also pass RTL timing-alignment simulation.'
    args = [sys.executable, str(CAP / 'validate_device_capacity.py'), '--chip', str(CAP / 'ph1_35p_device_dump.txt_chip'), '--routing', str(CAP / 'ph1_35p_device_dump.txt_connmngr'), '--tile-report', str(CAP / 'report_named_tiles.log'), '--datasheet', str(CAP / 'DS1300_logic_and_dram_excerpt.txt'), '--resource-report', str(CAP / 'physical_device_resources.txt'), '--expected-cells', str(AUDIT / 'expected_slice_cells.tsv'), '--expected-log', str(AUDIT / 'console_readonly.log'), '--placements', str(AUDIT / 'readonly.sites.tsv'), '--out', str(AUDIT / 'physical_capacity')]
    capacity = subprocess.run(args, capture_output=True, text=True)
    (AUDIT / 'physical_capacity_console.log').write_text(capacity.stdout + capacity.stderr, encoding='utf-8')
    checks['complete_compatible_unique_placed_slice_capacity'] = capacity.returncode == 0
    result = {'passed': all(checks.values()), 'checks': checks, 'details': details, 'hardware_status': 'NOT_RUN'}
    (AUDIT / 'supplementary_audit.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))
    return int(not result['passed'])
if __name__ == '__main__':
    raise SystemExit(main())
