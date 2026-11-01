"""Run focused KEY1 ownership, HXA cancel classification and RX FIFO RTL tests."""
from pathlib import Path
import argparse
import os
import re
import subprocess
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "stability_Runs_20261026" / "phy_1"
TOOLS = Path("E:/model/win64")
TESTS = [
    ROOT / "shared/tests/tb_grbl_key1_job_guard.sv",
    ROOT / "shared/tests/tb_hxa_job_cancel_classification.sv",
    ROOT / "shared/tests/tb_hxa_packet_rx_fifo4.sv",
]
EXPECTED = {
    "tb_grbl_key1_job_guard": "PASS KEY1 job guard:",
    "tb_hxa_job_cancel_classification": "PASS: lease expiry and ordinary HXD1 CANCEL are transport-only; explicit Type11 cancels job",
    "tb_hxa_packet_rx_fifo4": "PASS FIFO4:",
}


def active_files():
    text = (RUN / "secondary_cnn_multibox.al").read_text(encoding="utf-8-sig")
    text = re.sub(r"&(?!amp;|lt;|gt;|quot;|apos;|#\d+;)", "&amp;", text)
    text = text.replace("::", "_TD_DOUBLE_COLON_")
    tree = ET.fromstring(text)
    files = []
    for section in tree.findall("./Source_Files/*"):
        for entry in section.findall("File"):
            path = (RUN / entry.attrib["Path"]).resolve()
            if path.suffix.lower() in {".v", ".sv", ".vh", ".svh"} and path.is_file():
                files.append(path)
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out-dir", type=Path,
                        default=ROOT / "02_sim" / "key1_network_regression_20261026")
    args = parser.parse_args()
    out = args.out_dir.resolve()
    if not out.is_relative_to(ROOT / "02_sim"):
        raise SystemExit("regression output must stay under 02_sim")
    out.mkdir(parents=True, exist_ok=True)
    library = out / "work"
    if library.exists():
        import shutil
        shutil.rmtree(library)
    env = os.environ.copy()
    env["MGLS_LICENSE_FILE"] = str(TOOLS / "LICENSE.TXT")
    env["LM_LICENSE_FILE"] = str(TOOLS / "LICENSE.TXT")

    def run(command, log_name):
        result = subprocess.run([str(value) for value in command], cwd=out, env=env,
                                text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT)
        output = result.stdout
        (out / log_name).write_text(output, encoding="utf-8", errors="replace")
        if result.returncode:
            raise SystemExit(f"failed: {command}\n{output[-4000:]}")
        return output

    run([TOOLS / "vlib.exe", library], "vlib.log")
    sources = active_files() + [ROOT / "02_sim/testmodels/ph1p_logic_eram_stub.sv"] + TESTS
    compile_output = run([TOOLS / "vlog.exe", "-sv", "-lint", "-work", library, *sources], "vlog.log")
    if re.search(r"\*\*\s+(?:Error|Fatal):", compile_output):
        raise SystemExit("ModelSim lint reported an error")

    summary = []
    for test, marker in EXPECTED.items():
        output = run([TOOLS / "vsim.exe", "-c", "-lib", "work", test,
                      "-do", "onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -f"],
                     f"{test}.log")
        if marker not in output or re.search(r"\*\*\s+(?:Error|Fatal):", output):
            raise SystemExit(f"{test} did not report its expected PASS marker\n{output[-4000:]}")
        summary.append(f"{test}: PASS")
    (out / "RESULTS.txt").write_text("\n".join(summary) + "\n", encoding="ascii")
    print("\n".join(summary))


if __name__ == "__main__":
    main()
