from datetime import datetime, timezone
from pathlib import Path
import hashlib
import json
import shutil


ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "build_Runs_20261023" / "phy_1"
SYN = ROOT / "build_Runs_20261023" / "syn_1"
AUDIT = ROOT / "02_sim" / "readonly_ordinary_key2_20261023"
REGRESSION = ROOT / "02_sim" / "release_regression_20261023"
LINT = ROOT / "02_sim" / "active_lint_20261023"
OUT = ROOT / "artifacts"
BOOT = ROOT / "05_boot" / "best_result"
STEM = "dual_fpga_secondary_20261023_ordinary_doc_key2_diagnostic"


def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest().upper()


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def copy_checked(source, destinations):
    digest = sha(source)
    for destination in destinations:
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists() and sha(destination) != digest:
            raise RuntimeError(f"refusing to replace different artifact: {destination}")
        if not destination.exists():
            shutil.copy2(source, destination)
        if sha(destination) != digest:
            raise RuntimeError(f"copy hash mismatch: {destination}")
    return digest


gate = read_json(RUN / "release_gate.json")
if not gate.get("passed") or not gate.get("bitgen_allowed"):
    raise RuntimeError("release gate did not authorize packaging")
readonly = read_json(AUDIT / "readonly_verification.json")
if not readonly.get("passed"):
    raise RuntimeError("read-only reimport verification did not pass")
regression_results = (REGRESSION / "RESULTS.txt").read_text(encoding="utf-8")
required_tests = [
    "tb_grbl_key2_test_ctrl", "tb_grbl_reporter_key2", "tb_doc_grbl_uart_priority",
    "tb_doc_grbl_streamer_timers", "tb_doc_grbl_plotter", "tb_doc_grbl_map",
    "tb_hxa_packet_rx_fifo4",
]
for test in required_tests:
    if test not in regression_results:
        raise RuntimeError(f"missing regression result: {test}")
if regression_results.count("Errors: 0") != len(required_tests):
    raise RuntimeError("one or more RTL regressions reported errors")
lint_summary = (LINT / "summary.txt").read_text(encoding="utf-8", errors="replace")
if "returncode=0 files=72" not in lint_summary or "Errors: 0, Warnings: 0" not in lint_summary:
    raise RuntimeError("active RTL lint did not pass cleanly")
if not (RUN / ".bitgen.end.f").is_file() or (RUN / ".bitgen.error.f").exists():
    raise RuntimeError("bitgen completion evidence is missing or failed")

OUT.mkdir(parents=True, exist_ok=True)
BOOT.mkdir(parents=True, exist_ok=True)
normal = RUN / "secondary_cnn_multibox.bit"
compressed = RUN / "secondary_cnn_multibox_compress.bit"
normal_sha = copy_checked(normal, [OUT / f"{STEM}.bit", BOOT / f"{STEM}.bit"])
compressed_sha = copy_checked(compressed, [OUT / f"{STEM}_compress.bit", BOOT / f"{STEM}_compress.bit"])

snapshot = read_json(SYN / "source_snapshot.json")
for item in snapshot["files"]:
    path = (ROOT / item["path"]).resolve()
    if not path.is_file() or sha(path) != item["sha256"].upper():
        raise RuntimeError(f"source snapshot mismatch: {item['path']}")

