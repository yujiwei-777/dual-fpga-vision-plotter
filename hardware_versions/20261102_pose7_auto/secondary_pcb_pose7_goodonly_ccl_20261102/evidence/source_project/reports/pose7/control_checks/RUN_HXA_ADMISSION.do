onerror {quit -code 1}
onbreak {quit -code 1}
vlib work_hxa_admission
vmap work_hxa_admission work_hxa_admission
vlog -sv -work work_hxa_admission ph1p_logic_eram_stub.sv "D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_pose7_goodonly_ccl_20261102/shared/rtl/hxa_packet_codec.v" "D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_pose7_goodonly_ccl_20261102/shared/rtl/hxa_packet_rx_fifo4.v" "D:/program/fpga/lab_ex3_osd_SC500_720P/secondary_pcb_pose7_goodonly_ccl_20261102/shared/rtl/hxa_secondary_link.v" tb_pose7_hxa_admission.v
vsim -c -lib work_hxa_admission tb_pose7_hxa_admission
run -all
quit -code 0
