set build {E:/codex_main_cnn_multicoord_20261118_r1/01_rtl/imgq_gain_m/main/td_project_display_noise_v8}
set audit {E:/codex_main_cnn_multicoord_20261118_r1/audits/bitgen_r1}
set name {camera_to_dsi_display_720p60_cnn_multibox}
set bit {E:/codex_main_cnn_multicoord_20261118_r1/audits/bitgen_r1/dual_fpga_main_20261118_cnn_multicoord_diagnostic.bit}
set bid {E:/codex_main_cnn_multicoord_20261118_r1/audits/bitgen_r1/dual_fpga_main_20261118_cnn_multicoord_diagnostic.bid}
cd $build
if {[file exists $bit] || [file exists $bid]} {error "Refusing existing output"}
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project "$build/$name.al" -noanalyze
    import_db "$build/${name}_pr.db"
    update_timing -mode final
    report_timing_summary -file "$audit/pre_bitgen.timing"
    report_area -io_info -file "$audit/pre_bitgen.area"
    check_timing -verbose -file "$audit/pre_bitgen.check"
    commit_param -step bitgen
    bitgen -bit $bit
    export_bid $bid
    export_bitgen_param -file "$audit/checked_bitgen_param.f"
    update_timing -mode final
    report_timing_summary -file "$audit/post_bitgen.timing"
    report_area -io_info -file "$audit/post_bitgen.area"
    puts NO_SUSPECT_MAIN_BITGEN_PASS
} reason]} {puts "NO_SUSPECT_MAIN_BITGEN_FAIL: $reason";exit 1}
exit 0
