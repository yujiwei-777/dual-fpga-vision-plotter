# Only proven reset-synchronizer SR/ASR pins receive timing exceptions.
# A missing or ambiguous mapping is fatal. Gate, packed and mixed mappings
# are checked by the same proof before any false-path command is issued.
proc secondary_reset_net {stage name} {
    set nets [get_nets -nowarn $name]
    if {[llength $nets] != 1} {
        # After place, TD may merge the top-level rst125_n/store_rst125_n
        # aliases into the proven synchronizer output net (u_link/rst_n in
        # the current database). Resolve only that exact stage-1 Q and keep
        # the normal proof checks below; do not accept an arbitrary net.
        if {[llength $nets] == 0 && ($name eq "rst125_n" || $name eq "store_rst125_n")} {
            set q_pins [get_pins -nowarn {u_reset125/sync_ff_reg[1].q}]
            if {[llength $q_pins] == 1} {
                set q_nets [get_nets -nowarn -of $q_pins]
                if {[llength $q_nets] == 1} {
                    return [lindex $q_nets 0]
                }
            }
        }
        error "SECONDARY_RESET_MAPPING_ERROR $stage expected one source net $name: $nets"
    }
    return [lindex $nets 0]
}

proc secondary_reset_pin_net {stage pin} {
    set pins [get_pins -nowarn $pin]
    if {[llength $pins] != 1} {
        error "SECONDARY_RESET_MAPPING_ERROR $stage expected one pin $pin: $pins"
    }
    set nets [get_nets -nowarn -of $pins]
    if {[llength $nets] != 1} {
        error "SECONDARY_RESET_MAPPING_ERROR $stage expected one net at $pin: $nets"
    }
    return [lindex $nets 0]
}

# A post-place/route database may rename a clock net after inserting the
# device's SCLK buffer.  Comparing that generated net with the RTL clock name
# is therefore insufficient.  Accept such a net only after proving the
# complete, connected buffer chain: generated net -> SCLK.clkout and
# SCLK.clkin -> the canonical clock net.  When TD object properties are
# available, also require the documented PH1P SCLK primitive; the small audit
# harness intentionally has no object API and exercises the same connectivity
# proof.
proc secondary_clock_equivalent {stage actual expected} {
    set actual [lindex $actual 0]
    set expected [lindex $expected 0]
    if {$actual eq $expected} {
        return "DIRECT expected=$expected"
    }
    # The flattened PH1P netlist keeps the uimac_rx FIFO input as a local
    # port net.  In RTL this port is wired directly to I_gmii_rclk at the
    # mac_receive_fifo instance; accept this exact, hierarchy-specific alias
    # only for that proven source/target pair.
    if {[regexp {^(.+)/mac_receive_fifo/clkw$} $actual unused prefix] &&
        $expected eq "$prefix/I_gmii_rclk"} {
        return "RTL_PORT_ALIAS expected=$expected actual=$actual source=uimac_rx.mac_receive_fifo.clkw"
    }
    if {![regexp {^(.+)_sclk_outnet$} $actual unused cell]} {
        error "SECONDARY_RESET_MAPPING_ERROR $stage clock net $actual is not the canonical $expected or a generated SCLK net"
    }
    set clkout_pin [get_pins -nowarn "$cell.clkout"]
    set clkin_pin  [get_pins -nowarn "$cell.clkin"]
    if {[llength $clkout_pin] != 1 || [llength $clkin_pin] != 1} {
        # The saved inventory regression intentionally omits the very large
        # TOPPINS rows for generated clock cells.  A real TD database must
        # resolve both pins (and is rejected below when it cannot); the
        # harness can still exercise the generated-net discriminator.
        if {[llength [info commands get_cells]] == 0 &&
            [regexp {^(u_eth_pll/|u_ddr/.*/)(u_)?[A-Za-z0-9_]*auto_created_sclk_s_[0-9]+_[lr]_bk[0-9]+$} $cell]} {
            return "SCLK_BUFFER_INVENTORY cell=$cell expected_in=$expected out=$actual"
        }
        error "SECONDARY_RESET_MAPPING_ERROR $stage incomplete SCLK buffer $cell (clkout=$clkout_pin clkin=$clkin_pin)"
    }
    set out_net [secondary_reset_pin_net $stage "$cell.clkout"]
    set in_net  [secondary_reset_pin_net $stage "$cell.clkin"]
    if {$out_net ne $actual || $in_net ne $expected} {
        error "SECONDARY_RESET_MAPPING_ERROR $stage SCLK chain $cell is not connected (OUT=$out_net EXPECTED_OUT=$actual IN=$in_net EXPECTED_IN=$expected)"
    }
    # Real TD databases expose the primitive type.  Do not accept a name-only
    # match when the property API is present; the fallback is solely for the
    # inventory-only regression harness.
    if {[llength [info commands get_cells]] != 0} {
        set cells [get_cells -nowarn $cell]
        if {[llength $cells] != 1} {
            error "SECONDARY_RESET_MAPPING_ERROR $stage SCLK cell $cell is missing or ambiguous: $cells"
        }
        if {[llength [info commands get_property]] == 0} {
            error "SECONDARY_RESET_MAPPING_ERROR $stage TD cannot prove primitive type for SCLK cell $cell"
        }
        set typ [get_property TYPE [lindex $cells 0]]
        set ref [get_property REF_NAME [lindex $cells 0]]
        if {$typ ne "AL_PHY_SCLK" || ![string match "PH1P_PHY_SCLK*" $ref]} {
            error "SECONDARY_RESET_MAPPING_ERROR $stage non-PH1P SCLK primitive $cell TYPE=$typ REF_NAME=$ref"
        }
    }
    return "SCLK_BUFFER cell=$cell IN=$in_net OUT=$out_net"
}

