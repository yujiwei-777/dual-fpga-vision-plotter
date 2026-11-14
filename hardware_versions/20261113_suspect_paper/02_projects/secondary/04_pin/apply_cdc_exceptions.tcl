# Diagnostic candidate only. Requires the reset mapping helper to be sourced.
# Prove every mapping before issuing any constraint. No logical cell-name
# assumptions about packed A/B registers or their shared clock/reset pins.
proc secondary_cdc_property {stage cell key required} {
    set cells [get_cells -nowarn $cell]
    if {[llength $cells] != 1 || [catch {get_property $key [lindex $cells 0]} value] || $value ne $required} {
        error "SECONDARY_CDC_MAPPING_ERROR $stage $cell $key requires $required"
    }
}
proc secondary_cdc_identity_net {stage net} {
    set seen {}
    for {set depth 0} {$depth < 8} {incr depth} {
        if {[lsearch -exact $seen $net] >= 0} {error "SECONDARY_CDC_MAPPING_ERROR $stage identity-buffer cycle at $net"}
        lappend seen $net
        set drivers [get_pins -nowarn -filter {DIRECTION == output} -of [get_nets -nowarn $net]]
        if {[llength $drivers] != 1} {error "SECONDARY_CDC_MAPPING_ERROR $stage ambiguous identity net $net: $drivers"}
        set driver [lindex $drivers 0]
        if {[regexp {^(.+)\.opad$} $driver unused pad]} {
            set data [secondary_reset_pin_net $stage [format {%s.doq[0]} $pad]]
            secondary_async_source_equivalent $stage $data $net
            set net $data
        } elseif {[regexp {^(.+)\.o$} $driver unused cell] && [get_property TYPE [lindex [get_cells -nowarn $cell] 0]] eq "AL_LOGIC_BUFKEEP"} {
            secondary_cdc_property $stage $cell REF_NAME AL_BUFKEEP
            if {[secondary_reset_pin_net $stage "$cell.o"] ne $net} {error "SECONDARY_CDC_MAPPING_ERROR $stage disconnected BUFKEEP output $cell"}
            set net [secondary_reset_pin_net $stage "$cell.i"]
        } else {
            return $net
        }
    }
    error "SECONDARY_CDC_MAPPING_ERROR $stage excessive identity-buffer depth"
}
proc secondary_cdc_reg {stage logical direct_d always_enabled} {
    set net [secondary_cdc_identity_net $stage [secondary_reset_net $stage $logical]]
    set drivers [get_pins -nowarn -filter {DIRECTION == output} -of [get_nets -nowarn $net]]
    if {[llength $drivers] != 1 || ![regexp {^(.+)\.(q|oqa|oqb)$} [lindex $drivers 0] unused cell port]} {
        error "SECONDARY_CDC_MAPPING_ERROR $stage $logical has no unique registered Q: $drivers"
    }
    set q [lindex $drivers 0]
    if {$port eq "q"} {
        foreach {key value} {TYPE AL_MAP_SEQ REF_NAME AL_MAP_SEQ DFFMODE FF CLKMUX SIG SRMODE ASYNC} {
            secondary_cdc_property $stage $cell $key $value
        }
        if {$always_enabled} {
            secondary_cdc_property $stage $cell CEMUX 1
            secondary_cdc_property $stage $cell REGSET RESET
        }
        set d "$cell.d"; set reset "$cell.sr"; set mux SRMUX
    } else {
        set half [expr {$port eq "oqa" ? "A" : "B"}]
        foreach {key value} [list TYPE AL_PHY_LSLICE REF_NAME PH1P_PHY_LSLICE LATCHMODE DFF CLKMUX SIG OQ${half}MUX Q${half} SSRMUX 0] {
            secondary_cdc_property $stage $cell $key $value
        }
        if {$always_enabled} {
            secondary_cdc_property $stage $cell CE${half}MUX 1
            secondary_cdc_property $stage $cell REG${half}_REGSET_ASYNC RESET
        }
        if {$direct_d} {secondary_cdc_property $stage $cell REG${half}_SD IM${half}}
        set d "$cell.[expr {$half eq "A" ? "ima" : "imb"}]"; set reset "$cell.asr"; set mux ASRMUX
    }
    set result [dict create logical $logical net $net q $q clk [secondary_reset_pin_net $stage "$cell.clk"] \
        reset [secondary_reset_pin_net $stage $reset] polarity [get_property $mux [lindex [get_cells -nowarn $cell] 0]]]
    if {[dict get $result polarity] ni {SIG INV}} {error "SECONDARY_CDC_MAPPING_ERROR $stage $logical invalid reset polarity"}
    if {$direct_d} {
        dict set result d $d
        dict set result dnet [secondary_cdc_identity_net $stage [secondary_reset_pin_net $stage $d]]
    }
    return $result
}
proc secondary_cdc_clock {stage reg clock_name} {
    secondary_clock_equivalent $stage [dict get $reg clk] [secondary_reset_net $stage $clock_name]
}
proc secondary_cdc_reset_identity {net} {
    global secondary_proven_reset_outputs
    if {[dict exists $secondary_proven_reset_outputs $net]} {return [dict get $secondary_proven_reset_outputs $net]}
    return $net
}
# Frozen DDR2 CAL_EN=0 exposes state_cnt == S_DONE (5'b01111). Place may
# duplicate that combinational LUT and remove every calibrated/cal_done alias.
# Prove the entire decode using the five registered DDR-domain state bits.
proc secondary_cdc_calibrated_decode {stage net} {
    set state_root u_ddr/u_ddr2/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_dram_init
    set state_nets {}
    set state_records {}
    for {set bit 0} {$bit < 5} {incr bit} {
        set logical [format {%s/state_cnt[%d]} $state_root $bit]
        set reg [secondary_cdc_reg $stage $logical 0 0]
        secondary_cdc_clock $stage $reg ddr_clk
        lappend state_nets [dict get $reg net]
        lappend state_records $reg
    }
    set ordered [lsort -unique $state_nets]
    if {[llength $ordered] != 5} {error "SECONDARY_CDC_MAPPING_ERROR $stage calibrated decode state bits not unique"}
    set selected 0
    for {set bit 0} {$bit < 4} {incr bit} {
        set selected [expr {$selected | (1 << [lsearch -exact $ordered [lindex $state_nets $bit]])}]
    }
    set truth {}
    for {set assignment 0} {$assignment < 32} {incr assignment} {
        append truth [expr {$assignment == $selected ? 1 : 0}]
    }
    set drivers [get_pins -nowarn -filter {DIRECTION == output} -of [get_nets -nowarn $net]]
    if {[llength $drivers] == 1 && [regexp {^(.+)\.o$} [lindex $drivers 0] unused cell]} {
        # Before packing the same five-input decoder is an AL_MAP_LUT5.
        # Prove its pins, equation, and INIT exhaustively; the reset helper
        # intentionally accepts only packed physical LUTs and is unchanged.
        secondary_cdc_property $stage $cell TYPE AL_MAP_LUT
        secondary_cdc_property $stage $cell REF_NAME AL_MAP_LUT5
        set object [lindex [get_cells -nowarn $cell] 0]
        set equation [get_property EQN $object]
        set init [get_property INIT $object]
        if {![regexp {^[A-E01~*+() ]+$} $equation] || ![regexp {^32'[hH]([0-9a-fA-F]{8})$} $init unused init_hex]} {
            error "SECONDARY_CDC_MAPPING_ERROR $stage unsupported gate calibrated decoder EQN=$equation INIT=$init"
        }
        scan $init_hex %x init_bits
        set inputs {}
        foreach port {a b c d e} {lappend inputs [secondary_cdc_identity_net $stage [secondary_reset_pin_net $stage "$cell.$port"]]}
        if {[lsort -unique $inputs] ne $ordered} {error "SECONDARY_CDC_MAPPING_ERROR $stage gate calibrated decoder has unexpected inputs"}
        set actual_truth {}
        for {set assignment 0} {$assignment < 32} {incr assignment} {
            set replacements [list ~ ! * && + ||]
            set init_index 0
            foreach variable {A B C D E} input $inputs {
                set value [expr {($assignment >> [lsearch -exact $ordered $input]) & 1}]
                lappend replacements $variable $value
                set init_index [expr {$init_index | ($value << [lsearch -exact {A B C D E} $variable])}]
            }
            if {[catch {expr [string map $replacements $equation]} value] || $value ni {0 1} || $value != (($init_bits >> $init_index) & 1)} {
                error "SECONDARY_CDC_MAPPING_ERROR $stage inconsistent gate calibrated decoder EQN/INIT"
            }
            append actual_truth $value
        }
        set actual [list [list $ordered $actual_truth] "GATE_LUT5 cell=$cell EQN=$equation INIT=$init"]
    } else {
        set actual [secondary_reset_lut_function $stage $net]
    }
    if {[lindex $actual 0] ne [list $ordered $truth]} {
        error "SECONDARY_CDC_MAPPING_ERROR $stage calibrated decode is not proven DDR state_cnt==01111: $actual"
    }
    return "CALIBRATED_DECODE_PROVEN CAL_EN=0 S_DONE=01111 SOURCE=$actual STATE_REGISTERS=$state_records"
}

proc secondary_cdc_pair {stage first_name second_name source_name destination_clock} {
    set first [secondary_cdc_reg $stage $first_name 1 1]
    set second [secondary_cdc_reg $stage $second_name 1 1]
    secondary_cdc_clock $stage $first $destination_clock
    secondary_cdc_clock $stage $second $destination_clock
    if {[dict get $first net] eq [dict get $second net] || [dict get $second dnet] ne [dict get $first net]} {
        error "SECONDARY_CDC_MAPPING_ERROR $stage broken two-stage chain $first_name $second_name"
    }
    set source_alias [get_nets -nowarn $source_name]
    if {$source_name eq "u_store/calibrated" && [llength $source_alias] == 0} {
        dict set first source_proof [secondary_cdc_calibrated_decode $stage [dict get $first dnet]]
    } elseif {[dict get $first dnet] ne [secondary_cdc_identity_net $stage [secondary_reset_net $stage $source_name]]} {
        error "SECONDARY_CDC_MAPPING_ERROR $stage $first_name wrong source $source_name"
    }
    if {[secondary_cdc_reset_identity [dict get $first reset]] ne [secondary_cdc_reset_identity [dict get $second reset]] ||
        [dict get $first polarity] ne [dict get $second polarity]} {
        error "SECONDARY_CDC_MAPPING_ERROR $stage mismatched synchronizer reset $first_name $second_name"
    }
    return [list $first $second]
}
proc secondary_verify_cdc_mapping {stage} {
    # This also fills only rigorously proved same-run reset-output aliases.
    secondary_verify_reset_mapping $stage
    set records {}; set gray_d {}; set control_d {}; set control_q {}; set control_regs {}; set stage2_d {}; set same_domain_d {}
    set expected_inventory {}
    foreach {fifo width write_clock read_clock} {
        u_udp_stack/mac_layer_inst/mac_rx_inst/mac_receive_fifo 12 gmii_rx_clk clk125
        u_udp_stack/mac_layer_inst/mac_rx_inst/mac_rdata_len_fifo 7 gmii_rx_clk clk125
        u_udp_stack/mac_layer_inst/udp_pkg_buf_inst 7 gmii_rx_clk clk125
        u_udp_stack/mac_layer_inst/mac_tx_inst/max_send_fifo 12 clk125 clk125
        u_udp_stack/mac_layer_inst/mac_tx_inst/mac_tx_frame_info_fifo 7 clk125 clk125
        u_udp_stack/ip_layer_inst/icmp_echo_data_fifo 11 clk125 clk125
    } {
        foreach direction {rd_to_wr wr_to_rd} {
            if {$direction eq "rd_to_wr"} {set src_clock $read_clock; set dst_clock $write_clock} else {set src_clock $write_clock; set dst_clock $read_clock}
            set instance "$fifo/${direction}_cross_inst"
            for {set bit 0} {$bit < $width} {incr bit} {
                set first_name [format {%s/sync_r1[%d]} $instance $bit]
                set second_name [format {%s/primary_addr_gray_sync[%d]} $instance $bit]
                set source_name [format {%s/primary_addr_gray_reg[%d]} $instance $bit]
                lassign [secondary_cdc_pair $stage $first_name $second_name $source_name $dst_clock] first second
                set source [secondary_cdc_reg $stage $source_name 0 0]
                secondary_cdc_clock $stage $source $src_clock
                lappend expected_inventory [secondary_reset_net $stage $first_name]
                lappend stage2_d [dict get $second d]
                if {$src_clock ne $dst_clock} {
                    lappend gray_d [dict get $first d]
                    set category ASYNC_GRAY
                } else {
                    lappend same_domain_d [dict get $first d]
                    set category SAME_CLOCK_GRAY_NO_EXCEPTION
                }
                lappend records "$category SOURCE=$source FIRST=$first SECOND=$second"
            }
        }
    }
    set actual_inventory [get_nets -nowarn {u_udp_stack/*/sync_r1[*]}]
    if {[lsort -unique $expected_inventory] ne [lsort -unique $actual_inventory] || [llength $gray_d] != 52 || [llength $same_domain_d] != 60} {
        error "SECONDARY_CDC_MAPPING_ERROR $stage incomplete Gray inventory"
    }
    foreach {base source clock} {wreq wreq ddr_clk rreq rreq ddr_clk wack wack clk125 rack rack clk125 cal calibrated clk125} {
        lassign [secondary_cdc_pair $stage [format {u_store/%s_sync[0]} $base] [format {u_store/%s_sync[1]} $base] "u_store/$source" $clock] first second
        lappend control_d [dict get $first d]
        lappend control_regs [dict get $first net]
        if {$base eq "cal"} {
            # Prove the five-source decoder even when calibrated/cal_done
            # aliases survive. Each Q is then the exact launch-data filter.
            dict set first source_proof [secondary_cdc_calibrated_decode $stage [dict get $first dnet]]
            for {set bit 0} {$bit < 5} {incr bit} {
                set name [format {u_ddr/u_ddr2/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_dram_init/state_cnt[%d]} $bit]
                set source_reg [secondary_cdc_reg $stage $name 0 0]
                secondary_cdc_clock $stage $source_reg ddr_clk
                lappend control_q [dict get $source_reg q]
                lappend records "MAILBOX_CONTROL_SOURCE CALIBRATED_STATE=$source_reg"
            }
        } else {
            set source_reg [secondary_cdc_reg $stage "u_store/$source" 0 0]
            secondary_cdc_clock $stage $source_reg [expr {$clock eq "ddr_clk" ? "clk125" : "ddr_clk"}]
            if {[dict get $first dnet] ne [dict get $source_reg net]} {error "SECONDARY_CDC_MAPPING_ERROR $stage control source disconnected $base"}
            lappend control_q [dict get $source_reg q]
            lappend records "MAILBOX_CONTROL_SOURCE TOGGLE=$source_reg"
        }
        lappend stage2_d [dict get $second d]
        lappend records "MAILBOX_CONTROL FIRST=$first SECOND=$second"
    }
    if {[llength $control_q] != 9 || [llength $control_regs] != 5} {error "SECONDARY_CDC_MAPPING_ERROR $stage incorrect control inventory"}
    set selected_regs [get_regs -nowarn $control_regs]
    if {[lsort $selected_regs] ne [lsort $control_regs]} {error "SECONDARY_CDC_MAPPING_ERROR $stage control register collection did not resolve exactly"}
    lassign [secondary_cdc_pair $stage phy_link_meta phy_link_sync phy_link_raw clk125] link_first link_second
    set link_source [secondary_cdc_reg $stage phy_link_raw 0 0]
    secondary_cdc_clock $stage $link_source gmii_rx_clk
    lappend stage2_d [dict get $link_second d]
    lappend records "PHY_LINK FIRST=$link_first SECOND=$link_second SOURCE=$link_source"
    set request_q {}
    foreach {pattern count} {{u_store/waddr_hold[*]} 17 {u_store/raddr_hold[*]} 17 {u_store/wdata_hold[*]} 128} {
        set nets [get_regs -nowarn $pattern]
        if {[llength $nets] != $count} {error "SECONDARY_CDC_MAPPING_ERROR $stage held source count $pattern [llength $nets] expected $count"}
        foreach name $nets {
            set reg [secondary_cdc_reg $stage $name 0 0]
            secondary_cdc_clock $stage $reg clk125
            lappend request_q [dict get $reg q]
            lappend records "HELD_REQUEST SOURCE=$reg"
        }
    }
    set return_q {}; set return_d {}
    for {set bit 0} {$bit < 128} {incr bit} {
        set source [secondary_cdc_reg $stage [format {u_store/rdata_hold[%d]} $bit] 0 0]
        set dest [secondary_cdc_reg $stage [format {u_store/rd_data[%d]} $bit] 1 0]
        secondary_cdc_clock $stage $source ddr_clk
        secondary_cdc_clock $stage $dest clk125
        if {[dict get $dest dnet] ne [dict get $source net]} {error "SECONDARY_CDC_MAPPING_ERROR $stage return data bit $bit disconnected"}
        lappend return_q [dict get $source q]; lappend return_d [dict get $dest d]
        lappend records "HELD_RETURN SOURCE=$source DEST=$dest"
    }
    set groups [dict create gray_d $gray_d control_d $control_d control_q $control_q control_regs $control_regs link_d [dict get $link_first d] request_q $request_q return_q $return_q return_d $return_d stage2_d $stage2_d same_domain_d $same_domain_d]
    foreach group {gray_d control_d control_q control_regs request_q return_q return_d stage2_d same_domain_d} {
        if {[llength [dict get $groups $group]] != [llength [lsort -unique [dict get $groups $group]]]} {error "SECONDARY_CDC_MAPPING_ERROR $stage duplicate mapped pins $group"}
    }
    return [list $groups $records]
}
proc secondary_cdc_pins {stage names} {
    set pins [get_pins -nowarn $names]
    if {[llength $names] == 0 || [lsort $pins] ne [lsort $names]} {
        error "SECONDARY_CDC_MAPPING_ERROR $stage pin collection did not resolve exactly: requested=[llength $names] actual=[llength $pins]"
    }
    return $pins
}
proc secondary_apply_cdc_exceptions {stage} {
    lassign [secondary_verify_cdc_mapping $stage] groups records
    set fh [open secondary_cdc_${stage}.rpt w]
    foreach record $records {puts $fh $record}
    # -through Q retains launch clk2q within the original held-bus budget,
    # while avoiding the other register packed under the same launch clock.
    set ddr_clock [get_clocks {u_ddr/u_ddr2/usr_clk}]
    if {[llength $ddr_clock] != 1} {error "SECONDARY_CDC_MAPPING_ERROR $stage missing DDR clock; initialize timing before applying constraints"}
    foreach group [dict keys $groups] {
        if {$group ne "control_regs"} {dict set resolved $group [secondary_cdc_pins $stage [dict get $groups $group]]}
    }
    # TD replays SDC text when updating timing and when reading a database.
    # Direct commands in the outer Tcl session do not survive that replay.
    set sdc_path [file normalize secondary_cdc_${stage}.sdc]
    set sf [open $sdc_path w]
    puts $sf [format {set_max_delay -through [get_pins -nowarn {%s}] -to [get_clocks {u_ddr/u_ddr2/usr_clk}] -datapath_only 7.000} [dict get $groups request_q]]
    puts $sf [format {set_max_delay -through [get_pins -nowarn {%s}] -to [get_pins -nowarn {%s}] -datapath_only 7.500} [dict get $groups return_q] [dict get $groups return_d]]
    # A packed IM input can also feed a LUT: TD's -to IM then walks the
    # combinational fanout and unintentionally constrains ordinary paths.
    # get_regs selects the proved first-stage register, not that shared input;
    # launch Q filtering excludes its reset paths and the other packed FF.
    puts $sf [format {set_max_delay -through [get_pins -nowarn {%s}] -to [get_regs -nowarn {%s}] -datapath_only 7.500} [dict get $groups control_q] [dict get $groups control_regs]]
    puts $sf [format {set_max_delay -to [get_pins -nowarn {%s}] -datapath_only 7.500} [dict get $groups gray_d]]
    puts $sf [format {set_false_path -to [get_pins -nowarn {%s}]} [dict get $groups link_d]]
    close $sf
    read_sdc $sdc_path
    foreach group [dict keys $groups] {puts $fh "CDC_GROUP $group COUNT=[llength [dict get $groups $group]] PINS=[dict get $groups $group]"}
    puts $fh "CDC_MAPPING_COMPLETE GRAY_ASYNC=52 GRAY_SAME_CLOCK=60 MAILBOX_CONTROL=5 HELD_REQUEST_Q=162 HELD_RETURN_Q_D=128 PHY_LINK=1"
    close $fh
    puts "SECONDARY_CDC_EXCEPTIONS_APPLIED $stage gray=52 control=5 held_request=162 held_return=128 phy_link=1"
    return $groups
}

# Replace every user constraint at each phase so old gate/packed pin names
# cannot survive into the next mapping. IP constraints remain loaded in TD.
proc secondary_apply_phase_timing {stage base_sdc {timing_mode default}} {
    if {$timing_mode ni {default manhattan final}} {error "SECONDARY_CDC_MAPPING_ERROR $stage invalid timing mode $timing_mode"}
    set base_sdc [file normalize $base_sdc]
    if {![file isfile $base_sdc]} {error "SECONDARY_CDC_MAPPING_ERROR $stage missing base SDC $base_sdc"}
    clear_sdc -user
    read_sdc $base_sdc
    if {$timing_mode eq "default"} {update_timing} else {update_timing -mode $timing_mode}
    secondary_apply_reset_exceptions $stage
    set groups [secondary_apply_cdc_exceptions $stage]
    set exact_path [file normalize secondary_exact_${stage}.sdc]
    set fh [open $exact_path w]
    foreach part [list secondary_reset_${stage}.sdc secondary_cdc_${stage}.sdc] {
        set pf [open $part r]; puts $fh [read $pf]; close $pf
    }
    close $fh
    clear_sdc -user
    read_sdc $base_sdc
    read_sdc $exact_path
    if {$timing_mode eq "default"} {update_timing} else {update_timing -mode $timing_mode}
    set effective_path [file normalize secondary_effective_${stage}.sdc]
    export_sdc -file $effective_path
    set ef [open $effective_path r]; set effective [read $ef]; close $ef
    set xf [open $exact_path r]; set exact [read $xf]; close $xf
    set command_count 0
    foreach line [split $exact \n] {
        set line [string trim $line]
        if {$line eq "" || [string index $line 0] eq "#"} {continue}
        if {[string first $line $effective] < 0} {error "SECONDARY_CDC_MAPPING_ERROR $stage exact constraint did not persist: $line"}
        incr command_count
    }
    report_timing_exception -ep_num 4096 -path_num 4 -file secondary_effective_${stage}.exceptions.rpt
    report_timing_ignored -ep_num 4096 -path_num 4 -file secondary_effective_${stage}.ignored.rpt
    set tf [open secondary_effective_${stage}.exceptions.rpt r]; set exceptions [read $tf]; close $tf
    set counts {}
    foreach line [split $exceptions \n] {
        if {[regexp {^\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+set_max_delay } $line unused total dominated shadowed ignored]} {
            if {$dominated != $total || $shadowed != 0 || $ignored != 0} {error "SECONDARY_CDC_MAPPING_ERROR $stage ineffective max-delay constraint $line"}
            lappend counts $total
        }
    }
    if {$counts ne {290 128 9 52}} {error "SECONDARY_CDC_MAPPING_ERROR $stage actual max-delay path coverage $counts expected 290 128 9 52"}
    set reset_targets [lindex [secondary_verify_reset_mapping $stage] 0]
    set rf [open secondary_effective_${stage}.ignored.rpt r]; set ignored_report [read $rf]; close $rf
    foreach target $reset_targets {
        set found 0
        foreach line [split $ignored_report \n] {
            if {[regexp {^\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+([0-9]+)\s+set_false_path -to } $line unused total dominated shadowed ignored] && [string first $target $line] >= 0} {
                if {$total > 0 && $dominated == $total && $shadowed == 0 && $ignored == 0} {set found 1}
            }
        }
        if {!$found} {error "SECONDARY_CDC_MAPPING_ERROR $stage reset exception has no effective path $target"}
    }
    set lf [open secondary_loaded_${stage}.rpt w]
    puts $lf "PERSISTENT_SDC_COMMANDS $command_count"
    puts $lf "EFFECTIVE_RESET_PIN_CONSTRAINTS [llength $reset_targets]"
    puts $lf "EFFECTIVE_SMD_PATHS $counts"
    puts $lf "EXACT_SDC $exact_path"
    puts $lf "EFFECTIVE_SDC $effective_path"
    close $lf
    puts "SECONDARY_TIMING_CONSTRAINTS_LOADED $stage reset_pins=[llength $reset_targets] smd=290,128,9,52 commands=$command_count"
    return $groups
}
