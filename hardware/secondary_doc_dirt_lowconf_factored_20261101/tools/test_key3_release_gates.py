"""Read-only parser/gate rejection checks; no synthesis/physical PASS claim."""
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def module(name, relative):
    spec = importlib.util.spec_from_file_location(name, ROOT / relative)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


def main():
    scope = module("scope_test", "tools/release_source_scope.py")
    physical = module("physical_test", "tools/key3_physical_gate.py")
    checks = []
    def passed(name, action):
        action(); checks.append({"name": name, "result": "PASS"})
    def rejects(name, action):
        try: action()
        except RuntimeError as exc: checks.append({"name": name, "result": "EXPECTED_REJECTION", "reason": str(exc)})
        else: raise AssertionError("Gate accepted negative fixture: " + name)

    passed("current_source_scope_preflight", lambda: scope.check())
    tree = scope.generated(ROOT)
    bad = copy.deepcopy(tree)
    for group in bad.findall("Source_Files/*"):
        for node in list(group):
            if Path(node.attrib["Path"]).name == "cnn_result_stabilizer.v": group.remove(node)
    rejects("missing_active_stabilizer", lambda: scope.check(tree=bad))
    bad = copy.deepcopy(tree)
    for node in bad.findall("Source_Files/*/File"):
        if Path(node.attrib["Path"]).name == "hxa_yolo_result_codec.v":
            for attr in node.findall("FileInfo/Attr"):
                if attr.get("Name") == "AutoExcluded": attr.set("Val", "false")
    rejects("historical_excluded_source_enabled", lambda: scope.check(tree=bad))

    control = ROOT.parent / scope.CONTROL_NAME
    base = json.loads((control / scope.CONTROL_RUN / "syn_1/source_snapshot.json").read_text())
    records = []
    for value in base["files"]:
        if value["kind"] in scope.SKIP_KINDS: continue
        rel = Path(value["path"]).relative_to(control).as_posix()
        path = ROOT / rel
        records.append({"path": path.as_posix(), "kind": value["kind"], "sha256": scope.sha(path)})
    records.append({"path": (ROOT / scope.KERNEL).as_posix(), "kind": "Verilog", "sha256": scope.APPROVED[scope.KERNEL]})
    for rel in scope.PROOF_DEPENDENCIES:
        records.append({"path": (ROOT / rel).as_posix(), "kind": "explicit_dependency", "sha256": scope.sha(ROOT / rel)})
    def snap(items):
        content = [{key: value[key] for key in ("path", "kind", "sha256")}
                   for value in sorted(items, key=lambda item: item["path"].lower())]
        return {"passed": True, "errors": [], "project_root": str(ROOT), "files": items,
                "manifest_sha256": hashlib.sha256(json.dumps(content, sort_keys=True).encode()).hexdigest().upper()}
    passed("constructed_complete_snapshot_scope", lambda: scope.check(snapshot=snap(records)))
    missing_hook = [v for v in records if not v["path"].endswith("apply_reset_exceptions.tcl")]
    rejects("missing_explicit_reset_hook", lambda: scope.check(snapshot=snap(missing_hook)))
    missing_model = [v for v in records if not v["path"].endswith("01_rtl/model/export/weights.mem")]
    rejects("omitted_model_dependency", lambda: scope.check(snapshot=snap(missing_model)))
    stale = snap(records); stale["manifest_sha256"] = "0" * 64
    rejects("invalid_snapshot_manifest_digest", lambda: scope.check(snapshot=stale))

    phy = control / scope.CONTROL_RUN / "phy_1"
    names = ["secondary_cdc_route_end.rpt", "secondary_cdc_route_end.sdc", "secondary_exact_route_end.sdc", "secondary_effective_route_end.sdc"]
    texts = [physical.read(phy / name) for name in names]
    passed("control_actual_cdc_endpoint_parser", lambda: physical.verify_cdc(*texts))
    changed = list(texts); changed[0] = changed[0].replace("CDC_GROUP gray_d COUNT=52", "CDC_GROUP gray_d COUNT=51")
    rejects("cdc_declared_count_without_endpoints", lambda: physical.verify_cdc(*changed))
    changed = list(texts); changed[1] = changed[1].replace("-datapath_only 7.000", "-datapath_only 7.500")
    rejects("cdc_request_budget_relaxed", lambda: physical.verify_cdc(*changed))
    changed = list(texts); changed[0] = changed[0].replace("CDC_GROUP gray_d", "CDC_GROUP unapproved_gray_d")
    rejects("cdc_group_identity_changed", lambda: physical.verify_cdc(*changed))

    # This is an adapted parser fixture, never a claim that the old board has
    # the new supervisor. Actual acceptance requires check(root,runs).
    reset = physical.read(phy / "secondary_reset_route_end.rpt")
    reset_sdc = physical.read(phy / "secondary_reset_route_end.sdc")
    exact = physical.read(phy / "secondary_exact_route_end.sdc")
    effective = physical.read(phy / "secondary_effective_route_end.sdc")
    ignored = physical.read(phy / "secondary_effective_route_end.ignored.rpt").replace("{key3_meta}", "{u_board_reset/key_meta}")
    loaded = physical.read(phy / "secondary_loaded_route_end.rpt")
    args = [reset, reset_sdc, exact, effective, ignored, loaded, "por_release"]
    passed("adapted_control_actual_reset_endpoint_parser", lambda: physical.verify_resets(*args))
    bad = list(args); bad[0] = bad[0].replace("INSTANCE_PROVEN u_reset125 ", "INSTANCE_PROVEN unapproved_reset125 ")
    rejects("reset_same_count_wrong_instance", lambda: physical.verify_resets(*bad))
    bad = list(args); bad[0] = bad[0].replace("INSTANCE_PROVEN u_reset125 STAGE0=1 STAGE1=6", "INSTANCE_PROVEN u_reset125 STAGE0=1 STAGE1=5")
    rejects("reset_clone_count_mismatch", lambda: physical.verify_resets(*bad))
    bad = list(args); bad[1] = "\n".join(bad[1].splitlines()[2:])
    rejects("reset_generated_sdc_missing_actual_pin", lambda: physical.verify_resets(*bad))
    bad = list(args); bad[4] = bad[4].replace("{u_board_reset/key_meta}", "{u_board_reset/key_sync}")
    rejects("key3_second_stage_falsepath", lambda: physical.verify_resets(*bad))
    rejects("old_control_cannot_pass_new_current_run_gate", lambda: physical.check(ROOT, phy.parent))
    print(json.dumps({"status": "PASS_GATE_SELFTEST_ONLY", "checks": checks, "count": len(checks),
        "scope_sha256": scope.sha(ROOT / "tools/release_source_scope.py"),
        "physical_gate_sha256": scope.sha(ROOT / "tools/key3_physical_gate.py"),
        "fixtures": {name: physical.sha(phy / name) for name in names + ["secondary_reset_route_end.rpt"]},
        "notes": ["In-memory fixtures and read-only control report parsing only", "No TD, RTL simulation or physical implementation was run"],
        "hardware_status": "NOT_RUN"}, indent=2))


if __name__ == "__main__": main()
