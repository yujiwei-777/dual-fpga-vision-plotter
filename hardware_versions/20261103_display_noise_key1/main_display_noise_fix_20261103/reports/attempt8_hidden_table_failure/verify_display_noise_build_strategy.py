"""Allow the exact V8 official AreaOptimizeHigh+pack line over vendor flow.

The synthesis, place and route scripts are otherwise byte-identical to the
successful baseline. This does not alter device capacity or timing constraints.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

from display_noise_paths import BASE, ROOT, RUN, put, read, sha

AUTHORIZED_LINE = b'set synWildParams {gate add_map_lut_struct high gate map_mode area_prior gate multi_thread_mapping partition rtl resource_sharing auto rtl shifter_style shifter_reg gate pack_effort high}'
PARAMETERS = (
    ('gate', 'add_map_lut_struct', 'high', None),
    ('gate', 'map_mode', 'area_prior', 'auto'),
    ('gate', 'multi_thread_mapping', 'partition', None),
    ('rtl', 'resource_sharing', 'auto', None),
    ('rtl', 'shifter_style', 'shifter_reg', None),
    ('gate', 'pack_effort', 'high', 'medium'),
)
OFFICIAL_PATH = Path('E:/td/doc/strategies/official_strategy_ph1.json')
OFFICIAL_SHA256 = '6AAF4F51B9494C5F56AEBDB29C277FB350D05A1D122797B8553F9E24CD97792A'
BASE_RUN = '01_rtl/imgq_gain_m/main/td_project_pcb_auto_v2'
BASE_SCRIPT_HASHES = {
    'synth': '1CCECC28EA691C20D53397F8E51080D7B0DB983940450C65CEF537C6E9F9D49C',
    'place': '7F37E60BC89F993AD45FFEF350A60F0956B629B94789F83BA56906F8CC97EF74',
    'route': '2B7EDE0874A3CD6E1599CB3FAA04DFCABFC73D06FB706B48556DFE78F042BF2A',
}
DOCUMENTATION = [
    {'path': 'E:/td/doc/TD_User_Guide_V6.2.pdf', 'pdf_page': 231,
     'printed_page': 230, 'section': 'Optimize Gate parameter table',
     'finding': 'pack_effort ALL; default medium; high may reduce Slice and increase local congestion.'},
    {'path': 'E:/td/doc/TD_User_Guide_V6.2.pdf', 'pdf_pages': [78, 231, 246],
     'printed_pages': [77, 230, 245], 'section': 'Optimize Gate and AreaOptimizeHigh',
     'finding': 'map_mode ALL; auto/area_prior/logic_level_prior/balance_explore. AreaOptimizeHigh supports PH1P.'},
    {'path': str(OFFICIAL_PATH), 'lines': [23, 53], 'sha256': OFFICIAL_SHA256,
     'finding': 'Exact official five AreaOptimizeHigh tuples; additional pack_effort high is separate.'},
    {'path': 'E:/td/doc/SWUG/SWUG105_TCL_Command_User_Guide.pdf',
     'pdf_pages': [28, 29], 'printed_pages': [21, 22], 'section': '4.1.18 set_param',
     'finding': 'set_param [-run <run_name>] <step_name> <param> <value>'},
    {'path': 'E:/td/scripts/DefaultFlow.tcl', 'lines': [65, 72, 77, 142, 145],
     'finding': 'load_run_param/import_db, positional wildParams set_param, commit_param gate, optimize_gate.'},
]


def validate_log(log):
    """TD logs set_param start only; the committed table proves its effect.

    Do not invent a set_param RUN-1003 record. Require the actual setting before
    the corresponding RTL/gate commits, tables, and completed passes. Missing
    advanced-property rows fail closed pending genuine independent readback.
    """
    errors = []
    commands = list(re.finditer(r'(?m)^RUN-1002\s*:\s*start command "([^"]+)"', log))
    stages = {}
    for step in ('rtl', 'gate'):
        commits = [m for m in commands if m[1] == 'commit_param -step ' + step]
        optimizes = [m for m in commands if m[1] == 'optimize_' + step or m[1].startswith('optimize_' + step + ' ')]
        if len(commits) != 1 or len(optimizes) != 1:
            errors.append('Actual synth.log needs one ' + step + ' commit and one optimize_' + step + ' start')
            continue
        commit, optimize = commits[0], optimizes[0]
        if commit.start() >= optimize.start():
            errors.append('Actual ' + step + ' commit follows optimization')
        window = log[commit.end():optimize.start()]
        if len(re.findall(r'(?mi)^RUN-1001\s*:\s*Print ' + step + r' Property\s*$', window)) != 1:
            errors.append('Effective parameter rows are not in the ' + step + ' commit property table')
        finishes = list(re.finditer(r'(?m)^RUN-1003\s*:\s*finish command "' + re.escape(optimize[1]) + r'"', log))
        if len(finishes) != 1 or finishes[0].start() <= optimize.start():
            errors.append('Actual optimize_' + step + ' lacks exactly one successful completion')
        stages[step] = (commit, optimize, finishes)
    if set(stages) == {'rtl', 'gate'} and len(stages['rtl'][2]) == 1:
        if stages['rtl'][2][0].start() >= stages['gate'][0].start():
            errors.append('RTL must complete before gate commit')
    all_settings, committed_rows = [], {}
    for step, name, value, default in PARAMETERS:
        settings = [m for m in commands if m[1].startswith('set_param ') and
                    re.search(r'\b' + re.escape(name) + r'\b', m[1])]
        all_settings.extend(settings)
        rows = list(re.finditer(r'(?m)^RUN-1001\s*:\s*' + re.escape(name) + r'\s*\|\s*([^|\r\n]+)\|\s*([^|\r\n]+)\|([^\r\n]*)\r?$', log))
        committed_rows[name] = [[part.strip().strip('|').strip() for part in m.groups()] for m in rows]
        if len(settings) != 1 or settings[0][1] != 'set_param ' + step + ' ' + name + ' ' + value:
            errors.append('Actual synth.log needs exactly one authorized ' + name + ' setting and no overrides')
        valid_row = len(rows) == 1
        if valid_row:
            actual, original, note = committed_rows[name][0]
            valid_row = (actual == value and bool(original) and
                         (default is None or original == default) and
                         note == ('*' if actual != original else ''))
        if not valid_row:
            errors.append('Actual committed ' + step + ' table lacks exact value/default/note evidence for ' + name + '=' + value)
        if step in stages and len(settings) == len(rows) == 1:
            commit, optimize, _ = stages[step]
            if not settings[0].start() < commit.start() < rows[0].start() < optimize.start():
                errors.append('Actual ' + name + ' setting, gate commit, table and optimize order is invalid')
    if all_settings:
        first_setting = min(m.start() for m in all_settings)
        resets = [m for m in commands if m.start() > first_setting and
                  re.match(r'(?:load_run_param|reset_params|clear_param|clear_prj_params|import_param|import_db)\b', m[1])]
        if resets:
            errors.append('Parameters may have been reset/reloaded after an authorized setting')
    if re.search(r'ERROR:|FATAL:', log):
        errors.append('Actual synthesis log contains an error/fatal diagnostic')
    return {'passed': not errors, 'errors': errors,
            'setting_commands': [m[1] for m in sorted(all_settings, key=lambda m: m.start())],
            'committed_rows': committed_rows,
            'set_param_finish_record_required': False,
            'proof': 'All six exact settings; corresponding RTL/gate commit tables; no reset/override; both optimization completions.'}


def validate(run=RUN, base=BASE, require_log=False, snapshot=None):
    errors, scripts, actual_log = [], [], None
    official = {'path': OFFICIAL_PATH.as_posix(), 'sha256': None, 'passed': False}
    try:
        official['sha256'] = sha(OFFICIAL_PATH)
        data = json.loads(read(OFFICIAL_PATH))['AreaOptimizeHigh']
        expected = [{'step': step, 'param': name, 'val': value} for step, name, value, _ in PARAMETERS[:-1]]
        official['passed'] = (official['sha256'] == OFFICIAL_SHA256 and data.get('is_syn') == 'syn' and data.get('params') == expected)
    except (OSError, ValueError, KeyError, TypeError) as exc:
        official['error'] = str(exc)
    if not official['passed']:
        errors.append('Official PH1 AreaOptimizeHigh JSON hash/tuple evidence missing or changed')
    frozen = {str(Path(f['path']).resolve()).casefold(): f['sha256']
              for f in snapshot.get('files', [])} if snapshot is not None else None
    for stage, expected in BASE_SCRIPT_HASHES.items():
        original = base / BASE_RUN / ('run_compact_' + stage + '.tcl')
        current = run / ('run_display_noise_' + stage + '.tcl')
        if not original.is_file() or sha(original) != expected:
            errors.append('Immutable baseline build script missing/changed: ' + stage)
            continue
        if not current.is_file():
            errors.append('Missing current build script: ' + stage)
            continue
        source, raw = original.read_bytes(), current.read_bytes()
        stripped = raw
        if stage == 'synth':
            lines = raw.splitlines(keepends=True)
            selected = [i for i, line in enumerate(lines) if line.rstrip(b'\r\n') == AUTHORIZED_LINE]
            if len(selected) != 1:
                errors.append('Synthesis requires exactly one authorized area/pack line')
            else:
                authorized = lines[selected[0]]
                stripped = b''.join(lines[:selected[0]] + lines[selected[0] + 1:])
                anchor = b'set area_option -packarea'
                # The line must be immediately after the existing header anchor,
                # before the unchanged vendor prepare/commit flow.
                index = raw.find(anchor)
                if index < 0 or not raw[index + len(anchor):].lstrip(b'\r\n').startswith(authorized):
                    errors.append('Authorized line is outside the fixed editable header location')
        if stripped != source:
            errors.append('Build Tcl changed beyond exact authorized synthesis line: ' + stage)
        if frozen is not None and frozen.get(str(current.resolve()).casefold()) != sha(current):
            errors.append('Actual build Tcl is not bound to the prebuild snapshot: ' + stage)
        scripts.append({'stage': stage, 'baseline': str(original), 'current': str(current),
                        'baseline_sha256': expected, 'sha256': sha(current),
                        'stripped_sha256': hashlib.sha256(stripped).hexdigest().upper(),
                        'otherwise_byte_identical': stripped == source})
    if require_log:
        logfile = run / 'synth.log'
        if not logfile.is_file():
            errors.append('Missing actual synthesis log for area/pack verification')
        else:
            log = read(logfile)
            actual_log = validate_log(log)
            errors.extend(actual_log['errors'])
            if not (run / '.opt_gate.end.f').is_file() or (run / '.opt_gate.error.f').exists():
                errors.append('Synthesis gate completion marker is missing or an error marker remains')
    return {'passed': not errors, 'errors': errors, 'scripts': scripts,
            'authorized_change': AUTHORIZED_LINE.decode(),
            'parameters': [{'step': step, 'name': name, 'value': value} for step, name, value, _ in PARAMETERS],
            'official_strategy': official,
            'documentation': DOCUMENTATION, 'actual_synthesis_log_required': require_log,
            'actual_synthesis_log_review': actual_log,
            'snapshot_binding_required': snapshot is not None,
            'constraints_and_resource_timing_thresholds_changed': False}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--require-log', action='store_true')
    parser.add_argument('--require-snapshot', action='store_true')
    args = parser.parse_args()
    snapshot = json.loads(read(RUN / 'source_snapshot.json')) if args.require_snapshot else None
    result = validate(require_log=args.require_log, snapshot=snapshot)
    put(ROOT / 'reports/display_noise_build_strategy.json', result)
    print({'passed': result['passed'], 'errors': result['errors']})
    return int(not result['passed'])


if __name__ == '__main__':
    raise SystemExit(main())