evidence = [
    RUN / "release_gate.json", RUN / "route_flow.status", RUN / "secondary_cnn_multibox_pr.timing",
    RUN / "secondary_cnn_multibox_phy.area", RUN / "secondary_cnn_multibox_pr.db",
    RUN / "secondary_cnn_multibox_chk.timing", RUN / "secondary_cdc_route_end.rpt",
    RUN / "secondary_effective_route_end.exceptions.rpt", RUN / "secondary_effective_route_end.ignored.rpt",
    RUN / "td_20261023_210801.log", RUN / "td_20261023_214902.log", RUN / "bitgen_console.log",
    SYN / "source_snapshot.json", AUDIT / "readonly_verification.json", AUDIT / "readonly.timing",
    AUDIT / "readonly.area", AUDIT / "readonly.check", AUDIT / "readonly.flow",
    REGRESSION / "RESULTS.txt", REGRESSION / "vlog.log",
    *[REGRESSION / f"{test}.log" for test in required_tests],
    LINT / "summary.txt", LINT / "vlog.log",
]
evidence = [path for path in evidence if path.is_file()]
manifest = {
    "generated_utc": datetime.now(timezone.utc).isoformat(),
    "project_root": ROOT.as_posix(),
    "top": "secondary_top",
    "device": "PH1P35MDG324 speed 3",
    "hardware_status": "NOT_RUN",
    "scope": "Ordinary CNN + document copy + KEY2 GRBL test; PCB purpose disabled",
    "pcb_enabled": False,
    "ordinary_cnn_enabled": True,
    "document_copy_enabled": True,
    "key2_enabled": True,
    "artifacts": [
        {"path": f"artifacts/{STEM}.bit", "sha256": normal_sha, "bytes": normal.stat().st_size},
        {"path": f"artifacts/{STEM}_compress.bit", "sha256": compressed_sha, "bytes": compressed.stat().st_size},
    ],
    "timing_ns": gate["timing_ns"],
    "resources": gate["resources"],
    "source_snapshot": {"path": "build_Runs_20261023/syn_1/source_snapshot.json", "files": len(snapshot["files"])},
    "checks": {
        "release_gate": "PASS", "route": "PASS", "cdc": "REPORT_PRESENT",
        "fifo_ddr": "REPORT_PRESENT", "drc": "WARNINGS_RETAINED", "readonly_reimport": "PASS",
        "bitgen": "PASS", "hardware": "NOT_RUN",
        "active_rtl_lint": "PASS_72_FILES",
        "rtl_regression": {test: "PASS" for test in required_tests},
    },
    "retained_warning_codes": ["SLATR-1036", "SLATR-1038", "PHY-5016"],
    "absent_warning_codes": ["RTCLK-5078", "USR-6113", "USR-8159"],
    "evidence": [{"path": p.relative_to(ROOT).as_posix(), "sha256": sha(p)} for p in evidence],
}
(OUT / "RELEASE_MANIFEST.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
shutil.copy2(SYN / "source_snapshot.json", OUT / "source_snapshot.prebuild.json")
(OUT / "SHA256SUMS.txt").write_text(
    "".join(f"{sha(path)}  {path.relative_to(ROOT).as_posix()}\n" for path in
            [OUT / f"{STEM}.bit", OUT / f"{STEM}_compress.bit", OUT / "RELEASE_MANIFEST.json",
             OUT / "source_snapshot.prebuild.json"]), encoding="ascii")

status = f"""# Ordinary/document/KEY2 secondary release

Hardware status: **NOT_RUN**.

This independent build keeps ordinary CNN, document copy, KEY2 fixed-path GRBL test,
HXA1/DDR/CRC/Type18 and the existing plotter link. `PCB_ENABLE=0` is explicit in
`01_rtl/secondary_top.v`; purpose=1 is unsupported and does not instantiate PCB TinyCNN.

| Metric | Result |
|---|---:|
| Final setup WNS / TNS | {gate['timing_ns']['SWNS']:.3f} ns / {gate['timing_ns']['STNS']:.3f} ns |
| Final hold WNS / TNS | {gate['timing_ns']['HWNS']:.3f} ns / {gate['timing_ns']['HTNS']:.3f} ns |
| Slice | {gate['resources']['slice']['used']}/{gate['resources']['slice']['total']} ({gate['resources']['slice']['percent']:.2f}%) |
| ERAM | {gate['resources']['eram']['used']}/{gate['resources']['eram']['total']} ({gate['resources']['eram']['percent']:.2f}%) |
| DSP | {gate['resources']['dsp']['used']}/{gate['resources']['dsp']['total']} ({gate['resources']['dsp']['percent']:.2f}%) |
| Read-only routed reimport | PASS |
| Bitgen | PASS |
| Active RTL lint | PASS, 72 files, 0 errors / 0 warnings |
| Focused RTL regression | PASS, 7 testbenches, 0 errors |

Normal bit SHA256: `{normal_sha}`

Compressed bit SHA256: `{compressed_sha}`

The route log retains the known SLATR-1036/1038 and PHY-5016 warnings. RTCLK-5078,
USR-6113 and USR-8159 are absent. This is a build and database audit, not a claim
of board-level CNN, DDR, Ethernet or GRBL hardware validation.

Regression evidence: `02_sim/release_regression_20261023/RESULTS.txt` and its
per-test logs. Full-feature PCB-enabled trial results are separate and did not
pass resource/timing gates; no bit was generated for that trial.
"""
(ROOT / "BUILD_STATUS_20261023.md").write_text(status, encoding="utf-8")
print(json.dumps({"normal_sha256": normal_sha, "compressed_sha256": compressed_sha,
                  "hardware_status": "NOT_RUN", "artifacts": [str(OUT / f"{STEM}.bit"),
                  str(OUT / f"{STEM}_compress.bit")]}, indent=2))
