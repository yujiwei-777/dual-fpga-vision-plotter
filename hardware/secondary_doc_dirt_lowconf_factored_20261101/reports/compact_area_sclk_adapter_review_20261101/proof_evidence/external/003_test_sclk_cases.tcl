proc add_sclk {cell input output} {
    dict set ::cells $cell 1
    dict set ::properties $cell [dict create TYPE AL_PHY_SCLK REF_NAME PH1P_PHY_SCLK_V2]
    dict set ::tables $cell "Property Type Read-only Value\nTYPE string true AL_PHY_SCLK\nREF_NAME string true PH1P_PHY_SCLK_V2"
    setpin "$cell.clkin" [list $input] 0
    setpin "$cell.ce" {} 0
    setpin [format {%s.dlytrim[0]} $cell] {} 0
    setpin [format {%s.dlytrim[1]} $cell] {} 0
    setpin "$cell.clkout" [list $output] 1
    dict set ::drivers $output [list "$cell.clkout"]
}
proc add_sclk_case {name mutation pass {operation {secondary_key3_clock_equivalent TEST sclk_output I_sys_clk}}} {
    add_case $name route "add_sclk test_sclk I_sys_clk_syn_11 sclk_output; $mutation" $operation $pass {SECONDARY_(KEY3_PROOF|RESET_MAPPING|CDC_MAPPING)_ERROR}
}
set sclk_operation {secondary_key3_clock_equivalent TEST sclk_output I_sys_clk}
add_sclk_case sclk_defaults_open {} 1
foreach {property value} {GSR ENABLE BYPASS ENABLE DELAY 0 DELAY_DYN DISABLE} {
    add_sclk_case sclk_explicit_$property [list prop test_sclk $property $value] 1
}
foreach {property value} {GSR DISABLE BYPASS DISABLE DELAY 1 DELAY_DYN ENABLE TYPE AL_PHY_GCLK REF_NAME PH1P_PHY_SCLK} {
    add_sclk_case sclk_wrong_$property [list prop test_sclk $property $value] 0
}
foreach property {TYPE REF_NAME} {
    add_sclk_case sclk_missing_$property [list drop_prop test_sclk $property] 0
}
add_sclk_case sclk_all_explicit {
    foreach {property value} {GSR ENABLE BYPASS ENABLE DELAY 0 DELAY_DYN DISABLE} {prop test_sclk $property $value}
} 1
add_sclk_case sclk_const_one_ce {
    dict set ::cells sclk_one 1
    dict set ::properties sclk_one [dict create TYPE one REF_NAME AL_CONST_ONE]
    setpin sclk_one.O {one_net} 1
    dict set ::drivers one_net {sclk_one.O}
    setpin test_sclk.ce {one_net} 0
} 1
add_sclk_case sclk_tie_vdd_ce {
    setpin x24y38_auto_const.vdd {vdd_net} 1
    dict set ::drivers vdd_net {x24y38_auto_const.vdd}
    setpin test_sclk.ce {vdd_net} 0
} 1
add_sclk_case sclk_zero_delay_pins {
    foreach bit {0 1} {setpin [format {test_sclk.dlytrim[%d]} $bit] {x24y38_auto_gnd} 0}
} 1
add_sclk_case sclk_ce_zero {setpin test_sclk.ce {x24y38_auto_gnd} 0} 0
add_sclk_case sclk_ce_dynamic {setpin test_sclk.ce {I_sys_clk_dup_1} 0} 0
foreach bit {0 1} {
    add_sclk_case sclk_delay_dynamic_$bit [list setpin [format {test_sclk.dlytrim[%d]} $bit] {I_sys_clk_dup_1} 0] 0
}
add_sclk_case sclk_ce_multiple_nets {setpin test_sclk.ce {I_sys_clk_dup_1 x24y38_auto_gnd} 0} 0
add_sclk_case sclk_ce_multiple_drivers {
    setpin test_sclk.ce {x24y38_auto_gnd} 0
    dict lappend ::drivers x24y38_auto_gnd rogue.o
} 0
add_sclk_case sclk_unknown_parameter {prop test_sclk CLK_DIV 2} 0
add_sclk_case sclk_unknown_lowercase_parameter {prop test_sclk clk_div 2} 0
add_sclk_case sclk_routed_metadata {prop test_sclk inferred normal; prop test_sclk need_deskew true} 1
add_sclk_case sclk_duplicate_lowercase_metadata {dict append ::tables test_sclk "\ninferred string false normal\ninferred string false normal"} 0
add_sclk_case sclk_bad_header {dict set ::tables test_sclk {wrong header}} 0
add_sclk_case sclk_duplicate_property {dict append ::tables test_sclk "\nBYPASS string true ENABLE\nBYPASS string true ENABLE"} 0
add_sclk_case sclk_extra_input {setpin test_sclk.select {} 0} 0
add_sclk_case sclk_extra_output {setpin test_sclk.other {} 1} 0
add_sclk_case sclk_extra_inout {setpin test_sclk.bidir {} 2} 0
foreach pin {ce clkin {dlytrim[0]} {dlytrim[1]} clkout} {
    add_sclk_case sclk_missing_pin_$pin "dict unset ::pin_net {test_sclk.$pin}; dict unset ::pin_dir {test_sclk.$pin}" 0
}
add_sclk_case sclk_duplicate_input {
    set inputs [get_pins -nowarn -filter {DIRECTION == input} -of {test_sclk}]
    dict set ::pin_override test_sclk {DIRECTION == input} [concat $inputs {test_sclk.ce}]
} 0
add_sclk_case sclk_bad_input_direction {dict set ::pin_dir test_sclk.ce 1} 0
add_sclk_case sclk_bad_output_direction {dict set ::pin_dir test_sclk.clkout 0} 0
add_sclk_case sclk_wrong_output {setpin test_sclk.clkout {wrong_out} 1} 0
add_sclk_case sclk_wrong_driver_pin {dict set ::drivers sclk_output {test_sclk.clkin}} 0
add_sclk_case sclk_multiple_drivers {dict lappend ::drivers sclk_output rogue.o} 0
add_sclk_case sclk_missing_driver {dict set ::drivers sclk_output {}} 0
add_sclk_case sclk_ambiguous_cell {dict set ::cell_override test_sclk {test_sclk alias}} 0
add_sclk_case sclk_ambiguous_net {dict set ::net_override sclk_output {sclk_output alias}} 0
add_sclk_case sclk_unconnected_input {setpin test_sclk.clkin {} 0} 0
add_sclk_case sclk_self_cycle {setpin test_sclk.clkin {sclk_output} 0} 0
add_sclk_case sclk_two_node_cycle {
    add_sclk other_sclk sclk_output other_out
    setpin test_sclk.clkin {other_out} 0
} 0
add_sclk_case sclk_at_original_depth_limit {
    add_sclk other_sclk sclk_output other_out
} 1 {secondary_key3_clock_equivalent TEST other_out I_sys_clk}
add_sclk_case sclk_over_original_depth_limit {
    add_sclk other_sclk sclk_output other_out
    add_sclk third_sclk other_out third_out
} 0 {secondary_key3_clock_equivalent TEST third_out I_sys_clk}
add_sclk_case sclk_wrong_upstream_pad {setpin I_sys_clk_syn_2.ipad {I_key3_n} 0} 0
add_sclk_case sclk_wrong_upstream_gclk {prop $::gclk PRESELECT CLK1} 0
add_sclk_case sclk_clock_not_key {} 0 {secondary_key3_key_equivalent TEST sclk_output I_key3_n}
add_sclk_case sclk_source_twice {
    source [file join $::root 04_pin clocktrace_sclk prove_key3_supervisor_clocktrace.tcl]
    source [file join $::root 04_pin clocktrace_sclk prove_key3_supervisor_clocktrace.tcl]
} 1

