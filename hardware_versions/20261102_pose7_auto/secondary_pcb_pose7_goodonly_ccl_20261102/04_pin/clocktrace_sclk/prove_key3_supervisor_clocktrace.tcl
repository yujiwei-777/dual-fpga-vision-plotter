# Supplementary read-only SCLK identity proof. The original hook remains the
# sole implementation of all KEY3 register, pad, GCLK and reset checks.
# UG1310_1.5 section 41 (printed p89): BYPASS=ENABLE bypasses CE;
# DELAY_DYN=DISABLE with DELAY=0 disables programmable delay.
set secondary_key3_sclk_base [file join [file dirname [file dirname [file normalize [info script]]]] prove_key3_supervisor_clocktrace.tcl]
source $secondary_key3_sclk_base

# Each physical phase sources the hook again. Never overwrite an unrecognized
# alias: it must be exactly the freshly sourced original trace procedure.
if {[llength [info commands secondary_key3_trace_without_sclk]] != 0} {
    if {[llength [info procs secondary_key3_trace_without_sclk]] != 1 ||
        [info args secondary_key3_trace_without_sclk] ne [info args secondary_key3_trace] ||
        [info body secondary_key3_trace_without_sclk] ne [info body secondary_key3_trace]} {
        secondary_key3_fail LOAD "unrecognized original-trace alias"
    }
    foreach secondary_key3_sclk_arg [info args secondary_key3_trace] {
        if {[info default secondary_key3_trace_without_sclk $secondary_key3_sclk_arg secondary_key3_sclk_value] !=
            [info default secondary_key3_trace $secondary_key3_sclk_arg secondary_key3_sclk_other]} {
            secondary_key3_fail LOAD "changed original-trace alias argument defaults"
        }
    }
    rename secondary_key3_trace_without_sclk {}
}
rename secondary_key3_trace secondary_key3_trace_without_sclk

proc secondary_key3_sclk_static_pin {stage cell pin expected} {
    set full "$cell.$pin"
    set pins [get_pins -nowarn $full]
    if {[llength $pins] != 1} {secondary_key3_fail $stage "missing/ambiguous SCLK control $full"}
    set nets [get_nets -nowarn -of $pins]
    if {[llength $nets] == 0} {
        return "OPEN:$pin"
    }
    if {[llength $nets] != 1} {secondary_key3_fail $stage "ambiguous SCLK control net $full: $nets"}
    return "$pin=[secondary_key3_constant $stage [lindex $nets 0] $expected]"
}

