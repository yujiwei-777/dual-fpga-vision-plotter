"""Focused production-top and real dual-GRBL shared recovery regression.

Image/planner and physical interfaces are controlled leaves. The production
top's job_busy, guard, task retirement, reporter Reset lock, KEY3 query, doc
formatter/transport and Type15 status are all exercised unchanged.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '02_sim/top_doc_shared_recovery_r4'
OUT.mkdir(exist_ok=True)
SIM = Path('E:/model/win64')
env = os.environ.copy()
env.update(MGLS_LICENSE_FILE=str(SIM / 'LICENSE.TXT'), LM_LICENSE_FILE=str(SIM / 'LICENSE.TXT'))
source_list = [ROOT / x for x in (ROOT / 'lint_full.f').read_text().splitlines() if x.strip()]
modules = {}
for path in source_list:
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', path.read_text(errors='replace'), flags=re.S)
    for match in re.finditer(r'\bmodule\s+(\w+)\b', text):
        end = text.index(';', match.end())
        modules[match.group(1)] = text[match.start():end+1] + '\nendmodule\n'
names = ['pll', 'PLL', 'secondary_ddr_wrapper', 'reset_sync', 'hxa_ddr_store',
    'uiudp_stack', 'vision_pixel_reader', 'vision_pipeline', 'hxa_config_store',
    'hxa_secondary_link', 'grbl_uart_port', 'rgmii_interface', 'doc_image_frontend', 'doc_stroke_planner']
stubs = OUT / 'physical_datapath_leaf_stubs.sv'
stubs.write_text('// Test only: physical/image/planner leaves; both GRBL consumers remain production.\n'
                 + '\n'.join(modules[name] for name in names)
                 + '\nmodule PH1P_LOGIC_BUFG(input i, output o);assign o=i;endmodule\n')
sources = [stubs] + [ROOT / '01_rtl' / p for p in ['secondary_top.v','doc_copy_pipeline.v',
    'doc_grbl_plotter.v','doc_grbl_streamer.v','doc_grbl_response_parser.v',
    'grbl_line_formatter.v','doc_grbl_map.v','doc_machine_map.v','grbl_reporter.v',
    'grbl_streamer.v','grbl_response_parser.v','grbl_vector_font_rom.v']]
sources += [ROOT / '02_sim/testmodels/ph1p_logic_eram_stub.sv', ROOT / '02_sim/tb_top_doc_shared_recovery.sv']

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

before = {str(p.resolve()): sha(p) for p in sources}

def run(label, command):
    p = subprocess.run([v.as_posix() if isinstance(v, Path) else str(v) for v in command], cwd=ROOT, env=env,
                       text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=180)
    (OUT / (label + '.log')).write_text(p.stdout)
    if p.returncode or re.search(r'\*\*\s+(Error|Fatal):', p.stdout):
        raise SystemExit(p.stdout[-6000:])
    return p.stdout

run('vlib', [SIM / 'vlib.exe', OUT / 'work'])
run('compile', [SIM / 'vlog.exe', '-sv', '-lint', '-work', OUT / 'work', *sources])
text = run('top_doc_shared_recovery', [SIM / 'vsim.exe', '-c', '-quiet', '-lib', OUT / 'work',
                                       'tb_top_doc_shared_recovery', '-do', 'run -all; quit -f'])
assert 'PASS TOP_DOC_SHARED_RECOVERY_ALL' in text
assert 'Errors: 0, Warnings: 0' in text
assert all(sha(Path(p)) == digest for p, digest in before.items()), 'production inputs changed during review'
result = {'status':'PASS','scope':__doc__.strip(),'input_hashes':before,
          'checks':[line.strip('# ') for line in text.splitlines() if 'PASS' in line],
          'hardware_status':'NOT_RUN','production_sources_written':False,
          'evidence_hashes':{p.name:sha(p) for p in OUT.glob('*.log')}}
(OUT / 'RESULTS.json').write_text(json.dumps(result,indent=2))
print('\n'.join(result['checks']))
