# Pure Tcl object-API regression for the CURRENT supplementary KEY3 hook.
# Object inventories originate in the existing read-only TD probe logs.
# This is a fake-database unit test, never a physical/timing acceptance gate.
set here {D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_key3_sclk_proof_scratch_20261101/fixtures}
set root {D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_key3_sclk_proof_scratch_20261101}

proc json_string {value} {
    return "\"[string map [list \\ \\\\ \" \\\" \n \\n \r \\r \t \\t] $value]\""
}
proc emit {name status detail} {
    puts "RESULT {\"name\":[json_string $name],\"status\":[json_string $status],\"detail\":[json_string $detail]}"
}
proc reset_mock {} {
    foreach name {nets cells properties pin_net pin_dir drivers tables ports net_override cell_override pin_override} {
        set ::$name {}
    }
}
proc setpin {pin net direction} {
    dict set ::pin_net $pin $net
    dict set ::pin_dir $pin $direction
    foreach n $net {dict set ::nets $n 1}
}
proc import_inventory {path} {
    set fh [open $path r]; set text [read $fh]; close $fh
    set table_cell ""; set rows {}
    foreach line [split $text \n] {
        set line [string trimright $line \r]
        if {[regexp {^CELL_PROPERTY_TABLE_BEGIN (\S+)$} $line unused cell]} {
            set table_cell $cell; set rows {}; continue
        }
        if {[regexp {^CELL_PROPERTY_TABLE_END (\S+)$} $line unused cell]} {
            dict set ::tables $cell [join $rows \n]
            set table_cell ""; continue
        }
        if {$table_cell ne ""} {
            lappend rows $line
            if {[regexp {^\s*([A-Z][A-Z0-9_]*)\s+\S+\s+(true|false)\s*(.*)$} $line unused property readonly value]} {
                dict set ::properties $table_cell $property [string trim $value]
            }
            continue
        }
        if {[regexp {^CELL NAME=(\S+) OBJECTS=(.*)$} $line unused cell objects] && [llength $objects] == 1} {
            dict set ::cells $cell 1
        }
        if {[regexp {^CELL_PIN CELL=(\S+) PIN=(\S+) DIRECTION=([012]) NETS=(.*)$} $line unused cell pin direction nets]} {
            setpin $pin $nets $direction
        }
        if {[regexp {^NET_DRIVERS NET=(.*?) PINS=(.*)$} $line unused net pins]} {
            set net [lindex $net 0]
            dict set ::nets $net 1
            dict set ::drivers $net $pins
        }
    }
    # The pad-only inventory records the complete CELL_PIN directions and
    # connections but does not recursively print NET_DRIVERS for di outputs.
    dict for {pin direction} $::pin_dir {
        if {$direction != 1} {continue}
        foreach net [dict get $::pin_net $pin] {
            if {![dict exists $::drivers $net]} {dict set ::drivers $net [list $pin]}
        }
    }
}
proc build_mock {mapping} {
    reset_mock
    if {$mapping eq "route"} {set file control_route_inventory.txt} else {set file gate_inventory.txt}
    import_inventory [file join $::here $file]
    import_inventory [file join $::here key_pad_inventory.txt]
    foreach port {I_sys_clk I_key3_n} {
        dict set ::ports $port [list $port]
        setpin $port [list $port] 1
    }
}
proc get_nets {args} {
    set at [lsearch -exact $args -of]
    if {$at >= 0} {
        set result {}
        foreach pin [lindex $args [expr {$at + 1}]] {
            if {[dict exists $::pin_net $pin]} {set result [concat $result [dict get $::pin_net $pin]]}
        }
        return [lsort -unique $result]
    }
    set name [lindex $args end]
    if {[dict exists $::net_override $name]} {return [dict get $::net_override $name]}
    if {[dict exists $::nets $name]} {return [list $name]}
    return [lsearch -all -inline -glob [dict keys $::nets] $name]
}
proc get_cells {args} {
    set name [lindex $args end]
    if {[dict exists $::cell_override $name]} {return [dict get $::cell_override $name]}
    if {[dict exists $::cells $name]} {return [list $name]}
    return {}
}
proc get_ports {args} {
    set name [lindex $args end]
    if {[dict exists $::ports $name]} {return [dict get $::ports $name]}
    return {}
}
proc get_pins {args} {
    set at [lsearch -exact $args -of]
    set filter [lsearch -exact $args -filter]
    set wanted ""
    if {$filter >= 0} {set wanted [lindex $args [expr {$filter + 1}]]}
    if {$at >= 0} {
        set result {}
        foreach object [lindex $args [expr {$at + 1}]] {
            if {[dict exists $::cells $object]} {
                if {[dict exists $::pin_override $object $wanted]} {
                    set result [concat $result [dict get $::pin_override $object $wanted]]
                    continue
                }
                dict for {pin direction} $::pin_dir {
                    if {[string first "$object." $pin] != 0} {continue}
                    if {$wanted eq "DIRECTION == input" && $direction != 0} {continue}
                    if {$wanted eq "DIRECTION == output" && $direction != 1} {continue}
                    lappend result $pin
                }
            } elseif {[dict exists $::drivers $object]} {
                set result [concat $result [dict get $::drivers $object]]
            }
        }
        return $result
    }
    set pattern [lindex $args end]
    if {[dict exists $::pin_net $pattern]} {return [list $pattern]}
    return [lsearch -all -inline -glob [dict keys $::pin_net] $pattern]
}
proc get_property {property cell} {
    if {![dict exists $::properties $cell $property]} {error "MOCK_MISSING_PROPERTY $cell $property"}
    return [dict get $::properties $cell $property]
}
proc report_property {cell} {
    if {![dict exists $::tables $cell]} {error "MOCK_MISSING_TABLE $cell"}
    return [dict get $::tables $cell]
}
proc prop {cell property value} {
    dict set ::properties $cell $property $value
    set rows {}
    foreach row [split [dict get $::tables $cell] \n] {
        if {[regexp {^\s*(\S+)\s} $row unused name] && $name eq $property} {continue}
        lappend rows $row
    }
    lappend rows [format {%-20s string true %s} $property $value]
    dict set ::tables $cell [join $rows \n]
}
proc drop_prop {cell property} {
    # Hide a configured-table row, retaining API TYPE/REF metadata so the real
    # hook's complete-inventory requirement is the check under test.
    set rows {}
    foreach row [split [dict get $::tables $cell] \n] {
        if {[regexp {^\s*(\S+)\s} $row unused name] && $name eq $property} {continue}
        lappend rows $row
    }
    dict set ::tables $cell [join $rows \n]
}
proc add_buffer {cell input output} {
    dict set ::cells $cell 1
    dict set ::properties $cell [dict create TYPE AL_LOGIC_BUFKEEP REF_NAME AL_BUFKEEP]
    setpin "$cell.i" [list $input] 0
    setpin "$cell.o" [list $output] 1
    dict set ::drivers $output [list "$cell.o"]
}
foreach name {set_false_path set_max_delay set_min_delay read_sdc clear_sdc update_timing create_clock set_multicycle_path} {
    proc $name {args} {error "FORBIDDEN_TIMING_MUTATION"}
}
source [file join $root 04_pin apply_reset_exceptions.tcl]
source [file join $root 04_pin apply_cdc_exceptions.tcl]
source [file join $root 04_pin clocktrace_sclk prove_key3_supervisor_clocktrace.tcl]

