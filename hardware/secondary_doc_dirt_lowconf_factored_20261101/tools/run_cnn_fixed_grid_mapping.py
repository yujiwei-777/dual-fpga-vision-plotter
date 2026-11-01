"""Validate the promoted fixed-grid pipeline against its frozen R10 reference.

This runner never promotes or modifies RTL. It refuses to create output until
the production pipeline exactly matches the reviewed C7B43F candidate. Each run
requires a new 02_sim/cnn_fixed_grid_mapping directory, reruns the exhaustive
integer proof, and compiles the actual production pipeline/kernel in the reviewed
37-output/11-control cycle miter. Controlled CCL/CNN/DDR leaves are used; no full
image inference, board, synthesis, resource, timing, or bit validation is claimed.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT / "reports/fixed_grid_mapping_candidate"
OUT = ROOT / "02_sim/cnn_fixed_grid_mapping"
SIM = Path("E:/model/win64")
SOURCE = ROOT / "01_rtl/vision_pipeline.v"
KERNEL = ROOT / "01_rtl/cnn_result_stabilizer.v"
BASE = REVIEW / "baseline/vision_pipeline.v"
PROOF = REVIEW / "prove_fixed_mapping.py"
BENCH = REVIEW / "miter/tb_fixed_grid_mapping_miter.sv"
STUBS = REVIEW / "miter/pipeline_leaf_stubs.sv"
CANDIDATE_SHA256 = "C7B43FE8727F1145C2EF060CE9DC464029AF74CB4BD372DF10E1395E5D878413"
BASE_SHA256 = "88F00AC396BC103CB7A802BD349F290E3E85D68BEAD8B7CFDA5F9282F23A36FC"
KERNEL_SHA256 = "8D44203B9395F92441F09BD856AD77F4A4695343DD4D58AFB544C03DD2819D36"
PINS = {
    SOURCE: CANDIDATE_SHA256,
    KERNEL: KERNEL_SHA256,
    BASE: BASE_SHA256,
    PROOF: "808C3DF5672F1E69127C2010FDD1BDB4BB4971CDC1D48389FD828C5023C1CE36",
    BENCH: "98A159C7E02713647ADCDF99215B5E69CE7499137B078A66F0A6351AB529E26A",
    STUBS: "B19E7BDF866824235C6B89DC78E4A3FCD41C48FD0EE4C29FFA8ADFCF89AEAAA2",
    REVIEW / "baseline/run_cnn_stability_pipeline.py":
        "30A54C5EEA5409483C01D78CC66841B48BFAC83DF7393E188A066131CA4B1266",
}
PUBLIC = """word_req byte_addr busy done result_job_id config_version color_id shape_id
confidence valid x0 x1 y0 y1 area pcb_checked pcb_good pcb_status defect_count
defect_boxes defect_kinds multi_count multi_boxes multi_flags teach_success
teach_failed teach_code teach_commit taught_station_header ext_reader_request
ext_reader_invalidate ext_pixel_x ext_pixel_y yolo_pixel_valid yolo_pixel_rgb
yolo_pixel_last color_word_active""".split()
CONTROL = """state box_index box_total sample_index purpose_q map_bits_left area_bits_left
map_job raw_slot_order insert_physical_slot stable_raw_released""".split()
EXPECTED_CYCLES = 11742298


def now():
    return datetime.now(timezone.utc).isoformat()


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def hash_checks(values, parent=ROOT):
    for name, digest in values.items():
        path = Path(name)
        if not path.is_absolute():
            path = parent / path
        path = path.resolve()
        require(path.is_relative_to(ROOT.resolve()), "Evidence escapes independent project: " + str(path))
        require(path.is_file() and sha(path) == digest, "Input/evidence drift: " + str(path))


def record_inputs(paths):
    return {str(path.resolve()): sha(path) for path in paths}


def write_json(path, value):
    # Every output in this suite is new; completed evidence is never overwritten.
    with path.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def latest_mtime(values):
    return max(Path(path).stat().st_mtime_ns for path in values)


def save_child(path, data, inputs, evidence):
    hash_checks(inputs)
    hash_checks(evidence, path.parent)
    latest = latest_mtime(inputs)
    data.update(status="PASS", completed_utc=now(), input_hashes=inputs,
                evidence_hashes=evidence, hardware_status="NOT_RUN",
                production_candidate_applied=True, production_pipeline_sha256=CANDIDATE_SHA256,
                reference_pipeline_sha256=BASE_SHA256, production_modified=False, td_run=False,
                freshness={"latest_input_mtime_ns": latest,
                           "current_inputs_and_logs_sha256_verified": True})
    write_json(path, data)
    require(path.stat().st_mtime_ns >= latest, "Child result predates an input: " + str(path))
    return {"path": str(path.resolve()), "sha256": sha(path), "status": "PASS"}


def preconditions():
    require(not OUT.exists(), "Never overwrite a previous fixed-grid mapping regression")
    hash_checks({str(path.resolve()): digest for path, digest in PINS.items()})
    require((SIM / "LICENSE.TXT").is_file(), "Missing file-based ModelSim license")
    for name in ("vlib.exe", "vlog.exe", "vsim.exe"):
        require((SIM / name).is_file(), "Missing ModelSim tool: " + name)
    require(len(PUBLIC) == 37 and len(CONTROL) == 11, "Miter monitor set changed")
    text = BENCH.read_text(encoding="utf-8-sig")
    for name in PUBLIC + CONTROL:
        require(text.count("CYCLE_MITER " + name + " cycle=") == 1, "Missing cycle comparison: " + name)
    require("if(completions!=81||checks!=374)" in text, "Lost original coverage guard")
    # Compile frozen harness bytes, not an unchecked regenerated substitute.
    return record_inputs([*PINS, Path(__file__).resolve(), ROOT / "01_rtl/secondary_top.v",
                          ROOT / "lint_full.f"])


def run_integer(inputs):
    directory = OUT / "integer"
    directory.mkdir()
    # Importing the proof module runs no main(), writes no old PROOF or cache,
    # and audits only the frozen R10 source. The production DUT is checked by RTL.
    old_bytecode = sys.dont_write_bytecode
    sys.dont_write_bytecode = True
    try:
        spec = importlib.util.spec_from_file_location("cnn_fixed_mapping_frozen_proof", PROOF)
        require(spec is not None and spec.loader is not None, "Cannot load frozen integer proof")
        proof = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(proof)
        source_audit = proof.audit_source(BASE)
        coordinates = proof.prove_coordinates()
        area = proof.prove_area()
    finally:
        sys.dont_write_bytecode = old_bytecode
    coordinate_mismatches = sum(mode["mismatches"] for axis in coordinates["axes"].values()
                                for mode in axis["modes"].values())
    require(coordinates["cases"] == 1536 and coordinate_mismatches == 0,
            "Coordinate exhaustive coverage changed")
    require(area["cases"] == 65536 and area["mismatches"] == 0, "Area exhaustive coverage changed")
    coverage = {"coordinate_cases": 1536, "area_cases": 65536,
                "coordinate_mismatches": 0, "area_mismatches": 0}
    log = directory / "exhaustive.log"
    with log.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write("PASS FIXED_GRID_EXHAUSTIVE coordinates=1536 area=65536 coordinate_mismatches=0 area_mismatches=0\n")
    result = {"scope": "Fresh frozen-width integer arithmetic loops; not RTL equivalence alone",
              "source_audit": source_audit, "coordinates": coordinates, "area": area,
              "coverage": coverage, "frozen_proof_script_sha256": sha(PROOF)}
    record = save_child(directory / "RESULTS.json", result, dict(inputs), {log.name: sha(log)})
    return record, coverage


def run_miter(inputs):
    directory = OUT / "miter"
    directory.mkdir()
    renamed = directory / "vision_pipeline_baseline.v"
    baseline = BASE.read_bytes()
    old = b"module vision_pipeline #(" 
    new = b"module vision_pipeline_baseline #(" 
    require(baseline.count(old) == 1, "Unexpected frozen baseline module declaration")
    with renamed.open("xb") as stream:
        stream.write(baseline.replace(old, new))
    bench = directory / BENCH.name
    stubs = directory / STUBS.name
    for source, target in ((BENCH, bench), (STUBS, stubs)):
        with target.open("xb") as stream:
            stream.write(source.read_bytes())
    # The actual production sources are explicitly compiled here. No copied
    # candidate is allowed to stand in for the production pipeline or kernel.
    sources = [stubs, renamed, SOURCE, KERNEL, bench]
    child_inputs = dict(inputs)
    child_inputs.update(record_inputs(sources))
    env = os.environ.copy()
    env.update(MGLS_LICENSE_FILE=str(SIM / "LICENSE.TXT"), LM_LICENSE_FILE=str(SIM / "LICENSE.TXT"))

    def run(label, args):
        log = directory / (label + ".log")
        print("START fixed-grid " + label, flush=True)
        with log.open("x", encoding="utf-8") as stream:
            proc = subprocess.run([str(arg) for arg in args], cwd=directory, env=env,
                                  stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT,
                                  timeout=600, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        output = log.read_text(errors="replace")
        require(proc.returncode == 0 and not re.search(r"\*\*\s+(?:Error|Fatal):", output),
                label + " failed; inspect " + str(log))
        print("DONE fixed-grid " + label, flush=True)
        return output

    run("vlib", [SIM / "vlib.exe", "miterlib"])
    compile_output = run("compile", [SIM / "vlog.exe", "-sv", "-lint", "-work", "miterlib", *sources])
    output = run("simulate", [SIM / "vsim.exe", "-batch", "-quiet", "-novopt", "-suppress", "12110",
        "-lib", "miterlib", "tb_cnn_stability_pipeline", "-do", "onerror {quit -code 1}; run -all; quit -f"])
    checks = [line.strip("# ") for line in output.splitlines() if "PASS" in line]
    require(checks.count("PASS ORIGINAL_81_JOBS_374_ASSERTIONS_PRESERVED") == 1,
            "Original integration coverage was not preserved")
    marker = (r"PASS FIXED_GRID_PUBLIC_CYCLE_MITER cycles=(\d+) public_ports=(\d+) controls=(\d+) "
              r"completed_jobs=(\d+) assertions=(\d+)")
    matches = [re.fullmatch(marker, line) for line in checks]
    matches = [match for match in matches if match is not None]
    require(len(matches) == 1, "Missing or duplicate cycle miter PASS marker")
    cycles, ports, controls, jobs, assertions = map(int, matches[0].groups())
    require((cycles, ports, controls, jobs, assertions) == (EXPECTED_CYCLES, 37, 11, 113, 527),
            "Reviewed fixed-grid miter coverage changed")
    require(checks.count("PASS CNN_STABILITY_PIPELINE_ALL checks=527 jobs=113") == 1,
            "Pipeline integration completion marker changed")
    require("Errors: 0, Warnings: 0" in compile_output, "Compile diagnostics changed")
    require("Errors: 0, Warnings: 1" in output, "Simulation diagnostics changed")
    coverage = dict(cycles=cycles, public_ports=ports, controls=controls, completed_jobs=jobs,
                    assertions=assertions, original_completed_jobs=81, original_assertions=374)
    result = {"scope": "Both actual pipeline/control and stabilizer FSMs; controlled CCL/CNN/DDR leaves",
              "compile_sources": [str(path.resolve()) for path in sources],
              "public_ports_compared_every_active_clock": PUBLIC,
              "controls_compared_every_active_clock": CONTROL,
              "original_formal_program_preserved": {"completed_jobs": 81, "assertions": 374},
              "coverage": coverage, "checks": checks,
              "limits": ["Two-state CCL input contract; arbitrary forced X/Z equivalence is not claimed",
                         "No end-to-end camera/DDR/HXA/UART or physical/hardware validation"]}
    evidence = {path.name: sha(path) for path in directory.glob("*.log")}
    record = save_child(directory / "RESULTS.json", result, child_inputs, evidence)
    inputs.update(child_inputs)
    return record, coverage


def main():
    started = now()
    inputs = preconditions()  # Hash mismatch fails before creating any output.
    OUT.mkdir(parents=True, exist_ok=False)
    results = {"status": "RUNNING", "scope": __doc__, "started_utc": started,
               "hardware_status": "NOT_RUN", "production_modified": False, "td_run": False,
               "production_candidate_applied": True, "production_pipeline_sha256": CANDIDATE_SHA256,
               "reference_pipeline_sha256": BASE_SHA256,
               "production_modules": ["vision_pipeline", "cnn_result_stabilizer"]}
    children, coverage, evidence = {}, {}, {}
    try:
        children["integer"], coverage["integer"] = run_integer(inputs)
        children["miter"], coverage["miter"] = run_miter(inputs)
        for record in children.values():
            path = Path(record["path"])
            require(sha(path) == record["sha256"], "Child result drift: " + str(path))
            child = json.loads(path.read_text(encoding="utf-8"))
            hash_checks(child["input_hashes"])
            hash_checks(child["evidence_hashes"], path.parent)
            require(path.stat().st_mtime_ns >= latest_mtime(child["input_hashes"]),
                    "Child result is stale: " + str(path))
            inputs[str(path.resolve())] = record["sha256"]
            for relative, digest in child["evidence_hashes"].items():
                evidence[(path.parent / relative).relative_to(OUT).as_posix()] = digest
        hash_checks(inputs)
        hash_checks(evidence, OUT)
        latest = latest_mtime(inputs)
        results.update(status="PASS", completed_utc=now(), input_hashes=inputs,
                       child_results=children, coverage=coverage, evidence_hashes=evidence,
                       active_production_inputs_unchanged_during_run=True,
                       freshness={"latest_input_mtime_ns": latest,
                                  "all_child_results_newer_than_their_inputs": True,
                                  "current_inputs_and_logs_sha256_verified": True},
                       toolchain_identity={name: sha(SIM / name) for name in ("vlib.exe", "vlog.exe", "vsim.exe")},
                       limits=["151 fewer declared datapath bits is not a measured hardware resource gain",
                               "Controlled leaves do not establish full-frame inference or board integration",
                               "No synthesis, route, timing, bit generation, or hardware validation"])
        pending = OUT / "RESULTS.pending.json"
        write_json(pending, results)
        require(pending.stat().st_mtime_ns >= latest, "Aggregate result predates its inputs")
        pending.rename(OUT / "RESULTS.json")
    except BaseException as error:
        # Failed attempts retain evidence and are never silently overwritten.
        for path in OUT.rglob("*.log"):
            evidence[path.relative_to(OUT).as_posix()] = sha(path)
        results.update(status="FAILED", completed_utc=now(), error=repr(error),
                       input_hashes=inputs, child_results=children, coverage=coverage, evidence_hashes=evidence)
        failure = OUT / ("FAILURE.json" if (OUT / "RESULTS.json").exists() else "RESULTS.json")
        write_json(failure, results)
        raise
    print("PASS CNN_FIXED_GRID_MAPPING coordinates=1536 area=65536 cycles=11742298 jobs=113 assertions=527", flush=True)


if __name__ == "__main__":
    main()
