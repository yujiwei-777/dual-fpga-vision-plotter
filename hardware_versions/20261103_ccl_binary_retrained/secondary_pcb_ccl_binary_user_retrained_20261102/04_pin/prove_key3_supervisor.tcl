# Read-only mapped-netlist proof. Source after the reset and CDC helpers.
# This hook NEVER installs, removes or reloads timing constraints. Physical
# endpoint coverage is a separate consumer of the actual D pins recorded here.

proc secondary_key3_fail {stage reason} {
    error "SECONDARY_KEY3_PROOF_ERROR $stage $reason"
}

proc secondary_key3_property {stage cell property expected} {
    set cells [get_cells -nowarn $cell]
    if {[llength $cells] != 1} {
        secondary_key3_fail $stage "ambiguous register cell $cell: $cells"
    }
    if {[catch {get_property $property [lindex $cells 0]} actual] || $actual ne $expected} {
        secondary_key3_fail $stage "$cell $property=$actual expected=$expected"
    }
}

proc secondary_key3_register {stage logical reset_value direct_data always_enabled} {
    set logical_net [secondary_reset_net $stage $logical]
    set qnet [secondary_cdc_identity_net $stage $logical_net]
    # We do not infer cloned FF equivalence from names. A clone requires an
    # explicit complete D/enable/reset proof; this narrow hook rejects it.
    foreach prefix [lsort -unique [list $logical $logical_net $qnet]] {
        set clones [get_nets -nowarn "${prefix}_dup_*"]
        if {[llength $clones] != 0} {
            secondary_key3_fail $stage "unsupported cloned supervisor register $logical: $clones"
        }
    }
    set drivers [get_pins -nowarn -filter {DIRECTION == output} -of [get_nets -nowarn $qnet]]
    if {[llength $drivers] != 1 ||
        ![regexp {^(.+)\.(q|oqa|oqb)$} [lindex $drivers 0] unused cell port]} {
        secondary_key3_fail $stage "$logical lacks one registered Q driver: $drivers"
    }
    set q [lindex $drivers 0]
    set value [expr {$reset_value ? "SET" : "RESET"}]
    set d "-"; set dnet "-"; set dselect "-"
    if {$port eq "q"} {
        set mapping GATE
        set properties [list TYPE AL_MAP_SEQ REF_NAME AL_MAP_SEQ DFFMODE FF CLKMUX SIG \
            SRMODE ASYNC SRMUX INV REGSET $value]
        if {$always_enabled} {lappend properties CEMUX 1}
        set async_pin "$cell.sr"
        set dselect DIRECT
        if {$direct_data} {set d "$cell.d"}
    } else {
        set mapping PHYSICAL
        set half [expr {$port eq "oqa" ? "A" : "B"}]
        set properties [list TYPE AL_PHY_LSLICE REF_NAME PH1P_PHY_LSLICE LATCHMODE DFF \
            CLKMUX SIG ASRMUX INV SSRMUX 0 SSROVERCE ENABLE \
            OQ${half}MUX Q${half} REG${half}_REGSET_ASYNC $value]
        if {$always_enabled} {lappend properties CE${half}MUX 1}
        set async_pin "$cell.asr"
        if {$direct_data} {
            lappend properties REG${half}_SD IM${half}
            set d "$cell.[expr {$half eq "A" ? "ima" : "imb"}]"
            set dselect IM${half}
        }
        set shift [get_pins -nowarn "$cell.dffshiften"]
        if {[llength $shift] > 1 ||
            ([llength $shift] == 1 && [llength [get_nets -nowarn -of $shift]] != 0)} {
            secondary_key3_fail $stage "$logical has ambiguous or connected shift enable"
        }
    }
    foreach {property expected} $properties {
        secondary_key3_property $stage $cell $property $expected
    }
    set clock [secondary_reset_pin_net $stage "$cell.clk"]
    set clock_expected [secondary_reset_net $stage I_sys_clk]
    set clock_proof [secondary_clock_equivalent $stage $clock $clock_expected]
    set async [secondary_reset_pin_net $stage $async_pin]
    set por [secondary_reset_net $stage por_release]
    set async_proof [secondary_async_source_equivalent $stage $async $por]
    if {$direct_data} {set dnet [secondary_reset_pin_net $stage $d]}
    return [dict create logical $logical logical_net $logical_net q $q qnet $qnet \
        d $d dnet $dnet dselect $dselect clk $clock async_pin $async_pin async $async \
        async_value $reset_value mapping $mapping clock_proof $clock_proof \
        async_proof $async_proof modes $properties]
}

