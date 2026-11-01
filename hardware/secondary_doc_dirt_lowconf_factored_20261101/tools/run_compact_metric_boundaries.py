"""Fresh metric boundary miter for the actual combined production planner."""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ORIGIN = ROOT.parent / 'secondary_doc_metric_bound_scratch_20261031/functional_metric/02_sim/directed_metrics'
REFERENCE = ROOT.parent / 'secondary_cnn_key3_stroke_release_20261031/01_rtl/doc_stroke_planner.v'
OUT = ROOT / '02_sim/compact_metric_boundaries'
SIM = Path('E:/model/win64')
PLANNER = ROOT / '01_rtl/doc_stroke_planner.v'
PLANNER_SHA = '1C6AB2F04D6B8CDC0EDAAA6D275A3BCDA314985B5F219BD3EA0A5846518F4CB6'
REFERENCE_SHA = 'DB552C7E3619108DACF894232696B95A573AE194C44E2B6439A744705597E204'
BENCHES = {'finite_bound': '165178A87D3F9FA162157207A7E70FB1D17D22E3538A1BC652C01938F8993473',
           'generic32': '1CC83F7270F084310165D832415CD27FD5686DEC5C5D0A48616BA35F54DB4370'}


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def put(path, value):
    with path.open('x', encoding='utf-8', newline='\n') as stream:
        stream.write(value)


def main():
    assert sha(REFERENCE) == REFERENCE_SHA and sha(PLANNER) == PLANNER_SHA
    assert (SIM / 'LICENSE.TXT').is_file() and not OUT.exists()
    OUT.mkdir()
    baseline = REFERENCE.read_text()
    assert baseline.count('module doc_stroke_planner #(') == 1
    put(OUT / 'doc_stroke_planner_baseline.v', baseline.replace(
        'module doc_stroke_planner #(', 'module doc_stroke_planner_baseline #('))
    rtl = [PLANNER, OUT / 'doc_stroke_planner_baseline.v',
           ROOT / '01_rtl/doc_stroke_bram.v', ROOT / '01_rtl/doc_path_distance.v']
    inputs = {str(path): sha(path) for path in [*rtl, ROOT/'01_rtl/doc_copy_pipeline.v', Path(__file__)]}
    origins = {str(REFERENCE): REFERENCE_SHA}
    results = {}
    environment = os.environ.copy()
    environment.update(MGLS_LICENSE_FILE=str(SIM/'LICENSE.TXT'), LM_LICENSE_FILE=str(SIM/'LICENSE.TXT'))
    for name, digest in BENCHES.items():
        origin = ORIGIN / name / 'tb_metric_directed.sv'
        assert sha(origin) == digest
        origins[str(origin)] = digest
        case = OUT / name
        case.mkdir()
        tb = case / 'tb_metric_directed.sv'
        with tb.open('xb') as stream:
            stream.write(origin.read_bytes())
        inputs[str(tb)] = sha(tb)
        for phase, command in [
            ('vlib', [SIM/'vlib.exe', 'simlib']),
            ('compile', [SIM/'vlog.exe', '-sv', '-lint', '+define+DOC_BEHAVIORAL_RAM', '-work', 'simlib', *rtl, tb]),
            ('simulate', [SIM/'vsim.exe', '-batch', '-quiet', '-lib', 'simlib', 'tb_metric_directed',
                '-do', 'onerror {quit -code 1}; run -all; quit -f'])]:
            with (case/(phase+'.log')).open('x', encoding='utf-8') as stream:
                result = subprocess.run([str(arg) for arg in command], cwd=case, env=environment,
                    stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT,
                    timeout=300, creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            text = (case/(phase+'.log')).read_text(errors='replace')
            put(case/(phase+'_command.json'), json.dumps({'returncode': result.returncode,
                'command': [str(arg) for arg in command], 'log_sha256': sha(case/(phase+'.log'))}, indent=2)+'\n')
            assert result.returncode == 0 and not re.search(r'\*\*\s+(?:Error|Fatal):', text), text[-5000:]
            if phase == 'compile':
                assert 'Errors: 0, Warnings: 0' in text
        markers = [line.lstrip('# ').strip() for line in text.splitlines() if 'PASS ' in line]
        expected = 'PASS METRIC_FINITE_BOUND checks=13 rejects=3' if name == 'finite_bound' else 'PASS METRIC_GENERIC32 checks=80 rejects=0'
        assert any(line.startswith(expected) for line in markers)
        results[name] = {'status': 'PASS', 'checks': markers}
        print(name, markers, flush=True)
    assert all(sha(path) == digest for path, digest in {**inputs, **origins}.items())
    evidence = {path.relative_to(OUT).as_posix(): sha(path) for path in OUT.rglob('*')
                if path.is_file() and not any(part == 'simlib' for part in path.relative_to(OUT).parts)}
    put(OUT/'RESULTS.json', json.dumps({'status': 'PASS_FRESH_COMBINED_METRIC_BOUNDARIES',
        'input_hashes': inputs, 'origin_hashes': origins, 'evidence_hashes': evidence,
        'tests': results, 'hardware_status': 'NOT_RUN', 'planner_sha256': PLANNER_SHA,
        'limits': 'Directed state injection complements live golden path/G-code regression; it is not physical timing acceptance.'}, indent=2)+'\n')


if __name__ == '__main__':
    main()
