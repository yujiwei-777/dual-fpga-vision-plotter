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

# KEY3-only input-pad and static global-clock identity proof. No timing writes.
# UG1310 PH1P Libraries Guide section 37: cen/seln are active-low; with
# drct=11, cen=00 and seln=10, clkout is clkin[0] without clock gating.
proc secondary_key3_inventory {stage cell} {
    set cells [get_cells -nowarn $cell]
    if {[llength $cells] != 1} {secondary_key3_fail $stage "ambiguous input/clock cell $cell: $cells"}
    if {[catch {report_property [lindex $cells 0]} table] ||
        ![regexp {^Property\s+Type\s+Read-only\s+Value$} [string trim [lindex [split $table \n] 0]]]} {
        secondary_key3_fail $stage "missing/malformed complete property inventory for $cell"
    }
    set configured {}
    foreach row [split $table \n] {
        if {[regexp {^\s*([A-Z][A-Z0-9_]*)\s+\S+\s+(true|false)(\s|$)} $row unused property]} {
            # TD emits generic FORCE_KEEP and primitive FORCE_KEEP separately.
            if {$property in $configured && $property ne "FORCE_KEEP"} {
                secondary_key3_fail $stage "duplicate configured property $cell $property"
            }
            lappend configured $property
        }
    }
    return $configured
}

proc secondary_key3_default_property {stage cell configured property default} {
    # report_property is the complete configured table. Missing parameters use
    # the public PH1P primitive defaults; explicit overrides must match them.
    if {$property in $configured} {
        secondary_key3_property $stage $cell $property $default
        return "EXPLICIT:$property=$default"
    }
    return "PH1P_DEFAULT:$property=$default"
}

proc secondary_key3_open_pin {stage pin} {
    set pins [get_pins -nowarn $pin]
    if {[llength $pins] != 1 || [llength [get_nets -nowarn -of $pins]] != 0} {
        secondary_key3_fail $stage "expected one unconnected pin $pin"
    }
}

proc secondary_key3_root_net {stage expected port_name} {
    set ports [get_ports -nowarn $port_name]
    if {[llength $ports] != 1} {secondary_key3_fail $stage "canonical input port $port_name is missing/ambiguous"}
    set nets [get_nets -nowarn -of $ports]
    if {[llength $nets] != 1 || [lindex $nets 0] ne $expected} {
        secondary_key3_fail $stage "canonical input $port_name is not connected to $expected: $nets"
    }
    set drivers [get_pins -nowarn -filter {DIRECTION == output} -of $nets]
    if {[llength $drivers] != 1 || [lindex $drivers 0] ne [lindex $ports 0]} {
        secondary_key3_fail $stage "canonical input $port_name has unexpected drivers: $drivers"
    }
}

proc secondary_key3_constant {stage net expected} {
    set ns [get_nets -nowarn $net]
    if {[llength $ns] != 1} {secondary_key3_fail $stage "constant net is missing/ambiguous: $net"}
    set ds [get_pins -nowarn -filter {DIRECTION == output} -of $ns]
    if {[llength $ds] != 1 || ![regexp {^(.+)\.([^./]+)$} [lindex $ds 0] unused cell port]} {
        secondary_key3_fail $stage "constant $net lacks one primitive driver: $ds"
    }
    set cells [get_cells -nowarn $cell]
    if {[llength $cells] != 1} {secondary_key3_fail $stage "constant $net has ambiguous cell $cell"}
    set typ [get_property TYPE [lindex $cells 0]]
    set value -1
    if {$typ eq "one" && $port eq "O"} {set value 1}
    if {$typ eq "zero" && $port eq "O"} {set value 0}
    if {$typ eq "AL_PHY_TIE"} {
        secondary_key3_property $stage $cell REF_NAME PH1P_PHY_TIE
        if {$port eq "vdd"} {set value 1}
        if {$port eq "gnd"} {set value 0}
    }
    set pnet [secondary_reset_pin_net $stage [lindex $ds 0]]
    if {$value != $expected || $pnet ne [lindex $ns 0]} {
        secondary_key3_fail $stage "unproven constant $net TYPE=$typ PORT=$port VALUE=$value EXPECTED=$expected"
    }
    return "CONST:$expected:$typ:[lindex $ds 0]"
}

