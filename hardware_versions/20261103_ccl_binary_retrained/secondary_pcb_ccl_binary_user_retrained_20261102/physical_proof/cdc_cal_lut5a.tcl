# Review-only narrow override. Source AFTER the frozen reset and CDC helpers.
# No constraints are issued here; all complete phase proofs still run normally.
# Only the physical first DDR-calibration synchronizer may select LUT5A.
if {[llength [info procs secondary_cdc_reg]] != 1 ||
    [info args secondary_cdc_reg] ne {stage logical direct_d always_enabled} ||
    [llength [info procs secondary_cdc_reg_frozen_direct_im]] != 0 ||
    [llength [info procs secondary_cdc_calibrated_decode]] != 1 ||
    [llength [info procs secondary_reset_lut_function]] != 1} {
    error {SECONDARY_CDC_MAPPING_ERROR invalid frozen helper precondition for calibrated LUT5A override}
}
rename secondary_cdc_reg secondary_cdc_reg_frozen_direct_im
proc secondary_cdc_reg {stage logical direct_d always_enabled} {
    if {!$direct_d || $logical ne {u_store/cal_sync[0]}} {
        return [secondary_cdc_reg_frozen_direct_im $stage $logical $direct_d $always_enabled]
    }
    set net [secondary_cdc_identity_net $stage [secondary_reset_net $stage $logical]]
    set drivers [get_pins -nowarn -filter {DIRECTION == output} -of [get_nets -nowarn $net]]
    if {[llength $drivers] != 1 || ![regexp {^(.+)\.oqa$} [lindex $drivers 0] unused cell]} {
        return [secondary_cdc_reg_frozen_direct_im $stage $logical $direct_d $always_enabled]
    }
    set cells [get_cells -nowarn $cell]
    if {[llength $cells] != 1 || [catch {get_property REGA_SD [lindex $cells 0]} select]} {
        error "SECONDARY_CDC_MAPPING_ERROR $stage ambiguous calibrated selected D"
    }
    if {$select ne {LUT5A}} {
        return [secondary_cdc_reg_frozen_direct_im $stage $logical $direct_d $always_enabled]
    }
    if {!$always_enabled} {
        error "SECONDARY_CDC_MAPPING_ERROR $stage calibrated LUT5A requires always-enabled first stage"
    }
    foreach {key value} {TYPE AL_PHY_LSLICE REF_NAME PH1P_PHY_LSLICE LATCHMODE DFF
        CLKMUX SIG OQAMUX QA SSRMUX 0 CEAMUX 1 REGA_REGSET_ASYNC RESET
        REGA_SD LUT5A LUTMODE DLUT5 OFA_SD LUT5A} {
        secondary_cdc_property $stage $cell $key $value
    }
    # In this proven primitive mode the FF D and OFA select the same LUT5A.
    # OFA is a data-observation pin, NOT a timing endpoint. The existing
    # mailbox SDC must continue to target get_regs cal_sync[0], never OFA/IMA.
    set d "$cell.ofa"
    set dnet [secondary_cdc_identity_net $stage [secondary_reset_pin_net $stage $d]]
    set data_drivers [get_pins -nowarn -filter {DIRECTION == output} -of [get_nets -nowarn $dnet]]
    if {[llength $data_drivers] != 1 || [lindex $data_drivers 0] ne $d} {
        error "SECONDARY_CDC_MAPPING_ERROR $stage calibrated LUT5A output connectivity is not unique"
    }
    # Existing helper proves actual LUT mode, input muxes, input support and
    # all 32 combinations of the five registered DDR state bits == 01111.
    # It also checks all five source clocks; no name-only/selector-only pass.
    set proof [secondary_cdc_calibrated_decode $stage $dnet]
    set result [dict create logical $logical net $net q [lindex $drivers 0] \
        clk [secondary_reset_pin_net $stage "$cell.clk"] \
        reset [secondary_reset_pin_net $stage "$cell.asr"] \
        polarity [get_property ASRMUX [lindex $cells 0]] \
        d $d dnet $dnet d_role SELECTED_LUT_OUTPUT_OBSERVATION_ONLY \
        data_select REGA_SD=LUT5A data_proof $proof]
    if {[dict get $result polarity] ni {SIG INV}} {
        error "SECONDARY_CDC_MAPPING_ERROR $stage calibrated LUT5A invalid reset polarity"
    }
    return $result
}