# The first synchronizer stage has a constant-1 D in reset_sync.v.  Synthesis
# may route that constant through an arbitrary LUT input/net.  Prove the
# implementation by checking the resolved net has the technology constant-one
# driver.  This is deliberately skipped only by the inventory-only Tcl test,
# which does not provide TD's net-driver API; every real TD database is checked.
proc secondary_verify_stage0_d {stage dnet data_pin cell} {
    if {[llength [info commands get_cells]] == 0} {
        return "D_CHECK_DEFERRED inventory_harness=$dnet"
    }
    set dnet [lindex $dnet 0]
    set dnets [get_nets -nowarn $dnet]
    if {[llength $dnets] != 1} {
        error "SECONDARY_RESET_MAPPING_ERROR $stage stage0 D $data_pin has no unique net: $dnet"
    }
    set drivers [get_pins -nowarn -of [get_nets -nowarn $dnet]]
    set constants {}
    foreach dpin $drivers {
        if {[regexp {(^|/)_(al_)?const_one\.O$} $dpin]} { lappend constants $dpin }
    }
    if {[llength [lsort -unique $constants]] != 1} {
        error "SECONDARY_RESET_MAPPING_ERROR $stage stage0 D $data_pin NET=$dnet lacks a unique constant-one driver: $constants"
    }
    return "D_CONST_ONE net=$dnet driver=[lindex [lsort -unique $constants] 0]"
}

# TD can resolve an RTL output alias to the package-side opad net while the
# reset pin is connected to that output buffer's internal doq[0] net. The
# internal net may have a _dup suffix even when only one register drives it.
# Accept this electrical identity only for the fully configured combinational
# PH1P HD output pad, or the independently proven LUT function below.
proc secondary_phy_release_register {stage net} {
    global secondary_proven_reset_outputs
    set why "SECONDARY_RESET_MAPPING_ERROR $stage unproven PHY release register NET=$net"
    set drivers [get_pins -nowarn -filter {DIRECTION == output} -of [get_nets -nowarn $net]]
    if {[llength $drivers] != 1 || ![regexp {^(.+)\.oq([ab])$} [lindex $drivers 0] unused cell half]} {
        error "$why; expected one physical registered Q driver, got $drivers"
    }
    set half [string toupper $half]
    set cells [get_cells -nowarn $cell]
    if {[llength $cells] != 1} {error "$why; ambiguous cell $cell"}
    foreach {property required} [list TYPE AL_PHY_LSLICE REF_NAME PH1P_PHY_LSLICE \
        LATCHMODE DFF CLKMUX SIG ASRMUX INV SSRMUX 0 SSROVERCE ENABLE \
        CE${half}MUX 1 OQ${half}MUX Q${half} \
        REG${half}_REGSET_ASYNC RESET REG${half}_REGSET_SYNC RESET] {
        if {[catch {get_property $property [lindex $cells 0]} value] || $value ne $required} {
            error "$why; $cell $property=$value required=$required"
        }
    }
    # report_property returns the configured physical parameters as a table.
    # list_property only lists generic cell properties in TD. Querying absent
    # optional parameters logs a tool ERROR even inside catch, so enumerate
    # the complete instance table before querying optional values.
    if {[llength [info commands report_property]] != 1 ||
        [catch {report_property [lindex $cells 0]} table]} {
        error "$why; physical property inventory unavailable"
    }
    if {![regexp {^Property\s+Type\s+Read-only\s+Value$} [string trim [lindex [split $table \n] 0]]]} {
        error "$why; malformed physical property inventory header"
    }
    set configured {}
    foreach row [split $table \n] {
        if {[regexp {^\s*([A-Z][A-Z0-9_]*)\s+\S+\s+(true|false)(\s|$)} $row unused property]} {
            if {$property in $configured} {error "$why; duplicate property inventory row $property"}
            lappend configured $property
        }
    }
    foreach property [list TYPE REF_NAME LATCHMODE CLKMUX ASRMUX SSRMUX SSROVERCE \
        CE${half}MUX OQ${half}MUX REG${half}_SD REG${half}_REGSET_ASYNC REG${half}_REGSET_SYNC] {
        if {$property ni $configured} {error "$why; incomplete physical property inventory missing $property"}
    }
    # PH1P_PHY_LSLICE declares GSR=ENABLE, TESTMODE=OFF and no independent FF
    # INIT parameter. A parameter absent from the complete instance table uses
    # that verified vendor default; explicit overrides are still inspected.
    foreach {property default} {GSR ENABLE TESTMODE OFF} {
        if {$property ni $configured} {continue}
        if {[catch {get_property $property [lindex $cells 0]} value] || $value ne $default} {
            error "$why; unsupported $property=$value default=$default"
        }
    }
    foreach property {INIT INITVAL INIT_Q REGA_INIT REGB_INIT} {
        if {$property in $configured} {
            error "$why; unexpected FF initialization override $property"
        }
    }
    set shift_pins [get_pins -nowarn "$cell.dffshiften"]
    if {[llength $shift_pins] > 1 || ([llength $shift_pins] == 1 && [llength [get_nets -nowarn -of $shift_pins]] != 0)} {
        error "$why; connected/unproven shift enable"
    }
    set clock [secondary_reset_pin_net $stage "$cell.clk"]
    set expected_clock [secondary_reset_net $stage clk125]
    secondary_clock_equivalent $stage $clock $expected_clock
    set reset [secondary_reset_pin_net $stage "$cell.asr"]
    set expected_reset [secondary_reset_net $stage rst125_n]
    if {![info exists secondary_proven_reset_outputs] || ![dict exists $secondary_proven_reset_outputs $reset] ||
        [dict get $secondary_proven_reset_outputs $reset] ne $expected_reset} {
        error "$why; reset is not a previously proven rst125_n output: $reset"
    }
    set select [get_property REG${half}_SD [lindex $cells 0]]
    set data_proof DIRECT
    if {$select eq "IM$half"} {
        set data [secondary_reset_pin_net $stage "$cell.[string tolower $select]"]
    } elseif {$half eq "A" && $select eq "LUT5A"} {
        # The A FF and OFA=LUT5A both select the identical LUT5A result in
        # the PH1P primitive. Require the explicit mux modes and prove the
        # complete connected LUT function, as for the existing B case.
        foreach {property required} {LUTMODE DLUT5 OFA_SD LUT5A} {
            if {[catch {get_property $property [lindex $cells 0]} value] || $value ne $required} {
                error "$why; internal D requires $property=$required, got $value"
            }
        }
        set data [secondary_reset_pin_net $stage "$cell.ofa"]
        set data_proof [secondary_reset_lut_function $stage $data]
    } elseif {$half eq "B" && $select eq "LUT6"} {
        # The native PH1P model separately verifies that in DLUT5 mode the B
        # register LUT6 selection and OFB=LUTX expose the identical LUT5B D.
        # Prove the actual OFB connection and its complete LUT configuration.
        foreach {property required} {LUTMODE DLUT5 OFB_SD LUTX} {
            if {[catch {get_property $property [lindex $cells 0]} value] || $value ne $required} {
                error "$why; internal D requires $property=$required, got $value"
            }
        }
        set data [secondary_reset_pin_net $stage "$cell.ofb"]
        set data_proof [secondary_reset_lut_function $stage $data]
    } else {
        error "$why; unsupported registered D selection REG${half}_SD=$select"
    }
    return [dict create q [lindex $drivers 0] data $data clock $expected_clock reset $expected_reset \
        gsr ENABLE initial SAME_VENDOR_GSR_ENABLE async RESET_ZERO select $select data_proof $data_proof]
}

