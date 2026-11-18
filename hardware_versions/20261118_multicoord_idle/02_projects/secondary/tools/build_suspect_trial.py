"""Independent PCB operator-UI pair build; no release or bitgen action.

scope reads the exact selected baseline; lint checks current SYNTHESIS syntax.
prepare freezes source-only inputs into a new E: directory without starting TD.
syn/place/route are explicit actions against that frozen manifest. Negative
mapped WNS is diagnostic; final acceptance always requires routed setup/hold,
strict resources, current regressions and independent physical signoff.
"""
from __future__ import annotations
import argparse
import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
BOARD = 'secondary'
REQUIRED_ROOT = 'secondary_pcb_operator_ui_20261111'
REPORT = ROOT / 'reports/suspect_trial/build'
DEFAULT_RUN = Path('E:/codex_pcb_operator_ui_secondary_20261111_r1')
TD = Path('E:/td/bin/td_commands_prompt.exe')
MAIN_RUN = Path('01_rtl/imgq_gain_m/main/td_project_display_noise_v8')
MAIN_HDL = '01_rtl/imgq_gain_m/main/user_source/hdl_source/'
LIMITS = {'slice':95,'eram':90,'dsp':95}
NAME = 'secondary_cnn_multibox'
BASE = ROOT.parent / 'secondary_pcb_runtime_fix_20261111'
BIT = 'artifacts/dual_fpga_secondary_20261111_pcb_runtime_fix_diagnostic.bit'
BIT_SHA = '892CDE387093FB65404E72E1C5EC65BBB1689EFF0352D3B45B2F09E8811FA091'
CONTROL = Path('E:/codex_pcb_runtime_fix_secondary_20261111_r1')
BASE_MANIFEST = CONTROL / 'SOURCE_MANIFEST.json'
BASE_MANIFEST_SHA = '4D9F10BC0FFF24E38D7690C39C48F399C611AC4BAF3666FEF1C704F38EA5C960'
PROJECT = Path('secondary_cnn_multibox.al')
CONTROL_PROJECT = Path('runs/syn_1/secondary_cnn_multibox.al')
SUPPORT = ['01_rtl', '04_pin', 'shared', 'main', 'model']
AUDIT_CONFIG = 'binary_source_audit_config.json'
FLOWS = {'runs/syn_1/run.tcl': 'D8815D7606EDB0A2AE83E651B22B817D5BE687D5C57ED0E16CC455EA271F101D', 'runs/syn_1/settings.cfg': '84FEFB7933411BE4C9E8E9DC2F347F77C81AC0092256282FB35A57EEB7B1D90A', 'runs/phy_1/run_place.tcl': 'EC18F7507C310D0CAE98E4E797200B4BC083D134CFF52ED1D408D69EE1470FAF', 'runs/phy_1/run_route.tcl': '12AF06EE638313925EA2C090DA4CE6528F4884119FDD9DD2BF1F540C94FD81DC', 'runs/phy_1/settings.cfg': '909E1816CA5C3E19B4B3AD6C34DD271EF1E16666009FEAEBFA4154B200DDF90C'}
ALLOWED = set()


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def safe(path, root=None):
    path = Path(path).resolve()
    require('work' not in {x.lower() for x in path.parts}, 'Protected work/ path: ' + str(path))
    if root is not None:
        require(path.is_relative_to(Path(root).resolve()), 'Dependency escapes root: ' + str(path))
    return path


def sha(path):
    h = hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest().upper()


