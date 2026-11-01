from pathlib import Path
import os
import shutil
import subprocess
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
syn = root / "shared_ram_Runs_20261023d" / "syn_1"
al = syn / "secondary_cnn_multibox.al"
out = root / "02_sim" / "shared_ram_lint_20261023"
if out.exists(): shutil.rmtree(out)
out.mkdir(parents=True)
lib = out / "lint_work"
env = os.environ.copy()
env["MGLS_LICENSE_FILE"] = r"E:\model\win64\LICENSE.TXT"
env["LM_LICENSE_FILE"] = r"E:\model\win64\LICENSE.TXT"
subprocess.run([r"E:\model\win64\vlib.exe", str(lib)], cwd=out, env=env, check=True,
               stdout=(out / "vlib.log").open("w"), stderr=subprocess.STDOUT)
tree = ET.parse(al).getroot()
files=[]
for group in tree.find("Source_Files"):
    for ent in group.findall("File"):
        p = (syn / ent.attrib["Path"]).resolve()
        if p.exists(): files.append(str(p))
log = (out / "vlog.log").open("w")
proc = subprocess.run([r"E:\model\win64\vlog.exe", "-sv", "-lint", "-work", str(lib), *files],
                      cwd=out, env=env, stdout=log, stderr=subprocess.STDOUT)
log.close()
print(f"exit={proc.returncode} files={len(files)} log={out/'vlog.log'}")
print((out / "vlog.log").read_text(errors="replace")[-12000:])
raise SystemExit(proc.returncode)
