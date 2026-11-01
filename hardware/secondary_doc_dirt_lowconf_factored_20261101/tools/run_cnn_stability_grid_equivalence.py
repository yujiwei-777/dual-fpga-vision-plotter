"""Production grid equivalence regression, adapted from the reviewed scratch helper.

The candidate is compiled directly from 01_rtl; baseline/old evidence are read
only. Generated benches and simulator work files stay in the new suite.
"""
from pathlib import Path
import hashlib
import json
import os
import random
import re
import shutil
import subprocess

from cnn_stability_grid_common import ROOT, prepare_out, replace_exact
COMMON = ROOT / "tools/cnn_stability_grid_common.py"


def main():
    HERE = ROOT / "reports/coordinate_grid_review"
    OUT = prepare_out("equivalence")
    SIM = Path("E:/model/win64")
    SOURCE = ROOT / "01_rtl/cnn_result_stabilizer.v"
    BASE = HERE / "scratch/cnn_result_stabilizer_baseline.v"
    ORIGINAL_BENCH = HERE / "scratch/tb_coordinate_grid_equivalence.sv"
    BENCH = OUT / ORIGINAL_BENCH.name
    BENCH.write_bytes(ORIGINAL_BENCH.read_bytes())
    raw_trace = ROOT / "02_sim/cnn_stability/reference_trace.jsonl"
    env = os.environ.copy()
    env.update(MGLS_LICENSE_FILE=str(SIM / "LICENSE.TXT"), LM_LICENSE_FILE=str(SIM / "LICENSE.TXT"))
    PARAMS = [(1, 0, 1), (2, 1, 2), (3, 2, 3), (4, 0, 4), (15, 15, 15)]


    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest().upper()


    def box(x0=128, y0=128, x1=256, y1=256, cls=2, conf=80, area=10000):
        return sum(value << bit for value, bit in zip(
            (x0, y0, x1, y1, cls, conf, 0, area), (0, 16, 32, 48, 64, 80, 88, 96)))


    events = []
    groups = {}


    def event(label, boxes=(), op=0, count=None):
        packed = sum(value << (128 * i) for i, value in enumerate(boxes))
        if op != 3:
            for value in boxes:
                assert all(((value >> bit) & 7) == 0 for bit in (0, 16, 32, 48))
        events.append((op, len(boxes) if count is None else count, packed))
        groups[label] = groups.get(label, 0) + 1


    raw_count = 0
    for line in raw_trace.read_text().splitlines():
        row = json.loads(line)
        if row["group"] != "raw_replay":
            continue
        op, count, packed = row["op"], row["count"], int(row["input"], 16)
        boxes = [(packed >> (128 * i)) & ((1 << 128) - 1) for i in range(min(count, 4))]
        event("existing_raw_replay", boxes, op=op, count=count)
        raw_count += op == 0
    assert raw_count == 1170

    # Complete-frame endpoints, minimal grid cells, all four corners, full area.
    event("boundary_clear", op=1)
    for _ in range(18):
        event("full_frame_area_max", [box(0, 0, 1280, 720, area=0xffffffff)])
    for _ in range(18):
        event("four_frame_corners", [box(0, 0, 8, 8, cls=1, area=0xffffff),
            box(1272, 0, 1280, 8, cls=4, area=0xffffff),
            box(0, 712, 8, 720, cls=7, area=0xffffff),
            box(1272, 712, 1280, 720, cls=9, area=0xffffff)])

    # Repeated identity acquisition and deterministic nearest-distance tie order.
    for delta in (0, 8, 72, 80, 88, 152, 160, 168):
        event("gate_clear", op=1)
        for _ in range(18):
            event("overlap_ratio_center_gates", [box(320, 160, 480, 320)])
        for _ in range(18):
            event("overlap_ratio_center_gates", [box(320 + delta, 160, 480 + delta, 320, cls=3)])
    for ratio in (1, 2, 3):
        event("ratio_clear", op=1)
        for _ in range(18):
            event("exact_size_ratio", [box(320, 160, 384, 224)])
        for _ in range(18):
            event("exact_size_ratio", [box(320, 160, 320 + 64 * ratio, 160 + 64 * ratio)])

    event("crossing_clear", op=2)
    for repeat in range(3):
        for step in range(49):
            d = step * 8
            boxes = [box(256 + d, 240, 416 + d, 400, cls=2, area=0xffffff),
                     box(768 - d, 240, 928 - d, 400, cls=3, area=0xffffff)]
            if step & 1:
                boxes.reverse()
            event("crossing_and_equal_area", boxes)

    event("tie_clear", op=1)
    for _ in range(18):
        event("exact_distance_ties", [box(320, 160, 480, 320, cls=1), box(480, 160, 640, 320, cls=4)])
    for i in range(40):
        boxes = [box(392, 160, 552, 320, cls=1), box(408, 160, 568, 320, cls=4)]
        if i & 1:
            boxes.reverse()
        event("exact_distance_ties", boxes)

    # Random aligned geometry, unreliable observations, invalid aligned bounds and
    # counts: no quantization is applied to otherwise valid pixel coordinates.
    rng = random.Random(20261031)
    for i in range(800):
        if i % 61 == 0:
            event("random_clear_reset", op=1 if i & 1 else 2)
        boxes = []
        for j in range(rng.randrange(5)):
            x0 = rng.randrange(160) * 8
            y0 = rng.randrange(90) * 8
            x1 = rng.randrange(x0 // 8 + 1, 161) * 8
            y1 = rng.randrange(y0 // 8 + 1, 91) * 8
            cls = rng.choice([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
            if i % 47 == 0:
                x1 = 1288
            if i % 53 == 0:
                y1 = 728
            boxes.append(box(x0, y0, x1, y1, cls=cls, conf=rng.choice([0, 1, 39, 100]),
                             area=rng.choice([0, 1, 921600, 0xffffff, 0xffffffff])))
        rng.shuffle(boxes)
        event("random_aligned", boxes)
    for count in (5, 6, 7):
        event("invalid_count", [box()], count=count)

    # Each endpoint and each forbidden low bit must fail closed, without silent
    # truncation. Baseline accepts arbitrary pixels; equivalence is inapplicable.
    for coordinate in range(4):
        for lowbit in (1, 2, 4):
            event("nonaligned_clear", op=1)
            coordinates = [128, 128, 256, 256]
            coordinates[coordinate] += lowbit
            for _ in range(18):
                event("explicit_nonaligned_rejection", [box(*coordinates)], op=3)
    event("final_clear", op=2)

    vectors = OUT / "grid_vectors.txt"
    vectors.write_text("".join(f"{op} {count} {packed:0128x}\n" for op, count, packed in events))
    (OUT / "VECTOR_SCOPE.json").write_text(json.dumps({"groups": groups, "raw_frames": raw_count,
        "vectors": len(events), "independent_accuracy_dataset": False}, indent=2))
    old_copy = OUT / "cnn_result_stabilizer_baseline.sv"
    old_copy.write_text(BASE.read_text().replace("module cnn_result_stabilizer #(", "module cnn_result_stabilizer_baseline #(", 1))
    inputs = {str(path): sha(path) for path in (SOURCE, BASE, ORIGINAL_BENCH, BENCH, raw_trace, vectors, old_copy, Path(__file__))}

    inputs[str(COMMON)] = sha(COMMON)


    def run(label, args):
        proc = subprocess.run([str(x) for x in args], cwd=OUT, env=env,
                              stdin=subprocess.DEVNULL, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=240)
        (OUT / (label + ".log")).write_text(proc.stdout)
        assert not proc.returncode and not re.search(r"\*\*\s+(?:Error|Fatal):", proc.stdout), proc.stdout[-6000:]
        return proc.stdout


    run("vlib", [SIM / "vlib.exe", "work"])
    run("compile", [SIM / "vlog.exe", "-sv", "-lint", "-work", "work", old_copy, SOURCE, BENCH])
    checks = []
    for area_bits in (24, 32):
        for external in (0, 1):
            for confirm, hold, lost in PARAMS:
                label = f"equivalence_a{area_bits}_e{external}_c{confirm}h{hold}l{lost}"
                text = run(label, [SIM / "vsim.exe", "-batch", "-syncio", "-quiet", "-novopt", "-suppress", "12110",
                    "-lib", "work", "tb_coordinate_grid_equivalence", f"-gAREA_BITS={area_bits}",
                    f"-gEXTERNAL_CANDIDATE_READER={external}", f"-gCONFIRM_RESULTS={confirm}",
                    f"-gHOLD_RESULTS={hold}", f"-gLOST_RESULTS={lost}", "-do", "onerror {quit -code 1}; run -all; quit -f"])
                match = re.search(r"PASS GRID_COORDINATE_EQUIVALENCE.*", text)
                assert match
                checks.append(match[0]); print(match[0], flush=True)
    assert all(sha(Path(path)) == digest for path, digest in inputs.items())
    (OUT / "RESULTS.json").write_text(json.dumps({"status": "PASS", "scope": __doc__,
        "hardware_status": "NOT_RUN", "production_modified": False, "production_candidate_applied": True, "coord_shift": 3,
        "input_hashes": inputs, "parameter_modes": len(checks), "vectors": len(events),
        "real_frames": raw_count, "groups": groups, "checks": checks,
        "evidence_hashes": {path.name: sha(path) for path in OUT.glob("*.log")}}, indent=2))


if __name__ == "__main__":
    main()
