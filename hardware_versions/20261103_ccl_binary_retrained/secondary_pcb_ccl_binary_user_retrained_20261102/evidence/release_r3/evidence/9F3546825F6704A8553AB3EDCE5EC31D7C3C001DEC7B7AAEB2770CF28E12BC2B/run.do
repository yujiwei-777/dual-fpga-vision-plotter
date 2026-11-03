onerror {quit -code 1}
onbreak {quit -code 2}
vlib simlib
vlog -sv -work simlib "D:/program/fpga/lab_ex3_osd_SC500_720P/main_pcb_auto_compat_20261101/01_rtl/imgq_gain_m/shared/rtl/hxa_packet_codec.v" "D:/program/fpga/lab_ex3_osd_SC500_720P/main_pcb_auto_compat_20261101/01_rtl/imgq_gain_m/shared/rtl/hxa_main_link.v" "D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_ccl_binary_user_retrained_20261102/reports/retrained/main_protocol_compat_v3/tb_link_pcb_wait.sv"
vsim -voptargs=+acc simlib.tb_link_pcb_wait
run -all
quit -code 0
