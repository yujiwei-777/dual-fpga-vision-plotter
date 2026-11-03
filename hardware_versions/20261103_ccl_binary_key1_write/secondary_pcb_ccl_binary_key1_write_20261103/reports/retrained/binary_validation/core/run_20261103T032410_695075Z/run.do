onerror {quit -code 2}
onbreak {quit -code 3}
vlib work
vlog -sv "D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_ccl_binary_key1_write_20261103/01_rtl/vision_workspace_goodonly.v" "D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_ccl_binary_key1_write_20261103/01_rtl/vision_shared_mac.v" "D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_ccl_binary_key1_write_20261103/01_rtl/pcb_fullboard_spatial96.v" "D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_ccl_binary_key1_write_20261103/reports/retrained/binary_validation/core/run_20261103T032410_695075Z/tb_real_pcb_core.sv"
vsim -voptargs=+acc work.tb_real_pcb_core
run -all
quit -code 0
