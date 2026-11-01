"""R3 reporter versus R4 under constant-source existing regression stimuli.

Compare every public output each cycle, proving the serial endpoint selection
does not alter these traces. The intentional cross-source admission difference
is tested separately without this monitor. This is simulation, not formal proof.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / '02_sim/vector_reset_r4'
OUT.mkdir(exist_ok=True)
FROZEN = ROOT / 'vector_reset_nofinal_r3_Runs_20261028/frozen_inputs_before_job_tag_opt/01_rtl/grbl_reporter.v'
source = FROZEN.read_text()
(OUT / 'grbl_reporter_r3_ref.sv').write_text(source.replace('module grbl_reporter ', 'module grbl_reporter_r3_ref ', 1))
clean = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
header = clean[:clean.index(';') + 1]
params = re.findall(r'parameter\s+integer\s+(\w+)', header)
ports_text = header[header.rfind(')(') + 2:header.rfind(')')]
ports, outputs = [], []
direction = width = ''
for item in ports_text.split(','):
    match = re.search(r'\b(input|output|inout)\b', item)
    if match:
        direction = match.group(1)
        ranges = re.search(r'\[[^\]]+\]', item)
        width = ranges.group(0) if ranges else ''
    match = re.search(r'([A-Za-z_]\w*)\s*$', item.strip())
    assert match, item
    port = match.group(1)
    ports.append(port)
    if direction == 'output':
        outputs.append((port, width))
monitor = header.replace('module grbl_reporter ', 'module grbl_reporter_r4_equiv ', 1)
monitor = re.sub(r'\boutput\s+(?:wire|reg)', 'input wire', monitor)
monitor += '\n' + '\n'.join('wire ' + width + ' ref_' + port + ';' for port, width in outputs) + '\n'
param_map = ','.join('.' + p + '(' + p + ')' for p in params)
output_names = {p for p, _ in outputs}
port_map = ','.join('.' + p + '(' + ('ref_' if p in output_names else '') + p + ')' for p in ports)
monitor += 'grbl_reporter_r3_ref #(' + param_map + ') reference(' + port_map + ');\n'
monitor += 'always @(negedge I_clk) if(I_rst_n) begin\n'
monitor += ' if({' + ','.join('ref_' + p for p, _ in outputs) + '} !== {' + ','.join(p for p, _ in outputs) + '})\n'
monitor += '  $fatal(1,"R4 same-source reporter sequential equivalence failed");\nend\nendmodule\n'
monitor += 'bind grbl_reporter grbl_reporter_r4_equiv #(' + param_map + ') check_r3_equivalence(.*);\n'
(OUT / 'grbl_reporter_r4_equiv.sv').write_text(monitor)
print('prepared frozen-R3 same-source reporter per-cycle public-output monitor')
