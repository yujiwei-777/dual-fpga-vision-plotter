"""Rebase source-project UI metadata and bind unchanged controls."""
from pathlib import Path
import hashlib,json,re,subprocess,sys,xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'main_pcb_operator_ui_cn_font_shift1_dynamic_osd_20261113'
BUILD=Path('E:/codex_pcb_suspect_center_main_20261113_r3')
RUN_REL=Path('01_rtl/imgq_gain_m/main/td_project_display_noise_v8')
NAME='camera_to_dsi_display_720p60_cnn_multibox'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()

run=ROOT/RUN_REL
for path in (run/(NAME+'.al'),run/(NAME+'.prj')):
    raw=path.read_text(encoding='utf-8-sig')
    raw=re.sub(r'&(?!#?\w+;)', '&amp;',raw)
    raw=re.sub(r'(<\/?[A-Za-z_][\w:]*)::',lambda m:m[1]+'_TD_DOUBLE_COLON_',raw)
    tree=ET.fromstring(raw);tree.set('Path',run.as_posix());ET.indent(tree)
    path.write_text('<?xml version="1.0" encoding="UTF-8"?>\n'+ET.tostring(tree,encoding='unicode').replace('_TD_DOUBLE_COLON_','::')+'\n',encoding='utf-8')
cp=subprocess.run([sys.executable,str(ROOT/'tools/td_release_audit.py'),'snapshot','--root',str(ROOT),
    '--run',str(run),'--name',NAME,'--al',str(run/(NAME+'.al')),'--config',str(ROOT/'tools/release_audit_config.json'),
    '--output',str(run/'source_snapshot.json')],capture_output=True,text=True)
assert cp.returncode==0,cp.stdout+cp.stderr
baseline={str(p):sha(p) for folder in ('01_rtl','04_pin','artifacts') for p in sorted((BASE/folder).rglob('*')) if p.is_file()}
secondary=ROOT.parent/'secondary_pcb_airwalk_stroke_cont_20261113'
baseline.update({str(p):sha(p) for p in sorted((secondary/'artifacts').glob('*.bit'))})
out={'baseline_files':baseline,'build_manifest_sha256':sha(BUILD/'SOURCE_MANIFEST.json'),
     'source_project_snapshot_sha256':sha(run/'source_snapshot.json'),'hardware_status':'NOT_RUN'}
path=ROOT/'reports/CONTROL_INPUT_INTEGRITY_R3.json'
if path.exists():raise SystemExit('Refusing overwrite')
path.write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'baseline_files':len(baseline),'report':str(path)},ensure_ascii=False))
