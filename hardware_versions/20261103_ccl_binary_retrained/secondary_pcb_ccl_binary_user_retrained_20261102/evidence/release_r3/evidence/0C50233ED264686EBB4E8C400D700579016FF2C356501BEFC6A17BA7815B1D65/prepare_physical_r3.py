"""Freeze a physical-only continuation; never claim a new synthesis."""
from pathlib import Path
from datetime import datetime, timezone
import argparse, hashlib, json, shutil

HERE=Path(__file__).resolve().parent
PARENT=Path('E:/codex_pcb_binary_ccl_retrained_20261102_r2')
BUILD=Path('E:/codex_pcb_binary_ccl_retrained_20261102_r3')
PARENT_SHA='92E737ED8B7D585AEAAC64346A130A2AA7A9F2077A70B14A8CE2D036506A57DB'
NAME='secondary_cnn_multibox'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def put(p,v):Path(p).write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
def require(ok,m):
    if not ok:raise ValueError(m)
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--overlay',type=Path,required=True);a=parser.parse_args()
    require(not BUILD.exists(),'Refusing existing r3')
    require(a.overlay.is_file(),'Missing proof overlay')
    require(sha(PARENT/'SOURCE_MANIFEST.json')==PARENT_SHA,'Parent drift')
    parent=load(PARENT/'SOURCE_MANIFEST.json')['files']
    for rel,row in parent.items():require(sha(PARENT/rel)==row['sha256'],'Parent input drift '+rel)
    syn=load(PARENT/'logs/syn.json');require(syn['status']=='PASS_TOOL_INVOCATION' and syn['exit_code']==0 and syn['log_sha256']==sha(PARENT/'logs/syn.log'),'Parent synthesis failed')
    failure=load(PARENT/'logs/place.json');require(failure['status']=='FAILED_TOOL_INVOCATION' and failure['errors']==['SECONDARY_CDC_MAPPING_ERROR place_end u_store/cal_sync_reg[0]_syn_2 REGA_SD requires IMA'],'Unexpected parent failure')
    BUILD.mkdir();copied={};projects={};added={};records={}
    def record(rel):records[rel]={'sha256':sha(BUILD/rel),'bytes':(BUILD/rel).stat().st_size}
    for rel,row in parent.items():
        dest=BUILD/rel;dest.parent.mkdir(parents=True,exist_ok=True)
        if dest.suffix in {'.al','.prj'}:
            s=(PARENT/rel).read_text(encoding='utf-8-sig');dest.write_text(s.replace(PARENT.as_posix(),BUILD.as_posix()),encoding='utf-8')
            projects[rel]={'parent_sha256':row['sha256'],'sha256':sha(dest),'allowed_change':'project_root_only'}
        else:
            shutil.copy2(PARENT/rel,dest);require(sha(dest)==row['sha256'],'Copy mismatch '+rel);copied[rel]={'sha256':sha(dest)}
        record(rel)
    artifacts={}
    rels=['logs/syn.json','logs/syn.log','SYNTHESIS_REVIEW.json','runs/syn_1/'+NAME+'_gate.db','runs/syn_1/'+NAME+'_gate.area','runs/syn_1/'+NAME+'_gate.timing','runs/phy_1/'+NAME+'_place_checkpoint.db','logs/place.json','logs/place.log','runs/phy_1/place.qor']
    rels += [p.relative_to(PARENT).as_posix() for folder in ['runs/syn_1','runs/phy_1'] for p in (PARENT/folder).glob('secondary_*') if p.suffix in {'.rpt','.sdc'} and p.is_file()]
    for rel in sorted(set(rels)):
        source=PARENT/rel;dest=BUILD/'inherited/r2'/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,dest)
        require(sha(dest)==sha(source),'Inherited artifact drift');artifacts[rel]={'sha256':sha(source),'copy':'inherited/r2/'+rel};record('inherited/r2/'+rel)
    def add(rel,content,purpose):
        target=BUILD/rel;target.parent.mkdir(parents=True,exist_ok=True);target.write_text(content,encoding='utf-8');record(rel);added[rel]={'sha256':sha(target),'purpose':purpose}
    add('physical_proof/cdc_cal_lut5a.tcl',a.overlay.read_text(encoding='utf-8-sig'),'Narrow exhaustive proof for packed calibrated decoder; no RTL or numeric timing-budget changes')
    add('physical_proof/prepare_physical_r3.py',Path(__file__).read_text(encoding='utf-8'),'Physical continuation provenance generator')
    add('physical_proof/run_physical_r3.py',(HERE/'run_physical_r3.py').read_text(encoding='utf-8'),'Hash-bound actual tool invocation runner')
    resume='''set build {BUILD_PATH}
cd $build/runs/phy_1
if {[catch {
 import_device ph1_35p.db -package PH1P35MDG324 -speed 3
 open_project secondary_cnn_multibox.al -noanalyze
 import_db $build/inherited/r2/runs/phy_1/secondary_cnn_multibox_place_checkpoint.db
 source ../../04_pin/apply_reset_exceptions.tcl
 source ../../04_pin/apply_cdc_exceptions.tcl
 source ../../physical_proof/cdc_cal_lut5a.tcl
 secondary_apply_phase_timing place_end ../../04_pin/timing.sdc manhattan
 source ../../04_pin/clocktrace_sclk/prove_key3_supervisor_clocktrace.tcl
 secondary_prove_key3_supervisor place_end
 update_timing -mode manhattan
 report_timing_status -file secondary_cnn_multibox_place.ts
 report_timing_summary -file secondary_cnn_multibox_place.timing
 report_area -io_info -file secondary_cnn_multibox_phy.area
 flow_status -file place_resume_flow.status
 report_clock_utilization -file place_clock_utilization.txt
 export_db secondary_cnn_multibox_place.db
 set f [open .resume_place.end.f w];close $f
 puts PHYSICAL_PLACE_CHECKPOINT_REPROVED
} reason]} {puts "PHYSICAL_RESUME_FAILED $reason";exit 1}
exit 0
'''.replace('BUILD_PATH',BUILD.as_posix())
    add('runs/phy_1/run_resume_place.tcl',resume,'Reprove inherited completed place checkpoint; does not execute place or synthesis')
    route=(PARENT/'runs/phy_1/run_route.tcl').read_text(encoding='utf-8-sig')
    route=route.replace('source {../../04_pin/apply_cdc_exceptions.tcl}','source {../../04_pin/apply_cdc_exceptions.tcl}\n  source {../../physical_proof/cdc_cal_lut5a.tcl}')
    add('runs/phy_1/run_route_resume.tcl',route,'Unchanged vendor route sequence plus hash-bound narrow proof overlay')
    ro=(PARENT/'readonly/readonly_reimport.tcl').read_text(encoding='utf-8-sig').replace(PARENT.as_posix(),BUILD.as_posix())
    add('readonly/run_readonly_r3.tcl',ro,'Read-only reimport; root paths only changed from original audit')
    phases={label:{'script':script,'log':'logs/'+label+'.log','invocation':'logs/'+label+'.json'} for label,script in [('resume_place','runs/phy_1/run_resume_place.tcl'),('route','runs/phy_1/run_route_resume.tcl'),('readonly','readonly/run_readonly_r3.tcl')]}
    put(BUILD/'PHYSICAL_CONTINUATION.json',{'schema_version':1,'created_utc':datetime.now(timezone.utc).isoformat(),'parent':{'build_root':str(PARENT),'source_manifest_sha256':PARENT_SHA},'parent_artifacts':artifacts,'copied_parent_files':copied,'project_files':projects,'added_files':added,'phase_inheritance':{'syn':'INHERITED','place_checkpoint':'INHERITED_FAILED_POST_PLACE_PROOF'},'phases':phases,'ordinary_cnn_or_model_change':False,'numeric_constraint_change':False,'hardware_status':'NOT_RUN'});record('PHYSICAL_CONTINUATION.json')
    put(BUILD/'SOURCE_MANIFEST.json',{'files':records})
    put(BUILD/'BUILD_PLAN.json',{'status':'PHYSICAL_ONLY_CONTINUATION','source_root':str(HERE.parents[1]),'build_root':str(BUILD),'source_manifest_sha256':sha(BUILD/'SOURCE_MANIFEST.json'),'parent_source_manifest_sha256':PARENT_SHA,'synthesis':'INHERITED_NOT_RERUN','hardware_status':'NOT_RUN'})
    print(json.dumps({'build':str(BUILD),'source_manifest_sha256':sha(BUILD/'SOURCE_MANIFEST.json'),'inherited_synthesis':True,'files':len(records)},indent=2))
if __name__=='__main__':main()
