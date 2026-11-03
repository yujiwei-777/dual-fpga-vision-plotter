# Read-only routed-database audit. No clear_sdc/read_sdc, export_db,
# place, route, optimize, bitgen or project-save commands are permitted here.
set build {D:/program/fpga/lab_ex3_osd_SC500_720P/main_display_noise_fix_20261103/01_rtl/imgq_gain_m/main/td_project_display_noise_v8}
set audit {D:/program/fpga/lab_ex3_osd_SC500_720P/main_display_noise_fix_20261103/02_sim/display_noise_readonly}
set name {camera_to_dsi_display_720p60_cnn_multibox}
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

    report_drc -no_waivers -verbose -file {D:/program/fpga/lab_ex3_osd_SC500_720P/main_display_noise_fix_20261103/02_sim/display_noise_readonly/readonly.drc}
    report_path_skew -no_detailed_paths -file {D:/program/fpga/lab_ex3_osd_SC500_720P/main_display_noise_fix_20261103/02_sim/display_noise_readonly/readonly.skew}
    puts "RAW_CHECK_DESIGN_STATUS=[catch {check_design} raw_design_reason] REASON=$raw_design_reason"
    puts "CHECK_IO_STATUS=[catch {check_io} io_reason] REASON=$io_reason"
    puts "CHECK_PLB_STATUS=[catch {check_plb_attr -file {D:/program/fpga/lab_ex3_osd_SC500_720P/main_display_noise_fix_20261103/02_sim/display_noise_readonly/readonly.plb_check}} plb_reason] REASON=$plb_reason"
    export_sdc -file {D:/program/fpga/lab_ex3_osd_SC500_720P/main_display_noise_fix_20261103/02_sim/display_noise_readonly/readonly.exported.sdc}
    export_adc -verbose -file {D:/program/fpga/lab_ex3_osd_SC500_720P/main_display_noise_fix_20261103/02_sim/display_noise_readonly/readonly.exported.adc}
    export_io -verbose -file {D:/program/fpga/lab_ex3_osd_SC500_720P/main_display_noise_fix_20261103/02_sim/display_noise_readonly/readonly.io}
    set sites [open {D:/program/fpga/lab_ex3_osd_SC500_720P/main_display_noise_fix_20261103/02_sim/display_noise_readonly/readonly.sites.tsv} w]
    set expected [open {D:/program/fpga/lab_ex3_osd_SC500_720P/main_display_noise_fix_20261103/02_sim/display_noise_readonly/expected_slice_cells.tsv} w]
    puts $sites "cell	ref_name	is_placed	col	row	offset"
    puts $expected "cell	ref_name"
    set l_count 0
    set m_count 0
    foreach cell [get_cells -quiet -hier *] {
        set ref [get_property -quiet REF_NAME $cell]
        puts $sites "$cell	$ref	[get_property -quiet IS_PLACED $cell]	[get_property -quiet PLACED_COL $cell]	[get_property -quiet PLACED_ROW $cell]	[get_property -quiet PLACED_OFFSET $cell]"
        if {$ref eq "PH1P_PHY_LSLICE" || $ref eq "PH1P_PHY_MSLICE"} {
            puts $expected "$cell	$ref"
            if {$ref eq "PH1P_PHY_LSLICE"} {incr l_count} else {incr m_count}
        }
    }
    close $sites
    close $expected
    puts "EXPECTED_SLICE_COUNTS L=$l_count M=$m_count"
    puts READONLY_EXPECTED_SLICE_EXPORT_DONE

    puts TD_READONLY_REIMPORT_PASS
} reason]} {
    puts "TD_READONLY_REIMPORT_FAIL: $reason"
    exit 1
}
exit 0
