"""Generate label-free sequences, compare production kernel to integer gold."""
from __future__ import annotations

from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import random
import subprocess

from cnn_stability_reference import Box, Stabilizer, pack_boxes, unpack_boxes

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "02_sim/cnn_stability"
DATA_ORIGIN = ROOT.parent / "cnn_static_angle_diagnostic_20261031/reports/ccl_contract/frames.jsonl"
DATA = OUT / "frozen_frames.jsonl"
SIM = Path("E:/model/win64")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def box(cls=2, conf=57, x=100, y=100, w=100, h=100, area=200, reserved=0) -> Box:
    return Box(x, y, x+w, y+h, cls, conf, reserved, area)


def directed() -> list[dict]:
    events: list[dict] = []

    def emit(name, boxes=(), count=None, op=0):
        events.append({"group": "directed", "case": name, "op": op,
                       "count": len(boxes) if count is None else count, "input": pack_boxes(list(boxes))})

    def clear(name):
        emit(name, op=1)

    clear("initial_confirmation")
    for i in range(3):emit("initial_confirmation", [box()])
    for cls, conf in [(3, 0), (2, 65)]:emit("roundtrip_C2_57_C3_0_C2_65", [box(cls, conf)])
    for i in range(8):emit("alternating_class_keeps_uncertainty", [box(3 if i%2==0 else 2)])
    for i in range(3):emit("three_reliable_switch", [box(3, 70)])
    for i in range(3):emit("three_low_scores_clear_history", [box(3, 0)])
    for i in range(3):emit("reacquire_after_low_scores", [box(3, 62)])
    for i in range(2):emit("missing_then_return", [])
    emit("missing_then_return", [box(3, 63)])
    for i in range(3):emit("three_missing_release", [])
    for i in range(3):emit("same_position_new_object_fresh_streak", [box(8, 70)])
    clear("two_targets_slot_swaps")
    for i in range(7):
        two = [box(2, 80 if i%2 else 30, x=100, area=400), box(8, 30 if i%2 else 90, x=600, area=300)]
        emit("two_targets_slot_swaps", sorted(two, key=lambda b: -b.confidence))
    for i in range(4):
        emit("background_high_conf_cannot_steal_primary", [box(6, 99, x=1000, area=900), box(8, 50, x=600, area=300), box(2, 45, x=100, area=400)])
    clear("four_targets_slot_swaps")
    for i in range(8):
        four = [box(j+1, 30+((j+i)%4)*15, x=50+j*250, area=100+j*10) for j in range(4)]
        emit("four_targets_slot_swaps", sorted(four, key=lambda b: -b.confidence))
    # Existing targets must be matched before a larger new candidate is admitted.
    for i in range(4):
        emit("full_tracks_background_admission", [box(9, 99, x=1100, area=2000), box(3, 60, x=550, area=120),
                                                 box(2, 60, x=300, area=110), box(1, 60, x=50, area=100)])
    clear("coordinate_limits_and_invalid_classes")
    for i in range(3):emit("exclusive_image_boundary", [Box(0,0,1280,720,9,100,255,921600)])
    emit("invalid_class_discarded", [Box(0,0,1280,720,65535,100,255,921600)])
    emit("invalid_class_discarded", [Box(0,0,1280,720,0,100,255,921600)])
    emit("invalid_geometry_dropped", [Box(0,0,1281,720,9,100,0,921600), Box(500,100,500,200,3,70,0,20)])
    clear("invalid_count_rejection")
    for i in range(3):emit("count7_rejected_empty_uncertain", [box(j+1,70,x=50+j*250,area=100+j) for j in range(4)], count=7)
    clear("association_gates")
    for i in range(3):emit("geometry_gate_seed", [box(1,70)])
    emit("center_shift_exact_half_width", [box(1,70,x=150)])
    emit("center_shift_over_half_width", [box(1,70,x=201)])
    emit("scale_exact_ratio_two", [box(1,70,x=101,w=200)])
    emit("scale_over_ratio_two", [box(1,70,x=51,w=401)])
    clear("ties_and_area_admission")
    for i in range(3):emit("equal_area_stable_candidate_index", [box(6,70,x=400,area=500),box(4,70,x=100,area=500)])
    emit("global_pair_tie_track_then_candidate", [box(7,75,x=125,area=500),box(9,75,x=375,area=500)])
    clear("busy_start_clear_reentry")
    emit("busy_start_ignored", [box()], op=3)
    emit("busy_start_ignored", [box()], op=3)
    emit("busy_start_ignored", [box()], op=3)
    emit("clear_while_busy_aborts", [box()], op=4)
    for i in range(3):emit("reentry_after_busy_clear", [box(5,80)])
    emit("async_reset_clears", op=2)
    for i in range(3):emit("reentry_after_reset", [box(7,90)])
    return events


