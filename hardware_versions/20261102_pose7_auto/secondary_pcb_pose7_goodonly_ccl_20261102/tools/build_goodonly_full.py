"""Fresh, isolated full-board GOOD-only build scaffold.

prepare only copies/freezes inputs. Other explicit actions acquire TD and never
run automatically. Historical resource percentages and mapped WNS are reported.
The user's clarified resource ceiling is 100 percent, including before place.
Illegal mapping/placement, command errors, failed proofs,
DRC and negative final routed timing are never converted into timing PASS.
The user permits a NOT_RUN diagnostic after legal route despite negative
timing; such authorization must be explicit in the current pre-bitgen gate.
"""
from __future__ import annotations
import argparse
import copy
from datetime import datetime,timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
NAME='secondary_cnn_multibox'
TD=Path('E:/td/bin/td_commands_prompt.exe')
BASE_NAME='secondary_doc_dirt_lowconf_factored_20261101'
BASE_RUN='dirt_lowconf_factored_Runs_20261101'
BASE_STEM='dual_fpga_secondary_20261101_doc_dirt_lowconf_factored_diagnostic'
BASE_BIT_SHA='5066DC18572D27361957A63C1702EA3CD060CAEDAB88A0172F8A3C86451C1F34'
FLOW_HASHES={
    'syn_1/run.tcl':'D8815D7606EDB0A2AE83E651B22B817D5BE687D5C57ED0E16CC455EA271F101D',
    'phy_1/run.tcl':'A034A8658A05208B507698492E73F14C3B9F77C1E003E2C577B9B887434F40A5',
    'phy_1/run_bitgen.tcl':'E359B382D7ACB80C2399DCF644AEA68F1C9F36919329D1020B86BA5E6CBD26C1',
    'syn_1/settings.cfg':'84FEFB7933411BE4C9E8E9DC2F347F77C81AC0092256282FB35A57EEB7B1D90A',
    'phy_1/settings.cfg':'909E1816CA5C3E19B4B3AD6C34DD271EF1E16666009FEAEBFA4154B200DDF90C',
}
RELEASE_CHECKS={'integration','ordinary_cnn','pcb_goodonly','document','key2_key3','cdc','fifo','ddr','drc','readonly'}
PREPARE_OUTPUT=None


def require(ok,message):
    if not ok:raise RuntimeError(message)


def sha(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):h.update(block)
    return h.hexdigest().upper()


def load(path):return json.loads(Path(path).read_text(encoding='utf-8-sig'))
def put(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,indent=2)+'\n',encoding='utf-8')


def safe(path,root=None):
    resolved=Path(path).resolve()
    require('work' not in {part.lower() for part in resolved.parts},'Protected work/ path: '+str(resolved))
    if root is not None:require(resolved.is_relative_to(Path(root).resolve()),'Dependency escapes source root: '+str(resolved))
    return resolved


def xml(path):
    text=Path(path).read_text(encoding='utf-8-sig')
    text=re.sub(r'&(?!#?\w+;)', '&amp;',text)
    text=re.sub(r'(<\/?[A-Za-z_][\w:]*)::',lambda m:m[1]+'_TD_DOUBLE_COLON_',text)
    return ET.fromstring(text)


def write_project(tree,target,project_root,source_root,suffix):
    tree=copy.deepcopy(tree);tree.set('Path',target.as_posix())
    for node in tree.findall('Source_Files/*/File'):
        path=Path(node.attrib['Path']);path=safe(path if path.is_absolute() else source_root/path,source_root)
        dest=project_root/path.relative_to(source_root)
        node.set('Path',os.path.relpath(dest,target).replace('\\','/'))
    ET.indent(tree)
    text=ET.tostring(tree,encoding='unicode').replace('_TD_DOUBLE_COLON_','::')
    (target/(NAME+'.'+suffix)).write_text('<?xml version="1.0" encoding="UTF-8"?>\n'+text+'\n',encoding='utf-8')


