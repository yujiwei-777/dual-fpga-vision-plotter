"""Replay PCB model/core/reader golden vectors in the CNN-stability variant."""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "02_sim/cnn_named_pcb"
OUT.mkdir(parents=True, exist_ok=True)
assert not (OUT / "RESULTS.json").exists(), "Preserve existing regression evidence"
SIM = Path("E:/model/win64")
assert (SIM / "LICENSE.TXT").is_file()
env = os.environ.copy()
env.update(MGLS_LICENSE_FILE=str(SIM / "LICENSE.TXT"), LM_LICENSE_FILE=str(SIM / "LICENSE.TXT"))
model = ROOT / "model/experiments/conv4_4"
expected = {"weights.mem": "9B844CB0B0844F8A72E59192B4F04D3C192B6C1A501DA1F3376CE6BF5354DDE6",
            "biases.mem": "45FAC7544E47F2CD73A5571A6136CB57A82CADD1B130057C8FCB0BC647E51232"}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

for name, digest in expected.items():
    assert sha(model / name) == digest
vectors = OUT / "rtl_vectors"
source_vectors = ROOT / "02_sim/new_capture_mix_vectors3_20261029/rtl_vectors"
if vectors.exists():
    assert {p.name: sha(p) for p in vectors.iterdir() if p.is_file()} == {
        p.name: sha(p) for p in source_vectors.iterdir() if p.is_file()}, "Copied PCB vectors differ"
else:
    shutil.copytree(source_vectors, vectors)
tests = {"tb_real_pcb_core": "BINARY_C4_4_GOLDEN_PASS samples=15 sat=0",
         "tb_real_pcb_pipeline": "PCB_RAW_PIPELINE_GOLDEN_PASS samples=9"}
benches = []
for name in tests:
    original = ROOT / "02_sim/centered_50plus_inputs_20261029" / (name + ".sv")
    path = OUT / (name + ".sv")
    source = original.read_text()
    source = source.replace("model/selected/weights.mem", (model / "weights.mem").as_posix())
    source = source.replace("model/selected/biases.mem", (model / "biases.mem").as_posix())
    if name == "tb_real_pcb_pipeline":
        source = source.replace(".clk(clk),.rst_n(rst_n),.start(start)",
                                ".history_clear(1'b0),.clk(clk),.rst_n(rst_n),.start(start)")
    path.write_text(source)
    benches.append(path)
sources = [ROOT / "01_rtl" / name for name in (
    "vision_color_stats.v", "edge_roi_ccl.v", "vision_pixel_reader.v", "vision_ccl.v",
    "pcb_defect_cluster.v", "vision_workspace.v", "vision_shared_mac.v", "pcb_fullboard_spatial96.v",
    "vision_pipeline.v", "cnn_core.v", "cnn_result_stabilizer.v")]
inputs = [*sources, *benches, *vectors.iterdir(), *(model / name for name in expected), Path(__file__)]
hashes = {str(path.resolve()): sha(path) for path in inputs if path.is_file()}

def run(label, command):
    with (OUT / (label + ".log")).open("w") as log:
        result = subprocess.run([str(value) for value in command], cwd=OUT, env=env,
                                text=True, stdout=log, stderr=subprocess.STDOUT, timeout=300)
    text = (OUT / (label + ".log")).read_text(errors="replace")
    if result.returncode or re.search(r"\*\*\s+(?:Error|Fatal):", text):
        raise RuntimeError(label + " failed:\n" + text[-6000:])
    return text

run("vlib", [SIM / "vlib.exe", "work"])
run("compile", [SIM / "vlog.exe", "-sv", "-lint", "-work", "work", *sources, *benches])
checks = {}
for name, marker in tests.items():
    text = run(name, [SIM / "vsim.exe", "-batch", "-quiet", "-novopt", "-suppress", "12110",
                      "-lib", "work", name, "-do", "onerror {quit -code 1}; run -all; quit -f"])
    assert marker in text, "missing pass marker " + name
    checks[name] = {"status": "PASS", "marker": marker,
                    "checks": [line.strip("# ") for line in text.splitlines() if "PASS" in line]}
    print(name + ": " + marker, flush=True)
assert all(sha(Path(path)) == digest for path, digest in hashes.items())
(OUT / "RESULTS.json").write_text(json.dumps({"status": "PASS", "input_hashes": hashes,
    "tests": checks, "hardware_status": "NOT_RUN", "production_sources_written": False,
    "scope": __doc__.strip()}, indent=2))