set cases {}
proc add_case {name mapping mutation operation pass {reason {SECONDARY_(KEY3_PROOF|RESET_MAPPING)_ERROR}}} {
    lappend ::cases [list $name $mapping $mutation $operation $pass $reason]
}
set clock_pad I_sys_clk_syn_2
set key_pad I_key3_n_syn_4
set gclk I_sys_clk_dup_1_created_gclkinst
set clock_op {secondary_key3_clock_equivalent TEST I_sys_clk_dup_1 I_sys_clk}
set route_op {secondary_key3_clock_equivalent TEST I_sys_clk_syn_11 I_sys_clk}
set key_op {secondary_key3_key_equivalent TEST I_key3_n_dup_3 I_key3_n}
add_case gate_real_pad gate {} $clock_op 1
add_case route_real_static_gclk route {} $route_op 1
add_case key_real_pad gate {} $key_op 1
add_case clock_direct_canonical gate {} {secondary_key3_clock_equivalent TEST I_sys_clk I_sys_clk} 1
add_case key_direct_canonical gate {} {secondary_key3_key_equivalent TEST I_key3_n I_key3_n} 1
add_case key_bufkeep_from_real_pad gate {add_buffer key_buf I_key3_n_dup_3 key_buffered} \
    {secondary_key3_key_equivalent TEST key_buffered I_key3_n} 1