def baseline(base,source):
    base=safe(base);bit=base/'artifacts'/(BASE_STEM+'.bit')
    require(sha(bit)==BASE_BIT_SHA,'Read-only baseline bit hash differs')
    build=load(bit.with_name(BASE_STEM+'_BUILD.json'))
    require(build['bit_sha256']==BASE_BIT_SHA and build['status']=='DIAGNOSTIC_NOT_RUN','Unexpected baseline delivery')
    plan=load(base/BASE_RUN/'BUILD_PLAN.json')
    flow={}
    for relative,expected in FLOW_HASHES.items():
        path=base/BASE_RUN/relative
        require(sha(path)==expected and plan['flow_sha256'][BASE_RUN+'/'+relative]==expected,'Baseline exact Tcl/config drift: '+relative)
        flow[relative]=dict(path=str(path),sha256=expected)
    snapshot=load(base/BASE_RUN/'syn_1/source_snapshot.json');protected={}
    for entry in snapshot['files']:
        origin=safe(entry['path'],base);relative=origin.relative_to(base)
        if relative.parts[0] not in {'04_pin','main'}:continue
        require(sha(origin)==entry['sha256'],'Read-only baseline constraint/IP drift: '+str(relative))
        current=safe(source/relative,source)
        require(current.is_file() and sha(current)==entry['sha256'],'Current constraint/IP differs from successful baseline: '+str(relative))
        protected[relative.as_posix()]=entry['sha256']
    require(protected.get('04_pin/clocktrace_sclk/prove_key3_supervisor_clocktrace.tcl')==
        'B075E954594269ED473318765371C9D92E510B22D2A211D5AE1AD99453DD40E9','Required SCLK hook not bound')
    return dict(root=str(base),bit_sha256=BASE_BIT_SHA,flow=flow,protected_constraint_ip_sha256=protected,
        build_record_sha256=sha(bit.with_name(BASE_STEM+'_BUILD.json')))


