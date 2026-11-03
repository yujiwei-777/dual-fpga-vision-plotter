"""Prepare a frozen-source full vision_pipeline regression; --run is root-owned.

The pixel reader is an abstract source-Y/RGB-from-gray fixture, with a 2..4
clock accepted-read latency. This test does not measure actual DDR latency.
"""
from __future__ import annotations
import argparse
from collections import deque
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
DEFAULT_VECTORS = Path('D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_pose7_goodonly_ccl_20261102/reports/pose7/vectors')
NAMES = ['golden_good', 'golden_missing_pad', 'golden_missing_corner']
MEMORIES = ['source_y.mem', 'roi.mem', 'sample_x.mem', 'sample_y.mem', 'conv1.mem',
            'conv2.mem', 'conv1_acc.mem', 'conv2_acc.mem', 'residual.mem']
RTL_NAMES = ['vision_pipeline.v', 'edge_roi_ccl_shared_pcb_candidate.v',
             'vision_ccl_pcb_candidate.v', 'pcb_pose7_core.v', 'cnn_core.v',
             'vision_workspace_goodonly.v', 'vision_shared_mac.v',
             'cnn_result_stabilizer.v', 'vision_color_stats.v', 'vision_pixel_reader.v']


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def save(path, obj):
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')


def values(path):
    return [int(x, 16) for x in path.read_text(encoding='ascii').split()]


def independent_ccl(source):
    """Flood fill, independent of the RTL union/statistic implementation."""
    mask = [int(source[(8*y+4)*1280+8*x+4] <= 112) for y in range(90) for x in range(160)]
    provisional = sum(mask[i] and (i % 160 == 0 or not mask[i-1]) and
                      (i < 160 or not mask[i-160]) for i in range(14400))
    seen = bytearray(14400)
    eligible = []
    for first in range(14400):
        if not mask[first] or seen[first]:
            continue
        seen[first] = 1
        queue = deque([first])
        area = 0
        x0 = x1 = first % 160
        y0 = y1 = first // 160
        while queue:
            i = queue.popleft()
            x, y = i % 160, i // 160
            area += 1
            x0, x1 = min(x0, x), max(x1, x)
            y0, y1 = min(y0, y), max(y1, y)
            neighbors = []
            if x: neighbors.append(i-1)
            if x < 159: neighbors.append(i+1)
            if y: neighbors.append(i-160)
            if y < 89: neighbors.append(i+160)
            for j in neighbors:
                if mask[j] and not seen[j]:
                    seen[j] = 1
                    queue.append(j)
        w, h = x1-x0+1, y1-y0+1
        if area >= 64 and w >= 8 and h >= 4 and w <= 5*h and h <= 5*w and area*12 >= w*h:
            eligible.append({'area': area, 'first': first, 'grid_box': [x0, y0, x1+1, y1+1]})
    eligible.sort(key=lambda c: (-c['area'], c['first']))
    overflow = provisional > 510
    top4 = eligible[:4] if not overflow else []
    return mask, {'provisional_labels': provisional, 'overflow': overflow,
                  'truncated': len(eligible) > 4, 'count': len(top4),
                  'eligible_components': eligible, 'top4': top4}


