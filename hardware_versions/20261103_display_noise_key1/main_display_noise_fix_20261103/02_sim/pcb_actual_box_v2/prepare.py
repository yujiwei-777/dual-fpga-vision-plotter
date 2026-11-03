from pathlib import Path
import re
here = Path(__file__).resolve().parent
top = here.parents[1] / '01_rtl/imgq_gain_m/main/user_source/hdl_source/design_top_wrapper.v'
s = top.read_text(encoding='utf-8-sig')
assert '.PCB_RESULT_TIMEOUT_MS(30000)' in s
assert '.overlay_enable(S_sw2_px_s2 || S_mode_pcb_px)' in s
assert '.remote_clear(S_mode_pcb_eth && S_snap_capture_req)' in s
assert '.I_ovl_on        ( S_pcb_window_on || (S_ovl_on && !S_mode_text_px) )' in s
assert '.I_multi_valid   ( S_multi_px_valid && !S_pcb_window_on )' in s
parts = []
for pat in [r'    key4_pcb_status u_pcb_status\(.*?\);', r'    doc_copy_status_cdc u_pcb_status_cdc\(.*?\);', r'    hx_result_select u_result_select\(.*?\);', r'    wire S_pcb_window_on =.*?wire \[9:0\] S_box_cy =.*?;']:
    m = re.search(pat, s, re.S)
    assert m, pat
    parts.append(m.group(0))
(here / 'actual_top.vh').write_text('\n'.join(parts)+'\n', encoding='utf-8')
coords = re.search(r'    wire S_use_multi_box =.*?wire \[9:0\] S_box_cy =.*?;',s,re.S)
assert coords
(here/'actual_coords.vh').write_text(coords.group(0)+'\n',encoding='utf-8')
print('Actual top expressions/instances extracted; PCB timeout and SW2-independent overlay verified')