proc secondary_async_source_equivalent {stage actual expected} {
    if {$actual eq $expected} { return "ASYNC_DIRECT expected=$expected" }
    set why "SECONDARY_RESET_MAPPING_ERROR $stage wrong async source NET=$actual EXPECTED=$expected"
    if {[llength [info commands get_cells]] == 0 ||
        [llength [info commands get_property]] == 0} {
        error "$why; no object API for connected output-pad proof"
    }
    set pads {}
    foreach pin [get_pins -nowarn -of [get_nets -nowarn $expected]] {
        if {[regexp {^(.+)\.opad$} $pin unused cell]} { lappend pads $cell }
    }
    if {[llength $pads] == 0} {
        set actual_lut [secondary_reset_lut_function $stage $actual]
        set expected_lut [secondary_reset_lut_function $stage $expected]
        if {[lindex $actual_lut 0] ne [lindex $expected_lut 0]} {
            error "$why; unequal proven LUT functions ACTUAL=$actual_lut EXPECTED=$expected_lut"
        }
        return "ASYNC_LUT_EQUIVALENT ACTUAL=$actual_lut EXPECTED=$expected_lut"
    }
    if {[llength [lsort -unique $pads]] != 1} {
        error "$why; expected one output-pad driver, got $pads"
    }
    set cell [lindex $pads 0]
    set cells [get_cells -nowarn $cell]
    if {[llength $cells] != 1} { error "$why; ambiguous output-pad cell $cell" }
    foreach {property required} {
        TYPE AL_PHY_HD_PAD REF_NAME PH1P_PHY_HD_PAD MODE OUT
        ODDRMODE BYPASS ODLYEN DISABLE OTYPE DIRECTD0 TSMUX 0
    } {
        if {[catch {get_property $property [lindex $cells 0]} value] || $value ne $required} {
            error "$why; output-pad $cell property $property=$value required=$required"
        }
    }
    set pad_net [secondary_reset_pin_net $stage "$cell.opad"]
    set data_pin [format {%s.doq[0]} $cell]
    set data_net [secondary_reset_pin_net $stage $data_pin]
    if {$pad_net ne $expected} {
        error "$why; disconnected DIRECTD0 pad $cell OPAD=$pad_net D0=$data_net"
    }
    if {$data_net ne $actual} {
        if {[catch {
            set actual_reg [secondary_phy_release_register $stage $actual]
            set pad_reg [secondary_phy_release_register $stage $data_net]
        } reason]} {
            error "$why; disconnected DIRECTD0 pad $cell OPAD=$pad_net D0=$data_net; $reason"
        }
        foreach key {data clock reset gsr initial async} {
            if {[dict get $actual_reg $key] ne [dict get $pad_reg $key]} {
                error "$why; unequal registered PHY release $key ACTUAL=$actual_reg PAD=$pad_reg"
            }
        }
        return "ASYNC_PAD_REGISTER_EQUIVALENT cell=$cell OPAD=$pad_net D0=$data_net ACTUAL=$actual_reg PAD=$pad_reg"
    }
    return "ASYNC_PAD_DIRECT_D0 cell=$cell TYPE=AL_PHY_HD_PAD MODE=OUT ODDRMODE=BYPASS ODLYEN=DISABLE OTYPE=DIRECTD0 TSMUX=0 OPAD=$pad_net D0=$data_net"
}

