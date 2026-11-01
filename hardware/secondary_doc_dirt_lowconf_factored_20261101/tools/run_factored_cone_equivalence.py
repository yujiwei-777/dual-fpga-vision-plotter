"""Exact-source two-state proof of the isolated low-score reject/output cone.

This is a local cone proof, not a full vision-pipeline regression or physical
qualification. The only abstraction replaces each shared comparison by one
independent Boolean input, proving a superset of all initialized numeric inputs.
Raw-margin exhaustive RTL additionally checks actual numeric comparison wiring.
"""
from __future__ import annotations
from datetime import datetime, timezone
import hashlib
import importlib.util
import itertools
import json
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / 'reports/factored_source_creation'
SIM = Path('E:/model/win64')
PIPE_SHA = '02E7954C55C5696E299D7B980DE0C4BF95C1FDF65531D1D005CFDC6882D099D5'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def put(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8')


def create_module(name, block, wires, abstract):
    if abstract:
        for old, new in (
            ('color_samples_saved<8', 'low_samples'),
            ('color_samples_saved>=8', '!low_samples'),
            ('color_margin_saved<COLOR_MARGIN_MIN', 'color_below'),
            ('shape_margin_saved<selected_shape_threshold', 'shape_below'),
        ):
            block, wires = block.replace(old, new), wires.replace(old, new)
        ports = '''input shape_reject_saved, low_samples, color_below, shape_below,
 input [7:0] minimum_cnn_margin,'''
    else:
        ports = '''input shape_reject_saved,
 input [19:0] color_samples_saved,
 input [1:0] shape_saved,
 input [7:0] color_margin_saved, shape_margin_saved,'''
    return f'''module {name} #(
 parameter integer CNN_LOWCONF_OUTPUT=0,
 parameter integer COLOR_MARGIN_MIN=0,
 parameter integer TRIANGLE_MARGIN_MIN=31,
 parameter integer CIRCLE_MARGIN_MIN=28,
 parameter integer SQUARE_MARGIN_MIN=77
)(input clk, rst_n, seed, enable,
 {ports}
 input [7:0] flags_seed,
 output reg [7:0] confidence_margin, multi_flags);
{wires}
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin confidence_margin<=0; multi_flags<=0; end
 else if(seed) begin confidence_margin<=8'hA7; multi_flags<=flags_seed; end
 else if(enable) begin
{block}
 end
end
endmodule
'''


def main():
    assert sha(ROOT / '01_rtl/vision_pipeline.v') == PIPE_SHA
    spec = importlib.util.spec_from_file_location('factored_creation', ROOT / 'tools/create_factored_variant.py')
    creator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(creator)
    parent = (AUDIT / 'vision_pipeline.parent.v').read_bytes()
    production = (ROOT / '01_rtl/vision_pipeline.v').read_bytes()
    assert creator.exact_factored(parent) == production
    before, after = parent.decode(), production.decode()
    old_block = creator.OLD_BLOCK.decode()
    new_block = creator.NEW_BLOCK.decode()
    # Verify every emitted RTL statement is an exact source extraction.
    assert old_block in before.replace('\r\n', '\n')
    assert new_block in after.replace('\r\n', '\n')
    start = before.index('    wire [7:0] minimum_cnn_margin=')
    end = before.index('    reg [1:0] cnn_color_work', start)
    old_numeric_wires = before[start:end].replace('\r\n', '\n')
    start = after.index('    wire [7:0] minimum_cnn_margin=')
    end = after.index('    reg [1:0] cnn_color_work', start)
    new_numeric_wires = after[start:end].replace('\r\n', '\n')
    hard_start = new_numeric_wires.index('    // Separate hard eligibility')
    new_abstract_wires = new_numeric_wires[hard_start:]
    case_count = 0
    for param, reject, low_samples, color_below, shape_below, flag in itertools.product(
            (0, 1), repeat=6):
        for margin in range(256):
            original_reject = reject or low_samples or color_below or shape_below
            original = (margin if param and not reject and not low_samples else 0) if original_reject else margin
            hard = reject or low_samples
            soft = color_below or shape_below
            factored = (0 if hard else margin) if param else (0 if hard or soft else margin)
            assert original == factored
            assert (1 if original_reject else flag) == (1 if hard or soft else flag)
            case_count += 1
    out = AUDIT / ('cone_' + datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
    out.mkdir(exist_ok=False)
    modules = []
    for prefix, abstract in (('abstract', True), ('numeric', False)):
        modules.extend((
            create_module(prefix + '_parent', old_block, '' if abstract else old_numeric_wires, abstract),
            create_module(prefix + '_factored', new_block, new_abstract_wires if abstract else new_numeric_wires, abstract),
        ))
    (out / 'source_cones.sv').write_text('`timescale 1ns/1ps\n' + '\n'.join(modules), encoding='utf-8')
    bench = r'''
`timescale 1ns/1ps
module tb_factored_cones;
reg clk=0,rst_n=0,seed=0,enable=0;
always #5 clk=~clk;
reg reject=0,low=0,cb=0,sb=0;
reg [7:0] margin=0,flags=0;
reg [19:0] samples=0;
reg [1:0] shape=0;
reg [7:0] cm=0,sm=0;
wire [7:0] am0,af0,bm0,bf0,am1,af1,bm1,bf1;
wire [7:0] nm0,nf0,om0,of0,nm1,nf1,om1,of1;
abstract_parent #(.CNN_LOWCONF_OUTPUT(0)) ap0(clk,rst_n,seed,enable,reject,low,cb,sb,margin,flags,am0,af0);
abstract_factored #(.CNN_LOWCONF_OUTPUT(0)) bp0(clk,rst_n,seed,enable,reject,low,cb,sb,margin,flags,bm0,bf0);
abstract_parent #(.CNN_LOWCONF_OUTPUT(1)) ap1(clk,rst_n,seed,enable,reject,low,cb,sb,margin,flags,am1,af1);
abstract_factored #(.CNN_LOWCONF_OUTPUT(1)) bp1(clk,rst_n,seed,enable,reject,low,cb,sb,margin,flags,bm1,bf1);
numeric_parent #(.CNN_LOWCONF_OUTPUT(0)) np0(clk,rst_n,seed,enable,reject,samples,shape,cm,sm,flags,nm0,nf0);
numeric_factored #(.CNN_LOWCONF_OUTPUT(0)) op0(clk,rst_n,seed,enable,reject,samples,shape,cm,sm,flags,om0,of0);
numeric_parent #(.CNN_LOWCONF_OUTPUT(1)) np1(clk,rst_n,seed,enable,reject,samples,shape,cm,sm,flags,nm1,nf1);
numeric_factored #(.CNN_LOWCONF_OUTPUT(1)) op1(clk,rst_n,seed,enable,reject,samples,shape,cm,sm,flags,om1,of1);
integer c,m,s,r,i,j,k;
integer abstract_checks=0,numeric_checks=0,hold_checks=0;
task check_equal;
begin
 if({am0,af0,am1,af1}!={bm0,bf0,bm1,bf1} ||
    {nm0,nf0,nm1,nf1}!={om0,of0,om1,of1})
  $fatal(1,"FAIL FACTORED_CONE_MITER c=%0d margin=%0d shape=%0d reject=%0d cm=%0d sm=%0d samples=%0d",c,m,s,r,i,j,samples);
end
endtask
initial begin
 #2; rst_n=0; @(negedge clk);rst_n=1;
 // Independent Boolean predicates prove a superset of every binary numeric input.
 for(c=0;c<32;c=c+1) begin
  for(m=0;m<256;m=m+1) begin
   @(negedge clk);seed=1;enable=0;flags=(c[4] ? 8'hD5:8'h95);
   @(negedge clk);seed=0;enable=1;
   reject=c[0];low=c[1];cb=c[2];sb=c[3];margin=m;
   @(posedge clk);#1;check_equal;abstract_checks=abstract_checks+2;
   @(negedge clk);enable=0;reject=~reject;margin=~margin;
   @(posedge clk);#1;check_equal;hold_checks=hold_checks+2;
  end
 end
 // Exhaust all actual color/shape margin pairs, each shape lookup, both sides
 // of sample-count eligibility, and both hard-background states.
 for(s=0;s<4;s=s+1) begin
  for(k=0;k<2;k=k+1)begin
   for(r=0;r<2;r=r+1)begin
    for(i=0;i<256;i=i+1)begin
     for(j=0;j<256;j=j+1)begin
      @(negedge clk);seed=0;enable=1;shape=s;samples=(k ? 20'd8:20'd7);reject=r;cm=i;sm=j;
      @(posedge clk);#1;check_equal;numeric_checks=numeric_checks+2;
     end
    end
   end
  end
 end
 // The full 20-bit sample domain only enters through <8 / >=8. These raw
 // endpoints cover zero, largest eligible count, and under/over the boundary.
 for(k=0;k<4;k=k+1)begin
  @(negedge clk);samples=(k==0 ? 20'd0 : k==1 ? 20'd1 : k==2 ? 20'd9 : 20'hFFFFF);
  @(posedge clk);#1;check_equal;numeric_checks=numeric_checks+2;
 end
 $display("PASS FACTORED_EXACT_SOURCE_CONE abstract=%0d numeric=%0d hold=%0d params=0,1",abstract_checks,numeric_checks,hold_checks);
 $finish;
end
endmodule
'''
    (out / 'tb_factored_cones.sv').write_text(bench, encoding='utf-8')
    assert (SIM / 'LICENSE.TXT').is_file()
    env = os.environ.copy()
    env.update(MGLS_LICENSE_FILE=str(SIM / 'LICENSE.TXT'), LM_LICENSE_FILE=str(SIM / 'LICENSE.TXT'))
    commands = []
    for name, argv in (
        ('vlib', [SIM / 'vlib.exe', 'work']),
        ('compile', [SIM / 'vlog.exe', '-sv', '-lint', '-work', 'work', 'source_cones.sv', 'tb_factored_cones.sv']),
        ('simulate', [SIM / 'vsim.exe', '-batch', '-syncio', '-quiet', '-novopt', '-suppress', '12110',
                      '-lib', 'work', 'tb_factored_cones', '-do', 'onerror {quit -code 1}; run -all; quit -f']),
    ):
        started = time.monotonic()
        p = subprocess.run(list(map(str, argv)), cwd=out, env=env, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, text=True, timeout=180)
        log = out / (name + '.log')
        log.write_text(p.stdout, encoding='utf-8')
        commands.append({'name': name, 'argv': list(map(str, argv)), 'returncode': p.returncode,
                         'elapsed_seconds': time.monotonic() - started, 'log_sha256': sha(log)})
        assert p.returncode == 0 and not re.search(r'\*\*\s+(?:Error|Fatal):|^#?\s*FAIL\b', p.stdout, re.M), p.stdout[-5000:]
        if name != 'vlib':
            assert re.search(r'Errors: 0, Warnings: \d+\s*$', p.stdout), p.stdout[-5000:]
        if name == 'compile':
            assert re.search(r'Errors: 0, Warnings: 0\s*$', p.stdout)
        if name == 'simulate':
            assert 'PASS FACTORED_EXACT_SOURCE_CONE abstract=16384 numeric=2097160 hold=16384 params=0,1' in p.stdout
    assert sha(ROOT / '01_rtl/vision_pipeline.v') == PIPE_SHA
    result = {
        'status': 'PASS_EXACT_SOURCE_TWO_STATE_CONE_EQUIVALENCE', 'hardware_status': 'NOT_RUN',
        'candidate_pipeline_sha256': PIPE_SHA, 'parent_pipeline_sha256': creator.PARENT_PIPE_SHA,
        'creation_manifest_sha256': sha(AUDIT / 'CREATION.json'),
        'python_boolean_truth_table_cases': case_count,
        'rtl_abstract_param_checks': 16384, 'rtl_raw_numeric_param_checks': 2097160,
        'rtl_disabled_state_hold_param_checks': 16384,
        'source_reconstruction_exact': True, 'thresholds': {'triangle': 31, 'cylinder': 28, 'cube': 77},
        'flag6_hard_and_soft_conditions_unchanged': True,
        'all_prior_flag_bits_preserved': True,
        'four_state_x_propagation_equivalence_claimed': False,
        'limitations': ['Binary initialized register cone only; unknown-state propagation can differ between if and ?: semantics.',
                       'Raw numeric RTL uses production default thresholds; Boolean exhaustive proof covers all comparator outputs.',
                       'Does not replace full pipeline/ordinary CNN/PCB/writer regression, synthesis, place, route, or hardware acceptance.',
                       'No resource or timing benefit is established by this functional proof.'],
        'commands': commands,
        'input_sha256': {str(path.relative_to(ROOT)): sha(path) for path in (
            Path(__file__), ROOT / 'tools/create_factored_variant.py', ROOT / '01_rtl/vision_pipeline.v',
            AUDIT / 'vision_pipeline.parent.v', out / 'source_cones.sv', out / 'tb_factored_cones.sv')},
        'td_launched': False,
    }
    put(out / 'RESULTS.json', result)
    put(AUDIT / 'CONE_EQUIVALENCE.json', {**result, 'result': str(out / 'RESULTS.json'),
                                       'result_sha256': sha(out / 'RESULTS.json')})
    print(json.dumps({'status': result['status'], 'results': str(out / 'RESULTS.json'),
                      'result_sha256': sha(out / 'RESULTS.json'), 'python_cases': case_count}, indent=2))


if __name__ == '__main__':
    main()
