"""Independent read-only release audit; writes only new JSON/Markdown evidence.

Retains the raw check_design failure. A narrowly recognized logical LSLICE
counting discrepancy is acceptable only with complete physical-site evidence.
Command catch status alone never proves IO legality when its window warns.
"""
import argparse
from collections import Counter
import csv
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re

KNOWN_CAPACITY = ('RUN-8007 ERROR: Design failed the check. The resources used in your design exceed '
                  'the device limitations. Please try modifying the design or switch to a device '
                  'with a larger resource capacity.')
ISSUE = re.compile(r'\b(?:ERROR|FATAL|CRITICAL(?:-WARNING)?)\b|\b(?:FAIL(?:ED|URE)?|EXCEPTION|ABORT(?:ED)?)\b', re.I)


def read(path):
    raw=Path(path).read_bytes()
    return raw.decode('utf-16' if raw[:2] in (b'\xff\xfe',b'\xfe\xff') else 'utf-8-sig', errors='strict')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def command_window(log, command):
    lines = log.splitlines()
    starts = [i for i, line in enumerate(lines)
              if re.fullmatch(r'RUN-1002 : start command "' + re.escape(command) + r'"', line.strip())]
    if len(starts) != 1:
        return [], [f'Expected exactly one {command} invocation; found {len(starts)}']
    begin = starts[0]
    end = next((i for i in range(begin + 1, len(lines))
                if lines[i].startswith('RUN-1002 : start command ') or
                lines[i].startswith(f'RUN-1003 : finish command "{command}"')), len(lines))
    return lines[begin + 1:end], []


def check_design(log, site_checks):
    lines, errors = command_window(log, 'check_design')
    markers = [re.fullmatch(r'RAW_CHECK_DESIGN_STATUS=(\d+) REASON=(.*)', line.strip()) for line in lines]
    markers = [m for m in markers if m]
    if len(markers) != 1:
        errors.append('Missing/duplicate check_design catch marker in command window')
        return {'passed': False, 'errors': errors, 'window': lines}
    status, reason = int(markers[0][1]), markers[0][2]
    allowed = set()
    known = False
    if status == 0:
        if reason.strip():
            errors.append('Successful check_design has unexpected reason text')
    elif status == 1:
        nonempty = [line.strip() for line in lines if line.strip()]
        counts = [i for i, line in enumerate(nonempty) if line == 'RUN-1001 : lslices exceed capacity']
        failures = [i for i, line in enumerate(nonempty) if line == KNOWN_CAPACITY]
        if len(counts) != 1 or len(failures) != 1 or failures[0] != counts[0] + 1:
            errors.append('Failed check_design is not the exact adjacent known capacity diagnostic')
        elif not site_checks:
            errors.append('Known LSLICE discrepancy lacks complete compatible unique placed-site proof')
        else:
            known = True
            allowed.add(KNOWN_CAPACITY)
        if reason.strip():
            errors.append('Known capacity failure has unexpected catch reason')
    else:
        errors.append(f'Unexpected check_design catch status {status}')
    for line in lines:
        if line.strip().startswith('RAW_CHECK_DESIGN_STATUS='):
            continue
        if ISSUE.search(line) and line.strip() not in allowed:
            errors.append('Unexpected check_design diagnostic: ' + line.strip())
        if re.search(r'\bRUN-8007\b', line) and line.strip() != KNOWN_CAPACITY:
            errors.append('Unrecognized RUN-8007 text: ' + line.strip())
    return {'passed': not errors, 'errors': errors, 'raw_status': status,
            'known_logical_capacity_discrepancy': known, 'window': lines}


def check_simple_command(log, command, marker):
    lines, errors = command_window(log, command)
    markers = [re.fullmatch(re.escape(marker) + r'=(\d+) REASON=(.*)', line.strip()) for line in lines]
    markers = [m for m in markers if m]
    if len(markers) != 1 or markers[0][1] != '0' or markers[0][2].strip():
        errors.append(f'{command} missing exact successful catch marker')
    for line in lines:
        if ISSUE.search(line):
            errors.append(f'{command} adverse diagnostic: ' + line.strip())
    return {'passed': not errors, 'errors': errors, 'window': lines}