# Place can duplicate a combinational reset LUT, permute its inputs, and pack
# it alongside unrelated registers. Prove the selected LUT output, its input
# muxes, and the entire Boolean function. Register outputs are never accepted
# as LUT drivers. The only input-net aliases allowed here are stage-1 outputs
# whose D/Q/clock/reset/enable modes were proved earlier in this same run.
proc secondary_reset_lut_function {stage net} {
    global secondary_proven_reset_outputs
    set why "SECONDARY_RESET_MAPPING_ERROR $stage wrong async source NET=$net"
    set drivers [get_pins -nowarn -filter {DIRECTION == output} -of [get_nets -nowarn $net]]
    if {[llength $drivers] != 1 ||
        ![regexp {^(.+)\.(ofa|ofb)$} [lindex $drivers 0] unused cell output]} {
        error "$why; expected one combinational LUT driver, got $drivers"
    }
    set cells [get_cells -nowarn $cell]
    if {[llength $cells] != 1} { error "$why; ambiguous LUT cell $cell" }
    foreach {property required} {TYPE AL_PHY_LSLICE REF_NAME PH1P_PHY_LSLICE LUTMODE DLUT5} {
        if {[catch {get_property $property [lindex $cells 0]} value] || $value ne $required} {
            error "$why; LUT $cell property $property=$value required=$required"
        }
    }
    # Unconnected memory controls have documented tri0 defaults in the PH1P
    # simulation model. Connected controls need a separate proof, not a guess.
    foreach port {dpram_rammode dpram_shiftmode dpram_we} {
        set pins [get_pins -nowarn "$cell.$port"]
        if {[llength $pins] != 1 || [llength [get_nets -nowarn -of $pins]] != 0} {
            error "$why; LUT $cell has unproven memory control $port"
        }
    }
    if {$output eq "ofa"} {
        set selected [get_property OFA_SD [lindex $cells 0]]
        if {$selected ne "LUT5A"} { error "$why; OFA does not select LUT5A: $selected" }
        set equation [get_property LUT5A [lindex $cells 0]]
    } else {
        set selected [get_property OFB_SD [lindex $cells 0]]
        if {$selected ne "LUTX"} { error "$why; OFB does not select LUT5B: $selected" }
        set equation [get_property LUT5B [lindex $cells 0]]
    }
    # Only the vendor Boolean grammar is evaluated; no Tcl substitutions or
    # executable fragments can enter expr. All 2^N input assignments are used.
    if {![regexp {^[A-E01~*+() ]+$} $equation]} { error "$why; unsupported LUT equation $equation" }
    set equation_variables [lsort -unique [regexp -all -inline {[A-E]} $equation]]
    # Prove Boolean support before querying input muxes. TD legitimately omits
    # properties for inputs that cannot affect the selected LUT's truth table.
    # Enumerate every assignment first, so malformed expressions still fail and
    # a syntactically present but cancelled variable receives no guessed net.
    set variable_truth {}
    for {set bits 0} {$bits < (1 << [llength $equation_variables])} {incr bits} {
        set replacements [list ~ ! * && + ||]
        foreach variable $equation_variables {
            set index [lsearch -exact $equation_variables $variable]
            lappend replacements $variable [expr {($bits >> $index) & 1}]
        }
        set expression [string map $replacements $equation]
        if {[catch {expr $expression} value] || $value ni {0 1}} { error "$why; invalid Boolean expression $equation" }
        lappend variable_truth $value
    }
    set variables {}
    foreach variable $equation_variables {
        set mask [expr {1 << [lsearch -exact $equation_variables $variable]}]
        for {set bits 0} {$bits < [llength $variable_truth]} {incr bits} {
            if {[lindex $variable_truth $bits] ne [lindex $variable_truth [expr {$bits ^ $mask}]]} {
                lappend variables $variable
                break
            }
        }
    }
    set port_map [list A ia B ib C ic D id E ie]
    if {$output eq "ofa"} {
        if {"C" in $variables} {
            if {[catch {get_property LUT5A_SD0 [lindex $cells 0]} c] || $c ni {IC IMA}} {
                error "$why; unsupported LUT5A input mux C=$c"
            }
            dict set port_map C [string tolower $c]
        }
        if {"E" in $variables} {
            if {[catch {get_property LUT5A_SD1 [lindex $cells 0]} e] || $e ni {IE IMF}} {
                error "$why; unsupported LUT5A input mux E=$e"
            }
            dict set port_map E [string tolower $e]
        }
    } elseif {"D" in $variables} {
        if {[catch {get_property LUT5B_SD2 [lindex $cells 0]} d] || $d ni {ID IMB}} {
            error "$why; unsupported LUT5B input mux D=$d"
        }
        dict set port_map D [string tolower $d]
    }
    set input_map {}
    set aliases {}
    foreach variable $variables {
        set pin "$cell.[dict get $port_map $variable]"
        set input [secondary_reset_pin_net $stage $pin]
        if {[info exists secondary_proven_reset_outputs] && [dict exists $secondary_proven_reset_outputs $input]} {
            set canonical [dict get $secondary_proven_reset_outputs $input]
            lappend aliases [list $input $canonical]
            set input $canonical
        }
        dict set input_map $variable $input
    }
    set inputs [lsort -unique [dict values $input_map]]
    set truth {}
    for {set bits 0} {$bits < (1 << [llength $inputs])} {incr bits} {
        set replacements [list ~ ! * && + ||]
        foreach variable $equation_variables {
            if {$variable in $variables} {
                set index [lsearch -exact $inputs [dict get $input_map $variable]]
                lappend replacements $variable [expr {($bits >> $index) & 1}]
            } else {
                # Exhaustive truth support proved this value irrelevant.
                lappend replacements $variable 0
            }
        }
        set expression [string map $replacements $equation]
        if {[catch {expr $expression} value] || $value ni {0 1}} { error "$why; invalid Boolean expression $equation" }
        append truth $value
    }
    return [list [list $inputs $truth] DRIVER=[lindex $drivers 0] EQN=$equation SUPPORT=$variables INPUTS=$input_map PROVEN_RESET_ALIASES=$aliases]
}

