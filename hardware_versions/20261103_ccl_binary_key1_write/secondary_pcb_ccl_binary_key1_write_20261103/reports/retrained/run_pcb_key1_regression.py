"""Run a focused, controlled-leaf KEY1 PCB/CNN report regression."""
from datetime import datetime, timezone
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
SIM = Path("E:/model/win64")
MARKER = "PCB_KEY1_REPORT_PASS checks=23"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def module_header(path, name):
    text = Path(path).read_text(encoding="utf-8-sig", errors="replace")
    text = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.S)
    match = re.search(r"\bmodule\s+" + re.escape(name) + r"\b", text)
    if not match:
        raise RuntimeError(f"module {name} not found in {path}")
    return text[match.start():text.index(";", match.end()) + 1]


def run(output):
    output.mkdir(parents=True, exist_ok=False)
    env = dict(os.environ)
    env.update(LM_LICENSE_FILE=str(SIM / "LICENSE.TXT"),
               MGLS_LICENSE_FILE=str(SIM / "LICENSE.TXT"))
    declarations = {
        "pll": ROOT / "main/user_source/hdl_source/ethernet/pll.v",
        "PLL": ROOT / "main/user_source/ip_source/PLL/PLL.v",
        "secondary_ddr_wrapper": ROOT / "01_rtl/secondary_ddr_wrapper.v",
        "reset_sync": ROOT / "main/user_source/hdl_source/reset_sync.v",
        "hxa_ddr_store": ROOT / "01_rtl/hxa_ddr_store.v",
        "uiudp_stack": ROOT / "main/user_source/hdl_source/ethernet/uiudp_stack.v",
        "vision_pixel_reader": ROOT / "01_rtl/vision_pixel_reader.v",
        "vision_pipeline": ROOT / "01_rtl/vision_pipeline.v",
        "hxa_config_store": ROOT / "shared/rtl/hxa_config_store.v",
        "hxa_secondary_link": ROOT / "shared/rtl/hxa_secondary_link.v",
        "grbl_uart_port": ROOT / "01_rtl/grbl_uart.v",
        "grbl_reporter_shared_candidate": ROOT / "01_rtl/grbl_reporter_shared_candidate.v",
        "grbl_shared_transport_candidate": ROOT / "01_rtl/grbl_shared_transport_candidate.v",
        "doc_copy_pipeline_shared_candidate": ROOT / "01_rtl/doc_copy_pipeline_shared_candidate.v",
        "rgmii_interface": ROOT / "main/user_source/hdl_source/ethernet/rgmii_interface.v",
    }
    stub = output / "current_top_leaf_interfaces.sv"
    with stub.open("w", encoding="utf-8", newline="\n") as f:
        for name, source in declarations.items():
            f.write(module_header(source, name) + "\nendmodule\n")
        f.write("module PH1P_LOGIC_BUFG(input i, output o); assign o=i; endmodule\n")

    top = ROOT / "01_rtl/secondary_top.v"
    bench = Path(__file__).with_name("tb_pcb_key1_report.sv")
    sources = [stub, top, bench]
    source_hashes = {str(p.resolve()): sha(p) for p in [*sources, *declarations.values(), Path(__file__)]}
    lib = output / "key1_pcb_lib"
    commands = []

    def command(label, argv, marker=None):
        log = output / f"{label}.log"
        with log.open("w", encoding="utf-8") as stream:
            result = subprocess.run(list(map(str, argv)), cwd=output, env=env,
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=600)
        text = log.read_text(encoding="utf-8", errors="replace")
        ok = result.returncode == 0 and not re.search(r"\*\*\s+(?:Error|Fatal):", text)
        if marker:
            ok = ok and marker in text
        commands.append({"label": label, "argv": list(map(str, argv)),
                         "returncode": result.returncode, "status": "PASS" if ok else "FAIL",
                         "log": str(log), "log_sha256": sha(log)})
        if not ok:
            raise RuntimeError(f"{label} failed; see {log}\n{text[-3000:]}")
        return text

    try:
        command("vlib", [SIM / "vlib.exe", lib])
        command("lint", [SIM / "vlog.exe", "-sv", "-lint", "-work", lib, *sources])
        text = command("simulation", [SIM / "vsim.exe", "-batch", "-syncio", "-quiet",
                                       "-lib", lib.name, "tb_pcb_key1_report", "-do",
                                       "onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f"],
                       MARKER)
        status = "PASS"
        error = None
    except Exception as exc:
        status = "FAIL"
        error = str(exc)
        text = ""

    result = {
        "status": status,
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "hardware": "NOT_RUN",
        "physical_synthesis_route": "NOT_RUN",
        "scope": [
            "Actual secondary_top report/cache/admission always block with the production KEY1 debounce and key1 job guard.",
            "CNN, PCB, reporter, DDR, HXA, Ethernet and transport datapath leaves are controlled interfaces.",
            "Checks delayed PCB report, PCB snapshot replacement, KEY1 single admission, CNN purpose behavior, no-target, cancel/KEY4 invalidation and explicit Type20 independence.",
        ],
        "source_hashes": source_hashes,
        "commands": commands,
        "simulation_records": [line.strip("# ") for line in text.splitlines()
                               if "PASS " in line or "FAIL " in line],
        "error": error,
    }
    (output / "RESULTS.json").write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n",
                                          encoding="utf-8")
    print(json.dumps({"status": status, "output": str(output), "error": error}, ensure_ascii=False))
    if status != "PASS":
        raise SystemExit(1)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
    output = args.output or ROOT / "reports/retrained/key1_pcb" / stamp
    output = output.resolve()
    if not output.is_relative_to(ROOT / "reports/retrained/key1_pcb"):
        raise RuntimeError("output must stay under this variant's reports/retrained/key1_pcb")
    run(output)


if __name__ == "__main__":
    main()
