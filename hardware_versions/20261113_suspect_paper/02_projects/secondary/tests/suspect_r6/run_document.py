"""Retained document fixtures with symbolic, observational planner probes."""
from pathlib import Path
from datetime import datetime, timezone
import argparse, importlib.util, json, shutil, sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--run',type=Path,default=Path('E:/codex_pcb_runtime_fix_secondary_20261111_r1'))
RUN=parser.parse_args().run.resolve()
HELPER=ROOT/'tools/run_retrained_preserved_regressions.py'
s=importlib.util.spec_from_file_location('retained_document_r6',HELPER)
m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
OUT=ROOT/'reports/suspect_trial'/('r6_document_symbolic_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
r=m.Run(ROOT,OUT);r.pin(HELPER,Path(__file__),RUN/'SOURCE_MANIFEST.json')
assert m.sha(RUN/'SOURCE_MANIFEST.json')==json.loads((RUN/'BUILD_PLAN.json').read_text(encoding='utf-8-sig'))['source_manifest_sha256']
error=None
try:
    source=m.DOC/'reports/dirt_qualification'
    shutil.copytree(source/'fixtures',OUT/'fixtures')
    for p in (source/'fixtures').rglob('*'):
        if p.is_file():r.pin(p)
    front=r.copy(source/'source/tb_frontend.sv')
    integrated=r.copy(source/'source/tb_capture_integrated.sv')
    text=integrated.read_text(encoding='utf-8-sig')
    remap={'dut.state==25':'dut.state==dut.GR0','dut.state==58':'dut.state==dut.APPEND','dut.state==56':'dut.state==dut.PATH_END'}
    for before,after in remap.items():
        assert text.count(before)==1,(before,text.count(before))
        text=text.replace(before,after)
    integrated.write_text(text,encoding='utf-8')
    r.pin(integrated)
    eram=r.copy(m.OLD/'reports/pose7/hxa_tests/ph1p_logic_eram_stub.sv')
    names=['doc_image_frontend.v','doc_stroke_planner.v','doc_stroke_bram.v','doc_machine_map.v','doc_grbl_plotter.v','doc_grbl_map.v','doc_grbl_streamer.v','doc_grbl_response_parser.v','grbl_line_formatter.v']
    files=[ROOT/'01_rtl'/n for n in names]
    for p in files:
        assert m.sha(p)==m.sha(RUN/p.relative_to(ROOT)),p
    r.pin(*files)
    lib=OUT/'front_lib'
    r.cmd('frontend_vlib',[m.SIM/'vlib.exe',lib])
    r.cmd('frontend_lint',[m.SIM/'vlog.exe','-sv','-lint','-work',lib,files[0],front])
    for fixture in sorted((OUT/'fixtures').iterdir()):
        text=r.cmd('frontend_'+fixture.name,[m.SIM/'vsim.exe','-batch','-syncio','-quiet','-lib',lib.name,'tb_frontend',
            '+IMAGE='+(fixture/'source_y.mem').as_posix(),'+EXPECTED='+(fixture/'expected_binary.mem').as_posix(),
            '+OUTPUT='+(OUT/(fixture.name+'_binary.mem')).as_posix(),'+CASE='+fixture.name,
            '-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'],'PASS FRONTEND')
        r.scope.append(dict(test='frontend '+fixture.name))
    for case in ('blank2418','ink2358'):
        fixture=OUT/'fixtures'/case;lib=OUT/(case+'_lib')
        r.cmd(case+'_vlib',[m.SIM/'vlib.exe',lib])
        r.cmd(case+'_lint',[m.SIM/'vlog.exe','-sv','-lint','-work',lib,'+incdir+'+fixture.as_posix(),*files,eram,integrated])
        r.cmd(case+'_simulation',[m.SIM/'vsim.exe','-batch','-syncio','-quiet','-lib',lib.name,'tb_stroke_split',
            '-do','onerror {quit -code 1}; onbreak {quit -code 2}; cd {'+fixture.as_posix()+'}; run -all; quit -f'],'PASS CAPTURE_INTEGRATED')
        actual=(fixture/'gcode.txt').read_text().splitlines()
        expected=(fixture/'expected_gcode.txt').read_text().splitlines()
        assert actual==expected,(case,'G-code changed',len(actual),len(expected))
        r.pin(fixture/'gcode.txt',fixture/'raw_paths.txt')
        r.scope.append(dict(test=case+' frontend/skeleton/paths/coordinates/G-code',gcode_lines=len(actual)))
    r.scope.append(dict(observational_probe_remap=remap,stimulus_changed=False,
        explanation='Original bench compared raw numeric state 25; Gray recoding assigns that number to another state. Symbolic constants restore the same observation event, without changing any DUT or stimulus.'))
    r.limits+=['Archived real source-Y fixtures; no new independent handwriting-quality or hardware claim.',
               'Document-local transport checked here; shared transport tested separately.']
except Exception as exc:error=repr(exc)
result=r.finish(error)
print(json.dumps(dict(status=result['status'],report=str(OUT/'RESULTS.json'),sha256=m.sha(OUT/'RESULTS.json'))),flush=True)
if error:print(error,flush=True)
raise SystemExit(0 if result['status']=='PASS' else 1)
