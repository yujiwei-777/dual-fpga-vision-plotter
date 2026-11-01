# No-histogram OSD variant — 2026-10-31

Source: main_osd_chinese_compact_20261030; independent copy: main_osd_chinese_no_hist_20261031.

## RTL change

Only 01_rtl/imgq_gain_m/main/user_source/hdl_source/osd_compact_panel.v was changed in the copied RTL tree. The upper right mode row keeps its existing panel bounds, 20-cell geometry, mode text (cells 0–4), colors, and two-cycle video pipeline. Cells 7–10 (the 直方图 label) and cells 11–13 (the he_on ON/OFF indicator) now emit ASCII spaces for every he_on value. The module port remains unchanged.

The panel unit reference is in reports/panel_unit_no_hist/tb_osd_compact_panel.v; it checks cells 7–13 with he_on=1 and he_on=0 and retains the existing mode, geometry, decimal, motion, PCB, and pipeline checks.

## Verification

- vlog ModelSim SE-64 2020.4: pass, 0 errors, 0 warnings (reports/panel_unit_no_hist/compile_no_hist.log).
- vsim -c ... -do "run -all; quit -f": pass, 74,186 checks, 0 errors, 0 warnings (reports/panel_unit_no_hist/transcript_no_hist.log).
- Full TD synthesis/implementation was intentionally not run pending root-agent confirmation.

## SHA256

- Baseline RTL (main_osd_chinese_compact_20261030): BE43004C5DE76568CD5C686984E4933EA958106D31860AE2B68A060B8B5B02F7
- Variant RTL (main_osd_chinese_no_hist_20261031): 3FDAF50C6FE27C2E158FEB037D63E8E37783F08938928B70D81339820C46BEC3

Machine-readable hashes are in reports/no_hist_hashes.json.
