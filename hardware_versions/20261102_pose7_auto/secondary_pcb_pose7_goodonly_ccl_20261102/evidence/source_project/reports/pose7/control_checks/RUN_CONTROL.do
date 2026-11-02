onerror {quit -code 1}
onbreak {quit -code 1}
vlib work_control
vmap work_control work_control
vlog -sv -work work_control pose7_top_control_probe.v tb_pose7_top_control.v
vsim -c -lib work_control tb_pose7_top_control
run -all
quit -code 0