def prepare(args):
    global PREPARE_OUTPUT
    source=safe(args.project_root);require(source!=source.parent/BASE_NAME,'Cannot prepare in baseline')
    base=safe(args.baseline or source.parent/BASE_NAME)
    expected=baseline(base,source)
    stamp=datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
    output=safe(args.output or Path('E:/')/('codex_pcb_goodonly_full_'+stamp))
    require(output.drive.upper()=='E:' and output.name.startswith('codex_pcb_goodonly_full_'),'Fresh build root must be E:/codex_pcb_goodonly_full_<tag>')
    require(not output.exists() and not output.is_relative_to(source),'Refusing existing/source-tree output')
    project=source/(NAME+'.al');tree=xml(project)
    files={}
    def add(path,kind):
        path=safe(path,source);require(path.is_file(),'Missing '+kind+': '+str(path))
        relative=path.relative_to(source).as_posix()
        files.setdefault(relative,dict(path=path,kind=kind))
    for group in tree.findall('Source_Files/*'):
        for node in group.findall('File'):
            path=Path(node.attrib['Path']);add(path if path.is_absolute() else source/path,'declared_'+group.tag)
    # Preserve support trees (including every model asset and complete vendor
    # IP tree), not stale runs/work/databases or copied historical PASS logs.
    for folder in ['01_rtl','04_pin','shared','main','model']:
        for path in sorted((source/folder).rglob('*')):
            if path.is_file() and '__pycache__' not in path.parts:add(path,'support_'+folder)
    for relative in ['tools/build_goodonly_full.py','tools/td_release_audit.py',
                     'tools/release_audit_doc_dirt_lowconf_factored_config.json']:
        add(source/relative,'build_tool')
    image=source/'reports/integration_design/workspace_image_v1'
    for name in ['workspace_bank0_init.mem','workspace_bank1_init.mem']:
        add(image/name,'workspace_image')
    output.mkdir()
    PREPARE_OUTPUT=output
    put(output/'PREPARE_STATE.json',dict(status='PREPARING_NO_TOOLS_STARTED',started_utc=datetime.now(timezone.utc).isoformat()))
    records={}
    def record(path,origin=None,kind='generated'):
        relative=path.relative_to(output).as_posix()
        records[relative]=dict(sha256=sha(path),bytes=path.stat().st_size,kind=kind,
            origin=str(origin) if origin is not None else None)
    for relative,item in sorted(files.items()):
        origin=item['path'];expected_sha=sha(origin);dest=output/relative;dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(origin,dest);require(sha(dest)==expected_sha and sha(origin)==expected_sha,'Source changed while copying: '+relative)
        record(dest,origin,item['kind'])
    for suffix in ['al','prj']:write_project(tree,output,output,source,suffix);record(output/(NAME+'.'+suffix),project,'rebased_project')
    syn=output/'runs/syn_1';phy=output/'runs/phy_1'
    for directory in [syn,phy]:
        directory.mkdir(parents=True)
        for suffix in ['al','prj']:
            write_project(tree,directory,output,source,suffix);record(directory/(NAME+'.'+suffix),project,'rebased_run_project')
    for relative,item in expected['flow'].items():
        dest=output/'runs'/relative;shutil.copy2(item['path'],dest)
        require(sha(dest)==item['sha256'],'Exact baseline flow copy mismatch')
        record(dest,item['path'],'exact_successful_baseline_flow')
    text=(phy/'run.tcl').read_text(encoding='utf-8-sig')
    require(re.search(r'(?m)^set start_step opt_place$',text) and re.search(r'(?m)^set end_step opt_route$',text),'Unexpected physical flow bounds')
    for name,start,end in [('run_place.tcl','opt_place','opt_place'),('run_route.tcl','opt_route','opt_route')]:
        modified=re.sub(r'(?m)^set start_step \w+$','set start_step '+start,text,count=1)
        modified=re.sub(r'(?m)^set end_step \w+$','set end_step '+end,modified,count=1)
        dest=phy/name;dest.write_text(modified,encoding='utf-8');record(dest,expected['flow']['phy_1/run.tcl']['path'],'baseline_flow_only_phase_bounds_changed')
    # Bare module defaults and the explicit ../model/goodonly instance paths
    # must resolve to the same frozen bytes. Do not stage ambiguous generic
    # weights.mem aliases from different experiments.
    pipeline=(output/'01_rtl/vision_pipeline.v').read_text(encoding='utf-8-sig')
    active_cores=set(re.findall(r'\b(pcb_goodonly_auto_core(?:_[A-Za-z0-9]+)*)\s*#\(',pipeline))
    require(len(active_cores)==1,'Expected exactly one active GOOD-only core binding')
    active_core=next(iter(active_cores))
    combined_active=active_core!='pcb_goodonly_auto_core'
    geometry_binding=re.search(r'parameter\s+PCB_GOODONLY_GEOMETRY_ROM\s*=\s*"([^"\n]+)"',pipeline)
    require(geometry_binding is not None,'Missing explicit GOOD-only firmware binding')
    geometry_asset=Path(geometry_binding[1]).name
    require(geometry_asset.endswith('.mem'),'GOOD-only firmware must be a frozen mem asset')
    aliases={name:image/name for name in ['workspace_bank0_init.mem','workspace_bank1_init.mem']}
    coarse=source/'model/goodonly/coarse_engine_rom.mem'
    if coarse.is_file():aliases['coarse_engine_rom.mem']=coarse
    firmware=source/'model/goodonly'/geometry_asset
    require(firmware.is_file(),'Active core requires its explicit firmware asset')
    aliases[geometry_asset]=firmware
    for name,origin in aliases.items():
        goodonly=source/'model/goodonly'/name
        if goodonly.is_file():require(sha(goodonly)==sha(origin),'GOOD-only alias/model differs: '+name)
        for directory in [syn,phy]:
            dest=directory/name;shutil.copy2(origin,dest);record(dest,origin,'same_hash_readmem_cwd_alias')
    # The conservative generic scanner resolves module defaults, not parameter
    # forwarding. Explicitly check the three production GOOD-only bindings in
    # the exact TD search order: calling HDL directory, then .al directory.
    geometry_module='pcb_combined_microcode_engine_candidate' if combined_active else 'pcb_microcode_engine_v1'
    bindings=[]
    for parameter,module,asset in [
        ('PCB_GOODONLY_GEOMETRY_ROM',geometry_module,geometry_asset),
        ('PCB_GOODONLY_BANK0_INIT','vision_workspace_goodonly','workspace_bank0_init.mem'),
        ('PCB_GOODONLY_BANK1_INIT','vision_workspace_goodonly','workspace_bank1_init.mem')]:
        match=re.search(r'parameter\s+'+parameter+r'\s*=\s*"([^"\n]+)"',pipeline)
        require(match is not None,'Missing explicit production GOOD-only ROM parameter: '+parameter)
        literal=match[1];callers=[]
        for node in tree.findall('Source_Files/Verilog/File'):
            original=Path(node.attrib['Path']);original=safe(original if original.is_absolute() else source/original,source)
            path=output/original.relative_to(source)
            if re.search(r'\bmodule\s+'+module+r'\b',path.read_text(encoding='utf-8-sig',errors='replace')):callers.append(path)
        require(len(callers)==1,'Missing/duplicate active GOOD-only ROM caller: '+module)
        raw=Path(literal)
        canonical=output/'model/goodonly'/asset
        require(canonical.is_file(),'Missing frozen GOOD-only ROM: '+asset)
        # Preserve both documented TD source-relative lookup and the literal
        # run-working-directory path. Both aliases contain identical bytes.
        if not raw.is_absolute():
            for directory in [syn,phy]:
                alias=safe(directory/raw,output)
                alias.parent.mkdir(parents=True,exist_ok=True)
                if alias.exists():require(sha(alias)==sha(canonical),'Conflicting instance-path ROM alias: '+str(alias))
                else:shutil.copy2(canonical,alias);record(alias,canonical,'same_hash_readmem_instance_path_alias')
        candidates=[raw] if raw.is_absolute() else [callers[0].parent/raw,syn/raw]
        resolved=[path.resolve() for path in candidates if path.is_file()]
        require(resolved,'Production instance ROM cannot resolve with TD calling-source/.al order: '+parameter+'='+literal)
        require(canonical.is_file() and all(sha(path)==sha(canonical) for path in resolved),
            'Production instance ROM binding differs/ambiguous: '+parameter)
        bindings.append(dict(parameter=parameter,literal=literal,caller=str(callers[0]),
            candidates=[str(path.resolve()) for path in candidates],selected=str(resolved[0]),sha256=sha(resolved[0])))
    binding_report=output/'ROM_SOURCE_RESOLUTION.json'
    put(binding_report,dict(status='PASS_EXPLICIT_GOODONLY_PRODUCTION_ROM_BINDINGS',bindings=bindings,
        numerical_core='combined_candidate' if combined_active else 'original_production',
        active_core_module=active_core,firmware_asset=geometry_asset,
        scope='Exact current pipeline defaults propagated to active readmemh callers; not a substitute for TD elaboration evidence.'))
    record(binding_report,kind='explicit_production_ROM_source_resolution')
    config=load(source/'tools/release_audit_doc_dirt_lowconf_factored_config.json')
    config['extra_files']=sorted({path.relative_to(output).as_posix() for path in (output/'model').rglob('*') if path.is_file()}|
        {path.relative_to(output).as_posix() for path in (output/'04_pin').rglob('*.tcl')})
    config_path=output/'tools/goodonly_source_audit_config.json';put(config_path,config);record(config_path,kind='new_closure_audit_config')
    audit_template=base/'02_sim'/ (BASE_RUN+'_readonly')/'readonly_reimport.tcl'
    readonly=output/'readonly';readonly.mkdir()
    text=audit_template.read_text(encoding='utf-8-sig')
    text=re.sub(r'(?m)^set build \{[^\n]*\}$','set build {'+phy.as_posix()+'}',text,count=1)
    text=re.sub(r'(?m)^set audit \{[^\n]*\}$','set audit {'+readonly.as_posix()+'}',text,count=1)
    (readonly/'readonly_reimport.tcl').write_text(text,encoding='utf-8')
    record(readonly/'readonly_reimport.tcl',audit_template,'exact_readonly_template_only_output_paths_rebased')
    # Invoke only Python read-only source collection; never TD or vsim here.
    spec=importlib.util.spec_from_file_location('goodonly_snapshot_auditor',output/'tools/td_release_audit.py')
    audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
    snapshots={}
    for directory in [syn,phy]:
        namespace=argparse.Namespace(root=output,run=directory,name=NAME,al=None,config=config_path,extra=[])
        snapshot=audit.collect(namespace);put(directory/'source_snapshot.json',snapshot)
        snapshots[directory.name]=dict(passed=snapshot['passed'],errors=snapshot['errors'],
            manifest_sha256=snapshot['manifest_sha256'],snapshot_sha256=sha(directory/'source_snapshot.json'))
        record(directory/'source_snapshot.json',kind='new_current_source_closure')
    source_manifest=output/'SOURCE_MANIFEST.json'
    put(source_manifest,dict(status='FROZEN_INPUTS_ONLY_NOT_VALIDATED',source_root=str(source),build_root=str(output),
        created_utc=datetime.now(timezone.utc).isoformat(),files=records))
    passed=all(item['passed'] for item in snapshots.values())
    plan=dict(status='PREPARED_NOT_STARTED' if passed else 'PREPARED_SOURCE_CLOSURE_FAILED_NOT_STARTED',
        build_root=str(output),source_root=str(source),baseline=expected,source_manifest_sha256=sha(source_manifest),
        snapshots=snapshots,hardware_status='NOT_RUN',integration_validation='NOT_RUN',bitgen='BLOCKED_PENDING_CURRENT_INTEGRATION_AND_PHYSICAL_REVIEW',
        phase_order=['syn','place','route','readonly','explicit_pre_bitgen_gate','bitgen'],
        route_policy=dict(resource_percentages_are_diagnostic=True,negative_mapped_WNS_blocks_route=False,
            legacy_percent_limits={'slice':95,'eram':90,'dsp':95},
            resource_hard_limit_percent=100,allow_mapped_resource_above_100_percent=False,
            user_override='Old percentage limits are report-only; user clarified resource usage must not exceed 100 percent before placement or delivery.',
            illegal_or_DRC_errors_ignored=False,final_negative_timing_may_be_not_run_diagnostic=True,
            timing_failure_must_be_explicit_in_pre_bitgen_gate=True))
    put(output/'BUILD_PLAN.json',plan)
    put(output/'PREPARE_STATE.json',dict(status=plan['status'],finished_utc=datetime.now(timezone.utc).isoformat()))
    print(json.dumps(dict(status=plan['status'],build_root=str(output),source_manifest_sha256=sha(source_manifest),snapshots=snapshots),indent=2))
    require(passed,'Closure errors recorded in fresh source_snapshot.json; do not synthesize this snapshot')