def real_events() -> tuple[list[dict], list[dict]]:
    rows = [json.loads(line) for line in DATA.read_text(encoding="utf-8").splitlines()]
    assert len(rows) == 1170
    rows.sort(key=lambda row: (row["capture_session"], row["frame_id"], row["capture_batch"], row["index"]))
    events = []
    last_session = None
    for row in rows:
        if row["capture_session"] != last_session:
            events.append({"group": "raw_replay", "case": "capture_session_clear", "op": 1, "count": 0, "input": 0})
            last_session = row["capture_session"]
        # Production MULTI_INSERT sorts by confidence only, preserving ties.
        candidates = sorted(row["current_candidates"], key=lambda c: -c["confidence_0_to_100"])
        assert len(candidates) <= 4
        packed = [Box(*c["box"], c["class_id"], c["confidence_0_to_100"], 0, c["area"]*64)
                  for c in candidates]
        events.append({"group": "raw_replay", "case": "all_current_candidates", "op": 0,
                       "count": len(packed), "input": pack_boxes(packed),
                       "source_index": row["index"], "capture_session": row["capture_session"],
                       "capture_batch": row["capture_batch"], "frame_id": row["frame_id"],
                       "true_class_for_metrics_only": row["true_class_id"]})
    return events, rows


def random_events() -> list[dict]:
    rng = random.Random(0xC5520261031)
    events = []
    objects = [box(j+1,60,x=70+j*280,area=100+j*50) for j in range(4)]
    for index in range(1200):
        if index % 60 == 0:
            events.append({"group":"random","case":"seeded_clear","op":1,"count":0,"input":0})
        candidates = []
        for j, old in enumerate(objects):
            cls = rng.randint(1,9) if rng.random()<0.07 else old.class_id
            nx = min(1170,max(0,old.x0+rng.randint(-20,20)))
            ny = min(610,max(0,old.y0+rng.randint(-20,20)))
            conf = 0 if rng.random()<0.22 else rng.randint(1,100)
            current = box(cls,conf,nx,ny,old.x1-old.x0,old.y1-old.y0,rng.randint(0,0xffff),rng.randint(0,255))
            objects[j] = current
            if rng.random()>0.16:
                candidates.append(current)
        rng.shuffle(candidates)
        count = len(candidates)
        if index % 87 == 0 and candidates:
            b=candidates[0]
            candidates[0]=Box(b.x0,b.y0,b.x1,b.y1,65535,b.confidence,b.reserved,b.area)
        if index % 101 == 0 and candidates:
            b=candidates[0]
            candidates[0]=Box(b.x0,b.y0,1281,b.y1,b.class_id,b.confidence,b.reserved,b.area)
        if index % 113 == 0:
            count=7
        events.append({"group":"random","case":"seeded_multitarget_jitter_drop_reclass","op":0,
                       "count":count,"input":pack_boxes(candidates)})
    return events


