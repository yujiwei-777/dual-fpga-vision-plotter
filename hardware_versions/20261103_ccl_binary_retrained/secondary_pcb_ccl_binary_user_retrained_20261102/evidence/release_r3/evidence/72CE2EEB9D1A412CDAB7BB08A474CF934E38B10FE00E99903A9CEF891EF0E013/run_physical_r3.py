"""Run only hash-bound r3 physical stages, preserving parent failures."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,time
BUILD=Path('E:/codex_pcb_binary_ccl_retrained_20261102_r3');TD=Path('E:/td/bin/td_commands_prompt.exe');NAME='secondary_cnn_multibox'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def put(p,v):Path(p).write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
def require(ok,m):
    if not ok:raise ValueError(m)
def validate():
    plan=load(BUILD/'BUILD_PLAN.json');require(sha(BUILD/'SOURCE_MANIFEST.json')==plan['source_manifest_sha256'],'Manifest drift')
    for rel,row in load(BUILD/'SOURCE_MANIFEST.json')['files'].items():require(sha(BUILD/rel)==row['sha256'],'Frozen input drift '+rel)
    return load(BUILD/'PHYSICAL_CONTINUATION.json')
def phase(label):
    c=validate();row=c['phases'][label];script=BUILD/row['script'];log=BUILD/row['log'];inv=BUILD/row['invocation'];phy=BUILD/'runs/phy_1'
    require(not log.exists() and not inv.exists(),'Refusing overwrite phase '+label);log.parent.mkdir(exist_ok=True)
    inp=BUILD/'inherited/r2/runs/phy_1'/ (NAME+'_place_checkpoint.db') if label=='resume_place' else phy/(NAME+('_place.db' if label=='route' else '_pr.db'))
    out=phy/(NAME+('_place.db' if label=='resume_place' else '_pr.db'))
    require(inp.is_file(),'Missing input DB '+str(inp));pins={str(inp):sha(inp)}
    rec={'phase':label,'status':'RUNNING','started_ns':time.time_ns(),'cwd':str(script.parent),'command':[str(TD),script.name],'script':str(script),'script_sha256':sha(script),'input_artifact_sha256':pins};put(inv,rec)
    with log.open('xb') as f:r=subprocess.run([str(TD),script.name],cwd=script.parent,stdout=f,stderr=subprocess.STDOUT)
    s=log.read_text(encoding='utf-8-sig',errors='replace');errors=re.findall(r'(?m)^.*(?:[A-Z]+-\d+\s+(?:ERROR|FATAL)|MAPPING_ERROR|PHYSICAL_RESUME_FAILED|TD_READONLY_REIMPORT_FAIL|BUILD_FAILED).*$',s)
    passed=r.returncode==0 and not errors and out.is_file()
    if label=='resume_place':passed=passed and 'PHYSICAL_PLACE_CHECKPOINT_REPROVED' in s
    if label=='route':passed=passed and (phy/'.opt_route.end.f').is_file() and not (phy/'.opt_route.error.f').exists()
    if label=='readonly':passed=passed and 'TD_READONLY_REIMPORT_PASS' in s and sha(out)==pins[str(inp)]
    rec.update(status='PASS_TOOL_INVOCATION' if passed else 'FAILED_TOOL_INVOCATION',exit_code=r.returncode,finished_ns=time.time_ns(),log_sha256=sha(log),errors=errors,output_artifact_sha256={str(out):sha(out)} if out.is_file() else {});put(inv,rec)
    require(passed,'Phase failed '+label+'; retain '+str(log));validate();print(label+' PASS',flush=True)
def main():
    p=argparse.ArgumentParser();p.add_argument('phase',choices=['resume_place','route','readonly','physical']);a=p.parse_args()
    for label in (['resume_place','route'] if a.phase=='physical' else [a.phase]):phase(label)
if __name__=='__main__':main()
