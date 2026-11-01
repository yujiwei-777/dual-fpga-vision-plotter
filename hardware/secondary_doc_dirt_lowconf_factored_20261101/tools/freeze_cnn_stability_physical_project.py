"""Supplement physical project files omitted from the existing build archive.

Archives only phy_1/*.al, phy_1/*.prj and phy_1/source_snapshot.json, using the
R9 frozen_physical_project manifest layout. Validates the entire live physical
snapshot closure first. No existing archive, source, or build tool is modified.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def local(value):
    path = Path(value)
    path = (path if path.is_absolute() else ROOT / path).resolve()
    require(path.is_relative_to(ROOT), "Path outside project: " + str(path))
    require("work" not in [part.lower() for part in path.parts], "Protected work path: " + str(path))
    return path


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def verify_file(path, expected):
    require(path.is_file(), "Missing source: " + str(path))
    require(sha(path) == expected, "Input drift: " + str(path))


def verified_snapshot(runs):
    physical = local(runs / "phy_1")
    require(physical.parent == runs, "Physical run resolves outside the requested runs directory")
    snapshot_path = physical / "source_snapshot.json"
    require(snapshot_path.is_file(), "Missing physical source snapshot: " + str(snapshot_path))
    snapshot_sha = sha(snapshot_path)
    snapshot = read_json(snapshot_path)
    require(snapshot.get("passed") is True and not snapshot.get("errors"), "Physical snapshot did not pass")
    require(local(snapshot["project_root"]) == ROOT, "Snapshot project root differs")
    require(local(snapshot["run"]) == physical, "Snapshot physical run differs")
    files = snapshot["files"]
    require(isinstance(files, list) and bool(files), "Empty snapshot source list")
    ordered = sorted(files, key=lambda item: item["path"].lower())
    canonical = [{key: item[key] for key in ("path", "kind", "sha256")} for item in ordered]
    digest = hashlib.sha256(json.dumps(canonical, sort_keys=True).encode()).hexdigest().upper()
    require(digest == snapshot["manifest_sha256"], "Physical source manifest digest differs")
    inputs = {}
    for item in files:
        path = local(item["path"])
        expected = item["sha256"].upper()
        require(re.fullmatch(r"[0-9A-F]{64}", expected), "Invalid source SHA256: " + str(path))
        require(path not in inputs, "Duplicate snapshot source: " + str(path))
        verify_file(path, expected)
        inputs[path] = expected
    active_al = local(snapshot["al"])
    require(active_al.parent == physical and active_al.suffix.lower() == ".al", "Active project is not phy_1/*.al")
    require(active_al in inputs, "Active physical project is absent from snapshot")
    verify_file(snapshot_path, snapshot_sha)
    return physical, snapshot_path, snapshot_sha, snapshot, inputs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", required=True, help="Project-relative or absolute run directory")
    args = parser.parse_args()
    runs = local(args.runs)
    require(runs.is_dir(), "Missing runs directory: " + str(runs))
    target_path = runs / "frozen_physical_project"
    require(not target_path.exists() and not target_path.is_symlink(), "Archive already exists: " + str(target_path))
    target = local(target_path)
    require(target.parent == runs, "Archive resolves outside the requested runs directory")
    physical, snapshot_path, snapshot_sha, snapshot, inputs = verified_snapshot(runs)
    projects = sorted((path for path in physical.iterdir()
                       if path.is_file() and path.suffix.lower() in {".al", ".prj"}),
                      key=lambda path: path.name.lower())
    require(any(path.suffix.lower() == ".al" for path in projects), "No physical .al project found")
    selected = {snapshot_path: snapshot_sha}
    verification = {}
    for value in projects:
        path = local(value)
        require(path.parent == physical, "Project resolves outside phy_1: " + str(path))
        if path in inputs:
            expected = inputs[path]
            provenance = {"kind": "physical_snapshot_entry", "path": str(path)}
        else:
            # TD also saves a .prj mirror; older snapshots record only .al.
            # Never invent a frozen identity for an unmatched project file.
            require(path.suffix.lower() == ".prj", "Unfrozen physical project: " + str(path))
            sibling = local(path.with_suffix(".al"))
            require(sibling in inputs, "PRJ has no snapshot-bound AL: " + str(path))
            expected = inputs[sibling]
            verify_file(sibling, expected)
            provenance = {"kind": "byte_identical_snapshot_bound_al", "path": str(sibling)}
        verify_file(path, expected)
        selected[path] = expected
        verification[path.name] = provenance
    # All sources and project identities have passed before any output exists.
    for path, expected in inputs.items():
        verify_file(path, expected)
    verify_file(snapshot_path, snapshot_sha)
    target.mkdir(exist_ok=False)
    records = []
    for path, expected in sorted(selected.items(), key=lambda item: item[0].name.lower()):
        saved = target / path.name
        with path.open("rb") as source, saved.open("xb") as destination:
            shutil.copyfileobj(source, destination)
        verify_file(saved, expected)
        verify_file(path, expected)
        records.append({"source": str(path), "archive": path.name, "sha256": expected,
                        "bytes": saved.stat().st_size})
    for path, expected in inputs.items():
        verify_file(path, expected)
    verify_file(snapshot_path, snapshot_sha)
    payload = {"status": "PASS", "created_utc": datetime.now(timezone.utc).isoformat(),
        "purpose": "Supplement physical-project identity not duplicated in frozen_build_inputs; existing archives remain immutable.",
        "physical_source_manifest_sha256": snapshot["manifest_sha256"],
        "files": records, "hardware_status": "NOT_RUN",
        "archive_tool_sha256": sha(Path(__file__)), "physical_snapshot_sha256": snapshot_sha,
        "verified_source_file_count": len(inputs), "project_verification": verification}
    manifest = target / "ARCHIVE_MANIFEST.json"
    with manifest.open("x", encoding="utf-8") as stream:
        stream.write(json.dumps(payload, indent=2) + "\n")
    for record in records:
        verify_file(target / record["archive"], record["sha256"])
    print(json.dumps({"status": "PASS", "archive": str(target), "file_count": len(records),
        "verified_source_file_count": len(inputs), "manifest_sha256": sha(manifest),
        "all_hashes_verified": True}))


if __name__ == "__main__":
    main()
