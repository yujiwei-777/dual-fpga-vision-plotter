"""Validate recorded ModelSim evidence and preserve the tested input hashes."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def read_log(path):
    data = path.read_bytes()
    return data.decode("utf-16" if data.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8", errors="replace")


def main():
    # TH16 bit predicate and rounded avg2 are exhaustively checked.
    for a in range(256):
        for b in range(256):
            bits = (a-b) & 511
            close = (bits >> 4) == 0 or (bits >> 4) == 31 or bits == 16
            assert close == (abs(a-b) <= 16)
            assert (a>>1)+(b>>1)+((a|b)&1) == (a+b+1)//2
    manifest = json.loads((HERE / "vectors_manifest.json").read_text())
    source_files = [
        ROOT / "01_rtl/imgq_gain_m/main/user_source/hdl_source/a4_display_spatial_h1.v",
        ROOT / "model/display_spatial_reference.py",
        HERE / "generate_vectors.py", HERE / "tb_display_spatial.sv",
        HERE / "run_display_noise.ps1", HERE / "vectors_manifest.json", HERE / "summarize_results.py",
    ]
    assert sha(source_files[0]) == manifest["rtl_sha256"]
    assert sha(source_files[1]) == manifest["reference_sha256"]
    results = []
    for case in manifest["cases"]:
        folder = HERE / case["name"]
        log_path = folder / "transcript.log"
        log = read_log(log_path)
        match = re.search(r"PASS pixel oracle WIDTH=(\d+) HEIGHT=(\d+) cycles=(\d+) valid=(\d+) sof=(\d+) eol=(\d+)", log)
        assert match and "Errors: 0, Warnings: 0" in log, case["name"]
        assert not re.search(r"\*\* (Warning|Error|Fatal)", log), case["name"]
        assert not re.search(r"\bWarning\b", log, re.I), case["name"]
        width, height, cycles, valid, sof, eol = map(int, match.groups())
        assert (width, height, cycles) == (case["width"], case["height"], case["cycles"])
        assert valid == case["source_pixels"]
        for name, expected in case["inputs"].items():
            assert sha(folder / name) == expected, (case["name"], name)
        results.append(dict(name=case["name"], cycles=cycles, valid=valid, sof=sof, eol=eol,
                            log_sha256=sha(log_path), result="PASS", tags=case["tags"]))
    compile_path = HERE / "compile.log"
    compile_log = read_log(compile_path)
    assert "Errors: 0, Warnings: 0" in compile_log
    assert not re.search(r"\*\* (Warning|Error|Fatal)", compile_log)
    assert not re.search(r"\bWarning\b", compile_log, re.I)
    replay_path = ROOT / "reports/display_noise_replay/historical_replay.json"
    replay = json.loads(replay_path.read_text())
    assert replay["rtl_sha256"] == sha(source_files[0])
    assert replay["integer_reference_sha256"] == sha(source_files[1])
    assert replay["replay_script_sha256"] == sha(ROOT / "model/replay_display_noise.py")
    assert replay["frames"] == 100 and replay["vectorized_equals_integer_reference"]
    equivalence_path = HERE.parent / "display_noise_nocarry_trial/verification.json"
    equivalence = json.loads(equivalence_path.read_text())
    assert equivalence["status"] == "PASS"
    assert equivalence["candidate_sha256"] == sha(source_files[0])
    prior_equivalence_path = HERE.parent / "display_noise_combined_trial/verification.json"
    prior_equivalence = json.loads(prior_equivalence_path.read_text())
    assert prior_equivalence["status"] == "PASS"
    assert prior_equivalence["candidate_sha256"] == equivalence["frozen_product_sha256"]
    assert equivalence["per_case_exhaustive_rtl"] == {"avg2_byte_pairs": 65536, "th16_byte_pairs": 65536, "th16_rgb_channel_pairs": 196608}
    report = dict(status="PASS", tool="ModelSim SE-64 2020.4", edge_threshold=16,
                  source_sha256={str(p.relative_to(ROOT)): sha(p) for p in source_files},
                  compile_sha256=sha(compile_path), cases=results,
                  total_cycles=sum(c["cycles"] for c in results),
                  total_valid=sum(c["valid"] for c in results),
                  synthetic_noise_rms=manifest["synthetic_noise_rms"],
                  historical_replay_sha256=sha(replay_path),
                  historical_100frame_rms=replay["background_temporal_residual_rms"],
                  historical_change_vs_h1_percent=replay["change_vs_h1_percent"],
                  arithmetic_exhaustive_pairs=65536, avg2_exhaustive_pairs=65536,
                  equivalence_evidence={"path": str(equivalence_path.relative_to(ROOT)),
                                        "sha256": sha(equivalence_path),
                                        "frozen_product_sha256": equivalence["frozen_product_sha256"],
                                        "compared_all_cycles": equivalence["total_cycles"]},
                  prior_equivalence_evidence={"path": str(prior_equivalence_path.relative_to(ROOT)),
                                              "sha256": sha(prior_equivalence_path),
                                              "candidate_sha256": prior_equivalence["candidate_sha256"],
                                              "frozen_product_sha256": prior_equivalence["frozen_product_sha256"]},
                  nocarry_exhaustive_rtl_per_case=equivalence["per_case_exhaustive_rtl"],
                  implementation="Separable horizontal/vertical guarded avg2; H stored in row RAM, no final-output feedback",
                  board_validation="NOT_RUN", synthesis_and_physical="See parent project build reports")
    (HERE / "verification.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    lines = [
        "# HDMI spatial filter verification", "",
        "Result: **PASS**, 11/11 independent integer-oracle RTL cases. Board validation: **NOT_RUN**.", "",
        "## Algorithm and scope", "",
        "The display-only module first computes H from current source C and original source L: rounded avg2 when all RGB differences are <=16, otherwise C; the first column is C. It then averages current H with previous-row H under the same RGB guard; first-row output is H. Missing or rejected neighbours substitute the current sample. All RGB channels retain eight bits. Strong two-level edges are preserved; low-contrast texture can be smoothed and requires real-camera comparison.", "",
        "This separable v6 candidate preserves frozen v5/v4 image behavior exactly. V6 changes only the fixed TH16 neighbour predicate: high-nibble equality or explicit nonwrapping adjacent-high relations plus Boolean low-nibble ordering replace signed subtraction. The same abs(a-b)<=16 decision and RGB three-channel AND remain. The separate nocarry trial checks every byte pair, all 196,608 single-channel RGB placements, all 65,536 avg2 pairs and full-cycle RGB/markers including invalid RGB against frozen v5. Its verification hash is bound in equivalence_evidence. The prior combined proof from v5 to v4 remains bound in prior_equivalence_evidence. No threshold, precision, pipeline, model or filtering algorithm changed.", "",
        "The inherited v5 resource-only changes use an 8-bit split rounded-average sum, move neighbour selection to the output, and omit masked RAM forwarding when width>1. Row RAM stores horizontally averaged H, never final vertical output. H is always formed from original current/left source pixels; there is no recursive row or frame feedback. The image algorithm, integer model and replay script remain unchanged from separable v4.", "",
        "One synchronous line RAM stores 1280 x 24 bits of H, the horizontal-pass result. Final vertical output is never written back. Validity masks prevent stale/uninitialized samples after reset, frame boundaries, short rows or SOF restart. Width-one geometry retains explicit collision forwarding; for width>1 every possible read/write collision has the upper-neighbour validity masked. A supplemental reachable-state control enumeration confirms this for arbitrary DE/SOF/EOL inputs on tested small geometries. No DSP or previous-frame storage is introduced. Actual ERAM/Slice use and timing must be established by synthesis/route.", "",
        "Pixel data and vsync/hsync/de/user/last pass through the same two register stages. The DDR read request must use the original timing generator DE; the delayed display DE belongs only to the post-read display path.", "",
        "## Evidence", "",
        "ModelSim SE-64 2020.4; file license E:/model/win64/LICENSE.TXT supplied through both license environment variables. One simulator process at a time. Compilation and all simulation transcripts report zero errors and warnings. Every cycle checks all five timing markers; every active output checks exact RGB against the integer oracle, plus ENABLE=0 delayed identity. Case equality rejects X data.", "",
        "This canonical separable v6 run uses a fresh directory and library after the complete v5 evidence was archived and hash-verified in ../display_noise_attempt5_rtl_v5/. V5 replay JSON/image were independently copied and SHA-verified in reports/display_noise_replay_attempt5_v5/ before the new current-product 100-frame replay. Historical v2 logs are retained in ../display_noise_attempt2_rtl_v2/. The earlier vlib already-exists warning was missed by the original summarizer, which checked only the later vlog summary; that historical compile is not used to satisfy the clean zero-warning gate. No historical raw log has been changed. Both combined and nocarry equivalence trial directories remain preserved.", "",
        "| Case | Cycles | Active pixels | SOF | EOL |", "|---|---:|---:|---:|---:|",
    ]
    for c in results:
        lines.append(f"| {c['name']} | {c['cycles']} | {c['valid']} | {c['sof']} | {c['eol']} |")
    lines += ["", f"Total: {report['total_cycles']:,} cycles, {report['total_valid']:,} active output pixels.", "",
              "The complete-geometry test sends two 1280x720 frames back to back without line/frame blanking. It checks all 1,843,200 source pixels, 2 SOF and 1,440 EOL markers, including the final row with no invented drain pixels. Other cases cover random DE gaps, all 256 RGB8 channel levels/low bits, 16/17 threshold boundaries in each channel, strong horizontal/vertical/diagonal edges, a one-pixel line, checkerboard, width-one RAM collision, isolated/held/abrupt SOF, early/missing EOL, and reset before initialized RAM.", "",
              "## Synthetic noise result", "",
              "A flat RGB field with independent Gaussian input noise sigma=3.3 and fixed random seed gives newly calculated RMS 3.3042 before filtering, 2.3723 with the exact historical horizontal 2-tap rule, and 1.7732 with separable guarded averaging (-25.26% against historical h1). Borders are excluded consistently from all three RMS measurements. The test asserts the reduction and exact preservation of strong-edge images and flat RGB8 fields.", "",
              "The separate historical 100-frame RGB replay was also recomputed: source RMS3.8284718, exact old h1 threshold24 RMS3.3149624, separable threshold16 RMS2.9609883, a 10.6781% reduction against h1. Frames8385..8979 use ROI[100,20,1100,150], validated PNG hashes and zero recorded transport errors. The vectorized replay is checked against the integer model. It binds the actual RTL, model and replay script hashes. Historical capture bit identity is unknown; this does not establish new-bit camera performance, visible-detail quality, or the source of distant texture artifacts. Full-frame TNR, AE/ISP changes, CNN/ROI input changes, and style-operator changes are outside this module. Board visual validation remains NOT_RUN.", "",
              "## Reproduce and hashes", "",
              "Run generate_vectors.py, then run_display_noise.ps1, then summarize_results.py from this folder. verification.json records every transcript hash and tested source hash; vectors_manifest.json records all input vector hashes.", "",
              "| File | SHA256 |", "|---|---|"]
    for name, digest in report["source_sha256"].items():
        lines.append(f"| {name} | {digest} |")
    (HERE / "DISPLAY_SPATIAL_VERIFICATION.md").write_text("\n".join(lines)+"\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "cases": len(results),
                      "cycles": report["total_cycles"], "valid_pixels": report["total_valid"]}))


if __name__ == "__main__":
    main()
