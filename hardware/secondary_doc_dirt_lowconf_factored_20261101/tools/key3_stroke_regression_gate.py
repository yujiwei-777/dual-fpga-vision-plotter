"""Read-only fail-closed regression gate for the KEY3/stroke/CNN release.

check(files, required=None) returns {project-relative RESULTS path: SHA256}.
Only the seven named fresh release suites are accepted. Historical kernel
evidence is checked as explicitly imported evidence, never as fresh simulation.
Most legacy runners do not persist process exit codes; their exact pinned bytes
reject nonzero subprocess exit before publishing PASS. Those contracts plus
complete clean simulator logs are verified, and this limitation is reported.
"""
from __future__ import annotations

import copy
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
SUITES = frozenset(('cnn_named_top', 'key3_top_reset_release', 'stroke_release',
                    'cnn_named_pcb', 'cnn_area_pipeline_compact', 'cnn_stability_core', 'cnn_named_report'))
RUNNERS = {
 'cnn_named_top': ('run_cnn_top_regression.py', 'B3A82B8D54A11DE419D532789A80016CEE4EB1ACDBAA844ACAB708E8DEF75EF8'),
 'key3_top_reset_release': ('run_key3_top_reset.py', '0345C30600CEE927A5358AE1061593F4F32BF5ABA29EE5714408A019EC3B7AEE'),
 'stroke_release': ('run_stroke_split_regression.py', '69BC73E3DCC627E2B724B09E1FD4CEC3B31D17127C7591533F953427CE91A74B'),
 'cnn_named_pcb': ('run_cnn_named_pcb_regression.py', '28BF9DDF778D2FE796A2CDC22DCC93BD06A107F666F2BAC593F7E17EF7CF6CE1'),
 'cnn_area_pipeline_compact': ('run_cnn_area_pipeline_compact.py', '6DF6DDF36EE3E5AB79B6691D521C294B62478600ADDDEB9387C3A18818C4CC19'),
 'cnn_stability_core': ('run_cnn_stability_core.py', '77BD0601C5217473304A7D013AD16C49B3029D5D93C4F6DF6CEF0C21D5D92757'),
 'cnn_named_report': ('run_cnn_named_report_regression.py', '28222B11A1290CA7D30A4F1140EEA8BCECDB3729259585CAA7EF41DACA0574FE'),
}
PINS = {
 '01_rtl/vision_pipeline.v': '6D9B376A6FCEA579A8DF96845C80F162FD973A99ED9BDD9A015A9A48CE84A6E9',
 '01_rtl/cnn_result_stabilizer.v': '9C946B4DDBA2E0BE3CE917E172EAF6775095349E19A28B95D4300A5596157128',
 '01_rtl/secondary_top.v': '64176506920BFF546415A1D1433FE1F6558FAAA565B5845FA826B56566694DCA',
 '01_rtl/doc_stroke_planner.v': '1C6AB2F04D6B8CDC0EDAAA6D275A3BCDA314985B5F219BD3EA0A5846518F4CB6',
 '01_rtl/doc_copy_pipeline.v': '4780D3863ABE4BF0D261445209F914D2636B842E6C1DE23E7987647BAD56E330',
 '01_rtl/doc_path_distance.v': '265774F97B39989FF199B8D288F892E364AB2B38076C1384025430624FB67174',
 'model/doc_stroke_reference.py': 'CDBF0169E7698678FC62BA23E07603E3586427FE09D800009A7B6BB91C295A92',
 'model/export/weights.mem': '82FB0381424A047600E862FD0BBF55D6B23BCF347BE19F1074A9CD32847058DE',
 'model/export/biases.mem': '79A3DAA7C5F3E17A2D5882FC89EEAD2AEBE153420B8D02E001655BCB23740A98',
 'model/export/quantization.json': '350F95277AD107C95FF163F0C297665EEEC14F85A03BB97E50CAA83158BC0450',
 'model/experiments/conv4_4/weights.mem': '9B844CB0B0844F8A72E59192B4F04D3C192B6C1A501DA1F3376CE6BF5354DDE6',
 'model/experiments/conv4_4/biases.mem': '45FAC7544E47F2CD73A5571A6136CB57A82CADD1B130057C8FCB0BC647E51232',
}
SCOPE = {
 'cnn_named_top': {'01_rtl/secondary_top.v','01_rtl/vision_pipeline.v','01_rtl/cnn_result_stabilizer.v',
    '01_rtl/doc_stroke_planner.v','01_rtl/secondary_ddr_wrapper.v','shared/rtl/hxa_secondary_link.v','lint_full.f'},
 'key3_top_reset_release': {'01_rtl/secondary_top.v','01_rtl/grbl_uart.v','01_rtl/grbl_reporter.v',
    'shared/rtl/hxa_secondary_link.v','main/user_source/hdl_source/reset_sync.v','lint_full.f'},
 'stroke_release': {'01_rtl/doc_stroke_planner.v','01_rtl/doc_copy_pipeline.v','01_rtl/doc_stroke_bram.v','01_rtl/doc_machine_map.v',
    '01_rtl/doc_path_distance.v','01_rtl/doc_grbl_plotter.v','01_rtl/doc_grbl_map.v','01_rtl/doc_grbl_streamer.v',
    '01_rtl/doc_grbl_response_parser.v','01_rtl/grbl_line_formatter.v','model/doc_stroke_reference.py'},
 'cnn_named_pcb': {'01_rtl/vision_pipeline.v','01_rtl/pcb_fullboard_spatial96.v','01_rtl/vision_workspace.v',
    '01_rtl/vision_shared_mac.v','model/experiments/conv4_4/weights.mem','model/experiments/conv4_4/biases.mem'},
 'cnn_area_pipeline_compact': {'01_rtl/vision_pipeline.v','01_rtl/cnn_result_stabilizer.v','01_rtl/secondary_top.v','01_rtl/cnn_core.v'},
 'cnn_stability_core': {'01_rtl/cnn_core.v','01_rtl/vision_workspace.v','01_rtl/vision_shared_mac.v',
    'model/export/weights.mem','model/export/biases.mem','model/export/quantization.json'},
 'cnn_named_report': {'01_rtl/grbl_reporter.v','01_rtl/grbl_line_formatter.v','01_rtl/grbl_vector_font_rom.v',
    '01_rtl/grbl_streamer.v','01_rtl/grbl_response_parser.v','tools/cnn_named_report_reference.py'},
}
LAST_AUDIT = None
_CONSUMED = {}
COMPACT_METRIC_RUNNER_SHA = '301A7C5959A60B7428468ABBB6AB9FEFE8116DDD0749A6389EB55AD2D17076EA'
COMPACT_METRIC_MARKERS = {
 'finite_bound': (
    'PASS METRIC_FINITE_BOUND checks=13 rejects=3 bound=23164 distance_bits=15 pair_bits=16 route_bits=26',
    'PASS METRIC_PUBLIC_CYCLE_MITER cycles=32 public_ports=23 ram_signals=20'),
 'generic32': (
    'PASS METRIC_GENERIC32 checks=80 rejects=0 high_value_captures=72 modulo32_cases=6 output64_cases=2',
    'PASS METRIC_PUBLIC_CYCLE_MITER cycles=239 public_ports=23 ram_signals=20'),
}


def _require(condition, message):
    if not condition:
        raise AssertionError(message)


