"""Freeze/build user-retrained binary PCB plus original shared CCL ROI.

Negative mapped timing may proceed to physical exploration. Negative routed
timing, strict resource failure, or missing current evidence always blocks bitgen.
"""
from pathlib import Path
import argparse
import importlib.util
import json
import re
import shutil
import sys
sys.dont_write_bytecode = True

ROOT = Path(__file__).resolve().parents[1]
NAME = 'secondary_cnn_multibox'
spec = importlib.util.spec_from_file_location('binary_base_flow', ROOT/'tools/build_pose7.py')
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
flow = base.flow
sha, load, put, require, safe = flow.sha, flow.load, flow.put, flow.require, flow.safe
CHECKS = {'binary_integer','ordinary_cnn','document','writing','cancel_reentry',
          'cdc','fifo','ddr','drc','readonly'}
base.CHECKS = CHECKS
LIMITS = base.LIMITS
EXPECTED_MODEL = {
    'weights.mem':'92A3BBFD2192CC3D74A5BD3A893A34FCC3D45AE727DBEB8DEFAC56033634874B',
    'biases.mem':'88F1FC576BB24DC35FA58B5620F09CFBA7B61E600B5E92DE2CAD40DA2080B2D0'}
EVIDENCE_SCHEMA = {
    'source_manifest_sha256':'exact BUILD_PLAN.json source_manifest_sha256',
    'routed_database_sha256':'exact current routed secondary_cnn_multibox_pr.db SHA256',
    'checks':{check:True for check in sorted(CHECKS)},
    'evidence':{check:{'path':'absolute current result/report path','sha256':'SHA256 of report',
        'status':'PASS','source_sha256':{'01_rtl/example.v':'exact current frozen source SHA256'}} for check in sorted(CHECKS)}}


def current_evidence_gate(run, plan, gate_path):
    """Fail closed unless every current check has hashed, source-bound evidence."""
    gate=load(safe(gate_path));manifest=load(run/'SOURCE_MANIFEST.json')['files']
    database=run/'runs/phy_1'/(NAME+'_pr.db')
    require(gate.get('source_manifest_sha256')==plan['source_manifest_sha256'], 'Evidence is not for this frozen manifest')
    require(gate.get('routed_database_sha256')==sha(database), 'Evidence is not for this routed database')
    require(set(gate.get('checks',{}))>=CHECKS and all(gate['checks'][k] is True for k in CHECKS), 'Missing current checks')
    require(set(gate.get('evidence',{}))>=CHECKS, 'Each required check needs its own hashed evidence')
    for check in sorted(CHECKS):
        row=gate['evidence'][check]
        require(row.get('status')=='PASS', 'Evidence check not PASS: '+check)
        path=safe(row['path'])
        require(path.is_absolute() and path.is_file() and sha(path)==row.get('sha256'), 'Missing/drifted evidence: '+check)
        sources=row.get('source_sha256',{})
        require(isinstance(sources,dict) and bool(sources), 'Evidence needs source hashes: '+check)
        for relative,digest in sources.items():
            require(relative in manifest and digest==manifest[relative]['sha256'], 'Evidence source differs from frozen build: '+check+': '+relative)
            require(sha(safe(run/relative,run))==digest, 'Evidence source drift: '+relative)
    return gate


def strict_physical_gate(run):
    phy=run/'runs/phy_1';review=load(run/'PRE_BITGEN_REVIEW.json')
    current=flow.metrics(phy,True)
    require(current['resources']==review['resources'] and current['timing_ns']==review['timing_ns'], 'Physical report changed after review')
    require(flow.report_within_device_capacity(current), 'A physical resource exceeds device capacity')
    require(base.strict_resources(current) and flow.timing_pass(current['timing_ns']) and current['routed_two_corner'], 'Final strict resource or setup/hold/two-corner gate failed')
    timing=(phy/(NAME+'_pr.timing')).read_text(encoding='utf-8-sig',errors='replace')
    # A zero from a missing hold analysis must never become a hold PASS.
    hold_endpoints=re.findall(r'(?m)^Min\s*:\s*HWNS.*?\b(\d+)\s+Total Endpoints',timing)
    require(hold_endpoints and any(int(n)>0 for n in hold_endpoints), 'No analyzed hold endpoints in routed timing')
    require(review.get('routed_database_sha256')==sha(phy/(NAME+'_pr.db')), 'Routed DB changed after review')
    return current


