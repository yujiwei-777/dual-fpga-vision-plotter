"""Source-only freeze and explicit vendor phases for CN OSD / roller eject pair.

Never uses work/, never alters either released control, and never emits a bit.
Per-board changed production files must match an explicit reviewed scope file.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import copy
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET
sys.dont_write_bytecode=True

ROOT=Path(__file__).resolve().parent
BASE=Path(r'D:/program/fpga/lab_ex3_osd_SC500_720P')
CONFIG={
 'main':{'source':'main_pcb_operator_ui_cn_font_shift1_20261113','baseline':'main_pcb_operator_ui_20261111',
         'frozen':'E:/codex_pcb_operator_ui_main_20261111_r7',
         'project':'01_rtl/imgq_gain_m/main/td_project_display_noise_v8/camera_to_dsi_display_720p60_cnn_multibox.al',
         'name':'camera_to_dsi_display_720p60_cnn_multibox',
         'build':'E:/codex_pcb_operator_cn_main_20261112_r2',
         'run':'01_rtl/imgq_gain_m/main/td_project_display_noise_v8'},
 'secondary':{'source':'secondary_pcb_operator_ui_eject_opt_20261113','baseline':'secondary_pcb_operator_ui_20261111',
         'frozen':'E:/codex_pcb_operator_ui_secondary_20261111_r9_index',
         'project':'runs/syn_1/secondary_cnn_multibox.al','name':'secondary_cnn_multibox',
         'build':'E:/codex_paper_eject_secondary_opt_20261113_r1','run':'runs/syn_1'}
}
TD=Path('E:/td/bin/td_commands_prompt.exe')


def require(ok,msg):
    if not ok:raise RuntimeError(msg)
def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):
    h=hashlib.sha256()
    with Path(p).open('rb') as f:
        for block in iter(lambda:f.read(1048576),b''):h.update(block)
    return h.hexdigest().upper()
def put(p,v):
    p=Path(p);p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(json.dumps(v,ensure_ascii=False,indent=2,allow_nan=False)+'\n',encoding='utf-8')
def safe(p,root):
    p=Path(p).resolve();root=Path(root).resolve()
    require(p.is_relative_to(root) and 'work' not in [s.lower() for s in p.parts],'Unsafe source/output '+str(p))
    return p
def xml(p):
    text=Path(p).read_text(encoding='utf-8-sig')
    text=re.sub(r'&(?!#?\w+;)', '&amp;',text)
    text=re.sub(r'(<\/?[A-Za-z_][\w:]*)::',lambda m:m[1]+'_TD_DOUBLE_COLON_',text)
    return ET.fromstring(text)
def helper(board):
    c=CONFIG[board]
    p=BASE/c['baseline']/'tools/build_suspect_trial.py'
    retained_identity(board,[p])
    spec=importlib.util.spec_from_file_location('retained_'+board+'_build_helper',p)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
    return m
def retained_identity(board,paths):
    c=CONFIG[board];old=BASE/c['baseline']
    release=load(old/'artifacts/RELEASE_MANIFEST.json');entry=release['signoff_toolchain']
    require(sha(entry['path'])==entry['sha256'],'Retained validator inventory drift')
    inventory=load(entry['path'])['files']
    for p in paths:
        rel=Path(p).resolve().relative_to(old.resolve()).as_posix()
        require(rel in inventory and sha(p)==inventory[rel]['sha256'],'Retained validator differs from released inventory '+rel)
def source_rel(path,project,c):
    p=Path(path);p=(p if p.is_absolute() else project.parent/p).resolve()
    for root in [BASE/c['source'],Path(c['frozen']),BASE/c['baseline']]:
        if p.is_relative_to(root.resolve()):return p.relative_to(root.resolve()).as_posix()
    raise RuntimeError('External project declaration '+str(p))


def scope(board):
    c=CONFIG[board];src=BASE/c['source'];old=Path(c['frozen'])
    config=load(ROOT/(board+'_scope.json'))
    manifest=load(old/'SOURCE_MANIFEST.json')['files']
    release=load(BASE/c['baseline']/'artifacts/RELEASE_MANIFEST.json')
    require(sha(release['bit']['path'])==release['bit']['sha256'],'Control bit drift')
    changes=[];unmodified=0;inputs={}
    for rel,row in manifest.items():
        previous=safe(old/rel,old)
        require(sha(previous)==row['sha256'],'Frozen control source drift '+rel)
        # Generated project aliases / old source receipts are regenerated.
        if rel.endswith(('source_snapshot.json','.prj','.al')) or rel.startswith('tools/'):
            continue
        current=safe(src/rel,src)
        require(current.is_file(),'Missing current frozen dependency '+str(current))
        require(not current.is_symlink() and current.stat().st_nlink==1,'Linked input '+str(current))
        digest=sha(current)
        if digest!=row['sha256']:
            require(rel in config['allowed_production_changes'],'Unexpected source change '+rel)
            changes.append({'path':rel,'baseline_sha256':row['sha256'],'sha256':digest})
        else:unmodified+=1
        inputs[rel]=current
    for rel in config.get('new_production_sources',[]):
        require(rel not in inputs,'Duplicate new source '+rel)
        inputs[rel]=safe(src/rel,src);require(inputs[rel].is_file(),'Missing new source '+rel)
        changes.append({'path':rel,'baseline_sha256':None,'sha256':sha(inputs[rel])})
    require(set(r['path'] for r in changes)==set(config['expected_changed_sources']),'Changed source set differs from reviewed scope')
    project=src/c['project'];tree=xml(project)
    old_project=old/c['project']
    if not old_project.is_file() and board=='secondary':old_project=old/'runs/syn_1/secondary_cnn_multibox.al'
    oldtree=xml(old_project)
    def semantic(n):return None if n is None else [n.tag,dict(n.attrib),(n.text or '').strip(),[semantic(x) for x in n]]
    for tag in ['Name','HardWare','TOP_MODULE','Configurations','Runs','MultiSeed']:
        require(semantic(tree.find(tag))==semantic(oldtree.find(tag)),'Project setting drift '+tag)
    declarations=[]
    for group in tree.findall('Source_Files/*'):
        for node in group.findall('File'):
            rel=source_rel(node.attrib['Path'],project,c)
            require(rel in inputs,'Undeclared freeze dependency '+rel)
            declarations.append({'group':group.tag,'path':rel,'attributes':[(a.attrib['Name'],a.attrib['Val']) for a in node.findall('FileInfo/Attr')]})
    baseline_decl=[]
    for group in oldtree.findall('Source_Files/*'):
        for node in group.findall('File'):
            baseline_decl.append({'group':group.tag,'path':source_rel(node.attrib['Path'],old_project,c),
                                  'attributes':[(a.attrib['Name'],a.attrib['Val']) for a in node.findall('FileInfo/Attr')]})
    require(all(d in declarations for d in baseline_decl),'Baseline declaration removed/changed')
    require(all(d in baseline_decl or d['path'] in config.get('new_production_sources',[]) for d in declarations),'Unexpected new declaration')
    result={'status':'SCOPE_PASS','board':board,'source_root':str(src),'baseline_frozen':str(old),
            'control_bit':release['bit'],'baseline_source_manifest_sha256':sha(old/'SOURCE_MANIFEST.json'),
            'unchanged_inputs':unmodified,'production_changes':changes,'declarations':declarations,
            'model_weights_and_constraints_unchanged':all(not r['path'].startswith(('model/','04_pin/')) for r in changes),
            'inputs':{rel:{'sha256':sha(p),'bytes':p.stat().st_size} for rel,p in inputs.items()}}
    put(ROOT/(board+'_SCOPE_REVIEW.json'),result)
    return c,src,inputs,tree,result


def lint(board):
    c,src,inputs,tree,result=scope(board)
    files=[]
    for group in tree.findall('Source_Files/*'):
        if group.tag!='Verilog':continue
        for n in group.findall('File'):
            attrs={a.attrib['Name']:a.attrib['Val'] for a in n.findall('FileInfo/Attr')}
            files.append((int(attrs.get('CompileOrder','0')),inputs[source_rel(n.attrib['Path'],src/c['project'],c)]))
    files=[p for _,p in sorted(files,key=lambda x:x[0])]
    out=Path('E:/codex_operator_update_'+board+'_lint_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'));out.mkdir()
    env=dict(os.environ,LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT',MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT')
    commands=[['E:/model/win64/vlib.exe','rtl_lib'],['E:/model/win64/vlog.exe','-lint','-work','rtl_lib','+define+SYNTHESIS',
              *['+incdir+'+p for p in sorted({p.parent.as_posix() for p in files}|{(src/c['project']).parent.as_posix()})],*map(str,files)]]
    checks=[]
    for i,command in enumerate(commands):
        cp=subprocess.run(command,cwd=out,env=env,capture_output=True)
        log=out/f'phase_{i}.log';log.write_bytes(cp.stdout+cp.stderr)
        text=log.read_text(encoding='utf-8-sig',errors='replace')
        passed=cp.returncode==0 and not re.search(r'\*\*\s+(Error|Fatal):',text)
        checks.append({'command':command,'log':str(log),'sha256':sha(log),'passed':passed})
        require(passed,'Lint failed '+str(log))
    scope(board)
    put(ROOT/(board+'_LINT.json'),{'status':'SYNTAX_PASS_NOT_ELABORATED','source_scope_sha256':sha(ROOT/(board+'_SCOPE_REVIEW.json')),'checks':checks})
    print(json.dumps({'board':board,'status':'SYNTAX_PASS_NOT_ELABORATED','path':str(out)}))


def prepare(board,run):
    c,src,inputs,tree,result=scope(board)
    lint_review=load(ROOT/(board+'_LINT.json'))
    require(lint_review['status']=='SYNTAX_PASS_NOT_ELABORATED','Current lint required')
    require(lint_review['source_scope_sha256']==sha(ROOT/(board+'_SCOPE_REVIEW.json')),
            'Sources/scope changed after lint; rerun current lint before freezing')
    run=Path(run).resolve();require(run.drive.upper()=='E:' and not run.exists(),'Fresh E: build required')
    run.mkdir();records={}
    for rel,source in inputs.items():
        dest=run/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,dest)
        require(sha(dest)==result['inputs'][rel]['sha256']==sha(source),'Freeze drift '+rel)
        records[rel]={'sha256':sha(dest),'bytes':dest.stat().st_size,'origin':str(source)}
    targets=[run/c['run']] if board=='main' else [run/'runs/syn_1',run/'runs/phy_1']
    for target in targets:
        target.mkdir(parents=True,exist_ok=True);t=copy.deepcopy(tree);t.set('Path',target.as_posix())
        for group in t.findall('Source_Files/*'):
            for node in group.findall('File'):
                rel=source_rel(node.attrib['Path'],src/c['project'],c)
                node.set('Path',os.path.relpath(run/rel,target).replace('\\','/'))
        ET.indent(t);text=ET.tostring(t,encoding='unicode').replace('_TD_DOUBLE_COLON_','::')
        for ext in ['al','prj']:
            dest=target/(c['name']+'.'+ext);dest.write_text('<?xml version="1.0" encoding="UTF-8"?>\n'+text+'\n',encoding='utf-8')
            records[dest.relative_to(run).as_posix()]={'sha256':sha(dest),'bytes':dest.stat().st_size,'origin':str(src/c['project'])}
    # Recompute the actual include/IP/readmem closure for this fresh build.
    # The audit implementation/config is retained byte-for-byte, never its PASS.
    old=Path(c['frozen']);baseline_files=load(old/'SOURCE_MANIFEST.json')['files']
    audit_config='release_audit_config.json' if board=='main' else 'binary_source_audit_config.json'
    support=['tools/td_release_audit.py','tools/'+audit_config]
    support += [p for p in baseline_files if p.startswith('tools/physical_capacity/')]
    for rel in support:
        source=old/rel;require(sha(source)==baseline_files[rel]['sha256'],'Audit support drift '+rel)
        dest=run/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,dest)
        records[rel]={'sha256':sha(dest),'bytes':dest.stat().st_size,'origin':str(source)}
    spec=importlib.util.spec_from_file_location('current_source_closure_'+board,run/'tools/td_release_audit.py')
    audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit)
    snapshots=[]
    for target in targets:
        closure=audit.collect(argparse.Namespace(root=run,run=target,name=c['name'],al=None,
            config=run/'tools'/audit_config,extra=[]))
        path=target/'source_snapshot.json';put(path,closure)
        records[path.relative_to(run).as_posix()]={'sha256':sha(path),'bytes':path.stat().st_size,'origin':None}
        snapshots.append({'run':str(target),'passed':closure['passed'],'errors':closure['errors']})
    put(run/'SOURCE_MANIFEST.json',{'files':records})
    put(run/'BUILD_PLAN.json',{'status':'PREPARED_NOT_STARTED','board':board,'build_root':str(run),'source_root':str(src),
        'source_manifest_sha256':sha(run/'SOURCE_MANIFEST.json'),'scope':result,'snapshots':snapshots,
        'limits_strict_less_than':{'slice':95,'eram':90,'dsp':95},
        'bitgen_allowed':False,'hardware_status':'NOT_RUN'})
    put(ROOT/(board+'_BUILD_INDEX.json'),{'path':str(run),'plan_sha256':sha(run/'BUILD_PLAN.json')})
    require(all(s['passed'] for s in snapshots),'Current source closure failed '+str(snapshots))
    print(json.dumps({'status':'PREPARED_NOT_STARTED','board':board,'path':str(run),'inputs':len(records)}))


def validate(run,board):
    run=Path(run).resolve();plan=load(run/'BUILD_PLAN.json')
    require(plan['board']==board and Path(plan['build_root']).resolve()==run,'Wrong build')
    require(sha(run/'SOURCE_MANIFEST.json')==plan['source_manifest_sha256'],'Manifest drift')
    for rel,row in load(run/'SOURCE_MANIFEST.json')['files'].items():require(sha(safe(run/rel,run))==row['sha256'],'Frozen drift '+rel)
    return run,plan


def execute(board,phase,run):
    c=CONFIG[board];run,plan=validate(run,board)
    if board=='main':directory=run/c['run'];script='run_display_noise_'+{'syn':'synth','place':'place','route':'route'}[phase]+'.tcl'
    else:directory=run/('runs/syn_1' if phase=='syn' else 'runs/phy_1');script={'syn':'run.tcl','place':'run_place.tcl','route':'run_route.tcl'}[phase]
    if phase!='syn':
        prior=(run/c['run']) if board=='main' else run/('runs/syn_1' if phase=='place' else 'runs/phy_1')
        require((prior/('.'+{'place':'opt_gate','route':'opt_place'}[phase]+'.end.f')).is_file(),'Prior phase did not finish')
    log=run/'logs'/(phase+'.log');require(not log.exists(),'Refusing tool log overwrite');log.parent.mkdir(exist_ok=True)
    runner=log.with_name(phase+'_RUNNER_AT_EXECUTION.py');shutil.copy2(Path(__file__),runner)
    receipt={'status':'RUNNING','phase':phase,'command':[str(TD),script],'cwd':str(directory),
        'source_manifest_sha256':plan['source_manifest_sha256'],'script_sha256':sha(directory/script),
        'td_launcher_sha256':sha(TD),'runner_snapshot':{'path':str(runner),'sha256':sha(runner)}}
    put(log.with_suffix('.json'),receipt)
    with log.open('xb') as f:cp=subprocess.run([str(TD),script],cwd=directory,stdout=f,stderr=subprocess.STDOUT)
    text=log.read_text(encoding='utf-8-sig',errors='replace')
    errors=re.findall(r'(?m)^.*(?:[A-Z]+-\d+\s+(?:ERROR|FATAL)|\*\*\s+(?:Error|Fatal):|BUILD_FAILED|MAPPING_ERROR).*$',text)
    markers=[str(p) for p in directory.glob('.*.error.f')]
    marker={'syn':'opt_gate','place':'opt_place','route':'opt_route'}[phase]
    db=directory/(c['name']+{'syn':'_gate.db','place':'_place.db','route':'_pr.db'}[phase])
    passed=cp.returncode==0 and not errors and not markers and (directory/('.'+marker+'.end.f')).is_file() and db.is_file()
    receipt.update(status='PASS_TOOL_INVOCATION' if passed else 'FAILED_TOOL_INVOCATION',exit_code=cp.returncode,errors=errors,error_markers=markers,log_sha256=sha(log))
    put(log.with_suffix('.json'),receipt)
    m=helper(board);metrics=m.metrics(directory,phase!='syn')
    metrics.update(board=board,phase=phase,tool_pass=passed,bitgen_allowed=False,source_manifest_sha256=plan['source_manifest_sha256'])
    put(run/({'syn':'SYNTHESIS','place':'PLACE','route':'ROUTE'}[phase]+'_REVIEW.json'),metrics)
    validate(run,board)
    print(json.dumps(metrics,ensure_ascii=False,indent=2));require(passed,'Vendor phase failed '+str(log))


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('board',choices=CONFIG);p.add_argument('action',choices=['scope','lint','prepare','inspect','syn','place','route']);p.add_argument('--run',type=Path)
    a=p.parse_args();run=a.run or Path(CONFIG[a.board]['build'])
    if a.action=='scope':print(json.dumps(scope(a.board)[-1],ensure_ascii=False,indent=2))
    elif a.action=='lint':lint(a.board)
    elif a.action=='prepare':prepare(a.board,run)
    elif a.action=='inspect':validate(run,a.board);print('FROZEN_INPUTS_PASS')
    else:execute(a.board,a.action,run)


if __name__=='__main__':main()


