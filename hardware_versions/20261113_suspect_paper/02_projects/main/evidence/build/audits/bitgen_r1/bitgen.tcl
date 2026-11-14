# Current routed DB -> fresh diagnostic staging only.
set build {E:/codex_pcb_suspect_center_main_20261113_r4/01_rtl/imgq_gain_m/main/td_project_display_noise_v8}
set audit {E:/codex_pcb_suspect_center_main_20261113_r4/audits/bitgen_r1}
set name {camera_to_dsi_display_720p60_cnn_multibox}
set bit {E:/codex_pcb_suspect_center_main_20261113_r4/audits/bitgen_r1/dual_fpga_main_20261113_pcb_suspect_center_diagnostic.bit}
set bid {E:/codex_pcb_suspect_center_main_20261113_r4/audits/bitgen_r1/dual_fpga_main_20261113_pcb_suspect_center_diagnostic.bid}
cd $build
if {[file exists $bit] || [file exists $bid]} {error "Refusing staged bit/BID overwrite"}
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project "$build/$name.al" -noanalyze
    import_db "$build/${name}_pr.db"
    update_timing -mode final
    report_timing_status -file "$audit/pre_bitgen.ts"
    report_timing_summary -file "$audit/pre_bitgen.timing"
    report_area -io_info -file "$audit/pre_bitgen.area"
    check_timing -verbose -file "$audit/pre_bitgen.check"
    commit_param -step bitgen
    bitgen -bit $bit
    if {![file exists $bit] || [file size $bit] < 100000} {error "Missing/truncated staged bit"}
    export_bid $bid
    if {![file exists $bid] || [file size $bid] < 100} {error "Missing/truncated staged BID"}
    export_bitgen_param -file "$audit/checked_bitgen_param.f"
    update_timing -mode final
    report_timing_summary -file "$audit/post_bitgen.timing"
    report_area -io_info -file "$audit/post_bitgen.area"
    set marker [open "$audit/bitgen.end.json" w]
    puts $marker "{\"status\":\"PASS\",\"bit_bytes\":[file size $bit],\"bid_bytes\":[file size $bid]}"
    close $marker
    puts TD_BITGEN_PASS
} reason]} {
    puts "TD_BITGEN_FAIL: $reason"
    exit 1
}
exit 0
