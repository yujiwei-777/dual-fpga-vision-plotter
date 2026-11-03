set build {E:/codex_pcb_binary_ccl_retrained_20261102_r3}
cd $build/runs/phy_1
if {[catch {
 import_device ph1_35p.db -package PH1P35MDG324 -speed 3
 open_project secondary_cnn_multibox.al -noanalyze
 import_db $build/inherited/r2/runs/phy_1/secondary_cnn_multibox_place_checkpoint.db
 source ../../04_pin/apply_reset_exceptions.tcl
 source ../../04_pin/apply_cdc_exceptions.tcl
 source ../../physical_proof/cdc_cal_lut5a.tcl
 secondary_apply_phase_timing place_end ../../04_pin/timing.sdc manhattan
 source ../../04_pin/clocktrace_sclk/prove_key3_supervisor_clocktrace.tcl
 secondary_prove_key3_supervisor place_end
 update_timing -mode manhattan
 report_timing_status -file secondary_cnn_multibox_place.ts
 report_timing_summary -file secondary_cnn_multibox_place.timing
 report_area -io_info -file secondary_cnn_multibox_phy.area
 flow_status -file place_resume_flow.status
 report_clock_utilization -file place_clock_utilization.txt
 export_db secondary_cnn_multibox_place.db
 set f [open .resume_place.end.f w];close $f
 puts PHYSICAL_PLACE_CHECKPOINT_REPROVED
} reason]} {puts "PHYSICAL_RESUME_FAILED $reason";exit 1}
exit 0
