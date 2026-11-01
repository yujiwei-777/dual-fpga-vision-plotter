# Read-only routed-database audit. No clear_sdc/read_sdc, export_db,
# place, route, optimize, bitgen or project-save commands are permitted here.
set build {D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_doc_dirt_lowconf_factored_20261101/dirt_lowconf_factored_Runs_20261101/phy_1}
set audit {D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_doc_dirt_lowconf_factored_20261101/02_sim/dirt_lowconf_factored_Runs_20261101_readonly}
set name {secondary_cnn_multibox}
cd $build
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project "$build/$name.al" -noanalyze
    import_db "$build/${name}_pr.db"
    update_timing -mode final
    report_timing_status -file "$audit/readonly.ts"
    report_timing_summary -file "$audit/readonly.timing"
    report_timing_exception -file "$audit/readonly.exceptions"
    check_timing -verbose -file "$audit/readonly.check"
    report_area -io_info -file "$audit/readonly.area"
    report_clock_utilization -file "$audit/readonly.clocks"
    flow_status -file "$audit/readonly.flow"
    puts TD_READONLY_REIMPORT_PASS
} reason]} {
    puts "TD_READONLY_REIMPORT_FAIL: $reason"
    exit 1
}
exit 0
