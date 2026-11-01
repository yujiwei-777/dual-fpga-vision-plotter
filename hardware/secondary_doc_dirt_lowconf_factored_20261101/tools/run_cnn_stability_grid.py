"""Verify promoted production COORD_SHIFT=3 against the frozen pre-grid kernel.

This runner never promotes or rewrites RTL. Before promotion it refuses to run.
It creates only a fresh 02_sim/cnn_stability_grid tree, runs three independent
helpers, checks exact coverage and all input/evidence hashes, and publishes one
RESULTS.json consumable by the existing regression_gate. There is no hardware
build or accuracy claim in this regression.
"""
from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import subprocess
import sys

from cnn_stability_grid_common import BASE, BASE_SHA256, OUT, REVIEW, ROOT, SOURCE, preconditions, require, sha

HELPERS = {
    "equivalence": ROOT / "tools/run_cnn_stability_grid_equivalence.py",
    "lifecycle": ROOT / "tools/run_cnn_stability_grid_lifecycle.py",
    "transfer": ROOT / "tools/run_cnn_stability_grid_transfer.py",
}
PARAMS = {(1, 0, 1), (2, 1, 2), (3, 2, 3), (4, 0, 4), (15, 15, 15)}


def now():
    return datetime.now(timezone.utc).isoformat()


def hash_checks(values, parent=ROOT):
    checked = {}
    for name, expected in values.items():
        path = Path(name)
        if not path.is_absolute():
            path = parent / path
        path = path.resolve()
        require(path.is_relative_to(ROOT.resolve()), "Test evidence escapes independent project: " + str(path))
        require(path.is_file() and sha(path) == str(expected).upper(), "Test input/evidence drift: " + str(path))
        checked[str(path)] = str(expected).upper()
    return checked


def load_child(name):
    path = OUT / name / "RESULTS.json"
    require(path.is_file(), "Missing child result: " + str(path))
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    require(data.get("status") == "PASS", name + " did not pass")
    require(data.get("coord_shift") == 3 and data.get("production_candidate_applied") is True,
            name + " did not verify the production grid candidate")
    inputs = hash_checks(data.get("input_hashes", {}))
    require(str(SOURCE.resolve()) in inputs and str(BASE.resolve()) in inputs,
            name + " lacks production/baseline input identity")
    require(inputs[str(BASE.resolve())] == BASE_SHA256, name + " used a different baseline")
    require(inputs[str(SOURCE.resolve())] == sha(SOURCE), name + " did not compile the current production kernel")
    require(bool(data.get("evidence_hashes")), name + " lacks simulator log hashes")
    evidence = hash_checks(data["evidence_hashes"], path.parent)
    require(path.stat().st_mtime_ns >= max(Path(item).stat().st_mtime_ns for item in inputs),
            name + " result predates one of its current inputs")
    return data, inputs, evidence


def validate_equivalence(data):
    require(data.get("parameter_modes") == 20 and len(data.get("checks", [])) == 20,
            "Grid miter must cover all 20 parameter configurations")
    require(data.get("real_frames") == 1170 and data.get("vectors") == 2869,
            "Grid miter replay/vector coverage changed")
    require(data.get("groups", {}).get("explicit_nonaligned_rejection") == 216,
            "Explicit nonaligned rejection cases were lost")
    modes, parsed = set(), []
    pattern = (r"PASS GRID_COORDINATE_EQUIVALENCE area_bits=(\d+) external=(\d+) params=(\d+)/(\d+)/(\d+) "
               r"vectors=(\d+) jobs=(\d+) rejected=(\d+) cycle_checks=(\d+) serial=(\d+) bank_reuses=(\d+)")
    for line in data["checks"]:
        match = re.fullmatch(pattern, line)
        require(match is not None, "Malformed grid miter PASS marker")
        a, e, c, h, lost, vectors, jobs, rejected, cycles, serial, reuse = map(int, match.groups())
        mode = (a, e, c, h, lost)
        require(mode not in modes, "Duplicate grid miter parameter mode")
        modes.add(mode)
        require(vectors == 2869 and jobs == 2610 and rejected == 216,
                "Grid miter lost public-equivalence or nonaligned rejection transactions")
        require(cycles > 0 and serial > 0 and reuse == jobs,
                "Grid miter lost destructive raw-bank reuse or serialized output checks")
        parsed.append(dict(area_bits=a, external_reader=e, confirm=c, hold=h, lost=lost,
                           vectors=vectors, equivalent_jobs=jobs, explicit_nonaligned_rejections=rejected,
                           cycle_checks=cycles, serial_checks=serial, destructive_bank_reuses=reuse))
    expected = {(a, e, *p) for a in (24, 32) for e in (0, 1) for p in PARAMS}
    require(modes == expected, "Grid miter configuration coverage differs from the reviewed 20 modes")
    return {"parameter_modes": 20, "unique_input_events": 2869, "existing_replay_observations": 1170,
            "equivalent_jobs_per_mode": 2610, "nonaligned_rejections_per_mode": 216, "modes": parsed}


