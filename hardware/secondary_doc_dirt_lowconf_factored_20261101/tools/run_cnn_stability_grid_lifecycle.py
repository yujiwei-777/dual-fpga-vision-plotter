"""Production grid lifecycle regression, adapted from the reviewed scratch helper.

The candidate is compiled directly from 01_rtl; baseline/old evidence are read
only. Generated benches and simulator work files stay in the new suite.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess

from cnn_stability_grid_common import ROOT, prepare_out, replace_exact
COMMON = ROOT / "tools/cnn_stability_grid_common.py"


def main():
    HERE = ROOT / "reports/coordinate_grid_review"
    OUT = prepare_out("lifecycle")
    SOURCE = ROOT / "01_rtl/cnn_result_stabilizer.v"
    SIM = Path("E:/model/win64")
    env = os.environ.copy()
    env.update(MGLS_LICENSE_FILE=str(SIM / "LICENSE.TXT"), LM_LICENSE_FILE=str(SIM / "LICENSE.TXT"))
    originals = [ROOT / "02_sim/cnn_stability_ram" / name for name in
                 ("tb_cnn_stability_ram.sv", "tb_cnn_stability_metadata_atomic.sv")]
    ram = replace_exact(originals[0].read_text(), ".CONFIRM_RESULTS(1),.AREA_BITS(AREA_BITS)",
        ".CONFIRM_RESULTS(1),.AREA_BITS(AREA_BITS),.COORD_SHIFT(3)")
    ram = replace_exact(ram, "[AREA_BITS+41:0]", "[dut.PAYLOAD_BITS-1:0]", 2)
    ram = replace_exact(ram, "y+10'd100", "y+10'd96")
    ram = replace_exact(ram, "x+11'd100", "x+11'd96")
    ram = replace_exact(ram, "word_for={b[96+:AREA_BITS],b[57:48],b[25:16],b[42:32],b[10:0]};",
        "word_for={b[96+:AREA_BITS],b[57:51],b[25:19],b[42:35],b[10:3]};")
    for bits in (10, 11):
        ram = ram.replace(f"{bits}'d100", f"{bits}'d96")
        for old in (101, 102, 103, 105):
            ram = ram.replace(f"{bits}'d{old}", f"{bits}'d104")
    metadata = replace_exact(originals[1].read_text(), ".AREA_BITS(AREA_BITS),.EXTERNAL_CANDIDATE_READER",
        ".AREA_BITS(AREA_BITS),.COORD_SHIFT(3),.EXTERNAL_CANDIDATE_READER")
    metadata = replace_exact(metadata, "reg [AREA_BITS+41:0] old_payload;", "reg [dut.PAYLOAD_BITS-1:0] old_payload;")
    metadata = replace_exact(metadata, "x0=100+250*i;x1=x0+100;y0=210;y1=310;",
                                "x0=96+256*i;x1=x0+96;y0=208;y1=304;")
    assert ".COORD_SHIFT(3)" in ram and ".COORD_SHIFT(3)" in metadata
    benches = [OUT / p.name for p in originals]
    benches[0].write_text(ram);benches[1].write_text(metadata)


    def sha(path):
        return hashlib.sha256(path.read_bytes()).hexdigest().upper()


    BASE = HERE / "scratch/cnn_result_stabilizer_baseline.v"
    inputs = {str(path): sha(path) for path in [SOURCE, BASE, Path(__file__), *originals, *benches]}

    inputs[str(COMMON)] = sha(COMMON)


    def run(label, args):
        proc = subprocess.run([str(x) for x in args], cwd=OUT, env=env,
                              stdin=subprocess.DEVNULL, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=240)
        (OUT / (label + ".log")).write_text(proc.stdout)
        assert not proc.returncode and not re.search(r"\*\*\s+(?:Error|Fatal):", proc.stdout), proc.stdout[-6000:]
        return proc.stdout


    run("vlib", [SIM / "vlib.exe", "work"])
    run("compile", [SIM / "vlog.exe", "-sv", "-lint", "-work", "work", SOURCE, *benches])
    records = []
    for area_bits in (24, 32):
        tests = [(f"payload{area_bits}", "tb_cnn_stability_ram", []),
                 (f"metadata{area_bits}", "tb_cnn_stability_metadata_atomic", []),
                 (f"metadata_external{area_bits}", "tb_cnn_stability_metadata_atomic", ["-gEXTERNAL_CANDIDATE_READER=1"])]
        for label, bench, extra in tests:
            text = run(label, [SIM / "vsim.exe", "-batch", "-syncio", "-quiet", "-novopt", "-suppress", "12110",
                "-lib", "work", bench, f"-gAREA_BITS={area_bits}", *extra,
                "-do", "onerror {quit -code 1}; run -all; quit -f"])
            checks = [line.strip("# ") for line in text.splitlines() if "PASS" in line]
            assert checks
            records.append({"test": label, "checks": checks});print(label, checks, flush=True)
    assert all(sha(Path(path)) == digest for path, digest in inputs.items())
    (OUT / "RESULTS.json").write_text(json.dumps({"status": "PASS", "scope": __doc__,
        "hardware_status": "NOT_RUN", "coord_shift": 3, "production_modified": False, "production_candidate_applied": True,
        "input_hashes": inputs, "tests": records,
        "evidence_hashes": {path.name: sha(path) for path in OUT.glob("*.log")}}, indent=2))


if __name__ == "__main__":
    main()