def validate(run):
    run=safe(run);plan=load(run/'BUILD_PLAN.json')
    require(plan['status']=='PREPARED_NOT_STARTED' and Path(plan['build_root']).resolve()==run,'Wrong/unprepared build')
    manifest=run/'SOURCE_MANIFEST.json';require(sha(manifest)==plan['source_manifest_sha256'],'Source manifest drift')
    for relative,item in load(manifest)['files'].items():
        path=safe(run/relative,run);require(path.is_file() and sha(path)==item['sha256'],'Frozen input drift: '+relative)
    return run,plan


def metrics(directory,physical):
    suffix='_phy.area' if physical else '_gate.area'
    area=directory/(NAME+suffix);result={'resources':{},'reported_capacity':{},'timing_ns':{}}
    if area.is_file():
        text=area.read_text(encoding='utf-8-sig',errors='replace')
        # Include every resource whose capacity is stated by TD. Slice alone
        # cannot prove IO, clock, register, or dedicated-site capacity.
        result['reported_capacity']=reported_capacity(text)
        for name,limit in [('slice',95),('eram',90),('dsp',95)]:
            match=re.search(r'^#'+name+r'\*?\s+(\d+)\s+out of\s+(\d+)',text,re.M)
            if match:
                used,total=map(int,match.groups());require(total>0,'Invalid device resource report')
                result['resources'][name]=dict(used=used,total=total,percent=100*used/total,
                    original_strict_limit_percent=limit,within_original_limit=(used*100<total*limit))
    timing=directory/(NAME+('_pr.timing' if physical else '_gate.timing'))
    if timing.is_file():
        text=timing.read_text(encoding='utf-8-sig',errors='replace')
        for key in ['SWNS','STNS','HWNS','HTNS']:
            match=re.search(r'\b'+key+r':\s*([-+\d.]+)ns',text)
            if match:result['timing_ns'][key]=float(match[1])
        result['routed_two_corner']=('Routed' in text and 'Both (Slow and Fast)' in text)
    return result


