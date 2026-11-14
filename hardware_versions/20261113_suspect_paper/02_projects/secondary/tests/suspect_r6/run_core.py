"""Current production classifier versus immutable r5 and 22 integer fixtures."""
from pathlib import Path
from datetime import datetime, timezone
import argparse, hashlib, json, os, re, shutil, subprocess, sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--run',type=Path,default=Path('E:/codex_pcb_runtime_fix_secondary_20261111_r1'))
RUN=parser.parse_args().run.resolve()
MANIFEST=RUN/'SOURCE_MANIFEST.json'
EXPECTED=json.loads((RUN/'BUILD_PLAN.json').read_text(encoding='utf-8-sig'))['source_manifest_sha256']
CONTROL=Path('E:/codex_pcb_suspect_secondary_20261107_r5/01_rtl/pcb_fullboard_spatial96.v')
OUT=ROOT/'reports/suspect_trial'/('r6_core_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
OUT.mkdir(parents=True,exist_ok=False)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
assert sha(MANIFEST)==EXPECTED
source=ROOT/'01_rtl/pcb_fullboard_spatial96.v'
assert sha(source)==sha(RUN/'01_rtl/pcb_fullboard_spatial96.v')=='284B6BF9BB426AD2F04B2BCD0BA2679CFD2DD476C480439306A018D06EF429AB'
assert sha(CONTROL)=='9569901BBFFE9A0CE5147565FB44D3D57747868F829CA2545E754DEB734D182E'
prior=ROOT/'tests/suspect_r3'
inputs=[source,CONTROL,MANIFEST,Path(__file__),prior/'tb_suspect_core.sv',prior/'FIXTURES.json',prior/'cases.svh',prior/'calls.svh']
for p in sorted(prior.glob('*.mem')):
    inputs.append(p)
    shutil.copy2(p,OUT/p.name)
for name in ('cases.svh','calls.svh','FIXTURES.json'):
    shutil.copy2(prior/name,OUT/name)
original=CONTROL.read_text(encoding='utf-8-sig')
assert original.count('module pcb_fullboard_spatial96 #(')==1
baseline=OUT/'pcb_fullboard_spatial96_r5.v'
baseline.write_text(original.replace('module pcb_fullboard_spatial96 #(','module pcb_fullboard_spatial96_r5 #(',1),encoding='utf-8')
bench=(prior/'tb_suspect_core.sv').read_text(encoding='utf-8-sig')
pos=bench.index('pcb_fullboard_spatial96 #(',bench.index('pcb_fullboard_spatial96 #(')+1)
bench=bench[:pos]+bench[pos:].replace('pcb_fullboard_spatial96 #(','pcb_fullboard_spatial96_r5 #(',1)
marker='if(full&&(!(baseline_seen||bdone)'
assert marker in bench
bench=bench.replace(marker,'if(full&&(dut.logits[0]!==logits[0][19:0]||dut.logits[1]!==logits[1][19:0]))fail("integer golden logits mismatch");\n '+marker)
tb=OUT/'tb_suspect_core.sv';tb.write_text(bench,encoding='ascii')
sources=[source,baseline,ROOT/'01_rtl/vision_shared_mac.v',ROOT/'01_rtl/vision_workspace_goodonly.v',tb]
inputs += sources
inputs += [ROOT/p for p in ('model/experiments/conv4_4/weights.mem','model/experiments/conv4_4/biases.mem','model/suspect/mad_negative_constants.mem','model/suspect/CONTRACT.json')]
pins={str(p.resolve()):sha(p) for p in inputs}
env=dict(os.environ,LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT',MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT')
commands=[];error=None
try:
    for label,argv,passmarker in [
        ('vlib',['E:/model/win64/vlib.exe','rtl_lib'],None),
        ('compile',['E:/model/win64/vlog.exe','-sv','-lint','-work','rtl_lib','+incdir+'+OUT.as_posix(),*map(str,sources)],None),
        ('simulation',['E:/model/win64/vsim.exe','-batch','-syncio','-quiet','-voptargs=+acc','-lib','rtl_lib','tb_suspect_core','-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'],'SUSPECT_CORE_GOLDEN_PASS tests=22')]:
        log=OUT/(label+'.log')
        with log.open('x',encoding='utf-8') as stream:
            cp=subprocess.run(argv,cwd=OUT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=900)
        text=log.read_text(encoding='utf-8-sig',errors='replace')
        passed=cp.returncode==0 and not re.search(r'\*\*\s+(?:Error|Fatal):',text) and (not passmarker or passmarker in text)
        commands.append(dict(label=label,argv=argv,returncode=cp.returncode,passed=passed,log=str(log),log_sha256=sha(log)))
        assert passed,text[-2500:]
        print(label+' PASS',flush=True)
    assert len(re.findall('SUSPECT_CORE_PASS ',text))==22
except Exception as exc:error=repr(exc)
drift=[p for p,h in pins.items() if sha(p)!=h]
result=dict(status='PASS' if not error and not drift else 'FAIL',source_manifest_sha256=EXPECTED,
            source_hashes=pins,commands=commands,source_drift=drift,error=error,
            logs=[dict(path=str(OUT/'simulation.log'),sha256=sha(OUT/'simulation.log'),pass_marker='SUSPECT_CORE_GOLDEN_PASS tests=22')] if not error else [],
            scope='22 retained fixtures including three complete real ROIs; current production source directly compiled; r5 immutable control; all features/logits/status/score/margin/SUSPECT and 7121-cycle postpass checked.',
            hardware='NOT_RUN',localization_accuracy='EXPLORATORY_NOT_PASSED')
(OUT/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(dict(status=result['status'],report=str(OUT/'RESULT.json'),sha256=sha(OUT/'RESULT.json'))),flush=True)
raise SystemExit(0 if result['status']=='PASS' else 1)
