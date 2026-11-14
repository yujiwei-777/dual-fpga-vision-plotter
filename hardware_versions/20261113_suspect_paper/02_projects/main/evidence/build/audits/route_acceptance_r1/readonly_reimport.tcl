# Read-only routed-database audit. No clear_sdc/read_sdc, export_db,
# place, route, optimize, bitgen or project-save commands are permitted here.
set build {E:/codex_pcb_suspect_center_main_20261113_r4/01_rtl/imgq_gain_m/main/td_project_display_noise_v8}
set audit {E:/codex_pcb_suspect_center_main_20261113_r4/audits/route_acceptance_r1}
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

    # Fresh current-routed-database exports; device topology is reference-only.
    set expected [open "$audit/expected_slice_cells.tsv" w]
    puts $expected "cell\tref_name"
    set l_count 0
    set m_count 0
    foreach cell [get_cells -quiet -hier *] {
        set ref [get_property -quiet REF_NAME $cell]
        if {$ref eq "PH1P_PHY_LSLICE" || $ref eq "PH1P_PHY_MSLICE"} {
            puts $expected "$cell\t$ref"
            if {$ref eq "PH1P_PHY_LSLICE"} {incr l_count} else {incr m_count}
        }
    }
    close $expected
    puts "EXPECTED_SLICE_COUNTS L=$l_count M=$m_count"
    puts READONLY_EXPECTED_SLICE_EXPORT_DONE
    set sites [open "$audit/readonly.sites.tsv" w]
    puts $sites "cell\tref_name\tis_placed\tcol\trow\toffset"
    foreach cell [get_cells -quiet -hier *] {
        set ref [get_property -quiet REF_NAME $cell]
        puts $sites "$cell\t$ref\t[get_property -quiet IS_PLACED $cell]\t[get_property -quiet PLACED_COL $cell]\t[get_property -quiet PLACED_ROW $cell]\t[get_property -quiet PLACED_OFFSET $cell]"
    }
    close $sites
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