def control_identity(source):
    control = safe(source.parent/'secondary_pcb_pose7_goodonly_ccl_20261102')
    frozen = safe('E:/codex_pcb_pose7_20261102_r5')
    bit = control/'artifacts/dual_fpga_secondary_20261102_pcb_pose7_goodonly_ccl_diagnostic.bit'
    require(sha(bit) == 'AD02D4FC18AA58307EC2A3CBC1C5482B2B92B3FCF93CC0077B76748D11B692A8', 'Control bit differs')
    manifest = control/'reports/pose7/release_r5/SOURCE_MANIFEST.json'
    require(sha(manifest) == '3D847C5B889CEEF42A5CACAD22412145447AB4BC510463722DD0CDC852FC74FE', 'Control manifest differs')
    records = load(manifest)['files']
    require(len(records) == 305, 'Control source count differs')
    for relative, item in records.items():
        require(sha(safe(frozen/relative, frozen)) == item['sha256'], 'Control frozen input differs: '+relative)
        if relative.startswith(('04_pin/','main/')):
            require(sha(safe(source/relative, source)) == item['sha256'], 'Protected constraint/IP differs: '+relative)
    return {'root':str(control),'frozen_build':str(frozen),'bit_sha256':sha(bit),
            'source_manifest_sha256':sha(manifest),'verified_frozen_entries':305}


