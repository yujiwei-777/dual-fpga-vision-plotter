"""Compare the unchanged RX metadata queue mapped to DRAM and BRAM."""
from pathlib import Path
import hashlib, json, os, re, subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'artifacts/cart_full_20260925/fifo_r2'
OLD = ROOT/'artifacts/cart_closure_20260925/denoise/small_rams'
ENV = os.environ.copy()
ENV.update(MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT', LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT')

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def command(args, cwd, log, marker=None):
    with log.open('w', encoding='utf-8') as f:
        result = subprocess.run(args, cwd=cwd, env=ENV, stdout=f, stderr=subprocess.STDOUT)
    text = log.read_text(errors='replace')
    assert result.returncode == 0 and not re.search(r'\*\* (?:Error|Fatal):|\bERROR\b', text), str(log)
    if marker: assert marker in text, str(log)

def main():
    OUT.mkdir(parents=True, exist_ok=False)
    fifo = ROOT/'main/user_source/hdl_source/ethernet/udp_pkg_buf.v'
    source = fifo.read_text()
    results = {}
    for style in ('dram', 'bram'):
        run = OUT/style; run.mkdir()
        wrapper = '''
module leaf(input clkw,clkr,rst,we,re,input [27:0] di,
output [27:0] dout,output full_flag,empty_flag);
udp_pkg_buf #(.DATA_WIDTH_W(28),.DATA_WIDTH_R(28),.ADDR_WIDTH_W(7),
.ADDR_WIDTH_R(7),.RAM_STYLE("__MEM_STYLE__"),.SHOW_AHEAD_EN(1'b1),.OUTREG_EN("NOREG")) dut(
.clkw(clkw),.clkr(clkr),.rst(rst),.we(we),.re(re),.di(di),.dout(dout),
.full_flag(full_flag),.empty_flag(empty_flag));
endmodule
'''.replace('__MEM_STYLE__', style)
        (run/'leaf.v').write_text(source+wrapper)
        for fn in ('leaf.prj','settings.cfg','run.tcl'):
            (run/fn).write_bytes((OLD/'udp28_forced_bram'/fn).read_bytes())
        command(['E:/td/bin/td_commands_prompt.exe','run.tcl'], run, run/'run.log')
        assert (run/'.opt_gate.end.f').is_file() and (run/'leaf_gate.db').is_file()
        area = (run/'leaf_gate.area').read_text()
        results[style] = {k:int(re.search(r'^#'+k+r'\*?\s+(\d+)',area,re.M)[1])
                          for k in ('slice','lut','reg','eram','dsp')}
    reference = OUT/'udp_pkg_buf_before.v'
    reference.write_bytes((OLD/'udp_pkg_buf_before.v').read_bytes())
    bench = OUT/'tb_udp_metadata_fifo.sv'
    bench.write_text((OLD/'tb_udp_metadata_fifo.sv').read_text().replace('.RAM_STYLE("dram")', '.RAM_STYLE(W==28?"bram":"dram")'))
    command(['E:/model/win64/vlib.exe','sim'], OUT, OUT/'vlib.log')
    command(['E:/model/win64/vlog.exe','-sv','-lint','-work','sim',str(fifo),str(reference),str(bench)], OUT, OUT/'lint.log')
    command(['E:/model/win64/vsim.exe','-c','-quiet','-lib','sim','tb_udp_metadata_fifo','-do',
             'onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -code 0'], OUT, OUT/'udp_metadata_fifo.log',
            'UDP METADATA FIFO EQUIVALENCE PASS')
    assert results['bram']['slice'] < results['dram']['slice'] and results['bram']['eram'] == 1
    target = ROOT/'main/user_source/hdl_source/ethernet/uimac_rx.v'
    before = target.read_bytes()
    assert before.count(b'.RAM_STYLE("dram")') == 1
    target.write_bytes(before.replace(b'.RAM_STYLE("dram")', b'.RAM_STYLE("bram")'))
    (OUT/'uimac_rx_before.v').write_bytes(before)
    results.update(status='PASS', selected='bram', reason='Lower measured Slice; final whole-board ERAM gate still required')
    (OUT/'RESULTS.json').write_text(json.dumps(results,indent=2))
    paths = [fifo,target,ROOT/'main/user_source/hdl_source/ethernet/uimac_tx.v',reference,bench,Path(__file__)]
    paths += [p for s in ('dram','bram') for p in (OUT/s).iterdir() if p.suffix in ('.v','.prj','.cfg','.tcl')]
    (OUT/'INPUTS.json').write_text(json.dumps({p.relative_to(ROOT).as_posix():sha(p) for p in paths},indent=2))
    print(json.dumps(results,indent=2), flush=True)

if __name__ == '__main__': main()
