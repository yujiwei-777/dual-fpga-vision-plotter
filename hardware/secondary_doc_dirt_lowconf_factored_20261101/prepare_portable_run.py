#!/usr/bin/env python3
"""Prepare isolated TD synthesis/route inputs; never execute TD or generate a bit.

Distribution placement: secondary package root as prepare_portable_run.py.
The original package is verified BEFORE preparation. Generated run directories
are outside the sealed inventory and require a new release acceptance audit.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys


PROJECT = "secondary_cnn_multibox"
EVIDENCE = Path("artifacts/evidence/final_build")
PHASES = {"syn_1": ("read_design", "opt_gate"), "phy_1": ("opt_place", "opt_route")}
DRIVE = re.compile(r"(?i)(?<![A-Za-z0-9_])[a-z]:[/\\]")
SOURCES = re.compile(r'(?:^|[;{}])\s*source\s+(?:\{([^{}]+)\}|"([^"]+)"|([^\s;}]+))', re.M)
RUN_NAME = re.compile(r"[A-Za-z][A-Za-z0-9_.-]{0,63}\Z")
RESERVED = {"CON", "PRN", "AUX", "NUL"} | {f"{p}{n}" for p in ("COM", "LPT") for n in range(1, 10)}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def checked_path(root: Path, path: Path, *, must_exist: bool = True) -> Path:
    """Reject traversal and every symlink/junction component, including files."""
    path = Path(os.path.abspath(path))
    if not path.is_relative_to(root):
        raise ValueError(f"Path escapes the package: {path}")
    current = root
    for part in ((), *[(p,) for p in path.relative_to(root).parts]):
        if part:
            current = current / part[0]
        if current.exists() or current.is_symlink():
            info = current.lstat()
            if stat.S_ISLNK(info.st_mode) or getattr(info, "st_file_attributes", 0) & 0x400:
                raise ValueError(f"Symlink/junction/reparse point is forbidden: {current}")
        elif must_exist:
            raise FileNotFoundError(current)
    return path


def read_checked(root: Path, path: Path) -> bytes:
    path = checked_path(root, path)
    if not path.is_file():
        raise ValueError(f"Expected a regular file: {path}")
    return path.read_bytes()


def text_checked(root: Path, path: Path) -> str:
    return read_checked(root, path).decode("utf-8-sig")


def portable_text(text: str, label: str) -> None:
    if DRIVE.search(text) or "\\\\" in text:
        raise ValueError(f"Old drive/UNC path in active Tcl/configuration: {label}")


def map_snapshot_path(root: Path, original_root: str, original: str) -> Path:
    base = original_root.replace("\\", "/").rstrip("/")
    value = original.replace("\\", "/")
    if not value.lower().startswith(base.lower() + "/"):
        raise ValueError(f"Frozen dependency is outside the original project: {original}")
    return checked_path(root, root / value[len(base) + 1 :])


def verify_memories_and_includes(root: Path, snapshot: dict) -> int:
    original_root = snapshot["project_root"]
    frozen = {v["path"].replace("\\", "/").lower(): v for v in snapshot["files"]}
    references = snapshot["memory_references"]
    if not references:
        raise ValueError("No frozen memory dependency evidence was found")
    checked = set()
    for entry in references:
        if entry.get("status") != "present" or not entry.get("resolved"):
            raise ValueError(f"Unresolved frozen ROM dependency: {entry}")
        for original in entry["resolved"]:
            path = map_snapshot_path(root, original_root, original)
            item = frozen.get(original.replace("\\", "/").lower())
            if item is None or sha256(path) != item["sha256"].upper():
                raise ValueError(f"Frozen memory hash mismatch: {path}")
            checked.add(str(path))
    for item in snapshot["files"]:
        if item.get("kind") == "include":
            path = map_snapshot_path(root, original_root, item["path"])
            if sha256(path) != item["sha256"].upper():
                raise ValueError(f"Frozen include hash mismatch: {path}")
    return len(checked)


def verify_hooks(root: Path, text: str, run_dir: Path, seen: set[Path]) -> list[str]:
    hooks = []
    # Sources inside run Tcl are literal. One frozen SCLK hook deliberately
    # derives its parent's original hook from [info script]; validate that exact
    # known construction without evaluating Tcl.
    active = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
    for match in SOURCES.finditer(active):
        token = next(value for value in match.groups() if value is not None)
        if token == "./settings.cfg":
            continue
        if token == "$secondary_key3_sclk_base":
            expected = "set secondary_key3_sclk_base [file join [file dirname [file dirname [file normalize [info script]]]] prove_key3_supervisor_clocktrace.tcl]"
            if expected not in text or run_dir.name != "clocktrace_sclk":
                raise ValueError("Unrecognized dynamic SCLK source construction")
            path = run_dir.parent / "prove_key3_supervisor_clocktrace.tcl"
        else:
            if "$" in token or "[" in token or DRIVE.search(token) or Path(token).is_absolute():
                raise ValueError(f"Unverified Tcl source expression: {token}")
            path = run_dir / token
        path = checked_path(root, path)
        hooks.append(path.relative_to(root).as_posix())
        if path not in seen:
            seen.add(path)
            child = text_checked(root, path)
            portable_text(child, str(path))
            hooks.extend(verify_hooks(root, child, path.parent, seen))
    return hooks


def validate_runs_name(name: str) -> None:
    if not RUN_NAME.fullmatch(name) or name.endswith(".") or name.split(".")[0].upper() in RESERVED:
        raise ValueError("--runs must be one new directory name, without paths, spaces, or reserved names")


def prepare(root: Path, runs_name: str) -> dict:
    root = Path(os.path.abspath(root))
    checked_path(root, root)
    if root.resolve() != root:
        raise ValueError(f"A package reached through a symlink/junction is forbidden: {root}")
    validate_runs_name(runs_name)
    target = checked_path(root, root / runs_name, must_exist=False)
    if target.exists() or target.is_symlink():
        raise FileExistsError(f"Refusing an existing run directory: {target}")

    verifier = checked_path(root, root / "verify_package.py")
    result = subprocess.run([sys.executable, str(verifier)], cwd=root, capture_output=True, text=True)
    if result.stdout:
        print(result.stdout, end="" if result.stdout.endswith("\n") else "\n")
    if result.returncode:
        raise RuntimeError(f"Original sealed-package verification failed:\n{result.stderr}")

    prepared: dict[str, dict] = {}
    for phase, (start, end) in PHASES.items():
        source = root / EVIDENCE / phase
        run_dir = target / phase
        original_al = text_checked(root, source / f"{PROJECT}.al.original.txt")
        al, replacements = re.subn(r'(<Project\b[^>]*\bPath=")[^"]*(")', r'\g<1>.\g<2>', original_al)
        if replacements != 1:
            raise ValueError(f"Expected one Project Path attribute: {phase}")
        references = re.findall(r'<File\s+Path="([^"]+)"', al)
        if not references:
            raise ValueError(f"No active project inputs: {phase}")
        for reference in references:
            reference = html.unescape(reference)
            if DRIVE.search(reference) or Path(reference).is_absolute():
                raise ValueError(f"Absolute active project reference: {reference}")
            checked_path(root, run_dir / reference)
        tcl = read_checked(root, source / "run.tcl")
        cfg = read_checked(root, source / "settings.cfg")
        for label, data in (("run.tcl", tcl), ("settings.cfg", cfg)):
            text = data.decode("utf-8-sig")
            portable_text(text, f"{phase}/{label}")
            for key, value in (("start_step", start), ("end_step", end)):
                values = re.findall(rf"(?m)^set\s+{key}\s+(\S+)\s*$", text)
                if values != [value]:
                    raise ValueError(f"Unexpected {phase}/{label} {key}: {values}")
        hooks = sorted(set(verify_hooks(root, tcl.decode("utf-8-sig"), run_dir, set())))
        snapshot = json.loads(text_checked(root, source / "source_snapshot.json"))
        memories = verify_memories_and_includes(root, snapshot)
        prepared[phase] = {"al": al.encode("utf-8"), "tcl": tcl, "cfg": cfg,
                           "references": len(references), "hooks": hooks, "memories": memories}

    # All preflight checks finish before creating a single output directory.
    target.mkdir()
    output_hashes = {}
    for phase, values in prepared.items():
        directory = target / phase
        directory.mkdir()
        for name, data in ((f"{PROJECT}.al", values["al"]), (f"{PROJECT}.prj", values["al"]),
                           ("run.tcl", values["tcl"]), ("settings.cfg", values["cfg"])):
            output = directory / name
            output.write_bytes(data)
            output_hashes[output.relative_to(target).as_posix()] = sha256(output)
    manifest = {
        "status": "PREPARATION_ONLY_NO_TD_EXECUTED",
        "release_status": "REBUILD_REQUIRES_NEW_RELEASE_ACCEPTANCE",
        "original_sealed_package_verified_before_preparation": True,
        "td_executed": False, "bit_generated": False,
        "original_inventory_scope": "Only files sealed before preparation; generated run directory is not an original release artifact",
        "prepared_runs": {phase: {k: v for k, v in values.items() if k not in ("al", "tcl", "cfg")}
                          for phase, values in prepared.items()},
        "sha256": output_hashes,
    }
    (target / "PREPARATION_ONLY.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (target / "README_PREPARED.md").write_text(
        "# Prepared inputs only\n\n"
        "No synthesis, placement, routing, hardware programming, or bitgen has run.\n"
        "The original package passed verification before these outputs were created. "
        "This directory is outside the original sealed file inventory; that inventory does not certify a rebuild.\n\n"
        "In the vendor TD shell, change the working directory to syn_1 and source run.tcl; "
        "only after synthesis succeeds, use phy_1 and source its run.tcl. "
        "The preserved flows stop at opt_gate and opt_route respectively. "
        "run_bitgen.tcl is deliberately absent. Never use an old database or an old bitgen gate to accept a rebuild.\n\n"
        "Any rebuilt design requires new lint/simulation, timing/resource, CDC/FIFO/DDR/DRC, "
        "read-only reimport and release acceptance before separate authorized bit generation. "
        "RTL, constraints, models, frozen builders and archived evidence remain unchanged.\n",
        encoding="utf-8",
    )
    print(f"Prepared only: {target}")
    print("No TD was executed. No bit was generated. A rebuild needs new release acceptance.")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Prepare portable synthesis-through-route inputs only; does NOT execute TD or generate a bit.",
        epilog="Run from an intact extracted package. New outputs require a new release audit; original package verification covers only original sealed files.",
    )
    parser.add_argument("--runs", default="portable_Runs", help="One new directory name under the package root (default: portable_Runs); existing directories are refused")
    args = parser.parse_args()
    try:
        prepare(Path(__file__).absolute().parent, args.runs)
    except (OSError, ValueError, KeyError, RuntimeError) as exc:
        parser.exit(1, f"PREPARATION FAILED: {exc}\n")


if __name__ == "__main__":
    main()
