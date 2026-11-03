# Isolated area-only gate comparison. No product constraint or physical run.
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project module_area.al -single_run
    load_run_param -run syn_1
    set_param gate pack_effort high
    commit_param -step design
    elaborate -top module_area_top
    export_db module_area_elaborate.db
    commit_param -step rtl
    optimize_rtl
    report_area -file module_area_rtl.area
    commit_param -step gate
    optimize_gate -packarea module_area_gate.area
    legalize_phy_inst
    report_area -verbose -file module_area_after_legalize.area
    export_db module_area_gate.db
    set done [open .module_gate.end.f w]
    close $done
    puts MODULE_AREA_GATE_PASS
} reason]} {
    set failed [open .module_gate.error.f w]
    puts $failed $reason
    close $failed
    puts "MODULE_AREA_GATE_FAIL: $reason"
    exit 1
}
exit 0
