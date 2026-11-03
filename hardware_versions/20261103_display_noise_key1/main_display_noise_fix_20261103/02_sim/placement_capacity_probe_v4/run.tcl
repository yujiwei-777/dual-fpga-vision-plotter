# Read-only independent architecture/parameter probe.
set probe {D:/program/fpga/lab_ex3_osd_SC500_720P/main_display_noise_fix_20261103/02_sim/placement_capacity_probe_v4}
cd $probe
proc query {label script} {
    puts "PROBE_QUERY_BEGIN $label"
    set code [catch {uplevel 1 $script} result]
    puts "PROBE_QUERY_CATCH $label $code RESULT=$result"
    puts "PROBE_QUERY_END $label"
}
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project "$probe/camera_to_dsi_display_720p60_cnn_multibox.al" -single_run
    load_run_param -run syn_1
    import_db "$probe/camera_to_dsi_display_720p60_cnn_multibox_gate.db"
} reason]} {
    puts "PROBE_IMPORT_FAILED $reason"
    exit 1
}
query commands {
    foreach pattern {*field* *resource* *arch* *param* *pack* *report_tile* *help*} {
        puts "PROBE_COMMAND_PATTERN $pattern [lsort [info commands $pattern]]"
    }
}
query gate_params {report_param -stage gate -detail}
query place_params {report_param -stage place -detail}
query area {report_area -verbose -file "$probe/imported_gate_verbose.area"}
query help_arch {help query_current_arch}
query help_area {help report_area}
query help_param {help report_param}
query arch_default {query_current_arch -file "$probe/arch_default.txt"}
foreach kind {SLICEL SLICEM LUTL LUTM Plb Pmb PH1P_PHY_LSLICE PH1P_PHY_MSLICE} {
    query "arch_$kind" [list query_current_arch -type $kind -file "$probe/arch_$kind.txt"]
}
puts "READONLY_CAPACITY_PROBE_FINISHED"
exit 0