def prepare_fixtures(vectors, target):
    cases = []
    for name in NAMES:
        src, dst = vectors/name, target/name
        dst.mkdir(parents=True, exist_ok=True)
        frame = json.loads((src/'FRAME.json').read_text(encoding='utf-8'))
        expected = json.loads((src/'EXPECTED.json').read_text(encoding='utf-8'))
        for filename in MEMORIES + ['FRAME.json', 'EXPECTED.json']:
            if not (dst/filename).is_file() or sha(src/filename) != sha(dst/filename):
                shutil.copy2(src/filename, dst/filename)
        source = values(dst/'source_y.mem')
        assert len(source) == 921600 and all(0 <= x <= 255 for x in source)
        assert hashlib.sha256(bytes(source)).hexdigest().upper() == frame['source_Y_SHA256']
        mask, ccl = independent_ccl(source)
        assert ccl['provisional_labels'] == frame['provisional_labels']
        assert ccl['count'] == frame['count'] and ccl['overflow'] == frame['overflow']
        box = [8*x for x in ccl['top4'][0]['grid_box']]
        assert box == frame['bbox']
        x0, y0, x1, y1 = box
        xx = [x0+((2*u+1)*(x1-x0))//192 for u in range(96)]
        yy = [y0+((2*v+1)*(y1-y0))//192 for v in range(96)]
        assert xx == values(dst/'sample_x.mem') and yy == values(dst/'sample_y.mem')
        assert [source[y*1280+x] for y in yy for x in xx] == values(dst/'roi.mem')
        (dst/'mask.mem').write_text(''.join(f'{x:x}\n' for x in mask), encoding='ascii')
        boxes, areas = [], []
        for row in ccl['top4']:
            gx0, gy0, gx1, gy1 = row['grid_box']
            boxes.append((gy1 << 48) | (gx1 << 32) | (gy0 << 16) | gx0)
            areas.append(row['area'])
        boxes += [0]*(4-len(boxes)); areas += [0]*(4-len(areas))
        (dst/'boxes.mem').write_text(''.join(f'{x:016x}\n' for x in boxes), encoding='ascii')
        (dst/'areas.mem').write_text(''.join(f'{x:04x}\n' for x in areas), encoding='ascii')
        save(dst/'INDEPENDENT_CCL.json', ccl)
        cases.append({'name': name, 'frame': frame, 'expected': expected, 'ccl': ccl})
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--run', action='store_true')
    parser.add_argument('--vectors', type=Path, default=DEFAULT_VECTORS)
    parser.add_argument('--sim', type=Path, default=Path('E:/model/win64/vsim.exe'))
    parser.add_argument('--design', type=Path, default=ROOT, help='Frozen production RTL/model root; test helpers remain here')
    args = parser.parse_args()
    design=args.design.resolve()
    frozen_path = design/'SOURCE_MANIFEST.json'
    frozen=None
    if frozen_path.is_file():
        frozen = json.loads(frozen_path.read_text(encoding='utf-8'))['files']
        drift = [name for name, row in frozen.items() if sha(design/name) != row['sha256']]
        assert not drift, f'Frozen source drift before preparation: {drift}'
    report = ROOT/'reports/pose7/fullpipeline_regression'
    fixtures = report/'fixtures'
    cases = prepare_fixtures(args.vectors, fixtures)
    run = report/('run_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
    run.mkdir(parents=True, exist_ok=False)
    model = design/'model/pose7_96x96'
    paths = {'WEIGHTS_PATH': model/'weights.mem', 'BIASES_PATH': model/'biases.mem',
             'CENTRE_PATH': model/'feature_centre.mem', 'TOLERANCE_PATH': model/'feature_tolerance.mem',
             'ORIENTATION_PATH': model/'orientation_reference.mem',
             'CNN_WEIGHTS_PATH': design/'model/export/weights.mem', 'CNN_BIASES_PATH': design/'model/export/biases.mem'}
    (run/'pose7_fullpipeline_paths.svh').write_text(''.join(
        f'localparam {name}="{p.as_posix()}";\n' for name, p in paths.items()), encoding='ascii')
    calls = []
    for row in cases:
        calls.append(f'run_frame("{row["name"]}");\n')
    # Each cancellation is followed by a complete new job without raw reset.
    for mode in range(3):
        calls += [f'run_cancel({mode});\n', 'run_frame("golden_good");\n']
    (run/'pose7_fullpipeline_calls.svh').write_text(''.join(calls), encoding='ascii')
    case_config = []
    for row in cases:
        e, c, f = row['expected'], row['ccl'], row['frame']
        case_config.append('if(name=="'+row['name']+'")begin\n' +
            f' expected_count={c["count"]};expected_overflow={int(c["overflow"])};expected_truncated={int(c["truncated"])};\n' +
            f' expected_status={dict(PASS=0,FAIL=1,REVIEW=2)[e["decision"]]};expected_score={e["score"]};expected_flip={int(e["flip180"])};\n' +
            f' expected_mean0={e["thumb_means"][0]};expected_mean180={e["thumb_means"][1]};expected_cost0={e["orientation_costs"][0]};expected_cost180={e["orientation_costs"][1]};\n' +
            f' expected_peak_x={e["peak_xy"][0]};expected_peak_y={e["peak_xy"][1]};\n' +
            f' expected_x0={f["bbox"][0]};expected_y0={f["bbox"][1]};expected_x1={f["bbox"][2]};expected_y1={f["bbox"][3]};\nend\n')
    (run/'pose7_fullpipeline_config.svh').write_text('else '.join(case_config)+'else fail("unknown fixture name");\n', encoding='ascii')
    rtl = [design/'01_rtl'/p for p in RTL_NAMES]
    tb = ROOT/'reports/pose7/tb_pose7_fullpipeline.sv'
    lines = ['onerror {quit -code 2}', 'onbreak {quit -code 3}', 'vlib work',
             f'vlog -sv +incdir+{run.as_posix()} '+ ' '.join('"'+p.as_posix()+'"' for p in rtl+[tb]),
             f'vsim -voptargs=+acc work.tb_pose7_fullpipeline +FIXTURES={fixtures.as_posix()}',
             'run -all', 'quit -code 0', '']
    (run/'run.do').write_text('\n'.join(lines), encoding='ascii')
    pins = {str(p): sha(p) for p in rtl+[tb, Path(__file__)]+list(paths.values())+list(fixtures.rglob('*')) if p.is_file()}
    save(run/'SOURCE_SHA256.json', pins)
    save(run/'CASES.json', cases)
    result = {'status': 'PREPARED', 'run_directory': str(run),
              'command': [str(args.sim), '-batch', '-syncio', '-do', 'run.do'],
              'working_directory': str(run), 'RTL': 'NOT_RUN', 'hardware': 'NOT_RUN',
              'latency_scope': 'Abstract pixel reader, 2..4 cycles per accepted read; NOT actual DDR pipeline latency.',
              'design':str(design),'source_manifest_sha256':sha(frozen_path) if frozen_path.is_file() else None}
    if args.run:
        env = dict(os.environ)
        env.update(LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT', MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT')
        with (run/'SIM.log').open('w', encoding='utf-8') as log:
            proc = subprocess.run(result['command'], cwd=run, env=env, stdout=log, stderr=subprocess.STDOUT)
        log = (run/'SIM.log').read_text(encoding='utf-8', errors='replace')
        passed = proc.returncode == 0 and 'POSE7_FULLPIPELINE_REGRESSION_PASS' in log and 'POSE7_FULLPIPELINE_FAIL' not in log and not re.search(r'\*\*\s+(Error|Fatal):', log)
        result.update(status='PASS' if passed else 'FAIL', returncode=proc.returncode,
                      RTL='PASS' if passed else 'FAIL', frames_passed=log.count('POSE7_FULLPIPELINE_FRAME_PASS'),
                      cancellation_cases_passed=log.count('POSE7_FULLPIPELINE_CANCEL_PASS'))
        result['sources_unchanged'] = all(sha(p) == h for p, h in pins.items())
        if not result['sources_unchanged']: result['status'] = 'FAIL_SOURCE_DRIFT'
        if frozen is not None:
            result['frozen_sources_unchanged']=all(sha(design/name)==row['sha256'] for name,row in frozen.items())
            if not result['frozen_sources_unchanged']:result['status']='FAIL_SOURCE_DRIFT'
        result['latency_records'] = re.findall(r'POSE7_FULLPIPELINE_FRAME_PASS[^\r\n]*', log)
    save(run/'RESULTS.json', result)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    if result['status'].startswith('FAIL'): raise SystemExit(1)


if __name__ == '__main__':
    main()
