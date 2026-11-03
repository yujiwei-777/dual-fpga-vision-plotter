# Prepared only. This script has not been run during the independent audit.
# Run from this trial directory after ROOT has finished V8 synthesis.
# It only imports the existing DB into memory and reads settings. It does not
# open/save a project, set/reset/commit a parameter, optimize, export a DB, or
# run physical implementation. Capture its raw stdout/stderr externally.
# ROOT must bind the input DB SHA256 before and after execution.

set input_db {D:/program/fpga/lab_ex3_osd_SC500_720P/main_display_noise_fix_20261103/01_rtl/imgq_gain_m/main/td_project_display_noise_v8/camera_to_dsi_display_720p60_cnn_multibox_gate.db}
if {![file isfile $input_db]} {
    error "READBACK_NOT_RUN: completed V8 gate DB is absent: $input_db"
}
puts "PARAM_READBACK_INPUT_DB=$input_db"
puts "PARAM_READBACK_INPUT_BYTES=[file size $input_db]"

import_device ph1_35p.db -package PH1P35MDG324 -speed 3
import_db $input_db

# The installed executable registers get_param with:
# step_name param_name -run <string> -help
# This is binary metadata, not yet a successful runtime experiment.
set expected {
    {gate add_map_lut_struct high}
    {gate map_mode area_prior}
    {gate multi_thread_mapping partition}
    {rtl resource_sharing auto}
    {rtl shifter_style shifter_reg}
    {gate pack_effort high}
}
set failures 0
if {[llength [info commands get_param]] == 0} {
    puts "PARAM_READBACK_API_UNAVAILABLE=get_param"
    incr failures
} else {
    foreach item $expected {
        lassign $item step name wanted
        if {[catch {get_param $step $name} actual]} {
            puts "PARAM_READBACK_ERROR|$step|$name|$actual"
            incr failures
        } else {
            set actual [string trim $actual]
            # 'actual' comes only from the TD command return, never from wanted.
            puts "PARAM_READBACK_VALUE|$step|$name|$actual"
            if {$actual ne $wanted} {
                puts "PARAM_READBACK_MISMATCH|$step|$name|expected=$wanted|actual=$actual"
                incr failures
            }
        }
    }
}

# Optional supplementary reports. The executable registers -all, although the
# public PDF documents only -detail. A rejected -all is recorded as unsupported;
# it does not become an invented report or a substitute for get_param values.
foreach step {rtl gate} {
    puts "PARAM_READBACK_REPORT_BEGIN|$step"
    if {[catch {report_param -stage $step -detail -all} report_error]} {
        puts "PARAM_READBACK_REPORT_UNAVAILABLE|$step|$report_error"
    }
    puts "PARAM_READBACK_REPORT_END|$step"
}

if {$failures != 0} {
    error "PARAM_READBACK_NOT_VERIFIED: $failures query/mismatch failures"
}
puts "PARAM_READBACK_QUERY_MATCHES=6"
puts "PARAM_READBACK_SCOPE=DB settings queried after import; this is not a new synthesis run or a physical acceptance gate"
