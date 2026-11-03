"""Fail-closed display-noise release review; retains raw adverse diagnostics."""
import argparse
import csv
import json
import re
import subprocess
import sys
import strict_release_review as strict
from display_noise_paths import *
from audit_display_noise_scope import ALLOWED as ALLOWED_DISPLAY_CHANGES
from verify_inactive_project_files import validate as validate_inactive
from verify_display_noise_build_strategy import validate as validate_build_strategy
from validate_display_equivalence_chain import validate as validate_equivalence_chain, validate_binding as validate_equivalence_binding
def pins(text):
    block=text.split('Detailed IO Report',1)[1].split('Clock',1)[0]
    return {m[0]: {'direction':m[1],'location':m[2],'standard':m[3],'type':m[4]} for m in re.findall(r'^\s*(\S+)\s+(INPUT|OUTPUT|INOUT)\s+(\S+)\s+(\S+)\s+(HDIO|HRIO|DDR)\s+',block,re.M)}
def categories(text):
    return {m[0]:int(m[1]) for m in re.findall(r'^\d+\. checking (.+?)\((\d+)\) \((?:HIGH|MEDIUM|LOW)\)',text,re.M)}
def hashes_match(items):
    return bool(items) and all(Path(p).is_file() and sha(p)==h for p,h in items.items())
REQUIRED_REGRESSION_CHECKS = frozenset('''ordinary_cnn_stability startup_fault_0 startup_fault_1 startup_fault_2 document_type15 legacy_lint_compile pcb_packet_30s_current_downcounter pcb_packet_compile pcb_30000ms_deadline cnn_2000ms_deadline heartbeat_250ms session_frame_job_filter cached_ack_keeps_deadline mode_cancel real_lease_loss pcb_actual_box_status_cdc_13_checks pcb_actual_box_compile key4_oneshot_hold_bounce coordinate_mux_equivalence_400012 key4_equivalence_compile current_rtl_hashes_match_all_tested_inputs'''.split())
REQUIRED_REGRESSION_CHECKS = REQUIRED_REGRESSION_CHECKS | frozenset('''display_tone_fixed_tap_exhaustive display_tone_fixed_tap_stall_timing spatial_reference_match spatial_full_range_no_truncation spatial_edges_motion_no_smear spatial_frame_line_boundaries video_two_cycle_alignment top_cnn_unchanged_input ae_policy_unchanged'''.split())
REQUIRED_REGRESSION_CHECKS = REQUIRED_REGRESSION_CHECKS | {'exact_spatial_implementation_equivalence_chain'}
REQUIRED_CURRENT_RTL = (
    '01_rtl/imgq_gain_m/shared/rtl/hxa_main_link.v',
    '01_rtl/imgq_gain_m/shared/rtl/hxa_packet_codec.v',
    '01_rtl/imgq_gain_m/main/user_source/hdl_source/design_top_wrapper.v',
    '01_rtl/imgq_gain_m/main/user_source/hdl_source/hx_result_select.v',
    '01_rtl/imgq_gain_m/main/user_source/hdl_source/key4_hold_debounce.v',
    '01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/display_tone_96.v',
    '01_rtl/imgq_gain_m/main/user_source/hdl_source/a4_display_spatial_h1.v',
)
REQUIRED_REGRESSION_LOGS = {
    '02_sim/link_legacy_regression_v2/ordinary_stability.log':'PASS tb_hxa_main_stability',
    '02_sim/link_legacy_regression_v2/startup_fault_0.log':'PASS tb_hxa_main_startup_regression FAULT_KIND=0',
    '02_sim/link_legacy_regression_v2/startup_fault_1.log':'PASS tb_hxa_main_startup_regression FAULT_KIND=1',
    '02_sim/link_legacy_regression_v2/startup_fault_2.log':'PASS tb_hxa_main_startup_regression FAULT_KIND=2',
    '02_sim/link_legacy_regression_v2/document_type15.log':'PASS tb_hxa_main_document_type15',
    '02_sim/link_legacy_regression_v2/link_legacy_compile.log':'Top level modules:',
    '02_sim/link_pcb_wait_v2/transcript_batch_final.log':'PASS ALL packet-level PCB compatibility',
    '02_sim/link_pcb_wait_v2/compile.log':'Top level modules:',
    '02_sim/pcb_actual_box_v2/transcript.log':'PASS PCB actual-box integration checks=13',
    '02_sim/pcb_actual_box_v2/compile.log':'Top level modules:',
    '02_sim/pcb_actual_box_v2/key4_oneshot.log':'TB_KEY4_PCB_ONESHOT_PASS',
    '02_sim/pcb_actual_box_v2/coordinate_equivalence.log':'PASS six-coordinate mux equivalence checks=400012',
    '02_sim/pcb_actual_box_v2/extra_compile.log':'Top level modules:',
    'reports/display_tone_rtl_regression.log':'PASS display_tone frozen_tap_cycle_compare',
    '02_sim/display_noise/compile.log':'Top level modules:',
}
SPATIAL_CASES = frozenset('''flat_noise strong_edges rgb8_range threshold_rgb_guard geometry_1x1 geometry_1x7 geometry_2x5 geometry_7x1 geometry_7x5 malformed_reentry full_720p'''.split())
REQUIRED_REGRESSION_LOGS.update({'02_sim/display_noise/'+name+'/transcript.log':'PASS pixel oracle' for name in SPATIAL_CASES})
REQUIRED_ALGORITHM_INPUTS = (
    'reports/display_tone_reference.json','reports/display_tone_rtl_regression.json',
    'tools/display_tone_reference.py','tools/run_display_tone_regression.py',
    '02_sim/display_tone/tb_display_tone_regression.sv',
    '02_sim/display_tone/display_tone_96_frozen.v',
    '02_sim/display_tone/fixed_curve.hex','02_sim/display_tone/display_curve.hex',
    '02_sim/display_noise/vectors_manifest.json','model/display_spatial_reference.py',
    '02_sim/display_noise/generate_vectors.py','02_sim/display_noise/run_display_noise.ps1',
    '02_sim/display_noise/tb_display_spatial.sv',
    '02_sim/display_noise/verification.json',
    'reports/display_functional_contract.json',
    'tools/verify_display_functional_contract.py',
    'model/replay_display_noise.py',
    '02_sim/display_noise/summarize_results.py',
    'tools/validate_display_equivalence_chain.py',
    'reports/display_equivalence_chain.json',
    '02_sim/display_noise_combined_trial/verification.json',
    '02_sim/display_noise_nocarry_trial/verification.json',
    'reports/attempt8_spatial_reuse.json',
    'reports/attempt7_spatial_archive.json',
)