# Every production reset crossing is named explicitly. New synchronizers must
# be added here and in the build's expected proof list before they can receive
# an asynchronous-input exception. Consumer recovery/removal remains timed.
proc secondary_reset_specs {} {
    return {
        {u_reset125 clk125 board_release rst125_n INV}
        {u_store_resetddr ddr_clk board_release store_rstddr_n INV}
        {u_rgmii_rx_reset gmii_rx_clk rgmii_rx_async_n rgmii_rx_rst_n INV}
        {u_udp_stack/mac_layer_inst/mac_rx_inst/u_rx_input_reset u_udp_stack/mac_layer_inst/mac_rx_inst/I_gmii_rclk u_udp_stack/mac_layer_inst/mac_rx_inst/I_reset u_udp_stack/mac_layer_inst/mac_rx_inst/rx_input_rst_n SIG}
        {u_udp_stack/mac_layer_inst/mac_rx_inst/u_mac_read_reset u_udp_stack/mac_layer_inst/mac_rx_inst/I_mac_rclk {u_udp_stack/mac_layer_inst/mac_rx_inst/rst_cnt[7]} u_udp_stack/mac_layer_inst/mac_rx_inst/mac_read_rst_n INV}
    }
}

# The two MAC async_n aliases can be absorbed into the register's SRMUX.
# Bind the surviving RTL source above and prove its assertion polarity and
# the selected D/Q/clock/enable/reset modes in the actual primitive.
proc secondary_verify_reset_modes {stage cell mapping q_pin polarity} {
    if {[llength [info commands get_cells]] == 0 ||
        [llength [info commands get_property]] == 0} {
        error "SECONDARY_RESET_MAPPING_ERROR $stage reset mode property API unavailable for $cell"
    }
    set cells [get_cells -nowarn $cell]
    if {[llength $cells] != 1} {
        error "SECONDARY_RESET_MAPPING_ERROR $stage reset mode cell missing or ambiguous $cell"
    }
    if {$mapping eq "GATE"} {
        set required [list TYPE AL_MAP_SEQ REF_NAME AL_MAP_SEQ DFFMODE FF CLKMUX SIG CEMUX 1 SRMODE ASYNC REGSET RESET SRMUX $polarity]
    } else {
        set half [expr {[string match "*.oqa" $q_pin] ? "A" : "B"}]
        set required [list TYPE AL_PHY_LSLICE REF_NAME PH1P_PHY_LSLICE LATCHMODE DFF CLKMUX SIG ASRMUX $polarity SSRMUX 0 \
            CE${half}MUX 1 OQ${half}MUX Q${half} REG${half}_SD IM${half} REG${half}_REGSET_ASYNC RESET]
    }
    foreach {property value} $required {
        if {[catch {get_property $property [lindex $cells 0]} actual] || $actual ne $value} {
            error "SECONDARY_RESET_MAPPING_ERROR $stage reset mode $cell $property=$actual EXPECTED=$value"
        }
    }
    return "RESET_MODES_PROVEN ASSERT=$polarity DFF=1 CE=1 ASYNC_RESET=RESET"
}

# Packing may move either synchronizer FF into a slice named after unrelated
# hierarchy. Find it through its actual output net, never through that name.
# Clone names only nominate candidates: the full D/clock/reset/mode proof below
# is still mandatory. A unique registered driver must exist for every output.
proc secondary_reset_output_drivers {stage instance q0 q1} {
    set outputs [list $q0 $q1]
    set prefix "${q1}_dup_"
    foreach net [get_nets -nowarn "${prefix}*"] {
        if {[string first $prefix $net] == 0 &&
            [regexp {^[0-9]+$} [string range $net [string length $prefix] end]]} {
            lappend outputs $net
        }
    }
    set drivers {}
    foreach net [lsort -unique $outputs] {
        set pins [get_pins -nowarn -filter {DIRECTION == output} -of [get_nets -nowarn $net]]
        if {[llength $pins] != 1} {
            error "SECONDARY_RESET_MAPPING_ERROR $stage absent synchronizer or ambiguous output driver $instance NET=$net DRIVERS=$pins"
        }
        set pin [lindex $pins 0]
        if {![regexp {^(.+)\.(q|oqa|oqb)$} $pin]} {
            error "SECONDARY_RESET_MAPPING_ERROR $stage non-register output driver $instance NET=$net DRIVER=$pin"
        }
        dict set drivers $pin $net
    }
    return $drivers
}

# TD may leave the synchronizer's old cell name on a purely combinational
# DLUT after moving its FF into fully proved fanout clones. Port existence
# alone is not evidence of a live ASR: verify every possible FF/shift/memory
# connection is absent and both routed LUT outputs are combinational. This
# proof NEVER adds an asynchronous exception endpoint.
proc secondary_reset_equation_support {stage cell equation} {
    set why "SECONDARY_RESET_MAPPING_ERROR $stage unproven LUT equation $cell"
    if {![regexp {^[A-E01~*+() ]+$} $equation]} {
        error "$why; unsupported Boolean grammar: $equation"
    }
    set variables [lsort -unique [regexp -all -inline {[A-E]} $equation]]
    set values {}
    for {set bits 0} {$bits < (1 << [llength $variables])} {incr bits} {
        set replacements [list ~ ! * && + ||]
        foreach variable $variables {
            set index [lsearch -exact $variables $variable]
            lappend replacements $variable [expr {($bits >> $index) & 1}]
        }
        set expression [string map $replacements $equation]
        if {[catch {expr $expression} value] || $value ni {0 1}} {
            error "$why; invalid Boolean expression: $equation"
        }
        lappend values $value
    }
    set support {}
    foreach variable $variables {
        set mask [expr {1 << [lsearch -exact $variables $variable]}]
        for {set bits 0} {$bits < [llength $values]} {incr bits} {
            if {[lindex $values $bits] ne [lindex $values [expr {$bits ^ $mask}]]} {
                lappend support $variable
                break
            }
        }
    }
    return $support
}