add_case key_three_bufkeep_chain gate {
    add_buffer b0 I_key3_n_dup_3 n0; add_buffer b1 n0 n1; add_buffer b2 n1 n2
} {secondary_key3_key_equivalent TEST n2 I_key3_n} 1
add_case key_explicit_incken_disabled gate {prop $::key_pad INCKEN DISABLE} $key_op 1
add_case route_explicit_tie_vdd route {
    setpin x24y38_auto_const.vdd [list phy_vdd] 1
    dict set ::drivers phy_vdd {x24y38_auto_const.vdd}
    foreach pin [list [format {%s.drct[0]} $::gclk] [format {%s.drct[1]} $::gclk] [format {%s.seln[1]} $::gclk]] {
        dict set ::pin_net $pin [list phy_vdd]
    }
} $route_op 1

foreach {property wrong} {MODE OUT IDDRMODE IDDRX1 ODLYEN ENABLE TSMUX SIG INCKEN DISABLE REF_NAME WRONG_PAD TYPE WRONG_PAD} {
    add_case "clock_pad_wrong_$property" gate [list prop $clock_pad $property $wrong] $clock_op 0
}
add_case key_pad_wrong_incken gate [list prop $key_pad INCKEN ENABLE] $key_op 0
foreach property {TYPE REF_NAME MODE IDDRMODE ODLYEN TSMUX INCKEN} {
    add_case "clock_pad_missing_$property" gate [list drop_prop $clock_pad $property] $clock_op 0
}
foreach {property value} {DI_SEL SIG DI_TEST DO IDLYEN DISABLE IPCLK_DLY DISABLE IPCLKSWI SIG DLYCAS_MODE NONE DLYSRC IOB GSR ENABLE} {
    add_case "clock_pad_explicit_default_$property" gate [list prop $clock_pad $property $value] $clock_op 1
    add_case "clock_pad_bad_default_$property" gate [list prop $clock_pad $property WRONG] $clock_op 0
}
add_case clock_pad_wrong_canonical_input gate {setpin I_sys_clk_syn_2.ipad [list other_clock] 0} $clock_op 0
add_case key_pad_wrong_canonical_input gate {setpin I_key3_n_syn_4.ipad [list other_key] 0} $key_op 0
add_case clock_pad_output_net_mismatch gate {setpin I_sys_clk_syn_2.di [list disconnected_output] 1} $clock_op 0
add_case clock_pad_wrong_output_pin gate {dict set ::drivers I_sys_clk_dup_1 {I_sys_clk_syn_2.opad}} $clock_op 0
add_case clock_multiple_drivers gate {dict lappend ::drivers I_sys_clk_dup_1 rogue.o} $clock_op 0
add_case clock_missing_driver gate {dict set ::drivers I_sys_clk_dup_1 {}} $clock_op 0
add_case clock_net_ambiguous gate {dict set ::net_override I_sys_clk_dup_1 {I_sys_clk_dup_1 alias}} $clock_op 0
add_case clock_cell_ambiguous gate {dict set ::cell_override I_sys_clk_syn_2 {I_sys_clk_syn_2 alias}} $clock_op 0
add_case clock_canonical_port_missing gate {dict unset ::ports I_sys_clk} $clock_op 0
add_case clock_canonical_port_ambiguous gate {dict set ::ports I_sys_clk {I_sys_clk alias}} $clock_op 0
add_case clock_canonical_port_wrong_net gate {setpin I_sys_clk [list wrong_port_net] 1} $clock_op 0
add_case clock_canonical_multiple_drivers gate {dict lappend ::drivers I_sys_clk rogue.o} $clock_op 0
add_case key_canonical_multiple_drivers gate {dict lappend ::drivers I_key3_n rogue.o} $key_op 0
add_case clock_bad_inventory_header gate {dict set ::tables I_sys_clk_syn_2 {bad inventory}} $clock_op 0
add_case clock_duplicate_inventory_property gate {
    dict append ::tables I_sys_clk_syn_2 "\nMODE string true IN"
} $clock_op 0
add_case clock_pad_missing_aux_pin gate {dict unset ::pin_net I_sys_clk_syn_2.ce; dict unset ::pin_dir I_sys_clk_syn_2.ce} $clock_op 0
add_case clock_pad_duplicate_input_inventory gate {
    set inputs [get_pins -nowarn -filter {DIRECTION == input} -of {I_sys_clk_syn_2}]
    dict set ::pin_override I_sys_clk_syn_2 {DIRECTION == input} [concat $inputs {I_sys_clk_syn_2.ce}]
} $clock_op 0

