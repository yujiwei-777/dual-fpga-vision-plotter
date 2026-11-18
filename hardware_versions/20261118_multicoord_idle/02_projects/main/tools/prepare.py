"""Prepare a source-only, independent no-SUSPECT-text main build."""
from pathlib import Path
import hashlib, json, re, shutil, subprocess, sys, xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'main_pcb_suspect_center_20261113'
OLD=Path('E:/codex_pcb_suspect_center_main_20261113_r4')
BUILD=Path('E:/codex_pcb_no_suspect_main_20261116_r1')
RUN_REL=Path('01_rtl/imgq_gain_m/main/td_project_display_noise_v8')
HDL_REL=Path('01_rtl/imgq_gain_m/main/user_source/hdl_source')
NAME='camera_to_dsi_display_720p60_cnn_multibox'

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def put(p,o):p.write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def plain(p):
    for q in [p,*p.rglob('*')]:
        s=q.lstat()
        if q.is_symlink() or getattr(s,'st_file_attributes',0)&0x400 or (q.is_file() and s.st_nlink>1):
            raise RuntimeError('Linked input: '+str(q))

if (ROOT/'01_rtl').exists() or BUILD.exists():raise SystemExit('Refusing existing source/build')
protected={str(p):sha(p) for d in ('01_rtl','04_pin','artifacts')
           for p in sorted((BASE/d).rglob('*')) if p.is_file()}
