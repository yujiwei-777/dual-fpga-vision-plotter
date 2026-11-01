"""Extend generated read-only import with retained raw legality evidence."""
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / '02_sim/compact_readonly_v2'
def main():
    path = AUDIT / 'readonly_reimport.tcl'
    script = path.read_text(encoding='utf-8-sig')
    extra = r'''
    report_drc -no_waivers -verbose -file {@AUDIT@/readonly.drc}
    report_path_skew -no_detailed_paths -file {@AUDIT@/readonly.skew}
    puts "RAW_CHECK_DESIGN_STATUS=[catch {check_design} raw_design_reason] REASON=$raw_design_reason"
    puts "CHECK_IO_STATUS=[catch {check_io} io_reason] REASON=$io_reason"
    puts "CHECK_PLB_STATUS=[catch {check_plb_attr -file {@AUDIT@/readonly.plb_check}} plb_reason] REASON=$plb_reason"
    export_sdc -file {@AUDIT@/readonly.exported.sdc}
    export_adc -verbose -file {@AUDIT@/readonly.exported.adc}
    export_io -verbose -file {@AUDIT@/readonly.io}
    set sites [open {@AUDIT@/readonly.sites.tsv} w]
    set expected [open {@AUDIT@/expected_slice_cells.tsv} w]
    puts $sites "cell\tref_name\tis_placed\tcol\trow\toffset"
    puts $expected "cell\tref_name"
    set l_count 0
    set m_count 0
    foreach cell [get_cells -quiet -hier *] {
        set ref [get_property -quiet REF_NAME $cell]
        set placed [get_property -quiet IS_PLACED $cell]
        set col [get_property -quiet PLACED_COL $cell]
        set row [get_property -quiet PLACED_ROW $cell]
        set offset [get_property -quiet PLACED_OFFSET $cell]
        puts $sites "$cell\t$ref\t$placed\t$col\t$row\t$offset"
        if {$ref eq "PH1P_PHY_LSLICE" || $ref eq "PH1P_PHY_MSLICE"} {
            puts $expected "$cell\t$ref"
            if {$ref eq "PH1P_PHY_LSLICE"} {incr l_count} else {incr m_count}
        }
    }
    close $sites
    close $expected
    puts "EXPECTED_SLICE_COUNTS L=$l_count M=$m_count"
    puts READONLY_EXPECTED_SLICE_EXPORT_DONE
'''.replace('@AUDIT@', AUDIT.as_posix())
    script = script.replace('    puts TD_READONLY_REIMPORT_PASS', extra + '\n    puts TD_READONLY_REIMPORT_PASS')
    path.write_text(script, encoding='utf-8')
    print(path)
if __name__ == '__main__':
    main()
