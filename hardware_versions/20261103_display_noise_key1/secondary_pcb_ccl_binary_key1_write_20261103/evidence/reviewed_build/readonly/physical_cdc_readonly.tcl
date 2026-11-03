# Re-prove physical CDC/FIFO/mailbox connectivity on the routed database.
# This script only imports the routed DB and reads mapped objects/properties.
# It does not apply constraints or write/save/export the implementation DB.
set build {E:/codex_pcb_binary_ccl_retrained_20261103_key1}
set phy "$build/runs/phy_1"
set audit "$build/readonly"
set name {secondary_cnn_multibox}
cd $phy
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project "$phy/$name.al" -noanalyze
    import_db "$phy/${name}_pr.db"
    update_timing -mode final
    source {../../04_pin/apply_reset_exceptions.tcl}
    source {../../04_pin/apply_cdc_exceptions.tcl}
    lassign [secondary_verify_reset_mapping route_end] reset_targets reset_records
    lassign [secondary_verify_cdc_mapping route_end] groups records
    set out [open "$audit/physical_cdc_readonly.rpt" w]
    puts $out "PHYSICAL_CDC_READONLY_PASS"
    puts $out "ROUTED_DB $phy/${name}_pr.db"
    puts $out "RESET_TARGETS [llength $reset_targets]"
    puts $out "RESET_SYNCHRONIZERS [llength [secondary_reset_specs]]"
    foreach group [lsort [dict keys $groups]] {
        puts $out "GROUP $group [llength [dict get $groups $group]]"
    }
    foreach record $reset_records {puts $out "RESET_PROOF $record"}
    foreach record $records {puts $out "CDC_PROOF $record"}
    close $out
    puts "PHYSICAL_CDC_READONLY_PASS"
    puts "RESET_TARGETS [llength $reset_targets]"
    puts "CDC_GROUPS [dict size $groups]"
} reason]} {
    catch {close $out}
    puts "PHYSICAL_CDC_READONLY_FAIL: $reason"
    exit 1
}
exit 0
