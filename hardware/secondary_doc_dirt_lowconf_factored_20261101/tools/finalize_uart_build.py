"""Verify and record the completed isolated UART candidate; never touch backups."""
import hashlib
import json
import re
import shutil
from datetime import datetime, timezone
from pathlib import Path

from check_route_release import check

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / 'td_project/secondary_edge_bypass_Runs/phy_5'
SYN = ROOT / 'td_project/secondary_edge_bypass_Runs/syn_4'
OUT = ROOT / 'artifacts'
BIT = 'dual_fpga_secondary_20261001_uart_idle_query_timing_fixed.bit'


def digest(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def require(condition, reason):
    if not condition:
        raise SystemExit(reason)


def main():
    require(check(RUN), 'Final route gates failed')
    inputs = json.loads((OUT / 'INPUTS.json').read_text(encoding='utf-8'))
    for item in inputs['files']:
        require(digest(ROOT / item['path']) == item['sha256'], 'Input changed: ' + item['path'])
    validation = json.loads((ROOT / 'reports/uart_validation.json').read_text(encoding='utf-8'))
    require(validation['pass_count'] == validation['test_count'] == 22, 'RTL regression incomplete')
    for source in validation['source_hashes']:
        require(digest(ROOT / source['path']) == source['sha256'], 'RTL verification source changed')
    for test in validation['tests']:
        require(test['passed'] and not test['errors'], 'RTL verification failed')
        require(digest(ROOT / test['log']) == test['sha256'], 'RTL verification log changed')
    console = (RUN / 'bitgen_console.log').read_text(errors='replace')
    require('CHECKED_BITGEN_PASS' in console, 'No successful guarded bitgen')
    require(not re.search(r'CHECKED_BITGEN_FAILED|MAPPING_ERROR|[A-Z]+-\d+ ERROR', console), 'Bitgen error')
    timing = (RUN / 'bitgen_check.ts').read_text()
    for key in ('SWNS', 'STNS', 'HWNS', 'HTNS'):
        match = re.search(rf'{key}:\s*(-?[\d.]+)ns', timing)
        require(match is not None, 'Missing bitgen timing metric')
        value = float(match[1])
        require(value >= 0 and (not key.endswith('TNS') or value == 0), 'Bitgen timing failure')
    for log in SYN.glob('*.log'):
        require(not re.search(r'[A-Z]+-\d+ ERROR|BUILD_FAILED', log.read_text(errors='replace')), 'Synthesis error')
    source_bit = RUN / BIT
    require(source_bit.is_file() and source_bit.stat().st_size > 0, 'Missing or empty bit')
    destination = OUT / BIT
    if destination.exists():
        require(digest(destination) == digest(source_bit), 'Refusing to overwrite a different artifact')
    else:
        shutil.copy2(source_bit, destination)
    gate = json.loads((RUN / 'release_gate.json').read_text())
    build = {
        'generated_utc': datetime.now(timezone.utc).isoformat(),
        'status': 'build_and_rtl_passed_hardware_pending',
        'candidate_root': str(ROOT),
        'tool': 'Tang Dynasty Release_2026.1_SP2',
        'device': 'PH1P35MDG324', 'speed': 3, 'top': 'secondary_top',
        'synthesis': 'syn_4', 'implementation': 'phy_5',
        'actual_rtl': '01_rtl; td_project/import is not used',
        'bit': {'path': destination.relative_to(ROOT).as_posix(), 'bytes': destination.stat().st_size, 'sha256': digest(destination)},
        'timing_ns': gate['timing_ns'], 'resources': gate['resources'],
        'rtl_tests_passed': 22, 'rtl_tests_total': 22,
        'timing_mode': 'final', 'corner': 'Both (Slow and Fast)', 'sta_coverage_percent': 99.44,
        'input_hashes_verified': len(inputs['files']),
        'model_hash_note': 'Manifest additionally records td_project/model/pcb_tinycnn_*.mem (5); simulation and RTL parameters resolve to these files. Synthesis logs do not separately list resolved readmem filenames.',
        'rgmii_rx_ns': {'max_both_edges': 2.5, 'min_both_edges': 1.5},
        'rgmii_tx_ns': {'max_both_edges': 1.2, 'min_both_edges': -1.2},
        'cdc_budget_ns': {'held_request': 7, 'held_return_control_gray_first_stage': 7.5},
        'uart': {'baud': 115200, 'format': '8N1', 'startup_probe_ms': 200, 'normal_job_queries': 0,
                 'final_queries_initial': 1, 'final_retry_ms': 500, 'final_max_retries': 3,
                 'requires_fresh_idle': True, 'external_link_ready_required': False},
        'wiring': {'C18_J1_1': 'ATK RX', 'D15_J1_2': 'ATK TX', 'J1_30': 'GND', 'E12_J1_3': 'leave unconnected'},
        'old_bits_preserved': [
            {'path': 'work/secondary/secondary/05_boot/bit_archive/secondary_stage2_offline_20260924/dual_fpga_secondary_20260923_a10_pcb_cnn_diagnostic.bit', 'sha256': '2c5c698f0ade8027246ca222ec53d9e25b6976fbc223e99621b89fc9fd80c91c'},
            {'path': 'work/secondary_uart_only_20261001/artifacts/dual_fpga_secondary_20261001_atk_esp8266_uart_only.bit', 'sha256': 'e31932d4de1eafdec31bbe22d523a31ed61337470a4934735437af13161b4dc2'},
        ],
        'hardware_validation': False,
        'limits': ['Setup WNS is 0.000 ns with small margin.', 'No physical ATK/Wi-Fi/GRBL validation.', 'No full vendor DDR post-layout functional simulation.', 'STA coverage and remaining warnings are scoped in reports/reset_cdc_review.md.'],
        'reports': ['reports/uart_validation.md', 'reports/reset_cdc_review.md', 'reports/tinycnn_timing_review_20261001.md',
                    'td_project/secondary_edge_bypass_Runs/phy_5/release_gate.json',
                    'td_project/secondary_edge_bypass_Runs/phy_5/bitgen_check.ts'],
    }
    write_json(OUT / 'BUILD.json', build)
    files = {ROOT / item['path'] for item in inputs['files']}
    files.update(ROOT / test['log'] for test in validation['tests'])
    files.update((ROOT / 'td_project/model').glob('pcb_tinycnn_*.mem'))
    for directory in (SYN, RUN):
        files.update(p for p in directory.iterdir() if p.is_file())
    for directory in (ROOT / 'reports', ROOT / 'tools'):
        files.update(p for p in directory.iterdir() if p.is_file())
    files.update(p for p in (ROOT / '02_sim').rglob('*') if p.is_file() and p.suffix.lower() in {'.v', '.sv', '.ps1', '.py', '.do', '.tcl'})
    files.update([ROOT / 'README.md', OUT / 'BUILD.json', OUT / 'INPUTS.json', destination])
    entries = [{'path': p.relative_to(ROOT).as_posix(), 'bytes': p.stat().st_size, 'sha256': digest(p)}
               for p in sorted(files, key=lambda p: p.as_posix())]
    write_json(OUT / 'MANIFEST.json', {'generated_utc': datetime.now(timezone.utc).isoformat(),
               'algorithm': 'SHA256', 'root': str(ROOT), 'excludes': ['MANIFEST.json', 'SHA256SUMS.txt'], 'files': entries})
    sums = [f"{entry['sha256']}  {entry['path']}" for entry in entries]
    sums.append(f"{digest(OUT / 'MANIFEST.json')}  artifacts/MANIFEST.json")
    (OUT / 'SHA256SUMS.txt').write_text('\n'.join(sums) + '\n', encoding='utf-8')
    print(json.dumps({'bit': build['bit'], 'manifest_files': len(entries), 'status': build['status']}, indent=2))


if __name__ == '__main__':
    main()
