onerror {quit -code 1}
onbreak {quit -code 1}
vlib work_ccl
vmap work_ccl work_ccl
vlog -sv -work work_ccl "D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_pose7_goodonly_ccl_20261102/01_rtl/vision_ccl_pcb_candidate.v" "D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_pose7_goodonly_ccl_20261102/01_rtl/edge_roi_ccl_shared_pcb_candidate.v" tb_pose7_ccl_frames.v
vsim -c -lib work_ccl tb_pose7_ccl_frames
run -all
quit -code 0
