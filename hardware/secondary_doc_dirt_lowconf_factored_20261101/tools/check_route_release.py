"""Fail closed unless the completed TD route meets the UART candidate gates."""
import argparse
import hashlib
import json
import re
from pathlib import Path


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check(run):
    name = "secondary_edge_bypass"
    timing_path = run / f"{name}_pr.timing"
    area_path = run / f"{name}_phy.area"
    timing = timing_path.read_text(errors="replace")
    area = area_path.read_text(errors="replace")
    status = (run / "route_flow.status").read_text(errors="replace")
    loaded = (run / "secondary_loaded_route_end.rpt").read_text()
    console = (run / "build_console.log").read_text(errors="replace")
    errors = []
    metrics = {}
    for key in ("SWNS", "STNS", "HWNS", "HTNS"):
        match = re.search(rf"\b{key}:\s*(-?[\d.]+)ns", timing)
        if not match:
            errors.append(f"Missing final {key}")
            continue
        value = float(match[1])
        metrics[key] = value
        if (key.endswith("TNS") and value != 0) or value < 0:
            errors.append(f"{key}={value} ns")
    resources = {}
    for resource, limit in (("slice", 95), ("eram", 90), ("dsp", 95)):
        match = re.search(rf"^#{resource}\s+(\d+)\s+out of\s+(\d+)\s+([\d.]+)%", area, re.M)
        if not match:
            errors.append(f"Missing {resource} utilization")
            continue
        used, total = int(match[1]), int(match[2])
        percent = used * 100.0 / total
        resources[resource] = {"used": used, "total": total, "percent": percent, "limit": limit}
        if used <= 0 or percent > limit:
            errors.append(f"{resource} utilization {percent:.2f}%")
    for description, passed in (
        ("route completed", (run / ".opt_route.end.f").is_file()),
        ("routed timing", bool(re.search(r"Confidence\s*:\s*Routed", timing))),
        ("both corners", "Both (Slow and Fast)" in timing),
        ("final timing mode", bool(re.search(r"Timing Mode\s*:\s*final", status))),
        ("persistent exact CDC constraints", "EFFECTIVE_SMD_PATHS 290 128 9 52" in loaded),
        ("post-route database", (run / f"{name}_pr.db").is_file()),
        ("no flow/mapping errors", not re.search(r"BUILD_FAILED|MAPPING_ERROR|[A-Z]+-\d+ ERROR", console)),
    ):
        if not passed:
            errors.append(description)
    files = [timing_path, area_path, run / "route_flow.status", run / "secondary_loaded_route_end.rpt",
             run / "secondary_exact_route_end.sdc", run / f"{name}_pr.db"]
    result = {"passed": not errors, "run": str(run), "timing_ns": metrics,
              "resources": resources, "failures": errors,
              "sha256": {p.name: sha256(p) for p in files if p.is_file()},
              "hardware_validation": "not performed; build acceptance only"}
    (run / "release_gate.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({k: v for k, v in result.items() if k != "sha256"}, indent=2))
    return result["passed"]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run", type=Path)
    args = parser.parse_args()
    raise SystemExit(0 if check(args.run.resolve()) else 1)
