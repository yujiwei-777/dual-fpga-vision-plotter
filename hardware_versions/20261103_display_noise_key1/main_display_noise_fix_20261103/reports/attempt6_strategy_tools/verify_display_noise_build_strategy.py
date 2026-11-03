"""Allow exactly one documented V5 pack-effort line over immutable vendor flow.

The synthesis, place and route scripts are otherwise byte-identical to the
successful baseline. This does not alter device capacity or timing constraints.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

from display_noise_paths import BASE, ROOT, RUN, put, read, sha

AUTHORIZED_LINE = b'set synWildParams {gate pack_effort high}'
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
    {'path': 'E:/td/doc/SWUG/SWUG105_TCL_Command_User_Guide.pdf',
     'pdf_pages': [28, 29], 'printed_pages': [21, 22], 'section': '4.1.18 set_param',
     'finding': 'set_param [-run <run_name>] <step_name> <param> <value>'},
    {'path': 'E:/td/scripts/DefaultFlow.tcl', 'lines': [65, 72, 77, 142, 145],
     'finding': 'load_run_param/import_db, positional wildParams set_param, commit_param gate, optimize_gate.'},
]


def validate_log(log):
    """TD logs set_param start only; the committed table proves its effect.

    Do not invent a set_param RUN-1003 record. Require the actual setting before
    gate commit, one committed high/medium/* row, and the completed gate pass.
    """
    errors = []
    commands = list(re.finditer(r'(?m)^RUN-1002\s*:\s*start command "([^"]+)"', log))
    settings = [m for m in commands if m[1].startswith('set_param ') and
                re.search(r'\bpack_effort\b', m[1])]
    commits = [m for m in commands if m[1] == 'commit_param -step gate']
    optimizes = [m for m in commands if m[1].startswith('optimize_gate ')]
    rows = list(re.finditer(r'(?m)^RUN-1001\s*:\s*pack_effort\s*\|\s*([^|\r\n]+)\|\s*([^|\r\n]+)\|([^\r\n]*)\r?$', log))
    if len(settings) != 1 or settings[0][1] != 'set_param gate pack_effort high':
        errors.append('Actual synth.log needs exactly one authorized pack-effort setting and no overrides')
    if len(commits) != 1 or len(optimizes) != 1:
        errors.append('Actual synth.log needs one gate commit and one optimize_gate start')
    # Column spacing varies, while the effective setting/default/note may not.
    if len(rows) != 1 or rows[0][1].strip() != 'high' or rows[0][2].strip() != 'medium' or rows[0][3].strip().strip('|').strip() != '*':
        errors.append('Actual committed gate table needs one pack_effort high/default medium/* row')
    if len(settings) == len(commits) == len(optimizes) == len(rows) == 1:
        setting, commit, optimize, row = settings[0], commits[0], optimizes[0], rows[0]
        if not setting.start() < commit.start() < row.start() < optimize.start():
            errors.append('Actual pack-effort setting, gate commit, table and optimize order is invalid')
        window = log[commit.end():optimize.start()]
        if len(re.findall(r'(?m)^RUN-1001\s*:\s*Print Gate Property\s*$', window)) != 1:
            errors.append('Effective pack-effort row is not in the gate commit property table')
        finishes = list(re.finditer(r'(?m)^RUN-1003\s*:\s*finish command "' + re.escape(optimize[1]) + r'"', log))
        if len(finishes) != 1 or finishes[0].start() <= optimize.start():
            errors.append('Actual optimize_gate command lacks exactly one successful completion')
        resets = [m for m in commands if m.start() > setting.start() and
                  re.match(r'(?:load_run_param|reset_params|clear_param|clear_prj_params|import_param|import_db)\b', m[1])]
        if resets:
            errors.append('Parameters may have been reset/reloaded after the authorized high setting')
    if re.search(r'ERROR:|FATAL:', log):
        errors.append('Actual synthesis log contains an error/fatal diagnostic')
    return {'passed': not errors, 'errors': errors,
            'setting_commands': [m[1] for m in settings],
            'committed_rows': [[part.strip().strip('|').strip() for part in m.groups()] for m in rows],
            'set_param_finish_record_required': False,
            'proof': 'Unique setting before gate commit; committed high table; no reset/override; optimize_gate completion.'}


def validate(run=RUN, base=BASE, require_log=False, snapshot=None):
    errors, scripts, actual_log = [], [], None
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
                errors.append('Synthesis requires exactly one authorized pack-effort line')
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
            errors.append('Missing actual synthesis log for pack-effort verification')
        else:
            log = read(logfile)
            actual_log = validate_log(log)
            errors.extend(actual_log['errors'])
            if not (run / '.opt_gate.end.f').is_file() or (run / '.opt_gate.error.f').exists():
                errors.append('Synthesis gate completion marker is missing or an error marker remains')
    return {'passed': not errors, 'errors': errors, 'scripts': scripts,
            'authorized_change': AUTHORIZED_LINE.decode(), 'parameter': {'step': 'gate', 'name': 'pack_effort', 'value': 'high'},
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
