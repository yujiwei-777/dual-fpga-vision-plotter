onerror {quit -code 2}
onbreak {quit -code 3}
vlib work
vlog -sv +incdir+D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_pose7_goodonly_ccl_20261102/reports/pose7/fullpipeline_regression/run_20261102T074528_523921Z "E:/codex_pcb_pose7_20261102_r5/01_rtl/vision_pipeline.v" "E:/codex_pcb_pose7_20261102_r5/01_rtl/edge_roi_ccl_shared_pcb_candidate.v" "E:/codex_pcb_pose7_20261102_r5/01_rtl/vision_ccl_pcb_candidate.v" "E:/codex_pcb_pose7_20261102_r5/01_rtl/pcb_pose7_core.v" "E:/codex_pcb_pose7_20261102_r5/01_rtl/cnn_core.v" "E:/codex_pcb_pose7_20261102_r5/01_rtl/vision_workspace_goodonly.v" "E:/codex_pcb_pose7_20261102_r5/01_rtl/vision_shared_mac.v" "E:/codex_pcb_pose7_20261102_r5/01_rtl/cnn_result_stabilizer.v" "E:/codex_pcb_pose7_20261102_r5/01_rtl/vision_color_stats.v" "E:/codex_pcb_pose7_20261102_r5/01_rtl/vision_pixel_reader.v" "D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_pose7_goodonly_ccl_20261102/reports/pose7/tb_pose7_fullpipeline.sv"
vsim -voptargs=+acc work.tb_pose7_fullpipeline +FIXTURES=D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_pose7_goodonly_ccl_20261102/reports/pose7/fullpipeline_regression/fixtures
run -all
quit -code 0
