"""Execute selected production suites against one exact new build snapshot."""
from pathlib import Path
from datetime import datetime, timezone
import argparse, importlib.util, json, shutil, sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--run', type=Path, required=True)
p.add_argument('--output', type=Path)
p.add_argument('suites', nargs='+')
a = p.parse_args()
HELPER = ROOT/'tools/run_retrained_preserved_regressions.py'
spec = importlib.util.spec_from_file_location('retained_current', HELPER)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
manifest = a.run.resolve()/'SOURCE_MANIFEST.json'
frozen = json.loads(manifest.read_text(encoding='utf-8-sig'))['files']
OUT = (a.output or ROOT/'reports/suspect_trial'/('r6_functional_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))).resolve()
assert OUT.is_relative_to(ROOT/'reports'), 'Test output must stay inside candidate reports'
OUT.mkdir(parents=True, exist_ok=False)
for origin in (ROOT/'model/suspect').glob('*'):
    if origin.is_file():
        target = OUT/'model/suspect'/origin.name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(origin, target)
results = []
for label in a.suites:
    r = m.Run(ROOT, OUT/label)
    r.pin(HELPER, Path(__file__), manifest, *list((OUT/'model/suspect').glob('*')))
    error = None
    try:
        if label in m.SUITES:
            m.SUITES[label](r)
        elif label in ('pipeline', 'adapter', 'sharehold'):
            if label == 'sharehold':
                retained = ROOT/'tests/suspect/pipeline_r3_sharehold_verified'
                fixture = ROOT/'tests/suspect/pipeline/fixtures'
            else:
                retained = ROOT/'tests/suspect_r3'/label
                fixture = ROOT/'tests/suspect/pipeline/fixtures'
            if label == 'adapter':
                bench = r.copy(ROOT/'tests/suspect_r6/tb_suspect_adapter_current.sv')
                text=bench.read_text()
                for token,relative in [('@WEIGHTS@','model/experiments/conv4_4/weights.mem'),
                                       ('@BIASES@','model/experiments/conv4_4/biases.mem'),
                                       ('@SUSPECT@','model/suspect/mad_negative_constants.mem')]:
                    assert token in text
                    text=text.replace(token,(ROOT/relative).as_posix())
                bench.write_text(text)
                r.sim('adapter', [ROOT/'01_rtl'/n for n in ('pcb_ccl_binary_core.v','pcb_fullboard_spatial96.v')]+[bench],
                      'tb_suspect_adapter', 'SUSPECT_ADAPTER_CURRENT_PASS tests=30 good_pass_min=192 bad_min=32')
            else:
                bench = r.copy(retained/'tb_pipeline.sv')
                for name in ('binary_pipeline_calls.svh','binary_pipeline_config.svh'):
                    r.copy(retained/name)
                r.pin(retained/'FIXTURES.json', *list(fixture.rglob('*.mem')))
                names = ['vision_pipeline.v','edge_roi_ccl_shared_pcb_candidate.v','vision_ccl_pcb_candidate.v',
                         'pcb_ccl_binary_core.v','pcb_fullboard_spatial96.v','cnn_core.v','vision_workspace_goodonly.v',
                         'vision_shared_mac.v','cnn_result_stabilizer.v','vision_color_stats.v','vision_pixel_reader.v']
                sources = [ROOT/'01_rtl'/n for n in names]+[bench]
                r.pin(*sources)
                lib = r.out/(label+'_lib')
                r.cmd(label+'_vlib',[m.SIM/'vlib.exe',lib])
                r.cmd(label+'_lint',[m.SIM/'vlog.exe','-sv','-lint','-work',lib,*sources])
                text = r.cmd(label+'_simulation',[m.SIM/'vsim.exe','-batch','-syncio','-quiet','-voptargs=+acc',
                    '-lib',lib.name,'tb_binary_fullpipeline','+FIXTURES='+fixture.as_posix(),
                    '-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'],
                    'BINARY_FULLPIPELINE_GOLDEN_PASS frames=13 cancels=4')
                if label == 'sharehold':
                    assert 'PIPELINE_SHAREHOLD_PASS' in text
            r.pin(*list((ROOT/'model/export').glob('*.mem')),
                  *list((ROOT/'model/experiments/conv4_4').glob('*.mem')),
                  ROOT/'model/suspect/mad_negative_constants.mem', ROOT/'model/suspect/CONTRACT.json',
                  ROOT/'model/suspect/confidence_0_100.mem')
            r.scope.append({'suite':label,'coverage':'Current CCL/ROI/features/logits/class/score/margin/SUSPECT, cancel/drain/reentry; adapter controlled classification; sharehold actual snapshot lifetimes.'})
            r.limits += ['Existing frozen fixtures; no new localization accuracy or physical DDR/CDC claim.']
        else:
            raise ValueError('Unknown suite '+label)
        bound = {}
        for filename, digest in r.pins.items():
            source = Path(filename)
            if source.is_relative_to(ROOT):
                relative = source.relative_to(ROOT).as_posix()
                if relative in frozen:
                    assert frozen[relative]['sha256'] == digest, relative
                    assert m.sha(a.run/relative) == digest, relative
                    bound[relative] = digest
        r.scope.append({'source_manifest':str(manifest),'sha256':m.sha(manifest),'bound_current_production_sources':bound})
    except Exception as exc:
        error = repr(exc)
    result = r.finish(error)
    results.append(result)
    m.dump(OUT/'RESULTS.json', dict(status='PASS' if all(x['status']=='PASS' for x in results) else 'FAIL',
        source_manifest=str(manifest), source_manifest_sha256=m.sha(manifest), suite_results=results, hardware='NOT_RUN'))
    print(label+': '+result['status'], flush=True)
    if error:
        print(error, flush=True)
        break
print('CURRENT_SUITE_OUTPUT '+str(OUT), flush=True)
raise SystemExit(0 if all(x['status']=='PASS' for x in results) else 1)
