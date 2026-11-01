"""Fresh legal-production-domain integer gold and 28-state clear/reset miter.

Writes only this new state_lifecycle directory. Never invokes TD or edits RTL.
The combined kernel is AREA22/SHIFT6/COORD3; R11 control is AREA24/COORD3.
No malformed area is masked, rounded or made legal by this test generator.
"""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
import random
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = HERE / 'state_lifecycle'
SIM = Path('E:/model/win64')
EXPECTED_CANDIDATE = '8655EB872B8FD09C002FAD93331953F298BEEDA35A2FFFDCFBC9903AE5625B0C'
EXPECTED_R11 = '8D44203B9395F92441F09BD856AD77F4A4695343DD4D58AFB544C03DD2819D36'
EXPECTED_TEMPLATE = '206CAD1D5DED4BB4D42F4CC63D25912D11D3F87FB1FB6C449310B71E0C669222'
PARAMS = ((1, 0, 1), (2, 1, 2), (3, 2, 3), (4, 0, 4), (15, 15, 15))


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def replace_once(text, old, new):
    assert text.count(old) == 1, repr(old)
    return text.replace(old, new)


def main():
    assert not OUT.exists(), 'Use a fresh independent directory; never overwrite evidence.'
    sys.dont_write_bytecode = True
    candidate = HERE / 'cnn_result_stabilizer.v'
    r11 = HERE / 'cnn_result_stabilizer_r11.v'
    template = ROOT / 'reports/kernel_overlap_redundancy_candidate/tb_overlap_equivalence.sv'
    model_path = ROOT / 'tools/cnn_stability_reference.py'
    frozen_path = ROOT / '02_sim/cnn_stability/vectors.txt'
    assert sha(candidate) == EXPECTED_CANDIDATE
    assert sha(r11) == sha(ROOT / '01_rtl/cnn_result_stabilizer.v') == EXPECTED_R11
    assert sha(template) == EXPECTED_TEMPLATE
    for name in ('LICENSE.TXT', 'vlib.exe', 'vlog.exe', 'vsim.exe'):
        assert (SIM / name).is_file(), name
    OUT.mkdir()

    baseline = OUT / 'cnn_result_stabilizer_baseline.v'
    baseline.write_text(replace_once(r11.read_text(), 'module cnn_result_stabilizer #(',
                                    'module cnn_result_stabilizer_baseline #('))
    bench = OUT / 'tb_combined_state_lifecycle.sv'
    text = replace_once(template.read_text(), 'module tb_overlap_equivalence;',
                        'module tb_combined_state_lifecycle;')
    text = replace_once(text,
        'parameter integer COORD_SHIFT=0,AREA_BITS=32,EXTERNAL_CANDIDATE_READER=0;',
        'parameter integer COORD_SHIFT=3,AREA_BITS=22,EXTERNAL_CANDIDATE_READER=0;')
    text = replace_once(text,
        'cnn_result_stabilizer_baseline #(.AREA_BITS(AREA_BITS),.COORD_SHIFT(COORD_SHIFT),',
        'cnn_result_stabilizer_baseline #(.AREA_BITS(24),.COORD_SHIFT(COORD_SHIFT),')
    text = replace_once(text,
        'cnn_result_stabilizer #(.AREA_BITS(AREA_BITS),.COORD_SHIFT(COORD_SHIFT),',
        'cnn_result_stabilizer #(.AREA_BITS(AREA_BITS),.AREA_SHIFT(6),.COORD_SHIFT(COORD_SHIFT),')
    text = replace_once(text, "{32'd10000,8'd0,8'd80,16'd2,16'd304,b,16'd208,a}",
                        "{32'd10048,8'd0,8'd80,16'd2,16'd304,b,16'd208,a}")
    text = replace_once(text, 'PASS OVERLAP_EQUIVALENCE coord=',
                        'PASS COMBINED_STATE_LIFECYCLE coord=')
    text = replace_once(text,
        'task launch(input integer count,input [511:0] boxes);begin\n',
        '''task require_domain(input integer count,input [511:0] boxes);
 integer slot;reg [127:0] b;begin
  if(count<0||count>4)$fatal(1,"count outside legal production domain");
  for(slot=0;slot<count;slot=slot+1)begin
   b=boxes[128*slot+:128];
   if((b[127:96]&32'hffc0003f)!=0||
      ((b[15:0]|b[31:16]|b[47:32]|b[63:48])&16'd7)!=0||
      b[15:0]>=b[47:32]||b[31:16]>=b[63:48]||
      b[47:32]>1280||b[63:48]>720||b[79:64]<1||b[79:64]>9)
    $fatal(1,"input outside legal production domain slot%0d",slot);
  end
 end
endtask
task launch(input integer count,input [511:0] boxes);begin
 require_domain(count,boxes);
''')
    text = replace_once(text, 'integer cycle_checks=0,serial_checks=0,bank_reuses=0,jobs=0,aborts=0,gold_checks=0;',
        '''integer cycle_checks=0,serial_checks=0,bank_reuses=0,jobs=0,aborts=0,gold_checks=0;
integer used_slot;
''')
    text = replace_once(text, ' if(baseline.state!==candidate.state)$fatal(1,"FSM cadence mismatch");',
        ''' if(baseline.state!==candidate.state)$fatal(1,"FSM cadence mismatch");
 // Atomic payload writes plus validity must preserve the overlap theorem's
 // positive ordered endpoint premise, including after every abort/reentry.
 if(rst_n&&!clear)for(used_slot=0;used_slot<4;used_slot=used_slot+1)begin
  if(candidate.track_used[used_slot]&&
    ((candidate.track_payload[used_slot][0+:8]<candidate.track_payload[used_slot][8+:8])!==1'b1||
     (candidate.track_payload[used_slot][16+:7]<candidate.track_payload[used_slot][23+:7])!==1'b1))
   $fatal(1,"used-track ordered-payload invariant failed slot%0d",used_slot);
 end''')
    bench.write_text(text)

    spec = importlib.util.spec_from_file_location('combined_lifecycle_fresh_integer_reference', model_path)
    oracle = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = oracle
    spec.loader.exec_module(oracle)
    frozen = oracle.Stabilizer()
    fresh_frozen_checks = 0
    source_events = []
    for line in frozen_path.read_text().splitlines():
        row = line.split()
        op, count, raw = int(row[1]), int(row[2]), int(row[3], 16)
        if op in (1, 2, 4):
            frozen.clear()
        else:
            assert frozen.update(count, raw) == (int(row[4]), int(row[5], 16), int(row[6]))
            fresh_frozen_checks += 1
        source_events.append((op, count, raw))
    assert fresh_frozen_checks == 2453

    def legal(count, raw):
        if not 0 <= count <= 4:
            return False
        for b in oracle.unpack_boxes(raw, count):
            if (not b.geometry_valid or not 1 <= b.class_id <= 9 or
                any(v & 7 for v in (b.x0, b.y0, b.x1, b.y1)) or b.area & 0xFFC0003F):
                return False
        return True

    events = []
    kept, skipped = 0, 0
    for op, count, raw in source_events:
        if op in (1, 2):
            events.append((op, 0, 0, 'frozen_clear_reset'))
        elif legal(count, raw):
            events.append((op, count, raw, 'frozen_legal_unmodified'))
            kept += 1
        else:
            skipped += 1

    def b(x0=320, y0=160, x1=480, y1=320, cls=2, conf=80, code=157):
        return oracle.Box(x0, y0, x1, y1, cls, conf, 0, code << 6)

    def append_boxes(boxes, group, op=0):
        raw = oracle.pack_boxes(boxes)
        assert legal(len(boxes), raw)
        events.append((op, len(boxes), raw, group))

    # Positive-width touching/separated geometry and exact centre boundaries.
    for width in (8, 16, 64, 160, 320):
        for delta in sorted({0, width // 2, width - 8, width, width + 8}):
            if delta & 7:
                continue
            events.append((1, 0, 0, 'directed_clear'))
            for _ in range(18):
                append_boxes([b(x1=320 + width)], 'directed_seed')
            for _ in range(18):
                append_boxes([b(x0=320 + delta, x1=320 + delta + width, cls=3)],
                             'touch_separate_center')
    # Exact legal area boundaries, equal-area ties and all 16-bit code bits.
    for code in (0, 1, 2, 3, 32767, 32768, 65534, 65535):
        events.append((1, 0, 0, 'area_boundary_clear'))
        for _ in range(18):
            append_boxes([b(code=code)], 'legal_area_boundary')
    events.append((1, 0, 0, 'four_target_clear'))
    for i in range(40):
        boxes = [b(96 + 256*j, 208, 192 + 256*j, 304, cls=2+2*j,
                   conf=0 if i % 7 == 0 else 80, code=65535 if j & 1 else 0) for j in range(4)]
        if i & 1:
            boxes.reverse()
        append_boxes(boxes, 'four_target_tie_reorder', op=3 if i % 11 == 0 else 0)
    # Independent legal-domain random history; no preprocessing of invalid area.
    rng = random.Random(2026103111)
    for i in range(160):
        if i % 23 == 0:
            events.append((1 if i & 1 else 2, 0, 0, 'random_clear_reset'))
        boxes = []
        for _ in range(rng.randrange(5)):
            x0, y0 = rng.randrange(160)*8, rng.randrange(90)*8
            boxes.append(b(x0, y0, rng.randrange(x0//8+1, 161)*8,
                rng.randrange(y0//8+1, 91)*8, cls=rng.randrange(1, 10),
                conf=rng.choice((0, 1, 80, 100)), code=rng.randrange(65536)))
        append_boxes(boxes, 'random_legal')
    # A launched-then-aborted frame clears the reference history, too.
    append_boxes([b()], 'clear_busy', op=4)
    append_boxes([b()], 'post_abort_fresh')
    assert all(legal(count, raw) for op, count, raw, group in events)

    vector_paths = []
    for confirm, hold, lost in PARAMS:
        model = oracle.Stabilizer(confirm, hold, lost)
        rows = []
        for op, count, raw, group in events:
            if op in (1, 2, 4):
                model.clear()
                expected = (0, 0, 0)
            else:
                expected = model.update(count, raw)
            rows.append(f'{op} {count} {raw:0128x} {expected[0]} {expected[1]:0128x} {expected[2]}\n')
        path = OUT / f'c{confirm}h{hold}l{lost}.txt'
        path.write_text(''.join(rows))
        vector_paths.append(path)

    inputs = [Path(__file__), candidate, r11, template, model_path, frozen_path,
        ROOT / '01_rtl/cnn_result_stabilizer.v', ROOT / '01_rtl/vision_pipeline.v',
        ROOT / '01_rtl/secondary_top.v', ROOT / '01_rtl/cnn_core.v', baseline, bench, *vector_paths]
    input_hashes = {str(p.resolve()): sha(p) for p in inputs}
    (OUT / 'INPUT_MANIFEST.json').write_text(json.dumps({
        'status': 'SEALED_INPUTS_BEFORE_SIMULATION', 'production_modified': False,
        'input_hashes': input_hashes, 'candidate_parameters': {'AREA_BITS': 22, 'AREA_SHIFT': 6,
            'COORD_SHIFT': 3}, 'baseline_parameters': {'AREA_BITS': 24, 'COORD_SHIFT': 3},
        'fresh_frozen_checks': fresh_frozen_checks, 'kept_frozen_observations': kept,
        'skipped_out_of_domain_observations': skipped,
        'input_policy': 'Out-of-domain observations are omitted whole; accepted words are bit-identical. No masking, rounding or eligibility adaptation.',
        'groups': {g: sum(e[3] == g for e in events) for g in sorted({e[3] for e in events})}}, indent=2))

    env = os.environ.copy()
    env.update(MGLS_LICENSE_FILE=str(SIM / 'LICENSE.TXT'), LM_LICENSE_FILE=str(SIM / 'LICENSE.TXT'))

    def run(label, args):
        log = OUT / (label + '.log')
        assert not log.exists()
        result = subprocess.run([str(a) for a in args], cwd=OUT, env=env,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=300,
            creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
        with log.open('x') as stream:
            stream.write(result.stdout)
        assert result.returncode == 0, result.stdout[-8000:]
        assert not re.search(r'\*\*\s+(?:Error|Fatal):', result.stdout), result.stdout[-8000:]
        assert all(sha(Path(p)) == digest for p, digest in input_hashes.items()), 'Input drift during simulation'
        return result.stdout

    run('vlib', [SIM / 'vlib.exe', 'work'])
    run('compile', [SIM / 'vlog.exe', '-sv', '-lint', '-work', 'work', baseline, candidate, bench])
    modes = []
    expected_gold = sum(op not in (1, 2, 4) for op, count, raw, group in events)
    for (confirm, hold, lost), vector in zip(PARAMS, vector_paths):
        for reader in (0, 1):
            # This explicitly mutable simulator staging file is not a sealed
            # input; the corresponding immutable per-parameter vector is.
            (OUT / 'vectors.txt').write_bytes(vector.read_bytes())
            mode = f'production_c{confirm}h{hold}l{lost}_e{reader}'
            log = run(mode, [SIM / 'vsim.exe', '-batch', '-syncio', '-quiet', '-novopt',
                '-suppress', '12110', '-lib', 'work', 'tb_combined_state_lifecycle',
                f'-gEXTERNAL_CANDIDATE_READER={reader}', f'-gCONFIRM_RESULTS={confirm}',
                f'-gHOLD_RESULTS={hold}', f'-gLOST_RESULTS={lost}',
                '-do', 'onerror {quit -code 1}; run -all; quit -f'])
            passes = re.findall(r'PASS COMBINED_STATE_LIFECYCLE[^\r\n]*', log)
            assert len(passes) == 1, log[-8000:]
            check = passes[0]
            assert check.startswith(f'PASS COMBINED_STATE_LIFECYCLE coord=3 area=22 reader={reader} params={confirm}/{hold}/{lost} ')
            for key, expected in (('vectors', len(events)), ('gold', expected_gold), ('aborts', 56)):
                assert int(re.search(r'\b' + key + r'=(\d+)', check)[1]) == expected
            modes.append({'mode': mode, 'check': check, 'bench': str(bench.resolve()),
                'params': {'CONFIRM_RESULTS': confirm, 'HOLD_RESULTS': hold, 'LOST_RESULTS': lost,
                    'EXTERNAL_CANDIDATE_READER': reader, 'AREA_BITS': 22, 'AREA_SHIFT': 6, 'COORD_SHIFT': 3},
                'log': mode + '.log', 'vectors': vector.name,
                'log_sha256': sha(OUT / (mode + '.log')), 'vectors_sha256': sha(vector), 'aborts': 56})
            print(check, flush=True)
    assert len(modes) == len({m['mode'] for m in modes}) == 10
    assert all(sha(Path(p)) == digest for p, digest in input_hashes.items())
    evidence_paths = [OUT / 'INPUT_MANIFEST.json', OUT / 'vlib.log', OUT / 'compile.log',
                      OUT / 'vectors.txt', *[OUT / (row['mode'] + '.log') for row in modes]]
    result = {'status': 'PASS_COMBINED_STATE_LIFECYCLE',
        'completed_at_utc': datetime.now(timezone.utc).isoformat(),
        'production_modified': False, 'hardware_status': 'NOT_RUN',
        'mode_count': 10, 'aggregate_aborts': 560, 'modes': modes,
        'vectors_per_mode': len(events), 'gold_checks_per_mode': expected_gold,
        'fresh_frozen_gold_checks': fresh_frozen_checks,
        'candidate_sha256': sha(candidate), 'baseline_sha256': sha(r11),
        'input_hashes': input_hashes,
        'evidence_hashes': {str(p.relative_to(OUT)): sha(p) for p in evidence_paths},
        'limits': ['Legal production domain only; invalid-input behavior is not legalized or tested here.',
            'All 28 FSM states are reached without force, then aborted once by clear and once by async reset in each mode.',
            'Kernel only; no TD, place, route, board timing, CDC/FIFO/DDR/DRC, reimport, bitgen or accuracy claim.']}
    with (OUT / 'RESULTS.json').open('x') as stream:
        json.dump(result, stream, indent=2)
    print(json.dumps({'status': result['status'], 'mode_count': 10, 'aggregate_aborts': 560,
        'results_sha256': sha(OUT / 'RESULTS.json')}, indent=2), flush=True)


if __name__ == '__main__':
    main()
