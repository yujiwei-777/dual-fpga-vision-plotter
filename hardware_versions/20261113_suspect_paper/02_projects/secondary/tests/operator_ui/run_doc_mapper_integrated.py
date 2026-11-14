"""Real document regression with per-request mapper/planner handshake checks.

Reuse the captured-Y/KEY1/shared-transport bench without forcing any design
boundary. Production RTL is read only. Baseline and candidate use separate
libraries, and complete point/G-code streams must match byte for byte.
"""
from pathlib import Path
from datetime import datetime, timezone
import importlib.util, json, re, shutil, sys
sys.dont_write_bytecode = True

HERE = Path(__file__).resolve()
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location('current_integrated', HERE.with_name('run_doc_current_integrated.py'))
current = importlib.util.module_from_spec(spec)
spec.loader.exec_module(current)
spec = importlib.util.spec_from_file_location('regression_run', ROOT/'tools/run_retrained_preserved_regressions.py')
h = importlib.util.module_from_spec(spec)
spec.loader.exec_module(h)

MONITOR = r'''
// Observe the real registered request at its accepting edge. No RTL is forced.
integer metric_requests=0,metric_completions=0,metric_start_cycle=0;
integer metric_min_latency=1000,metric_max_latency=0,metric_latency=0;
reg metric_pending=0;
reg [8:0] metric_resume=0;
reg [31:0] metric_result=0;
reg [32:0] metric_square=0;
always @(posedge clk)begin
 if(rst_n)begin
  if(dut.metric_start)begin
   if(metric_pending||dut.u_planner.state!==dut.u_planner.DIST0||
      dut.u_machine_map.state!==dut.u_machine_map.ST_IDLE||dut.mapper_start||dut.metric_done)
    $fatal(1,"distance request not accepted in planner DIST0/mapper IDLE");
   metric_pending=1;metric_requests=metric_requests+1;metric_start_cycle=cycle;
  end
  if(metric_pending&&dut.u_planner.state!==dut.u_planner.DIST0)
   $fatal(1,"planner left DIST0 before distance completion");
  if(dut.metric_done)begin
   if(!metric_pending||dut.u_planner.state!==dut.u_planner.DIST0||dut.metric_busy)
    $fatal(1,"unexpected or missed distance completion");
   metric_latency=cycle-metric_start_cycle;
   if(metric_latency!=@LATENCY@)$fatal(1,"distance latency %0d expected @LATENCY@",metric_latency);
   if(metric_latency<metric_min_latency)metric_min_latency=metric_latency;
   if(metric_latency>metric_max_latency)metric_max_latency=metric_latency;
   metric_resume=dut.u_planner.dist_return;
   metric_result=dut.metric_distance;metric_square=dut.metric_squared;
   metric_pending=0;metric_completions=metric_completions+1;
   #1;
   if(dut.u_planner.state!==metric_resume||dut.u_planner.dist_result!==metric_result||
      dut.u_planner.dist_square!==metric_square)
    $fatal(1,"distance completion not captured before planner resumed");
  end
 end
end
'''

def bench(design, latency):
    text = current.bench(design, True)
    marker = ' $finish;'
    assert text.count(marker) == 1
    text = text.replace(marker, '''
 if(metric_pending||metric_requests==0||metric_requests!=metric_completions)
  $fatal(1,"distance request/completion imbalance req=%0d done=%0d pending=%0d",metric_requests,metric_completions,metric_pending);
 $display("DOC_MAPPER_HANDSHAKE_PASS requests=%0d completions=%0d min_latency=%0d max_latency=%0d",metric_requests,metric_completions,metric_min_latency,metric_max_latency);
 $finish;''')
    assert text.count('task tick') == 1
    return text.replace('task tick', MONITOR.replace('@LATENCY@', str(latency)) + '\ntask tick', 1)

