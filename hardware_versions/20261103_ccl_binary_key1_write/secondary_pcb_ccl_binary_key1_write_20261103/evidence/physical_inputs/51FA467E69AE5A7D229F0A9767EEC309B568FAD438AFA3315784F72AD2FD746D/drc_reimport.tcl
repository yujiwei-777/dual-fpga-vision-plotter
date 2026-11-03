# Read-only DRC audit of the frozen routed database.
set build {E:/codex_pcb_binary_ccl_retrained_20261103_key1/runs/phy_1}
set audit {E:/codex_pcb_binary_ccl_retrained_20261103_key1/readonly}
set name {secondary_cnn_multibox}
cd $build
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project "$build/$name.al" -noanalyze
    import_db "$build/${name}_pr.db"
    report_drc -no_waivers -verbose -file "$audit/routed.drc"
    puts TD_READONLY_DRC_PASS
} reason]} {
    puts "TD_READONLY_DRC_FAIL: $reason"
    exit 1
}
exit 0