def validate_lifecycle(data):
    tests = data.get("tests", [])
    require(len(tests) == 6, "Lifecycle requires two payload and four metadata modes")
    by_name = {row["test"]: row for row in tests}
    require(len(by_name) == 6, "Duplicate lifecycle test mode")
    total = 0
    for area in (24, 32):
        payload = by_name.get(f"payload{area}", {}).get("checks", [])
        require(len(payload) == 1 and re.fullmatch(r"PASS WIDE_RAM_ATOMIC checks=10 aborts=5", payload[0]) is not None,
                f"Payload atomic coverage changed for AREA_BITS={area}")
        total += 5
        for external in (0, 1):
            label = f"metadata{'_external' if external else ''}{area}"
            checks = by_name.get(label, {}).get("checks", [])
            require(len(checks) == 1, "Missing metadata marker: " + label)
            match = re.fullmatch(r"PASS METADATA_ATOMIC area_bits=(\d+) boundaries=(\d+) fresh_checks=(\d+) "
                                 r"publications=(\d+) max_latency_cycles=(\d+) external_reader=(\d+)", checks[0])
            require(match is not None, "Malformed metadata lifecycle PASS marker")
            a, boundaries, fresh, publications, latency, e = map(int, match.groups())
            require((a, e, boundaries) == (area, external, 24), "Metadata abort boundary coverage changed")
            require(fresh == 147 and publications == 196 and latency > 0, "Metadata fresh-history checks changed")
            total += boundaries
    require(total == 106, "Lifecycle did not cover exactly 106 reviewed atomic abort boundaries")
    return {"atomic_abort_boundaries": total, "payload_modes": 2, "metadata_modes": 4,
            "stale_payload_metadata_isolation": True, "held_clear_and_reset": True}


def validate_transfer(data):
    require(data.get("parameter_modes") == 4 and len(data.get("checks", [])) == 4,
            "Transfer regression must cover AREA24/32 times reader0/1")
    require(data.get("boundaries_per_mode") == 16 and len(data.get("targets", [])) == 8,
            "Transfer regression lost pre/post ownership-transfer targets")
    require(data.get("abort_types") == ["held synchronous clear", "held processing reset"],
            "Transfer clear/reset coverage changed")
    modes, parsed = set(), []
    pattern = (r"PASS GRID_TRANSFER_EQUIVALENCE area_bits=(\d+) external=(\d+) boundaries=(\d+) "
               r"fresh_frames=(\d+) cycle_checks=(\d+) serial=(\d+) bank_reuses=(\d+)")
    for line in data["checks"]:
        match = re.fullmatch(pattern, line)
        require(match is not None, "Malformed transfer PASS marker")
        a, e, boundaries, fresh, cycles, serial, reuse = map(int, match.groups())
        require((a, e) not in modes, "Duplicate transfer mode")
        modes.add((a, e))
        require(boundaries == 16 and fresh == 96 and cycles > 0 and serial > 0 and reuse > 0,
                "Transfer regression lost abort, fresh-confirmation, serial or destructive-bank checks")
        parsed.append(dict(area_bits=a, external_reader=e, abort_boundaries=boundaries,
                           fresh_confirmation_frames=fresh, cycle_checks=cycles,
                           serial_checks=serial, destructive_bank_reuses=reuse))
    require(modes == {(a, e) for a in (24, 32) for e in (0, 1)}, "Missing transfer configuration")
    return {"parameter_modes": 4, "abort_boundaries_per_mode": 16, "total_mode_boundaries": 64,
            "fresh_confirmation_frames_per_mode": 96, "modes": parsed}