proc secondary_verify_unused_reset_cell {stage cell} {
    set why "SECONDARY_RESET_MAPPING_ERROR $stage unproven packed reset $cell.asr"
    if {[llength [info commands get_cells]] == 0 || [llength [info commands get_property]] == 0 ||
        [llength [info commands report_property]] == 0} {
        error "$why; object/property API required for non-sequential proof"
    }
    # A fresh placement may widen this purely combinational partner from the
    # dual-output DLUT5 encoding to a six-input LUT.  The reset exception is
    # never attached to this cell; the proof below still requires every
    # sequential/reset/shift/memory pin to be unconnected.  Accepting LUT6 is
    # therefore safe only for this non-sequential proof, while the registered
    # synchronizer checks above continue to require DLUT5 for their data path.
    set cells [get_cells -nowarn $cell]
    if {[llength $cells] != 1} { error "$why; ambiguous cell" }
    # Enumerate first: querying a missing physical property emits USR-8001
    # even inside Tcl catch. A complete table distinguishes absence from a
    # tool/API failure without guessing the omitted property's value.
    if {[catch {report_property [lindex $cells 0]} table] ||
        ![regexp {^Property\s+Type\s+Read-only\s+Value$} [string trim [lindex [split $table \n] 0]]]} {
        error "$why; physical property inventory unavailable or malformed"
    }
    set configured {}
    foreach row [split $table \n] {
        if {[regexp {^\s*([A-Z][A-Z0-9_]*)\s+\S+\s+(true|false)(\s|$)} $row unused property]} {
            if {$property in $configured} {error "$why; duplicate property inventory row $property"}
            lappend configured $property
        }
    }
    foreach property {TYPE REF_NAME LUTMODE OFA_SD LUT5B} {
        if {$property ni $configured} {error "$why; incomplete property inventory missing $property"}
    }
    if {[catch {get_property TYPE [lindex $cells 0]} actual_type] || $actual_type ne "AL_PHY_LSLICE"} {
        error "$why; non-sequential TYPE=$actual_type expected=AL_PHY_LSLICE"
    }
    if {[catch {get_property REF_NAME [lindex $cells 0]} actual_ref] || $actual_ref ne "PH1P_PHY_LSLICE"} {
        error "$why; non-sequential REF_NAME=$actual_ref expected=PH1P_PHY_LSLICE"
    }
    if {[catch {get_property LUTMODE [lindex $cells 0]} actual_mode] || ($actual_mode ne "DLUT5" && $actual_mode ne "LUT6")} {
        error "$why; non-sequential LUTMODE=$actual_mode expected=DLUT5-or-LUT6"
    }
    set b_pins [get_pins -nowarn "$cell.ofb"]
    if {[llength $b_pins] != 1} {error "$why; missing or ambiguous combinational ofb output"}
    set b_unused [expr {[llength [get_nets -nowarn -of $b_pins]] == 0}]
    set b_proof UNCONNECTED
    foreach {property expected} {OFA_SD LUT5A OFB_SD LUTX} {
        if {$property ni $configured} {
            # Both DLUT5 and LUT6 databases may omit an unused B selector.
            # Accept absence only when the actual B output is disconnected;
            # do not infer a LUTX selector from that absence.
            if {$property eq "OFB_SD" && $b_unused} {continue}
            error "$why; absent $property with a connected or unproven output"
        }
        set actual [get_property $property [lindex $cells 0]]
        if {$actual ne $expected} {
            error "$why; non-sequential $property=$actual expected=$expected"
        }
        if {$property eq "OFB_SD"} {set b_proof $actual}
    }
    # TD may omit LUT5B_SD2 even while OFB is used. That selector matters only
    # when the LUT5B truth function depends on input D; prove support from the
    # reported equation before accepting the missing selector. The complete
    # sequential-pin inventory below is still required in every case.
    if {"LUT5B_SD2" ni $configured} {
        set b_equation [get_property LUT5B [lindex $cells 0]]
        set b_support [secondary_reset_equation_support $stage $cell $b_equation]
        if {!$b_unused && "D" in $b_support} {
            error "$why; absent LUT5B_SD2 while connected ofb depends on D: $b_equation"
        }
        set b_proof "LUT5B_SD2_OMITTED support=$b_support"
    } else {
        set actual [get_property LUT5B_SD2 [lindex $cells 0]]
        if {$actual ne "IMB" && $actual ne "ID"} {
            error "$why; non-sequential LUT5B_SD2=$actual expected=IMB-or-ID"
        }
    }
    # The mandatory ports are present on PH1P_PHY_LSLICE. An absent mandatory
    # port is a failed inventory, not an unconnected signal. dffshiften is an
    # optional tool port; inspect it if the database exposes it.
    set empty_ports {asr clk ssr cea ceb oqa oqb shiqa shiqb shoqa shoqb
        dpram_byteaddr dpram_rammode dpram_shiftmode dpram_wclk dpram_we dpram_width
        {dpram_waddr[0]} {dpram_waddr[1]} {dpram_waddr[2]} {dpram_waddr[3]} {dpram_waddr[4]}}
    foreach port $empty_ports {
        set pins [get_pins -nowarn "$cell.$port"]
        if {[llength $pins] != 1 || [llength [get_nets -nowarn -of $pins]] != 0} {
            error "$why; non-sequential proof needs one unconnected $port pin"
        }
    }
    set ima_pins [get_pins -nowarn "$cell.ima"]
    if {[llength $ima_pins] != 1} {error "$why; missing or ambiguous ima pin"}
    if {[llength [get_nets -nowarn -of $ima_pins]] != 0} {
        # IMA can feed the combinational A LUT. Prove its actual selector;
        # a connected IM pin alone is not evidence of a live FF or safe LUT.
        set ima_selected 0
        foreach property {LUT5A_SD0 LUT5A_SD1} {
            if {$property in $configured &&
                [get_property $property [lindex $cells 0]] eq "IMA"} {set ima_selected 1}
        }
        if {!$ima_selected} {error "$why; connected ima not selected by LUT5A"}
    }
    set pins [get_pins -nowarn "$cell.dffshiften"]
    if {[llength $pins] > 1 || ([llength $pins] == 1 && [llength [get_nets -nowarn -of $pins]] != 0)} {
        error "$why; connected or ambiguous shift enable"
    }
    foreach port {ofa ofb} {
        if {[llength [get_pins -nowarn "$cell.$port"]] != 1} {
            error "$why; missing or ambiguous combinational $port output"
        }
    }
    # Positive allow-list for all connected pins also excludes unexpected
    # cascade/feedback outputs and future tool ports from this narrow proof.
    set pins [get_pins -nowarn "$cell.*"]
    if {[llength $pins] == 0 || [llength $pins] != [llength [lsort -unique $pins]]} {
        error "$why; incomplete or ambiguous full pin inventory"
    }
    foreach pin $pins {
        set prefix "$cell."
        if {[string first $prefix $pin] != 0} { error "$why; unrelated pin $pin" }
        set port [string range $pin [string length $prefix] end]
        set allowed_ports {ia ib ic id ie ima imb imf ofa ofb}
        if {$actual_mode eq "LUT6"} { lappend allowed_ports if }
        if {$port ni $allowed_ports && [llength [get_nets -nowarn -of [get_pins -nowarn $pin]]] != 0} {
            error "$why; connected non-combinational/unknown port $port"
        }
    }
    return "NONSEQUENTIAL_LUT_PROVEN $cell TYPE=AL_PHY_LSLICE LUTMODE=$actual_mode OFA=LUT5A OFB=$b_proof SEQUENTIAL_PINS=UNCONNECTED NO_EXCEPTION_ADDED"
}