proc secondary_key3_trace {stage actual expected kind seen} {
    if {$actual eq $expected} {return "DIRECT expected=$expected"}
    if {$actual in $seen || [llength $seen] >= 4} {
        secondary_key3_fail $stage "cyclic/overlong $kind source chain: $seen -> $actual"
    }
    lappend seen $actual
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
    if {$typ eq "AL_PHY_HD_PAD" && $ref eq "PH1P_PHY_HD_PAD" && $pin eq "di"} {
        set configured [secondary_key3_inventory $stage $cell]
        foreach {property required} {TYPE AL_PHY_HD_PAD REF_NAME PH1P_PHY_HD_PAD MODE IN IDDRMODE BYPASS ODLYEN DISABLE TSMUX 1} {
            if {$property ni $configured} {secondary_key3_fail $stage "incomplete input-pad inventory $cell missing $property"}
            secondary_key3_property $stage $cell $property $required
        }
        set defaults {}
        foreach {property default} {DI_SEL SIG DI_TEST DO IDLYEN DISABLE IPCLK_DLY DISABLE IPCLKSWI SIG DLYCAS_MODE NONE DLYSRC IOB GSR ENABLE} {
            lappend defaults [secondary_key3_default_property $stage $cell $configured $property $default]
        }
        set incken [expr {$kind eq "CLOCK" ? "ENABLE" : "DISABLE"}]
        if {$kind eq "CLOCK" && "INCKEN" ni $configured} {
            secondary_key3_fail $stage "clock input-pad $cell lacks explicit INCKEN=ENABLE"
        }
        if {"INCKEN" in $configured} {
            secondary_key3_property $stage $cell INCKEN $incken
        }
        set pad [secondary_reset_pin_net $stage "$cell.ipad"]
        set out [secondary_reset_pin_net $stage "$cell.di"]
        if {$pad ne $expected || $out ne $actual} {
            secondary_key3_fail $stage "input pad does not directly connect canonical $expected: IN=$pad OUT=$out"
        }
        set inputs [get_pins -nowarn -filter {DIRECTION == input} -of $cells]
        if {[llength $inputs] != 18 || [llength [lsort -unique $inputs]] != 18 || "$cell.ipad" ni $inputs} {
            secondary_key3_fail $stage "unexpected PH1P input-pad pin inventory $cell: $inputs"
        }
        foreach input $inputs {
            if {$input ne "$cell.ipad"} {secondary_key3_open_pin $stage $input}
        }
        foreach other [get_pins -nowarn "$cell.*"] {
            if {$other ne "$cell.ipad" && $other ne "$cell.di"} {
                secondary_key3_open_pin $stage $other
            }
        }
        return "INPUT_PAD cell=$cell PAD_TYPE=$typ PAD_MODE=IN IDDRMODE=BYPASS INCKEN=$incken IN=$pad OUT=$out DEFAULTS=[join $defaults ,]"
    }
    if {$kind eq "CLOCK" && $typ eq "AL_PHY_GCLK" && $ref eq "PH1P_PHY_GCLK" && $pin eq "clkout"} {
        set configured [secondary_key3_inventory $stage $cell]
        foreach {property required} {TYPE AL_PHY_GCLK REF_NAME PH1P_PHY_GCLK PRESELECT CLK0 HOLD YES SEL_TRIGGER POS GSR ENABLE} {
            if {$property ni $configured} {secondary_key3_fail $stage "incomplete GCLK inventory $cell missing $property"}
            secondary_key3_property $stage $cell $property $required
        }
        set required_inputs {}
        foreach stem {cen drct seln clkin} {
            foreach bit {0 1} {lappend required_inputs [format {%s.%s[%d]} $cell $stem $bit]}
        }
        set inputs [get_pins -nowarn -filter {DIRECTION == input} -of $cells]
        if {[lsort $inputs] ne [lsort $required_inputs]} {
            secondary_key3_fail $stage "unexpected GCLK input pin inventory $cell: $inputs"
        }
        set controls {}
        foreach {stem bit value} {cen 0 0 cen 1 0 drct 0 1 drct 1 1 seln 0 0 seln 1 1} {
            set p [format {%s.%s[%d]} $cell $stem $bit]
            set n [secondary_reset_pin_net $stage $p]
            lappend controls "${stem}${bit}=[secondary_key3_constant $stage $n $value]"
        }
        secondary_key3_open_pin $stage [format {%s.clkin[1]} $cell]
        set input [secondary_reset_pin_net $stage [format {%s.clkin[0]} $cell]]
        set output [secondary_reset_pin_net $stage "$cell.clkout"]
        if {$output ne $actual} {secondary_key3_fail $stage "GCLK output disconnected from $actual"}
        set upstream [secondary_key3_trace $stage $input $expected $kind $seen]
        return "GCLK_STATIC cell=$cell IN=$input OUT=$output PRESELECT=CLK0 HOLD=YES SEL_TRIGGER=POS GSR=ENABLE CONTROLS=[join $controls ,] UPSTREAM=($upstream)"
    }
    if {$kind eq "KEY" && $typ eq "AL_LOGIC_BUFKEEP" && $ref eq "AL_BUFKEEP" && $pin eq "o"} {
        set out [secondary_reset_pin_net $stage "$cell.o"]
        set input [secondary_reset_pin_net $stage "$cell.i"]
        if {$out ne $actual} {secondary_key3_fail $stage "BUFKEEP output disconnected from $actual"}
        return "BUFKEEP cell=$cell IN=$input OUT=$out UPSTREAM=([secondary_key3_trace $stage $input $expected $kind $seen])"
    }
    secondary_key3_fail $stage "unsupported $kind source $actual DRIVER=[lindex $ds 0] TYPE=$typ REF_NAME=$ref"
}

