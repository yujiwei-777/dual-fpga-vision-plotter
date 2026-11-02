onerror {quit -code 2}
onbreak {quit -code 3}
vlib simlib
vlog -sv -lint -work simlib "E:/codex_pcb_pose7_20261102_r5/01_rtl/cnn_core.v" "E:/codex_pcb_pose7_20261102_r5/01_rtl/vision_workspace_goodonly.v" "E:/codex_pcb_pose7_20261102_r5/01_rtl/vision_shared_mac.v" "E:/codex_pose7_ordinary_20261102_r5/edges_20261102T074912_435076Z/cnn_core_reference.v" "E:/codex_pose7_ordinary_20261102_r5/edges_20261102T074912_435076Z/tb_remote_detail.sv"
vsim -voptargs=+acc simlib.tb_remote_detail
run -all
quit -code 0
