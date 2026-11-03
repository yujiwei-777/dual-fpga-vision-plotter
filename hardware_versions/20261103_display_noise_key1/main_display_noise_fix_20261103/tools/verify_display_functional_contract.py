"""Read-only display-change scope and functional wiring contract audit.

No simulator, FPGA tools, capture files or existing reports are modified.
Only reports/display_functional_contract.json is generated. This proves
source/wiring scope, not identical motion events or hardware image quality.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
from pathlib import Path
import random
import re
import sys
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
HDL = "01_rtl/imgq_gain_m/main/user_source/hdl_source/"
NAME = "camera_to_dsi_display_720p60_cnn_multibox"
ALLOWED = {HDL + "design_top_wrapper.v", HDL + "a4_display_spatial_h1.v",
           HDL + "isp/display_tone_96.v"}
BASE_BIT_SHA = "B048D5BD30915F7C08791A9947D90982B741929E00CC0BE3036F7018C76209BC"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def source(path: Path) -> str:
    # Some inherited sources use a legacy encoding. Bytes map losslessly;
    # comments are removed before token comparison and strings are preserved.
    text = path.read_bytes().decode("latin1")
    pattern = r'("(?:\\.|[^"\\])*")|(/\*.*?\*/|//[^\r\n]*)'
    return re.sub(pattern, lambda m: m[1] if m[1] is not None else " ",
                  text, flags=re.S)


def tokens(text: str) -> list[str]:
    return re.findall(r'"(?:\\.|[^"\\])*"|\\[^\s]+|[A-Za-z_$][A-Za-z0-9_$]*|'
                      r"(?:\d+)?'[sS]?[bBoOdDhH][0-9a-fA-F_xXzZ?]+|\d+|\S", text)


def parens(text: str, start: int) -> tuple[str, int]:
    assert text[start] == "("
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "(":
            depth += 1
        elif text[i] == ")":
            depth -= 1
            if depth == 0:
                return text[start + 1:i], i + 1
    raise ValueError("Unbalanced Verilog parentheses")


def instance(text: str, module: str, name: str) -> dict:
    for match in re.finditer(r"\b" + re.escape(module) + r"\s*", text):
        pos = match.end()
        params = ""
        param_span = None
        if pos < len(text) and text[pos] == "#":
            pos = re.match(r"#\s*", text[pos:]).end() + pos
            param_start = pos
            params, pos = parens(text, pos)
            param_span = (param_start + 1, pos - 1)
        ident = re.match(r"\s*([A-Za-z_$][A-Za-z0-9_$]*)\s*", text[pos:])
        if ident is None or ident[1] != name:
            continue
        pos += ident.end()
        ports, end = parens(text, pos)
        return {"params": params, "ports": ports, "param_span": param_span,
                "start": match.start(), "end": end}
    raise ValueError(f"Missing instance: {module} {name}")


def bindings(text: str) -> dict[str, str]:
    result = {}
    for match in re.finditer(r"\.([A-Za-z_$][A-Za-z0-9_$]*)\s*\(", text):
        value, _ = parens(text, match.end() - 1)
        result[match[1]] = "".join(tokens(value))
    return result


def module_from_file(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def active_project_files(project: Path, project_root: Path) -> set[tuple[str, str]]:
    entries = set()
    # TD writes literal '&' in the UsedInP&R attribute name; normalize only
    # that vendor XML syntax in memory. Never rewrite the project file.
    project_xml = project.read_text(encoding="utf-8-sig").replace(
        'Name="UsedInP&R"', 'Name="UsedInP&amp;R"')
    # Other TD sections contain non-XML names such as BitgenProperty::...;
    # only the source declaration subtree is needed for this scope check.
    sources = ET.fromstring(re.search(r"<Source_Files>.*?</Source_Files>",
                                     project_xml, flags=re.S)[0])
    for group in sources:
        for item in group.findall("File"):
            flags = {x.get("Name"): x.get("Val", "").lower()
                     for x in item.findall("./FileInfo/Attr")}
            if not (flags.get("UsedInSyn") == "true" or flags.get("UsedInP&R") == "true"):
                continue
            path = Path(item.get("Path"))
            if not path.is_absolute():
                path = project.parent / path
            rel = path.resolve().relative_to(project_root.resolve()).as_posix()
            rel = re.sub(r"td_project_(?:pcb_auto_v2|display_noise_v\d+)/", "FROZEN_RUN/", rel)
            entries.add((group.tag, rel))
    return entries


def verify(root: Path, run: Path) -> dict:
    base = root.parent / "main_pcb_auto_compat_20261101"
    errors, checks = [], []

    def check(name, passed, **evidence):
        checks.append({"name": name, "passed": bool(passed), **evidence})
        if not passed:
            errors.append(name)

    snapshot_path = root / "reports/baseline_source_snapshot_original.json"
    frozen = load_json(snapshot_path)
    validation = load_json(root / "reports/baseline_dependency_validation.json")
    check("validated_frozen_189_dependency_snapshot",
          len(frozen["files"]) == 189 and frozen.get("passed") is True
          and validation.get("passed") is True
          and sha(snapshot_path) == validation["baseline_snapshot_sha256"])
    check("successful_baseline_bit_unchanged", sha(base / "artifacts" /
          "dual_fpga_main_20261101_pcb_auto_compat_diagnostic.bit") == BASE_BIT_SHA)

    files = []
    for item in frozen["files"]:
        baseline_file = Path(item["path"])
        rel = baseline_file.relative_to(base).as_posix()
        baseline_actual = sha(baseline_file) if baseline_file.is_file() else None
        check("baseline_frozen_hash:" + rel, baseline_actual == item["sha256"])
        if item["kind"] == "project":
            continue  # Project paths/inactive declarations change separately.
        current = (run / baseline_file.name if "/td_project_pcb_auto_v2/" in rel
                   else root / rel)
        current_sha = sha(current) if current.is_file() else None
        allowed = rel in ALLOWED
        files.append({"path": rel, "kind": item["kind"],
                      "baseline_sha256": item["sha256"], "current_sha256": current_sha,
                      "identical": current_sha == item["sha256"],
                      "approved_display_file": allowed})
        check("copied_dependency_scope:" + rel,
              current.is_file() and (allowed or current_sha == item["sha256"]))
    changed = sorted(x["path"] for x in files if not x["identical"])
    check("exact_three_display_source_changes", set(changed) == ALLOWED, changed=changed)
    base_run = base / "01_rtl/imgq_gain_m/main/td_project_pcb_auto_v2"
    old_active = active_project_files(base_run / (NAME + ".al"), base)
    new_active = active_project_files(run / (NAME + ".al"), root)
    check("active_project_source_set_identical", old_active == new_active,
          active_entries=len(new_active),
          removed=sorted(old_active - new_active), added=sorted(new_active - old_active),
          inactive_entries="Excluded explicitly; inactive cleanup does not change active sources")

    top_rel = HDL + "design_top_wrapper.v"
    old_top, new_top = source(base / top_rel), source(root / top_rel)
    old_filter = instance(old_top, "a4_display_spatial_h1", "u_display_spatial_h1")
    new_filter = instance(new_top, "a4_display_spatial_h1", "u_display_spatial_h1")
    old_params, new_params = bindings(old_filter["params"]), bindings(new_filter["params"])
    check("only_filter_parameter_changes", old_params == {"ENABLE": "1", "EDGE_TH": "24"}
          and new_params == {"ENABLE": "1", "EDGE_TH": "16", "IMG_WIDTH": "1280"},
          baseline=old_params, current=new_params)
    start, end = new_filter["param_span"]
    normalized_top = new_top[:start] + old_filter["params"] + new_top[end:]
    check("top_tokens_identical_except_approved_filter_parameters",
          tokens(old_top) == tokens(normalized_top),
          comments="Ignored with string-preserving lexer; all other RTL tokens compared")

    old_ae, new_ae = (instance(text, "ae_auto", "u_ae_auto") for text in (old_top, new_top))
    ae_params = bindings(new_ae["params"])
    check("ae_all_instance_parameters_and_ports_identical",
          tokens(old_ae["params"]) == tokens(new_ae["params"])
          and tokens(old_ae["ports"]) == tokens(new_ae["ports"]), parameters=ae_params)
    ae_files = [x for x in files if re.search(r"(?:ae_auto|raw10_ae_stat|SC500GainTbl|uics500reg|uicfgcs500|aec_ctrl|ae_set)", x["path"], re.I)]
    check("ae_sensor_controller_writer_statistics_hashes_identical",
          bool(ae_files) and all(x["identical"] for x in ae_files),
          paths=[x["path"] for x in ae_files])

    core_rel = HDL + "isp/isp_top_basic_core.v"
    check("isp_core_entire_file_hash_identical", sha(base / core_rel) == sha(root / core_rel))
    core = source(root / core_rel)
    clean_assigns = re.findall(r"assign\s+(O_clean_\w+)\s*=\s*([^;]+);", core)
    tone = instance(core, "display_tone_96", "u_display_tone")
    tone_ports = bindings(tone["ports"])
    check("recognition_tap_is_original_fixed_tone",
          tone_ports.get("O_fixed_tdata") == "tone_fixed_O_tdata"
          and ("O_clean_rgb", "tone_fixed_O_tdata") in
          [(n, "".join(tokens(v))) for n, v in clean_assigns],
          clean_assigns=[{"name": n, "value": "".join(tokens(v))} for n, v in clean_assigns])
    tone_test = load_json(root / "reports/display_tone_rtl_regression.json")
    tone_rtl_sha = sha(root / HDL / "isp/display_tone_96.v")
    check("fixed_tap_cycle_equivalence_evidence_matches_current_rtl",
          tone_test.get("status") == "PASS" and tone_test.get("baseline_fixed_tap_cycle_equivalence")
          and tone_test.get("rtl_sha256") == tone_rtl_sha, evidence=tone_test)

    sampler = instance(new_top, "motion_post_hist_adapter", "u_motion_sample")
    check("motion_sampler_bypasses_hdmi_spatial_filter",
          bindings(sampler["ports"]).get("I_data") == "S_video_rd_data",
          source="S_video_rd_data", spatial_filter_output="S_display_data")
    for module, inst in (("motion_post_hist_adapter", "u_motion_sample"),
                         ("motion_detect", "u_motion_post_hist")):
        old, new = instance(old_top, module, inst), instance(new_top, module, inst)
        check("motion_parameters_and_ports_identical:" + module,
              tokens(old["params"]) == tokens(new["params"])
              and tokens(old["ports"]) == tokens(new["ports"]),
              parameters=bindings(new["params"]))
    motion_files = [x for x in files if "/motion" in x["path"].lower()]
    check("motion_algorithm_source_hashes_identical",
          bool(motion_files) and all(x["identical"] for x in motion_files),
          paths=[x["path"] for x in motion_files])

    tone_reference = module_from_file("contract_tone_reference", root / "tools/display_tone_reference.py")
    old_curve = [tone_reference.fixed_tone(i) for i in range(256)]
    new_curve = [tone_reference.display_tone(i) for i in range(256)]
    delta = [b - a for a, b in zip(old_curve, new_curve)]
    pair_change = max(abs((new_curve[b] - new_curve[a]) - (old_curve[b] - old_curve[a]))
                      for a in range(256) for b in range(256))
    abs_pair_change = max(abs(abs(new_curve[b] - new_curve[a]) - abs(old_curve[b] - old_curve[a]))
                          for a in range(256) for b in range(256))
    check("exhaustive_tone_difference_bounds", min(delta) == -4 and max(delta) == 0
          and pair_change == 4 and abs_pair_change == 4,
          input_values=256, input_pairs=65536, signed_channel_delta_range=[min(delta), max(delta)],
          maximum_signed_temporal_difference_change=pair_change,
          maximum_absolute_temporal_difference_change=abs_pair_change)

    import numpy as np
    spatial = module_from_file("contract_spatial_reference", root / "model/display_spatial_reference.py")
    replay = module_from_file("contract_replay_reference", root / "model/replay_display_noise.py")
    rng = random.Random(0x385601)
    images = []
    for width, height in ((1, 1), (1, 17), (17, 1), (3, 7), (13, 9), (32, 18)):
        images.append([[rng.getrandbits(24) for _ in range(width)] for _ in range(height)])
        images.append([[spatial.packed((96 + rng.randrange(-12, 13),
                                       112 + rng.randrange(-12, 13),
                                       128 + rng.randrange(-12, 13)))
                        for _ in range(width)] for _ in range(height)])
    images.append([[spatial.packed((96+x, 96, 96)) for x in (0, 16, 17, 0, 16, 17)]
                   for _ in range(3)])
    equal, pixels, cases = True, 0, 0
    for image in images:
        rgb = np.array([[spatial.rgb(v) for v in row] for row in image], dtype=np.uint8)
        for threshold in (0, 16, 24, 255):
            expected = np.array([[spatial.rgb(v) for v in row]
                                 for row in spatial.filter_image(image, threshold)], dtype=np.uint8)
            actual = replay.spatial_separable(rgb, threshold)
            equal = equal and bool(np.array_equal(expected, actual))
            cases += 1
            pixels += len(image) * len(image[0])
    check("historical_replay_spatial_model_matches_independent_integer_oracle", equal,
          cases=cases, compared_pixels=pixels, tested_thresholds=[0, 16, 24, 255],
          scope="Normal rectangular frames: H=round((source C+guarded source L)/2), then O=round((H+guarded previous-row H)/2); all-channel guard in each stage, missing neighbour=current, including all borders",
          limitation="Replay compares spatial filters on the same historical RGB; it does not simulate sensor/tone changes or the new bit on hardware",
          model_sha256=sha(root / "model/display_spatial_reference.py"),
          replay_sha256=sha(root / "model/replay_display_noise.py"))

    categories = {}
    for name, pattern in {"DDR_and_snapshots": r"ddr|snapshot|hx_frame|frame_write|frame_read",
                          "HXA1_and_network": r"hxa|rgmii|udp|eth_",
                          "CNN_PCB_document_interfaces": r"cnn|pcb|doc|hx_",
                          "motion": r"motion"}.items():
        subset = [x for x in files if re.search(pattern, x["path"], re.I)]
        categories[name] = {"count": len(subset), "all_hashes_identical": all(x["identical"] for x in subset),
                            "paths": [x["path"] for x in subset]}

    return {"passed": not errors, "generated_utc": datetime.now(timezone.utc).isoformat(),
            "baseline": str(base), "variant": str(root), "project_run": str(run),
            "baseline_bit_sha256": BASE_BIT_SHA, "changed_dependencies": changed,
            "frozen_dependency_count": len(frozen["files"]),
            "compared_nonproject_dependencies": len(files), "subsystem_scope": categories,
            "motion_input_pixel_identity_claimed": False,
            "motion_event_identity_claimed": False,
            "motion_caveat": "The motion sampler still reads S_video_rd_data before HDMI spatial filtering, with unchanged algorithm and parameters. However, original-style camera-domain display tone has four changed source values; these pixels pass through DDR to motion. Therefore motion input pixels/events are not claimed bit-identical to baseline. At the tone channel itself delta is [-4,0] DN; exhaustive two-frame signed/absolute difference change is at most 4 DN. This is not a formal bound on every downstream motion decision.",
            "recognition_contract": "O_clean remains connected to the original fixed-tone tap; matching current-RTL cycle-equivalence evidence is required above. No secondary-board source or model is modified by this main-only variant.",
            "historical_replay_scope": "Same historical RGB input to old/new spatial filters; tone correction and gain policy are outside that replay model.",
            "spatial_algorithm": "Separable causal 2x2: rounded horizontal average of source C/L, then rounded vertical average of current/previous-row H. Line BRAM stores H, not source RGB or recursively filtered output. Each stage uses the RGB edge guard independently.",
            "hardware_status": "NOT_RUN", "checks": checks, "dependencies": files,
            "dependency_kinds": dict(Counter(x["kind"] for x in files)), "errors": errors}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--run", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    configured = module_from_file("contract_project_paths", root / "tools/display_noise_paths.py")
    run = args.run or configured.RUN
    try:
        report = verify(root, run.resolve())
    except Exception as exc:
        report = {"passed": False, "errors": [f"{type(exc).__name__}: {exc}"],
                  "hardware_status": "NOT_RUN"}
    destination = root / "reports/display_functional_contract.json"
    destination.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "errors": report["errors"],
                      "report": str(destination), "motion_input_pixel_identity_claimed": False}, indent=2))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
