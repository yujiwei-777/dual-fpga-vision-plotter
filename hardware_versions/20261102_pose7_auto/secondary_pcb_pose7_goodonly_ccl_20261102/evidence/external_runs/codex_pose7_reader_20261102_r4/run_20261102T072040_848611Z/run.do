onerror {quit -code 2}
onbreak {quit -code 3}
vlib simlib
vlog -sv -lint -work simlib "E:/codex_pcb_pose7_20261102_r4/01_rtl/vision_pixel_reader.v" "E:/codex_pcb_pose7_20261102_r4/01_rtl/hxa_ddr_store.v" "E:/codex_pose7_reader_20261102_r4/run_20261102T072040_848611Z/top_read_route_probe.sv" "E:/codex_pose7_reader_20261102_r4/run_20261102T072040_848611Z/hxa_read_route_probe.sv" "E:/codex_pose7_reader_20261102_r4/tb_reader.sv"
vsim -voptargs=+acc simlib.tb_pose7_real_reader
run -all
quit -code 0