proc secondary_key3_clock_equivalent {stage actual expected} {
    secondary_key3_root_net $stage $expected I_sys_clk
    return [secondary_key3_trace $stage $actual $expected CLOCK {}]
}

proc secondary_key3_key_equivalent {stage actual expected} {
    secondary_key3_root_net $stage $expected I_key3_n
    return [secondary_key3_trace $stage $actual $expected KEY {}]
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
    set clock_proof [secondary_key3_clock_equivalent $stage $clock $clock_expected]
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
    foreach api {get_nets get_pins get_cells get_ports get_property report_property secondary_reset_net \
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
    set meta_source_proof [secondary_key3_key_equivalent $stage [dict get $meta dnet] $key]
    set key_source_proof [secondary_key3_key_equivalent $stage $key $key]
    set meta_source $key
    set key_source $key
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
    puts $fh "KEY3_KEY_SOURCE LOGICAL=I_key3_n PORT_NET=$key SOURCE_NET=$key_source META_D_SOURCE_NET=$meta_source PROOF=[list $meta_source_proof]"
    puts $fh "KEY3_PROOF_LIMITS ASYNC_VALUE_IS_POR_BRANCH_NOT_CONFIG_INIT=1 FIRST_STAGE_EXCEPTION_COVERAGE=SEPARATE_REQUIRED_GATE NO_TIMING_EXCEPTION_ADDED=1"
    puts $fh "KEY3_PROOF_PASS"
    close $fh
    puts "SECONDARY_KEY3_SUPERVISOR_PROVEN $stage registers=[dict size $registers] report=$report"
    return [dict create report $report stage $stage registers $registers meta_d [dict get $meta d] \
        sync_d [dict get $sync d] clock_net $clock por_net $por output_net $output]
}
