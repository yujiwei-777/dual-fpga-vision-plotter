"""Pinned-source area-domain derivation and exhaustive finite integer checks.

This is a source/control-flow argument plus numeric enumeration, not a formal
HDL proof. RTL behavior is independently checked by the per-cycle miter.
"""
from pathlib import Path
import hashlib
import json
import re

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def main():
    pipeline=ROOT/"01_rtl/vision_pipeline.v"
    kernel=ROOT/"02_sim/cnn_area_pipeline_compact/origin/cnn_result_stabilizer_r11.v"
    candidate=ROOT/"01_rtl/cnn_result_stabilizer.v"
    assert sha(pipeline)=="02E7954C55C5696E299D7B980DE0C4BF95C1FDF65531D1D005CFDC6882D099D5"
    assert sha(kernel)=="8D44203B9395F92441F09BD856AD77F4A4695343DD4D58AFB544C03DD2819D36"
    assert sha(candidate)=="9C946B4DDBA2E0BE3CE917E172EAF6775095349E19A28B95D4300A5596157128"
    assert "pair_overlap" not in candidate.read_text()
    text=pipeline.read_text()
    required=(
        "wire [15:0] selected_area = cc_areas[{box_index[1:0],4'b0}+:16];",
        "reg [15:0] fixed_area;",
        "fixed_area<=selected_area;",
        "area<={2'b00,fixed_area,6'b000000};",
        "wire [127:0] packed_cnn_box={{8'd0,area},8'd0,confidence,candidate_class_id,",
        "wire [127:0] multi_write_box={8'd0,(stable_slot_write ? stable_emit_box[119:0] :",
        "wire multi_slot_write=(USE_INDIRECT_SORT ? state==MULTI_STORE : state==MULTI_INSERT) || stable_slot_write;",
        ".HOLD_RESULTS(CNN_HOLD_RESULTS),.LOST_RESULTS(CNN_LOST_RESULTS),.AREA_BITS(22),.AREA_SHIFT(6)",
        "stable_start<=1'b1;state<=CNN_STABLE_WAIT;",
    )
    lines=[]
    for item in required:
        assert text.count(item)==1, item
        line=text[:text.index(item)].count("\n")+1
        lines.append({"line":line,"text":item})
    fixed_writes=re.findall(r"\bfixed_area\s*<=\s*([^;]+);",text)
    assert fixed_writes==["0","selected_area"], fixed_writes
    # Parse the flat production state case. All explicit successors are kept,
    # ignoring conditions. This conservatively overapproximates each PCB path.
    state_matches=list(re.finditer(r"^                ([A-Z][A-Z0-9_]*|default):",text,re.M))
    assert len(state_matches)>30
    graph={}
    sections={}
    for i,match in enumerate(state_matches):
        end=state_matches[i+1].start() if i+1<len(state_matches) else text.index("            endcase",match.end())
        section=text[match.start():end]
        sections[match[1]]=section
        graph[match[1]]=sorted(set(re.findall(r"\bstate\s*<=\s*([A-Z][A-Z0-9_]*);",section)))
    assert "purpose==1" in sections["IDLE"]
    pending=["PCB_WINDOW_INIT"]
    reached=set()
    while pending:
        node=pending.pop()
        if node in reached:continue
        reached.add(node)
        if node=="FINISH":continue # New admission starts a different transaction.
        assert node in graph,node
        pending.extend(graph[node])
    assert "CNN_STABLE_START" not in reached and "CNN_STABLE_WAIT" not in reached
    assert "MULTI_STORE" not in reached and "CC_START" not in reached
    assert all(node.startswith("PCB_") or node=="FINISH" for node in reached)
    # Only ordinary store writes the raw bank; every raw store is reached via
    # AREA_DIV before ROI/CNN. Stable re-publication preserves the same area.
    ordinary_to_store=[]
    pending=["ROI_PREP"]
    while pending:
        node=pending.pop()
        if node in ordinary_to_store:continue
        ordinary_to_store.append(node)
        if node=="MULTI_STORE":continue
        assert node in graph,node
        assert not re.search(r"\barea\s*<=",sections[node]),node
        pending.extend(graph[node])
    assert "MULTI_STORE" in ordinary_to_store
    assert set(re.findall(r"\bstable_start\s*<=\s*([^;]+);",text))=={"1'b0","1'b1"}

    digest=hashlib.sha256()
    roundtrips=0
    for code in range(65536):
        area=code<<6
        assert 0<=area<(1<<22) and area&63==0 and area>>22==0
        assert area>>6==code and ((area>>6)<<6)==area
        digest.update(area.to_bytes(4,"little"));roundtrips+=1
    # Strict adjacency plus integer transitivity proves ordering for all pairs;
    # equality is preserved because <<6 is injective on this finite domain.
    adjacent=sum((code<<6)<((code+1)<<6) for code in range(65535))
    assert adjacent==65535
    low=(1<<6)-1
    high=(0xffffffff<<22)&0xffffffff
    allowed=((1<<16)-1)<<6
    assert (low|high)==(~allowed&0xffffffff)
    # Existing raw replay observations are used verbatim by production tests.
    rows=[json.loads(line) for line in (ROOT/"02_sim/cnn_area_pipeline_compact/origin/reference_trace.jsonl").read_text().splitlines()]
    raw=[row for row in rows if row["group"]=="raw_replay" and row["op"]==0]
    assert len(raw)==1170
    raw_boxes=0
    for row in raw:
        word=int(row["input"],16)
        for i in range(min(row["count"],4)):
            area=(word>>(128*i+96))&0xffffffff
            assert area&(low|high)==0
            raw_boxes+=1
    report={"status":"PASS_SOURCE_DERIVATION_AND_FINITE_INTEGER_CHECKS",
        "production_modified":False,"hardware_status":"NOT_RUN",
        "input_hashes":{str(p):sha(p) for p in (pipeline,kernel,candidate,Path(__file__))},
        "source_evidence":lines,"fixed_area_assignments":fixed_writes,
        "pcb_reachable_before_finish":sorted(reached),
        "pcb_cannot_reach_stabilizer_in_same_transaction":True,
        "ordinary_post_area_path_to_store":sorted(ordinary_to_store),
        "invariant":"Each ordinary raw area32 is {10'b0,fixed_area16,6'b0}; 24-bit area bus is {2'b0,fixed_area16,6'b0}",
        "induction":["Reset/admission/clear empty raw slots with area=0",
            "BOX_MAP captures only selected_area16; AREA_DIV writes area={2'b0,fixed_area16,6'b0}",
            "No area write occurs between AREA_DIV and ordinary MULTI_STORE",
            "Raw confidence insertion only reorders/copies these exact words",
            "R11 AREA_BITS24 stabilizer stores/emits area unchanged; destructive bank reuse remains in this domain",
            "PCB state graph reaches only PCB states and FINISH before new admission; it never starts this ordinary kernel"],
        "integer_checks":{"code_domain_size":roundtrips,"strict_adjacent_order_checks":adjacent,
            "allowed_bit_mask":f"{allowed:08X}","forbidden_bit_mask":f"{low|high:08X}",
            "encoded_area_min":0,"encoded_area_max":65535<<6,
            "encoded_area_sha256":digest.hexdigest().upper(),"raw_replay_frames":len(raw),"raw_replay_boxes":raw_boxes},
        "metric":{"r11_area_bits":24,"candidate_code_bits":16,"coordinate_shift":3,
            "distance_bits":10,"best_metric_bits":16,
            "area_phase":"Compare area code without shift; monotonic ordering preserves allocation/primary/ties",
            "matching_phase":"Exactly the original R11 coordinate-grid distance, 10 low bits, no area rescaling"},
        "structure":{"payload_r11":{"depth":4,"logical_width_bits":54},
            "payload_candidate":{"depth":4,"logical_width_bits":46},
            "metadata_r11_and_candidate":{"depth":4,"logical_width_bits":22},
            "logical_payload_bits_removed":32,"best_metric_ff_bits_removed":8,
            "physical_eram_count_or_packed_lut_savings":"NOT_MEASURED"},
        "limits":["Pinned source/control-flow argument, not a formal Verilog proof",
            "State graph overapproximates branch conditions and stops at FINISH; fault-forced state corruption not assumed",
            "Runtime source-to-candidate behavior is verified separately by cycle miter and lifecycle suites",
            "Logical width reductions can be optimized away already and do not guarantee physical area savings"]}
    output=HERE/"AREA_DOMAIN_PROOF.json"
    assert not output.exists()
    output.write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps({"status":report["status"],"proof_sha256":sha(output),"integer_checks":report["integer_checks"],"structure":report["structure"]},indent=2))


if __name__=="__main__":
    main()
