"""Adapt focused regressions and freeze exact independent main inputs."""
from pathlib import Path
import hashlib,json,re,shutil,subprocess,sys,xml.etree.ElementTree as ET
ROOT=Path(__file__).resolve().parents[1]
BUILD=Path('E:/codex_pcb_no_suspect_main_20261116_r1')
RUN=Path('01_rtl/imgq_gain_m/main/td_project_display_noise_v8')
NAME='camera_to_dsi_display_720p60_cnn_multibox'
HDL=Path('01_rtl/imgq_gain_m/main/user_source/hdl_source')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def put(p,o):p.write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert not BUILD.exists()
p=ROOT/'tools/run_regression.py';t=p.read_text(encoding='utf-8')
t=t.replace("assert changes==[(HDL_REL/'osd_compact_panel.v').as_posix()],changes", "assert changes==[(HDL_REL/n).as_posix() for n in ('hdmi_mixer.v','operator_ui_text.v','osd_compact_panel.v')],changes")
t=t.replace('operator_data[10:8]==2&&operator_data[4]&&\n          x>=808&&x<840', 'operator_data[10:8]==2&&\n          x>=808&&x<1256')
t=t.replace('operator prefix still visible','PCB suspected-coordinate row still visible')
t=t.replace("'scope':'Actual panel/font pixel and glyph miter; all eight PCB statuses; operator coordinates except deleted prefix; dynamic visibility; Type21 CRC/session control. Region/mixer/protocol/DDR files byte unchanged. No whole-board functional simulation.'", "'scope':'Actual panel/font pixel and glyph comparison: eight PCB statuses without SUSPECT; entire PCB coordinate row blank; ordinary CNN numeric rows preserved; dynamic visibility and Type21 controls. Region suppression tested separately.'")
p.write_text(t,encoding='utf-8')
p=ROOT/'tests/suspect_center_dotted/tb_suspect_center.sv';t=p.read_text(encoding='utf-8')
t=t.replace('expecthit=edgehit||crosshit;', 'expecthit=0; // Suspect border and cross are both retired.')
t=t.replace('if(!crosshit||edgehit)$fatal(1,"unintended pixel changed");','if(!edgehit)$fatal(1,"unrelated overlay pixel changed");')
t=t.replace("px=scx;py=scy;colour(24'hffff00);", "px=scx;py=scy;colour(24'h123456);")
t=t.replace('if(changed!=83)$fatal(1,"expected independent dotted-cross total=83 new pixels got %0d",changed);','if(changed==0)$fatal(1,"no removed border pixels checked");')
p.write_text(t,encoding='utf-8')
# Explicitly check the preserved whole-board overlay in the same pixel path.
t=p.read_text(encoding='utf-8').replace("    px=scx;py=scy;colour(24'h123456);", """    px=scx;py=scy;colour(24'h123456);
    force mix.S_ovl_hit=1'b1;force mix.S_ovl_color=24'h00ff00;
    colour(24'h00ff00);release mix.S_ovl_hit;release mix.S_ovl_color;
    colour(24'h123456);""")
p.write_text(t,encoding='utf-8')
p=ROOT/'tools/release.py';t=p.read_text(encoding='utf-8')
t=t.replace('pcb_no_suspect_text_diagnostic','pcb_no_suspect_diagnostic')
p.write_text(t,encoding='utf-8')
def rebase(root):
 run=root/RUN
 for ext in ('.al','.prj'):
  p=run/(NAME+ext);t=p.read_text(encoding='utf-8-sig')
  t=re.sub(r'&(?!#?\w+;)','&amp;',t);t=re.sub(r'(<\/?[A-Za-z_][\w:]*)::',lambda m:m[1]+'_TD_DOUBLE_COLON_',t)
  tree=ET.fromstring(t);tree.set('Path',run.as_posix());ET.indent(tree)
  p.write_text('<?xml version="1.0" encoding="UTF-8"?>\n'+ET.tostring(tree,encoding='unicode').replace('_TD_DOUBLE_COLON_','::')+'\n',encoding='utf-8')
 cp=subprocess.run([sys.executable,'-B',str(root/'tools/td_release_audit.py'),'snapshot','--root',str(root),'--run',str(run),'--name',NAME,'--al',str(run/(NAME+'.al')),'--config',str(root/'tools/release_audit_config.json'),'--output',str(run/'source_snapshot.json')],capture_output=True,text=True)
 assert cp.returncode==0,cp.stdout+cp.stderr
 assert json.loads((run/'source_snapshot.json').read_text(encoding='utf-8-sig'))['passed']
rebase(ROOT);BUILD.mkdir()
for d in ('01_rtl','04_pin','tools','tests'):
 shutil.copytree(ROOT/d,BUILD/d,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
(BUILD/'audits').mkdir();shutil.copy2(ROOT/'tools/summarize_readonly.py',BUILD/'audits/summarize_readonly.py')
rebase(BUILD)
records={p.relative_to(BUILD).as_posix():dict(sha256=sha(p),bytes=p.stat().st_size) for d in ('01_rtl','04_pin','tools','tests') for p in sorted((BUILD/d).rglob('*')) if p.is_file()}
put(BUILD/'SOURCE_MANIFEST.json',dict(schema='main-no-suspect-source-v1',files=records))
plan=dict(status='PREPARED',source_root=str(ROOT),build_root=str(BUILD),source_manifest_sha256=sha(BUILD/'SOURCE_MANIFEST.json'),phase_runner_sha256=sha(ROOT/'tools/run_build_phases.py'),limits_strict_less_than=dict(slice=95,eram=90,dsp=95),hardware_status='NOT_RUN',bitgen_allowed=False)
put(BUILD/'BUILD_PLAN.json',plan);put(ROOT/'reports/BUILD_PLAN.json',plan)
protected=json.loads((ROOT/'baseline_reference/PROTECTED_INPUTS.json').read_text(encoding='utf-8'))
assert all(sha(p)==v for p,v in protected.items())
print(json.dumps(dict(status='PREPARED',build=str(BUILD),files=len(records))))
