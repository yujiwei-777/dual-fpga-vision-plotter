onerror {quit -code 2}
onbreak {quit -code 3}
vlib work
vlog -sv -lint "D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_ccl_binary_roi120_20261102/01_rtl/vision_workspace_goodonly.v" "D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_ccl_binary_roi120_20261102/01_rtl/vision_shared_mac.v" "D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_ccl_binary_roi120_20261102/01_rtl/pcb_fullboard_spatial96.v" "D:/program/fpga/lab_ex3_osd_SC500_720P/pcb_ccl_binary_user_retrain_20261102/reports/contract_audit/tb_retrained_pcb_core.sv"
vsim -voptargs=+acc work.tb_real_pcb_core
run -all
quit -code 0