def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def put(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def xml(path):
    text = Path(path).read_text(encoding='utf-8-sig')
    text = re.sub(r'&(?!#?\w+;)', '&amp;', text)
    text = re.sub(r'(<\/?[A-Za-z_][\w:]*)::', lambda m: m[1] + '_TD_DOUBLE_COLON_', text)
    return ET.fromstring(text)


def source_path(value, project_parent):
    path = Path(value)
    if path.is_absolute():
        path = path.resolve()
        if path.is_relative_to(BASE.resolve()):
            path = ROOT / path.relative_to(BASE.resolve())
    else:
        path = project_parent / path
    return safe(path, ROOT)


def project_inputs():
    tree = xml(ROOT / PROJECT)
    rows = []
    for group in tree.findall('Source_Files/*'):
        for node in group.findall('File'):
            rows.append((group.tag, node, source_path(node.attrib['Path'], (ROOT / PROJECT).parent)))
    require(rows, 'No declared project inputs')
    require(all(p.is_file() for _, _, p in rows), 'Declared input missing')
    return tree, rows


def support_files(root):
    files = {}
    for folder in SUPPORT:
        for path in sorted((root / folder).rglob('*')):
            if path.is_file() and '__pycache__' not in path.parts:
                resolved = safe(path, root)
                require(not path.is_symlink(), 'Symlink input prohibited: ' + str(path))
                files[path.relative_to(root).as_posix()] = resolved
    return files


def project_scope():
    old, new = xml(CONTROL / CONTROL_PROJECT), xml(ROOT / PROJECT)
    def semantic(node):
        return None if node is None else (node.tag,dict(node.attrib),(node.text or '').strip(),[semantic(x) for x in node])
    for tag in ['Name','HardWare','TOP_MODULE','Configurations','Runs','MultiSeed']:
        require(semantic(old.find(tag))==semantic(new.find(tag)), 'Protected project settings changed: '+tag)
    def declarations(tree, parent, origin_root):
        result={}
        for group in tree.findall('Source_Files/*'):
            for node in group.findall('File'):
                path=Path(node.attrib['Path'])
                path=safe(path if path.is_absolute() else parent/path, origin_root)
                relative=path.relative_to(origin_root).as_posix()
                result[(group.tag,relative)]=[(a.attrib['Name'],a.attrib['Val']) for a in node.findall('FileInfo/Attr')]
        return result
    before=declarations(old,(CONTROL/CONTROL_PROJECT).parent,CONTROL)
    after=declarations(new,(ROOT/PROJECT).parent,ROOT)
    require(set(before)<=set(after),'Declared baseline source removed')
    for key in before:require(before[key]==after[key],'Source compile attributes drift: '+str(key))
    allowed=set(load(ROOT/'tools/suspect_trial_scope.json')['allowed_production_changes'])
    for group,relative in set(after)-set(before):
        require(group=='Verilog' and relative in allowed,'Unexpected declaration: '+relative)
    return {'project':str(ROOT/PROJECT),'sha256':sha(ROOT/PROJECT),'new_declared_verilog':sorted(r for g,r in set(after)-set(before))}


def baseline_identity():
    require(ROOT.name==REQUIRED_ROOT,'Independent trial root required')
    require(sha(BASE/BIT)==BIT_SHA,'Baseline bit drift')
    require(sha(BASE_MANIFEST)==BASE_MANIFEST_SHA,'Baseline source manifest drift')
    rows=load(BASE_MANIFEST)['files']
    for relative,row in rows.items():require(sha(safe(CONTROL/relative,CONTROL))==row['sha256'],'Frozen baseline drift: '+relative)
    old,new=support_files(BASE),support_files(ROOT)
    if BOARD=='main':
        relative=(MAIN_RUN/'osd_compact_glyphs.vh').as_posix()
        old[relative],new[relative]=BASE/relative,ROOT/relative
    require(not(set(old)-set(new)),'Baseline support file removed')
    allowed=set(load(ROOT/'tools/suspect_trial_scope.json')['allowed_production_changes'])
    differences=[]
    for relative,path in sorted(new.items()):
        previous=sha(old[relative]) if relative in old else None
        current=sha(path)
        if previous!=current:
            require(relative in allowed,'Unapproved trial production change: '+relative)
            differences.append({'path':relative,'baseline_sha256':previous,'current_sha256':current})
    for relative,digest in FLOWS.items():require(sha(CONTROL/relative)==digest,'Vendor flow drift: '+relative)
    # Pin unchanged active production sources directly to the routed snapshot.
    checked=0
    for relative,row in rows.items():
        if relative in new and relative not in allowed:
            require(sha(new[relative])==row['sha256'],'Routed production mismatch: '+relative)
            checked+=1
    return {'baseline_root':str(BASE),'bit':str(BASE/BIT),'bit_sha256':BIT_SHA,
        'baseline_manifest':str(BASE_MANIFEST),'baseline_manifest_sha256':BASE_MANIFEST_SHA,
        'verified_baseline_entries':len(rows),'unchanged_active_sources':checked,
        'production_changes':differences,'project_scope':project_scope(),
        'classification_model_unchanged':True,'protected_constraints_ip_unchanged':True,
        'software_gate_override':'Inherited SUSPECT localization remains EXPLORATORY_NOT_PASSED; this variant adds operator UI only and claims no localization accuracy improvement.',
        'hardware_status':'NOT_RUN'}


def lint():
    identity = baseline_identity()
    _, rows = project_inputs()
    nodes = [(n, p) for group, n, p in rows if group == 'Verilog']
    def order(item):
        attrs = {a.attrib['Name']: a.attrib['Val'] for a in item[0].findall('FileInfo/Attr')}
        return int(attrs.get('CompileOrder', '0'))
    files = [p for _, p in sorted(nodes, key=order)]
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
    out = Path('E:/codex_pcb_operator_ui_' + BOARD + '_lint_' + stamp)
    out.mkdir()
    pin_files = [ROOT / PROJECT, *support_files(ROOT).values(), *[p for _, _, p in rows]]
    if BOARD == 'main':
        pin_files.append(ROOT / MAIN_RUN / 'osd_compact_glyphs.vh')
    pins = {str(p): sha(p) for p in pin_files}
    env = dict(os.environ, LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT', MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT')
    commands = [('vlib', ['E:/model/win64/vlib.exe', 'rtl_lib']),
        ('compile', ['E:/model/win64/vlog.exe', '-lint', '-work', 'rtl_lib', '+define+SYNTHESIS',
         *['+incdir+' + p for p in sorted({p.parent.as_posix() for p in files} | {(ROOT / PROJECT).parent.as_posix()})],
         *map(str, files)])]
    results = []
    for phase, command in commands:
        cp = subprocess.run(command, cwd=out, env=env, capture_output=True)
        path = out / (phase + '.log')
        path.write_bytes(cp.stdout + cp.stderr)
        text = path.read_text(encoding='utf-8-sig', errors='replace')
        passed = cp.returncode == 0 and not re.search(r'\*\*\s+(Error|Fatal):', text)
        results.append({'phase': phase, 'exit_code': cp.returncode, 'passed': passed,
                        'log': str(path), 'log_sha256': sha(path), 'command': command})
        require(passed, 'Syntax/lint failed: ' + str(path))
    require(all(sha(p) == digest for p, digest in pins.items()), 'Source changed during lint')
    put(REPORT / 'SYNTAX.json', {'status': 'SYNTAX_PASS_NOT_ELABORATED', 'baseline': identity,
        'source_sha256': pins, 'commands': results, 'hardware_status': 'NOT_RUN'})
    print(json.dumps({'status': 'SYNTAX_PASS_NOT_ELABORATED', 'output': str(out)}))


def write_project(tree, target, out):
    tree = copy.deepcopy(tree)
    tree.set('Path', target.as_posix())
    for group in tree.findall('Source_Files/*'):
        for node in group.findall('File'):
            origin = source_path(node.attrib['Path'], (ROOT / PROJECT).parent)
            dest = out / origin.relative_to(ROOT)
            require(dest.is_file(), 'Frozen declared source missing: ' + str(dest))
            node.set('Path', os.path.relpath(dest, target).replace('\\', '/'))
    ET.indent(tree)
    text = ET.tostring(tree, encoding='unicode').replace('_TD_DOUBLE_COLON_', '::')
    for extension in ['al', 'prj']:
        (target / (NAME + '.' + extension)).write_text('<?xml version="1.0" encoding="UTF-8"?>\n' + text + '\n', encoding='utf-8')


def prepare(out):
    identity = baseline_identity()
    syntax = load(REPORT / 'SYNTAX.json')
    require(syntax['status'] == 'SYNTAX_PASS_NOT_ELABORATED', 'Current syntax/lint required')
    require(all(sha(p) == digest for p, digest in syntax['source_sha256'].items()), 'Lint inputs changed')
    out = safe(out)
    require(out.drive.upper() == 'E:' and out.name.startswith('codex_pcb_operator_ui_' + BOARD + '_20261111_'), 'Fresh isolated operator UI E: build required')
    require(not out.exists(), 'Refusing existing build directory')
    tree, declared = project_inputs()
    files = support_files(ROOT)
    for _, _, path in declared:
        files[path.relative_to(ROOT).as_posix()] = path
    if BOARD == 'main':
        path = ROOT / MAIN_RUN / 'osd_compact_glyphs.vh'
        files[path.relative_to(ROOT).as_posix()] = path
    for filename in ['build_suspect_trial.py', 'suspect_trial_scope.json', 'build_doc_key1_confirm.py', 'signoff_doc_key1_confirm.py', 'doc_key1_confirm_strict_checks.py',
                     'td_release_audit.py', AUDIT_CONFIG]:
        files['tools/' + filename] = ROOT / 'tools' / filename
    for filename in ['validate_device_capacity.py', 'ph1_35p_device_dump.txt_chip',
                     'ph1_35p_device_dump.txt_connmngr', 'physical_device_resources.txt',
                     'DS1300_logic_and_dram_excerpt.txt']:
        files['tools/physical_capacity/' + filename] = ROOT / 'tools/physical_capacity' / filename
    out.mkdir()
    records = {}
    def record(dest, origin=None):
        records[dest.relative_to(out).as_posix()] = {'sha256': sha(dest), 'bytes': dest.stat().st_size,
                                                   'origin': str(origin) if origin else None}
    for relative, origin in sorted(files.items()):
        digest = sha(origin)
        dest = out / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(origin, dest)
        require(sha(dest) == digest == sha(origin), 'Source changed during freeze: ' + relative)
        record(dest, origin)
    run_dirs = [out / 'runs/syn_1', out / 'runs/phy_1'] if BOARD == 'secondary' else [out / MAIN_RUN]
    for directory in run_dirs:
        directory.mkdir(parents=True, exist_ok=True)
        write_project(tree, directory, out)
        for extension in ['al', 'prj']:
            record(directory / (NAME + '.' + extension), ROOT / PROJECT)
    for relative, digest in FLOWS.items():
        origin, dest = CONTROL / relative, out / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(origin, dest)
        require(sha(dest) == digest, 'Successful vendor flow copy drift')
        record(dest, origin)
    if BOARD == 'secondary':
        # ROM paths are relative to the .al directory; these are byte-identical
        # aliases of the frozen model, never an alternate set of model weights.
        for filename in ['weights.mem', 'biases.mem', 'quantization.json', 'MODEL_NEW_CAPTURE.json']:
            origin = out / 'model/experiments/conv4_4' / filename
            dest = out / 'runs/model/experiments/conv4_4' / filename
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(origin, dest)
            record(dest, origin)
    if BOARD == 'secondary':
        for origin in sorted((out/'model/suspect').glob('*')):
            if origin.is_file():
                dest=out/'runs/model/suspect'/origin.name
                dest.parent.mkdir(parents=True,exist_ok=True)
                shutil.copy2(origin,dest)
                record(dest,origin)
    spec = importlib.util.spec_from_file_location('preview_source_audit', out / 'tools/td_release_audit.py')
    audit = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(audit)
    snapshots = []
    for directory in run_dirs:
        result = audit.collect(argparse.Namespace(root=out, run=directory, name=NAME, al=None,
            config=out / 'tools' / AUDIT_CONFIG, extra=[]))
        put(directory / 'source_snapshot.json', result)
        record(directory / 'source_snapshot.json')
        snapshots.append({'run': str(directory), 'passed': result['passed'], 'errors': result['errors']})
    put(out / 'SOURCE_MANIFEST.json', {'files': records})
    plan = {'status': 'PREPARED_NOT_STARTED', 'board': BOARD, 'source_root': str(ROOT),
        'build_root': str(out), 'source_manifest_sha256': sha(out / 'SOURCE_MANIFEST.json'),
        'baseline': identity, 'snapshots': snapshots, 'limits_strict_less_than': LIMITS,
        'mapped_negative_wns_blocks_physical_exploration': False, 'bitgen_allowed': False,
        'hardware_status': 'NOT_RUN', 'frozen_utc': datetime.now(timezone.utc).isoformat()}
    put(out / 'BUILD_PLAN.json', plan)
    put(REPORT / 'BUILD_INDEX.json', {'run': str(out), 'plan_sha256': sha(out / 'BUILD_PLAN.json')})
    require(all(row['passed'] for row in snapshots), 'Source closure failed: ' + str(snapshots))
    print(json.dumps(plan, ensure_ascii=False, indent=2))


def validate(out):
    out = safe(out)
    plan = load(out / 'BUILD_PLAN.json')
    require(plan['board'] == BOARD and Path(plan['build_root']).resolve() == out, 'Wrong frozen build')
    require(sha(out / 'SOURCE_MANIFEST.json') == plan['source_manifest_sha256'], 'Frozen manifest drift')
    for relative, row in load(out / 'SOURCE_MANIFEST.json')['files'].items():
        require(sha(safe(out / relative, out)) == row['sha256'], 'Frozen input drift: ' + relative)
    require(all(row['passed'] for row in plan['snapshots']), 'Frozen closure failed')
    return out, plan


def metrics(directory, physical):
    resources, capacity, timing = {}, {}, {}
    area = directory / (NAME + ('_phy.area' if physical else '_gate.area'))
    if area.is_file():
        for match in re.finditer(r'^\s*#([A-Za-z_][A-Za-z_0-9 ]*?)\*?\s+(\d+)\s+out of\s+(\d+)\b', area.read_text(encoding='utf-8-sig', errors='replace'), re.M):
            key = re.sub(r'\s+', '_', match[1].strip().lower())
            used, total = int(match[2]), int(match[3])
            capacity[key] = {'used': used, 'total': total, 'percent': used * 100 / total if total else None}
            if key in LIMITS:
                resources[key] = capacity[key]
    path = directory / (NAME + ('_pr.timing' if physical else '_gate.timing'))
    text = path.read_text(encoding='utf-8-sig', errors='replace') if path.is_file() else ''
    for key in ['SWNS', 'STNS', 'HWNS', 'HTNS']:
        match = re.search(r'\b' + key + r':\s*([-+\d.]+)ns', text)
        if match:
            timing[key] = float(match[1])
    return {'resources': resources, 'reported_capacity': capacity, 'timing_ns': timing,
            'routed_two_corner': 'Routed' in text and 'Both (Slow and Fast)' in text}


def execute(phase, out):
    out, plan = validate(out)
    syn, phy = (out / 'runs/syn_1', out / 'runs/phy_1') if BOARD == 'secondary' else (out / MAIN_RUN, out / MAIN_RUN)
    if phase == 'place':
        review = load(out / 'SYNTHESIS_REVIEW.json')
        require(not review['illegal_logic_evidence'], 'Illegal inferred logic blocks place')
        rows = review['reported_capacity']
        require(set(LIMITS) <= set(rows) and all(0 <= x['used'] <= x['total'] and x['total'] > 0 for x in rows.values()), 'Mapped resources exceed physical capacity')
    prior = 'opt_gate' if phase == 'place' else 'opt_place'
    if phase != 'syn':
        require(((syn if phase == 'place' else phy) / ('.' + prior + '.end.f')).is_file(), 'Previous phase did not finish')
    directory = syn if phase == 'syn' else phy
    script = ('run.tcl' if phase == 'syn' else 'run_' + phase + '.tcl') if BOARD == 'secondary' else 'run_display_noise_' + ('synth' if phase == 'syn' else phase) + '.tcl'
    log = out / 'logs' / (phase + '.log')
    require(not log.exists(), 'Refusing to overwrite tool evidence')
    log.parent.mkdir(exist_ok=True)
    receipt = {'status': 'RUNNING', 'phase': phase, 'cwd': str(directory), 'script_sha256': sha(directory / script),
               'command': [str(TD), script], 'source_manifest_sha256': plan['source_manifest_sha256']}
    put(log.with_suffix('.json'), receipt)
    with log.open('xb') as stream:
        cp = subprocess.run([str(TD), script], cwd=directory, stdout=stream, stderr=subprocess.STDOUT)
    text = log.read_text(encoding='utf-8-sig', errors='replace')
    errors = re.findall(r'(?m)^.*(?:[A-Z]+-\d+\s+(?:ERROR|FATAL)|\*\*\s+(?:Error|Fatal):|BUILD_FAILED|MAPPING_ERROR).*$', text)
    error_markers = [str(p) for p in directory.glob('.*.error.f')]
    marker = {'syn': 'opt_gate', 'place': 'opt_place', 'route': 'opt_route'}[phase]
    database = directory / (NAME + {'syn': '_gate.db', 'place': '_place.db', 'route': '_pr.db'}[phase])
    passed = cp.returncode == 0 and not errors and not error_markers and (directory / ('.' + marker + '.end.f')).is_file() and database.is_file()
    receipt.update(status='PASS_TOOL_INVOCATION' if passed else 'FAILED_TOOL_INVOCATION',
                   exit_code=cp.returncode, log_sha256=sha(log), errors=errors, error_markers=error_markers)
    put(log.with_suffix('.json'), receipt)
    result = metrics(directory, phase != 'syn')
    result.update(source_manifest_sha256=plan['source_manifest_sha256'], bitgen_allowed=False, hardware_status='NOT_RUN', tool_pass=passed)
    if phase == 'syn':
        result['illegal_logic_evidence'] = [s for s in text.splitlines() if re.search(r'SYN-5033|unstable comb insts loops|TMR-250[79].*combinational loop|inferred latch', s, re.I)]
    if phase == 'route':
        database = phy / (NAME + '_pr.db')
        result['routed_database_sha256'] = sha(database) if database.is_file() else None
        t = result['timing_ns']
        result['final_timing_pass'] = set(t) == {'SWNS', 'STNS', 'HWNS', 'HTNS'} and t['SWNS'] >= 0 and t['HWNS'] >= 0 and t['STNS'] == t['HTNS'] == 0
        r = result['resources']
        result['final_resource_pass'] = set(r) == set(LIMITS) and all(r[k]['used'] * 100 < r[k]['total'] * LIMITS[k] for k in LIMITS)
    filename = {'syn': 'SYNTHESIS_REVIEW.json', 'place': 'PLACE_REVIEW.json', 'route': 'ROUTE_REVIEW.json'}[phase]
    put(out / filename, result)
    put(REPORT / filename, result)
    validate(out)
    require(passed, 'TD phase failed; retain current logs/reports: ' + str(log))
    print(json.dumps(result, ensure_ascii=False, indent=2))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=['scope', 'lint', 'prepare', 'inspect', 'syn', 'place', 'route'])
    p.add_argument('--run', type=Path, default=DEFAULT_RUN)
    args = p.parse_args()
    if args.action == 'scope':
        result = baseline_identity()
        put(REPORT / 'BASELINE_SCOPE.json', result)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    elif args.action == 'lint':
        lint()
    elif args.action == 'prepare':
        prepare(args.run)
    elif args.action == 'inspect':
        out, plan = validate(args.run)
        print(json.dumps({'status': 'FROZEN_INPUTS_PASS', 'build': str(out), 'manifest_sha256': plan['source_manifest_sha256']}))
    else:
        execute(args.action, args.run)


if __name__ == '__main__':
    main()
