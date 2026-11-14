"""Revalidate raw functional evidence and exact frozen-production hashes, without new PASS claims."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,re,sys
ROOT=Path(__file__).resolve().parents[1]
WORKSPACE=ROOT.parent
FREEZE=Path('E:/codex_paper_eject_secondary_20261112_r2')
AGG=ROOT/'reports/preserved_paper_r2/20261112T153300_674057Z/RESULTS.json'
PAPER=ROOT/'reports/paper_eject/20261112T153624_301341Z/RESULTS.json'
DOC=ROOT/'reports/paper_document/20261112T153624_479671Z/RESULTS.json'
INDEPENDENT=WORKSPACE/'pcb_operator_update_20261112/paper_eject_review/20261112T151937_145564Z/EVIDENCE_BINDING.json'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
read=lambda p:Path(p).read_text(encoding='utf-8-sig',errors='replace')
load=lambda p:json.loads(read(p))
errors=[];file_refs={};receipt_rows={};log_rows={};visited=set();source_pins={}
def resolve(value,parent):
 p=Path(value)
 if p.is_absolute():return p
 for root in [ROOT,parent.parent,WORKSPACE]:
  candidate=root/p
  if candidate.is_file():return candidate
 return p

def checkfile(path,digest=None,kind='referenced'):
 p=Path(path).resolve()
 if not p.is_file():errors.append('Missing '+str(p));return
 actual=sha(p)
 if digest is not None and actual!=digest.upper():errors.append('Hash mismatch '+str(p))
 if str(p) in file_refs and file_refs[str(p)]['sha256']!=actual:errors.append('Cross-receipt drift '+str(p))
 file_refs[str(p)]=dict(path=str(p),sha256=actual,kind=kind)
 return actual

def required_markers(path,argv,label,context):
 name=path.name
 full=str(path).replace('\\','/')
 mappings={
 'publication_simulation.log':['PASS CNN_PUBLICATION_INTEGRATION checks=170 jobs=30 starts=32'],
 'snapshot_simulation.log':['SUSPECT_KEY1_SNAPSHOT_PASS checks=21'],
 'metadata_simulation.log':['OPERATOR_METADATA_PASS checks=23'],
 'key2_simulation.log':['KEY2_OPERATOR_PASS checks=14'],
 'robust_transport_simulation.log':['ROBUST_TRANSPORT_PASS cases=12 checks=51'],
 'paper_simulation.log':['PAPER_EJECT_PASS cases=29'],
 'document_simulation.log':['OPERATOR_DOCUMENT_PASS cases=12 checks=78'],
 'top_control_simulation.log':['POSE7_TOP_CONTROL_PASS checks=50'],
 'key1_simulation.log':['PASS KEY1 job guard:'],
 'reader_mailbox_simulation.log':['POSE7_REAL_READER_PASS cases=12 checks=506'],
 'key3_supervisor_simulation.log':['KEY3_RESET_UNIT_PASS cases=5'],
 'tb_pose7_fifo4.log':['POSE7_FIFO4_PASS: 41 payload/header/control checks'],
 'tb_pose7_hxa_crc_network.log':['POSE7_HXA_CRC_NETWORK_PASS cases=11'],
 'transport_simulation.log':['POSE7_PLOTTER_REGRESSION_PASS cases=13'],
 'pipeline_simulation.log':['BINARY_FULLPIPELINE_GOLDEN_PASS frames=13 cancels=4'],
 'adapter_simulation.log':['SUSPECT_ADAPTER_GOLDEN_PASS tests=24'],
 'sharehold_simulation.log':['BINARY_FULLPIPELINE_GOLDEN_PASS frames=13 cancels=4','PIPELINE_SHAREHOLD_PASS hold_checks=104 clear_checks=50'],
 'ordinary_integer27.log':['PASS RTL + integer golden: 27 cases'],
 }
 if name in mappings:return mappings[name]
 if re.fullmatch(r'case\d+\.log',name):return ['PAIR_RUNTIME_EXTRA_PASS case='+re.search(r'\d+',name)[0]]
 if name.startswith('frontend_') and not name.endswith(('_vlib.log','_lint.log')):return ['PASS FRONTEND '+name[9:-4]]
 if name in ['blank2418_simulation.log','ink2358_simulation.log']:return ['PASS CAPTURE_INTEGRATED']
 if name=='simulation.log':
  if '/ordinary/integer27/' in full:return ['PASS ALL CNN REMOTE DETAIL cases=27']
  if 'paper_eject_review/' in full:return ['INDEPENDENT_PAPER_BARRIER_PASS cases=50 checks=276']
  if 'r6_core_' in full:return ['SUSPECT_CORE_GOLDEN_PASS tests=22']
  if '/key2_center/' in full:return ['KEY2_ZERO_REGRESSION_PASS cases=15']
  if '/suspect_trial_report_center/' in full:return ['SUSPECT_REPORT_REGRESSION_PASS cases=12']
  if '/doc_key1/integrated/' in full:return ['DOC_KEY1_INTEGRATED_PASS points=351 lines=417']
 # Native ordinary runner names its vsim logs differently. It records an
 # explicit expected pass string in its command metadata where applicable.
 if any('vsim' in str(x).lower() for x in argv):
  text=read(path)
  if 'PASS RTL' in text:return ['PASS RTL']
  if 'CNN_RTL_PASS' in text:return ['CNN_RTL_PASS']
  errors.append('Unclassified simulation marker '+str(path)+' '+label)
 return []

def logcheck(path,digest=None,argv=(),label='',context=''):
 p=Path(path).resolve();h=checkfile(p,digest,'raw_log')
 if h is None:return
 text=read(p)
 if re.search(r'\*\*\s+(?:Error|Fatal):|Traceback \(most recent call last\)',text):errors.append('Error/Fatal in '+str(p))
 needed=required_markers(p,argv,label,context)
 for marker in needed:
  if marker not in text:errors.append('Missing marker '+marker+' in '+str(p))
 observed=[line.lstrip('# ').strip() for line in text.splitlines() if re.match(r'(?:PASS\b|[A-Z0-9_]*PASS\b)',line.lstrip('# ').strip())]
 row=dict(path=str(p),sha256=h,required_pass_markers=needed,observed_pass_markers=observed,
  no_error_fatal=True if not re.search(r'\*\*\s+(?:Error|Fatal):',text) else False)
 if str(p) in log_rows:
  row['required_pass_markers']=sorted(set(row['required_pass_markers']+log_rows[str(p)]['required_pass_markers']))
 log_rows[str(p)]=row

def visit(path,expected=None):
 p=Path(path).resolve();h=checkfile(p,expected,'receipt')
 if h is None or p in visited:return
 visited.add(p);v=load(p)
 state=v.get('status') if isinstance(v,dict) else None
 # Build-plan metadata is an input descriptor, not an execution receipt.
 if state and not state.startswith('PASS') and p.name not in ['BUILD_PLAN.json','SOURCE_MANIFEST.json']:
  errors.append('Non-PASS receipt '+str(p)+' '+state)
 receipt_rows[str(p)]=dict(path=str(p),sha256=h,status=state)
 walk(v,p)

def walk(v,parent):
 if isinstance(v,list):
  for x in v:walk(x,parent)
 elif isinstance(v,dict):
  if isinstance(v.get('path'),str) and isinstance(v.get('sha256'),str):
   p=resolve(v['path'],parent);checkfile(p,v['sha256'])
   if p.suffix=='.log':logcheck(p,v['sha256'],label=v.get('name',''),context=str(parent))
   elif p.suffix=='.json' and v.get('name') not in ['contract']:visit(p,v['sha256'])
  log=v.get('log')
  if isinstance(log,str):
   p=resolve(log,parent);logcheck(p,v.get('log_sha256') or v.get('sha256'),
    argv=v.get('command',v.get('argv',[])),label=v.get('label',v.get('phase','')),context=str(parent))
  for key in ['source_before','source_after','source_hashes','source_sha256','source_sha256_before','source_sha256_after','input_hashes','artifact_sha256','tested_inputs']:
   values=v.get(key)
   if isinstance(values,dict):
    for name,digest in values.items():
     if isinstance(digest,str) and re.fullmatch('[0-9a-fA-F]{64}',digest):
      p=resolve(name,parent);checkfile(p,digest,'source_or_fixture');source_pins[str(p.resolve())]=digest.upper()
  for key,x in v.items():
   if key in ['results','result','report','receipt'] and isinstance(x,str) and x.endswith('.json'):
    p=resolve(x,parent)
    if p.is_file():visit(p)
   elif key=='receipts' and isinstance(x,list):
    for row in x:visit(resolve(row['path'],parent),row['sha256'])
   else:walk(x,parent)
manifest=FREEZE/'SOURCE_MANIFEST.json';frozen=load(manifest)['files']
prod=[]
for rel,row in frozen.items():
 if not rel.startswith(('01_rtl/','shared/','04_pin/','model/','main/')):continue
 source=ROOT/rel;snapshot=FREEZE/rel
 checkfile(source,row['sha256'],'current_production');checkfile(snapshot,row['sha256'],'frozen_production')
 prod.append(dict(relative=rel,current_path=str(source),freeze_path=str(snapshot),sha256=row['sha256']))
assert load(AGG)['status']=='PASS_CURRENT_PAPER_R2_PRESERVED'
assert len(load(AGG)['commands'])==12
for path in [AGG,PAPER,DOC,INDEPENDENT]:visit(path)
# Explicit original-review proof has command names without log filenames.
review=INDEPENDENT.parent/'REVIEW.json'
for item in load(INDEPENDENT)['logs']:
 logcheck(Path(item['path']),item['sha256'],argv=['vsim.exe'] if item['name']=='simulation' else [],label=item['name'])
# Every requested raw simulation must have a prescribed contract marker.
for row in log_rows.values():
 if 'simulation' in Path(row['path']).name and not row['required_pass_markers']:
  errors.append('No mandatory simulation PASS marker '+row['path'])
errors=sorted(set(errors))
v=dict(status='PASS_CURRENT_BEHAVIOR_EVIDENCE' if not errors else 'FAIL',
 generated_utc=datetime.now(timezone.utc).isoformat(),design=str(ROOT),freeze=str(FREEZE),
 source_manifest=dict(path=str(manifest),sha256=sha(manifest)),
 production_sources=prod,primary_reports=[dict(path=str(p),sha256=sha(p)) for p in [AGG,PAPER,DOC,INDEPENDENT]],
 preserved_groups=load(AGG)['commands'],
 recursive_receipts=list(receipt_rows.values()),raw_logs=list(log_rows.values()),
 checked_references=list(file_refs.values()),checked_reference_count=len(file_refs),
 error_count=len(errors),errors=errors,
 coverage=['ordinary CNN input/features/logits/class/confidence integer replay','PCB model features/logits/score/margin/SUSPECT',
 'shared CCL crop/DDR/pipeline snapshot lifetimes and cancel/reentry','CNN current-candidate publication and confirmation',
 'KEY1 immutable CNN/PCB snapshot and document write confirmation','KEY2 consecutive final-ok square/newline/G92',
 'KEY2 longpress roller feed/freshIdle/G92Y0/finalACK page clear','KEY3 reset and KEY4 transport stop/recovery',
 'actual captured document image/skeleton/planner/351 points/417 G-code byte identity','HXA/FIFO/DDR behavioral reader',
 'both-links 12-mode-reentry scenarios plus accepted DRAW retention and local MAC failure'],
 hardware_status='NOT_RUN',localization_accuracy='EXPLORATORY_NOT_PASSED',
 limitations=['Behavioral DDR/MAC/UART/primitive models are explicitly identified in raw receipts; physical timing/CDC/DRC and mechanics require independent build and hardware checks.',
 'Model data and suspect localization algorithm unchanged; these regressions do not establish defect localization accuracy.',
 'The original main HXA source is a read-only delivered-version protocol stimulus in paired reentry tests.'])
out=AGG.parent/'CURRENT_BEHAVIOR_EVIDENCE.json';out.write_text(json.dumps(v,indent=2)+'\n')
print(json.dumps(dict(status=v['status'],report=str(out),sha256=sha(out),refs=len(file_refs),logs=len(log_rows),errors=errors)))
raise SystemExit(0 if not errors else 1)