def prepare(args):
    source = safe(args.project_root)
    control = control_identity(source)
    vendor = flow.baseline(source.parent/flow.BASE_NAME, source)
    require(source.name=='secondary_pcb_ccl_binary_user_retrained_20261102', 'Use this isolated retrained source project only')
    out = safe(args.output or 'E:/codex_pcb_binary_ccl_retrained_20261102_r1')
    require(out.drive.upper() == 'E:' and out.name.startswith('codex_pcb_binary_ccl_retrained_'), 'Fresh E:/codex_pcb_binary_ccl_retrained_* required')
    require(not out.exists(), 'Refusing existing build directory')
    tree = flow.xml(source/(NAME+'.al'))
    active = [n.attrib['Path'] for n in tree.findall('Source_Files/Verilog/File')]
    require(any(p.endswith('/pcb_ccl_binary_core.v') for p in active), 'Binary adapter absent')
    require(any(p.endswith('/pcb_fullboard_spatial96.v') for p in active), 'Frozen binary classifier absent')
    require(not any(p.endswith('/pcb_pose7_core.v') for p in active), 'Retired pose7 core remains declared')
    model = source/'model/experiments/conv4_4'
    for name,digest in EXPECTED_MODEL.items():
        require(sha(model/name) == digest, 'Retrained model differs: '+name)
    assets = ['weights.mem','biases.mem','quantization.json','MODEL_NEW_CAPTURE.json']
    model_hashes = {name:sha(model/name) for name in assets}
    metadata = load(model/'MODEL_NEW_CAPTURE.json')
    require(metadata['weight_count']==308 and metadata['bias_count']==10 and metadata['shifts']==[7,7,8], 'Model integer architecture differs')
    require(metadata['crop_scale']==1 and metadata['margin_min']==32, 'Model input or decision contract differs')
    require(metadata['hashes']==EXPECTED_MODEL, 'Model metadata hashes differ')
    out.mkdir()
    records = {}
    def record(p, origin=None):
        records[p.relative_to(out).as_posix()]={'sha256':sha(p),'bytes':p.stat().st_size,
                                             'origin':str(origin) if origin else None}
    for folder in ['01_rtl','04_pin','shared','main','model','tools']:
        for origin in sorted((source/folder).rglob('*')):
            if not origin.is_file() or '__pycache__' in origin.parts: continue
            safe(origin,source)
            digest=sha(origin);dest=out/origin.relative_to(source)
            dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(origin,dest)
            require(sha(dest)==digest==sha(origin),'Input changed during freeze')
            record(dest,origin)
    syn,phy=out/'runs/syn_1',out/'runs/phy_1'
    for directory in [out,syn,phy]:
        directory.mkdir(parents=True,exist_ok=True)
        for suffix in ['al','prj']:
            flow.write_project(tree,directory,out,source,suffix)
            record(directory/(NAME+'.'+suffix),source/(NAME+'.al'))
    for relative,item in vendor['flow'].items():
        dest=out/'runs'/relative;shutil.copy2(item['path'],dest)
        require(sha(dest)==item['sha256'],'Vendor flow changed');record(dest,item['path'])
    text=(phy/'run.tcl').read_text(encoding='utf-8-sig')
    for fname,phase in [('run_place.tcl','opt_place'),('run_route.tcl','opt_route')]:
        script=re.sub(r'(?m)^set start_step \w+$','set start_step '+phase,text,count=1)
        script=re.sub(r'(?m)^set end_step \w+$','set end_step '+phase,script,count=1)
        (phy/fname).write_text(script,encoding='utf-8');record(phy/fname)
    config=load(source/'tools/release_audit_doc_dirt_lowconf_factored_config.json')
    config['resolved_memory_references']=[x for x in config['resolved_memory_references'] if x['source'].startswith('main/')]
    for expression,name in [('WEIGHTS_MEM','weights.mem'),('BIASES_MEM','biases.mem')]:
        config['resolved_memory_references'].append({'source':'01_rtl/pcb_fullboard_spatial96.v','expression':expression,
            'literal':'../model/experiments/conv4_4/'+name,
            'reason':'Explicit pipeline PCB_BINARY -> pcb_ccl_binary_core original CCL box -> retrained spatial96 C4/C4 binding; exact source hash in MODEL_FREEZE.json.'})
    config['extra_files']=sorted({p.relative_to(out).as_posix() for p in (out/'model').rglob('*') if p.is_file()} |
                                {p.relative_to(out).as_posix() for p in (out/'04_pin').rglob('*.tcl')})
    config_path=out/'tools/binary_source_audit_config.json';put(config_path,config);record(config_path)
    # CWD-relative and source-relative readmem resolution use identical copies.
    for directory in [syn,phy]:
        alias=directory/'../model/experiments/conv4_4';alias.mkdir(parents=True,exist_ok=True)
        for name in assets:
            dest=alias/name;shutil.copy2(out/'model/experiments/conv4_4'/name,dest)
            require(sha(dest)==model_hashes[name],'Model alias differs');record(dest,out/'model/experiments/conv4_4'/name)
    put(out/'MODEL_FREEZE.json',{'active_model':'user-only retrained C4/C4 GOOD/BAD binary','assets':model_hashes,
        'pose7_statistics_or_orientation_active':False,'input':'unsigned Y8; original shared CCL half-open box; exact96 point samples',
        'crop_scale':1,'margin_min':32,'known_test_falsePASS':metadata.get('known_test_falsePASS'),
        'hardware_status':'NOT_RUN','model_accuracy_is_not_a_hardware_execution_claim':True})
    record(out/'MODEL_FREEZE.json')
    readonly=out/'readonly';readonly.mkdir()
    template=Path(control['frozen_build'])/'readonly/readonly_reimport.tcl'
    script=template.read_text(encoding='utf-8-sig')
    script=re.sub(r'(?m)^set build \{[^\n]*\}$','set build {'+phy.as_posix()+'}',script,count=1)
    script=re.sub(r'(?m)^set audit \{[^\n]*\}$','set audit {'+readonly.as_posix()+'}',script,count=1)
    (readonly/'readonly_reimport.tcl').write_text(script,encoding='utf-8');record(readonly/'readonly_reimport.tcl',template)
    audit_spec=importlib.util.spec_from_file_location('binary_audit',out/'tools/td_release_audit.py')
    audit=importlib.util.module_from_spec(audit_spec);audit_spec.loader.exec_module(audit)
    snapshots={}
    for directory in [syn,phy]:
        snap=audit.collect(argparse.Namespace(root=out,run=directory,name=NAME,al=None,config=config_path,extra=[]))
        put(directory/'source_snapshot.json',snap);record(directory/'source_snapshot.json')
        snapshots[directory.name]={'passed':snap['passed'],'errors':snap['errors'],'manifest_sha256':snap['manifest_sha256']}
    put(out/'SOURCE_MANIFEST.json',{'files':records})
    plan={'status':'PREPARED_NOT_STARTED','source_root':str(source),'build_root':str(out),
          'source_manifest_sha256':sha(out/'SOURCE_MANIFEST.json'),'baseline':control,'original_vendor_flow':vendor,
          'snapshots':snapshots,'hardware_status':'NOT_RUN','limits_strict_less_than':LIMITS,
          'mapped_negative_timing_blocks_route':False,'negative_final_timing_blocks_bitgen':True,
          'current_regression_checks_required':sorted(CHECKS),'historical_reports_certify_this_build':False}
    plan['evidence_gate_schema']=EVIDENCE_SCHEMA
    put(out/'BUILD_PLAN.json',plan)
    put(source/'reports/build/LATEST_BUILD.json',{'build':str(out),'plan_sha256':sha(out/'BUILD_PLAN.json')})
    require(all(x['passed'] for x in snapshots.values()),'Source closure failed: '+str(snapshots))
    print(json.dumps({'status':'PREPARED_NOT_STARTED','build':str(out),'source_manifest_sha256':plan['source_manifest_sha256'],'snapshots':snapshots},indent=2))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['prepare','inspect','syn','place','route','readonly','bitgen'])
    parser.add_argument('--project-root',type=Path,default=ROOT)
    parser.add_argument('--output',type=Path)
    parser.add_argument('--run',type=Path)
    parser.add_argument('--gate',type=Path)
    args=parser.parse_args()
    if args.action=='prepare': prepare(args)
    else:
        run,plan=flow.validate(args.run)
        control_identity(Path(plan['source_root']))
        if args.action=='inspect': print(json.dumps({'status':'FROZEN_INPUTS_PASS','build':str(run)},indent=2))
        else:
            if args.action=='bitgen':
                require(args.gate, 'Current source-bound gate is required')
                strict_physical_gate(run)
                current_evidence_gate(run,plan,args.gate)
            base.execute(args)
        control_identity(Path(plan['source_root']))


if __name__=='__main__': main()