def clean_simulation_log(text, marker):
    """A final zero summary cannot hide an earlier simulator error."""
    clean_summary = re.search(r'(?:^|\n)(?:# )?Errors: 0, Warnings: 0(?:\r?\n|$)', text)
    adverse = re.search(r'\*\*\s+(?:Error|Fatal):|(?:^|\n)(?:# )?Errors:\s*[1-9]\d*', text)
    warning_count = re.search(r'(?:^|\n)(?:# )?Errors:\s*\d+, Warnings:\s*[1-9]\d*', text)
    return bool(marker in text and clean_summary and not adverse and not warning_count)
def validate_regression(regression, root=ROOT, snapshot=None):
    """Require this release's named regressions and hash-bound current inputs."""
    errors=[]
    if not isinstance(regression,dict): return {'passed':False,'errors':['Regression must be an object']}
    named=regression.get('checks',{})
    inputs=regression.get('input_hashes',{})
    logs=regression.get('logs',[])
    if regression.get('passed') is not True: errors.append('Regression overall status must be true')
    if not isinstance(named,dict): named={}; errors.append('checks must be an object')
    for key in sorted(REQUIRED_REGRESSION_CHECKS):
        if named.get(key) is not True: errors.append('Missing or failed required regression: '+key)
    if any(value is not True for value in named.values()): errors.append('A regression check is not true')
    if not isinstance(inputs,dict): inputs={}; errors.append('input_hashes must be an object')
    def canonical(p): return str(Path(p).resolve()).replace('\\','/').casefold()
    normalized={}
    for path,digest in inputs.items():
        if not isinstance(path,str) or not isinstance(digest,str) or not re.fullmatch(r'[0-9A-Fa-f]{64}',digest):
            errors.append('Malformed input hash entry'); continue
        key=canonical(path)
        if key in normalized: errors.append('Duplicate canonical input: '+path)
        normalized[key]=digest.upper()
        if not Path(path).is_absolute() or not Path(path).is_file() or sha(path)!=digest.upper(): errors.append('Input hash mismatch/missing: '+path)
    for rel in REQUIRED_CURRENT_RTL:
        path=root/rel; digest=normalized.get(canonical(path))
        if not path.is_file() or digest!=sha(path): errors.append('Required current RTL missing or stale: '+rel)
    for rel in REQUIRED_ALGORITHM_INPUTS:
        path=root/rel;digest=normalized.get(canonical(path))
        if not path.is_file() or digest!=sha(path):errors.append('Required algorithm evidence missing/unbound: '+rel)
    if snapshot is not None:
        frozen={canonical(item['path']):item['sha256'] for item in snapshot.get('files',[])}
        for rel in REQUIRED_CURRENT_RTL:
            key=canonical(root/rel)
            if key not in frozen or normalized.get(key)!=frozen[key]: errors.append('Tested RTL differs from routed prebuild snapshot: '+rel)
    if not isinstance(logs,list) or any(not isinstance(p,str) for p in logs): logs=[]; errors.append('logs must be a list of paths')
    canonical_logs=[canonical(p) for p in logs]
    if len(canonical_logs)!=len(set(canonical_logs)): errors.append('Duplicate regression log')
    for rel,marker in REQUIRED_REGRESSION_LOGS.items():
        path=root/rel; key=canonical(path)
        if key not in canonical_logs: errors.append('Missing required regression log: '+rel)
        if key not in normalized: errors.append('Required log lacks SHA256 binding: '+rel)
        if not path.is_file(): errors.append('Required log file missing: '+rel); continue
        text=read(path)
        if not clean_simulation_log(text, marker): errors.append('Required log lacks clean completion or contains adverse simulator evidence: '+rel)
    return {'passed':not errors,'errors':errors,'required_check_count':len(REQUIRED_REGRESSION_CHECKS),'required_rtl_count':len(REQUIRED_CURRENT_RTL),'required_log_count':len(REQUIRED_REGRESSION_LOGS)}
