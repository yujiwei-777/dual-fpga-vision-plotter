from pathlib import Path
import os
import subprocess
import sys
import argparse
import xml.etree.ElementTree as ET
import re


ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--run-dir", type=Path, default=ROOT / "build_Runs_20261023" / "phy_1")
parser.add_argument("--out-dir", type=Path, default=ROOT / "02_sim" / "active_lint_20261023")
args = parser.parse_args()
RUN = args.run_dir.resolve()
OUT = args.out_dir.resolve()
LIB = OUT / "work"
TOOLS = Path("E:/model/win64")


def active_files():
    text = (RUN / "secondary_cnn_multibox.al").read_text(encoding="utf-8-sig")
    text = re.sub(r"&(?!amp;|lt;|gt;|quot;|apos;|#\d+;)", "&amp;", text)
    text = text.replace("::", "_TD_DOUBLE_COLON_")
    tree = ET.fromstring(text)
    result = []
    for section in tree.findall("./Source_Files/*"):
        for entry in section.findall("File"):
            path = (RUN / entry.attrib["Path"]).resolve()
            if path.suffix.lower() in {".v", ".sv", ".vh", ".svh"} and path.is_file():
                result.append(path)
    return result


OUT.mkdir(parents=True, exist_ok=True)
if LIB.exists():
    import shutil
    shutil.rmtree(LIB)
env = os.environ.copy()
env["MGLS_LICENSE_FILE"] = str(TOOLS / "LICENSE.TXT")
env["LM_LICENSE_FILE"] = str(TOOLS / "LICENSE.TXT")
files = active_files()
with (OUT / "vlib.log").open("w", encoding="utf-8") as log:
    result = subprocess.run([str(TOOLS / "vlib.exe"), str(LIB)], cwd=OUT, env=env,
                            stdout=log, stderr=subprocess.STDOUT)
if result.returncode:
    raise SystemExit(result.returncode)
with (OUT / "vlog.log").open("w", encoding="utf-8") as log:
    result = subprocess.run([str(TOOLS / "vlog.exe"), "-sv", "-lint", "-work", str(LIB),
                             *[str(path) for path in files]], cwd=OUT, env=env,
                            stdout=log, stderr=subprocess.STDOUT)
text = (OUT / "vlog.log").read_text(encoding="utf-8", errors="replace")
(OUT / "summary.txt").write_text(f"returncode={result.returncode} files={len(files)}\n" + text[-4000:], encoding="utf-8")
print(f"returncode={result.returncode} files={len(files)}")
print(text[-4000:])
raise SystemExit(result.returncode)
