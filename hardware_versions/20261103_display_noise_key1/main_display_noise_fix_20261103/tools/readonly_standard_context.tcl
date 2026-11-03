# Independent immutable audit using the exact standard bitgen context.
# No write/save, implementation, constraint override or bitgen command.
set root {D:/program/fpga/lab_ex3_osd_SC500_720P/main_display_noise_fix_20261103}
set build "$root/01_rtl/imgq_gain_m/main/@RUN_NAME@"
set audit "$root/02_sim/display_noise_standard_context"
set name {camera_to_dsi_display_720p60_cnn_multibox}
cd $build
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project "$build/$name.al" -single_run
    load_run_param -run syn_1
    import_db "$build/${name}_pr.db"
    puts "CHECK_IO_STANDARD_CONTEXT_BEGIN"
    puts "CHECK_IO_STANDARD_CONTEXT_CATCH=[catch {check_io} io_reason] REASON=$io_reason"
    puts "CHECK_IO_STANDARD_CONTEXT_END"
    report_area -io_info -file "$audit/standard.area"
    export_io -verbose -file "$audit/standard.io"
    export_adc -verbose -file "$audit/standard.adc"
    set cells [open "$audit/standard.hard_io_cells.tsv" w]
    puts $cells "cell\tref_name\tis_placed\tcol\trow\toffset"
    foreach cell [get_cells -quiet -hier *] {
        set ref [get_property -quiet REF_NAME $cell]
        if {[string match *PAD* $ref] || [string match *DPHY* $ref] || [string match *DDR* $ref]} {
            puts $cells "$cell\t$ref\t[get_property -quiet IS_PLACED $cell]\t[get_property -quiet PLACED_COL $cell]\t[get_property -quiet PLACED_ROW $cell]\t[get_property -quiet PLACED_OFFSET $cell]"
        }
    }
    close $cells
    puts STANDARD_CONTEXT_READONLY_PASS
} reason]} {
    puts "STANDARD_CONTEXT_READONLY_FAIL: $reason"
    exit 1
}
exit 0