# Every actual non-data pad pin is required open, including extra outputs and
# bpad; connecting one is an independent negative case.
build_mock gate
foreach cell [list $clock_pad $key_pad] op [list $clock_op $key_op] {
    foreach pin [get_pins -nowarn "$cell.*"] {
        if {$pin in [list "$cell.ipad" "$cell.di"]} {continue}
        add_case "aux_connected_$pin" gate [list setpin $pin [list unexpected_aux_net] [dict get $::pin_dir $pin]] $op 0
    }
}
foreach {property wrong} {PRESELECT CLK1 HOLD NO SEL_TRIGGER NEG GSR DISABLE REF_NAME WRONG_GCLK TYPE WRONG_GCLK} {
    add_case "gclk_wrong_$property" route [list prop $gclk $property $wrong] $route_op 0
}
foreach property {TYPE REF_NAME PRESELECT HOLD SEL_TRIGGER GSR} {
    add_case "gclk_missing_$property" route [list drop_prop $gclk $property] $route_op 0
}
foreach {stem bit value} {cen 0 0 cen 1 0 drct 0 1 drct 1 1 seln 0 0 seln 1 1} {
    set wrong_net [expr {$value == 0 ? "phy_wrong_one" : "x24y38_auto_gnd"}]
    set mutation {}
    if {$value == 0} {
        append mutation {setpin _al_const_one.O [list phy_wrong_one] 1; dict set ::drivers phy_wrong_one {_al_const_one.O}; }
    }
    append mutation [list setpin [format {%s.%s[%d]} $gclk $stem $bit] [list $wrong_net] 0]
    add_case "gclk_control_wrong_${stem}${bit}" route $mutation $route_op 0
}
add_case gclk_aux_clkin1_connected route {setpin [format {%s.clkin[1]} $::gclk] [list I_sys_clk_dup_1] 0} $route_op 0
add_case gclk_extra_input route {setpin "$::gclk.extra" {} 0} $route_op 0
add_case gclk_missing_input route {
    dict unset ::pin_net [format {%s.cen[0]} $::gclk]
    dict unset ::pin_dir [format {%s.cen[0]} $::gclk]
} $route_op 0
add_case gclk_duplicate_input route {
    set inputs [get_pins -nowarn -filter {DIRECTION == input} -of [list $::gclk]]
    dict set ::pin_override $::gclk {DIRECTION == input} [concat $inputs [lrange $inputs 0 0]]
} $route_op 0
add_case gclk_wrong_output_net route {setpin "$::gclk.clkout" [list wrong_out] 1} $route_op 0
add_case gclk_output_multiple_drivers route {dict lappend ::drivers I_sys_clk_syn_11 rogue.o} $route_op 0
add_case gclk_constant_multiple_drivers route {dict lappend ::drivers x24y38_auto_gnd rogue.o} $route_op 0
add_case gclk_constant_wrong_tie_reference route {prop x24y38_auto_const REF_NAME WRONG_TIE} $route_op 0
add_case gclk_constant_unsupported_primitive route {prop x24y38_auto_const TYPE AL_LOGIC_LUT4} $route_op 0
add_case gclk_constant_output_mismatch route {setpin x24y38_auto_const.gnd [list wrong_ground] 1} $route_op 0
add_case gclk_constant_wrong_driver_port route {dict set ::drivers x24y38_auto_gnd {x24y38_auto_const.vdd}} $route_op 0
add_case gclk_constant_missing_net route {dict unset ::nets x24y38_auto_gnd} $route_op 0
add_case gclk_cycle route {setpin [format {%s.clkin[0]} $::gclk] [list I_sys_clk_syn_11] 0} $route_op 0
add_case key_buffer_wrong_primitive gate {
    add_buffer key_buf I_key3_n_dup_3 key_buffered
    dict set ::properties key_buf REF_NAME UNPROVEN_BUFFER
} {secondary_key3_key_equivalent TEST key_buffered I_key3_n} 0
add_case key_buffer_output_mismatch gate {
    add_buffer key_buf I_key3_n_dup_3 key_buffered
    setpin key_buf.o [list wrong_buffered] 1
} {secondary_key3_key_equivalent TEST key_buffered I_key3_n} 0
add_case key_buffer_self_cycle gate {add_buffer key_buf key_buffered key_buffered} \
    {secondary_key3_key_equivalent TEST key_buffered I_key3_n} 0
