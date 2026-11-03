"""Independent PCB companion paths; never import stale OSD release claims."""
from pathlib import Path
import hashlib
import json
ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT.parent / 'main_osd_brightness_20261101'
NAME = 'camera_to_dsi_display_720p60_cnn_multibox'
RUN = ROOT / '01_rtl/imgq_gain_m/main/td_project_pcb_auto_v2'
AUDIT = ROOT / '02_sim/pcb_compat_readonly'
CONTEXT = ROOT / '02_sim/pcb_compat_standard_context'
BIT = ROOT / 'artifacts/dual_fpga_main_20261101_pcb_auto_compat_diagnostic.bit'
BASEBIT = BASE / 'artifacts/dual_fpga_main_20261101_osd_brightness_diagnostic.bit'
BASESHA = 'FB3FE4F57721C7068821EC0C010D589CB82398E6F38CCCF3F7892006033E5515'
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p): return Path(p).read_text(encoding='utf-8-sig', errors='strict')
def obj(p): return json.loads(read(p))
def put(p, value):
    Path(p).parent.mkdir(parents=True, exist_ok=True)
    Path(p).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
