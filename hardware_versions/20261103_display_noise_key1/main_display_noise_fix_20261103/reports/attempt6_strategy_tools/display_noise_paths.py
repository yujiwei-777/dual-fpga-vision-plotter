"""Paths for the independent display-noise variant."""
from pathlib import Path
import hashlib
import json
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'main_pcb_auto_compat_20261101'
NAME='camera_to_dsi_display_720p60_cnn_multibox'
RUN=ROOT/'01_rtl/imgq_gain_m/main/td_project_display_noise_v6'
AUDIT=ROOT/'02_sim/display_noise_readonly'
CONTEXT=ROOT/'02_sim/display_noise_standard_context'
BIT=ROOT/'artifacts/dual_fpga_main_20261103_display_noise_fix_diagnostic.bit'
BASEBIT=BASE/'artifacts/dual_fpga_main_20261101_pcb_auto_compat_diagnostic.bit'
BASESHA='B048D5BD30915F7C08791A9947D90982B741929E00CC0BE3036F7018C76209BC'
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p):
    raw=Path(p).read_bytes()
    return raw.decode('utf-16' if raw[:2] in (b'\xff\xfe',b'\xfe\xff') else 'utf-8-sig',errors='strict')
def obj(p): return json.loads(read(p))
def put(p,value):
    Path(p).parent.mkdir(parents=True,exist_ok=True)
    Path(p).write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