def validate_gate_evidence(gate, run=RUN, name=NAME):
    """Recheck every gate-bound DB/report/log and require the complete set."""
    errors=[]
    canonical=lambda p:str(Path(p).resolve()).replace('\\','/').casefold()
    if not isinstance(gate,dict): return {'passed':False,'errors':['Gate must be an object']}
    if gate.get('passed') is not True or gate.get('bitgen_allowed') is not True or gate.get('failures')!=[]: errors.append('Gate did not allow bitgen')
    if gate.get('name')!=name or canonical(gate.get('run',''))!=canonical(run): errors.append('Gate run/name identity mismatch')
    if canonical(gate.get('snapshot',''))!=canonical(run/'source_snapshot.json'): errors.append('Gate snapshot identity mismatch')
    bound={}
    raw=gate.get('evidence',{})
    if not isinstance(raw,dict): raw={}; errors.append('Gate evidence must be an object')
    for value,item in raw.items():
        p=Path(value); p=p if p.is_absolute() else run/p
        if not isinstance(item,dict) or not re.fullmatch(r'[0-9A-Fa-f]{64}',str(item.get('sha256',''))): errors.append('Malformed gate evidence hash: '+str(value)); continue
        key=canonical(p)
        if key in bound: errors.append('Duplicate gate evidence path: '+str(p))
        bound[key]=item['sha256'].upper()
        if not p.resolve().is_relative_to(run.resolve()) or not p.is_file() or sha(p)!=item['sha256'].upper(): errors.append('Gate evidence changed/missing/outside run: '+str(p))
        elif 'mtime_ns' in item and p.stat().st_mtime_ns!=item['mtime_ns']: errors.append('Gate evidence timestamp changed: '+str(p))
    required=[name+'_pr.timing',name+'_phy.area','route_flow.status','.opt_route.end.f','.read_design.begin.f',name+'_pr.db','synth.log','place.log','route.log']
    for rel in required:
        if canonical(run/rel) not in bound: errors.append('Missing required gate evidence: '+rel)
    return {'passed':not errors,'errors':errors,'required_evidence_count':len(required)}
