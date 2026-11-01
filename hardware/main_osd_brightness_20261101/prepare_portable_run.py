"""Prepare an isolated TD work directory; does not run TD or bitgen."""
from pathlib import Path
import os,re,shutil
root=Path(__file__).resolve().parent
entry='camera_to_dsi_display_720p60_cnn_multibox.al'
run=root/'01_rtl/imgq_gain_m/main/build_portable'
assert not run.exists(),f'Output exists: {run}'
al=(root/entry).read_text(encoding='utf-8-sig')
def repl(m):
 p=(root/m.group(1)).resolve(); assert p.is_file() and root in p.parents
 return '<File Path="'+os.path.relpath(p,run).replace('\\','/')+'"'
al=re.sub(r'<File\s+Path="([^"]+)"',repl,al)
run.mkdir()
(run/entry).write_text(al,encoding='utf-8-sig')
for name in ['osd_compact_glyphs.vh','horizontal.mem','vertical.mem','ddrphy_cfg_rom.txt']:
 shutil.copy2(root/name,run/name)
evidence=root/'artifacts/evidence/final_build'
for stage in ['synth','place','route']:
 name=f'run_compact_{stage}.tcl'
 text=(evidence/name).read_text(encoding='utf-8-sig')
 text=text.replace('bitgen -bit $prj_name.bit','error "Bitgen disabled in portable preparation scripts; review all gates before generating a new bit"')
 (run/name).write_text(text,encoding='utf-8')
print('PREPARED_ONLY',run)
print('Open the AL in TD, or open this project in a TD command context and source run_compact_synth.tcl, then place, then route. No tool has been executed.')