assert sha(BASE/'artifacts/dual_fpga_main_20261113_pcb_suspect_center_diagnostic.bit')=='E2E1FE983B3D63056B4044710EF979A42FF8EBEDC81D6440C2301175FBE08011'
for d in ('01_rtl','04_pin','tests'):
    plain(BASE/d)
    shutil.copytree(BASE/d,ROOT/d,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
for d in ('reports','artifacts','baseline_reference'):(ROOT/d).mkdir(exist_ok=True)
put(ROOT/'baseline_reference/PROTECTED_INPUTS.json',protected)

p=ROOT/HDL_REL/'osd_compact_panel.v'
t=p.read_text(encoding='utf-8')
a="2:static_key=(pcb_suspect===1'b1)?6'd46+{3'd0,pcb_status}:6'd38+{3'd0,pcb_status};"
b="2:static_key=6'd38+{3'd0,pcb_status}; // Status only; region graphics stay independent."
assert t.count(a)==1;t=t.replace(a,b)
a="                if((pcb_suspect===1'b1)&&cell_idx>=5&&cell_idx<=11)color_c=4'd10;\n"
assert t.count(a)==1;t=t.replace(a,'')
# Operator key 26 uses block 90: remove only its two-character prefix.
for i in (1440,1441):
    pattern=rf"characters\[{i}\]=9'h[0-9a-fA-F]+;"
    assert len(re.findall(pattern,t))==1
    t=re.sub(pattern,f"characters[{i}]=9'h020;",t)
p.write_text(t,encoding='utf-8',newline='\n')
changes=[]
for f in sorted((ROOT/'01_rtl').rglob('*')):
    if f.is_file():
        rel=f.relative_to(ROOT)
        if sha(f)!=sha(BASE/rel):changes.append(str(rel))
assert changes==[str(HDL_REL/'osd_compact_panel.v')],changes
put(ROOT/'BASELINE.json',{'baseline':str(BASE),'baseline_bit_sha256':sha(BASE/'artifacts/dual_fpga_main_20261113_pcb_suspect_center_diagnostic.bit'),
    'changes':changes,'scope':'Remove status SUSPECT text and operator suspect prefix only; retain source coordinates/region/cross and dynamic visibility.','hardware_status':'NOT_RUN'})

for f in ('td_release_audit.py','release_audit_config.json'):
    shutil.copy2(BASE/'tools'/f,ROOT/'tools'/f)
shutil.copytree(OLD/'tools/physical_capacity',ROOT/'tools/physical_capacity')
shutil.copy2(OLD/'audits/summarize_readonly.py',ROOT/'tools/summarize_readonly.py')
phase=(BASE/'tools/run_build_phases_r4.py').read_text(encoding='utf-8').replace(str(OLD).replace('\\','/'),BUILD.as_posix())
(ROOT/'tools/run_build_phases.py').write_text(phase,encoding='utf-8')
audit=(BASE/'tools/audit_current_route_r4.py').read_text(encoding='utf-8')
audit=audit.replace(OLD.as_posix(),BUILD.as_posix()).replace("SOURCE.name == 'main_pcb_suspect_center_20261113'","SOURCE.name == 'main_pcb_no_suspect_20261116'")
audit=re.sub(r"MANIFEST_SHA256 = '[0-9A-F]{64}'", "MANIFEST_SHA256 = json.loads((BUILD/'BUILD_PLAN.json').read_text(encoding='utf-8'))['source_manifest_sha256']",audit)
audit=re.sub(r"PHASE_RUNNER_SHA256 = '[0-9A-F]{64}'", "PHASE_RUNNER_SHA256 = json.loads((BUILD/'BUILD_PLAN.json').read_text(encoding='utf-8'))['phase_runner_sha256']",audit)
audit=audit.replace('tools/run_build_phases_r4.py','tools/run_build_phases.py')
(ROOT/'tools/audit_current_route.py').write_text(audit,encoding='utf-8')

# Project roots are rewritten in both source checkout and independent freeze.
def rebase(root):
    run=root/RUN_REL
    for f in (NAME+'.al',NAME+'.prj'):
        p=run/f;raw=p.read_text(encoding='utf-8-sig')
        raw=re.sub(r'&(?!#?\w+;)', '&amp;',raw)
        raw=re.sub(r'(<\/?[A-Za-z_][\w:]*)::',lambda m:m[1]+'_TD_DOUBLE_COLON_',raw)
        tree=ET.fromstring(raw);tree.set('Path',run.as_posix());ET.indent(tree)
        p.write_text('<?xml version="1.0" encoding="UTF-8"?>\n'+ET.tostring(tree,encoding='unicode').replace('_TD_DOUBLE_COLON_','::')+'\n',encoding='utf-8')
    cp=subprocess.run([sys.executable,'-B',str(root/'tools/td_release_audit.py'),'snapshot','--root',str(root),
        '--run',str(run),'--name',NAME,'--al',str(run/(NAME+'.al')),'--config',str(root/'tools/release_audit_config.json'),
        '--output',str(run/'source_snapshot.json')],capture_output=True,text=True)
    assert cp.returncode==0,cp.stdout+cp.stderr
    assert json.loads((run/'source_snapshot.json').read_text(encoding='utf-8-sig'))['passed']

rebase(ROOT)
BUILD.mkdir()
for d in ('01_rtl','04_pin','tools','tests'):
    shutil.copytree(ROOT/d,BUILD/d,ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
(BUILD/'audits').mkdir()
shutil.copy2(ROOT/'tools/summarize_readonly.py',BUILD/'audits/summarize_readonly.py')
rebase(BUILD)
records={p.relative_to(BUILD).as_posix():{'sha256':sha(p),'bytes':p.stat().st_size}
         for d in ('01_rtl','04_pin','tools','tests') for p in sorted((BUILD/d).rglob('*')) if p.is_file()}
put(BUILD/'SOURCE_MANIFEST.json',{'schema':'main-no-suspect-text-source-v1','files':records})
plan={'status':'PREPARED','source_root':str(ROOT),'build_root':str(BUILD),
      'source_manifest_sha256':sha(BUILD/'SOURCE_MANIFEST.json'),'phase_runner_sha256':sha(ROOT/'tools/run_build_phases.py'),
      'limits_strict_less_than':{'slice':95,'eram':90,'dsp':95},'hardware_status':'NOT_RUN','bitgen_allowed':False}
put(BUILD/'BUILD_PLAN.json',plan);put(ROOT/'reports/BUILD_PLAN.json',plan)
assert all(sha(Path(p))==v for p,v in protected.items())
print(json.dumps({'status':'PREPARED','build':str(BUILD),'source_files':len(records),'changes':changes},ensure_ascii=False))
