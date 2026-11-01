from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
OLD = "csq5_s_joint_model_key1_fast_roi_linkfix4_classid_fix"
NEW = "csq5_s_joint_model_key1_fast_roi_linkfix4_classid_fix_retrained"

for path in ROOT.rglob("*"):
    if path == Path(__file__) or not path.is_file() or path.suffix.lower() not in {".al", ".tcl", ".json", ".md", ".py", ".status", ".txt"}:
        continue
    try:
        source = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        continue
    updated = re.sub(r"classid_fix(?:_retrained)+", "classid_fix_retrained", source)
    updated = updated.replace(OLD + "/", NEW + "/").replace(OLD + "\\\\", NEW + "\\\\")
    updated = updated.replace("td_project_classid_fix", "td_project_retrained")
    if updated != source:
        path.write_text(updated, encoding="utf-8")

for old_name in ("td_project_classid_fix_build", "td_project_classid_fix_resume", "td_project_classid_fix_selected"):
    old_path = ROOT / old_name
    new_path = ROOT / old_name.replace("td_project_classid_fix", "td_project_retrained")
    if old_path.exists() and not new_path.exists():
        old_path.rename(new_path)

control_bit = ROOT / "artifacts" / "dual_fpga_secondary_20261018_fast_roi_linkfix4_classid_fix_diagnostic.bit"
if control_bit.exists():
    control_bit.unlink()

print(f"prepared independent variant: {ROOT}")
