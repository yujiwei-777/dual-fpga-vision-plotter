# Read-only API fixture: executes the ACTUAL frozen Tcl + narrow overlay.
# This is proof-helper fault injection, not a TD/physical-netlist pass.
set here [file dirname [file normalize [info script]]]
source [file join $here ../../.. 04_pin apply_reset_exceptions.tcl]
source [file join $here ../../.. 04_pin apply_cdc_exceptions.tcl]
source [file join $here calibrated_lut5a_override.tcl]
proc get_cells {args} {global props;set key [lindex $args end];if {[dict exists $props $key]} {return [list $key]};return {}}
proc get_property {key cell} {global props;return [dict get $props $cell $key]}
proc get_nets {args} {
 global aliases pin_net drivers
 set i [lsearch -exact $args -of]
 if {$i >= 0} {set p [lindex [lindex $args [expr {$i+1}]] 0];if {[dict exists $pin_net $p] && [dict get $pin_net $p] ne {}} {return [list [dict get $pin_net $p]]};return {}}
 set n [lindex $args end]
 if {[dict exists $aliases $n]} {return [list [dict get $aliases $n]]}
 if {[dict exists $drivers $n]} {return [list $n]}
 return {}
}
proc get_pins {args} {
 global drivers pin_net
 set i [lsearch -exact $args -of]
 if {$i >= 0} {set n [lindex [lindex $args [expr {$i+1}]] 0];if {[dict exists $drivers $n]} {return [dict get $drivers $n]};return {}}
 set p [lindex $args end];if {[dict exists $pin_net $p]} {return [list $p]};return {}
}
proc pin {p n {output 0}} {global pin_net drivers;dict set pin_net $p $n;if {$output} {dict lappend drivers $n $p}}
proc fixture {} {
 global props aliases pin_net drivers first second state_root secondary_proven_reset_outputs
 set props {};set aliases {};set pin_net {};set drivers {};set secondary_proven_reset_outputs {}
 set first {u_store/cal_sync_reg[0]_syn_2};set second {u_store/cal_sync_reg[1]_syn_2}
 set state_root u_ddr/u_ddr2/ph1p_ddrmc_wrapper/ph1p_ddrmc_top/u_ddr_phy/u_ddrphy_dram_init
 dict set aliases clk125 clk125;dict set aliases ddr_clk ddr_clk
 set common {TYPE AL_PHY_LSLICE REF_NAME PH1P_PHY_LSLICE LATCHMODE DFF CLKMUX SIG OQAMUX QA SSRMUX 0 CEAMUX 1 REGA_REGSET_ASYNC RESET ASRMUX INV LUTMODE DLUT5 OFA_SD LUT5A REGA_SD LUT5A LUT5A (~C*B*E*D*A) LUT5A_SD0 IMA LUT5A_SD1 IE}
 dict set props $first $common;dict set props $second [dict replace $common REGA_SD IMA]
 foreach cell [list $first $second] {
  pin $cell.clk clk125;pin $cell.asr reset125
  foreach port {dpram_rammode dpram_shiftmode dpram_we} {pin $cell.$port {}}
 }
 pin $first.oqa cal0 1;pin $first.ofa calibrated 1;pin $second.oqa cal1 1
 pin $second.ima cal0
 dict set aliases {u_store/cal_sync[0]} cal0;dict set aliases {u_store/cal_sync[1]} cal1;dict set aliases u_store/calibrated calibrated
 for {set b 0} {$b < 5} {incr b} {
  set n [format {%s/state_cnt[%d]} $state_root $b];set c state$b
  dict set props $c {TYPE AL_MAP_SEQ REF_NAME AL_MAP_SEQ DFFMODE FF CLKMUX SIG SRMODE ASYNC SRMUX INV}
  pin $c.q $n 1;pin $c.clk ddr_clk;pin $c.sr resetddr
  dict set aliases $n $n
 }
 foreach port {ia ib id ie ima} b {0 1 2 3 4} {pin $first.$port [format {%s/state_cnt[%d]} $state_root $b]}
}
set passed 0;set failed 0
proc test {name mutation command expect} {
 global passed failed first second props aliases pin_net drivers state_root
 fixture
 uplevel #0 $mutation
 set rc [catch {uplevel #0 $command} result]
 if {($expect eq {PASS} && !$rc) || ($expect eq {REJECT} && $rc)} {incr passed;puts "TEST_PASS $name expected=$expect result=$result"} else {incr failed;puts "TEST_FAIL $name expected=$expect rc=$rc result=$result"}
}
set first_call {secondary_cdc_reg fixture {u_store/cal_sync[0]} 1 1}
set pair_call {secondary_cdc_pair fixture {u_store/cal_sync[0]} {u_store/cal_sync[1]} u_store/calibrated clk125}
test packed_cal_first {} $first_call PASS
test packed_cal_pair {} $pair_call PASS
test direct_cal_pair {dict set props $first REGA_SD IMA;pin $first.ima calibrated} $pair_call PASS
test wrong_truth {dict set props $first LUT5A {(C*B*E*D*A)}} $first_call REJECT
test unsupported_mux {dict set props $first LUT5A_SD0 FT_LUT5A} $first_call REJECT
test wrong_connected_input {pin $first.ia alien;pin alien.q alien 1} $first_call REJECT
test connected_memory {pin $first.dpram_we unsafe_enable} $first_call REJECT
test wrong_lutmode {dict set props $first LUTMODE LUT6} $first_call REJECT
test wrong_ofa_select {dict set props $first OFA_SD QB} $first_call REJECT
test ambiguous_output {dict lappend drivers calibrated stranger.ofa} $first_call REJECT
test unsupported_reg_select {dict set props $first REGA_SD OFA} $first_call REJECT
test enable_not_constant {dict set props $first CEAMUX SIG} $first_call REJECT
test unsupported_reset {dict set props $first ASRMUX 0} $first_call REJECT
test wrong_state_clock {pin state3.clk clk125} $first_call REJECT
test duplicate_state {dict set aliases [format {%s/state_cnt[4]} $state_root] [format {%s/state_cnt[0]} $state_root]} $first_call REJECT
test wrong_logical {dict set aliases unrelated cal0} {secondary_cdc_reg fixture unrelated 1 1} REJECT
test second_stage_lut_forbidden {dict set props $second REGA_SD LUT5A} {secondary_cdc_reg fixture {u_store/cal_sync[1]} 1 1} REJECT
test second_stage_disconnected {pin $second.ima calibrated} $pair_call REJECT
test mismatched_resets {pin $second.asr another_reset} $pair_call REJECT
test wrong_destination_clock {pin $first.clk ddr_clk} $pair_call REJECT
test not_always_enabled {} {secondary_cdc_reg fixture {u_store/cal_sync[0]} 1 0} REJECT
puts "HELPER_FAULT_INJECTION_COMPLETE passed=$passed failed=$failed; TD_PHYSICAL_PROOF=NOT_RUN"
if {$failed != 0} {exit 1}
exit 0
