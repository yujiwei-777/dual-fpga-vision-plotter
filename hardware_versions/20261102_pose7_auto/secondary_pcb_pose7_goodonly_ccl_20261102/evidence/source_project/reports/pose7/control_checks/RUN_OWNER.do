onerror {quit -code 1}
onbreak {quit -code 1}
vlib work_owner
vmap work_owner work_owner
vlog -sv -work work_owner pose7_frame_owner_probe.v tb_pose7_frame_owner.v
vsim -c -lib work_owner tb_pose7_frame_owner
run -all
quit -code 0