proc secondary_key3_trace {stage actual expected kind seen} {
    # Preserve the original cycle/depth limits and the original behavior for
    # all sources other than the one explicitly supported SCLK primitive.
    if {$actual eq $expected} {
        return [secondary_key3_trace_without_sclk $stage $actual $expected $kind $seen]
    }
    if {$actual in $seen || [llength $seen] >= 4} {
        secondary_key3_fail $stage "cyclic/overlong $kind source chain: $seen -> $actual"
    }
    set ns [get_nets -nowarn $actual]
    if {[llength $ns] != 1} {secondary_key3_fail $stage "ambiguous $kind net $actual"}
    set ds [get_pins -nowarn -filter {DIRECTION == output} -of $ns]
    if {[llength $ds] != 1 || ![regexp {^(.+)\.([^./]+)$} [lindex $ds 0] unused cell pin]} {
        secondary_key3_fail $stage "$kind $actual lacks one primitive driver: $ds"
    }
    set cells [get_cells -nowarn $cell]
    if {[llength $cells] != 1} {secondary_key3_fail $stage "ambiguous source cell $cell"}
    set typ [get_property TYPE [lindex $cells 0]]
    set ref [get_property REF_NAME [lindex $cells 0]]
    if {$kind ne "CLOCK" || $typ ne "AL_PHY_SCLK" || $ref ne "PH1P_PHY_SCLK_V2" || $pin ne "clkout"} {
        return [secondary_key3_trace_without_sclk $stage $actual $expected $kind $seen]
    }
    set configured [secondary_key3_inventory $stage $cell]
    foreach {property required} {TYPE AL_PHY_SCLK REF_NAME PH1P_PHY_SCLK_V2} {
        if {$property ni $configured} {secondary_key3_fail $stage "incomplete SCLK inventory $cell missing $property"}
        secondary_key3_property $stage $cell $property $required
    }
    # Reject unknown configuration knobs rather than assuming they cannot
    # select/invert/divide/gate the clock. Metadata is enumerated explicitly.
    set allowed {CLASS FILE_NAME FORCE_KEEP IS_BLACKBOX IS_DEBUGGABLE IS_PLACED IS_PRIMITIVE LINE_NUMBER NAME PLACED_COL PLACED_OFFSET PLACED_ROW PRIMITIVE_COUNT REF_NAME TYPE GSR BYPASS DELAY DELAY_DYN}
    foreach property $configured {
        if {$property ni $allowed} {secondary_key3_fail $stage "unsupported SCLK property $cell $property"}
    }
    # These two lowercase fields are TD placement metadata in the actual
    # routed inventory, not HDL primitive parameters. Reject all other
    # lowercase/unknown rows too, without discarding them during parsing.
    set table [report_property [lindex $cells 0]]
    set observed {}
    foreach row [split $table \n] {
        if {[regexp {^\s*([A-Za-z][A-Za-z0-9_]*)\s+\S+\s+(true|false)(\s|$)} $row unused property]} {
            if {$property ni $allowed && $property ni {inferred need_deskew}} {
                secondary_key3_fail $stage "unsupported SCLK inventory field $cell $property"
            }
            if {$property in $observed && $property ne "FORCE_KEEP"} {
                secondary_key3_fail $stage "duplicate SCLK inventory field $cell $property"
            }
            lappend observed $property
        }
    }
    set defaults {}
    foreach {property value} {GSR ENABLE BYPASS ENABLE DELAY 0 DELAY_DYN DISABLE} {
        lappend defaults [secondary_key3_default_property $stage $cell $configured $property $value]
    }
    set required_inputs [list "$cell.ce" "$cell.clkin" [format {%s.dlytrim[0]} $cell] [format {%s.dlytrim[1]} $cell]]
    set required_outputs [list "$cell.clkout"]
    set inputs [get_pins -nowarn -filter {DIRECTION == input} -of $cells]
    set outputs [get_pins -nowarn -filter {DIRECTION == output} -of $cells]
    set all [get_pins -nowarn "$cell.*"]
    if {[lsort $inputs] ne [lsort $required_inputs] ||
        [lsort $outputs] ne $required_outputs ||
        [lsort $all] ne [lsort [concat $required_inputs $required_outputs]]} {
        secondary_key3_fail $stage "unexpected SCLK pin inventory $cell: INPUTS=$inputs OUTPUTS=$outputs ALL=$all"
    }
    # CE may be open only because the proven BYPASS=ENABLE ignores it. A
    # connected CE must be constant one. Dynamic-delay controls must be open
    # or constant zero; arbitrary connected nets are deliberately rejected.
    set controls [list [secondary_key3_sclk_static_pin $stage $cell ce 1]]
    foreach bit {0 1} {
        lappend controls [secondary_key3_sclk_static_pin $stage $cell [format {dlytrim[%d]} $bit] 0]
    }
    set input [secondary_reset_pin_net $stage "$cell.clkin"]
    set output [secondary_reset_pin_net $stage "$cell.clkout"]
    if {$output ne $actual} {secondary_key3_fail $stage "SCLK output disconnected from $actual"}
    lappend seen $actual
    set upstream [secondary_key3_trace $stage $input $expected $kind $seen]
    return "SCLK_STATIC cell=$cell IN=$input OUT=$output DEFAULTS=[join $defaults ,] CONTROLS=[join $controls ,] UPSTREAM=($upstream)"
}
unset secondary_key3_sclk_base