def validate_source_scope(scope, historical_snapshot, root=ROOT, base=BASE):
    errors=[]
    if not isinstance(scope,dict) or scope.get('passed') is not True:return {'passed':False,'errors':['Scope must be an accepted object']}
    expected={}
    for item in historical_snapshot.get('files',[]):
        p=Path(item['path']);rel=p.relative_to(base).as_posix()
        if item['kind'] in {'project','audit_configuration'} or '/td_project_pcb_auto_v2/' in rel:continue
        expected[rel]=item['sha256']
    rows=scope.get('files',[])
    if not isinstance(rows,list):return {'passed':False,'errors':['Scope files must be a list']}
    actual={}
    for item in rows:
        if not isinstance(item,dict) or not {'path','sha256','baseline_sha256'}<=item.keys():errors.append('Malformed scope row');continue
        if item['path'] in actual:errors.append('Duplicate scope source: '+item['path'])
        actual[item['path']]=item
    if not expected or set(actual)!=set(expected):errors.append('Scope omits or adds baseline active dependencies')
    changed=set()
    for rel,entry in actual.items():
        p=root/rel
        if rel not in expected or entry['baseline_sha256']!=expected[rel]:errors.append('Scope baseline hash mismatch: '+rel)
        if not p.resolve().is_relative_to(root.resolve()) or not p.is_file() or sha(p)!=entry['sha256']:errors.append('Scope current input mismatch/missing: '+rel)
        if entry['sha256']!=entry['baseline_sha256']:changed.add(rel)
    if changed!=set(scope.get('changed',[])) or not changed<=ALLOWED_DISPLAY_CHANGES:errors.append('Scope changed-source list is incomplete or outside three display modules')
    if set(scope.get('allowed_changes',[]))!=ALLOWED_DISPLAY_CHANGES:errors.append('Scope allowed changes differ from fixed three-module policy')
    return {'passed':not errors,'errors':errors,'expected_input_count':len(expected),'changed':sorted(changed)}
