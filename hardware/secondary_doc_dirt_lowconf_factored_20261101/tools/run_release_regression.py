from pathlib import Path
import os
import shutil
import subprocess
import argparse


ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--out-dir", type=Path,
                    default=ROOT / "02_sim" / "release_regression_20261023")
args = parser.parse_args()
OUT = args.out_dir.resolve()
if not OUT.is_relative_to(ROOT / "02_sim"):
    raise SystemExit("regression output must stay under 02_sim")
TOOLS = Path("E:/model/win64")
LIB = OUT / "work"


def run(command, log):
    env = os.environ.copy()
    env["MGLS_LICENSE_FILE"] = str(TOOLS / "LICENSE.TXT")
    env["LM_LICENSE_FILE"] = str(TOOLS / "LICENSE.TXT")
    result = subprocess.run([str(item) for item in command], cwd=OUT, env=env,
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    log.write_text(result.stdout, encoding="utf-8", errors="replace")
    if result.returncode:
        raise SystemExit(f"failed: {command}\n{result.stdout[-5000:]}")
    return result.stdout


OUT.mkdir(parents=True, exist_ok=True)
if LIB.exists():
    shutil.rmtree(LIB)
run([TOOLS / "vlib.exe", "work"], OUT / "vlib.log")

rtl = [
    ROOT / "01_rtl/grbl_decimal.v", ROOT / "01_rtl/grbl_line_formatter.v",
    ROOT / "01_rtl/grbl_reporter.v", ROOT / "01_rtl/grbl_response_parser.v",
    ROOT / "01_rtl/grbl_streamer.v", ROOT / "01_rtl/grbl_key2_test_ctrl.v",
    ROOT / "01_rtl/grbl_stroke_rom.v",
    ROOT / "01_rtl/grbl_vector_font_rom.v",
    # The UART port and RX are defined together in grbl_uart.v.  The KEY2
    # controller lives in secondary_top.v; compiling the source also keeps
    # this regression tied to the implementation used by the build.
    ROOT / "01_rtl/grbl_uart.v", ROOT / "01_rtl/secondary_top.v",
    ROOT / "01_rtl/doc_grbl_map.v",
    ROOT / "01_rtl/doc_grbl_plotter.v", ROOT / "01_rtl/doc_grbl_response_parser.v",
    ROOT / "01_rtl/doc_grbl_streamer.v", ROOT / "shared/rtl/hxa_packet_rx_fifo4.v",
    ROOT / "01_rtl/hxa_packet_rx.v", ROOT / "shared/rtl/hxa_packet_codec.v",
    ROOT / "shared/rtl/hxa_secondary_link.v", ROOT / "main/user_source/hdl_source/reset_sync.v",
]
tbs = [
    ROOT / "02_sim/doc_plotter/tb_grbl_reporter_key2.sv",
    ROOT / "02_sim/doc_plotter/tb_grbl_key2_test_ctrl.sv",
    ROOT / "02_sim/doc_plotter/tb_doc_grbl_uart_priority.sv",
    ROOT / "02_sim/doc_plotter/tb_doc_grbl_streamer_timers.sv",
    ROOT / "02_sim/doc_plotter/tb_doc_grbl_plotter.sv",
    ROOT / "02_sim/doc_plotter/tb_doc_grbl_map.sv",
    ROOT / "shared/tests/tb_hxa_packet_rx_fifo4.sv",
]
test_models = [ROOT / "02_sim/testmodels/ph1p_logic_eram_stub.sv"]
files = test_models + [path for path in rtl + tbs if path.is_file()]
compile_log = OUT / "vlog.log"
run([TOOLS / "vlog.exe", "-sv", "-lint", "-work", "work", *files], compile_log)

tests = [
    "tb_grbl_key2_test_ctrl", "tb_grbl_reporter_key2",
    "tb_doc_grbl_uart_priority", "tb_doc_grbl_streamer_timers",
    "tb_doc_grbl_plotter", "tb_doc_grbl_map", "tb_hxa_packet_rx_fifo4",
]
results = {}
for test in tests:
    output = run([TOOLS / "vsim.exe", "-c", "-lib", "work", test,
                  "-do", "onerror {quit -code 1}; run -all; quit -f"], OUT / f"{test}.log")
    results[test] = [line for line in output.splitlines() if "PASS" in line or "Errors:" in line]
(OUT / "RESULTS.txt").write_text("\n".join(f"{name}: {lines}" for name, lines in results.items()) + "\n", encoding="utf-8")
print(results)
