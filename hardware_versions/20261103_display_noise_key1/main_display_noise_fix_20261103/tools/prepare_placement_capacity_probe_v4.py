"""Prepare a read-only TD query using independent copies of the V4 gate inputs.

No product sources, constraints, saved design databases or implementation runs
are modified. The probe intentionally contains no place/route/bitgen command.
"""
from pathlib import Path
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[1]
NAME = 'camera_to_dsi_display_720p60_cnn_multibox'
SOURCE = ROOT / '01_rtl/imgq_gain_m/main/td_project_display_noise_v4'
PROBE = ROOT / '02_sim/placement_capacity_probe_v4'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def main():
    if PROBE.exists():
        raise ValueError('Probe destination must be new')
    PROBE.mkdir()
    copies = []
    for filename in (NAME + '.al', NAME + '_gate.db', 'osd_compact_glyphs.vh'):
        source, target = SOURCE / filename, PROBE / filename
        original = source.read_bytes()
        if filename.endswith('.al'):
            before, after = str(SOURCE).replace('\\', '/').encode(), str(PROBE).replace('\\', '/').encode()
            changed = original.replace(before, after)
            if changed == original or changed.replace(after, before) != original:
                raise ValueError('Expected an isolated AL project metadata path')
            target.write_bytes(changed)
        else:
            shutil.copy2(source, target)
            if target.read_bytes() != original:
                raise ValueError('Independent input copy differs')
        copies.append({'source': str(source), 'target': str(target),
                       'source_sha256': sha(source), 'target_sha256': sha(target),
                       'bytes': target.stat().st_size})
    script = r'''# Read-only independent architecture/parameter probe.
set probe {@PROBE@}
cd $probe
proc query {label script} {
    puts "PROBE_QUERY_BEGIN $label"
    set code [catch {uplevel 1 $script} result]
    puts "PROBE_QUERY_CATCH $label $code RESULT=$result"
    puts "PROBE_QUERY_END $label"
}
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project "$probe/@NAME@.al" -single_run
    load_run_param -run syn_1
    import_db "$probe/@NAME@_gate.db"
} reason]} {
    puts "PROBE_IMPORT_FAILED $reason"
    exit 1
}
query commands {
    foreach pattern {*field* *resource* *arch* *param* *pack* *report_tile* *help*} {
        puts "PROBE_COMMAND_PATTERN $pattern [lsort [info commands $pattern]]"
    }
}
query gate_params {report_param -stage gate -detail}
query place_params {report_param -stage place -detail}
query area {report_area -verbose -file "$probe/imported_gate_verbose.area"}
query help_arch {help query_current_arch}
query help_area {help report_area}
query help_param {help report_param}
query arch_default {query_current_arch -file "$probe/arch_default.txt"}
foreach kind {SLICEL SLICEM LUTL LUTM Plb Pmb PH1P_PHY_LSLICE PH1P_PHY_MSLICE} {
    query "arch_$kind" [list query_current_arch -type $kind -file "$probe/arch_$kind.txt"]
}
puts "READONLY_CAPACITY_PROBE_FINISHED"
exit 0
'''.replace('@PROBE@', PROBE.as_posix()).replace('@NAME@', NAME)
    (PROBE / 'run.tcl').write_text(script, encoding='utf-8')
    manifest = {'source_run': str(SOURCE), 'probe': str(PROBE), 'copies': copies,
                'read_only': True, 'place_route_bitgen': False,
                'script_sha256': sha(PROBE / 'run.tcl')}
    (PROBE / 'input_manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