def validate_algorithm_evidence(root=ROOT, base=BASE):
    errors=[]
    tone=root/'01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/display_tone_96.v'
    original=base/'01_rtl/imgq_gain_m/main/user_source/hdl_source/isp/display_tone_96.v'
    tone_ref=obj(root/'reports/display_tone_reference.json')
    tone_rtl=obj(root/'reports/display_tone_rtl_regression.json')
    if tone_ref.get('status')!='PASS' or tone_ref.get('input_values')!=256 or tone_ref.get('baseline_rtl_sha256')!=sha(original) or tone_ref.get('variant_rtl_sha256')!=sha(tone):errors.append('Tone exhaustive reference identity/coverage failed')
    if tone_ref.get('changes_ae_gain_awb') is not False or tone_ref.get('adds_dsp_operations') is not False:errors.append('Tone reference reports unauthorized AE/gain/DSP change')
    if tone_rtl.get('status')!='PASS' or tone_rtl.get('baseline_fixed_tap_cycle_equivalence') is not True or tone_rtl.get('integer_reference_data_and_markers') is not True or tone_rtl.get('rtl_sha256')!=sha(tone) or tone_rtl.get('tb_sha256')!=sha(root/'02_sim/display_tone/tb_display_tone_regression.sv'):errors.append('Tone RTL cycle-equivalence identity/coverage failed')
    log=read(root/'reports/display_tone_rtl_regression.log')
    if not isinstance(tone_rtl.get('pass_line'),str) or tone_rtl['pass_line'] not in log:errors.append('Tone JSON pass line missing from actual simulation log')
    frozen=read(root/'02_sim/display_tone/display_tone_96_frozen.v').replace('module display_tone_96_frozen','module display_tone_96',1)
    if frozen!=read(original):errors.append('Tone cycle baseline is not the exact signed-baseline RTL with only module rename')
    spatial=root/'02_sim/display_noise';manifest=obj(spatial/'vectors_manifest.json')
    verification=obj(spatial/'verification.json')
    if verification.get('status')!='PASS' or verification.get('edge_threshold')!=16 or verification.get('board_validation')!='NOT_RUN':errors.append('Spatial verification status/threshold/hardware scope mismatch')
    source_hashes=verification.get('source_sha256',{})
    required_sources={
        '01_rtl/imgq_gain_m/main/user_source/hdl_source/a4_display_spatial_h1.v',
        'model/display_spatial_reference.py',
        '02_sim/display_noise/generate_vectors.py',
        '02_sim/display_noise/tb_display_spatial.sv',
        '02_sim/display_noise/run_display_noise.ps1',
        '02_sim/display_noise/vectors_manifest.json',
        '02_sim/display_noise/summarize_results.py',
    }
    normalized_sources={p.replace('\\','/'):digest for p,digest in source_hashes.items()}
    if set(normalized_sources)!=required_sources or any(not (root/p).is_file() or sha(root/p)!=digest for p,digest in normalized_sources.items()):errors.append('Spatial verification source hashes are missing or stale')
    if verification.get('compile_sha256')!=sha(spatial/'compile.log'):errors.append('Spatial verification compile log hash mismatch')
    verified_cases=verification.get('cases',[])
    if len(verified_cases)!=len(SPATIAL_CASES) or {c.get('name') for c in verified_cases}!=SPATIAL_CASES:errors.append('Spatial verification case list is reduced or duplicated')
    verified_cases={c['name']:c for c in verified_cases if c.get('name') in SPATIAL_CASES}
    if manifest.get('edge_threshold')!=16 or manifest.get('reference_sha256')!=sha(root/'model/display_spatial_reference.py') or manifest.get('rtl_sha256')!=sha(root/'01_rtl/imgq_gain_m/main/user_source/hdl_source/a4_display_spatial_h1.v'):errors.append('Spatial reference/current RTL identity mismatch')
    cases=manifest.get('cases',[])
    if len(cases)!=len(SPATIAL_CASES) or {c.get('name') for c in cases}!=SPATIAL_CASES:errors.append('Spatial case list is reduced or duplicated')
    for case in cases:
        if case.get('name') not in SPATIAL_CASES:continue
        if set(case.get('inputs',{}))!={'stim.mem','expected.mem','source.mem'}:errors.append('Spatial case lacks all three vector files: '+case['name'])
        for filename,digest in case.get('inputs',{}).items():
            p=spatial/case['name']/filename
            if not p.resolve().is_relative_to(spatial.resolve()) or not p.is_file() or sha(p)!=digest:errors.append('Spatial vector hash mismatch: '+str(p))
        text=read(spatial/case['name']/'transcript.log')
        expected='PASS pixel oracle WIDTH='+str(case['width'])+' HEIGHT='+str(case['height'])+' cycles='+str(case['cycles'])
        if expected not in text:errors.append('Spatial transcript geometry/cycle count mismatch: '+case['name'])
        verified=verified_cases.get(case['name'],{})
        if verified.get('result')!='PASS' or verified.get('cycles')!=case['cycles'] or verified.get('log_sha256')!=sha(spatial/case['name']/'transcript.log'):errors.append('Spatial verification case identity/hash mismatch: '+case['name'])
        counts=re.search(re.escape(expected)+r' valid=(\d+) sof=(\d+) eol=(\d+) all_markers_and_ENABLE0_checked',text)
        if counts is None or [verified.get(k) for k in ['valid','sof','eol']]!=[int(v) for v in counts.groups()]:errors.append('Spatial verification transaction counts mismatch: '+case['name'])
    if verification.get('total_cycles')!=sum(c.get('cycles',0) for c in verified_cases.values()) or verification.get('total_valid')!=sum(c.get('valid',0) for c in verified_cases.values()):errors.append('Spatial verification total transaction counts mismatch')
    return {'passed':not errors,'errors':errors,'required_spatial_cases':len(SPATIAL_CASES),'tone_input_values':256}

def validate_contract_report(reported, current):
    """Compare the saved contract with a fresh, read-only recomputation."""
    errors=[]
    if not isinstance(reported,dict) or not isinstance(current,dict):
        return {'passed':False,'errors':['Functional contract must be an object']}
    if reported.get('passed') is not True or current.get('passed') is not True:
        errors.append('Functional contract or current source recomputation failed')
    ignored={'generated_utc'}
    left={k:v for k,v in reported.items() if k not in ignored}
    right={k:v for k,v in current.items() if k not in ignored}
    if left!=right:errors.append('Functional contract differs from current read-only source/evidence recomputation')
    return {'passed':not errors,'errors':errors,'scope':'Source and wiring identity only; historical replay is not a real-camera quality gate, and weak spatial texture is not claimed unchanged.'}
