"""Assemble a fail-closed, source-bound final gate. Never invokes TD or bitgen.

Missing physical/readonly evidence yields PENDING_FINAL_GATE.json only.
--require-complete returns nonzero until every required check is current/PASS.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse, hashlib, json, re, sys
sys.dont_write_bytecode=True
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
from release_guard import quarantine_gate, verify_main_protocol
SOURCE=HERE.parents[1]
BUILD=Path('E:/codex_pcb_binary_ccl_retrained_20261102_r2')
MANIFEST='92E737ED8B7D585AEAAC64346A130A2AA7A9F2077A70B14A8CE2D036506A57DB'
CHECKS=('binary_integer','ordinary_cnn','document','writing','cancel_reentry','cdc','fifo','ddr','drc','readonly')
EXPECTED_DELTA={'01_rtl/pcb_ccl_binary_core.v','01_rtl/vision_pipeline.v','model/experiments/conv4_4/weights.mem','model/experiments/conv4_4/biases.mem','model/experiments/conv4_4/quantization.json','model/experiments/conv4_4/MODEL_NEW_CAPTURE.json'}
def sha(p):
    h=hashlib.sha256()
    with Path(p).open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''):h.update(b)
    return h.hexdigest().upper()
def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def put(p,v):Path(p).write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def require(ok,message):
    if not ok:raise ValueError(message)

class Audit:
    def __init__(self):self.inputs={};self.sources={};self.manifest={};self.pending=[];self.errors=[]
    def pin(self,path,digest=None):
        p=Path(path).resolve();require('work' not in [x.lower() for x in p.parts],'Protected backup dependency: '+str(p));require(p.is_file(),'Missing evidence: '+str(p));h=sha(p)
        require(digest is None or h==digest,'Evidence drift: '+str(p));self.inputs[str(p)]=h;return h
    def read(self,p):self.pin(p);return load(p)
    def sources_match(self,values):
        require(isinstance(values,dict) and bool(values),'Empty source binding')
        for rel,digest in values.items():
            require(rel in self.manifest and self.manifest[rel]['sha256']==digest,'Frozen source mismatch: '+rel)
            self.pin(BUILD/rel,digest);self.sources[rel]=digest
        return values
    def map(self,path):
        values=self.read(path);require(isinstance(values,dict),'Invalid hash map '+str(path))
        for path_or_rel,digest in values.items():
            require(isinstance(digest,str) and re.fullmatch('[A-Fa-f0-9]{64}',digest),'Invalid digest '+str(path_or_rel));p=Path(path_or_rel)
            self.pin(p if p.is_absolute() else Path(path).parent/p,digest.upper())
        return values
    def report(self,path,status='PASS',sources=None):
        p=Path(path).resolve();self.pin(p);return dict(path=str(p),sha256=sha(p),status=status,source_sha256=sources or {})

def freeze(a):
    require(a.pin(BUILD/'SOURCE_MANIFEST.json')==MANIFEST,'Wrong retrained r1 manifest');a.manifest=a.read(BUILD/'SOURCE_MANIFEST.json')['files']
    for rel,row in a.manifest.items():a.pin(BUILD/rel,row['sha256'])
    plan=a.read(BUILD/'BUILD_PLAN.json');require(plan['source_manifest_sha256']==MANIFEST,'Build plan manifest differs')
    require(Path(plan['source_root']).resolve()==SOURCE,'Build source root differs')
    delta=a.read(HERE/'SOURCE_DELTA.json');prov=a.read(HERE/'BRANCH_PROVENANCE.json')
    require(delta['status']=='PASS_INPUT_IDENTITY_AND_EXPECTED_DELTA' and delta['manifest_sha256']==MANIFEST,'Source delta not current/PASS')
    parent=Path(prov['read_only_parent_build']);a.pin(parent/'SOURCE_MANIFEST.json',prov['parent_manifest_sha256']);prior=a.read(parent/'SOURCE_MANIFEST.json')['files']
    monitored={rel:h for rel,h in prov['source_files_before_changes'].items() if not rel.startswith('tools/')};changes={}
    for rel,digest in monitored.items():
        require(rel in prior and prior[rel]['sha256']==digest,'Parent provenance mismatch '+rel);a.pin(parent/rel,digest)
        require(rel in a.manifest,'Monitored input absent '+rel);current=a.manifest[rel]['sha256'];a.pin(SOURCE/rel,current)
        if current!=digest:changes[rel]=(digest,current)
    require(set(changes)==EXPECTED_DELTA,'Unexpected production delta: '+str(set(changes)));require(delta['checked_sources_assets']==len(monitored)+3,'Unexpected source addition count'); require(all(k in a.manifest for k in ['model/experiments/conv4_4/MODEL.json','model/experiments/conv4_4/QUANTIZED.npz','model/experiments/conv4_4/ARITHMETIC_BOUNDS.json']),'New model metadata absent')
    require({x['path']:(x['parent_sha256'],x['current_sha256']) for x in delta['changed']}==changes,'Delta hashes differ')
    syntax=a.read(HERE/'SYNTAX.json');require(syntax['status']=='SYNTAX_PASS_NOT_ELABORATED','Current syntax check failed')
    for path,digest in syntax['inputs'].items():
        p=Path(path);a.pin(p,digest)
        if p.is_relative_to(SOURCE):
            rel=p.relative_to(SOURCE).as_posix()
            if rel.startswith(('01_rtl/','main/','shared/')):a.sources_match({rel:digest})
    log=Path(syntax['output'])/'compile.log';a.pin(log);text=log.read_text(encoding='utf-8-sig',errors='replace')
    require('Errors: 0, Warnings: 0' in text and not re.search(r'\*\*\s+(?:Error|Fatal):',text),'Syntax log failed')
    return dict(source_delta=a.report(HERE/'SOURCE_DELTA.json'),syntax=a.report(HERE/'SYNTAX.json'),syntax_scope='Syntax only; physical elaboration/synthesis is separately required')

def preserved(a):
    path=HERE/'regressions/PRESERVED_REGRESSIONS_BINDING_R2.json';binding=a.read(path);require(binding['status']=='PASS' and binding['fresh_execution'] is True,'Preserved regressions not fresh/PASS')
    require(binding['source_manifest']['sha256']==MANIFEST,'Regression manifest differs');a.sources_match(binding['source_sha256']);by_name={}
    for row in binding['evidence']:
        p=Path(row['path']);a.pin(p,row['sha256']);require(row['status']=='PASS','Failed preserved evidence '+str(p));a.sources_match(row['source_sha256']);r=a.read(p)
        require(r['status']=='PASS' and not r['source_drift'] and r['error'] is None,'Preserved result failed '+str(p))
        for source,digest in r['source_hashes'].items():
            test=Path(source)
            if test==SOURCE/'tools/run_retrained_preserved_regressions.py' and sha(test)!=digest:test=HERE/'regressions/preserved_compat/RUNNER_AT_EXECUTION.py'
            a.pin(test,digest)
        for cmd in r['commands']:
            require(cmd['status']=='PASS' and cmd['returncode']==0,'Failed command in '+str(p));a.pin(cmd['log'],cmd['log_sha256']);text=Path(cmd['log']).read_text(encoding='utf-8-sig',errors='replace');require(not re.search(r'\*\*\s+(?:Error|Fatal):',text),'Simulator error in '+cmd['log'])
        by_name[p.parent.name]=dict(reference=a.report(p,sources=row['source_sha256']),scope=r['scope'],limitations=r['limitations'])
    require(set(by_name)=={'plotter','hxa','document','ordinary','publication','controls','reader','key3','top_metadata','top_reset'},'Preserved suite set incomplete')
    ordinary=HERE/'regressions/preserved_compat/ordinary/integer27/RESULTS.json';r=a.read(ordinary);require(r['status']=='PASS' and r['simulation_cases_passed']==27,'Ordinary integer checks incomplete')
    for p,h in r['input_hashes'].items():a.pin(p,h)
    for name in ['pixels.mem','shape.mem','feature1.mem','feature2.mem','results.mem','simulation.log','lint.log']:a.pin(ordinary.parent/name)
    for name in ['blank2418','ink2358']:
        folder=HERE/'regressions/preserved_compat/document/fixtures'/name
        require((folder/'gcode.txt').read_text().splitlines()==(folder/'expected_gcode.txt').read_text().splitlines(),'Current G-code differs: '+name);a.pin(folder/'gcode.txt');a.pin(folder/'expected_gcode.txt')
    review=binding['static_review'];a.pin(review['path'],review['sha256']);a.sources_match(review['source_sha256'])
    return binding,by_name

def binary(a):
    folder=HERE/'binary_validation_compat';a.map(folder/'ARTIFACT_SHA256.json');summary=a.read(folder/'SUMMARY.json')
    require(summary['status']=='PASS' and summary['frozen_manifest_sha256']==MANIFEST,'Binary summary not current/PASS');a.sources_match(summary['branch_and_frozen_match'])
    for rel in ['fixtures/SHA256.json','pipeline_fixtures/SHA256.json']:a.map(folder/rel)
    for key,marker in [('pipeline','BINARY_FULLPIPELINE_REGRESSION_PASS'),('adapter','BINARY_ADAPTER_REGRESSION_PASS')]:
        r=summary[key];require(r['status']=='PASS' and r['returncode']==0 and r['sources_unchanged'] is True and r['frozen_manifest_sha256']==MANIFEST,'Binary '+key+' incomplete');a.sources_match(r['frozen_design_inputs']);run=Path(r['run_directory']);a.map(run/'SOURCE_SHA256.json');a.pin(run/'SIM.log',r['log_sha256']);rr=a.read(run/'RESULTS.json');require(rr==r,'Binary summary child differs: '+key)
        text=(run/'SIM.log').read_text(encoding='utf-8-sig',errors='replace');require(not re.search(r'\*\*\s+(?:Error|Fatal):',text),'Binary simulator error')
    require(summary['pipeline']['frames_passed']==22 and summary['pipeline']['cancels_passed']==3 and summary['pipeline']['ordinary_empty_passed'] is True,'Binary integrated coverage incomplete')
    require(summary['adapter']['tests_passed']==20,'Binary adapter coverage incomplete');require(a.read(folder/'ADDRESS_CHECKS.json')['status']=='PASS','Integer address test failed')
    return dict(reference=a.report(folder/'SUMMARY.json',sources=summary['branch_and_frozen_match']),scope=summary['coverage'],limitations=summary['limitations'])

def physical(a):
    p=HERE/'physical_gate_r2/PHYSICAL_REVIEW_R2.json';ro=BUILD/'READONLY_VERIFICATION.json';database=BUILD/'runs/phy_1/secondary_cnn_multibox_pr.db'
    if not p.is_file():a.pending.append('Current physical supplement has not been produced');return None
    r=a.read(p);require(r['source_manifest_sha256']==MANIFEST,'Physical manifest differs')
    if r.get('errors'):raise ValueError('Physical review has errors: '+str(r['errors']))
    if r['status']!='PASS_PHYSICAL_SUPPLEMENT' or r.get('pending'):
        a.pending.append('Physical supplement is not complete: '+str(r.get('pending',r['status'])));return None
    required={'freeze','gate_proofs','final_routed','reset_cdc','timing_check_drc','ddr_identity','readonly'};require(required<=set(r['checks']),'Physical check set incomplete')
    for path,digest in r['evidence_sha256'].items():a.pin(path,digest)
    require(database.is_file(),'Routed DB missing');dbsha=a.pin(database);require(r['checks']['final_routed']['database_sha256']==dbsha,'Physical DB differs')
    t=r['checks']['final_routed']['timing_ns'];require(all(t[x]>=0 for x in ['SWNS','HWNS']) and t['STNS']==t['HTNS']==0,'Final timing fails')
    limits={'slice':95,'eram':90,'dsp':95}
    for kind,lim in limits.items():
        x=r['checks']['final_routed']['resources'][kind];require(x['used']*100<x['total']*lim and x['strict_pass'] is True,'Strict resource gate fails '+kind)
    require(all(x['endpoints']>0 and x['paths']>0 for x in r['checks']['final_routed']['coverage'].values()),'No analyzed timing endpoints')
    if not ro.is_file():a.pending.append('Readonly verification missing');return None
    v=a.read(ro);require(v['status']=='PASS_READONLY' and v['routed_database_sha256']==dbsha and v['timing_ns']==t,'Readonly identity/timing differs')
    pins=a.read(HERE/'physical_gate_r2/READONLY_INPUT_PINS_R2.json');require(pins['source_manifest_sha256']==MANIFEST,'Readonly pins wrong manifest')
    for path,digest in pins['files'].items():a.pin(path,digest)
    for phase in ['syn','place','route','readonly']:
        inv=a.read(BUILD/'logs'/(phase+'.json'));require(inv.get('exit_code')==0,'Build phase did not complete '+phase);a.pin(BUILD/'logs'/(phase+'.log'),inv['log_sha256'])
    return r,dbsha

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--require-complete',action='store_true');args=parser.parse_args();archive=quarantine_gate(HERE,'A new audit started; previous actionable gate is archived before reevaluation');a=Audit();a.pin(Path(__file__));a.pin(HERE/'release_guard.py');a.pin(HERE/'release_runtime.py');a.pin(HERE/'package_release.py');assembled={};extra={};dbsha=None
    try:
        extra=freeze(a);binding,suites=preserved(a);pcb=binary(a);phys=physical(a)
        compat=verify_main_protocol(HERE);folder=HERE/'main_protocol_compat_v3'
        for name in ('RESULTS.json','SOURCE_SHA256.json','SIM.log','run.do','tb_link_pcb_wait.sv'):a.pin(folder/name)
        for path,digest in compat['source_hashes'].items():a.pin(path,digest)
        extra['main_protocol_compat_v3']=dict(reference=a.report(folder/'RESULTS.json'),main_bit_sha256=compat['main_bit_sha256'],scope=compat['scope'],hardware='NOT_RUN')
        def combine(name,parts,scope):
            sources={}
            for part in parts:sources.update(part['reference']['source_sha256'])
            require(bool(sources),'Empty combined source map '+name)
            assembled[name]=dict(status='PASS',source_manifest_sha256=MANIFEST,scope=scope,source_sha256=sources,support=parts,hardware='NOT_RUN')
        combine('binary_integer',[pcb],'Current CCL original box, exact unsigned Y8 sampling, both convolution layers, pool/logits/status and adapter control; expected model errors are retained.')
        combine('ordinary_cnn',[suites[x] for x in ['ordinary','publication','top_metadata']],'Real classifier numerical/feature checks plus separately controlled-leaf publication and accepted KEY1 snapshot tests.')
        combine('document',[suites['document']],'Six complete-frame frontend fixtures and two exact skeleton/path/machine-coordinate/G-code fixture comparisons.')
        combine('writing',[suites[x] for x in ['plotter','top_metadata','top_reset','key3']],'Current shared transport, final-ok completion, no motion replay, KEY4/Alarm/Reset and KEY3 whole-board reset.')
        combine('cancel_reentry',[pcb,*[suites[x] for x in ['hxa','controls','reader','plotter','top_metadata']]],'Current packet cancellations/PHY/lease/HELLO plus accepted task preservation, drain/reentry and no old G-code replay.')
        combine('fifo',[suites['hxa']],'Actual current packed RX FIFO behavioral regression with payload/header/control cases and packet rejection.')
        if phys:
            physical_report,dbsha=phys
            physical_ref=dict(reference=a.report(HERE/'physical_gate_r2/PHYSICAL_REVIEW_R2.json',sources={k:v['sha256'] for k,v in a.manifest.items() if k.startswith(('01_rtl/','shared/','main/','04_pin/'))}),scope=physical_report['checks'],limitations=[physical_report['scope']])
            for name,subset,scope in [('cdc',['reader','key3'],'Unequal-clock mailbox/reset behavioral tests plus this routed database synchronizer/reset mapping and exact exceptions.'),('ddr',['reader','hxa'],'Current DDR IP/ROM elaboration identity plus mailbox/reader/CRC behavior; real hardware remains NOT_RUN.'),('drc',[],'Current timing-check categories and exact inherited DRC targets reviewed against routed logs.'),('readonly',[],'Readonly reimport checks unchanged DB, timing/resources/clocks/exceptions and original input pins.')]:combine(name,[physical_ref,*[suites[x] for x in subset]],scope)
    except (OSError,ValueError,KeyError,AssertionError,TypeError) as exc:a.errors.append(str(exc))
    missing=sorted(set(CHECKS)-set(assembled));complete=not a.errors and not a.pending and not missing and dbsha is not None
    status='PASS' if complete else ('BLOCKED' if a.errors else 'PENDING')
    report=dict(status=status,generated_utc=datetime.now(timezone.utc).isoformat(),source_manifest_sha256=MANIFEST,routed_database_sha256=dbsha,completed_checks=sorted(assembled),missing_checks=missing,pending=a.pending,errors=a.errors,prerequisites=extra,input_sha256=a.inputs,previous_gate_archive=archive,bitgen_allowed=False,hardware='NOT_RUN',scope='Evidence assembler only; does not run TD, bitgen or board tests.')
    if complete:
        folder=HERE/'final_gate_evidence_r2';folder.mkdir(exist_ok=True);evidence={}
        for name in CHECKS:
            path=folder/(name+'.json');put(path,assembled[name]);evidence[name]=dict(path=str(path),sha256=sha(path),status='PASS',source_sha256=assembled[name]['source_sha256'])
        gate=dict(status='PASS',generated_utc=report['generated_utc'],source_manifest_sha256=MANIFEST,routed_database_sha256=dbsha,checks={name:True for name in CHECKS},evidence=evidence,source_sha256=a.sources,input_sha256=a.inputs,hardware='NOT_RUN',scope='All requested diagnostic build evidence is current/PASS; board validation remains NOT_RUN.')
        staged=HERE/'FINAL_GATE.json.staging';put(staged,gate);report['gate']=dict(path=str(HERE/'FINAL_GATE.json'),sha256=sha(staged));put(HERE/'FINAL_GATE_AUDIT.json',report);staged.replace(HERE/'FINAL_GATE.json')
    else:
        # No schema-compatible all-true gate is emitted while anything is missing.
        put(HERE/'PENDING_FINAL_GATE.json',report)
    print(json.dumps({k:report[k] for k in ['status','completed_checks','missing_checks','pending','errors','bitgen_allowed']},ensure_ascii=False,indent=2))
    return int(bool(a.errors) or (args.require_complete and not complete))
if __name__=='__main__':raise SystemExit(main())