def main():
    started = now()
    initial = preconditions()  # Fails before creating output while production is pre-grid.
    require(not OUT.exists(), "Never overwrite an earlier production grid regression")
    production = [ROOT / path for path in ("01_rtl/cnn_result_stabilizer.v", "01_rtl/vision_pipeline.v",
                  "01_rtl/secondary_top.v", "01_rtl/edge_roi_ccl.v", "01_rtl/vision_ccl.v")]
    derivation = [REVIEW / ("run_grid_" + name + ".py") for name in HELPERS]
    drivers = [Path(__file__).resolve(), ROOT / "tools/cnn_stability_grid_common.py", *HELPERS.values()]
    before = {str(path.resolve()): sha(path) for path in [*production, BASE, *drivers, *derivation]}
    before.update(initial)
    OUT.mkdir(parents=True, exist_ok=False)
    results = {"status": "RUNNING", "started_utc": started, "hardware_status": "NOT_RUN",
               "production_candidate_applied": True, "coord_shift": 3,
               "production_modules": ["cnn_result_stabilizer"], "production_modified": False,
               "scope": __doc__, "input_hashes": before}
    evidence, child_records, coverages = {}, {}, {}
    validators = {"equivalence": validate_equivalence, "lifecycle": validate_lifecycle, "transfer": validate_transfer}
    try:
        for name, driver in HELPERS.items():
            log_path = OUT / f"{name}_driver.log"
            with log_path.open("x", encoding="utf-8") as stream:
                proc = subprocess.run([sys.executable, str(driver)], cwd=ROOT,
                                      stdin=subprocess.DEVNULL, stdout=stream, stderr=subprocess.STDOUT,
                                      creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0), timeout=7200)
            evidence[log_path.relative_to(OUT).as_posix()] = sha(log_path)
            require(proc.returncode == 0, f"{name} helper failed; inspect {log_path}")
            child, inputs, logs = load_child(name)
            coverages[name] = validators[name](child)
            for path, digest in inputs.items():
                require(path not in before or before[path] == digest, "Conflicting child input identity: " + path)
                before[path] = digest
            child_path = OUT / name / "RESULTS.json"
            before[str(child_path.resolve())] = sha(child_path)
            child_records[name] = {"path": str(child_path), "sha256": sha(child_path), "status": "PASS"}
            for path, digest in logs.items():
                evidence[Path(path).relative_to(OUT).as_posix()] = digest
            # VECTOR_SCOPE describes the generated input set; freeze it too.
            scope = OUT / name / "VECTOR_SCOPE.json"
            if scope.exists():
                before[str(scope.resolve())] = sha(scope)
            print(f"PASS production grid {name}", flush=True)
        hash_checks(before)
        hash_checks(evidence, OUT)
        latest = max(Path(path).stat().st_mtime_ns for path in before)
        results.update(status="PASS", completed_utc=now(), input_hashes=before,
                       child_results=child_records, coverage=coverages,
                       evidence_hashes=evidence, active_production_inputs_unchanged_during_run=True,
                       freshness={"latest_input_mtime_ns": latest, "all_child_results_newer_than_inputs": True,
                                  "current_inputs_and_logs_sha256_verified": True},
                       limits=["1170 replay observations overlap existing training/development data; no independent accuracy claim.",
                               "20 parameter configurations reuse the same vectors and are not 20 independent datasets.",
                               "The production kernel is compiled directly with COORD_SHIFT=3; full pipeline/top integration is a separate suite.",
                               "Only ordinary-CNN raw endpoint grid is covered; PCB/general coordinates must retain their original contract.",
                               "No synthesis, route, full camera/DDR/HXA/UART transaction or hardware validation is claimed."])
    except BaseException as error:
        for log_path in OUT.glob("*_driver.log"):
            evidence[log_path.relative_to(OUT).as_posix()] = sha(log_path)
        for name in HELPERS:
            for log_path in (OUT / name).glob("*.log"):
                evidence[log_path.relative_to(OUT).as_posix()] = sha(log_path)
        results.update(status="FAILED", completed_utc=now(), error=repr(error),
                       child_results=child_records, coverage=coverages, evidence_hashes=evidence,
                       input_hashes=before)
        (OUT / "RESULTS.json").write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        raise
    path = OUT / "RESULTS.json"
    path.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if path.stat().st_mtime_ns < latest:
        results.update(status="FAILED", error="Aggregate result predates current input evidence")
        results["freshness"]["current_inputs_and_logs_sha256_verified"] = False
        path.write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        raise RuntimeError(results["error"])
    print("PASS CNN_STABILITY_GRID modes=20 lifecycle_boundaries=106 transfer_modes=4 COORD_SHIFT=3", flush=True)


if __name__ == "__main__":
    main()
