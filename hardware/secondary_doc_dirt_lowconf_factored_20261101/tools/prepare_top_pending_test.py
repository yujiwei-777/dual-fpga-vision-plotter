"""Compile the real top-level control with leaf interface stubs for a focused test.

The clock/GRBL/network/datapath leaf outputs are driven by the bench. The KEY2
controller, pending registers, task admission, and KEY4 reset latch are the
unchanged production secondary_top.v, not a copy of its sequential logic.
This deliberately does not simulate DDR, inference, or the physical UART.
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
OUT = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / '02_sim/vector_reset_r2'
OUT.mkdir(exist_ok=True)
source = [ROOT / x for x in (ROOT / 'lint_full.f').read_text().splitlines() if x.strip()]
modules = {}
for p in source:
    text = re.sub(r'/\*.*?\*/|//[^\n]*', '', p.read_text(errors='replace'), flags=re.S)
    for match in re.finditer(r'\bmodule\s+(\w+)\b', text):
        end = text.index(';', match.end())
        modules[match.group(1)] = text[match.start():end + 1] + '\nendmodule\n'
names = ['pll', 'PLL', 'secondary_ddr_wrapper', 'reset_sync', 'hxa_ddr_store',
         'uiudp_stack', 'vision_pixel_reader', 'vision_pipeline', 'hxa_config_store',
         'doc_copy_pipeline', 'hxa_secondary_link', 'grbl_uart_port', 'grbl_reporter', 'rgmii_interface']
text = '// Test-only leaf interfaces; never included in the synthesis project.\n'
text += '\n'.join(modules[name] for name in names)
text += '\nmodule PH1P_LOGIC_BUFG(input i, output o); assign o=i; endmodule\n'
(OUT / 'secondary_top_leaf_stubs.sv').write_text(text)
print('prepared production-top pending integration leaf interfaces')