def check_drc(text):
    errors = []
    totals = re.findall(r'^\s*Violations found\s*:\s*(\d+)\s*$', text, re.M)
    if len(totals) != 1:
        errors.append('DRC missing/duplicate total violation count')
    summary = []
    for line in text.splitlines():
        if line.startswith('|') and re.search(r'[A-Z]+-\d+', line):
            m = re.fullmatch(r'\|\s*([A-Z]+-\d+)\s*\|\s*(\w+)\s*\|[^|]*\|\s*(\d+)\s*\|', line)
            if not m:
                errors.append('Unparsed DRC summary diagnostic: ' + line)
            else:
                summary.append((m[1], m[2], int(m[3])))
    if not summary:
        errors.append('No DRC summary rows')
    if len({(r, s) for r, s, _ in summary}) != len(summary):
        errors.append('Duplicate DRC summary rule/severity')
    details = []
    for line in text.splitlines():
        if re.match(r'^[A-Z]+-\d+#', line):
            m = re.fullmatch(r'([A-Z]+-\d+)#(\d+)\s+(\w+)\s*', line)
            if not m:
                errors.append('Unparsed DRC detail diagnostic: ' + line)
            else:
                details.append((m[1], int(m[2]), m[3]))
        if ISSUE.search(line):
            errors.append('Adverse DRC text: ' + line.strip())
    allowed = {'SLATR-1036', 'SLATR-1038'}
    for rule, severity, count in summary:
        if rule not in allowed or severity != 'NOTE':
            errors.append(f'Non-whitelisted DRC summary {rule}/{severity}')
        ids = [idx for r, idx, s in details if r == rule and s == severity]
        if len(ids) != count or sorted(ids) != list(range(1, count + 1)):
            errors.append(f'DRC summary/detail count or numbering mismatch: {rule}')
    for rule, _, severity in details:
        if rule not in allowed or severity != 'NOTE':
            errors.append(f'Non-whitelisted DRC detail {rule}/{severity}')
    total = int(totals[0]) if len(totals) == 1 else None
    if total != sum(c for _, _, c in summary) or total != len(details):
        errors.append('DRC total/summary/detail mismatch')
    return {'passed': not errors, 'errors': errors, 'total': total, 'summary': summary,
            'detail_count': len(details)}


def check_timing(text):
    errors, metrics = [], {}
    for key in ('SWNS', 'STNS', 'HWNS', 'HTNS'):
        found = re.findall(r'\b' + key + r':\s*([-+]?\d+(?:\.\d+)?)ns', text)
        if len(found) != 1:
            errors.append('Missing/duplicate timing ' + key)
        else:
            metrics[key] = float(found[0])
            if metrics[key] < 0 or (key.endswith('TNS') and metrics[key] != 0):
                errors.append(f'{key} fails threshold')
    for expr in (r'Confidence\s*:\s*Routed', r'Check Corner\s*:\s*Both \(Slow and Fast\)',
                 r'^Slow\s*\|\s*yes\s+yes', r'^Fast\s*\|\s*yes\s+yes'):
        if not re.search(expr, text, re.M):
            errors.append('Timing scope missing: ' + expr)
    return {'passed': not errors, 'errors': errors, 'metrics_ns': metrics}


def check_area(text):
    errors, resources = [], {}
    for label, limit in (('slice', 95), ('eram', 90), ('dsp', 95)):
        values = re.findall(r'^#' + label + r'\s+(\d+)\s+out of\s+(\d+)\s+([\d.]+)%', text, re.M | re.I)
        if len(values) != 1 or int(values[0][1]) == 0:
            errors.append('Missing/duplicate resource ' + label)
            continue
        used, total = int(values[0][0]), int(values[0][1])
        resources[label] = {'used': used, 'total': total, 'percent': used * 100 / total}
        if used * 100 >= total * limit:
            errors.append(label + ' resource fails strict threshold')
    if resources.get('dsp', {}).get('used', 999) > 37:
        errors.append('DSP count increased from baseline 37')
    return {'passed': not errors, 'errors': errors, 'resources': resources}


def tsv(path):
    with path.open(encoding='utf-8-sig', newline='') as stream:
        return list(csv.DictReader(stream, delimiter='\t'))


def check_sites(audit, expected_count):
    errors = []
    expected_rows = tsv(audit / 'expected_slice_cells.tsv')
    expected = {r['cell']: r['ref_name'] for r in expected_rows}
    if len(expected) != len(expected_rows) or len(expected) != expected_count:
        errors.append('Expected Slice list duplicates/count mismatch')
    allrows = tsv(audit / 'readonly.sites.tsv')
    slices = [r for r in allrows if r['ref_name'] in {'PH1P_PHY_LSLICE', 'PH1P_PHY_MSLICE'}]
    actual = {r['cell']: r['ref_name'] for r in slices}
    if actual != expected or len(actual) != len(slices):
        errors.append('Placed Slice list does not correspond exactly to expected list')
    tiles = {(int(r['col']), int(r['row'])): r['tile_name']
             for r in tsv(audit / 'physical_capacity/named_logic_tiles.tsv')}
    slots = set()
    for r in slices:
        if r['is_placed'] != '1':
            errors.append('Unplaced Slice: ' + r['cell'])
            continue
        site = (int(r['col']), int(r['row']), int(r['offset']))
        tile = tiles.get(site[:2])
        if site in slots:
            errors.append('Duplicate physical Slice slot: ' + str(site))
        slots.add(site)
        if site[2] not in range(8) or tile not in {'Plb', 'Pmb'}:
            errors.append('Invalid Slice physical site: ' + r['cell'])
        if r['ref_name'] == 'PH1P_PHY_MSLICE' and tile != 'Pmb':
            errors.append('Incompatible memory Slice site: ' + r['cell'])
    proof = json.loads(read(audit / 'physical_capacity/physical_capacity_validation.json'))
    if not proof.get('passed') or proof.get('placed_compatible_unique_slices') != expected_count:
        errors.append('Physical device capacity proof failed')
    for name, item in proof.get('inputs', {}).items():
        path = Path(item['path'])
        if not path.is_file() or sha(path) != item['sha256']:
            errors.append('Physical proof input hash drift: ' + name)
    return {'passed': not errors, 'errors': errors, 'expected_slices': len(expected),
            'placed_slices': len(slices), 'unique_sites': len(slots)}