def semantic_assertions(trace: list[dict]) -> dict:
    cases = {}
    for event in trace:
        if event["group"]=="directed" and event["op"] not in (1,2,4):
            cases.setdefault(event["case"],[]).append(event)

    def classes(event):
        return [(b.class_id,b.confidence) for b in unpack_boxes(int(event["output"],16),event["output_count"])]

    assert [classes(e) for e in cases["initial_confirmation"]]==[[],[],[(2,57)]]
    assert [classes(e) for e in cases["roundtrip_C2_57_C3_0_C2_65"]]==[[(2,0)],[(2,65)]]
    assert [classes(e) for e in cases["three_reliable_switch"]]==[[(2,0)],[(2,0)],[(3,70)]]
    assert [classes(e) for e in cases["three_low_scores_clear_history"]]==[[(3,0)],[(3,0)],[]]
    assert [e["uncertain"] for e in cases["three_missing_release"]]==[1,1,0]
    assert [classes(e) for e in cases["same_position_new_object_fresh_streak"]]==[[],[],[(8,70)]]
    assert all(classes(e)[0][0]==2 for e in cases["two_targets_slot_swaps"][2:])
    assert all(classes(e)[0][0]==2 for e in cases["background_high_conf_cannot_steal_primary"])
    assert all([c for c,_ in classes(e)]==[4,3,2,1] for e in cases["four_targets_slot_swaps"][2:])
    assert all(e["output_count"]==0 and e["uncertain"]==1 for e in cases["invalid_class_discarded"])
    assert all(e["output_count"]==0 and e["uncertain"]==1 for e in cases["count7_rejected_empty_uncertain"])
    checks=0
    for e in trace:
        if e["op"] in (1,2,4):continue
        inputs=unpack_boxes(int(e["input"],16),min(e["count"],4)) if e["count"]<=4 else []
        outputs=unpack_boxes(int(e["output"],16),e["output_count"])
        for output in outputs:
            valid=[b for b in inputs if b.geometry_valid and 1<=b.class_id<=9 and
                   (b.x0,b.y0,b.x1,b.y1,b.area)==(output.x0,output.y0,output.x1,output.y1,output.area)]
            assert valid,(e["id"],"ghost geometry",output)
            assert output.reserved==0
            if output.confidence:
                assert any(b.class_id==output.class_id and b.confidence==output.confidence for b in valid)
            else:
                assert e["uncertain"]==1
            checks+=1
    return {"directed_history_and_order_assertions":"PASS","no_ghost_or_confidence_upgrade_checks":checks,
            "random_seed":"0xC5520261031","random_results":1200}


def generate() -> tuple[list[dict], dict]:
    events = directed()
    events.extend(random_events())
    real, rows = real_events()
    events.extend(real)
    model = Stabilizer()
    lines, trace = [], []
    raw_metrics = Counter()
    previous_raw = previous_output = previous_session = None
    for ident, event in enumerate(events):
        if event["op"] in (1,2,4):
            model.clear()
            expected = (0,0,0)
        else:
            expected = model.update(event["count"], event["input"])
        event = dict(event, id=ident, output_count=expected[0], output=f"{expected[1]:0128x}", uncertain=expected[2])
        event["input"] = f"{event['input']:0128x}"
        trace.append(event)
        lines.append(f"{ident} {event['op']} {event['count']} {event['input']} {expected[0]} {expected[1]:0128x} {expected[2]}")
        if event["group"] == "raw_replay" and event["op"] == 0:
            raw_metrics["frames"] += 1
            raw_metrics["input_candidates"] += event["count"]
            raw_metrics["uncertain_frames"] += expected[2]
            outputs = unpack_boxes(expected[1], expected[0])
            inputs = unpack_boxes(int(event["input"],16), event["count"])
            raw_metrics["output_targets"] += len(outputs)
            raw_metrics["output_primary_accepted"] += bool(outputs and outputs[0].confidence > 0)
            raw_metrics["no_output_frames"] += not outputs
            raw_metrics["held_zero_confidence_targets"] += sum(b.confidence==0 for b in outputs)
            pending_visible=sum(track is not None and track.missing==0 and track.confirmed==0 for track in model.tracks)
            raw_metrics["unconfirmed_visible_tracks"] += pending_visible
            raw_metrics["frames_with_unconfirmed_visible_tracks"] += pending_visible>0
            raw_metrics["zero_confidence_input_candidates"] += sum(b.confidence==0 for b in inputs)
            raw_metrics["raw_primary_accepted"] += bool(inputs and inputs[0].confidence>0)
            raw_metrics["raw_primary_matches_dataset_label"] += bool(inputs and inputs[0].confidence>0 and inputs[0].class_id==event["true_class_for_metrics_only"])
            raw_metrics["raw_primary_differs_dataset_label"] += bool(inputs and inputs[0].confidence>0 and inputs[0].class_id!=event["true_class_for_metrics_only"])
            raw_metrics["primary_matches_dataset_label"] += bool(outputs and outputs[0].confidence > 0 and outputs[0].class_id == event["true_class_for_metrics_only"])
            raw_metrics["primary_differs_dataset_label"] += bool(outputs and outputs[0].confidence > 0 and outputs[0].class_id != event["true_class_for_metrics_only"])
            if previous_session==event["capture_session"]:
                if previous_raw is not None and inputs:
                    raw_metrics["raw_primary_adjacent_pairs"]+=1
                    raw_metrics["raw_primary_category_changes"]+=previous_raw.class_id!=inputs[0].class_id
                if previous_output is not None and outputs:
                    raw_metrics["output_primary_adjacent_pairs"]+=1
                    raw_metrics["output_primary_category_changes"]+=previous_output.class_id!=outputs[0].class_id
            previous_session=event["capture_session"]
            previous_raw=inputs[0] if inputs else None
            previous_output=outputs[0] if outputs else None
    (OUT / "vectors.txt").write_text("\n".join(lines)+"\n")
    (OUT / "reference_trace.jsonl").write_text("\n".join(json.dumps(event,ensure_ascii=False) for event in trace)+"\n",encoding="utf-8")
    semantics=semantic_assertions(trace)
    metrics = {"dataset_frames":len(rows),"capture_sessions":len({r["capture_session"] for r in rows}),
               "semantic_assertions":semantics,
               "raw_metrics":dict(raw_metrics),"directed_cases":dict(Counter(e["case"] for e in events if e["group"]=="directed"))}
    return trace,metrics


