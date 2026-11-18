"""Publish only this variant's strictly audited fresh routed diagnostic bit."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,os,re,shutil,subprocess,sys
sys.dont_write_bytecode=True
from audit_current_route import (BUILD,SOURCE,RUN,NAME,TD,check_sources,check_phases,bound_inputs,
    no_changed,load,read,sha,put,ref,require,stamp)
STEM='dual_fpga_main_20261118_cnn_multicoord_diagnostic'

def behavior():
    guideptr=load(SOURCE/'reports/GUIDE_VALIDATION_LATEST.json')
    require(sha(guideptr['path'])==guideptr['sha256'],'Guide validation pointer drift')
    guide=load(guideptr['path'])
    require(guide['status']=='PASS' and guide['source_manifest_sha256']==sha(BUILD/'SOURCE_MANIFEST.json'),'Guide validation/freeze mismatch')
    for path,h in guide['inputs'].items():require(sha(path)==h,'Guide source drift')
    for step in guide['steps']:require(step['exit_code']==0 and sha(step['log'])==step['sha256'],'Guide log drift')
    require('DOC_CENTER80_GUIDE_PASS' in read(guide['steps'][-1]['log']),'Guide marker missing')
    paperptr=load(SOURCE/'reports/PAPER_STATUS_VALIDATION_LATEST.json')
    require(sha(paperptr['path'])==paperptr['sha256'],'Paper-status validation pointer drift')
    paper=load(paperptr['path'])
    require(paper['status']=='PASS' and paper['source_manifest_sha256']==sha(BUILD/'SOURCE_MANIFEST.json'),'Paper-status validation/freeze mismatch')
    for path,h in paper['inputs'].items():require(sha(path)==h,'Paper-status input drift')
    for step in paper['test']['steps']:require(step['exit_code']==0 and sha(step['log'])==step['sha256'],'Paper-status log drift')
    require('PAPER_STATUS_DISABLED_PASS' in read(paper['test']['steps'][-1]['log']),'Paper-status marker missing')
    ptr=load(SOURCE/'reports/CNN_PANEL_VALIDATION_LATEST.json'); require(sha(ptr['path'])==ptr['sha256'],'CNN panel validation drift'); panel=load(ptr['path'])
    require(panel['status']=='PASS' and panel['source_manifest_sha256']==sha(BUILD/'SOURCE_MANIFEST.json'),'CNN panel validation/freeze mismatch')
    for path,h in panel['inputs'].items():require(sha(path)==h,'CNN panel input drift')
    for step in panel['test']['steps']:require(step['exit_code']==0 and sha(step['log'])==step['sha256'],'CNN panel log drift')
    require('CNN_PANEL_HIDDEN_PASS' in read(panel['test']['steps'][-1]['log']),'CNN panel marker missing')
    style=load(SOURCE/'reports/STYLE_VALIDATION_LATEST.json'); require(sha(style['path'])==style['sha256'],'Style validation pointer drift'); result=load(style['path']); require(result['status']=='PASS' and result['source_manifest_sha256']==sha(BUILD/'SOURCE_MANIFEST.json'),'Style validation/freeze mismatch')
    for path,h in result['inputs'].items():require(sha(path)==h,'Style input drift')
    for row in result['tests'].values():
        require(row['status']=='PASS','Style regression failure')
        for step in row['steps']:require(step['exit_code']==0 and sha(step['log'])==step['sha256'],'Style regression log drift')
    pointer=load(SOURCE/'reports/VALIDATION_LATEST.json')
    p=Path(pointer['path']);require(sha(p)==pointer['sha256'],'Validation pointer hash drift')
    v=load(p);require(v['status']=='PASS' and v['baseline_unchanged'],'Current functional validation failed')
    require(v['source_manifest_sha256']==sha(BUILD/'SOURCE_MANIFEST.json'),'Validation/freeze mismatch')
    for filename,h in v['inputs'].items():require(sha(filename)==h,'Test input drift: '+filename)
    for row in v['tests'].values():
        require(row['status']=='PASS','Failed test')
        for step in row['steps']:
            require(step['exit_code']==0 and sha(step['log'])==step['sha256'],'Test log drift')
        text=read(row['steps'][-1]['log'])
        require(row['marker'] in text and not re.search(r'\*\* (?:Error|Fatal):',text),'Missing simulation pass')
    for filename,h in load(SOURCE/'baseline_reference/PROTECTED_INPUTS.json').items():
        require(sha(filename)==h,'Protected baseline drift: '+filename)
    region_reports=[]
    for folder in ('center_integration','regression_controls'):
        candidates=sorted((SOURCE/'reports'/folder).glob('*/RESULT.json'))
        require(candidates,'Missing current region/control regression')
        p=candidates[-1];r=load(p)
        require(r['status']=='PASS' and r['frozen_manifest_sha256']==sha(BUILD/'SOURCE_MANIFEST.json'),
            'Wrong region/control regression freeze')
        for filename,row in r['inputs'].items():require(sha(filename)==row['sha256'],'Region input drift')
        groups=[r['result']] if 'result' in r else list(r['tests'].values())
        for group in groups:
            require(group['status']=='PASS','Region test failed')
            for step in group['steps']:
                require(step['returncode']==0 and sha(step['log'])==step['log_sha256'],'Region log drift')
            require(group['marker'] in read(group['steps'][-1]['log']),'Missing region marker')
        region_reports.append(ref(p))
    m=load(BUILD/'SOURCE_MANIFEST.json')['files']
    for rel,row in m.items():
        if rel.startswith(('01_rtl/','04_pin/')) and not rel.endswith(('source_snapshot.json','.al','.prj')):
            require(sha(SOURCE/rel)==row['sha256'],'Current production differs from freeze: '+rel)
    return {'text':ref(Path(pointer['path'])),'region_and_controls':region_reports,'paper_status':ref(Path(paperptr['path']))}

TCL=r'''set build {@RUN@}
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
    report_timing_summary -file "$audit/pre_bitgen.timing"
    report_area -io_info -file "$audit/pre_bitgen.area"
    check_timing -verbose -file "$audit/pre_bitgen.check"
    commit_param -step bitgen
    bitgen -bit $bit
    export_bid $bid
    export_bitgen_param -file "$audit/checked_bitgen_param.f"
    update_timing -mode final
    report_timing_summary -file "$audit/post_bitgen.timing"
    report_area -io_info -file "$audit/post_bitgen.area"
    puts NO_SUSPECT_MAIN_BITGEN_PASS
} reason]} {puts "NO_SUSPECT_MAIN_BITGEN_FAIL: $reason";exit 1}
exit 0
'''

def main():
    a=argparse.ArgumentParser();a.add_argument('--acceptance',type=Path,required=True);args=a.parse_args()
    check_sources();check_phases();validation=behavior();bound=bound_inputs()
    acceptance=load(args.acceptance)
    require(acceptance['passed'] and acceptance['source_manifest_sha256']==sha(BUILD/'SOURCE_MANIFEST.json'),'Wrong route audit')
    for key in ('generic_gate','readonly_summary','physical_capacity'):
        row=acceptance[key];require(sha(row['path'])==row['sha256'],'Audit evidence drift')
        require(load(row['path'])['passed'],'Audit check failed: '+key)
    generic=load(acceptance['generic_gate']['path'])
    spec=importlib.util.spec_from_file_location('timing_parser',BUILD/'audits/summarize_readonly.py')
    parser=importlib.util.module_from_spec(spec);spec.loader.exec_module(parser)
    out=BUILD/'audits/bitgen_r1';require(not out.exists(),'Refusing staged overwrite');out.mkdir()
    bit=out/(STEM+'.bit');bid=out/(STEM+'.bid')
    text=TCL
    for k,v in {'RUN':RUN.as_posix(),'OUT':out.as_posix(),'NAME':NAME,'BIT':bit.as_posix(),'BID':bid.as_posix()}.items():
        text=text.replace('@'+k+'@',v)
    script=out/'bitgen.tcl';script.write_text(text,encoding='utf-8')
    no_changed(bound)
    log=out/'bitgen.log'
    with log.open('xb') as f:cp=subprocess.run([str(TD),script.name],cwd=out,stdout=f,stderr=subprocess.STDOUT)
    no_changed(bound);behavior()
    text=read(log)
    require(cp.returncode==0 and text.splitlines().count('NO_SUSPECT_MAIN_BITGEN_PASS')==1 and
        not re.search(r'\b(?:ERROR|FATAL)\b|NO_SUSPECT_MAIN_BITGEN_FAIL|HDL-5105',text),'Bitgen failed')
    require(bit.stat().st_size>1000000 and bid.stat().st_size>100,'Missing/truncated bit or BID')
    for prefix in ('pre_bitgen','post_bitgen'):
        t=parser.parse_timing(read(out/(prefix+'.timing')));r=parser.parse_area(read(out/(prefix+'.area')))
        require(t['passed'] and r['passed'] and t['metrics_ns']==generic['timing_ns'] and r['resources']==generic['resources'],
            'Bitgen reimport timing/area changed')
    require(parser.parse_check(read(out/'pre_bitgen.check'))['passed_core_static_checks'],'Bitgen static checks failed')
    require(not re.search(r'unconstr_io\s+(?:on|1)|\bignore\w*\s+(?:on|1)',read(out/'checked_bitgen_param.f'),re.I),'Nonstandard bitgen bypass')
    artifacts=SOURCE/'artifacts';dest=artifacts/bit.name;destbid=dest.with_suffix('.bid')
    require(not dest.exists() and not destbid.exists() and not (artifacts/'RELEASE_REPORT.json').exists(),'No overwrite')
    for src,target in ((bit,dest),(bid,destbid)):
        temporary=target.with_suffix(target.suffix+'.part');shutil.copy2(src,temporary)
        require(sha(temporary)==sha(src),'Copy hash mismatch');os.rename(temporary,target)
    receipt={'status':'PASS_DIAGNOSTIC_NOT_RUN','hardware_status':'NOT_RUN','bit':ref(dest),'bid':ref(destbid),
        'source_manifest':ref(BUILD/'SOURCE_MANIFEST.json'),'route_acceptance':ref(args.acceptance),
        'validation':validation,'timing_ns':generic['timing_ns'],'resources':generic['resources'],
        'bitgen_log':ref(log),'inputs_unchanged':True,'completed_utc':stamp(),
        'limitations':['Targeted RTL regressions and static CDC/FIFO/DDR evidence; physical two-board and plotter operation NOT_RUN.']}
    put(artifacts/'RELEASE_REPORT.json',receipt);print(json.dumps(receipt,ensure_ascii=False,indent=2))
if __name__=='__main__':main()
