"""Preserve failed r1 and prepare a suspect-computation-disabled retry."""
from pathlib import Path
import hashlib,json,shutil
BASE=Path(__file__).resolve().parents[1]
ROOT=BASE.parent/'secondary_write_repeat_fix_20261117'
BUILD=Path('E:/codex_secondary_write_repeat_fix_20261117_r1')
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def put(p,o):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
assert not ROOT.exists() and not BUILD.exists()
for d in ('01_rtl','shared','04_pin','main','model','runs','tools','tests','02_sim','baseline_reference'):
 for p in (BASE/d).rglob('*'):
  if not p.is_file() or '__pycache__' in p.parts or p.suffix=='.pyc':continue
  target=ROOT/p.relative_to(BASE);target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,target)
for d in ('reports','artifacts'):(ROOT/d).mkdir(exist_ok=True)
for p in (ROOT/'tools').rglob('*.py'):
 t=p.read_text(encoding='utf-8-sig').replace(BASE.name,ROOT.name).replace('codex_pcb_no_suspect_lite_secondary_20261116_r1',BUILD.name).replace('pcb_no_suspect_lite_diagnostic','pcb_no_suspect_lite_diagnostic')
 p.write_text(t,encoding='utf-8')
for p in (ROOT/'runs').rglob('*'):
 if p.suffix in ('.al','.prj'):p.write_text(p.read_text(encoding='utf-8-sig').replace(str(BASE),str(ROOT)).replace(BASE.as_posix(),ROOT.as_posix()),encoding='utf-8')
p=ROOT/'01_rtl/pcb_ccl_binary_core.v';t=p.read_text(encoding='utf-8')
t=t.replace('parameter integer MARGIN_MIN=32,','parameter integer SUSPECT_ENABLE=0, // Approximate-region computation retired.\n    parameter integer MARGIN_MIN=32,')
t=t.replace('.SUSPECT_ENABLE(1),.SUSPECT_MARGIN_MIN(MARGIN_MIN),','.SUSPECT_ENABLE(SUSPECT_ENABLE),.SUSPECT_MARGIN_MIN(MARGIN_MIN),')
t=t.replace('if(core_suspect_valid && core_class==1 && core_margin>=MARGIN_MIN &&','if(SUSPECT_ENABLE != 0 && core_suspect_valid && core_class==1 && core_margin>=MARGIN_MIN &&')
assert t.count('parameter integer SUSPECT_ENABLE=0,')==1
p.write_text(t,encoding='utf-8',newline='\n')
changes=['01_rtl/vision_pipeline.v','01_rtl/pcb_ccl_binary_core.v']
put(ROOT/'tools/secondary_scope.json',dict(allowed_production_changes=changes,expected_changed_sources=changes,new_production_sources=[],notes=['Remove public suspect metadata and compile out serial suspect postpass/mapping with constant parameter0; classifier arithmetic and model remain.']))
put(ROOT/'BASELINE.json',dict(baseline=str(BASE.parent/'secondary_pcb_airwalk_stroke_cont_20261113'),failed_predecessor=str(BASE),build=str(BUILD),changed_production=changes,hardware_status='NOT_RUN'))
put(ROOT/'reports/r4_integration/BASELINE_IDENTITY.json',json.loads((BASE/'reports/r4_integration/BASELINE_IDENTITY.json').read_text()))
# The core arithmetic suite remains byte identical. Integrated pipelines execute
# the production default0 and additionally forbid any suspect-only states.
for rel in ('tests/suspect_r3/pipeline/tb_pipeline.sv','tests/suspect/pipeline_r3_sharehold_verified/tb_pipeline.sv'):
 p=ROOT/rel;t=p.read_text(encoding='utf-8')
 t=t.replace('if(checks)begin','if(`CORE.suspect_active||`CORE.state==15||`CORE.state==16||`CORE.state==17)fail("retired suspect postpass executed");\n        if(checks)begin',1)
 t=t.replace('`CORE.busy&&`CORE.state==15','`CORE.busy&&`CORE.state==13').replace('no postpass cancel trigger','no classifier-finalization cancel trigger')
 p.write_text(t,encoding='utf-8')
# Preserve optional generic adapter mapping tests with explicit parameter1.
# Production-disabled behavior is exercised by two whole-pipeline golden suites.
p=ROOT/'tests/suspect_r6/tb_suspect_adapter_current.sv';t=p.read_text(encoding='utf-8').replace('pcb_ccl_binary_core #(.WEIGHTS_MEM','pcb_ccl_binary_core #(.SUSPECT_ENABLE(1),.WEIGHTS_MEM');p.write_text(t,encoding='utf-8')
for name in ('run_current.py','run_core.py','run_publication.py'):
 p=ROOT/'tests/suspect_r6'/name;t=p.read_text(encoding='utf-8').replace(BASE.name,ROOT.name);p.write_text(t,encoding='utf-8')
# No old signoff or test PASS receipt is reused for the new freeze.
print(json.dumps(dict(status='SOURCE_READY',source=str(ROOT),build=str(BUILD),changes=changes)))