def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--after-bitgen',action='store_true'); args=parser.parse_args()
    checks,details,evidence={},{},{}
    def record(p):
        evidence[str(p.relative_to(ROOT))]={'sha256':sha(p)}
        return read(p)
    for p in [RUN/'source_snapshot.json',RUN/'release_gate.json',ROOT/'reports/display_noise_source_scope.json',ROOT/'reports/display_noise_regression.json',ROOT/'reports/baseline_source_snapshot_original.json',ROOT/'reports/baseline_dependency_validation.json',AUDIT/'readonly_verification.json',AUDIT/'readonly_input_hashes.json',CONTEXT/'input_hashes.json',ROOT/'tools/review_display_noise_release.py',ROOT/'tools/audit_display_noise_scope.py',ROOT/'tools/release_audit_config.json',ROOT/'tools/inactive_project_files.json',ROOT/'tools/verify_inactive_project_files.py']:
        record(p)
    record(ROOT/'tools/verify_display_noise_build_strategy.py')
    record(ROOT/'reports/attempt8_spatial_reuse.json')
    record(ROOT/'reports/attempt7_spatial_archive.json')
    snapshot=obj(RUN/'source_snapshot.json')
    strategy_review=validate_build_strategy(require_log=True,snapshot=snapshot)
    checks['exact_documented_synthesis_pack_strategy']=strategy_review['passed']
    details['synthesis_pack_strategy_review']=strategy_review
    checks['frozen_prebuild_inputs_match']=snapshot['passed'] and all(Path(f['path']).is_file() and sha(Path(f['path']))==f['sha256'] for f in snapshot['files'])
    gate_review=validate_gate_evidence(obj(RUN/'release_gate.json'))
    checks['fresh_route_gate']=gate_review['passed']
    details['route_gate_evidence_review']=gate_review
    checks['implementation_no_missing_project_inputs']=all('PRJ-7001' not in read(RUN/name) for name in ['synth.log','place.log','route.log'])
    checks['readonly_input_timing_unchanged']=obj(AUDIT/'readonly_verification.json')['passed']
    checks['baseline_bit_unchanged']=BASEBIT.is_file() and sha(BASEBIT)==BASESHA
    inactive_review=validate_inactive()
    checks['inactive_project_inputs_match_baseline']=inactive_review['passed']
    details['inactive_project_files_review']=inactive_review
    source_scope=obj(ROOT/'reports/display_noise_source_scope.json')
    scope_review=validate_source_scope(source_scope,obj(ROOT/'reports/baseline_source_snapshot_original.json'))
    checks['three_display_source_scope']=scope_review['passed']
    details['display_source_scope_review']=scope_review
    cap=ROOT/'tools/physical_capacity'
    command=[sys.executable,str(cap/'validate_device_capacity.py'),'--chip',str(cap/'ph1_35p_device_dump.txt_chip'),'--routing',str(cap/'ph1_35p_device_dump.txt_connmngr'),'--tile-report',str(cap/'report_named_tiles.log'),'--datasheet',str(cap/'DS1300_logic_and_dram_excerpt.txt'),'--resource-report',str(cap/'physical_device_resources.txt'),'--expected-cells',str(AUDIT/'expected_slice_cells.tsv'),'--expected-log',str(AUDIT/'console_readonly.log'),'--placements',str(AUDIT/'readonly.sites.tsv'),'--out',str(AUDIT/'physical_capacity')]
    capacity=subprocess.run(command,capture_output=True,text=True)
    (AUDIT/'physical_capacity_console.log').write_text(capacity.stdout+capacity.stderr,encoding='utf-8')
    checks['complete_compatible_unique_placed_capacity']=capacity.returncode==0
    reviewed=strict.run(AUDIT)
    put(AUDIT/'strict_independent_release_review.json',reviewed)
    checks['strict_area_sites_design_plb_drc_timing']=all(item['passed'] for k,item in reviewed['checks'].items() if k!='check_io')
    details['raw_check_design']=reviewed['checks']['check_design']
    details['raw_check_io']=reviewed['checks']['check_io']
    rawlog=record(AUDIT/'console_readonly.log')
    contextlog=record(CONTEXT/'console_standard_context.log')
    checks['standard_context_inputs_unchanged']=hashes_match(obj(CONTEXT/'input_hashes.json'))
    adverse=lambda text:re.findall(r'^.*(?:ERROR:|CRITICAL-WARNING:|FATAL:).*$',text,re.M)
    details['standard_context_adverse_diagnostics']=adverse(contextlog)
    checks['standard_context_only_known_raw_io_diagnostic']=('STANDARD_CONTEXT_READONLY_PASS' in contextlog and all('USR-8450' in line and 'unconstraint IOs(10 out of 39)' in line for line in adverse(contextlog)))
    io_window=reviewed['checks']['check_io']['window']
    checks['raw_io_only_known_or_clean']=(reviewed['checks']['check_io']['passed'] or (sum('USR-8450' in x and 'unconstraint IOs(10 out of 39)' in x for x in io_window)==1 and all('USR-8450' in line for line in adverse('\n'.join(io_window))) and 'CHECK_IO_STATUS=0 REASON=' in rawlog))
    currentpins=pins(record(AUDIT/'readonly.area')); standardpins=pins(record(CONTEXT/'standard.area'))
    baselinepins=pins(read(BASE/'02_sim/pcb_compat_readonly/readonly.area'))
    checks['all_79_physical_io_locations_match_baseline_context']=(len(currentpins)==79 and currentpins==standardpins==baselinepins and len({p['location'] for p in currentpins.values()})==79)
    assignments=re.findall(r'set_pin_assignment\s*\{\s*(.*?)\s*\}\s*\{\s*LOCATION\s*=\s*([^;\s]+)',read(ROOT/'04_pin/pin.adc'))
    checks['ordinary_adc_locations_match']=len(assignments)==30 and all(currentpins.get(p,{}).get('location')==loc for p,loc in assignments)
    sites=list(csv.DictReader(read(AUDIT/'readonly.sites.tsv').splitlines(),delimiter='\t'))
    mipi=[r for r in sites if r['ref_name']=='PH1P_PHY_MIPIIO_RX']
    pads=[r for r in sites if r['ref_name'] in {'PH1P_PHY_HD_PAD','PH1P_PHY_HR_PAD_V2','PH1P_PHY_DDRPHY_PAD_V2'}]
    checks['all_79_pad_sites_placed_unique']=len(pads)==79 and all(p['is_placed']=='1' for p in pads) and len({(p['col'],p['row'],p['offset']) for p in pads})==79
    hdl=ROOT/'01_rtl/imgq_gain_m/main/user_source/hdl_source'
    top=read(hdl/'design_top_wrapper.v'); wrapper=read(hdl/'mipi_dphy_rx/ph1p_mipiio_rx_wrapper.v')
    checks['hard_dphy0_source_binding_and_placement']=(len(mipi)==1 and mipi[0]['is_placed']=='1' and (mipi[0]['col'],mipi[0]['row'],mipi[0]['offset'])==('47','0','0') and bool(re.search(r'\.DPHY_RX_LOCATION\s*\(\s*"DPHY0"\s*\)',top)) and all(re.search(r'\.'+port+r'\s*\(\s*'+port+r'\s*\)',top) for port in ['IO_rx_clk_pad_n','IO_rx_clk_pad_p','IO_rx_data_pad_n','IO_rx_data_pad_p']) and all(re.search(r'\.'+internal+r'\s*\(\s*'+port+r'\s*\)',wrapper) for internal,port in [('io_clk_pad_n','IO_rx_clk_pad_n'),('io_clk_pad_p','IO_rx_clk_pad_p'),('io_data_pad_n','IO_rx_data_pad_n'),('io_data_pad_p','IO_rx_data_pad_p')]))
    newcheck=record(AUDIT/'readonly.check'); oldcheck=read(BASE/'02_sim/pcb_compat_readonly/readonly.check')
    ca,cb=categories(oldcheck),categories(newcheck)
    details['timing_check_category_changes']={k:[ca.get(k),cb.get(k)] for k in ca.keys()|cb.keys() if ca.get(k)!=cb.get(k)}
    checks['no_new_timing_check_category_or_increased_warning_count']=bool(cb) and ca.keys()==cb.keys() and all(v<=ca[k] for k,v in cb.items())
    skew=record(AUDIT/'readonly.skew')
    skewrows=re.findall(r'^\s*(slow_\w+|fast_\w+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s*$',skew,re.M)
    baserows=re.findall(r'^\s*(slow_\w+|fast_\w+)\s+([-\d.]+)\s+([-\d.]+)\s+([-\d.]+)\s*$',read(BASE/'02_sim/pcb_compat_readonly/readonly.skew'),re.M)
    checks['fifo_mailbox_skew_constraints_retained_all_pass']=bool(skewrows) and len(skewrows)==len(baserows) and all(float(row[3])>=0 for row in skewrows)
    clocks=record(AUDIT/'readonly.clocks')
    checks['ddr_hdmi_clocks_retained']=any('7.500' in x and 'u_ddr2/usr_clk' in x for x in clocks.splitlines()) and any('13.333' in x and 'HDMI_PIXEL_CLK' in x for x in clocks.splitlines())
    checks['tracked_clock_diagnostics_absent']=not re.search(r'RTCLK-5078|USR-6113',rawlog+contextlog)
    regression=obj(ROOT/'reports/display_noise_regression.json')
    chain_review=validate_equivalence_chain()
    chain_binding=validate_equivalence_binding(regression,chain_review)
    checks['exact_spatial_implementation_equivalence_chain']=(chain_review['passed'] and chain_binding['passed'] and obj(ROOT/'reports/display_equivalence_chain.json')==chain_review)
    details['implementation_equivalence_chain_review']=chain_review
    details['implementation_equivalence_chain_binding']=chain_binding
    for path,digest in chain_review['evidence'].items():
        evidence[Path(path).relative_to(ROOT).as_posix()]={'sha256':digest}
    regression_review=validate_regression(regression,snapshot=snapshot)
    checks['required_rtl_regression']=regression_review['passed']
    details['regression_evidence_review']=regression_review
    algorithm_review=validate_algorithm_evidence()
    checks['tone_and_spatial_reference_rtl_evidence']=algorithm_review['passed']
    details['tone_spatial_evidence_review']=algorithm_review
    from verify_display_functional_contract import verify as recompute_contract
    contract_review=validate_contract_report(obj(ROOT/'reports/display_functional_contract.json'),recompute_contract(ROOT,RUN))
    checks['fresh_functional_source_contract']=contract_review['passed']
    details['functional_source_contract_review']=contract_review
    details['cdc_ddr_fifo_scope']='Display-only causal spatial line memory is authorized; no new clock domain or DDR datapath. Existing result mailbox and FIFO/DDR constraint scope is retained, source equality outside three reviewed display modules is checked. Fresh clock/check/skew and display transaction tests are required. This is not a new exhaustive asynchronous CDC or DDR electrical proof.'
    details['raw_io_interpretation']='Raw USR-8450 remains an adverse diagnostic; catch=0 is not clean. Independent source binding, all physical pads, baseline/context pin identity and standard bitgen without unconstr_io override are required. No claim of a vendor bug.'
    if args.after_bitgen:
        log=record(CONTEXT/'console_bitgen.log')
        script=record(CONTEXT/'bitgen.tcl')
        checks['standard_bitgen_no_override_and_clean_success']=('DISPLAY_NOISE_BITGEN_PASS:' in log and not re.search(r'ERROR:|FATAL:|CRITICAL-WARNING:|DISPLAY_NOISE_BITGEN_FAIL',log) and not re.search(r'(?im)^\s*set_param\b|unconstr_io\s+on',script) and BIT.is_file() and BIT.stat().st_size>1000000)
        details['artifact']={'path':str(BIT),'sha256':sha(BIT) if BIT.is_file() else None,'bytes':BIT.stat().st_size if BIT.is_file() else None}
    result={'passed':all(checks.values()),'checks':checks,'details':details,'evidence':evidence,'hardware_status':'NOT_RUN','scope':'Independent display-noise diagnostic release. Raw check_design/check_io diagnostics are retained. Fixed recognition tone and non-display protocols must match the signed baseline.'}
    put(ROOT/'reports'/('display_noise_release.json' if args.after_bitgen else 'display_noise_prebitgen_review.json'),result)
    print(json.dumps({'passed':result['passed'],'checks':checks},indent=2)); return int(not result['passed'])
if __name__=='__main__': raise SystemExit(main())
