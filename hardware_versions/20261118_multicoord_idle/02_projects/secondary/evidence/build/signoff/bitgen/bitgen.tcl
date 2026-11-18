# Standard diagnostic bitgen. No constraint or IO overrides.
set build {E:/codex_secondary_plotter_idle_preflight_20261118_r2/runs/phy_1}
set audit {E:/codex_secondary_plotter_idle_preflight_20261118_r2/signoff/bitgen}
set name {secondary_cnn_multibox}
set bit {E:/codex_secondary_plotter_idle_preflight_20261118_r2/signoff/bitgen/dual_fpga_secondary_20261118_plotter_idle_preflight_diagnostic.bit}
set bid {E:/codex_secondary_plotter_idle_preflight_20261118_r2/signoff/bitgen/dual_fpga_secondary_20261118_plotter_idle_preflight_diagnostic.bid}
cd $build
if {[file exists $bit] || [file exists $bid]} {error "Refusing existing output"}
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project "$build/$name.al" -noanalyze
    import_db "$build/${name}_pr.db"
    update_timing -mode final
    report_timing_status -file "$audit/pre_bitgen.ts"
    report_timing_summary -file "$audit/pre_bitgen.timing"
    check_timing -verbose -file "$audit/pre_bitgen.check"
    report_area -io_info -file "$audit/pre_bitgen.area"
    commit_param -step bitgen
    bitgen -bit $bit
    if {![file exists $bit] || [file size $bit] < 1000000} {error "Missing/truncated bit"}
    export_bid $bid
    export_bitgen_param -file "$audit/checked_bitgen_param.f"
    puts AIRWALK_SECONDARY_BITGEN_PASS
} reason]} {
    puts "AIRWALK_SECONDARY_BITGEN_FAIL: $reason"
    exit 1
}
exit 0
