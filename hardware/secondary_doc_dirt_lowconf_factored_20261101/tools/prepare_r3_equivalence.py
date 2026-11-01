"""Bind frozen R2 transport references to each R3 transport in regression.

This compares every public output on every falling clock under the actual
regression stimuli. It is a sequential simulation miter, not a formal proof.
"""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
FROZEN = ROOT / 'vector_reset_nofinal_r2_Runs_20261028/frozen_inputs_before_area_opt/01_rtl'
OUT = ROOT / '02_sim/vector_reset_r3'
OUT.mkdir(exist_ok=True)
for name, clock, reset in [('grbl_streamer', 'I_clk', 'I_rst_n'), ('doc_grbl_streamer', 'clk', 'rst_n')]:
    source = (FROZEN / (name + '.v')).read_text()
    (OUT / (name + '_r2_ref.sv')).write_text(source.replace('module ' + name + ' ', 'module ' + name + '_r2_ref ', 1))
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
    monitor = header.replace('module ' + name + ' ', 'module ' + name + '_r3_equiv ', 1)
    monitor = re.sub(r'\boutput\s+(?:wire|reg)', 'input wire', monitor)
    monitor += '\n' + '\n'.join('wire ' + width + ' ref_' + port + ';' for port, width in outputs) + '\n'
    param_map = ','.join('.' + p + '(' + p + ')' for p in params)
    output_names = {p for p, _ in outputs}
    port_map = ','.join('.' + p + '(' + ('ref_' if p in output_names else '') + p + ')' for p in ports)
    monitor += name + '_r2_ref #(' + param_map + ') reference(' + port_map + ');\n'
    monitor += 'always @(negedge ' + clock + ') if(' + reset + ') begin\n'
    monitor += ' if({' + ','.join('ref_' + p for p, _ in outputs) + '} !== {' + ','.join(p for p, _ in outputs) + '})\n'
    monitor += '  $fatal(1,"R3 reachable sequential equivalence failed: ' + name + '");\nend\nendmodule\n'
    monitor += 'bind ' + name + ' ' + name + '_r3_equiv #(' + param_map + ') check_r2_equivalence(.*);\n'
    (OUT / (name + '_r3_equiv.sv')).write_text(monitor)
print('prepared per-cycle frozen-R2 equivalence monitors for report and document streamers')
