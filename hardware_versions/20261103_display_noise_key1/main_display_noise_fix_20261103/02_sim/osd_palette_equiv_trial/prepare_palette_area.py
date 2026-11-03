"""Prepare a complete dynamic OSD gate comparison; TD requires --run-prepared.

All new files stay inside this isolated experiment. Neither preparation nor an
area run changes the production RTL, V8 inputs, constraints or RUN scripts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from run_spatial_module_area import prepare_module_gate, run_module_gate

FRAMEWORK = ROOT / "tools/run_spatial_module_area.py"
PRODUCTION = ROOT / "01_rtl/imgq_gain_m/main/user_source/hdl_source/osd_compact_panel.v"
RECEIPT = HERE / "verification.json"
CASES = {
    "baseline": ("osd_compact_panel_frozen.v", "osd_compact_panel_frozen"),
    "palette": ("osd_compact_panel_palette.v", "osd_compact_panel_palette"),
}
AREA_MODULE = "osd_compact_panel_area_dut"
DEFAULT_OUT = HERE / "module_gate_20261103_dynamicio"

# PH1P35MDG324 exposes 160 IO to this helper configuration. A direct copy of
# all OSD ports would require 213. Only the 112 BCD metadata input bits are
# serialized, using exactly the same 112 FF wrapper in both cases. Four
# arbitrary 32-bit words can reach every possible 112-bit metadata value.
# All controls, coordinates and font data remain independent external inputs;
# every DUT output remains an external output. No mode/status is tied off.
WRAPPER = """module module_area_top(
    input wire clk, rst_n,
    input wire [11:0] x, y,
    input wire pcb_mode,
    input wire [2:0] pcb_status,
    input wire [4:0] algo_mode,
    input wire he_on, lat_valid, lat_overflow,
    input wire [31:0] metadata_word,
    input wire remote, ovl_valid,
    input wire [1:0] target_color, shape3,
    input wire target_shape, motion_enable,
    input wire [15:0] font_row_bits,
    output wire panel_on, panel_border, text_on,
    output wire [23:0] text_color,
    output wire [7:0] font_glyph,
    output wire [3:0] font_row
);
    reg [111:0] dynamic_bcd_metadata;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) dynamic_bcd_metadata <= 112'd0;
        else dynamic_bcd_metadata <= {dynamic_bcd_metadata[79:0], metadata_word};
    end
    osd_compact_panel_area_dut dut(
        .clk(clk), .rst_n(rst_n), .x(x), .y(y),
        .pcb_mode(pcb_mode), .pcb_status(pcb_status), .algo_mode(algo_mode),
        .he_on(he_on), .lat_valid(lat_valid), .lat_overflow(lat_overflow),
        .frame_bcd(dynamic_bcd_metadata[111:92]),
        .lat_bcd(dynamic_bcd_metadata[91:76]),
        .target_x_bcd(dynamic_bcd_metadata[75:60]),
        .target_y_bcd(dynamic_bcd_metadata[59:44]),
        .area_bcd(dynamic_bcd_metadata[43:20]),
        .remote(remote), .ovl_valid(ovl_valid),
        .target_color(target_color), .shape3(shape3),
        .target_shape(target_shape), .motion_enable(motion_enable),
        .motion_bcd(dynamic_bcd_metadata[19:0]),
        .panel_on(panel_on), .panel_border(panel_border), .text_on(text_on),
        .text_color(text_color), .font_glyph(font_glyph), .font_row(font_row),
        .font_row_bits(font_row_bits)
    );
