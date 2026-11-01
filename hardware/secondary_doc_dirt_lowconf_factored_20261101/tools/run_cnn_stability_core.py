"""Rerun real ordinary-CNN arithmetic using frozen, same-ROM golden vectors.

The 27 vectors are nine existing native ROIs plus two synthetic detail-loss
variants per ROI. Their labels are not used for simulation acceptance.
"""
from __future__ import annotations

import ast
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/"02_sim/cnn_stability_core"
ORIGIN=ROOT.parent/"secondary_font_structured_20261028/02_sim/ordinary_cnn_remote_detail_golden_fc8_release_20261027"
SIM=Path("E:/model/win64")
NAMES=("pixels.mem","shape.mem","feature1.mem","feature2.mem","results.mem")


def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def prepare():
    OUT.mkdir(parents=True,exist_ok=True)
    fixture=OUT/"fixture_origin"
    if not fixture.exists():
        fixture.mkdir()
        for name in (*NAMES,"tb_remote_detail.sv","RESULTS.json"):
            (fixture/name).write_bytes((ORIGIN/name).read_bytes())
    prior=json.loads((fixture/"RESULTS.json").read_text(encoding="utf-8"))
    assert prior["status"]=="PASS" and prior["rtl_case_count"]==27 and prior["padding_mode"]=="zero"
    for name in ("weights.mem","biases.mem"):
        expected=[h for path,h in prior["input_hashes"].items() if path.replace("\\","/").endswith("/model/export/"+name)]
        assert len(expected)==1 and sha(ROOT/"model/export"/name)==expected[0],"golden model mismatch "+name
    for name in NAMES:
        (OUT/name).write_bytes((fixture/name).read_bytes())
    bench=(fixture/"tb_remote_detail.sv").read_text(encoding="utf-8").replace("module tb_remote_detail;","module tb_cnn_stability_core;")
    for param,name in (("WEIGHTS_MEM","weights.mem"),("BIASES_MEM","biases.mem")):
        bench=re.sub(r"\."+param+r'\("[^"]+"\)',lambda _:'.'+param+'("'+(ROOT/"model/export"/name).as_posix()+'")',bench)
    assert ".FC_CONF_SHIFT(8)" in bench and ".USE_SHARED_WORKSPACE(1)" in bench and ".EXTERNAL_MAC(1)" in bench
    bench=bench.replace("f1count=0;f2count=0;","f1count=0;f2count=0; if(c==13) begin rst_n=0; repeat(3) @(negedge clk); rst_n=1; end")
    (OUT/"tb_cnn_stability_core.sv").write_text(bench,encoding="utf-8")
    # Reuse only the explicit numerical boundary stimuli, without importing
    # their former Torch/training/cache dependencies.
    source=ROOT/"tools/run_cnn_boundaries.py"
    node=ast.parse(source.read_text(encoding="utf-8"))
    directed=next(ast.literal_eval(stmt.value) for stmt in node.body if isinstance(stmt,ast.Assign)
                  and any(isinstance(t,ast.Name) and t.id=="DIRECTED" for t in stmt.targets))
    header=bench[:bench.index("    reg [23:0] pixels")].replace("module tb_cnn_stability_core;","module tb_cnn_stability_boundaries;")
    (OUT/"tb_cnn_stability_boundaries.sv").write_text(header+directed,encoding="utf-8")
    provenance={"source_directory":str(ORIGIN),"source_hashes":{name:sha(fixture/name) for name in (*NAMES,"tb_remote_detail.sv","RESULTS.json")},
                "cases":prior["case_rows"],"contract":prior["contract"],"padding_mode":prior["padding_mode"],
                "note":"Frozen previous integer gold; all simulator inputs now reside inside this independent project."}
    (OUT/"FIXTURE_PROVENANCE.json").write_text(json.dumps(provenance,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    return prior


def run(name,args,timeout=180):
    env=os.environ.copy()
    env.update(MGLS_LICENSE_FILE=str(SIM/"LICENSE.TXT"),LM_LICENSE_FILE=str(SIM/"LICENSE.TXT"))
    with (OUT/(name+".log")).open("w",encoding="utf-8") as stream:
        result=subprocess.run([arg.as_posix() if isinstance(arg,Path) else str(arg) for arg in args],
                              cwd=OUT,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=timeout)
    text=(OUT/(name+".log")).read_text(encoding="utf-8",errors="replace")
    if result.returncode or re.search(r"\*\*\s+(?:Error|Fatal):",text):
        raise RuntimeError(name+" failed:\n"+text[-6000:])
    print("PASS "+name,flush=True)
    return text


def main():
    prior=prepare()
    rtl=[ROOT/"01_rtl"/name for name in ("cnn_core.v","vision_workspace.v","vision_shared_mac.v")]
    benches=[OUT/"tb_cnn_stability_core.sv",OUT/"tb_cnn_stability_boundaries.sv"]
    inputs=rtl+benches+[ROOT/"model/export"/name for name in ("weights.mem","biases.mem","quantization.json")]
    inputs+=[Path(__file__).resolve(),ROOT/"tools/run_cnn_boundaries.py",OUT/"FIXTURE_PROVENANCE.json"]
    inputs+=[OUT/name for name in NAMES]
    inputs+=[OUT/"fixture_origin"/name for name in (*NAMES,"tb_remote_detail.sv","RESULTS.json")]
    before={str(path):sha(path) for path in inputs}
    run("vlib",[SIM/"vlib.exe",OUT/"work"])
    run("lint",[SIM/"vlog.exe","-sv","-lint","-work",OUT/"work",*rtl,*benches])
    # Batch mode avoids the interactive console's RPC listener. A local HTTP
    # probe sent GET to that listener during the first attempt and crashed
    # vish after six numerically passing cases; preserve that diagnostic log.
    old_log=OUT/"core.log"
    if old_log.exists() and "incorrect read of header" in old_log.read_text(errors="replace"):
        (OUT/"core_interactive_rpc_failure.log").write_bytes(old_log.read_bytes())
    base=[SIM/"vsim.exe","-batch","-syncio","-quiet","-lib",OUT/"work"]
    boundary=run("boundaries",[*base,"tb_cnn_stability_boundaries","-do","run -all; quit -f"])
    assert "PASS ALL CLASSIFY BOUNDARIES checks=11" in boundary
    log=run("core",[*base,"tb_cnn_stability_core","-do","run -all; quit -f"],timeout=900)
    passed=re.findall(r"PASS CNN CASE (\d+) cycles=(\d+) logits=(-?\d+),(-?\d+),(-?\d+) class=(\d+) color_conf=(\d+) shape_conf=(\d+)",log)
    assert len(passed)==27 and "PASS ALL CNN REMOTE DETAIL cases=27" in log
    assert before=={str(path):sha(path) for path in inputs},"core test input changed during run"
    report={"status":"PASS","hardware_status":"NOT_RUN","input_hashes":before,
            "production_modules":["cnn_core","vision_workspace","vision_shared_mac"],
            "full_inference_cases":27,"native_roi_cases":9,"synthetic_detail_cases":18,
            "boundary_classify_checks":11,"reset_before_inference_case":13,
            "conv1_byte_values_compared":27*8192,"conv2_byte_values_compared":27*4096,
            "fc_logits_compared":27*3,"color_sums_compared":27*3,
            "case_results":[{"case":int(p[0]),"cycles":int(p[1]),"logits":[int(v) for v in p[2:5]],
                             "class_id":int(p[5]),"color_conf":int(p[6]),"shape_conf":int(p[7])} for p in passed],
            "confidence_shift":8,"weight_sha256":sha(ROOT/"model/export/weights.mem"),
            "bias_sha256":sha(ROOT/"model/export/biases.mem"),
            "limits":["Nine native existing dataset ROIs plus 18 synthetic detail variants; no independent accuracy claim",
                      "Gold vectors reused only after exact model-ROM identity check; generated by previous integer reference",
                      "Boundary checks inject final scores to isolate classification tie/shift/saturation",
                      "This suite proves ordinary CNN arithmetic/shared RAM/MAC compatibility; full camera/DDR/HXA integration is separate"]}
    (OUT/"RESULTS.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf-8")
    print("PASS real ordinary-CNN 27-vector arithmetic and 11 numeric boundary checks",flush=True)


if __name__=="__main__":main()
