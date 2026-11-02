# Standard bitgen only; no unconstr_io or other parameter override.
set build {D:/program/fpga/lab_ex3_osd_SC500_720P/main_pcb_auto_compat_20261101/01_rtl/imgq_gain_m/main/td_project_pcb_auto_v2}
set name {camera_to_dsi_display_720p60_cnn_multibox}
set bitfile {D:/program/fpga/lab_ex3_osd_SC500_720P/main_pcb_auto_compat_20261101/artifacts/dual_fpga_main_20261101_pcb_auto_compat_diagnostic.bit}
cd $build
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project "$build/$name.al" -single_run
    load_run_param -run syn_1
    import_db "$build/${name}_pr.db"
    bitgen -bit $bitfile
    puts "PCB_COMPAT_BITGEN_PASS: $bitfile"
} reason]} {
    puts "PCB_COMPAT_BITGEN_FAIL: $reason"
    exit 1
}
exit 0
