"""Clock-trace proof adapter for the frozen KEY3/stroke release builder.

The original builder, source scope, regression suites and physical/bitgen gates
are reused unchanged.  Both the historical hook and this supplementary hook
remain explicit snapshot dependencies.  An unreviewed supplementary hook is
never eligible for prepare or for validation of an existing run.
"""
from __future__ import annotations

from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

import build_key3_stroke_release as base

flow = base.flow
ROOT = base.ROOT
RUNS = "cnn_key3_stroke_clockproof_Runs_20261031"
STEM = base.STEM
CLOCKTRACE_HOOK = "04_pin/prove_key3_supervisor_clocktrace.tcl"
# Actual TD gate/physical supervisor proof and 143 positive/negative source
# trace cases bind this digest. It changes no production RTL or timing budget.
CLOCKTRACE_HOOK_SHA256: str | None = "EDC066683001510C7159AC7351348C209FFD556570F3C66CE40DD6735E834A34"
PHASES = ("gate", "place_begin", "place_end", "route_begin", "route_end")
SNAPSHOT_EXTRAS = (
    "tools/build_key3_stroke_release.py",
    "tools/build_key3_stroke_release_v2.py",
    "04_pin/prove_key3_supervisor.tcl",
    CLOCKTRACE_HOOK,
)
EXTRAS = tuple(dict.fromkeys((*base.EXTRAS, *SNAPSHOT_EXTRAS)))

_original_active_scope_check = base.active_scope_check
_original_prepare = base.prepare


def supplementary_scope_check(snapshot=None):
    """Require the reviewed hook and explicitly sealed builder/hook inputs."""
    digest = CLOCKTRACE_HOOK_SHA256
    flow.require(isinstance(digest, str) and
                 re.fullmatch(r"[0-9A-F]{64}", digest) is not None,
                 "Clock-trace hook SHA256 has not been reviewed and pinned")
    hook = flow.local(CLOCKTRACE_HOOK)
    flow.require(hook.is_file() and flow.sha(hook) == digest,
                 "Reviewed clock-trace hook missing or changed")
    dependencies = {}
    for relative in SNAPSHOT_EXTRAS:
        path = flow.local(relative)
        flow.require(path.is_file(), "Supplementary build input missing: " + relative)
        dependencies[relative] = flow.sha(path)

    result = {
        "status": "PASS_REVIEWED_CLOCKTRACE_SOURCE_ONLY",
        "hook": CLOCKTRACE_HOOK,
        "hook_sha256": digest,
        "explicit_dependencies": dependencies,
        "snapshot_scope": "NOT_SUPPLIED_PREPARE_ONLY",
        "physical_acceptance": "NOT_GRANTED_REQUIRES_CURRENT_DATABASE_PROOFS",
    }
    if snapshot is not None:
        snapshot = flow.load(snapshot) if isinstance(snapshot, (str, Path)) else snapshot
        flow.require(snapshot.get("passed") is True and not snapshot.get("errors"),
                     "Supplementary snapshot did not pass")
        flow.require(Path(snapshot["project_root"]).resolve() == ROOT.resolve(),
                     "Supplementary snapshot belongs to another project")
        selected = {relative: [] for relative in SNAPSHOT_EXTRAS}
        for item in snapshot["files"]:
            path = flow.local(item["path"])
            relative = path.relative_to(ROOT.resolve()).as_posix()
            if relative in selected:
                selected[relative].append(item)
        for relative, entries in selected.items():
            flow.require(len(entries) == 1,
                         "Supplementary input must be frozen exactly once: " + relative)
            flow.require(entries[0]["kind"] == "explicit_dependency",
                         "Supplementary input must use --extra: " + relative)
            flow.require(entries[0]["sha256"].upper() == dependencies[relative],
                         "Supplementary frozen input SHA256 differs: " + relative)
        result["snapshot_scope"] = "PASS_EXPLICIT_BUILDERS_AND_BOTH_PROOF_HOOKS"
        result["source_manifest_sha256"] = snapshot["manifest_sha256"]
    return result


def active_scope_check(snapshot, baseline):
    # This call retains the old approved SHA, reset/CDC dependencies, complete
    # source/model/IP closure, and the old canonical snapshot digest checks.
    result = _original_active_scope_check(snapshot, baseline)
    return {**result, "clocktrace_supplement": supplementary_scope_check(snapshot)}


def instrument_key3(text, gen, directory):
    flow.require("secondary_prove_key3_supervisor " not in text,
                 "Refusing duplicate KEY3 proof instrumentation")
    pattern = (r"(?m)^([ \t]*)secondary_apply_phase_timing "
               r"(gate|place_begin|place_end|route_begin|route_end) [^\r\n]+$")
    matches = list(re.finditer(pattern, text))
    flow.require(tuple(match[2] for match in matches) == PHASES,
                 "Expected exactly one of each of the five ordered phase proof points")
    hook = gen.rel(ROOT / CLOCKTRACE_HOOK, directory)

    def replacement(match):
        indent, phase = match[1], match[2]
        # Preserve a mapped database even if a later timing/proof check fails.
        checkpoint = (indent + "export_db ${prj_name}_mapped_before_proof.db\n"
                      if phase == "gate" else "")
        return (checkpoint + match[0] + "\n" + indent + "source {" + hook + "}\n" +
                indent + "secondary_prove_key3_supervisor " + phase)

    return re.sub(pattern, replacement, text)


def prepare(args, runs):
    # Verify the reviewed SHA before the old prepare can create any run files.
    supplement = supplementary_scope_check()
    _original_prepare(args, runs)
    baseline = flow.baseline_check()
    snapshots = {}
    for phase in ("syn_1", "phy_1"):
        path = runs / phase / "source_snapshot.json"
        snapshot = flow.load(path)
        flow.require(Path(snapshot["run"]).resolve() == (runs / phase).resolve(),
                     "Clock-trace snapshot belongs to another run")
        active_scope_check(snapshot, baseline)
        snapshots[phase] = {
            "path": path.relative_to(ROOT).as_posix(),
            "sha256": flow.sha(path),
            "manifest_sha256": snapshot["manifest_sha256"],
        }
    plan_path = runs / "BUILD_PLAN.json"
    plan = flow.load(plan_path)
    plan["clocktrace_supplement"] = {
        **supplement,
        "snapshots": snapshots,
        "phases": list(PHASES),
        "mapped_before_proof": "syn_1/" + flow.NAME + "_mapped_before_proof.db",
        "legacy_builder_and_source_scope": "REUSED_UNCHANGED",
    }
    plan["mapping_experiment"]["key3_proof"] = (
        "reviewed self-contained strict clock-trace hook at all five phases; "
        "legacy hook remains frozen and checked by the original source scope")
    flow.save(plan_path, plan)


def install():
    # Only runtime bindings change.  The frozen original files are not edited.
    base.RUNS = RUNS
    base.EXTRAS = EXTRAS
    base.instrument_key3 = instrument_key3
    base.active_scope_check = active_scope_check
    base.prepare = prepare
    base.install()


if __name__ == "__main__":
    install()
    try:
        raise SystemExit(flow.main())
    except (OSError, ValueError, KeyError, RuntimeError, ET.ParseError) as error:
        print("BUILD_KEY3_STROKE_RELEASE_V2_FAIL:", error, file=sys.stderr)
        raise SystemExit(1)