def main():
    out = ROOT/'reports/doc_mapper_r4'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
    out.mkdir(parents=True, exist_ok=False)
    runs, error = {}, None
    try:
        for label, design, latency in [('baseline', current.BASE, 30), ('confirm', ROOT, 28)]:
            r = h.Run(design, out/label)
            r.pin(HERE, current.__file__, h.__file__, current.TEMPLATE, current.FIXTURE)
            fixture = r.out/'source_y.mem'
            shutil.copyfile(current.FIXTURE, fixture)
            tb = r.out/'tb_doc_key1_integrated.sv'
            tb.write_text(bench(design, latency), encoding='ascii')
            files = [design/'01_rtl'/n for n in ['doc_copy_pipeline_shared_candidate.v', 'doc_image_frontend.v', 'doc_stroke_planner.v', 'doc_stroke_bram.v', 'doc_machine_map.v', 'doc_grbl_plotter_shared_candidate.v', 'grbl_shared_transport_candidate.v', 'grbl_response_parser.v', 'grbl_line_formatter.v']]
            r.pin(*files, tb, fixture)
            lib = r.out/'rtl_lib'
            r.cmd('vlib', [h.SIM/'vlib.exe', lib])
            r.cmd('lint', [h.SIM/'vlog.exe', '-sv', '-lint', '-work', lib, '+define+DOC_BEHAVIORAL_RAM', '+define+CONFIRM', *files, tb])
            log = r.cmd('simulation', [h.SIM/'vsim.exe', '-batch', '-syncio', '-voptargs=+acc', '-lib', lib.name, 'tb_doc_key1_integrated', '-do', 'onerror {quit -code 2}; onbreak {quit -code 3}; run -all; quit -code 0'], 'DOC_MAPPER_HANDSHAKE_PASS', timeout=1200)
            assert 'DOC_KEY1_INTEGRATED_PASS' in log
            metrics = re.search(r'DOC_MAPPER_HANDSHAKE_PASS requests=(\d+) completions=(\d+) min_latency=(\d+) max_latency=(\d+)', log)
            assert metrics
            values = dict(zip(['requests','completions','min_latency','max_latency'], map(int, metrics.groups())))
            r.scope.append(dict(test='real document distance request/complete/capture handshake', **values))
            runs[label] = dict(result=r.finish(), handshake=values,
                points=len(h.read(r.out/'draw_points.txt').splitlines()),
                gcode_lines=len(h.read(r.out/'gcode.txt').splitlines()),
                point_sha256=h.sha(r.out/'draw_points.txt'), gcode_sha256=h.sha(r.out/'gcode.txt'))
            assert runs[label]['result']['status']=='PASS'
        assert runs['baseline']['handshake']['requests']==runs['confirm']['handshake']['requests']
        assert (out/'baseline/draw_points.txt').read_bytes()==(out/'confirm/draw_points.txt').read_bytes(), 'committed point stream changed'
        assert (out/'baseline/gcode.txt').read_bytes()==(out/'confirm/gcode.txt').read_bytes(), 'G-code changed'
    except Exception as exc:
        error = str(exc)
    result = dict(status='FAIL' if error else 'PASS', design=str(ROOT), output=str(out), runs=runs,
        assertions=['real captured source Y -> frontend -> planner -> fresh KEY1 -> shared transport',
          'every real distance request accepted in mapper IDLE while planner is in DIST0',
          'planner stays in DIST0 until completion and captures both metric words before returning',
          'all requests complete exactly once; candidate completion advances exactly two cycles',
          'early KEY1 is discarded, fresh KEY1 emits once, completed task cannot replay',
          'full committed point and G-code streams byte-identical to selected baseline'],
        error=error, hardware='NOT_RUN', limitations=['Captured ink2358 regression fixture with PLANNER_OPT_PASSES=0.',
          'Abstract source-pixel and UART interfaces; no physical DDR, HXA or mechanics signoff.',
          'doc_total_ack separately isolates ACK accounting with an abstract point source and mapper.'])
    h.dump(out/'RESULT.json', result)
    print(json.dumps(dict(status=result['status'], report=str(out/'RESULT.json'), error=error), ensure_ascii=False), flush=True)
    return 0 if not error else 1

if __name__=='__main__':
    raise SystemExit(main())