add_case key_buffer_two_node_cycle gate {add_buffer b0 n1 n0; add_buffer b1 n0 n1} \
    {secondary_key3_key_equivalent TEST n1 I_key3_n} 0
add_case key_buffer_overlong_chain gate {
    add_buffer b0 I_key3_n_dup_3 n0; add_buffer b1 n0 n1
    add_buffer b2 n1 n2; add_buffer b3 n2 n3
} {secondary_key3_key_equivalent TEST n3 I_key3_n} 0
add_case clock_unapproved_bufkeep gate {add_buffer clock_buf I_sys_clk clock_buffered} \
    {secondary_key3_clock_equivalent TEST clock_buffered I_sys_clk} 0
add_case key_unapproved_gclk route {} {secondary_key3_key_equivalent TEST I_sys_clk_syn_11 I_key3_n} 0

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

set failed 0; set positive 0; set negative 0
foreach case $cases {
    lassign $case name mapping mutation operation expected reason
    build_mock $mapping
    if {[catch {uplevel #0 $mutation} mutation_error options]} {
        emit $name HARNESS_ERROR $mutation_error
        incr failed
        continue
    }
    set rc [catch {uplevel #0 $operation} detail options]
    if {$expected} {
        incr positive
        if {$rc == 0} {emit $name PASS $detail} else {emit $name UNEXPECTED_REJECTION $detail; incr failed}
    } else {
        incr negative
        if {$rc != 0 && [regexp $reason $detail]} {
            emit $name EXPECTED_REJECTION $detail
        } else {
            emit $name MISSING_OR_WRONG_REJECTION $detail
            incr failed
        }
    }
}
puts "SUMMARY {\"cases\":[llength $cases],\"positive\":$positive,\"negative\":$negative,\"failed\":$failed}"
if {$failed} {exit 1}
