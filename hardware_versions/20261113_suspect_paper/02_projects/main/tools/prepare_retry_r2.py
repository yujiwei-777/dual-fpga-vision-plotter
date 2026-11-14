"""Freeze compact center implementation without modifying the failed r1 run."""
from pathlib import Path
import hashlib,json,re,shutil,subprocess,sys,xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
OLD=Path('E:/codex_pcb_suspect_center_main_20261113_r1')
OUT=Path('E:/codex_pcb_suspect_center_main_20261113_r2')
RUN_REL=Path('01_rtl/imgq_gain_m/main/td_project_display_noise_v8')
NAME='camera_to_dsi_display_720p60_cnn_multibox'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def put(p,o):p.write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

if OUT.exists():raise SystemExit('Refusing existing r2 freeze')
archive=ROOT/'reports/r1_place_failure';archive.mkdir()
for f in ('BUILD_PLAN.json','CONTROL_INPUT_INTEGRITY.json'):
    shutil.copy2(ROOT/'reports'/f,archive/f)
for f in ('SOURCE_MANIFEST.json','logs/synth.json','logs/place.json'):
    shutil.copy2(OLD/f,archive/Path(f).name)
for n in ('hx_result_select.v','hdmi_mixer.v','design_top_wrapper.v'):
    shutil.copy2(OLD/'01_rtl/imgq_gain_m/main/user_source/hdl_source'/n,archive/n)
put(archive/'FAILURE.json',{'status':'PLACE_FAILED','run':str(OLD),
    'errors':json.loads((OLD/'logs/place.json').read_text(encoding='utf-8'))['errors'],
    'gate_slice':21389,'baseline_gate_slice':21371,'eram':97,'dsp':37,
    'setup_gate_wns_ns':-1.265,'bitgen_run':False,
    'change':'r2 derives center from existing frame coordinates and shares cross distance arithmetic; exact display preserved.'})

original=ROOT/'tools/run_build_phases.py'
retry=ROOT/'tools/run_build_phases_r2.py'
text=original.read_text(encoding='utf-8')
assert text.count('E:/codex_pcb_suspect_center_main_20261113_r1')==1
retry.write_text(text.replace('E:/codex_pcb_suspect_center_main_20261113_r1','E:/codex_pcb_suspect_center_main_20261113_r2'),encoding='utf-8')
for folder in ('01_rtl','04_pin','tools','tests'):
    for p in [ROOT/folder,*(ROOT/folder).rglob('*')]:
        if p.is_symlink() or getattr(p.lstat(),'st_file_attributes',0)&0x400 or (p.is_file() and p.stat().st_nlink>1):
            raise RuntimeError('Linked input '+str(p))
OUT.mkdir()
for folder in ('01_rtl','04_pin','tools','tests'):
    shutil.copytree(ROOT/folder,OUT/folder,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
for name in ('BASELINE.json','README_CN.md'):shutil.copy2(ROOT/name,OUT/name)
(OUT/'audits').mkdir()
shutil.copy2(OLD/'audits/summarize_readonly.py',OUT/'audits/summarize_readonly.py')
run=OUT/RUN_REL
for path in (run/(NAME+'.al'),run/(NAME+'.prj')):
    raw=path.read_text(encoding='utf-8-sig');raw=re.sub(r'&(?!#?\w+;)', '&amp;',raw)
    raw=re.sub(r'(<\/?[A-Za-z_][\w:]*)::',lambda m:m[1]+'_TD_DOUBLE_COLON_',raw)
    tree=ET.fromstring(raw);tree.set('Path',run.as_posix());ET.indent(tree)
    path.write_text('<?xml version="1.0" encoding="UTF-8"?>\n'+ET.tostring(tree,encoding='unicode').replace('_TD_DOUBLE_COLON_','::')+'\n',encoding='utf-8')
cp=subprocess.run([sys.executable,str(OUT/'tools/td_release_audit.py'),'snapshot','--root',str(OUT),
    '--run',str(run),'--name',NAME,'--al',str(run/(NAME+'.al')),'--config',str(OUT/'tools/release_audit_config.json'),
    '--output',str(run/'source_snapshot.json')],capture_output=True,text=True)
assert cp.returncode==0 and json.loads((run/'source_snapshot.json').read_text(encoding='utf-8-sig'))['passed'],cp.stdout+cp.stderr
records={p.relative_to(OUT).as_posix():{'sha256':sha(p),'bytes':p.stat().st_size}
    for p in sorted(OUT.rglob('*')) if p.is_file() and p.relative_to(OUT).parts[0] in ('01_rtl','04_pin','tools','tests')}
put(OUT/'SOURCE_MANIFEST.json',{'schema':'main-suspect-center-compact-r2-source-manifest-v1','files':records})
plan={'status':'PREPARED_NOT_STARTED','source_root':str(ROOT),'build_root':str(OUT),
    'source_manifest_sha256':sha(OUT/'SOURCE_MANIFEST.json'),'phase_runner_sha256':sha(retry),
    'limits_strict_less_than':{'slice':95,'eram':90,'dsp':95},'hardware_status':'NOT_RUN','bitgen_allowed':False}
put(OUT/'BUILD_PLAN.json',plan);put(ROOT/'reports/BUILD_PLAN_R2.json',plan)
print(json.dumps({'build':str(OUT),'files':len(records),'manifest_sha256':plan['source_manifest_sha256'],
    'runner_sha256':sha(retry)},ensure_ascii=False))