def run(audit):
    checks, evidence = {}, {}
    names = ['console_readonly.log', 'readonly.drc', 'readonly.timing', 'readonly.area',
             'readonly.sites.tsv', 'expected_slice_cells.tsv', 'readonly_input_hashes.json',
             'readonly_verification.json', 'physical_capacity/physical_capacity_validation.json',
             'physical_capacity/named_logic_tiles.tsv']
    for name in names:
        path = audit / name
        if not path.is_file():
            raise ValueError('Missing evidence ' + str(path))
        evidence[name] = {'path': str(path.resolve()), 'sha256': sha(path)}
    log = read(audit / 'console_readonly.log')
    checks['area'] = check_area(read(audit / 'readonly.area'))
    count = checks['area']['resources'].get('slice', {}).get('used', -1)
    checks['placed_sites'] = check_sites(audit, count)
    checks['check_design'] = check_design(log, checks['placed_sites']['passed'])
    checks['check_io'] = check_simple_command(log, 'check_io', 'CHECK_IO_STATUS')
    starts = re.findall(r'^RUN-1002 : start command "(check_plb_attr[^"\n]*)"$', log, re.M)
    checks['check_plb'] = (check_simple_command(log, starts[0], 'CHECK_PLB_STATUS') if len(starts) == 1
                           else {'passed': False, 'errors': ['Missing/duplicate check_plb invocation']})
    checks['drc'] = check_drc(read(audit / 'readonly.drc'))
    checks['timing'] = check_timing(read(audit / 'readonly.timing'))
    bad_clocks = re.findall(r'^.*(?:RTCLK-5078|USR-6113).*$', log, re.M)
    checks['tracked_clock_warnings'] = {'passed': not bad_clocks, 'errors': bad_clocks}
    raw_hashes = json.loads(read(audit / 'readonly_input_hashes.json'))
    changed = [path for path, digest in raw_hashes.items() if not Path(path).is_file() or sha(path) != digest]
    checks['readonly_unchanged'] = {'passed': not changed and bool(raw_hashes), 'errors': changed}
    completion = log.count('TD_READONLY_REIMPORT_PASS') == 1
    checks['readonly_completion'] = {'passed': completion, 'errors': [] if completion else ['Missing/duplicate readonly marker']}
    return {'passed': all(c['passed'] for c in checks.values()), 'generated_utc': datetime.now(timezone.utc).isoformat(),
            'checks': checks, 'evidence': evidence, 'hardware_status': 'NOT_RUN',
            'scope': 'Strict read-only command/DRC/timing/placed-site audit. Raw adverse IO diagnostics are never hidden by catch=0.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit', type=Path, required=True)
    args = parser.parse_args()
    result = run(args.audit.resolve())
    json_path = args.audit / 'strict_independent_release_review.json'
    md_path = args.audit / 'strict_independent_release_review.md'
    json_path.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    lines = ['# Strict independent release review', '', 'Overall: ' + ('PASS' if result['passed'] else 'FAIL'), '']
    for name, item in result['checks'].items():
        lines.append('- ' + name + ': ' + ('PASS' if item['passed'] else 'FAIL'))
        for error in item.get('errors', []):
            lines.append('  - ' + error)
    lines += ['', 'Raw input SHA256:', '']
    lines += ['- ' + name + ': ' + obj['sha256'] for name, obj in result['evidence'].items()]
    lines += ['', result['scope'], '', 'Hardware: NOT_RUN', '']
    md_path.write_text('\n'.join(lines), encoding='utf-8')
    print(json.dumps({'passed': result['passed'], 'checks': {k: v['passed'] for k, v in result['checks'].items()}}, indent=2))
    return int(not result['passed'])


if __name__ == '__main__':
    raise SystemExit(main())