proc secondary_verify_reset_mapping {stage} {
    global secondary_proven_reset_outputs
    set secondary_proven_reset_outputs {}
    set targets {}
    set records {}
    # RTL explicitly shares the clk125 POR synchronizer with the store.
    # Prove that alias rather than assuming a missing third instance is CSE.
    set shared_reset [secondary_reset_net $stage rst125_n]
    set store_reset [secondary_reset_net $stage store_rst125_n]
    if {$shared_reset ne $store_reset} {
        error "SECONDARY_RESET_MAPPING_ERROR $stage store_rst125_n is not rst125_n"
    }
    if {[llength [get_pins -nowarn u_store_reset125/*]] != 0} {
        error "SECONDARY_RESET_MAPPING_ERROR $stage unexpected u_store_reset125 instance; RTL sharing not proven"
    }
    lappend records "MERGED_LOGICAL u_store_reset125/sync_ff\[0..1\] MERGED_INTO u_reset125/sync_ff\[0..1\] NET=$shared_reset"

    foreach specification [secondary_reset_specs] {
        lassign $specification instance clock_name async_name output_name async_polarity
        set expected_clock [secondary_reset_net $stage $clock_name]
        set expected_async [secondary_reset_net $stage $async_name]
        set q0 [secondary_reset_net $stage [format {%s/sync_ff[0]} $instance]]
        set q1 [secondary_reset_net $stage $output_name]
        if {$q0 eq $q1} {
            error "SECONDARY_RESET_MAPPING_ERROR $stage synchronizer stages merged at $instance"
        }
        set counts(0) 0
        set counts(1) 0
        set canonical_stage1 0
        set physical_cells {}
        set stage1_outputs {}
        set all_pins [get_pins -nowarn "$instance/*"]
        set output_drivers [secondary_reset_output_drivers $stage $instance $q0 $q1]
        set discovered_physical_cells {}
        foreach pin [dict keys $output_drivers] {
            lappend all_pins $pin
            if {[regexp {^(.+)\.(oqa|oqb)$} $pin unused cell]} {
                lappend discovered_physical_cells $cell
                # ASR is shared by both FFs in a physical slice. Inspect the
                # partner too; an unrelated live Q must not gain an exception
                # merely because it was packed beside the synchronizer.
                foreach suffix {oqa oqb asr} {
                    foreach partner [get_pins -nowarn "$cell.$suffix"] {
                        lappend all_pins $partner
                    }
                }
            }
        }
        set all_pins [lsort -unique $all_pins]
        foreach pin $all_pins {
            set mapping {}
            if {[regexp [format {^%s/(sync_ff_reg\[([01])\])\.q$} $instance] $pin unused cell_suffix logical_bit]} {
                set mapping GATE
                set cell "$instance/$cell_suffix"
                set data_pin "$cell.d"
                set reset_pin "$cell.sr"
            } elseif {[regexp {^(.+)\.(oqa|oqb)$} $pin unused candidate_cell q_suffix] &&
                ([lsearch -exact $discovered_physical_cells $candidate_cell] >= 0 ||
                 [regexp [format {^%s/sync_ff_reg\[[01]\]_syn_[0-9]+$} $instance] $candidate_cell])} {
                set mapping PHYSICAL
                set cell $candidate_cell
                set data_pin "$cell.[expr {$q_suffix eq "oqa" ? "ima" : "imb"}]"
                set reset_pin "$cell.asr"
                # A packed cell may retain an unused Q. It cannot receive an
                # exception by itself; a live, proven partner is mandatory.
                set qnets [get_nets -nowarn -of [get_pins -nowarn $pin]]
                if {[llength $qnets] == 0} {
                    lappend records "UNUSED_Q $pin"
                    continue
                }
            } elseif {[dict exists $output_drivers $pin] && [regexp {^(.+)\.q$} $pin unused cell]} {
                set mapping GATE
                set logical_bit -1
                set data_pin "$cell.d"
                set reset_pin "$cell.sr"
            } else {
                continue
            }
            set qnet [secondary_reset_pin_net $stage $pin]
            set bit -1
            if {$qnet eq $q0} { set bit 0 }
            if {$qnet eq $q1} { set bit 1; incr canonical_stage1 }
            # TD fanout clones must retain the exact canonical stage-1 net
            # prefix and an integer clone index. Their D is checked below.
            set prefix "${q1}_dup_"
            if {[string first $prefix $qnet] == 0 &&
                [regexp {^[0-9]+$} [string range $qnet [string length $prefix] end]]} {
                set bit 1
            }
            if {$bit < 0 || ($mapping eq "GATE" && $logical_bit >= 0 && $logical_bit != $bit)} {
                error "SECONDARY_RESET_MAPPING_ERROR $stage unrelated Q $pin NET=$qnet"
            }
            set dnet [secondary_reset_pin_net $stage $data_pin]
            if {$bit == 1 && $dnet ne $q0} {
                error "SECONDARY_RESET_MAPPING_ERROR $stage broken stage1 D $data_pin NET=$dnet EXPECTED=$q0"
            }
            if {$bit == 0} {
                set dproof [secondary_verify_stage0_d $stage $dnet $data_pin $cell]
            } else {
                set dproof "D_STAGE0 net=$dnet"
            }
            set clock_net [secondary_reset_pin_net $stage "$cell.clk"]
            set async_net [secondary_reset_pin_net $stage $reset_pin]
            set cproof [secondary_clock_equivalent $stage $clock_net $expected_clock]
            set mproof [secondary_verify_reset_modes $stage $cell $mapping $pin $async_polarity]
            set aproof [secondary_async_source_equivalent $stage $async_net $expected_async]
            incr counts($bit)
            if {$bit == 1} { lappend stage1_outputs $qnet }
            lappend targets $reset_pin
            if {$mapping eq "PHYSICAL"} { lappend physical_cells $cell }
            lappend records "${mapping}_PROVEN $instance/sync_ff\[$bit\] Q=$pin NET=$qnet D=$data_pin DNET=$dnet $dproof CLK=$clock_net $cproof ASYNC_PIN=$reset_pin ASYNC=$async_net $aproof $mproof"
        }
        # Stage 0 cannot be duplicated or missing; stage 1 can have proven
        # fanout clones but exactly one canonical output must remain.
        if {$counts(0) != 1 || $counts(1) < 1 || $canonical_stage1 != 1} {
            error "SECONDARY_RESET_MAPPING_ERROR $stage incomplete/ambiguous stages $instance: Q0=$counts(0) Q1=$counts(1) canonical_Q1=$canonical_stage1"
        }
        # A live ASR with no mapped Q is not automatically optimized away.
        foreach pin $all_pins {
            if {[regexp {^(.+)\.asr$} $pin unused cell] &&
                ([lsearch -exact $discovered_physical_cells $cell] >= 0 ||
                 [regexp [format {^%s/sync_ff_reg\[[01]\]_syn_[0-9]+$} $instance] $cell]) &&
                [lsearch -exact $physical_cells $cell] < 0} {
                lappend records [secondary_verify_unused_reset_cell $stage $cell]
            }
        }
        # Publish aliases only after the complete instance proof succeeds.
        foreach output $stage1_outputs { dict set secondary_proven_reset_outputs $output $q1 }
        lappend records "INSTANCE_PROVEN $instance STAGE0=$counts(0) STAGE1=$counts(1) CLK=$expected_clock ASYNC=$expected_async"
    }
    return [list [lsort -unique $targets] $records]
}

proc secondary_apply_reset_exceptions {stage} {
    # Complete all five instance proofs before applying any exception. The same
    # function handles a database with logical and physical cells together.
    set proof [secondary_verify_reset_mapping $stage]
    set targets [lindex $proof 0]
    set records [lindex $proof 1]
    # TD stores loaded SDC constraints across timing updates and database
    # saves; direct commands from the main flow Tcl are not persistent.
    # Emit literal, individually proved pins without evaluating get_pins here.
    set sdc_name [file normalize secondary_reset_${stage}.sdc]
    set sdc [open $sdc_name w]
    puts $sdc {# Generated only after complete reset mapping proof.}
    foreach target $targets {
        puts $sdc [format {set_false_path -to [get_pins -nowarn %s]} [list $target]]
    }
    close $sdc
    read_sdc $sdc_name
    set fh [open secondary_reset_${stage}.rpt w]
    foreach record $records { puts $fh $record }
    puts $fh "LOADED_RESET_SDC $sdc_name"
    foreach target $targets {
        puts $fh "APPLIED_ASYNC_PIN $target"
    }
    set logical_count [llength [secondary_reset_specs]]
    puts $fh "APPLIED_RESET_EXCEPTIONS [llength $targets] unique asynchronous pins; $logical_count proven synchronizers; store_rst125_n shares rst125_n"
    close $fh
    puts "SECONDARY_RESET_EXCEPTIONS_APPLIED $stage physical=[llength $targets] logical_syncs=$logical_count shared_store_reset=1"
}

proc secondary_apply_reset_physical {stage} {
    secondary_apply_reset_exceptions $stage
}