proc secondary_prove_key3_supervisor {stage} {
    if {![regexp {^[A-Za-z][A-Za-z0-9_]*$} $stage]} {
        secondary_key3_fail INVALID_STAGE "unsafe phase name"
    }
    foreach api {get_nets get_pins get_cells get_property secondary_reset_net \
        secondary_reset_pin_net secondary_clock_equivalent secondary_async_source_equivalent \
        secondary_cdc_identity_net} {
        if {[llength [info commands $api]] != 1} {
            secondary_key3_fail $stage "required mapped-netlist API/helper unavailable: $api"
        }
    }
    set clock [secondary_reset_net $stage I_sys_clk]
    set por [secondary_reset_net $stage por_release]
    set output [secondary_reset_net $stage board_release]
    if {$por eq $output || $clock eq $output || $clock eq $por} {
        secondary_key3_fail $stage "clock/POR/supervisor output nets must be distinct"
    }
    # This is the frozen production supervisor's default DEBOUNCE_CYCLES=
    # 1,000,000 contract: 20 counter bits, two sample-valid bits and four scalar
    # registers. Missing/optimized/renamed storage is not silently count-passed.
    set specifications [list [list u_board_reset/key_meta 1 1 1] \
        [list u_board_reset/key_sync 1 1 1] [list u_board_reset/key_sample 1 0 0] \
        [list {u_board_reset/sample_valid[0]} 0 0 0] \
        [list {u_board_reset/sample_valid[1]} 0 0 0]]
    for {set bit 0} {$bit < 20} {incr bit} {
        lappend specifications [list [format {u_board_reset/stable_count[%d]} $bit] 0 0 0]
    }
    lappend specifications [list board_release 0 0 0]
    set registers {}; set q_pins {}; set q_nets {}; set records {}
    foreach specification $specifications {
        lassign $specification logical initial direct enabled
        set proof [secondary_key3_register $stage $logical $initial $direct $enabled]
        if {[dict get $proof q] in $q_pins || [dict get $proof qnet] in $q_nets} {
            secondary_key3_fail $stage "merged supervisor registers at $logical"
        }
        lappend q_pins [dict get $proof q]
        lappend q_nets [dict get $proof qnet]
        dict set registers $logical $proof
        lappend records "KEY3_REGISTER_PROVEN LOGICAL=$logical Q=[dict get $proof q] QNET=[dict get $proof qnet] CLK=[dict get $proof clk] ASYNC_PIN=[dict get $proof async_pin] ASYNC=[dict get $proof async] ASYNC_VALUE=$initial MODE=[dict get $proof mapping] MODES=[list [dict get $proof modes]] CLOCK_PROOF=[list [dict get $proof clock_proof]] ASYNC_PROOF=[list [dict get $proof async_proof]]"
    }
    set meta [dict get $registers u_board_reset/key_meta]
    set sync [dict get $registers u_board_reset/key_sync]
    set key [secondary_reset_net $stage I_key3_n]
    set meta_source [secondary_cdc_identity_net $stage [dict get $meta dnet]]
    set key_source [secondary_cdc_identity_net $stage $key]
    if {$meta_source ne $key_source} {
        secondary_key3_fail $stage "META D is not the proven I_key3_n source"
    }
    # The second stage is deliberately stricter: a direct Q-to-D connection.
    # A data LUT, merged stage or unsupported alias cannot gain approval.
    if {[dict get $sync dnet] ne [dict get $meta qnet]} {
        secondary_key3_fail $stage "SYNC D is not exactly META Q"
    }
    set stage_records {}
    foreach label {META SYNC} proof [list $meta $sync] {
        lappend stage_records "KEY3_STAGE_PROVEN $label Q=[dict get $proof q] QNET=[dict get $proof qnet] D=[dict get $proof d] DNET=[dict get $proof dnet] CLK=[dict get $proof clk] ASYNC_PIN=[dict get $proof async_pin] ASYNC=[dict get $proof async] MODE=[dict get $proof mapping] ASYNC_VALUE=1 D_SELECT=[dict get $proof dselect] MODES=[list [dict get $proof modes]] CLOCK_PROOF=[list [dict get $proof clock_proof]] ASYNC_PROOF=[list [dict get $proof async_proof]]"
    }
    # Only after every register, mode and connection has been proven can a
    # successful report exist. Exclusive creation preserves previous evidence.
    set report [file normalize [format {secondary_key3_%s.rpt} $stage]]
    set fh [open $report {WRONLY CREAT EXCL}]
    puts $fh "KEY3_PROOF_STAGE $stage"
    foreach record $stage_records {puts $fh $record}
    foreach record $records {puts $fh $record}
    puts $fh "KEY3_SUPERVISOR_PROVEN CLK=I_sys_clk ASYNC=por_release OUTPUT=board_release CLOCK_NET=$clock POR_NET=$por OUTPUT_NET=$output INPUT_NET=$key SELF_RESET=0 REGISTER_COUNT=[dict size $registers]"
    puts $fh "KEY3_KEY_SOURCE LOGICAL=I_key3_n PORT_NET=$key SOURCE_NET=$key_source META_D_SOURCE_NET=$meta_source"
    puts $fh "KEY3_PROOF_LIMITS ASYNC_VALUE_IS_POR_BRANCH_NOT_CONFIG_INIT=1 FIRST_STAGE_EXCEPTION_COVERAGE=SEPARATE_REQUIRED_GATE NO_TIMING_EXCEPTION_ADDED=1"
    puts $fh "KEY3_PROOF_PASS"
    close $fh
    puts "SECONDARY_KEY3_SUPERVISOR_PROVEN $stage registers=[dict size $registers] report=$report"
    return [dict create report $report stage $stage registers $registers meta_d [dict get $meta d] \
        sync_d [dict get $sync d] clock_net $clock por_net $por output_net $output]
}
