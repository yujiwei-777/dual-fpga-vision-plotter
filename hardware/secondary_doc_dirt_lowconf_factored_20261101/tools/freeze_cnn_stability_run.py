"""Preserve exact build inputs and regression evidence outside the live RTL tree."""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def local(value):
    path = Path(value)
    path = (path if path.is_absolute() else ROOT / path).resolve()
    assert path.is_relative_to(ROOT) and "work" not in [p.lower() for p in path.parts], path
    return path


def archive(target, inputs, metadata):
    assert not target.exists(), "Archive already exists: " + str(target)
    # Validate every source before creating any output.
    for path, expected in inputs.items():
        assert path.is_file() and sha(path) == expected, "Input drift: " + str(path)
    target.mkdir()
    records = {}
    for path, expected in sorted(inputs.items(), key=lambda item: str(item[0])):
        relative = path.relative_to(ROOT)
        saved = target / relative
        saved.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, saved)
        assert sha(saved) == expected and sha(path) == expected, path
        records[relative.as_posix()] = {"sha256": expected, "bytes": saved.stat().st_size}
    payload = {**metadata, "created_utc": datetime.now(timezone.utc).isoformat(),
               "file_count": len(records), "total_bytes": sum(v["bytes"] for v in records.values()),
               "archive_tool_sha256": sha(Path(__file__)), "files": records}
    manifest = target / "ARCHIVE_MANIFEST.json"
    manifest.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    for relative, record in records.items():
        assert sha(target / relative) == record["sha256"]
    print(json.dumps({"archive": str(target), "file_count": len(records),
                      "manifest_sha256": sha(manifest), "all_hashes_verified": True}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", required=True)
    args = parser.parse_args()
    runs = local(args.runs)
    plan = read(runs / "BUILD_PLAN.json")
    snapshot = read(runs / "syn_1/source_snapshot.json")
    assert snapshot["manifest_sha256"] == plan["source_manifest_sha256"]
    build = {local(item["path"]): item["sha256"].upper() for item in snapshot["files"]}
    # Flow, plan and both snapshots are useful even after the live RTL changes.
    for relative, expected in plan["flow_sha256"].items():
        build[local(relative)] = expected
    for path in [runs / "BUILD_PLAN.json", runs / "PRE_SYN_REGRESSIONS.json",
                 runs / "syn_1/source_snapshot.json", runs / "phy_1/source_snapshot.json"]:
        build[path] = sha(path)
    archive(runs / "frozen_build_inputs", build,
            {"source_manifest_sha256": snapshot["manifest_sha256"], "kind": "BUILD_INPUTS_AND_FLOW"})
    evidence, results = {}, read(runs / "PRE_SYN_REGRESSIONS.json")
    for value, expected in results.items():
        result = local(value)
        assert sha(result) == expected
        data = read(result)
        evidence[result] = expected
        for source, digest in (data.get("input_hashes") or data.get("inputs_sha256")).items():
            path = local(source)
            assert path not in evidence or evidence[path] == digest.upper()
            evidence[path] = digest.upper()
        for relative, digest in data.get("evidence_hashes", {}).items():
            evidence[local(result.parent / relative)] = digest.upper()
    archive(runs / "frozen_regression_evidence", evidence,
            {"results_sha256": results, "kind": "CURRENT_REGRESSION_INPUTS_AND_LOGS"})


if __name__ == "__main__":
    main()