def timing_pass(value):
    return set(value)=={'SWNS','STNS','HWNS','HTNS'} and all(x>=0 for x in value.values()) and value['STNS']==0 and value['HTNS']==0


def within_device_capacity(resources):
    return set(resources)=={'slice','eram','dsp'} and all(
        item['total']>0 and 0<=item['used']<=item['total'] for item in resources.values())


def reported_capacity(text):
    result={}
    for match in re.finditer(r'^\s*#([A-Za-z_][A-Za-z_0-9 ]*?)\*?\s+(\d+)\s+out of\s+(\d+)\b',text,re.M):
        name=re.sub(r'\s+','_',match[1].strip().lower())
        used,total=int(match[2]),int(match[3])
        require(name not in result,'Duplicate capacity row: '+name)
        result[name]=dict(used=used,total=total,percent=100*used/total if total else None)
    return result


def report_within_device_capacity(review):
    capacities=review.get('reported_capacity',{})
    return within_device_capacity(review.get('resources',{})) and {'slice','eram','dsp'}<=set(capacities) and all(
        item['total']>0 and 0<=item['used']<=item['total'] for item in capacities.values())


def invocation(run,phase,directory,script):
    log=run/'logs'/(phase+'.log');require(not log.exists(),'Refusing repeated phase/overwriting log: '+phase)
    log.parent.mkdir(exist_ok=True);started=time.time_ns()
    record=dict(phase=phase,status='RUNNING',started_ns=started,cwd=str(directory),script=script,
        script_sha256=sha(directory/script),command=[str(TD),script])
    put(run/'logs'/(phase+'.json'),record)
    with log.open('xb') as stream:cp=subprocess.run([str(TD),script],cwd=directory,stdout=stream,stderr=subprocess.STDOUT)
    text=log.read_text(encoding='utf-8-sig',errors='replace')
    errors=re.findall(r'(?m)^.*(?:[A-Z]+-\d+\s+(?:ERROR|FATAL)|\*\*\s+(?:Error|Fatal):|BUILD_FAILED|MAPPING_ERROR).*$',text)
    markers=[str(path) for path in directory.glob('.*.error.f')]
    record.update(exit_code=cp.returncode,finished_ns=time.time_ns(),log_sha256=sha(log),errors=errors,error_markers=markers,
        status='PASS_TOOL_INVOCATION' if cp.returncode==0 and not errors and not markers else 'FAILED_TOOL_INVOCATION')
    put(run/'logs'/(phase+'.json'),record)
    require(record['status']=='PASS_TOOL_INVOCATION','TD phase failed; retain reports/logs: '+phase)
    return text


