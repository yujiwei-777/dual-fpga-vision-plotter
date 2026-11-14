"""Fail-closed secondary signoff bound to build_airwalk.py and a selected freeze.

prepare/static never call TD. Route, read-only import and bitgen are separate
explicit actions. Historical designs provide query/validator source only.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse, importlib.util, json, re, shutil, subprocess, sys
sys.dont_write_bytecode = True

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

build = module('airwalk_signoff_build', TOOLS/'build_airwalk.py').m
legacy = module('airwalk_retained_signoff', TOOLS/'signoff_doc_key1_confirm.py')
sha, load, put, require = build.sha, build.load, build.put, build.require
CONFIG = build.CONFIG['secondary']
NAME = CONFIG['name']
ARTIFACT = 'dual_fpga_secondary_20261113_pcb_paper_load_stroke_cont_diagnostic.bit'
PRODUCTION = ('01_rtl/', 'shared/', '04_pin/', 'main/', 'model/')
CHECKERS = ['Pin Swap', 'Net Connection', 'Lut Bridge', 'Multi Drive',
            'Clock Status', 'Abnormal Path', 'Route Region', 'Bound']

def read(path):
    return Path(path).read_text(encoding='utf-8-sig', errors='replace')

def evidence(path):
    p = Path(path).resolve()
    return dict(path=str(p), sha256=sha(p))

def validate(run):
    run, plan = build.validate(run, 'secondary')
    require(Path(plan['source_root']).resolve() == ROOT, 'Wrong source root in selected freeze')
    require((build.BASE/CONFIG['source']).resolve() == ROOT, 'build_airwalk source configuration differs')
    for rel, row in load(run/'SOURCE_MANIFEST.json')['files'].items():
        if rel.startswith(PRODUCTION):
            require(sha(ROOT/rel) == row['sha256'], 'Current production differs from selected freeze: '+rel)
    return run, plan

def report_dir(run):
    return ROOT/'reports/airwalk_signoff'/Path(run).name

def configure(run):
    run, plan = validate(run)
    legacy.ROOT, legacy.BOARD, legacy.NAME = ROOT, 'secondary', NAME
    legacy.REPORT = report_dir(run)
    legacy.TD = build.TD
    legacy.validate = validate
    legacy.metrics = lambda directory, routed: build.helper('secondary').metrics(directory, routed)
    return run, plan

def tool_inventory(run):
    return [evidence(p) for p in [Path(__file__), TOOLS/'build_airwalk.py', TOOLS/'build_opt.py',
        TOOLS/'signoff_doc_key1_confirm.py', TOOLS/'doc_key1_confirm_strict_checks.py',
        run/'tools/td_release_audit.py', run/'tools/binary_source_audit_config.json',
        run/'tools/physical_capacity/validate_device_capacity.py']]

def baseline_identity(run):
    path = ROOT/'reports/r4_integration/BASELINE_IDENTITY.json'
    value = load(path)
    control = Path(CONFIG['frozen']).resolve()
    manifest = value['baseline_source_freeze']
    require(Path(manifest['path']).resolve()==control/'SOURCE_MANIFEST.json' and
        sha(manifest['path'])==manifest['sha256'], 'Immediate control manifest differs from identity/configuration')
    bit = value['baseline_bit']
    require(Path(bit['path']).is_file() and sha(bit['path'])==bit['sha256'] and
        Path(bit['path']).stat().st_size>1000000, 'Immediate control diagnostic bit drift')
    original = Path(value['baseline_root']).resolve()
    rows = load(control/'SOURCE_MANIFEST.json')['files']
    verified = {}
    for rel,row in rows.items():
        require(sha(control/rel)==row['sha256'], 'Immediate frozen control input drift: '+rel)
        if rel.startswith(PRODUCTION):
            require(sha(original/rel)==row['sha256'], 'Immediate D: control production drift: '+rel)
            verified[rel] = row['sha256']
    require(verified, 'No immediate control production files')
    plan = load(run/'BUILD_PLAN.json')
    return dict(identity_record=evidence(path), immediate_physical_source_control=dict(
        root=str(original), bit=evidence(bit['path']), source_manifest=evidence(manifest['path']),
        checked_production_files=len(verified), production_sha256=verified),
        older_validator_trust_root=dict(root=str(build.BASE/CONFIG['baseline']),
            bit=plan['scope']['control_bit'], scope='Retained validator inventory only; not the immediate physical/source control.'))

def static_review(run):
    run, plan = configure(run)
    frozen = load(run/'SOURCE_MANIFEST.json')['files']
    control = Path(CONFIG['frozen']).resolve()
    baseline = load(control/'SOURCE_MANIFEST.json')['files']
    protected = ['04_pin/apply_reset_exceptions.tcl', '04_pin/apply_cdc_exceptions.tcl',
        'main/user_source/hdl_source/reset_sync.v', '01_rtl/hxa_ddr_store.v',
        '01_rtl/secondary_ddr_wrapper.v', '01_rtl/vision_pixel_reader.v',
        'shared/rtl/hxa_packet_rx_fifo4.v']
    protected += [p for p in frozen if p.startswith('main/user_source/hdl_source/ph1p35_ddr/')]
    protected += [p for p in frozen if p.startswith('main/user_source/hdl_source/ethernet/')]
    rows = {}
    for rel in sorted(set(protected)):
        require(rel in frozen and rel in baseline, 'Missing protected source: '+rel)
        digest = frozen[rel]['sha256']
        require(sha(control/rel) == baseline[rel]['sha256'] == digest == sha(run/rel),
            'Protected CDC/FIFO/DDR source differs from selected control: '+rel)
        rows[rel] = digest
    before = read(control/'04_pin/timing.sdc').replace('{key1_meta}', '{u_key1_action/key_meta}')
    require(before == read(run/'04_pin/timing.sdc'), 'Timing constraints changed beyond reviewed KEY1 first-stage retarget')
    top = read(run/'01_rtl/secondary_top.v')
    require('secondary_key1_action_ctrl' in top and 'u_key1_action' in top and
        'key_meta<=key_n;key_sync<=key_meta' in top.replace(' ', ''), 'KEY1 first-stage synchronizer missing')
    mailbox = read(run/'01_rtl/hxa_ddr_store.v')
    tokens = ['wreq_sync<={wreq_sync[0],wreq}', 'rreq_sync<={rreq_sync[0],rreq}',
        'wack_sync<={wack_sync[0],wack}', 'rack_sync<={rack_sync[0],rack}',
        'rdata_hold<=app_rd_data', 'command_accepted||(app_en&&app_rdy)',
        'data_accepted||(app_wdf_wren&&app_wdf_rdy)']
    require(all(t in mailbox.replace(' ', '') for t in tokens), 'Held-data/two-stage mailbox structure missing')
    fifo = read(run/'shared/rtl/hxa_packet_rx_fifo4.v')
    require('fifo_count==3\'d4' in fifo and 'ctrl_count!=2||ctrl_pop' in fifo and
        'pop_event' in fifo and 'data_head_ready' in fifo, 'Packet FIFO capacity/commit structure missing')
    closure = module('airwalk_source_audit', run/'tools/td_release_audit.py').collect(argparse.Namespace(
        root=run, run=run/'runs/phy_1', name=NAME, al=None,
        config=run/'tools/binary_source_audit_config.json', extra=[]))
    require(closure['passed'], 'Active source closure failed: '+str(closure['errors']))
    snapshot = load(run/'runs/phy_1/source_snapshot.json')
    require(closure['manifest_sha256'] == snapshot['manifest_sha256'], 'Active source closure differs from prebuild snapshot')
    result = dict(status='STATIC_SOURCES_VERIFIED_NOT_ROUTED', passed_source_checks=True,
        generated_utc=datetime.now(timezone.utc).isoformat(), run=str(run), source_manifest=evidence(run/'SOURCE_MANIFEST.json'),
        active_closure_digest=closure['manifest_sha256'], protected_source_sha256=rows,
        reviewed_constraint_change='Only KEY1 first synchronizer target key1_meta -> u_key1_action/key_meta.',
        cdc='Reset and CDC mapping verifier bytes unchanged; actual mapped endpoint proof is mandatory after route.',
        fifo='Packet DATA=4/CONTROL=2 single-clock committed-head FIFO unchanged; vendor DDR FIFOs unchanged.',
        ddr='Two-stage toggle control and held request/return mailbox unchanged; command/data ACK requires both accepts.',
        baseline_identity=baseline_identity(run), toolchain=tool_inventory(run), bitgen_allowed=False, hardware_status='NOT_RUN',
        limitations=['Source audit only; no mapped CDC, DDR calibration, MTBF, physical capacity or timing acceptance.'])
    put(report_dir(run)/'STATIC_AUDIT.json', result)
    return result

def readonly_script(run, out):
    template = Path(CONFIG['frozen'])/'signoff/readonly/readonly_reimport.tcl'
    require(template.is_file(), 'Successful control read-only query template missing')
    text = read(template)
    text, n = re.subn(r'^set build \{[^\r\n]+\}', 'set build {'+(run/'runs/phy_1').as_posix()+'}', text, count=1, flags=re.M)
    require(n == 1, 'Template build binding absent')
    text, n = re.subn(r'^set audit \{[^\r\n]+\}', 'set audit {'+out.as_posix()+'}', text, count=1, flags=re.M)
    require(n == 1, 'Template audit binding absent')
    require(not re.search(r'^\s*(?:bitgen|commit_param|clear_sdc|read_sdc|export_db|save_project|place|route|optimize\w*|secondary_apply\w*)\b', text, re.M), 'Read-only template contains a mutation command')
    return text

def prepare(run):
    run, plan = configure(run)
    static = static_review(run)
    out = report_dir(run)
    out.mkdir(parents=True, exist_ok=True)
    (out/'PREPARED_READONLY.tcl').write_text(readonly_script(run, run/'signoff/readonly'), encoding='utf-8')
    (out/'PREPARED_BITGEN.tcl').write_text(bitgen_script(run, run/'signoff/bitgen', run/'signoff/bitgen'/ARTIFACT), encoding='utf-8')
    value = dict(status='PREPARED_NOT_EXECUTED', run=str(run), source_manifest=static['source_manifest'],
        readonly_template=evidence(out/'PREPARED_READONLY.tcl'), bitgen_template=evidence(out/'PREPARED_BITGEN.tcl'),
        pending=['Fresh successful syn/place/route invocation receipts', 'Current routed timing/resource gate',
            'Final eight named DRC checkers', 'Read-only DB import and unchanged AL/DB/source hashes',
            'Fresh placed-site device capacity and mapped CDC/reset/DDR proof',
            'Source-bound functional gate including preserved/document-integrated/total-ACK receipts'],
        artifact_name=ARTIFACT, bitgen_allowed=False, hardware_status='NOT_RUN')
    put(out/'PREPARATION.json', value)
    return value

def route_drc(text):
    starts = list(re.finditer(r'^RUN-1001 : Stage (\d+)\.(\d+) \| Run Pin Swap Checker\s*$', text, re.M))
    require(starts, 'No final named route DRC group')
    last = starts[-1]
    major = last[1]
    section = text[last.start():]
    rows = []
    for name in CHECKERS:
        begin = list(re.finditer(r'^RUN-1001 : Stage '+major+r'\.(\d+) \| Run '+re.escape(name)+r' Checker\s*$', section, re.M))
        end = list(re.finditer(r'^RUN-1001 : End Stage '+major+r'\.(\d+) \| Run '+re.escape(name)+r' Checker;.*$', section, re.M))
        require(len(begin)==len(end)==1 and begin[0][1]==end[0][1] and begin[0].end()<end[0].start(), 'Incomplete/duplicate final DRC checker: '+name)
        block = section[begin[0].end():end[0].start()]
        require(not re.search(r'\b(?:ERROR|FATAL|FAIL(?:ED|URE)?|CRITICAL-WARNING)\b', block, re.I), 'Adverse final DRC checker: '+name)
        rows.append(dict(stage=major+'.'+begin[0][1], checker=name, completed=True))
    require([int(r['stage'].split('.')[1]) for r in rows] == list(range(int(last[2]), int(last[2])+8)), 'Final DRC group is not eight ordered named checkers')
    return dict(passed=True, final_stage=major, checkers=rows)

SLICEL_WARNING = 'PHY-7027 CRITICAL-WARNING: Base field: model type (SLICEL) execeed the design limits.'

def implementation_warnings(run, physical=None):
    """Preserve diagnostics; logical SLICEL warnings need current site proof."""
    control = Path(CONFIG['frozen'])
    warnings, blockers, logs = [], [], []
    for phase in ['syn','place','route']:
        path = run/'logs'/(phase+'.log')
        if not path.is_file():
            continue
        text = read(path)
        logs.append(evidence(path))
        previous = read(control/'logs'/(phase+'.log'))
        stage = ''
        for number,line in enumerate(text.splitlines(),1):
            if re.match(r'^(?:PHY|SYN|RUN)-1001 : Stage ',line):
                stage = line
            if 'PHY-9002' in line:
                blockers.append(dict(phase=phase,line=number,text=line,reason='Placement failure is never waived.'))
            match = re.match(r'^([A-Z]+-\d+)\s+(CRITICAL-WARNING|WARNING):?\s*(.*)$',line)
            if not match:
                continue
            row = dict(phase=phase,line=number,code=match[1],severity=match[2],stage=stage,text=line,
                disposition='RECORDED_WARNING')
            if match[2]=='CRITICAL-WARNING':
                if line==SLICEL_WARNING:
                    row['disposition']='REQUIRES_CURRENT_COMPLETE_UNIQUE_COMPATIBLE_SLICE_SITE_PROOF'
                    row['same_text_seen_in_selected_control']=line in previous.splitlines()
                elif match[1]=='SYN-6024' and line in previous.splitlines() and 'u_rgmii/rgmii_txc_ddr' in line:
                    rel = 'main/user_source/hdl_source/ethernet/rgmii_interface.v'
                    require(sha(run/rel)==sha(control/rel), 'Retained RGMII ODDR critical warning source changed')
                    row['disposition']='RETAINED_UNCHANGED_RGMII_ODDR_WARNING'
                    row['unchanged_source']=dict(relative=rel,sha256=sha(run/rel))
                else:
                    row['disposition']='BLOCKED_UNREVIEWED_CRITICAL_WARNING'
                    blockers.append(row)
            warnings.append(row)
    site_path = run/'signoff/readonly/physical_capacity/physical_capacity_validation.json'
    site_ok = False
    site_evidence = None
    if physical is not None and site_path.is_file():
        proof = load(site_path)
        count = physical.get('checks',{}).get('area',{}).get('resources',{}).get('slice',{}).get('used',-1)
        site_ok = (physical.get('checks',{}).get('placed_sites',{}).get('passed') is True and
            physical.get('checks',{}).get('readonly',{}).get('passed') is True and
            proof.get('passed') is True and not proof.get('errors') and count>0 and
            proof.get('expected_slices')==proof.get('placed_compatible_unique_slices')==count and
            proof.get('official_resource_cross_check',{}).get('slots_from_named_device_tiles')==21216 and
            set(proof.get('inputs',{}))=={'chip','routing','tile_report','datasheet','expected_cells','expected_log','resource_report','placements'})
        for row in proof.get('inputs',{}).values():
            site_ok = site_ok and Path(row['path']).is_file() and sha(row['path'])==row['sha256']
        site_evidence=evidence(site_path)
    pending=[]
    for row in warnings:
        if row['text']==SLICEL_WARNING:
            if site_ok:
                row['disposition']='RETAINED_LOGICAL_SLICEL_WARNING_WITH_CURRENT_COMPLETE_SITE_PROOF'
                row['physical_capacity_evidence']=site_evidence
            else:
                pending.append(row)
    result = dict(status='IMPLEMENTATION_WARNINGS_REVIEW_REQUIRED' if blockers or pending else 'WARNINGS_REVIEWED_WITH_EVIDENCE',
        passed=not blockers and not pending, policy_blockers=blockers, pending_site_proof=pending,
        warnings=warnings, warning_count=len(warnings),
        critical_warning_count=sum(row['severity']=='CRITICAL-WARNING' for row in warnings),
        logs=logs, current_complete_site_proof=site_evidence if site_ok else None,
        note='Warnings remain present. Exit code and intermediate legalization summaries do not replace final complete site/capacity proof.',
        bitgen_allowed=False, hardware_status='NOT_RUN')
    return result

def route_gate(run):
    run, plan = configure(run)
    phy = run/'runs/phy_1'
    require((phy/'.opt_route.end.f').is_file() and (phy/(NAME+'_pr.db')).is_file(), 'Actual completed route required')
    audit = module('airwalk_route_gate', run/'tools/td_release_audit.py')
    output = run/'RELEASE_GATE.json'
    args = argparse.Namespace(root=run, run=phy, name=NAME, al=None,
        config=run/'tools/binary_source_audit_config.json', extra=[], snapshot=phy/'source_snapshot.json',
        supplemental=[], syn_run=run/'runs/syn_1', log=[run/'logs'/str(p+'.log') for p in ['syn','place','route']], output=output)
    require(audit.gate(args)==0, 'Current route build gate failed')
    receipts = []
    for phase in ['syn','place','route']:
        receipt = load(run/'logs'/(phase+'.json'))
        log = run/'logs'/(phase+'.log')
        require(receipt['status']=='PASS_TOOL_INVOCATION' and receipt['log_sha256']==sha(log), 'Implementation invocation receipt mismatch: '+phase)
        require(receipt['source_manifest_sha256']==plan['source_manifest_sha256'], 'Implementation receipt belongs to another freeze')
        receipts.append(evidence(run/'logs'/(phase+'.json')))
    drc = route_drc(read(run/'logs/route.log'))
    warnings = implementation_warnings(run)
    require(not warnings['policy_blockers'], 'Unreviewed critical warning or PHY-9002 blocks implementation')
    result = dict(status='PASS_CURRENT_ROUTE_GATE', route_gate=evidence(output), final_named_drc=drc,
        implementation_warnings=warnings,
        implementation_receipts=receipts, source_manifest=evidence(run/'SOURCE_MANIFEST.json'),
        routed_database=evidence(phy/(NAME+'_pr.db')), bitgen_allowed=False, hardware_status='NOT_RUN')
    put(report_dir(run)/'ROUTE_GATE_REVIEW.json', result)
    return result

def physical_review(run):
    run, plan = configure(run)
    static = static_review(run)
    gate = route_gate(run)
    physical = legacy.physical_review(run)
    warnings = implementation_warnings(run, physical)
    warning_path = report_dir(run)/'IMPLEMENTATION_WARNING_REVIEW.json'
    put(warning_path,warnings)
    physical['checks']['implementation_warnings']=dict(passed=warnings['passed'],
        errors=warnings['policy_blockers']+warnings['pending_site_proof'], review=evidence(warning_path))
    physical['retained_implementation_warnings']=warnings['warnings']
    physical['passed']=physical['passed'] and warnings['passed']
    physical['status']='PASS_CURRENT_PHYSICAL_SIGNOFF' if physical['passed'] else 'PHYSICAL_REVIEW_REQUIRED'
    put(run/'signoff/readonly/PHYSICAL_REVIEW.json',physical)
    put(report_dir(run)/'PHYSICAL_REVIEW.json',physical)
    require(physical['passed'], 'Current physical review failed')
    result = dict(status='PASS_CURRENT_IMPLEMENTATION_SIGNOFF', static_audit=evidence(report_dir(run)/'STATIC_AUDIT.json'),
        route_review=evidence(report_dir(run)/'ROUTE_GATE_REVIEW.json'),
        physical_review=evidence(run/'signoff/readonly/PHYSICAL_REVIEW.json'),
        warning_review=evidence(warning_path), retained_critical_warnings=[row for row in warnings['warnings'] if row['severity']=='CRITICAL-WARNING'],
        source_manifest=evidence(run/'SOURCE_MANIFEST.json'), routed_database=gate['routed_database'],
        bitgen_allowed=False, hardware_status='NOT_RUN')
    put(report_dir(run)/'IMPLEMENTATION_SIGNOFF.json', result)
    return result

def prepare_readonly(run):
    run, plan = configure(run)
    route_gate(run)
    out = legacy.prepare_readonly(run)
    # Use the successful secondary query context and fresh run/output bindings.
    (out/'readonly_reimport.tcl').write_text(readonly_script(run, out), encoding='utf-8')
    put(out/'PREPARE.json', dict(status='PREPARED_NOT_EXECUTED', script=evidence(out/'readonly_reimport.tcl'),
        source_manifest_sha256=plan['source_manifest_sha256'], readonly=True, bitgen_invoked=False))
    return out

def run_readonly(run):
    run, plan = configure(run)
    out = run/'signoff/readonly'
    if not out.exists():
        prepare_readonly(run)
    log = out/'console_readonly.log'
    require(not log.exists(), 'Refusing read-only log overwrite')
    inputs = load(out/'readonly_input_hashes.json')
    require(inputs == legacy.immutable_inputs(run), 'Prepared read-only inputs changed')
    with log.open('xb') as stream:
        cp = subprocess.run([str(build.TD), 'readonly_reimport.tcl'], cwd=out, stdout=stream, stderr=subprocess.STDOUT)
    unchanged = inputs == legacy.immutable_inputs(run)
    text = read(log)
    put(out/'readonly_verification.json', dict(status='CURRENT_QUERY_COMPLETE_NOT_YET_PHYSICAL_ACCEPTANCE',
        exit_code=cp.returncode, inputs_unchanged=unchanged, inputs=inputs, script=evidence(out/'readonly_reimport.tcl'),
        log=evidence(log), source_manifest_sha256=plan['source_manifest_sha256'],
        routed_database_sha256=sha(run/'runs/phy_1'/(NAME+'_pr.db')), hardware_status='NOT_RUN'))
    require(cp.returncode==0 and unchanged and text.count('TD_READONLY_REIMPORT_PASS')==1 and
        'TD_READONLY_REIMPORT_FAIL' not in text, 'Current read-only import failed')
    return physical_review(run)

def bitgen_script(run, out, bit):
    values = dict(PHY=(run/'runs/phy_1').as_posix(), OUT=out.as_posix(), NAME=NAME,
                  BIT=bit.as_posix(), BID=bit.with_suffix('.bid').as_posix())
    text = r'''# Standard diagnostic bitgen. No constraint or IO overrides.
set build {@PHY@}
set audit {@OUT@}
set name {@NAME@}
set bit {@BIT@}
set bid {@BID@}
cd $build
if {[file exists $bit] || [file exists $bid]} {error "Refusing existing output"}
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project "$build/$name.al" -noanalyze
    import_db "$build/${name}_pr.db"
    update_timing -mode final
    report_timing_status -file "$audit/pre_bitgen.ts"
    report_timing_summary -file "$audit/pre_bitgen.timing"
    check_timing -verbose -file "$audit/pre_bitgen.check"
    report_area -io_info -file "$audit/pre_bitgen.area"
    commit_param -step bitgen
    bitgen -bit $bit
    if {![file exists $bit] || [file size $bit] < 1000000} {error "Missing/truncated bit"}
    export_bid $bid
    export_bitgen_param -file "$audit/checked_bitgen_param.f"
    puts AIRWALK_SECONDARY_BITGEN_PASS
} reason]} {
    puts "AIRWALK_SECONDARY_BITGEN_FAIL: $reason"
    exit 1
}
exit 0
'''
    for key, value in values.items():
        text = text.replace('@'+key+'@', value)
    require(not re.search(r'^\s*set_param\b|unconstr_io\s+on', text, re.M|re.I), 'Nonstandard bitgen override prohibited')
    return text

def receipt_evidence(run, path):
    """Re-read actual receipt trees, their source pins and completion logs."""
    path = Path(path).resolve()
    require(path.is_relative_to(ROOT) and path.is_file(), 'Current report must be inside candidate')
    require(load(path).get('status','').startswith('PASS'), 'Behavior report is not PASS: '+str(path))
    frozen = load(run/'SOURCE_MANIFEST.json')['files']
    sources, logs, receipts = {}, {}, {}
    maps = {'source_hashes','source_sha256','input_hashes','tested_inputs','source_before',
            'production_inputs','bound_current_production_sources'}
    inventory_only = {'production_inputs','bound_current_production_sources'}
    def pin_input(name, digest, tested):
        if isinstance(digest,dict):
            digest = digest.get('sha256')
        if not isinstance(digest,str) or not re.fullmatch('[A-Fa-f0-9]{64}', digest):
            return
        p = Path(name)
        if not p.is_absolute():
            p = ROOT/p
        require(p.is_file() and sha(p)==digest.upper(), 'Behavior input drift: '+str(p))
        p = p.resolve()
        if p.is_relative_to(ROOT):
            rel = p.relative_to(ROOT).as_posix()
            if rel.startswith(PRODUCTION):
                require(rel in frozen and sha(run/rel)==frozen[rel]['sha256']==digest.upper(), 'Behavior source differs from selected freeze: '+rel)
                if tested:
                    sources[rel] = digest.upper()
    def check_log(p, digest, command=()):
        p = Path(p).resolve()
        require(p.is_relative_to(ROOT) and p.is_file() and digest and sha(p)==digest.upper(), 'Behavior log missing/hash drift: '+str(p))
        text = read(p)
        require(not re.search(r'\*\*\s+(?:Error|Fatal):|Traceback \(most recent call last\)|(?:^|\n)(?:# )?Errors:\s*[1-9]\d*', text), 'Behavior log contains errors: '+str(p))
        markers = [line.lstrip('# ').strip() for line in text.splitlines()
            if re.match(r'(?:PASS\b|[A-Z][A-Z0-9_]*PASS\b)', line.lstrip('# ').strip())]
        is_sim = 'simulation' in p.name.lower() or any('vsim' in str(x).lower() for x in command) or 'run -all' in text
        require(not is_sim or markers, 'Simulation completion marker absent: '+str(p))
        if markers:
            logs[str(p)] = dict(path=str(p), sha256=sha(p), pass_marker=markers[0], observed_markers=markers)
    def visit(p, expected=None):
        p = Path(p).resolve()
        require(p.is_relative_to(ROOT) and p.is_file(), 'Behavior child receipt outside current tree/missing: '+str(p))
        if expected:
            require(sha(p)==expected.upper(), 'Behavior child receipt drift: '+str(p))
        if str(p) in receipts:
            return
        value = load(p)
        require(isinstance(value,dict) and value.get('status','').startswith('PASS'), 'Behavior child is not PASS: '+str(p))
        receipts[str(p)] = evidence(p)
        walk(value)
    def walk(value):
        if isinstance(value,list):
            for row in value:
                walk(row)
        elif isinstance(value,dict):
            if 'source_drift' in value:
                require(not value['source_drift'], 'Behavior source drift recorded')
            # Application samples also have statuses such as "confirmed".
            # Require PASS on execution/source receipts, not on sample labels.
            if 'status' in value and any(k in value for k in ('command','log','source_drift','source_hashes')):
                require(str(value['status']).startswith('PASS'), 'Non-PASS nested behavior result: '+str(value['status']))
            for key in maps:
                mapping = value.get(key)
                if isinstance(mapping,dict):
                    for name,digest in mapping.items():
                        pin_input(name,digest,key not in inventory_only)
            if isinstance(value.get('log'),str):
                check_log(value['log'], value.get('log_sha256') or value.get('sha256'), value.get('command',value.get('argv',())))
            elif isinstance(value.get('log'),dict) and 'path' in value['log']:
                row = value['log']
                check_log(row['path'],row.get('sha256'),value.get('command',()))
            if isinstance(value.get('path'),str) and value['path'].endswith('.log') and value.get('sha256'):
                check_log(value['path'],value['sha256'],value.get('command',()))
            for key in ['receipts','reused_fresh_results','reused_current_results']:
                for row in value.get(key,[]) if isinstance(value.get(key),list) else []:
                    visit(row['path'],row.get('sha256'))
            for key in ['report','result','results','receipt']:
                row = value.get(key)
                if isinstance(row,str) and row.endswith('.json') and Path(row).is_file():
                    visit(row)
            for key,row in value.items():
                if key not in maps and key not in {'receipts','reused_fresh_results','reused_current_results'}:
                    if isinstance(row,(dict,list)):
                        walk(row)
    visit(path)
    require(sources and logs, 'No actual current source/marker evidence in '+str(path))
    return dict(path=str(path), sha256=sha(path), source_sha256=sources,
        logs=list(logs.values()), checked_receipts=list(receipts.values()))

def make_functional_gate(run, entries):
    run, plan = validate(run)
    groups = {}
    for entry in entries:
        name, separator, value = entry.partition('=')
        require(separator and name not in groups, 'Use distinct --evidence group=absolute_report.json')
        groups[name] = receipt_evidence(run, Path(value))
    require(set(groups) >= {'preserved','document_integrated','doc_total_ack'}, 'Need preserved/document_integrated/doc_total_ack groups')
    value = dict(status='PASS_CURRENT_FUNCTIONAL_GATE', source_manifest_sha256=plan['source_manifest_sha256'],
        groups=groups, hardware_status='NOT_RUN', bitgen_allowed=False)
    path = report_dir(run)/'FUNCTIONAL_GATE.json'
    functional_gate(run,None,value)
    put(path,value)
    return value

def functional_gate(run, path, value=None):
    run, plan = validate(run)
    gate = value if value is not None else load(path)
    require(gate.get('status')=='PASS_CURRENT_FUNCTIONAL_GATE', 'Current functional gate missing')
    require(gate.get('source_manifest_sha256')==plan['source_manifest_sha256'], 'Functional gate belongs to another freeze')
    require(set(gate.get('groups', {})) >= {'preserved','document_integrated','doc_total_ack'}, 'Missing required functional groups')
    covered = {}
    for name, row in gate['groups'].items():
        path = Path(row['path']).resolve()
        require(path.is_relative_to(ROOT) and path.is_file() and sha(path)==row['sha256'], 'Functional report drift: '+name)
        require(load(path).get('status', '').startswith('PASS'), 'Functional report not PASS: '+name)
        actual = receipt_evidence(run,path)
        require(actual==row, 'Functional gate contents differ from actual receipt tree: '+name)
        sources = row.get('source_sha256', {})
        require(sources, 'Functional evidence needs exact source bindings: '+name)
        for rel, digest in sources.items():
            require(rel in load(run/'SOURCE_MANIFEST.json')['files'] and sha(run/rel)==digest, 'Functional source differs: '+rel)
            covered[rel] = digest
        require(row.get('logs'), 'Actual checked logs required for '+name)
        for item in row['logs']:
            log = Path(item['path']).resolve()
            require(log.is_relative_to(ROOT) and sha(log)==item['sha256'], 'Functional log drift: '+name)
            text = read(log)
            require(item.get('pass_marker') and item['pass_marker'] in text, 'Functional completion marker absent: '+name)
            require(not re.search(r'\*\*\s+(?:Error|Fatal):|Traceback \(most recent call last\)', text), 'Functional log error: '+name)
    changed = [r['path'] for r in plan['scope']['production_changes'] if r['path'].startswith(('01_rtl/','shared/'))]
    require(set(changed) <= set(covered), 'Functional evidence omits changed RTL: '+str(sorted(set(changed)-set(covered))))
    preserved = load(gate['groups']['preserved']['path'])
    require(preserved.get('status')=='PASS_CURRENT_R4_PRESERVED', 'Final current preserved suite required')
    required_jobs = {'ordinary27','pcb_pipeline_adapter_sharehold','pcb_core22','cnn_publication','plotter',
        'hxa_fifo_crc','reader','key3','key1_snapshot','key2_consecutive','report_suspect12'}
    require({row.get('label') for row in preserved.get('commands',[])}==required_jobs,
        'Preserved suite job inventory differs')
    marker_text = {name:'\n'.join(marker for row in group['logs'] for marker in row['observed_markers']) for name,group in gate['groups'].items()}
    require('DOC_MAPPER_HANDSHAKE_PASS' in marker_text['document_integrated'] and
        'DOC_KEY1_INTEGRATED_PASS' in marker_text['document_integrated'], 'Actual document and mapper handshake completion required')
    require('DOC_TOTAL_ACK_PASS' in marker_text['doc_total_ack'], 'Actual total ACK completion required')
    return gate

def prebitgen(run, gate_path):
    run, plan = configure(run)
    physical_review(run)
    functional_gate(run, gate_path)
    result = dict(status='PASS_CURRENT_PREBITGEN_GATE', source_manifest_sha256=plan['source_manifest_sha256'],
        routed_database_sha256=sha(run/'runs/phy_1'/(NAME+'_pr.db')),
        implementation=evidence(report_dir(run)/'IMPLEMENTATION_SIGNOFF.json'), functional_gate=evidence(gate_path),
        toolchain=tool_inventory(run), artifact_name=ARTIFACT, bitgen_allowed=True, hardware_status='NOT_RUN')
    put(run/'signoff/PREBITGEN_GATE.json', result)
    return result

def bitgen(run, gate_path):
    prebitgen(run, gate_path)
    run, plan = configure(run)
    out = run/'signoff/bitgen'
    require(not out.exists(), 'Preserve existing bitgen evidence')
    destination = ROOT/'artifacts'/ARTIFACT
    require(not destination.exists() and not destination.with_suffix('.bid').exists(), 'Refusing artifact overwrite')
    out.mkdir(parents=True)
    bit = out/ARTIFACT
    tcl = out/'bitgen.tcl'
    tcl.write_text(bitgen_script(run, out, bit), encoding='utf-8')
    before = legacy.immutable_inputs(run)
    put(out/'PRE_BITGEN_INPUTS.json', before)
    with (out/'bitgen.log').open('xb') as stream:
        cp = subprocess.run([str(build.TD), 'bitgen.tcl'], cwd=out, stdout=stream, stderr=subprocess.STDOUT)
    text = read(out/'bitgen.log')
    validate(run)
    unchanged = before == legacy.immutable_inputs(run)
    frozen = load(run/'SOURCE_MANIFEST.json')['files']
    drift = [rel for rel,row in frozen.items() if sha(run/rel)!=row['sha256']]
    put(out/'POST_BITGEN_INTEGRITY.json', dict(status='PASS' if unchanged and not drift else 'FAIL',
        frozen_files_checked=len(frozen), source_drift=drift, immutable_inputs_unchanged=unchanged,
        inputs_before=before, inputs_after=legacy.immutable_inputs(run), hardware_status='NOT_RUN'))
    require(unchanged and not drift, 'Bitgen changed frozen/routed inputs')
    require(cp.returncode==0 and text.count('AIRWALK_SECONDARY_BITGEN_PASS')==1 and
        not re.search(r'\b[A-Z]+-\d+\s+(?:ERROR|FATAL|CRITICAL-WARNING)|AIRWALK_SECONDARY_BITGEN_FAIL', text), 'Bitgen failed')
    require(bit.is_file() and bit.stat().st_size>1000000 and bit.with_suffix('.bid').is_file(), 'Missing bit/BID')
    timing = legacy.strict.check_timing(read(out/'pre_bitgen.timing'))
    area = legacy.strict.check_area(read(out/'pre_bitgen.area'))
    route = load(run/'RELEASE_GATE.json')
    require(timing['passed'] and area['passed'] and timing['metrics_ns']==route['timing_ns'], 'Bitgen reimport timing/resources failed or changed')
    require({k:(v['used'],v['total']) for k,v in area['resources'].items()}==
        {k:(v['used'],v['total']) for k,v in route['resources'].items()}, 'Bitgen reimport resources differ')
    parameters = read(out/'checked_bitgen_param.f')
    require(not re.search(r'unconstr_io\s+(?:on|1)|\bignore\w*\s+(?:on|1)', parameters,re.I), 'Nonstandard bitgen parameter bypass')
    destination.parent.mkdir(parents=True,exist_ok=True)
    shutil.copy2(bit,destination)
    shutil.copy2(bit.with_suffix('.bid'),destination.with_suffix('.bid'))
    require(sha(destination)==sha(bit) and sha(destination.with_suffix('.bid'))==sha(bit.with_suffix('.bid')), 'Artifact copy hash mismatch')
    value = dict(status='BITGEN_PASS', artifact=evidence(destination), bytes=destination.stat().st_size,
        bid=evidence(destination.with_suffix('.bid')), temporary_bit=evidence(bit),
        source_manifest=evidence(run/'SOURCE_MANIFEST.json'),
        prebitgen_gate=evidence(run/'signoff/PREBITGEN_GATE.json'),
        warning_review=evidence(report_dir(run)/'IMPLEMENTATION_WARNING_REVIEW.json'),
        retained_critical_warnings=[row for row in load(report_dir(run)/'IMPLEMENTATION_WARNING_REVIEW.json')['warnings'] if row['severity']=='CRITICAL-WARNING'],
        routed_database=evidence(run/'runs/phy_1'/(NAME+'_pr.db')), input_hashes_before=before,
        inputs_unchanged=True, post_integrity=evidence(out/'POST_BITGEN_INTEGRITY.json'),
        script=evidence(tcl), log=evidence(out/'bitgen.log'), hardware_status='NOT_RUN')
    put(out/'BITGEN_RECEIPT.json', value)
    put(report_dir(run)/'BITGEN_RECEIPT.json', value)
    return value

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('action', choices=['prepare','static','functional','route-gate','prepare-readonly','readonly','review','prebitgen','bitgen'])
    p.add_argument('--run', type=Path, default=Path(CONFIG['build']))
    p.add_argument('--gate', type=Path)
    p.add_argument('--evidence', action='append', default=[], help='group=absolute_current_report.json for functional action')
    a = p.parse_args()
    if a.action in {'prebitgen','bitgen'}:
        p.error('--gate is required for '+a.action) if not a.gate else None
    action = {'prepare':prepare, 'static':static_review, 'functional':lambda r:make_functional_gate(r,a.evidence), 'route-gate':route_gate,
        'prepare-readonly':prepare_readonly, 'readonly':run_readonly, 'review':physical_review,
        'prebitgen':lambda r:prebitgen(r,a.gate), 'bitgen':lambda r:bitgen(r,a.gate)}[a.action]
    try:
        result = action(a.run.resolve())
        print(json.dumps(result if isinstance(result,dict) else dict(output=str(result)), ensure_ascii=False, indent=2))
        return 0
    except Exception as exc:
        print('SIGNOFF_REJECTED: '+str(exc), file=sys.stderr)
        return 1

if __name__=='__main__':
    raise SystemExit(main())
