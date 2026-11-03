onerror {quit -code 2}
onbreak {quit -code 3}
vlib work
vlog -modelsimini D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_ccl_binary_user_retrained_20261102/reports/retrained/binary_validation_compat/adapter/run_20261102T151132_480068Z/modelsim.ini -sv "E:/codex_pcb_binary_ccl_retrained_20261102_r2/01_rtl/pcb_ccl_binary_core.v" "E:/codex_pcb_binary_ccl_retrained_20261102_r2/01_rtl/pcb_fullboard_spatial96.v" "E:/codex_pcb_binary_ccl_retrained_20261102_r2/01_rtl/vision_workspace_goodonly.v" "E:/codex_pcb_binary_ccl_retrained_20261102_r2/01_rtl/vision_shared_mac.v" "D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_ccl_binary_user_retrained_20261102/reports/retrained/binary_validation_compat/adapter/run_20261102T151132_480068Z/tb_adapter.sv"
vsim -modelsimini D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_ccl_binary_user_retrained_20261102/reports/retrained/binary_validation_compat/adapter/run_20261102T151132_480068Z/modelsim.ini -voptargs=+acc work.tb_binary_adapter_control
run -all
quit -code 0