def execute(args):
    run,plan=validate(args.run);syn=run/'runs/syn_1';phy=run/'runs/phy_1';phase=args.action
    require(TD.is_file(),'TD executable missing')
    if phase=='syn':
        invocation(run,phase,syn,'run.tcl')
        require((syn/'.opt_gate.end.f').is_file() and (syn/(NAME+'_gate.db')).is_file(),'Fresh synthesis incomplete')
        log=(run/'logs/syn.log').read_text(encoding='utf-8-sig',errors='replace')
        illegal=[line for line in log.splitlines() if re.search(
            r'SYN-5033|SYN-1048.*comb insts loops|unstable comb insts loops|TMR-250[79].*combinational loop|inferred latch',line,re.I)]
        result=metrics(syn,False)
        status=('MAPPED_DIAGNOSTIC_ILLEGAL_LOGIC_BLOCKS_PLACE' if illegal else
            'MAPPED_DIAGNOSTIC_CONTINUE_TO_ACTUAL_PLACE' if report_within_device_capacity(result) else
            'MAPPED_ABOVE_100_PERCENT_REQUIRES_RESOURCE_REDUCTION')
        put(run/'SYNTHESIS_REVIEW.json',dict(status=status,source_manifest_sha256=plan['source_manifest_sha256'],
            illegal_logic_evidence=illegal,**result,route_policy=plan['route_policy']))
    elif phase=='place':
        require((syn/'.opt_gate.end.f').is_file() and (syn/(NAME+'_gate.db')).is_file(),'Synthesis prerequisite missing')
        review=load(run/'SYNTHESIS_REVIEW.json')
        require(not review.get('illegal_logic_evidence'),'Known unstable combinational loop/latch blocks place; resource/WNS override does not waive illegal logic')
        require(report_within_device_capacity(review),'User clarified at most 100 percent of each reported device resource; reduce oversized mapping before place')
        invocation(run,phase,phy,'run_place.tcl')
        require((phy/'.opt_place.end.f').is_file() and (phy/(NAME+'_place.db')).is_file(),'Place incomplete')
        put(run/'PLACE_REVIEW.json',dict(status='PLACED_NOT_ROUTED',source_manifest_sha256=plan['source_manifest_sha256'],**metrics(phy,True)))
    elif phase=='route':
        require((phy/'.opt_place.end.f').is_file() and (phy/(NAME+'_place.db')).is_file(),'Place prerequisite missing')
        invocation(run,phase,phy,'run_route.tcl')
        require((phy/'.opt_route.end.f').is_file() and (phy/(NAME+'_pr.db')).is_file(),'Route incomplete')
        result=metrics(phy,True)
        put(run/'PRE_BITGEN_REVIEW.json',dict(status='ROUTED_REQUIRES_INTEGRATION_DRC_READONLY_REVIEW',
            source_manifest_sha256=plan['source_manifest_sha256'],routed_database_sha256=sha(phy/(NAME+'_pr.db')),
            final_timing_pass=timing_pass(result['timing_ns']),**result,bitgen_allowed=False,hardware_status='NOT_RUN'))
    elif phase=='readonly':
        require((phy/'.opt_route.end.f').is_file(),'Route prerequisite missing')
        database=phy/(NAME+'_pr.db');before=sha(database)
        text=invocation(run,phase,run/'readonly','readonly_reimport.tcl')
        require('TD_READONLY_REIMPORT_PASS' in text and sha(database)==before,'Readonly reimport failed or database modified')
        status=(run/'readonly/readonly.ts').read_text(encoding='utf-8-sig',errors='replace')
        expected=metrics(phy,True)['timing_ns'];actual={}
        for key in ['SWNS','STNS','HWNS','HTNS']:
            match=re.search(r'\b'+key+r':\s*([-+\d.]+)ns',status);require(match is not None,'Readonly missing '+key)
            actual[key]=float(match[1])
        flow=(run/'readonly/readonly.flow').read_text(encoding='utf-8-sig',errors='replace')
        require(actual==expected and re.search(r'^\s*import_db\s*\|\s*[1-9]',flow,re.M) and
            not re.search(r'^\s*(?:place|route|bitgen|optimize_\w+)\s*\|',flow,re.M),'Readonly timing/flow mismatch')
        validate(run)
        put(run/'READONLY_VERIFICATION.json',dict(status='PASS_CURRENT_ROUTED_DATABASE_READONLY_REIMPORT',
            source_manifest_sha256=plan['source_manifest_sha256'],routed_database_sha256=before,timing_ns=actual,
            evidence_sha256={path.name:sha(path) for path in (run/'readonly').iterdir() if path.is_file()},bitgen_allowed=False))
    elif phase=='bitgen':
        require(args.gate is not None,'Explicit current integration/physical gate is required before bitgen')
        gate=load(args.gate);review=load(run/'PRE_BITGEN_REVIEW.json');readonly=load(run/'READONLY_VERIFICATION.json')
        require(gate.get('status')=='PASS_GOODONLY_PRE_BITGEN_GATE' and
            gate.get('source_manifest_sha256')==plan['source_manifest_sha256'] and
            gate.get('routed_database_sha256')==sha(phy/(NAME+'_pr.db')) and
            gate.get('readonly_verification_sha256')==sha(run/'READONLY_VERIFICATION.json'),'Pre-bitgen gate identity mismatch')
        require(gate.get('bitgen_allowed') is True and all(gate.get('checks',{}).get(key) is True for key in RELEASE_CHECKS),
            'Missing current integrated/CDC/FIFO/DDR/DRC/readonly checks')
        require(review['routed_two_corner'] and readonly['timing_ns']==review['timing_ns'],
            'Final routed/read-only timing coverage/identity differs')
        require(report_within_device_capacity(review),'Routed resources exceed the user clarified 100 percent ceiling')
        if not timing_pass(readonly['timing_ns']):
            require(gate.get('allow_negative_timing_diagnostic') is True and
                gate.get('timing_status')=='FAILED_ACCEPTED_AS_NOT_RUN_DIAGNOSTIC',
                'Negative final timing requires explicit diagnostic authorization and failed-timing label')
        evidence=gate.get('evidence',{});require(evidence,'Gate lacks hashed current evidence')
        for item in evidence.values():require(sha(item['path'])==item['sha256'],'Pre-bitgen evidence drift')
        put(run/'BITGEN_AUTHORIZATION.json',dict(gate_path=str(Path(args.gate).resolve()),gate_sha256=sha(args.gate),
            source_manifest_sha256=plan['source_manifest_sha256'],hardware_status='NOT_RUN'))
        invocation(run,phase,phy,'run_bitgen.tcl')
        require((phy/'.bitgen.end.f').is_file() and (phy/(NAME+'.bit')).is_file(),'Bitgen incomplete')
        put(run/'BITGEN_RESULT.json',dict(status='DIAGNOSTIC_NOT_RUN',bit=str(phy/(NAME+'.bit')),
            bit_sha256=sha(phy/(NAME+'.bit')),source_manifest_sha256=plan['source_manifest_sha256'],hardware_status='NOT_RUN',
            timing_status='PASS_ROUTED_TIMING' if timing_pass(readonly['timing_ns']) else 'FAILED_TIMING_NOT_RUN_DIAGNOSTIC',
            actual_timing_ns=readonly['timing_ns'],resources=review['resources']))
    print(json.dumps(dict(action=phase,build_root=str(run),status='ACTION_COMPLETE',hardware_status='NOT_RUN'),indent=2))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['prepare','inspect','syn','place','route','readonly','bitgen'])
    parser.add_argument('--project-root',type=Path,default=ROOT);parser.add_argument('--baseline',type=Path)
    parser.add_argument('--output',type=Path);parser.add_argument('--run',type=Path);parser.add_argument('--gate',type=Path)
    args=parser.parse_args()
    if args.action=='prepare':prepare(args)
    elif args.action=='inspect':
        require(args.run is not None,'--run is required');run,plan=validate(args.run)
        print(json.dumps(dict(status='PASS_FROZEN_INPUTS_ONLY',build_root=str(run),plan=plan),indent=2))
    else:
        require(args.run is not None,'--run is required');execute(args)


if __name__=='__main__':
    try:main()
    except (OSError,RuntimeError,ValueError,KeyError,ET.ParseError) as error:
        if PREPARE_OUTPUT is not None:
            put(PREPARE_OUTPUT/'PREPARE_STATE.json',dict(status='PREPARE_FAILED_NO_TOOLS_STARTED',error=repr(error),
                finished_utc=datetime.now(timezone.utc).isoformat()))
        print('GOODONLY_FULL_BUILD_FAIL:',error,file=sys.stderr);raise SystemExit(1)