def _hash(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def _mtime(path):
    return Path(path).stat().st_mtime_ns


def _json(path):
    return json.loads(_local(path).read_text(encoding='utf-8-sig'))


def _local(value, base=ROOT):
    path = Path(value)
    if not path.is_absolute():
        path = base / path
    path = path.resolve()
    _require(path.is_relative_to(ROOT), 'Evidence escapes independent release: ' + str(path))
    _require(path.is_file(), 'Missing evidence: ' + str(path))
    _CONSUMED[path] = _hash(path)
    return path


def _digest(path, expected):
    path = _local(path)
    _require(isinstance(expected,str) and re.fullmatch('[0-9A-Fa-f]{64}',expected), 'Invalid SHA256 value')
    _require(_hash(path) == expected.upper(), 'SHA256 mismatch: ' + str(path))


def _hash_maps(path, data):
    inputs, evidence = {}, {}
    for alias in ('input_hashes','input_sha256','inputs_sha256'):
        values = data.get(alias)
        if values is None:
            continue
        _require(isinstance(values,dict) and values, 'Invalid input hash map ' + alias)
        for name,value in values.items():
            source = _local(name)
            _digest(source,value)
            _require(source not in inputs or inputs[source] == value.upper(), 'Conflicting hash aliases')
            inputs[source] = value.upper()
    _require(inputs, 'RESULTS lacks input hashes: ' + str(path))
    hashes = data.get('evidence_hashes',{})
    _require(isinstance(hashes,dict), 'Invalid evidence map')
    for name,value in hashes.items():
        _require(not Path(name).is_absolute(), 'Evidence hash key must be relative')
        source = _local(name,path.parent)
        _require(source.is_relative_to(path.parent), 'Evidence escapes suite')
        _digest(source,value)
        evidence[source] = value.upper()
    latest = max(_mtime(p) for p in {*inputs,*evidence})
    _require(_mtime(path) >= latest, 'RESULTS predates current input/evidence: ' + str(path))
    return inputs,evidence


def _runner(name, inputs):
    file,digest = RUNNERS[name]
    path = ROOT/'tools'/file
    _require(path in inputs, 'Suite does not bind canonical runner: ' + name)
    _digest(path,digest)
    text = path.read_text()
    _require('.returncode' in text and ('raise ' in text or 'assert ' in text), 'Missing fail-closed process exit contract')
    _require("'-batch'" in text or '"-batch"' in text, 'Interactive simulator launch is prohibited')
    return ('persisted_command_rc_zero' if name in {'stroke_release','cnn_area_pipeline_compact'}
            else 'pinned_runner_rejects_nonzero_rc_before_PASS')


def _log(directory, name, inputs, result, marker=None, compile=False):
    path = _local(name,directory)
    text = path.read_text(errors='replace')
    _require(not re.search(r'\*\*\s+(?:Error|Fatal):|\bErrors:\s*[1-9]|^#?\s*FAIL\b|GET / HTTP|bad header|vish.*cleanup',text,re.M|re.I),
             'Failure/abnormal simulator termination: ' + str(path))
    _require(re.search(r'(?:^|\n)#?\s*Errors: 0, Warnings: \d+\s*$',text), 'Missing clean terminal simulator summary: ' + str(path))
    if compile:
        _require(re.search(r'Errors: 0, Warnings: 0\s*$',text), 'Compile/lint warnings: ' + str(path))
    if marker is not None:
        matches = [line.lstrip('# ').strip() for line in text.splitlines()]
        _require(matches.count(marker) == 1, 'Missing/duplicate exact PASS marker ' + marker)
    # Only current production inputs are shared across all stages. Test-only
    # inputs generated for a later stage must not make earlier logs look stale.
    production = [p for p in inputs if p.is_relative_to(ROOT/'01_rtl') or p.is_relative_to(ROOT/'shared')
                  or p.is_relative_to(ROOT/'main') or p.is_relative_to(ROOT/'model') or p.is_relative_to(ROOT/'tools')]
    _require(_mtime(path) >= max((_mtime(p) for p in production),default=0), 'Log predates production source/runner: ' + str(path))
    _require(_mtime(result) >= _mtime(path), 'RESULTS predates simulator log: ' + str(path))
    return text


def compact_metric_gate():
    """Mandatory fresh current combined-planner proof, separate from 7 suites.

    Every consumed local input/output joins the same evidence closure used by
    the release builder. External origins are checked only as provenance; all
    compiled sources and testbenches must be true copies inside the new root.
    """
    directory = ROOT/'02_sim/compact_metric_boundaries'
    result = directory/'RESULTS.json'
    data = _json(result)
    _require(data.get('status') == 'PASS_FRESH_COMBINED_METRIC_BOUNDARIES' and
        data.get('hardware_status') == 'NOT_RUN', 'Combined metric boundary test did not pass')
    _require(data.get('planner_sha256') == PINS['01_rtl/doc_stroke_planner.v'],
        'Metric boundary test does not bind current production planner')
    inputs,evidence = _hash_maps(result,data)
    expected_inputs = {ROOT/path for path in (
        '01_rtl/doc_stroke_planner.v', '01_rtl/doc_stroke_bram.v',
        '01_rtl/doc_path_distance.v', '01_rtl/doc_copy_pipeline.v',
        'tools/run_compact_metric_boundaries.py')}
    expected_inputs.update(directory/path for path in (
        'doc_stroke_planner_baseline.v','finite_bound/tb_metric_directed.sv','generic32/tb_metric_directed.sv'))
    _require(set(inputs) == expected_inputs, 'Combined metric input closure differs')
    runner = ROOT/'tools/run_compact_metric_boundaries.py'
    _digest(runner,COMPACT_METRIC_RUNNER_SHA)
    for relative in ('01_rtl/doc_stroke_planner.v','01_rtl/doc_copy_pipeline.v','01_rtl/doc_path_distance.v'):
        _digest(ROOT/relative,PINS[relative])
    provenance = {
        ROOT.parent/'secondary_cnn_key3_stroke_release_20261031/01_rtl/doc_stroke_planner.v':
            'DB552C7E3619108DACF894232696B95A573AE194C44E2B6439A744705597E204',
        ROOT.parent/'secondary_doc_metric_bound_scratch_20261031/functional_metric/02_sim/directed_metrics/finite_bound/tb_metric_directed.sv':
            '165178A87D3F9FA162157207A7E70FB1D17D22E3538A1BC652C01938F8993473',
        ROOT.parent/'secondary_doc_metric_bound_scratch_20261031/functional_metric/02_sim/directed_metrics/generic32/tb_metric_directed.sv':
            '1CC83F7270F084310165D832415CD27FD5686DEC5C5D0A48616BA35F54DB4370',
    }
    recorded = data.get('origin_hashes',{})
    _require({Path(path).resolve():digest.upper() for path,digest in recorded.items()} ==
             {path.resolve():digest for path,digest in provenance.items()}, 'Metric origin identity differs')
    for path,digest in provenance.items():
        _require(path.is_file() and path.resolve().is_relative_to(ROOT.parent) and
            'work' not in {part.lower() for part in path.resolve().parts} and _hash(path) == digest,
            'Metric origin source drift: '+str(path))
    original = next(path for path in provenance if path.name == 'doc_stroke_planner.v').read_text()
    _require(original.count('module doc_stroke_planner #(') == 1 and
        (directory/'doc_stroke_planner_baseline.v').read_text() == original.replace(
            'module doc_stroke_planner #(','module doc_stroke_planner_baseline #('),
        'Metric reference is not exactly the frozen release with module rename')
    _require(set(data.get('tests',{})) == set(COMPACT_METRIC_MARKERS), 'Metric boundary coverage missing')
    expected_evidence = {'doc_stroke_planner_baseline.v'}
    for name,markers in COMPACT_METRIC_MARKERS.items():
        case = directory/name
        _require(data['tests'][name] == {'status':'PASS','checks':list(markers)}, 'Metric exact coverage changed')
        origin = next(path for path in provenance if path.parent.name == name)
        _digest(case/'tb_metric_directed.sv',provenance[origin])
        expected_evidence.add(name+'/tb_metric_directed.sv')
        for phase,executable in (('vlib','vlib.exe'),('compile','vlog.exe'),('simulate','vsim.exe')):
            expected_evidence.update((name+'/'+phase+'.log',name+'/'+phase+'_command.json'))
            metadata_path = case/(phase+'_command.json')
            metadata = _json(metadata_path)
            _require(metadata.get('returncode') == 0, 'Metric persisted command failed: '+name+'/'+phase)
            logfile = _local(phase+'.log',case)
            _digest(logfile,metadata.get('log_sha256'))
            _require(_mtime(result)>=_mtime(metadata_path)>=_mtime(logfile), 'Metric evidence chronology differs')
            command = metadata.get('command',[])
            _require(command and Path(command[0]).name.lower() == executable, 'Metric unexpected executable')
            if phase == 'compile':
                _require('-sv' in command and '-lint' in command and '+define+DOC_BEHAVIORAL_RAM' in command,
                    'Metric compile/lint contract changed')
                required_sources = {ROOT/'01_rtl/doc_stroke_planner.v',directory/'doc_stroke_planner_baseline.v',
                    ROOT/'01_rtl/doc_stroke_bram.v',ROOT/'01_rtl/doc_path_distance.v',case/'tb_metric_directed.sv'}
                _require({Path(arg).resolve() for arg in command if str(arg).endswith(('.v','.sv'))} ==
                    {path.resolve() for path in required_sources}, 'Metric compile sources differ')
                _log(case,'compile.log',inputs,result,compile=True)
            elif phase == 'simulate':
                _require('-batch' in command and 'onerror {quit -code 1}; run -all; quit -f' in command,
                    'Metric simulator completion contract changed')
                for marker in markers:
                    _log(case,'simulate.log',inputs,result,marker)
    _require(set(data.get('evidence_hashes',{})) == expected_evidence, 'Metric output evidence closure differs')
    return {'status':'PASS_FRESH_CURRENT_COMBINED_METRIC_PROOF',
        'result':result.relative_to(ROOT).as_posix(),'result_sha256':_hash(result),
        'runner_sha256':COMPACT_METRIC_RUNNER_SHA,'planner_sha256':data['planner_sha256'],
        'origin_sha256':recorded,'cases':data['tests'],'hardware_status':'NOT_RUN'}


def compact_metric_evidence_manifest():
    global _CONSUMED
    _CONSUMED={}
    compact_metric_gate()
    return {path.relative_to(ROOT).as_posix():digest for path,digest in sorted(_CONSUMED.items())}


def _area_modes():
    params=((1,0,1),(2,1,2),(3,2,3),(4,0,4),(15,15,15))
    modes=[(bits,0,coord,reader,(3,2,3),'generic_vectors.txt')
           for bits in (20,22,24,32) for reader in (0,1) for coord in (0,3)]
    for reader in (0,1):
        for setting in params:
            value=(32,0,0,reader,setting,'generic_vectors.txt')
            if value not in modes:
                modes.append(value)
    modes.extend((22,6,3,reader,setting,'aligned_a22_s6.txt') for reader in (0,1) for setting in params)
    modes.extend((bits,shift,0,reader,(3,2,3),f'aligned_a{bits}_s{shift}.txt')
                 for bits,shift in ((20,1),(20,19),(32,31)) for reader in (0,1))
    _require(len(modes)==40 and len(set(modes))==40,'Internal compact configuration contract changed')
    return params,modes


def _area_command(directory,label,executable,args,inputs,result,marker=None,compile=False):
    """Validate persisted fresh command, sources, exit code and complete log."""
    metadata_path=directory/(label+'_command.json')
    metadata=_json(metadata_path)
    _require(metadata.get('returncode')==0 and metadata.get('exception') is None,
             'Compact fresh command did not exit successfully: '+str(metadata_path))
    command=metadata.get('command',[])
    _require(isinstance(command,list) and command and metadata.get('args')==command,
             'Compact persisted command/args mismatch')
    if executable=='python':
        _require(Path(command[0]).resolve()==Path(sys.executable).resolve(),'Unexpected domain Python executable')
    else:
        _require(Path(command[0]).resolve()==Path('E:/model/win64',executable).resolve(),
                 'Unexpected compact simulator executable')
    _require(command[1:]==[str(value) for value in args],
             'Compact command does not use exact current-root inputs: '+str(metadata_path))
    _require(metadata.get('runner_sha256')==RUNNERS['cnn_area_pipeline_compact'][1] and
        metadata.get('production_kernel_sha256')==PINS['01_rtl/cnn_result_stabilizer.v'] and
        metadata.get('production_pipeline_sha256')==PINS['01_rtl/vision_pipeline.v'],
        'Compact command production/runner identity mismatch')
    for variable in ('MGLS_LICENSE_FILE','LM_LICENSE_FILE'):
        _require(metadata.get(variable)=='E:/model/win64/LICENSE.TXT','Compact file license environment mismatch')
    started=datetime.fromisoformat(metadata['started_utc'])
    completed=datetime.fromisoformat(metadata['completed_utc'])
    whole=_json(result)
    _require(datetime.fromisoformat(whole['started_utc'])<=started<=completed<=
        datetime.fromisoformat(whole['completed_utc']),'Compact command timestamps escape fresh suite')
    logfile=_local(label+'.log',directory)
    _digest(logfile,metadata.get('log_sha256'))
    _require(_mtime(result)>=_mtime(metadata_path)>=_mtime(logfile),'Compact command chronology mismatch')
    if executable in {'vlog.exe','vsim.exe'}:
        text=_log(directory,label+'.log',inputs,result,marker,compile)
        warnings=[line for line in text.splitlines() if re.search(r'\*\*\s+Warning:',line)]
        _require(all(re.search(r'\*\* Warning: \((?:vsim|vlog)-8891\)',line) for line in warnings),
                 'Unexpected compact simulator warning')
    elif executable=='python':
        recorded=json.loads(logfile.read_text())
        _require(recorded.get('status')=='PASS_SOURCE_DERIVATION_AND_FINITE_INTEGER_CHECKS' and
            recorded.get('proof_sha256')==_hash(directory/'AREA_DOMAIN_PROOF.json'),
            'Compact fresh domain process did not publish the bound proof')


def _area_sim(directory,top,label,params,inputs,result,marker):
    _area_command(directory,label,'vsim.exe',['-batch','-syncio','-quiet','-novopt','-suppress','12110',
        '-lib','simlib',top,*params,'-do','onerror {quit -code 1}; run -all; quit -f'],inputs,result,marker)


def _area_compile(directory,sources,inputs,result):
    _area_command(directory,'vlib','vlib.exe',['simlib'],inputs,result)
    _require(all(path in inputs for path in sources),'Compact compile source missing from current input closure')
    _area_command(directory,'compile','vlog.exe',['-sv','-lint','-work','simlib',*sources],inputs,result,compile=True)


def _area_origins(directory,inputs):
    reference='8655EB872B8FD09C002FAD93331953F298BEEDA35A2FFFDCFBC9903AE5625B0C'
    imported=_json(directory/'ORIGIN_IMPORT.json')
    _require(imported.get('status')=='PASS' and imported.get('fresh') is False and
        'same_kernel_as_production' not in imported and imported.get('forty_mode_miter')==40 and
        imported.get('ten_mode_lifecycle')==10 and imported.get('aggregate_aborts')==560,
        'Imported provenance is not clearly separated from fresh production evidence')
    for key,value in {'historical_candidate_sha256':PINS['01_rtl/cnn_result_stabilizer.v'],
        'historical_reference_sha256':reference,'production_kernel_sha256':PINS['01_rtl/cnn_result_stabilizer.v'],
        'reference_kernel_sha256':reference}.items():
        _require(imported.get(key)==value,'Imported kernel chain identity mismatch: '+key)
    _require(imported.get('chain')==[
        'R11 kernel to area-grid 8655 reference: imported original area/domain evidence',
        '8655 reference to metadata-flat 9C946: imported previous fresh exact-cycle evidence',
        'Current compact production 9C946 vs frozen 8655: fresh suites run separately below'],
        'Imported reference-to-production chain changed')
    copies=imported.get('copies',{})
    _require(isinstance(copies,dict) and copies,'Missing imported byte-copy provenance')
    for relative,item in copies.items():
        local=_local(relative,directory)
        _require(local.is_relative_to(directory) and local in inputs,'Imported copy omitted from input closure')
        _digest(local,item['sha256'])
        source=Path(item['source']).resolve()
        _require(source.is_relative_to(ROOT.parent) and not source.is_relative_to(ROOT) and
            'work' not in {part.lower() for part in source.parts} and source.is_file() and
            _hash(source)==item['sha256'],'Imported historical source drift: '+str(source))
    oldroot=directory/'imported_metadata_functional'
    for name,digest in {
        'RESULTS.json':'50A3FF531E8EEE7227296BA8353F8937BB5C4A23B05D527DFB01243CD0F66247',
        'QUICK_RESULTS.json':'3D9AAD17842E4F10948172AF0EFEE9386963713222BFED530B9F72858E0127D6',
        'PREPARATION.json':'86452D333245213B0CB51B44EBBEC1C6100F4645DC442806C8C6BA099155BC80',
        'FINAL_AUDIT.json':'F9B6F138173D16F8060C9D011B99A60C5A971FA05B51FCE57EC1681F5AF12AAA',
        'run_regression.py':'54DE43B460E5488FD8123EA28C008B15676E232689372F612C0D8937552F6316',
    }.items():
        _digest(oldroot/name,digest)
    old=_json(oldroot/'RESULTS.json')
    _require(old.get('status')=='PASS_SCRATCH_RTL_EXACT_CYCLE' and
        old.get('candidate_sha256')==PINS['01_rtl/cnn_result_stabilizer.v'] and
        old.get('source_kernel_sha256')==reference and len(old.get('generic_miter_modes',[]))==40 and
        len(old.get('lifecycle_modes',[]))==10 and old.get('aggregate_state_aborts')==560,
        'Frozen reference equivalence coverage/identities changed')
    for result_name in ('RESULTS.json','QUICK_RESULTS.json'):
        for name,digest in _json(oldroot/result_name)['evidence_sha256'].items():
            _digest(oldroot/name,digest)
    origin=directory/'origin'
    _digest(origin/'cnn_result_stabilizer_reference.v',reference)
    _digest(origin/'cnn_result_stabilizer_baseline.v','5EB86B41BE952A4948A50EE17E8DB83EA8A892C7E05365AC8F525BE4D11B10C5')
    _require((origin/'cnn_result_stabilizer_baseline.v').read_text()==
        (origin/'cnn_result_stabilizer_reference.v').read_text().replace(
            'module cnn_result_stabilizer #(','module cnn_result_stabilizer_baseline #('),
        'Fresh frozen reference has nonrename edits')
    _digest(origin/'cnn_result_stabilizer_r11.v','8D44203B9395F92441F09BD856AD77F4A4695343DD4D58AFB544C03DD2819D36')
    _digest(origin/'vision_pipeline_r11.v','C7B43FE8727F1145C2EF060CE9DC464029AF74CB4BD372DF10E1395E5D878413')
    _digest(origin/'reference_trace.jsonl','04E7AB74BCF2A5DC0D2801F9880639EA2F60C05A98954E45761BD8A82F91FADE')
    return old,reference


def _area_contract(directory,data,inputs,result):
    old,reference=_area_origins(directory,inputs)
    _require(data.get('hardware_status')=='NOT_RUN' and data.get('production_modified') is False and
        data.get('td_run') is False and data.get('imported_evidence')=='ORIGIN_IMPORT.json' and
        data.get('reference_kernel_sha256')==reference,'Compact suite identity/scope changed')
    expected = dict(cycles=11742298,public_ports=37,controls=11,completed_jobs=113,assertions=527)
    miter = data.get('pipeline_miter',{})
    _require(miter.get('status')=='PASS' and miter.get('fresh') is True and miter.get('coverage')==expected,
             'Production pipeline cycle-miter coverage changed')
    _require(miter.get('original_program')=={'jobs':81,'assertions':374}, 'Original integration coverage missing')
    _require(miter.get('compared_kernels')=={'reference':reference,
                'production':PINS['01_rtl/cnn_result_stabilizer.v']}, 'Miter uses different kernel')
    _require(data.get('production_pipeline_sha256')==PINS['01_rtl/vision_pipeline.v'] and
             data.get('production_kernel_sha256')==PINS['01_rtl/cnn_result_stabilizer.v'], 'Production identity missing')
    md = directory/'pipeline_miter'
    pipeline,kernel=ROOT/'01_rtl/vision_pipeline.v',ROOT/'01_rtl/cnn_result_stabilizer.v'
    _require(miter.get('production_compiled_directly')==[str(pipeline),str(kernel)],
        'Fresh pipeline miter does not bind direct current production paths')
    _area_compile(md,[md/'pipeline_leaf_stubs.sv',md/'vision_pipeline_baseline.v',
        directory/'origin/cnn_result_stabilizer_baseline.v',pipeline,kernel,md/'tb_fixed_grid_mapping_miter.sv'],inputs,result)
    _area_sim(md,'tb_cnn_stability_pipeline','simulate',[],inputs,result,
        'PASS FIXED_GRID_PUBLIC_CYCLE_MITER cycles=11742298 public_ports=37 controls=11 completed_jobs=113 assertions=527')
    text=(md/'simulate.log').read_text()
    _require(text.count('PASS ORIGINAL_81_JOBS_374_ASSERTIONS_PRESERVED')==1 and
             text.count('PASS CNN_STABILITY_PIPELINE_ALL checks=527 jobs=113')==1, 'Original/full PASS guard missing')
    bench = _local('tb_fixed_grid_mapping_miter.sv',md)
    _digest(bench,'98A159C7E02713647ADCDF99215B5E69CE7499137B078A66F0A6351AB529E26A')
    _require(bench in inputs and 'if(completions!=81||checks!=374)' in bench.read_text(), 'Original bench guard missing')
    monitors='''word_req byte_addr busy done result_job_id config_version color_id shape_id confidence valid
        x0 x1 y0 y1 area pcb_checked pcb_good pcb_status defect_count defect_boxes defect_kinds multi_count
        multi_boxes multi_flags teach_success teach_failed teach_code teach_commit taught_station_header
        ext_reader_request ext_reader_invalidate ext_pixel_x ext_pixel_y yolo_pixel_valid yolo_pixel_rgb
        yolo_pixel_last color_word_active state box_index box_total sample_index purpose_q map_bits_left
        area_bits_left map_job raw_slot_order insert_physical_slot stable_raw_released'''.split()
    _require(len(monitors)==48,'Monitor list changed')
    for name in monitors:
        _require(bench.read_text().count('CYCLE_MITER '+name+' cycle=')==1, 'Miter monitor removed')
    _digest(md/'pipeline_leaf_stubs.sv','B19E7BDF866824235C6B89DC78E4A3FCD41C48FD0EE4C29FFA8ADFCF89AEAAA2')
    _digest(md/'vision_pipeline_baseline.v','7876918A9EA2347E2E1791DCA47A30004462F8B536EECF81B3780BB8EE1233C3')
    _require((md/'vision_pipeline_baseline.v').read_text()==pipeline.read_text().replace(
        'module vision_pipeline #(','module vision_pipeline_baseline #(').replace(
        '        cnn_result_stabilizer #(','        cnn_result_stabilizer_baseline #('),
        'Fresh reference pipeline includes nonrename edits')
    # Provenance binds the specialization to the current pipeline data flow.
    domain=data.get('domain',{})
    coverage=domain.get('coverage',{})
    _require(domain.get('status')=='PASS' and domain.get('fresh') is True and
             domain.get('source_pipeline_sha256')==PINS['01_rtl/vision_pipeline.v'] and
             domain.get('source_kernel_sha256')==PINS['01_rtl/cnn_result_stabilizer.v'] and
             domain.get('reference_kernel_sha256')==reference, 'Domain proof source binding missing')
    for key,value in {'code_domain_size':65536,'strict_adjacent_order_checks':65535,'allowed_bit_mask':'003FFFC0',
        'forbidden_bit_mask':'FFC0003F','encoded_area_min':0,'encoded_area_max':4194240,
        'encoded_area_sha256':'EDBE990A0F5F56B2B696AEFD06F01EF25C58CB248D188EE13FFA46885AF4B164',
        'raw_replay_frames':1170,'raw_replay_boxes':1223}.items():
        _require(coverage.get(key)==value, 'Area domain coverage changed: '+key)
    proof=_json(directory/'domain/AREA_DOMAIN_PROOF.json')
    _require(proof.get('status')=='PASS_SOURCE_DERIVATION_AND_FINITE_INTEGER_CHECKS' and
             proof.get('integer_checks')==coverage and proof.get('pcb_cannot_reach_stabilizer_in_same_transaction') is True,
             'Domain proof content mismatch')
    _require(proof.get('fixed_area_assignments')==['0','selected_area'], 'Area assignment invariant changed')
    _require(str(ROOT/'01_rtl/vision_pipeline.v') in proof['input_hashes'], 'Domain proof does not bind current source')
    for name,value in proof['input_hashes'].items():
        _digest(_local(name),value)
    domain_script=directory/'domain/prove_compact_area_domain.py'
    _digest(domain_script,'316487DCED53A37E6502746903F7F29A00C2F29A83BF44E0B61D2B803C47DF45')
    _require({Path(name).resolve() for name in proof['input_hashes']}==
        {pipeline,kernel,directory/'origin/cnn_result_stabilizer_r11.v',domain_script},
        'Current source/domain proof input closure changed')
    _area_command(directory/'domain','prove_domain','python',[domain_script],inputs,result)
    golden=data.get('kernel_reference',{})
    _require(golden.get('status')=='PASS' and golden.get('fresh_rtl_replay') is True and golden.get('checks')==
        dict(gold_checks=3240,events=3307,serial_records=2059,bank_reuses=3247,clear_boundaries=2,max_cycles=857),
        'Kernel integer replay coverage changed')
    gold_dir=directory/'kernel_reference'
    _area_compile(gold_dir,[kernel,gold_dir/'tb_cnn_stability_serial.sv'],inputs,result)
    _area_sim(gold_dir,'tb_cnn_stability_serial','simulate',[],inputs,result,
         'PASS SERIAL_GOLD checks=3240 vectors=3307 emitted=2059 bank_reuses=3247 clear_boundaries=2 max_latency_cycles=857')
    params,modes=_area_modes()
    for name,count in (('kernel_configurations',40),('kernel_lifecycle',10)):
        value=data.get(name,{})
        _require(value.get('status')=='PASS' and value.get('fresh_rtl_replay') is True and
            value.get('mode_count')==count and len(value.get('modes',[]))==count and
            value.get('production_kernel_sha256')==PINS['01_rtl/cnn_result_stabilizer.v'] and
            value.get('reference_kernel_sha256')==reference,'Compact fresh mode coverage missing: '+name)
        _require(_json(directory/name/'RESULTS.json')==value,'Compact per-stage result mismatch: '+name)
        bench_name='tb_area_grid_equivalence.sv' if count==40 else 'tb_combined_state_lifecycle.sv'
        _area_compile(directory/name,[directory/'origin/cnn_result_stabilizer_baseline.v',kernel,
            directory/name/bench_name],inputs,result)
    configs=data['kernel_configurations']['modes']
    old_modes={item['mode']:item['summary'] for item in old['generic_miter_modes']}
    _require(len(old_modes)==40,'Historical reference mode labels duplicate')
    for actual,(bits,shift,coord,reader,(c,h,l),vectors) in zip(configs,modes):
        label=f'miter_a{bits}s{shift}_c{coord}_e{reader}_p{c}_{h}_{l}'
        summary=old_modes[label]
        matches=re.fullmatch(r'PASS AREA_GRID_EQUIVALENCE area_bits=\d+ shift=\d+ coord=\d+ external=\d+ params=\d+/\d+/\d+ '
            r'vectors=(\d+) jobs=(\d+) rejected=(\d+) cycle_checks=(\d+) serial=(\d+) bank_reuses=(\d+)',summary)
        _require(matches is not None,'Historical configuration completion format changed')
        expected_record=dict(mode=label,summary=summary,area_bits=bits,area_shift=shift,coord_shift=coord,
            external_reader=reader,parameters=[c,h,l],vectors_file=vectors,
            counts=dict(zip(('vectors','jobs','rejected','cycle_checks','serial','bank_reuses'),map(int,matches.groups()))))
        _require(actual==expected_record,'Fresh configuration coverage differs: '+label)
        _area_sim(directory/'kernel_configurations','tb_area_grid_equivalence',label,[
            f'-gAREA_BITS={bits}',f'-gAREA_SHIFT={shift}',f'-gCOORD_SHIFT={coord}',
            f'-gEXTERNAL_CANDIDATE_READER={reader}',f'-gCONFIRM_RESULTS={c}',f'-gHOLD_RESULTS={h}',
            f'-gLOST_RESULTS={l}','+vectors='+vectors],inputs,result,summary)
    old_modes={item['mode']:item['summary'] for item in old['lifecycle_modes']}
    _require(len(old_modes)==10 and data['kernel_lifecycle'].get('aggregate_aborts')==560,
        'Ten-mode lifecycle aggregate coverage changed')
    for actual,((c,h,l),reader) in zip(data['kernel_lifecycle']['modes'],
        ((setting,reader) for setting in params for reader in (0,1))):
        label=f'lifecycle_c{c}h{h}l{l}_e{reader}'
        summary=old_modes[label]
        match=re.fullmatch(r'PASS COMBINED_STATE_LIFECYCLE coord=3 area=22 reader=\d+ params=\d+/\d+/\d+ '
            r'vectors=(\d+) gold=(\d+) jobs=(\d+) cycles=(\d+) serial=(\d+) reuses=(\d+) aborts=(\d+)',summary)
        _require(match is not None,'Historical lifecycle completion format changed')
        counts=dict(zip(('vectors','gold','jobs','cycles','serial','reuses','aborts'),map(int,match.groups())))
        _require((counts['vectors'],counts['gold'],counts['aborts'])==(2385,2315,56),
            '28-state lifecycle reset/clear coverage changed')
        _require(actual==dict(mode=label,summary=summary,external_reader=reader,parameters=[c,h,l],
            area_bits=22,area_shift=6,coord_shift=3,**counts),'Fresh lifecycle coverage differs: '+label)
        _area_sim(directory/'kernel_lifecycle','tb_combined_state_lifecycle',label,[
            f'-gEXTERNAL_CANDIDATE_READER={reader}',f'-gCONFIRM_RESULTS={c}',f'-gHOLD_RESULTS={h}',
            f'-gLOST_RESULTS={l}',f'+vectors=c{c}h{h}l{l}.txt'],inputs,result,summary)
    for name in ('pipeline_miter','kernel_reference'):
        _require(_json(directory/name/'RESULTS.json')==data[name],'Compact stage output differs: '+name)
    suffixes={'.json','.jsonl','.log','.txt','.py','.sv','.v','.patch'}
    expected_evidence={path.relative_to(directory).as_posix() for path in directory.rglob('*')
        if path.is_file() and path!=result and path.suffix in suffixes}
    _require({Path(name).as_posix() for name in data.get('evidence_hashes',{})}==expected_evidence,
        'Compact complete fresh/imported evidence file closure differs')
    _require(len([name for name in expected_evidence if name.endswith('_command.json') and
        name.split('/')[0] in {'pipeline_miter','domain','kernel_reference','kernel_configurations','kernel_lifecycle'}])==61,
        'Compact expected 61 persisted fresh command records missing')


def _stroke_contract(directory,data,inputs,result):
    tests=data.get('tests',{})
    names={'mixed_nn','mixed_two_opt','blank','edge_capacity','path_capacity','point_capacity','lifecycle'}
    _require(set(tests)==names and all(item.get('status')=='PASS' for item in tests.values()), 'Stroke test coverage missing')
    for name in names:
        case=directory/name
        for phase in ('vlib','compile','simulate'):
            metadata=_json(case/(phase+'_command.json'))
            _require(metadata.get('returncode')==0, 'Nonzero persisted process exit: '+name+'/'+phase)
            logfile=_local(phase+'.log',case)
            _digest(logfile,metadata.get('log_sha256'))
            _require(_mtime(result)>=_mtime(case/(phase+'_command.json'))>=_mtime(logfile), 'Command evidence chronology error')
            command=metadata.get('command',[])
            _require(command and Path(command[0]).name.lower()=={'vlib':'vlib.exe','compile':'vlog.exe','simulate':'vsim.exe'}[phase],
                     'Unexpected test executable')
            if phase=='simulate':
                _require('-batch' in command and 'onerror {quit -code 1}; run -all; quit -f' in command, 'Unsafe simulation completion contract')
        _log(case,'compile.log',inputs,result,compile=True)
        item=tests[name]
        if name=='lifecycle':
            marker='PASS STROKE_LIFECYCLE cancel/reset priority and no replay checks=18'
        elif name.endswith('_capacity'):
            error={'edge_capacity':2,'path_capacity':3,'point_capacity':4}[name]
            _require(item.get('expected_error')==error,'Capacity error changed')
            marker=f'PASS capacity error={error} before motion'
        else:
            expected={'mixed_nn':(549,26,64,122,26260769),'mixed_two_opt':(549,26,64,122,26776781),'blank':(0,0,0,4,12973103)}[name]
            edges,paths,points,acked,cycles=expected
            _require(tuple(item.get(k) for k in ('edges','paths','points','gcode_lines'))==(edges,paths,points,acked),'Stroke coverage counts changed')
            _require(item.get('planned_distance_cmm',1)<=item.get('baseline_distance_cmm',0),'Planner increases own baseline pen-up distance')
            marker=f'PASS STROKE_SPLIT full thin graph paths mapper Gcode cycles={cycles} edges={edges} paths={paths} points={points} acked={acked}'
            actual=_local('gcode.txt',case).read_bytes()
            expected_text=_local('expected_gcode.txt',case).read_bytes()
            _require(actual==expected_text and len(actual.splitlines())==acked,'G-code mismatch')
        _require(item.get('checks')==[marker], 'Recorded stroke marker mismatch')
        _log(case,'simulate.log',inputs,result,marker)


def _suite_contract(name,path,data,inputs,evidence):
    directory=path.parent
    if name=='cnn_area_pipeline_compact':
        _area_contract(directory,data,inputs,path)
        return
    if name=='stroke_release':
        _stroke_contract(directory,data,inputs,path)
        return
    if name=='cnn_named_top':
        _require((data.get('baseline_assertion_count'),data.get('added_assertion_count'),data.get('assertion_count'))==(44,7,51),
                 'Top original/focused assertions missing')
        _require(data.get('full_lint_source_count')==77,'Full production lint closure changed')
        _require(directory/'lint_full.log' in evidence,'Lint log is not hashed')
        _log(directory,'lint_full.log',inputs,path,compile=True)
        _log(directory,'compile_top.log',inputs,path,compile=True)
        text=_log(directory,'simulate_top.log',inputs,path,'PASS CNN_NAMED_TOP_ALL checks=51')
        _require('CENTER_CACHE_FULL_TOP_COUNTS baseline=44 added=7 total=51' in text,'Top counts not substantiated')
        _require(len(re.findall(r'^# PASS (?!CNN_NAMED_TOP_ALL)',text,re.M))==51,'Top assertion log coverage changed')
    elif name=='key3_top_reset_release':
        _require(data.get('assertion_count')==26,'KEY3 reset coverage changed')
        _log(directory,'compile.log',inputs,path,compile=True)
        text=_log(directory,'simulate.log',inputs,path,'PASS KEY3_TOP_RESET_ALL checks=26')
        _require(len(re.findall(r'^# PASS (?!KEY3_TOP_RESET_ALL)',text,re.M))==26,'KEY3 assertion coverage changed')
        for item in ('KEY3 asynchronously asserts both application reset domains','KEY3 asserts Ethernet PLL, DDR reference PLL and DDR IP reset',
                     'KEY1/KEY2 held through reset do not start jobs after boot lock expires'):
            _require(item in text,'Missing reset safety assertion '+item)
    elif name=='cnn_named_pcb':
        _log(directory,'compile.log',inputs,path,compile=True)
        tests=data.get('tests',{})
        _require(set(tests)=={'tb_real_pcb_core','tb_real_pcb_pipeline'},'PCB test coverage changed')
        for top,marker,count,prefix in (
            ('tb_real_pcb_core','BINARY_C4_4_GOLDEN_PASS samples=15 sat=0',15,'BINARY_C4_4_SAMPLE_PASS'),
            ('tb_real_pcb_pipeline','PCB_RAW_PIPELINE_GOLDEN_PASS samples=9',9,'PCB_RAW_PIPELINE_SAMPLE_PASS')):
            text=_log(directory,top+'.log',inputs,path,marker)
            _require(tests[top].get('status')=='PASS' and tests[top].get('marker')==marker,'PCB result marker changed')
            _require(len(re.findall(r'^# '+prefix+r'\b',text,re.M))==count,'PCB vector coverage changed')
    elif name=='cnn_stability_core':
        for key,value in {'full_inference_cases':27,'native_roi_cases':9,'synthetic_detail_cases':18,'boundary_classify_checks':11,
                          'conv1_byte_values_compared':221184,'conv2_byte_values_compared':110592,'fc_logits_compared':81,
                          'color_sums_compared':81,'confidence_shift':8}.items():
            _require(data.get(key)==value,'Ordinary CNN coverage changed: '+key)
        _require(data.get('weight_sha256')==PINS['model/export/weights.mem'] and data.get('bias_sha256')==PINS['model/export/biases.mem'],
                 'Ordinary CNN model changed')
        _log(directory,'lint.log',inputs,path,compile=True)
        text=_log(directory,'core.log',inputs,path,'PASS ALL CNN REMOTE DETAIL cases=27')
        records=re.findall(r'^# PASS CNN CASE (\d+) cycles=(\d+) logits=(-?\d+),(-?\d+),(-?\d+) class=(\d+) color_conf=(\d+) shape_conf=(\d+)',text,re.M)
        _require(len(records)==27 and {int(row[0]) for row in records}==set(range(27)),'Ordinary CNN sample coverage changed')
        _require(len(data.get('case_results',[]))==27,'Ordinary CNN result entries missing')
        for row,item in zip(records,data['case_results']):
            values=list(map(int,row));_require(item==dict(case=values[0],cycles=values[1],logits=values[2:5],class_id=values[5],
                    color_conf=values[6],shape_conf=values[7]),'CNN logged logits/result mismatch')
        _log(directory,'boundaries.log',inputs,path,'PASS ALL CLASSIFY BOUNDARIES checks=11')
    elif name=='cnn_named_report':
        _log(directory,'compile.log',inputs,path,compile=True)
        _log(directory,'simulate.log',inputs,path,'PASS CNN_NAMED_REPORT_ALL 33 jobs plus capacity and safety')
        jobs=data.get('jobs',[])
        _require(len(jobs)==33 and [item.get('job') for item in jobs]==list(range(1,34)) and
                 all(item.get('all_gcode_commands_exact') is True for item in jobs),'Report/G-code comparison missing')
        _require({item.get('class_id') for item in jobs[:9]}==set(range(1,10)),'Report class coverage changed')
        _require((_local('safety_trace.txt',directory).read_text().splitlines())==
                 ['CAPACITY|13|14|12|0|26780','STOP|2|4|0|0|0'],'Report page/stop safety trace changed')
        _report_artifacts(directory,data)


def _report_artifacts(directory,data):
    """Recheck un-hashed legacy output text/G-code against its pinned reference."""
    source=_local('tools/cnn_named_report_reference.py')
    previous=sys.dont_write_bytecode
    sys.dont_write_bytecode=True
    try:
        spec=importlib.util.spec_from_file_location('release_gate_named_report_reference',source)
        reference=importlib.util.module_from_spec(spec)
        spec.loader.exec_module(reference)
    finally:
        sys.dont_write_bytecode=previous
    traces,commands={},{}
    for line in _local('glyph_trace.txt',directory).read_text().splitlines():
        ident,row,col,char=map(int,line.split('|'))
        traces.setdefault(ident,{}).setdefault(row,[]).append((col,chr(char)))
    for line in _local('gcode.txt',directory).read_text().splitlines():
        ident,command=line.split('|',1)
        commands.setdefault(int(ident),[]).append(command)
    font=reference.font_segments(_local('01_rtl/grbl_vector_font_rom.v'))
    actual_jobs=[]
    for line in _local('jobmeta.txt',directory).read_text().splitlines():
        ident,cls,conf,judgement,cnn,square,old_offset,new_offset,count=map(int,line.split('|'))
        expected=[] if square else reference.report_text(cls,conf,judgement,bool(cnn),ident,
                                                          (639,359) if ident==12 else (210,110))
        text=[]
        for row in sorted(traces.get(ident,{})):
            cells=traces[ident][row]
            _require([col for col,_ in cells]==list(range(len(cells))),'Report character columns changed')
            text.append(''.join(char for _,char in cells))
        _require([line.rstrip() for line in text]==[line.rstrip() for line in expected],'Report glyph/text differs from reference')
        target=cnn and judgement==2 and 1<=cls<=9
        height=2500 if square else 2060 if target else 860 if cnn else 1460
        _require(new_offset-old_offset==height,'Report newline height changed')
        expected_gcode=reference.machine_commands(expected,font,old_offset,height,bool(square))
        actual=commands[ident]
        _require(actual==expected_gcode and len(actual)==count,'Report G-code artifact differs from reference')
        actual_jobs.append(dict(job=ident,class_id=cls,text=text,all_gcode_commands_exact=True,
            gcode_lines=count,pen_downs=actual.count('G1 Z+005.00 F01200'),newline_delta_cmm=height))
    _require(actual_jobs==data['jobs'],'Report artifacts do not substantiate RESULTS jobs')


def check(files, required=None) -> dict:
    """Validate the current independent release without changing any files."""
    global LAST_AUDIT, _CONSUMED
    _CONSUMED={}
    _local(Path(__file__))
    _require(files, 'Supply fresh current regression RESULTS.json files')
    required=SUITES if required is None else frozenset(required)
    _require(required and required<=SUITES,'Unknown/empty required regression set')
    metric_proof=compact_metric_gate()
    for name,value in PINS.items():
        _digest(_local(name),value)
    result,names,details={},set(),{}
    for value in files:
        path=_local(value)
        name=path.parent.name
        _require(name in SUITES and path==ROOT/'02_sim'/name/'RESULTS.json','Not an approved current regression result: '+str(path))
        _require(name not in names,'Duplicate regression suite: '+name)
        data=_json(path)
        _require(data.get('status')=='PASS','Regression did not pass: '+name)
        inputs,evidence=_hash_maps(path,data)
        covered={p.relative_to(ROOT).as_posix() for p in inputs}
        _require(SCOPE[name]<=covered,'Current source/model coverage missing for '+name+': '+repr(sorted(SCOPE[name]-covered)))
        rc_contract=_runner(name,inputs)
        before=set(_CONSUMED)
        _suite_contract(name,path,data,inputs,evidence)
        for consumed in set(_CONSUMED)-before:
            _require(_mtime(path)>=_mtime(consumed),'RESULTS predates consumed output artifact: '+str(consumed))
        names.add(name)
        result[path.relative_to(ROOT).as_posix()]=_hash(path)
        details[name]={'status':'PASS','input_hash_count':len(inputs),'evidence_hash_count':len(evidence),'exit_code_contract':rc_contract}
    _require(required<=names,'Missing required regressions: '+repr(sorted(required-names)))
    LAST_AUDIT={'status':'PASS','required':sorted(required),'checked':details,'result_hashes':result,
                'compact_metric_proof':metric_proof,
                'validated_file_sha256':{p.relative_to(ROOT).as_posix():value for p,value in sorted(_CONSUMED.items())},
                'limitation':'Explicit process exit codes are available for stroke, compact CNN and metric cases; other exact pinned runners reject nonzero exit before PASS and clean terminal logs are verified.',
                'hardware_status':'NOT_RUN'}
    return result


def evidence_manifest(files, required=None) -> dict:
    """Check first; fingerprint every consumed input, RESULT, log and artifact.

    This supplements older RESULTS without changing them. Keys are release-root
    relative paths. The builder must save/pin this map before synthesis and check
    it again before bitgen, including every listed byte in its frozen evidence.
    """
    check(files,required)
    return dict(LAST_AUDIT['validated_file_sha256'])


def _selftest():
    files=[ROOT/'02_sim'/name/'RESULTS.json' for name in sorted(SUITES)]
    check(files)
    positive=copy.deepcopy(LAST_AUDIT)
    original_json=_json
    mutations=[]
    def reject(label,target,change):
        def amended(path):
            value=original_json(path)
            if Path(path)==target:
                value=copy.deepcopy(value);change(value)
            return value
        with mock.patch.object(sys.modules[__name__],'_json',side_effect=amended):
            try:
                check(files)
            except (AssertionError,KeyError,TypeError) as exc:
                mutations.append({'case':label,'status':'REJECTED','reason':str(exc)})
            else:
                raise AssertionError('Negative selftest accepted: '+label)
    area=ROOT/'02_sim/cnn_area_pipeline_compact/RESULTS.json'
    reject('bad_status',area,lambda d:d.update(status='FAIL'))
    reject('missing_kernel_input',area,lambda d:d['input_hashes'].pop(str(ROOT/'01_rtl/cnn_result_stabilizer.v')))
    reject('miter_count_weakened',area,lambda d:d['pipeline_miter']['coverage'].update(public_ports=36))
    reject('original_guard_weakened',area,lambda d:d['pipeline_miter']['original_program'].update(jobs=80))
    reject('domain_count_weakened',area,lambda d:d['domain']['coverage'].update(code_domain_size=65535))
    reject('lifecycle_abort_weakened',area,lambda d:d['kernel_lifecycle']['modes'][0].update(aborts=55))
    reject('kernel_hash_corrupt',area,lambda d:d['input_hashes'].update({str(ROOT/'01_rtl/cnn_result_stabilizer.v'):'0'*64}))
    reject('configuration_mode_missing',area,lambda d:d['kernel_configurations']['modes'].pop())
    reject('configuration_parameter_changed',area,lambda d:d['kernel_configurations']['modes'][0].update(parameters=[1,0,1]))
    reject('lifecycle_parameter_mode_missing',area,lambda d:d['kernel_lifecycle']['modes'].pop())
    reject('historical_wrongly_claimed_fresh',area.parent/'ORIGIN_IMPORT.json',lambda d:d.update(fresh=True))
    reject('historical_same_kernel_claim',area.parent/'ORIGIN_IMPORT.json',lambda d:d.update(same_kernel_as_production=True))
    reject('reference_kernel_changed',area,lambda d:d.update(reference_kernel_sha256='0'*64))
    reject('fresh_command_nonzero_rc',area.parent/'pipeline_miter/simulate_command.json',lambda d:d.update(returncode=1))
    reject('fresh_command_wrong_production',area.parent/'pipeline_miter/compile_command.json',lambda d:d.update(production_kernel_sha256='0'*64))
    reject('fresh_command_wrong_compile_source',area.parent/'pipeline_miter/compile_command.json',lambda d:d['command'].__setitem__(-1,'D:/wrong/bench.sv'))
    reject('fresh_command_unsafe_simulation',area.parent/'pipeline_miter/simulate_command.json',lambda d:d['command'].__setitem__(-1,'run -all; quit -f'))
    reject('fresh_command_missing_file_license',area.parent/'pipeline_miter/simulate_command.json',lambda d:d.update(MGLS_LICENSE_FILE=''))
    reject('fresh_command_wrong_log_hash',area.parent/'pipeline_miter/simulate_command.json',lambda d:d.update(log_sha256='0'*64))
    metric=ROOT/'02_sim/compact_metric_boundaries/RESULTS.json'
    reject('metric_boundary_case_missing',metric,lambda d:d['tests'].pop('generic32'))
    reject('metric_wrong_planner_identity',metric,lambda d:d.update(planner_sha256='0'*64))
    reject('metric_nonzero_command_rc',metric.parent/'finite_bound/simulate_command.json',lambda d:d.update(returncode=1))
    stroke=ROOT/'02_sim/stroke_release/RESULTS.json'
    reject('stroke_capacity_missing',stroke,lambda d:d['tests'].pop('edge_capacity'))
    reject('explicit_process_rc_nonzero',stroke.parent/'mixed_nn/simulate_command.json',lambda d:d.update(returncode=1))
    reject('explicit_log_hash_corrupt',stroke.parent/'mixed_nn/simulate_command.json',lambda d:d.update(log_sha256='0'*64))
    reject('core_confidence_shift_changed',ROOT/'02_sim/cnn_stability_core/RESULTS.json',lambda d:d.update(confidence_shift=9))
    reject('pcb_test_missing',ROOT/'02_sim/cnn_named_pcb/RESULTS.json',lambda d:d['tests'].pop('tb_real_pcb_pipeline'))
    reject('report_gcode_comparison_missing',ROOT/'02_sim/cnn_named_report/RESULTS.json',lambda d:d['jobs'][0].update(all_gcode_commands_exact=False))
    original_mtime=_mtime
    with mock.patch.object(sys.modules[__name__],'_mtime',side_effect=lambda p:0 if Path(p)==area else original_mtime(p)):
        try:
            check(files)
        except AssertionError as exc:
            mutations.append({'case':'stale_results','status':'REJECTED','reason':str(exc)})
        else:
            raise AssertionError('Stale result accepted')
    try:
        check(files[:-1])
    except AssertionError as exc:
        mutations.append({'case':'missing_required_suite','status':'REJECTED','reason':str(exc)})
    else:
        raise AssertionError('Missing required suite accepted')
    _require(len(mutations)==30,'Selftest count changed')
    check(files)
    record={'status':'PASS','completed_utc':datetime.now(timezone.utc).isoformat(),
        'gate_sha256':_hash(Path(__file__)),'positive':positive,'negative_cases':mutations,
        'production_modified':False,'simulation_rerun':False,'hardware_status':'NOT_RUN'}
    out=ROOT/('reports/key3_stroke_regression_gate_selftest_'+_hash(Path(__file__))[:12]+'.json')
    _require(not out.exists(),'Do not overwrite prior gate selftest')
    out.write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps(record,indent=2))


if __name__=='__main__':
    if sys.argv[1:]==['--selftest']:
        _selftest()
    else:
        print(json.dumps(check(sys.argv[1:]),indent=2))
