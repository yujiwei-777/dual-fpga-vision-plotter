"""Generate independent read-only/standard-context/bitgen Tcl; no TD launch."""
import argparse
import subprocess
import sys
from display_noise_paths import *
def main():
    parser=argparse.ArgumentParser(); parser.add_argument('stage',choices=['readonly','context','bitgen']); args=parser.parse_args()
    snapshot=obj(RUN/'source_snapshot.json')
    if not snapshot['passed'] or any(not Path(f['path']).is_file() or sha(Path(f['path']))!=f['sha256'] for f in snapshot['files']):
        raise ValueError('Prebuild snapshot drift or rejection')
    from review_display_noise_release import validate_gate_evidence
    if not validate_gate_evidence(obj(RUN/'release_gate.json'))['passed']: raise ValueError('Fresh routed release gate/evidence must pass first')
    AUDIT.mkdir(parents=True,exist_ok=True); CONTEXT.mkdir(parents=True,exist_ok=True)
    if args.stage=='readonly':
        path=AUDIT/'readonly_reimport.tcl'
        if path.exists(): raise ValueError('Refusing to overwrite prior readonly Tcl')
        subprocess.run([sys.executable,str(ROOT/'tools/td_release_audit.py'),'reimport-template','--root',str(ROOT),'--run',str(RUN),'--name',NAME,'--audit-dir',str(AUDIT)],check=True)
        script=read(path)
        extra='''
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
        puts $sites "$cell\t$ref\t[get_property -quiet IS_PLACED $cell]\t[get_property -quiet PLACED_COL $cell]\t[get_property -quiet PLACED_ROW $cell]\t[get_property -quiet PLACED_OFFSET $cell]"
        if {$ref eq "PH1P_PHY_LSLICE" || $ref eq "PH1P_PHY_MSLICE"} {
            puts $expected "$cell\t$ref"
            if {$ref eq "PH1P_PHY_LSLICE"} {incr l_count} else {incr m_count}
        }
    }
    close $sites
    close $expected
    puts "EXPECTED_SLICE_COUNTS L=$l_count M=$m_count"
    puts READONLY_EXPECTED_SLICE_EXPORT_DONE
'''.replace('@AUDIT@',AUDIT.as_posix())
        script=script.replace('    puts TD_READONLY_REIMPORT_PASS',extra+'\n    puts TD_READONLY_REIMPORT_PASS')
    elif args.stage=='context':
        path=CONTEXT/'standard_context.tcl'
        if path.exists(): raise ValueError('Refusing to overwrite prior standard-context Tcl')
        script=read(ROOT/'tools/readonly_standard_context.tcl').replace('@RUN_NAME@',RUN.name)
        if '@RUN_NAME@' in script or RUN.name not in script:raise ValueError('Standard-context run placeholder was not resolved')
        put(CONTEXT/'input_hashes.json',{str(p.resolve()):sha(p) for p in [RUN/(NAME+'.al'),RUN/(NAME+'_pr.db')]})
    else:
        subprocess.run([sys.executable,str(ROOT/'tools/review_display_noise_release.py')],check=True)
        review=obj(ROOT/'reports/display_noise_prebitgen_review.json')
        if not review['passed']: raise ValueError('Independent prebitgen review must pass first')
        for value,item in review['evidence'].items():
            p=ROOT/value
            if not p.is_file() or sha(p)!=item['sha256']: raise ValueError('Review evidence drift: '+str(p))
        path=CONTEXT/'bitgen.tcl'
        if path.exists() or BIT.exists(): raise ValueError('Refusing to overwrite bitgen evidence/artifact')
        script='''# Standard bitgen only; no unconstr_io or other parameter override.
set build {@RUN@}
set name {@NAME@}
set bitfile {@BIT@}
cd $build
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project "$build/$name.al" -single_run
    load_run_param -run syn_1
    import_db "$build/${name}_pr.db"
    bitgen -bit $bitfile
    puts "DISPLAY_NOISE_BITGEN_PASS: $bitfile"
} reason]} {
    puts "DISPLAY_NOISE_BITGEN_FAIL: $reason"
    exit 1
}
exit 0
'''.replace('@RUN@',RUN.as_posix()).replace('@NAME@',NAME).replace('@BIT@',BIT.as_posix())
    path.write_text(script,encoding='utf-8'); print(path)
if __name__=='__main__': main()