endmodule
"""


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def put(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def fail_unless(condition, message):
    if not condition:
        raise RuntimeError(message)


def parse_ports(source, module):
    """Parse the deliberately simple ANSI headers used by these two modules."""
    match = re.search(r"\bmodule\s+" + re.escape(module) + r"\s*\((.*?)\);", source, re.S)
    fail_unless(match is not None, "Missing expected module declaration")
    ports = {}
    for declaration in re.finditer(r"\b(input|output)\s+wire\s*(\[\d+:\d+\])?\s*([^;]+?)(?=\binput\b|\boutput\b|$)", match[1], re.S):
        direction, vector, names = declaration.groups()
        width = 1
        if vector:
            hi, lo = map(int, re.findall(r"\d+", vector))
            width = abs(hi - lo) + 1
        for name in names.strip().rstrip(",").split(","):
            name = name.strip()
            fail_unless(re.fullmatch(r"[A-Za-z_]\w*", name) is not None,
                        "Unexpected ANSI port syntax: " + name)
            fail_unless(name not in ports, "Duplicate port: " + name)
            ports[name] = {"direction": direction, "width": width}
    return ports


def validate_wrapper(source):
    dut_ports = parse_ports(source, AREA_MODULE)
    external = parse_ports(WRAPPER, "module_area_top")
    instance = re.search(r"\bosd_compact_panel_area_dut\s+dut\s*\((.*?)\);", WRAPPER, re.S)
    fail_unless(instance is not None, "Missing complete DUT instance")
    pairs = re.findall(r"\.([A-Za-z_]\w*)\(([^()]+)\)", instance[1])
    connections = dict(pairs)
    fail_unless(len(pairs) == len(connections) and set(connections) == set(dut_ports),
                "DUT has missing, extra or duplicate wrapper connections")
    metadata_bits = []
    for name, details in dut_ports.items():
        expression = connections[name]
        if details["direction"] == "output" or name in external:
            fail_unless(expression == name and external.get(name) == details,
                        "Direct dynamic/external port mismatch: " + name)
        else:
            bit_range = re.fullmatch(r"dynamic_bcd_metadata\[(\d+):(\d+)\]", expression)
            fail_unless(bit_range is not None, "Metadata tied off or unexpectedly computed: " + name)
            hi, lo = map(int, bit_range.groups())
            fail_unless(hi >= lo and hi - lo + 1 == details["width"], "Metadata width mismatch")
            metadata_bits.extend(range(lo, hi + 1))
    fail_unless(sorted(metadata_bits) == list(range(112)), "Metadata overlap or uncovered bits")
    input_bits = sum(p["width"] for p in external.values() if p["direction"] == "input")
    output_bits = sum(p["width"] for p in external.values() if p["direction"] == "output")
    fail_unless((input_bits, output_bits) == (94, 39), "Unexpected wrapper IO count")
    # Independent of RTL/TD: demonstrate that arbitrary four input words can
    # reach all 112 single-bit basis vectors, including zero. This rules out
    # hidden metadata constants or bit duplication in the shift staging.
    mask = (1 << 112) - 1
    for expected in [0] + [1 << bit for bit in range(112)]:
        state = 0
        for offset in (96, 64, 32, 0):
            state = ((state << 32) | ((expected >> offset) & 0xFFFFFFFF)) & mask
        fail_unless(state == expected, "Dynamic metadata reachability failure")
    return {"input_bits": input_bits, "output_bits": output_bits,
            "total_io": input_bits + output_bits, "dut_ports": dut_ports,
            "connections": connections, "metadata_bits": 112,
            "arbitrary_metadata_loading_cycles": 4,
            "metadata_basis_vectors_checked": 113}


def check_equivalence():
    receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
    fail_unless(receipt["status"] == "PASS" and receipt["all_outputs_including_invalid_compared"],
                "No complete functional equivalence PASS")
    fail_unless(receipt["cycles"] == 2984788 and receipt["asynchronous_reset_checks"] == 53,
                "Unexpected functional coverage receipt")
    fail_unless(receipt["coverage"]["pcb_statuses"] == 8 and receipt["coverage"]["normal_rows"] == 5,
                "Missing PCB/normal panel equivalence coverage")
    for name, digest in receipt["evidence_sha256"].items():
        fail_unless(sha(HERE / name) == digest, "Equivalence evidence drift: " + name)
    fail_unless(sha(PRODUCTION) == receipt["baseline_sha256"], "Production baseline drift")
    fail_unless(sha(HERE / CASES["palette"][0]) == receipt["candidate_sha256"], "Candidate drift")
    restored = (HERE / CASES["baseline"][0]).read_bytes().replace(
        b"module osd_compact_panel_frozen(", b"module osd_compact_panel(", 1)
    fail_unless(restored == PRODUCTION.read_bytes(), "Frozen source is not exact production baseline")
    return receipt


def prepare(out):
    fail_unless(not out.exists(), "Refuse to overwrite area evidence")
    receipt = check_equivalence()
    raw = {label: (HERE / name).read_bytes() for label, (name, _) in CASES.items()}
    normalized = {}
    for label, (_, module) in CASES.items():
        old = ("module " + module + "(").encode()
        fail_unless(raw[label].count(old) == 1, "Unexpected source module declaration")
        normalized[label] = raw[label].replace(old, ("module " + AREA_MODULE + "(").encode(), 1)
    checks = [validate_wrapper(text.decode("utf-8-sig")) for text in normalized.values()]
    fail_unless(checks[0] == checks[1], "Baseline/candidate port contract differs")
    out.mkdir(parents=True)
    source_dir = out / "normalized_sources"
    source_dir.mkdir()
    manifests = {}
    for label, (upstream, _) in CASES.items():
        source = source_dir / (label + ".v")
        source.write_bytes(normalized[label])
        folder = out / label
        manifest = prepare_module_gate(folder, source, WRAPPER, {})
        shutil.copy2(HERE / "osd_compact_glyphs.vh", folder / "osd_compact_glyphs.vh")
        manifest["inputs"]["osd_compact_glyphs.vh"] = sha(folder / "osd_compact_glyphs.vh")
        manifest["complete_verilog_filelist"] = ["module_source.v", "module_area_top.v"]
        manifest["include_files"] = {"osd_compact_glyphs.vh": sha(folder / "osd_compact_glyphs.vh")}
        manifest["upstream_source"] = str(HERE / upstream)
        manifest["upstream_sha256"] = sha(HERE / upstream)
        manifest["only_preparation_source_change"] = "module declaration renamed to common area DUT"
        manifest["all_eight_pcb_statuses_and_normal_panel_runtime_dynamic"] = True
        manifest["wrapper_metadata_loading"] = "112 FF shifted by 32 arbitrary external bits; all input values reachable in four clocks"
        put(folder / "input_manifest.json", manifest)
        manifests[label] = manifest
    for name in ("module_area_top.v", "run.tcl", "osd_compact_glyphs.vh"):
        fail_unless((out / "baseline" / name).read_bytes() == (out / "palette" / name).read_bytes(),
                    "Unfair baseline/candidate preparation: " + name)
    context = {
        "status": "PREPARED_NOT_RUN", "hardware_status": "NOT_RUN",
        "runner_sha256": sha(Path(__file__)), "framework_sha256": sha(FRAMEWORK),
        "equivalence_receipt": str(RECEIPT), "equivalence_receipt_sha256": sha(RECEIPT),
        "equivalence_cycles": receipt["cycles"], "equivalence_reset_checks": receipt["asynchronous_reset_checks"],
        "production_sha256": sha(PRODUCTION), "candidate_sha256": receipt["candidate_sha256"],
        "input_manifests": {label: sha(out / label / "input_manifest.json") for label in CASES},
        "wrapper_sha256": sha(out / "baseline/module_area_top.v"), "port_validation": checks[0],
        "device": "PH1P35MDG324", "speed": 3,
        "mapping": "default auto", "pack_effort": "high", "uses_complete_V8_strategy": False,
        "same_wrapper_device_strategy": True, "all_DUT_outputs_external": True,
        "all_DUT_inputs_dynamic": True, "all_eight_pcb_statuses_retained": True,
        "normal_panel_all_five_rows_retained": True, "wrapper_FF_added_to_both_cases": 112,
        "resource_status": "NOT_MEASURED", "product_modified": False, "V8_modified": False,
        "place_route_bitgen": False,
        "limitation": "Preliminary module gate comparison only; no full-board capacity, Slice, routed timing, image quality or release acceptance.",
    }
    put(out / "comparison_context.json", context)
    print(json.dumps({"status": context["status"], "output": str(out),
                      "external_io_count": checks[0]["total_io"], "TD_started": False}, indent=2))


def run_prepared(out):
    """Explicit opt-in for the root agent; preparation never calls this."""
    context = json.loads((out / "comparison_context.json").read_text(encoding="utf-8"))
    fail_unless(sha(Path(__file__)) == context["runner_sha256"] and sha(FRAMEWORK) == context["framework_sha256"],
                "Runner/framework drift")
    fail_unless(sha(RECEIPT) == context["equivalence_receipt_sha256"], "Equivalence receipt drift")
    check_equivalence()
    fail_unless(not (out / "comparison.json").exists(), "Preserve prior comparison")
    for label in CASES:
        folder = out / label
        fail_unless(not (folder / "console.log").exists(), "Preserve prior raw gate logs")
        fail_unless(sha(folder / "input_manifest.json") == context["input_manifests"][label], "Manifest drift")
        manifest = json.loads((folder / "input_manifest.json").read_text(encoding="utf-8"))
        for name, digest in manifest["inputs"].items():
            fail_unless(sha(folder / name) == digest, "Prepared input drift: " + name)
        fail_unless(sha(manifest["source"]) == manifest["source_sha256"], "Normalized source drift")
        fail_unless(sha(manifest["upstream_source"]) == manifest["upstream_sha256"], "Upstream source drift")
        validate_wrapper((folder / "module_source.v").read_text(encoding="utf-8-sig"))
    results = {}
    for label in CASES:
        print("START isolated OSD palette gate: " + label, flush=True)
        result = run_module_gate(out / label)
        fail_unless(result["source_current_matches_copied"], "Current normalized source differs from copied input")
        results[label] = result
    before = results["baseline"]["reports"]["module_area_gate.area"]["dut"]
    after = results["palette"]["reports"]["module_area_gate.area"]["dut"]
    warnings = {}
    for label in CASES:
        log = (out / label / "console.log").read_text(encoding="utf-8-sig")
        warnings[label] = [line for line in log.splitlines() if re.search(r"\bWARNING\b|\bWARN\b", line)]
    result = {
        "status": "PASS_AREA_COMPARISON_ONLY", "baseline": before, "palette": after,
        "palette_minus_baseline": {key: after[key] - before[key] for key in before},
        "after_legalize_dut": {label: results[label]["reports"]["module_area_after_legalize.area"]["dut"] for label in CASES},
        "results": {label: str(out / label / "area_result.json") for label in CASES},
        "comparison_context_sha256": sha(out / "comparison_context.json"),
        "raw_warning_lines_retained": warnings, "hardware_status": "NOT_RUN",
        "all_DUT_inputs_dynamic": True, "all_DUT_outputs_external": True,
        "same_133IO_wrapper": True, "all_eight_pcb_statuses_and_normal_panel_retained": True,
        "product_modified": False, "V8_modified": False, "place_route_bitgen": False,
        "limitation": context["limitation"],
    }
    put(out / "comparison.json", result)
    print(json.dumps(result, indent=2), flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--prepare-only", action="store_true")
    mode.add_argument("--run-prepared", action="store_true")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    if args.prepare_only:
        prepare(args.out.resolve())
    else:
        run_prepared(args.out.resolve())