def run(name,args):
    env=os.environ.copy()
    env.update(MGLS_LICENSE_FILE=str(SIM/"LICENSE.TXT"),LM_LICENSE_FILE=str(SIM/"LICENSE.TXT"))
    result=subprocess.run([arg.as_posix() if isinstance(arg,Path) else str(arg) for arg in args],cwd=OUT,env=env,text=True,
                          stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=180)
    (OUT/f"{name}.log").write_text(result.stdout)
    if result.returncode or re.search(r"\*\*\s+(?:Error|Fatal):",result.stdout):
        raise RuntimeError(name+" failed:\n"+result.stdout[-6000:])
    return result.stdout


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    if not DATA.exists():
        DATA.write_bytes(DATA_ORIGIN.read_bytes())
    trace,metrics=generate()
    inputs=[ROOT/"01_rtl/cnn_result_stabilizer.v",OUT/"tb_cnn_stability.sv",
            ROOT/"tools/cnn_stability_reference.py",Path(__file__).resolve(),DATA,OUT/"vectors.txt"]
    before={str(path):sha(path) for path in inputs}
    run("vlib",[SIM/"vlib.exe",OUT/"work"])
    run("compile",[SIM/"vlog.exe","-sv","-lint","-work",OUT/"work",*inputs[:2]])
    log=run("simulate",[SIM/"vsim.exe","-batch","-syncio","-quiet","-novopt","-suppress","12110","-lib",OUT/"work",
                        "tb_cnn_stability","-do","run -all; quit -f"])
    assert "PASS CNN_STABILITY_GOLD" in log
    actual=(OUT/"rtl_trace.txt").read_text().splitlines()
    expected=[e for e in trace if e["op"] not in (1,2,4)]
    assert len(actual)==len(expected)
    cycles=[]
    for row,e in zip(actual,expected):
        ident,count,packed,uncertain,latency=row.split("|")
        assert (int(ident),int(count),int(packed,16),int(uncertain))==(e["id"],e["output_count"],int(e["output"],16),e["uncertain"])
        cycles.append(int(latency))
    assert before=={str(path):sha(path) for path in inputs},"test inputs changed during simulation"
    summary={"status":"PASS","hardware_status":"NOT_RUN","input_hashes":before,
             "exact_results_compared":len(actual),"max_latency_cycles":max(cycles),"metrics":metrics,
             "ordering":"capture_session then numeric frame_id, capture_batch and original index; clear only at session boundaries",
             "association_uses_true_class":False,
             "frozen_dataset_origin":str(DATA_ORIGIN),"frozen_dataset_sha256":sha(DATA),
             "limits":["1170 replay frames overlap existing training/development; no independent accuracy claim",
                       "Frames are selected inference observations, not every camera frame; missing observations between files are unknown",
                       "All current candidates retained, including confidence0; spatial association uses no dataset labels",
                       "Adjacent category-change totals include real object/category changes and use different surviving pair counts; not an accuracy or same-object flicker rate",
                       "Simulation covers stabilizer kernel only; integration and PCB/CNN/DDR/HXA regressions are separate"]}
    (OUT/"RESULTS.json").write_text(json.dumps(summary,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    print(f"PASS {len(actual)} exact RTL result comparisons; 1170 raw frames + directed sequences; max latency {max(cycles)} cycles")


if __name__=="__main__":main()
