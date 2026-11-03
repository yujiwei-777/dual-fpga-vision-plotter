"""Independent PH1P single-module area comparison; no product implementation.

All dynamic input/output bits stay connected to a wrapper top. The same device,
default mapping, pack_effort=high and no physical/IO/timing constraints are used
for each module. Counts are preliminary gate estimates, never release gates.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '02_sim/spatial_module_gate_20261103'
TD = Path('E:/td/bin/td_commands_prompt.exe')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def put(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


SPATIAL_TOP = '''module module_area_top(
 input wire I_clk,I_rst_n,I_vsync,I_hsync,I_de,I_user,I_last,
 input wire [23:0] I_data,
 output wire O_vsync,O_hsync,O_de,O_user,O_last,
 output wire [23:0] O_data);
 a4_display_spatial_h1 #(.ENABLE(1),.EDGE_TH(16),.IMG_WIDTH(1280),.IMG_HEIGHT(720)) dut(
 .I_clk(I_clk),.I_rst_n(I_rst_n),.I_vsync(I_vsync),.I_hsync(I_hsync),
 .I_de(I_de),.I_user(I_user),.I_last(I_last),.I_data(I_data),
 .O_vsync(O_vsync),.O_hsync(O_hsync),.O_de(O_de),
 .O_user(O_user),.O_last(O_last),.O_data(O_data));
endmodule
'''


def prepare_module_gate(folder, source, wrapper, parameters):
    """Reusable isolated AL/Tcl setup. Caller supplies a complete dynamic top."""
    folder, source = Path(folder), Path(source)
    if folder.exists():
        raise ValueError('Refusing to overwrite area evidence: ' + str(folder))
    folder.mkdir(parents=True)
    copied = folder / 'module_source.v'
    shutil.copy2(source, copied)
    if copied.read_bytes() != source.read_bytes():
        raise ValueError('Source copy differs')
    (folder / 'module_area_top.v').write_text(wrapper, encoding='utf-8')
    entries = []
    for order, filename in enumerate(('module_source.v', 'module_area_top.v'), 1):
        path = escape((folder / filename).as_posix(), {'"': '&quot;'})
        entries.append(f'''<File Path="{path}"><FileInfo>
<Attr Name="UsedInSyn" Val="true"/><Attr Name="UsedInP&R" Val="true"/>
<Attr Name="BelongTo" Val="design_1"/><Attr Name="CompileOrder" Val="{order}"/>
</FileInfo></File>''')
    # TD's standalone AL reader requires its complete metadata schema and uses
    # literal UsedInP&R attributes, matching its own generated AL. Keep that
    # schema but remove every original source/IP/constraint entry.
    template = ROOT / '01_rtl/imgq_gain_m/main/td_project_display_noise_v5/camera_to_dsi_display_720p60_cnn_multibox.al'
    project = template.read_text(encoding='utf-8-sig')
    project = re.sub(r'(<Project[^>]* Path=")[^"]+("[^>]*>)',
                     lambda m: m[1] + folder.as_posix() + m[2], project, count=1)
    project = re.sub(r'<Name>.*?</Name>', '<Name>module_area</Name>', project, count=1)
    project = re.sub(r'<Source_Files>.*?</Source_Files>',
                     '<Source_Files><Verilog>' + ''.join(entries) + '</Verilog></Source_Files>',
                     project, count=1, flags=re.S)
    project = re.sub(r'<TOP_MODULE>.*?</TOP_MODULE>',
                     '<TOP_MODULE><LABEL>module_area_top</LABEL><MODULE>module_area_top</MODULE><CREATEINDEX>user</CREATEINDEX></TOP_MODULE>',
                     project, count=1, flags=re.S)
    (folder / 'module_area.al').write_text(project, encoding='utf-8')
    script = '''# Isolated area-only gate comparison. No product constraint or physical run.
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project module_area.al -single_run
    load_run_param -run syn_1
    set_param gate pack_effort high
    commit_param -step design
    elaborate -top module_area_top
    export_db module_area_elaborate.db
    commit_param -step rtl
    optimize_rtl
    report_area -file module_area_rtl.area
    commit_param -step gate
    optimize_gate -packarea module_area_gate.area
    legalize_phy_inst
    report_area -verbose -file module_area_after_legalize.area
    export_db module_area_gate.db
    set done [open .module_gate.end.f w]
    close $done
    puts MODULE_AREA_GATE_PASS
} reason]} {
    set failed [open .module_gate.error.f w]
    puts $failed $reason
    close $failed
    puts "MODULE_AREA_GATE_FAIL: $reason"
    exit 1
}
exit 0
'''
    (folder / 'run.tcl').write_text(script, encoding='utf-8')
    inputs = {filename: sha(folder / filename) for filename in
              ('module_source.v', 'module_area_top.v', 'module_area.al', 'run.tcl')}
    manifest = {'source': str(source), 'source_sha256': sha(source), 'copied_source_sha256': sha(copied),
                'parameters': parameters, 'device': 'PH1P35MDG324', 'speed': 3,
                'mapping': 'default auto', 'pack_effort': 'high', 'inputs': inputs,
                'all_dynamic_module_io_connected': True,
                'product_constraints_used_or_changed': False,
                'place_route_bitgen': False, 'resource_kind': 'PRELIMINARY_SINGLE_MODULE_GATE_ESTIMATE'}
    put(folder / 'input_manifest.json', manifest)
    return manifest


def run_module_gate(folder):
    folder = Path(folder)
    manifest = json.loads((folder / 'input_manifest.json').read_text(encoding='utf-8'))
    for filename, digest in manifest['inputs'].items():
        if sha(folder / filename) != digest:
            raise ValueError('Prepared input drift')
    logfile = folder / 'console.log'
    if logfile.exists():
        raise ValueError('Prior log exists')
    with logfile.open('wb') as stream:
        process = subprocess.run([str(TD), 'run.tcl'], cwd=folder, stdout=stream, stderr=subprocess.STDOUT)
    log = logfile.read_text(encoding='utf-8-sig')
    if process.returncode or not (folder / '.module_gate.end.f').is_file() or (folder / '.module_gate.error.f').exists() or 'MODULE_AREA_GATE_PASS' not in log:
        raise ValueError('Module gate failed; raw log: ' + str(logfile))
    if re.search(r'ERROR:|FATAL:', log):
        raise ValueError('Module gate has adverse errors; raw log retained')
    for filename, digest in manifest['inputs'].items():
        if sha(folder / filename) != digest:
            raise ValueError('Frozen copied input changed during area run')
    reports = {}
    for name in ('module_area_gate.area', 'module_area_after_legalize.area'):
        area = (folder / name).read_text(encoding='utf-8-sig')
        rows = re.findall(r'^\|\s*dut\s*\|[^|]+\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|', area, re.M)
        if len(rows) != 1:
            raise ValueError('Expected retained DUT hierarchy area row in ' + name)
        counts = dict(zip(('logic_lut', 'ripple', 'seq', 'eram', 'dsp'), map(int, rows[0])))
        estimates = {key: int(value) for key, value in re.findall(r'^#(slice\*?|lut|reg|lslice|mslice|eram|dsp)\s+(\d+)', area, re.M)}
        reports[name] = {'dut': counts, 'top_preliminary': estimates, 'sha256': sha(folder / name)}
    result = {'status': 'PASS', 'manifest': manifest, 'reports': reports,
              'log_sha256': sha(logfile), 'source_current_matches_copied': sha(manifest['source']) == manifest['source_sha256'],
              'hardware_status': 'NOT_RUN', 'scope': 'Isolated gate area only. No full-system timing, placement, capacity or image-quality acceptance.'}
    put(folder / 'area_result.json', result)
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--out', type=Path, default=OUT)
    args = parser.parse_args()
    out = args.out.resolve()
    cases = [
        ('v5_high', ROOT / 'reports/attempt5_rtl/a4_display_spatial_h1.v'),
        ('nocarry_high', ROOT / '02_sim/display_noise_nocarry_trial/a4_display_spatial_nocarry.v'),
    ]
    if out.exists():
        raise ValueError('Output area already exists; refusing evidence overwrite')
    for label, source in cases:
        manifest = prepare_module_gate(out / label, source, SPATIAL_TOP,
                                      {'ENABLE': 1, 'EDGE_TH': 16, 'IMG_WIDTH': 1280, 'IMG_HEIGHT': 720})
        print(label, manifest['source_sha256'], flush=True)
    if args.prepare_only:
        return
    results = {label: run_module_gate(out / label) for label, _ in cases}
    before = results['v5_high']['reports']['module_area_gate.area']['dut']
    after = results['nocarry_high']['reports']['module_area_gate.area']['dut']
    summary = {'status': 'PASS', 'v5': before, 'nocarry': after,
               'nocarry_minus_v5': {key: after[key] - before[key] for key in before},
               'results': {key: str(out / key / 'area_result.json') for key in results},
               'not_final_physical_resource_or_timing_gate': True}
    put(out / 'comparison.json', summary)
    print(json.dumps(summary, indent=2), flush=True)


if __name__ == '__main__':
    main()
