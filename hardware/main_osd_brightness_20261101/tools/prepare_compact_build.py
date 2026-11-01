"""Prepare a fresh OSD-only build. Does not launch TD or modify HDL."""
import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parents[1]
# The compact Chinese OSD project was forked from this source snapshot. Keep
# the fresh build self-contained by rewriting source references into this
# independent clone before TD is launched.
BASE = ROOT.parent / 'main_osd_chinese_compact_20261030'
NAME = 'camera_to_dsi_display_720p60_cnn_multibox'
RUN = ROOT / '01_rtl/imgq_gain_m/main/td_project_compact_v2'
HDL = ROOT / '01_rtl/imgq_gain_m/main/user_source/hdl_source'
TOOLS = ROOT / 'tools'
AUDIT = ROOT / '02_sim/compact_readonly_v2'

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()

def main():
    RUN.mkdir(parents=True, exist_ok=True)
    AUDIT.mkdir(parents=True, exist_ok=True)
    al = RUN / (NAME + '.al')
    text = al.read_text(encoding='utf-8-sig')
    text = text.replace(BASE.as_posix(), ROOT.as_posix())
    text = text.replace(str(BASE), ROOT.as_posix())
    text = re.sub(r'(<Project[^>]*\bPath=")[^"]+', lambda m: m[1] + RUN.as_posix(), text, count=1)
    new_sources = ['osd_compact_font_rom.v', 'osd_compact_panel.v', 'osd_decimal_snapshot.v']
    order = max(map(int, re.findall(r'Name="CompileOrder" Val="(\d+)"', text)))
    for filename in new_sources:
        full = (HDL / filename).as_posix()
        if full not in text:
            order += 1
            node = f'''            <File Path="{full}">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="{order}"/>
                </FileInfo>
            </File>
'''
            text = text.replace('        </Verilog>', node + '        </Verilog>', 1)
    al.write_text(text, encoding='utf-8')
    # Source-local include resolution is retained. Also freeze an identical
    # header in the compiler working directory, rather than guess an
    # undocumented TD project property or alter HDL include directives.
    header = HDL / 'osd_compact_glyphs.vh'
    if header.is_file():
        shutil.copyfile(header, RUN / header.name)
    template = (RUN / 'run_full.tcl').read_text(encoding='utf-8-sig')
    for output, start, end in [('run_compact_synth.tcl', 'read_design', 'opt_gate'),
                                ('run_compact_place.tcl', 'opt_place', 'opt_place'),
                                ('run_compact_route.tcl', 'opt_route', 'opt_route')]:
        flow = re.sub(r'^set start_step \w+', 'set start_step ' + start, template, flags=re.M)
        flow = re.sub(r'^set end_step \w+', 'set end_step ' + end, flow, flags=re.M)
        flow = 'set parent {.}\n' + flow
        (RUN / output).write_text(flow, encoding='utf-8')
    # The compact baseline artifact directory contains the bit but does not
    # carry the older large-font source manifest. Preserve the manifest
    # already shipped with this independent clone when it is unavailable.
    source_manifest = BASE / 'artifacts/dual_fpga_main_20261030_osd_chinese_compact_sources.csv'
    if source_manifest.is_file():
        shutil.copyfile(source_manifest, TOOLS / 'baseline_sources.csv')
    paths = re.findall(r'<File Path="([^"]+)"', text)
    problems = []
    for value in paths:
        p = Path(value)
        p = p if p.is_absolute() else RUN / p
        p = p.resolve()
        if not p.is_relative_to(ROOT):
            problems.append('External project reference: ' + str(p))
        if 'work' in [v.lower() for v in p.parts]:
            problems.append('Protected work reference: ' + str(p))
        if not p.is_file():
            problems.append('Not ready: ' + str(p))
    result = {'project': str(al), 'source_references': len(paths),
              'new_sources': new_sources, 'problems': problems,
              'header_present': header.is_file(),
              'header_cwd_copy_identical': header.is_file() and sha(header) == sha(RUN / header.name),
              'td_started': False, 'bitgen_automatic': False}
    (TOOLS / 'build_preparation.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
    print(json.dumps(result, indent=2))
    return int(bool(problems) or not header.is_file())

if __name__ == '__main__':
    raise SystemExit(main())
