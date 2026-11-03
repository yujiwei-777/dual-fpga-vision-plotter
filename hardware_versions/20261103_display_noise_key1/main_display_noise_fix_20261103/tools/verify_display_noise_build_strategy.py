"""Allow the exact V8 official AreaOptimizeHigh+pack line over vendor flow.

The synthesis, place and route scripts are otherwise byte-identical to the
successful baseline. This does not alter device capacity or timing constraints.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

from display_noise_paths import BASE, ROOT, RUN, NAME, put, read, sha

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
READBACK_RECEIPT = ROOT / 'reports/parameter_readback_trial/actual_readback_run_v2.json'
# Pin the reviewed read-only Tcl; a receipt hash alone must not authorize a
# script which prints wanted values or changes parameters before querying.
READBACK_TCL_SHA256 = '8D0F47DE9AEBC97801CD6F4FE77DAE006896321D0CD86AE219F137AB6792F7A2'
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


def validate_readback(run, receipt_path):
    """Verify real get_param returns from the unchanged completed gate DB.

    Receipt booleans are necessary but insufficient: pin/read the Tcl, hash
    every file, parse actual command/return order and all six exact values.
    The import's opt_area=high command is a documented observation in this
    raw TD log; permit it only nested inside that single DB import.
    """
    errors = []
    result = {'passed': False, 'errors': errors, 'receipt': str(receipt_path),
              'values': {}, 'scope': 'Read-only completed gate DB parameter query; not physical acceptance.'}
    try:
        receipt_path, run = Path(receipt_path), Path(run)
        receipt = json.loads(read(receipt_path))
        result['receipt_sha256'] = sha(receipt_path)
        expected_db = run / (NAME + '_gate.db')
        expected_script = receipt_path.parent / 'read_v8_parameters.tcl'
        expected_log = receipt_path.parent / 'console_readback_v2.log'
        for field, expected in (('db', expected_db), ('script', expected_script), ('log', expected_log)):
            if Path(receipt[field]).resolve() != expected.resolve():
                errors.append('Readback receipt binds the wrong ' + field + ' path')
        actual_db_sha = sha(expected_db)
        actual_script_sha, actual_log_sha = sha(expected_script), sha(expected_log)
        result.update(db=str(expected_db), db_sha256=actual_db_sha,
                      script=str(expected_script), script_sha256=actual_script_sha,
                      log=str(expected_log), log_sha256=actual_log_sha)
        if (receipt['db_sha256_before'] != actual_db_sha or receipt['db_sha256_after'] != actual_db_sha or
                receipt['db_unchanged'] is not True):
            errors.append('Readback DB before/after/current SHA256 binding failed')
        if (actual_script_sha != READBACK_TCL_SHA256 or receipt['script_sha256'] != actual_script_sha or
                receipt['script_unchanged'] is not True):
            errors.append('Readback reviewed read-only Tcl/hash binding failed')
        if receipt['log_sha256'] != actual_log_sha:
            errors.append('Readback raw log SHA256 binding failed')
        if type(receipt['process_exit_code']) is not int or receipt['process_exit_code'] != 0:
            errors.append('Readback process did not exit successfully')
        if receipt['readback_query_pass_marker'] is not True:
            errors.append('Readback receipt did not observe the final marker')
        if not (run / '.opt_gate.end.f').is_file() or (run / '.opt_gate.error.f').exists():
            errors.append('Readback is not bound to a completed error-free gate run')
        script = read(expected_script)
        input_assignment = re.findall(r'(?m)^set input_db \{([^}\r\n]+)\}\r?$', script)
        if len(input_assignment) != 1 or Path(input_assignment[0]).resolve() != expected_db.resolve():
            errors.append('Reviewed readback Tcl does not import the actual gate DB')
        log = read(expected_log)
        inputs = re.findall(r'(?m)^PARAM_READBACK_INPUT_DB=([^\r\n]+)\r?$', log)
        sizes = re.findall(r'(?m)^PARAM_READBACK_INPUT_BYTES=(\d+)\r?$', log)
        if len(inputs) != 1 or Path(inputs[0]).resolve() != expected_db.resolve():
            errors.append('Readback log input DB marker mismatch/duplicate')
        if sizes != [str(expected_db.stat().st_size)]:
            errors.append('Readback log input DB size mismatch/duplicate')
        starts = list(re.finditer(r'(?m)^RUN-1002\s*:\s*start command "([^"]+)"', log))
        finishes = list(re.finditer(r'(?m)^RUN-1003\s*:\s*finish command "([^"]+)"', log))
        device = 'import_device ph1_35p.db -package PH1P35MDG324 -speed 3'
        imports = [m for m in starts if m[1].startswith('import_db ')]
        import_ends = [m for m in finishes if m[1].startswith('import_db ')]
        devices = [m for m in starts if m[1] == device]
        device_ends = [m for m in finishes if m[1] == device]
        valid_import = (len(imports) == len(import_ends) == len(devices) == len(device_ends) == 1)
        if valid_import:
            valid_import = (Path(imports[0][1][len('import_db '):]).resolve() == expected_db.resolve() and
                            imports[0][1] == import_ends[0][1] and
                            devices[0].start() < device_ends[0].start() < imports[0].start() < import_ends[0].start())
        if not valid_import:
            errors.append('Readback needs one exact successful device/DB import in order')
        expected_queries = ['get_param ' + step + ' ' + name for step, name, _, _ in PARAMETERS]
        queries = [m for m in starts if m[1].startswith('get_param ')]
        if [m[1] for m in queries] != expected_queries:
            errors.append('Readback needs each of the six exact get_param commands once in order')
        values = list(re.finditer(r'(?m)^PARAM_READBACK_VALUE\|([^|\r\n]+)\|([^|\r\n]+)\|([^|\r\n]+)\r?$', log))
        actual_values = [(m[1], m[2], m[3]) for m in values]
        expected_values = [(step, name, value) for step, name, value, _ in PARAMETERS]
        if actual_values != expected_values or len(re.findall(r'(?m)^PARAM_READBACK_VALUE', log)) != 6:
            errors.append('Readback actual get_param values are missing/duplicate/out-of-order/wrong')
        if len(queries) == len(values) == 6 and valid_import:
            for index, (query, value) in enumerate(zip(queries, values)):
                next_start = queries[index + 1].start() if index < 5 else len(log)
                if not import_ends[0].start() < query.start() < value.start() < next_start:
                    errors.append('Readback value must follow its get_param after DB import')
        markers = list(re.finditer(r'(?m)^PARAM_READBACK_QUERY_MATCHES=6\r?$', log))
        scopes = list(re.finditer(r'(?m)^PARAM_READBACK_SCOPE=DB settings queried after import; this is not a new synthesis run or a physical acceptance gate\r?$', log))
        if (len(markers) != 1 or len(re.findall(r'(?m)^PARAM_READBACK_QUERY_MATCHES=', log)) != 1 or
                len(scopes) != 1 or not values or not values[-1].start() < markers[0].start() < scopes[0].start()):
            errors.append('Readback final exact six-query marker/scope missing/duplicate/out-of-order')
        allowed = {device, 'import_db ' + expected_db.as_posix(), *expected_queries,
                   'report_param -stage rtl -detail -all', 'report_param -stage gate -detail -all'}
        nested_side_effects = []
        for command in starts:
            if command[1] in allowed:
                continue
            if (command[1] == 'set_param gate opt_area high' and valid_import and
                    imports[0].start() < command.start() < import_ends[0].start()):
                nested_side_effects.append(command[1])
            else:
                errors.append('Readback has an unauthorized mutating/reload/extra command: ' + command[1])
        if len(nested_side_effects) > 1:
            errors.append('Readback repeats the import-internal opt_area side effect')
        if re.search(r'ERROR:|FATAL:|PARAM_READBACK_(?:ERROR|MISMATCH|API_UNAVAILABLE|NOT_VERIFIED|REPORT_UNAVAILABLE)', log):
            errors.append('Readback log contains an error/unavailable/mismatch diagnostic')
        result['query_commands'] = [m[1] for m in queries]
        result['actual_value_rows'] = actual_values
        result['import_internal_commands'] = nested_side_effects
        if not errors:
            result['values'] = {name: value for _, name, value in actual_values}
    except (OSError, ValueError, KeyError, TypeError) as exc:
        errors.append('Readback evidence missing/invalid: ' + str(exc))
    result['passed'] = not errors
    return result


def validate_log(log, readback_values=None):
    """TD logs set_param start only; commit tables and real DB query prove effect.

    Do not invent a set_param RUN-1003 record. Require the actual setting before
    the corresponding RTL/gate commits, tables, and completed passes. Missing
    advanced-property rows fail closed unless actual DB-bound get_param values
    were independently verified by validate_readback. Existing wrong rows are
    never overridden; the two public rows always remain mandatory.
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
        from_readback = (not rows and default is None and readback_values is not None and
                         readback_values.get(name) == value)
        if valid_row:
            actual, original, note = committed_rows[name][0]
            valid_row = (actual == value and bool(original) and
                         (default is None or original == default) and
                         note == ('*' if actual != original else ''))
        if not valid_row and not from_readback:
            errors.append('Actual committed ' + step + ' table lacks exact value/default/note evidence for ' + name + '=' + value)
        if step in stages and len(settings) == 1:
            commit, optimize, _ = stages[step]
            if not settings[0].start() < commit.start() < optimize.start():
                errors.append('Actual ' + name + ' setting must precede corresponding commit/optimize')
            if len(rows) == 1 and not commit.start() < rows[0].start() < optimize.start():
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
            'missing_advanced_rows': [name for _, name, _, default in PARAMETERS
                                      if default is None and not committed_rows[name]],
            'advanced_rows_proved_by_readback': [name for _, name, value, default in PARAMETERS
                                                if default is None and not committed_rows[name] and
                                                readback_values is not None and readback_values.get(name) == value],
            'proof': 'Six unique exact settings before corresponding commits; mandatory public commit rows; hidden rows or DB-bound real get_param; no reset/override; both optimization completions.'}


def validate(run=RUN, base=BASE, require_log=False, snapshot=None, readback_receipt=None):
    errors, scripts, actual_log, readback = [], [], None, None
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
            if actual_log['missing_advanced_rows']:
                readback = validate_readback(run, readback_receipt or READBACK_RECEIPT)
                if readback['passed']:
                    actual_log = validate_log(log, readback['values'])
                else:
                    errors.extend(readback['errors'])
            errors.extend(actual_log['errors'])
            actual_log['path'] = str(logfile)
            actual_log['sha256'] = sha(logfile)
            if not (run / '.opt_gate.end.f').is_file() or (run / '.opt_gate.error.f').exists():
                errors.append('Synthesis gate completion marker is missing or an error marker remains')
    return {'passed': not errors, 'errors': errors, 'scripts': scripts,
            'authorized_change': AUTHORIZED_LINE.decode(),
            'parameters': [{'step': step, 'name': name, 'value': value} for step, name, value, _ in PARAMETERS],
            'official_strategy': official,
            'documentation': DOCUMENTATION, 'actual_synthesis_log_required': require_log,
            'actual_synthesis_log_review': actual_log,
            'independent_parameter_readback': readback,
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