proc test_polluted_alias {mode} {
    set args [info args secondary_key3_trace_without_sclk]
    set body [info body secondary_key3_trace_without_sclk]
    rename secondary_key3_trace_without_sclk {}
    if {$mode eq "body"} {
        proc secondary_key3_trace_without_sclk {stage actual expected kind seen} {return UNPROVEN}
    } elseif {$mode eq "args"} {
        proc secondary_key3_trace_without_sclk {stage actual expected kind} $body
    } else {
        proc secondary_key3_trace_without_sclk {stage actual expected kind {seen {}}} $body
    }
    set rc [catch {source [file join $::root 04_pin clocktrace_sclk prove_key3_supervisor_clocktrace.tcl]} detail options]
    rename secondary_key3_trace_without_sclk {}
    proc secondary_key3_trace_without_sclk $args $body
    source [file join $::root 04_pin clocktrace_sclk prove_key3_supervisor_clocktrace.tcl]
    if {$rc} {return -options $options $detail}
    return WRONG_ACCEPTANCE
}
foreach mode {body args defaults} {
    add_sclk_case sclk_polluted_alias_$mode {} 0 [list test_polluted_alias $mode]
}

# Exercise the unchanged full 26-register hook through the added SCLK chain.
proc build_supervisor {mapping} {
    set ::reginfo {}
    dict set ::nets por_release 1
    set specs [list [list u_board_reset/key_meta 1] [list u_board_reset/key_sync 1] [list u_board_reset/key_sample 1] [list {u_board_reset/sample_valid[0]} 0] [list {u_board_reset/sample_valid[1]} 0]]
    for {set bit 0} {$bit<20} {incr bit} {lappend specs [list [format {u_board_reset/stable_count[%d]} $bit] 0]}
    lappend specs [list board_release 0]
    set index 0
    foreach spec $specs {
        lassign $spec logical initial
        set physical [expr {$mapping eq "physical" || ($mapping eq "mixed" && $index%2)}]
        set cell "full_ff_$index"
        if {$physical} {
            set half [expr {$index%2 ? "B" : "A"}]
            set q "$cell.[expr {$half eq "A" ? "oqa" : "oqb"}]"
            set d "$cell.[expr {$half eq "A" ? "ima" : "imb"}]"
            set async "$cell.asr"
            set props [list TYPE AL_PHY_LSLICE REF_NAME PH1P_PHY_LSLICE LATCHMODE DFF CLKMUX SIG ASRMUX INV SSRMUX 0 SSROVERCE ENABLE CE${half}MUX 1 OQ${half}MUX Q${half} REG${half}_REGSET_ASYNC [expr {$initial?"SET":"RESET"}] REG${half}_SD IM${half}]
            setpin "$cell.dffshiften" {} 0
        } else {
            set q "$cell.q"; set d "$cell.d"; set async "$cell.sr"
            set props [list TYPE AL_MAP_SEQ REF_NAME AL_MAP_SEQ DFFMODE FF CLKMUX SIG CEMUX 1 SRMODE ASYNC SRMUX INV REGSET [expr {$initial?"SET":"RESET"}]]
        }
        dict set ::cells $cell 1
        dict set ::properties $cell $props
        setpin $q [list $logical] 1
        dict set ::drivers $logical [list $q]
        setpin "$cell.clk" {sclk_output} 0
        setpin $async {por_release} 0
        if {$index==0} {setpin $d {I_key3_n_dup_3} 0} elseif {$index==1} {setpin $d {u_board_reset/key_meta} 0} else {setpin $d [list "data_$index"] 0}
        dict set ::reginfo $logical [dict create cell $cell q $q d $d async $async physical $physical]
        incr index
    }
}
proc full_supervisor {stage} {
    set proof [secondary_prove_key3_supervisor $stage]
    if {[dict size [dict get $proof registers]] != 26} {error WRONG_REGISTER_COUNT}
    set path [dict get $proof report]
    set fh [open $path r]; set before [read $fh]; close $fh
    if {![catch {secondary_prove_key3_supervisor $stage}]} {error REPORT_OVERWRITE_ACCEPTED}
    set fh [open $path r]; set after [read $fh]; close $fh
    if {$before ne $after} {error REPORT_OVERWRITTEN}
    return "FULL_SUPERVISOR_26_PROVEN report=$path overwrite_rejected=1"
}
foreach mapping {gate physical mixed} {
    add_sclk_case full_supervisor_$mapping [list build_supervisor $mapping] 1 [list full_supervisor full_$mapping]
}
foreach {name mutation} {
    bad_reset_value {dict set ::properties full_ff_0 REGSET RESET}
    bad_sync_data {setpin full_ff_1.d {I_key3_n_dup_3} 0}
    bad_counter_reset {setpin full_ff_24.sr {board_release} 0}
    bad_clock {setpin full_ff_0.clk {I_key3_n_dup_3} 0}
    missing_counter {dict unset ::nets {u_board_reset/stable_count[19]}}
    merged_register {dict set ::drivers u_board_reset/key_sync {full_ff_0.q}}
    cloned_register {dict set ::nets u_board_reset/key_meta_dup_1 1}
} {
    add_sclk_case full_supervisor_$name "build_supervisor gate; $mutation" 0 [list full_supervisor reject_$name]
}
