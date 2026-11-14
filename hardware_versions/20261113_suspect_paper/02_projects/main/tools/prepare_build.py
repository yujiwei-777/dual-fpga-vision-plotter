"""Create an independent main-board source variant and clean build freeze."""
from pathlib import Path
import hashlib, json, re, shutil, subprocess, sys, xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
WORKSPACE=ROOT.parent
BASE=WORKSPACE/'main_pcb_operator_ui_cn_font_shift1_dynamic_osd_20261113'
CAND=WORKSPACE/'main_pcb_suspect_center_candidate_20261113'
OLD_BUILD=Path('E:/codex_pcb_operator_dynamic_osd_main_20261113_r2')
BUILD=Path('E:/codex_pcb_suspect_center_main_20261113_r1')
RUN_REL=Path('01_rtl/imgq_gain_m/main/td_project_display_noise_v8')
HDL_REL=Path('01_rtl/imgq_gain_m/main/user_source/hdl_source')
NAME='camera_to_dsi_display_720p60_cnn_multibox'

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def write(p,obj): p.write_text(json.dumps(obj,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def assert_plain(tree):
    for p in [tree,*tree.rglob('*')]:
        s=p.lstat()
        if p.is_symlink() or getattr(s,'st_file_attributes',0)&0x400 or (p.is_file() and s.st_nlink>1):
            raise RuntimeError(f'Refusing linked input: {p}')

if BUILD.exists() or (ROOT/'01_rtl').exists(): raise SystemExit('Refusing existing prepared variant/build')
manifest=json.loads((CAND/'SOURCE_MANIFEST.json').read_text(encoding='utf-8'))
bit=BASE/'artifacts/dual_fpga_main_20261113_pcb_operator_dynamic_osd_diagnostic.bit'
assert sha(bit)==manifest['baseline_bit_sha256']
for r in manifest['changes']:
    assert sha(Path(r['source']))==r['source_sha256']
    assert sha(Path(r['candidate']))==r['candidate_sha256']
for folder in ('01_rtl','04_pin','tests'):
    assert_plain(BASE/folder)
    shutil.copytree(BASE/folder,ROOT/folder)
for folder in ('baseline_reference','reports','artifacts'): (ROOT/folder).mkdir()
for r in manifest['changes']: shutil.copy2(r['candidate'],ROOT/HDL_REL/Path(r['source']).name)
shutil.copy2(CAND/'CHANGE.patch',ROOT/'baseline_reference/CHANGE.patch')
shutil.copy2(CAND/'SOURCE_MANIFEST.json',ROOT/'baseline_reference/CANDIDATE_MANIFEST.json')
shutil.copytree(CAND/'tests',ROOT/'tests/suspect_center')
shutil.copy2(CAND/'tools/run_regression.py',ROOT/'baseline_reference/run_candidate_regression.py')
for name in ('td_release_audit.py','release_audit_config.json'):
    shutil.copy2(OLD_BUILD/'tools'/name,ROOT/'tools'/name)
shutil.copytree(OLD_BUILD/'tools/physical_capacity',ROOT/'tools/physical_capacity')
write(ROOT/'BASELINE.json',{'baseline':str(BASE),'baseline_build':str(OLD_BUILD),
    'baseline_bit':str(bit),'baseline_bit_sha256':sha(bit),
    'candidate_manifest_sha256':sha(CAND/'SOURCE_MANIFEST.json'),
    'candidate_test':'reports/20261113T123737_281618Z/RESULT.json',
    'scope':'Main SUSPECT center cross only; existing classification, region, protocol and secondary unchanged.',
    'hardware_status':'NOT_RUN'})
(ROOT/'README_CN.md').write_text('# PCB 疑似区域中心标记主板\n\n独立主板变体，在现有黄色疑似区域中增加短十字，中心采用原图半开坐标，与副板 KEY1 报告一致。保留按需操作面板、中文 OSD、普通 CNN、文档、上退纸及全部原功能。\n\n此显示改动不提高定位准确率；缺焊盘定位仍未达到既定 80% 目标。实际综合/布线结果以本工程新报告为准。实板状态：`NOT_RUN`。\n',encoding='utf-8')

BUILD.mkdir()
for folder in ('01_rtl','04_pin','tools','tests'): shutil.copytree(ROOT/folder,BUILD/folder)
for f in ('BASELINE.json','README_CN.md'): shutil.copy2(ROOT/f,BUILD/f)
(BUILD/'audits').mkdir()
shutil.copy2(OLD_BUILD/'audits/summarize_readonly.py',BUILD/'audits/summarize_readonly.py')
run=BUILD/RUN_REL
for path in (run/(NAME+'.al'),run/(NAME+'.prj')):
    raw=path.read_text(encoding='utf-8-sig')
    raw=re.sub(r'&(?!#?\w+;)', '&amp;',raw)
    raw=re.sub(r'(<\/?[A-Za-z_][\w:]*)::',lambda m:m[1]+'_TD_DOUBLE_COLON_',raw)
    tree=ET.fromstring(raw);tree.set('Path',run.as_posix());ET.indent(tree)
    path.write_text('<?xml version="1.0" encoding="UTF-8"?>\n'+ET.tostring(tree,encoding='unicode').replace('_TD_DOUBLE_COLON_','::')+'\n',encoding='utf-8')
cmd=[sys.executable,str(BUILD/'tools/td_release_audit.py'),'snapshot','--root',str(BUILD),
    '--run',str(run),'--name',NAME,'--al',str(run/(NAME+'.al')),
    '--config',str(BUILD/'tools/release_audit_config.json'),'--output',str(run/'source_snapshot.json')]
cp=subprocess.run(cmd,capture_output=True,text=True)
assert cp.returncode==0 and json.loads((run/'source_snapshot.json').read_text(encoding='utf-8-sig'))['passed'], cp.stdout+cp.stderr
records={}
for p in sorted(x for x in BUILD.rglob('*') if x.is_file() and x.relative_to(BUILD).parts[0] in ('01_rtl','04_pin','tools','tests')):
    rel=p.relative_to(BUILD).as_posix();records[rel]={'sha256':sha(p),'bytes':p.stat().st_size}
write(BUILD/'SOURCE_MANIFEST.json',{'schema':'main-suspect-center-source-manifest-v1','files':records})
plan={'status':'PREPARED_NOT_STARTED','source_root':str(ROOT),'build_root':str(BUILD),
    'source_manifest_sha256':sha(BUILD/'SOURCE_MANIFEST.json'),'limits_strict_less_than':{'slice':95,'eram':90,'dsp':95},
    'hardware_status':'NOT_RUN','bitgen_allowed':False}
write(BUILD/'BUILD_PLAN.json',plan);write(ROOT/'reports/BUILD_PLAN.json',plan)
print(json.dumps({'build':str(BUILD),'files':len(records),'manifest_sha256':plan['source_manifest_sha256']},ensure_ascii=False))
