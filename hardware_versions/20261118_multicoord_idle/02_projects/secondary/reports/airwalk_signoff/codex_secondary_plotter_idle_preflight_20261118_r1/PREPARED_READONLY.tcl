# Import/read/report only. No constraint reload or implementation command.
set build {E:/codex_secondary_plotter_idle_preflight_20261118_r1/runs/phy_1}
set audit {E:/codex_secondary_plotter_idle_preflight_20261118_r1/signoff/readonly}
set name {secondary_cnn_multibox}
cd $build
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project "$build/$name.al" -single_run
    load_run_param -run syn_1
    import_db "$build/${name}_pr.db"
    update_timing -mode final

    source {../../04_pin/apply_reset_exceptions.tcl}
    source {../../04_pin/apply_cdc_exceptions.tcl}
    lassign [secondary_verify_reset_mapping preview_readonly] reset_targets reset_records
    lassign [secondary_verify_cdc_mapping preview_readonly] groups records
    set proof [open "$audit/current_cdc_mapping.rpt" w]
    puts $proof "CURRENT_PHYSICAL_CDC_READONLY_PASS"
    puts $proof "RESET_TARGETS [llength $reset_targets]"
    puts $proof "RESET_SYNCHRONIZERS [llength [secondary_reset_specs]]"
    foreach group [lsort [dict keys $groups]] {puts $proof "GROUP $group [llength [dict get $groups $group]]"}
    foreach row $reset_records {puts $proof "RESET_PROOF $row"}
    foreach row $records {puts $proof "CDC_PROOF $row"}
    close $proof

    report_timing_status -file "$audit/readonly.ts"
    report_timing_summary -file "$audit/readonly.timing"
    report_timing_exception -ep_num 4096 -path_num 4 -file "$audit/readonly.exceptions"
    check_timing -verbose -file "$audit/readonly.check"
    report_area -io_info -file "$audit/readonly.area"
    report_clock_utilization -file "$audit/readonly.clocks"
    report_drc -no_waivers -verbose -file "$audit/readonly.drc"
    report_path_skew -no_detailed_paths -file "$audit/readonly.skew"
    puts "RAW_CHECK_DESIGN_STATUS=[catch {check_design} raw_design_reason] REASON=$raw_design_reason"
    puts "CHECK_IO_STATUS=[catch {check_io} io_reason] REASON=$io_reason"
    puts "CHECK_PLB_STATUS=[catch {check_plb_attr -file "$audit/readonly.plb_check"} plb_reason] REASON=$plb_reason"
    export_sdc -file "$audit/readonly.exported.sdc"
    export_adc -verbose -file "$audit/readonly.exported.adc"
    export_io -verbose -file "$audit/readonly.io"
    set sites [open "$audit/readonly.sites.tsv" w]
    set expected [open "$audit/expected_slice_cells.tsv" w]
    puts $sites "cell\tref_name\tis_placed\tcol\trow\toffset"
    puts $expected "cell\tref_name"
    set l_count 0
    set m_count 0
    foreach cell [get_cells -quiet -hier *] {
        set ref [get_property -quiet REF_NAME $cell]
        puts $sites "$cell\t$ref\t[get_property -quiet IS_PLACED $cell]\t[get_property -quiet PLACED_COL $cell]\t[get_property -quiet PLACED_ROW $cell]\t[get_property -quiet PLACED_OFFSET $cell]"
        if {$ref eq "PH1P_PHY_LSLICE" || $ref eq "PH1P_PHY_MSLICE"} {
            puts $expected "$cell\t$ref"
            if {$ref eq "PH1P_PHY_LSLICE"} {incr l_count} else {incr m_count}
        }
    }
    close $sites
    close $expected
    puts "EXPECTED_SLICE_COUNTS L=$l_count M=$m_count"
    puts READONLY_EXPECTED_SLICE_EXPORT_DONE
    foreach tile {x31y49 x15y64 x2y1 x31y1 x9y1 x2y40 x9y40} {
        puts "TILE_QUERY_BEGIN $tile"
        puts "TILE_QUERY_STATUS=[catch {report_tile $tile} tile_reason]"
        puts "TILE_QUERY_END"
    }
    flow_status -file "$audit/readonly.flow"
    puts TD_READONLY_REIMPORT_PASS
} reason]} {
    puts "TD_READONLY_REIMPORT_FAIL: $reason"
    exit 1
}
exit 0
