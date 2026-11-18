"""Actual top/report/UART startup and receive-only idle requalification.

The UART peer is serial, not a forced ready/ACK signal. Image/network interfaces
are controlled as in the preserved common-write test. No production RTL edits.
"""
from pathlib import Path
from datetime import datetime, timezone
import importlib.util, json, re, shutil, sys
sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
helper = ROOT/'tools/run_retrained_preserved_regressions.py'
spec = importlib.util.spec_from_file_location('integrated_idle_helper', helper)
h = importlib.util.module_from_spec(spec); spec.loader.exec_module(h)
out = ROOT/'reports/integrated_idle_uart'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
r = h.Run(ROOT, out); error = None

def replace_once(text, old, new):
    assert text.count(old) == 1, ('test anchor drift', old)
    return text.replace(old, new)

try:
    r.pin(Path(__file__), helper)
    declarations = h.top_declarations(r)
    names = ['pll', 'PLL', 'secondary_ddr_wrapper', 'reset_sync', 'hxa_ddr_store',
             'uiudp_stack', 'vision_pixel_reader', 'vision_pipeline', 'hxa_config_store',
             'hxa_secondary_link', 'doc_copy_pipeline_shared_candidate', 'rgmii_interface']
    stub = out/'controlled_inference_interfaces.sv'
    stub.write_text('\n'.join(declarations[n]+'\nendmodule\n' for n in names)+
                    '\nmodule PH1P_LOGIC_BUFG(input i,output o);assign o=i;endmodule\n', encoding='utf-8')
    rom = ROOT/'model/suspect/report_text_tokens.mem'; r.pin(rom)
    staged = out.parent/'model/suspect/report_text_tokens.mem'; staged.parent.mkdir(parents=True, exist_ok=True)
    if staged.exists(): assert h.sha(staged) == h.sha(rom)
    else: shutil.copyfile(rom, staged)
    source = ROOT/'tests/paper_eject/tb_common_write_uart.sv'; r.pin(source)
    text = h.read(source)
    text = replace_once(text, 'defparam dut.u_uart.CLK_HZ=460800;',
                        'defparam dut.u_uart.CLK_HZ=4000;')
    text = replace_once(text, 'defparam dut.u_uart.BAUD=115200;',
                        'defparam dut.u_uart.BAUD=1000;')
    text = replace_once(text, 'defparam dut.u_uart.PROBE_INTERVAL_CYCLES=10000;',
                        'defparam dut.u_uart.PROBE_INTERVAL_CYCLES=1000;\n'
                        'defparam dut.u_uart.IDLE_POLL_INTERVAL_CYCLES=2000;')
    text = replace_once(text, 'bit boot_ready=0;', '''bit boot_ready=0;
bit peer_reply=1,peer_receiving=0;
localparam integer BOOT_CASE=0;
integer expected_boot_holds,expected_boot_resets;''')
    text = replace_once(text, 'string serial_line="";', '''string serial_line="";
integer idle_lines, idle_holds, idle_resets, idle_queries, runtime_start_queries;
task malformed;begin
 @(negedge clk);serial_rx=0;repeat(BIT_TICKS*11)@(negedge clk);
 serial_rx=1;repeat(BIT_TICKS*4)@(negedge clk);
end endtask
task await_idle_certificate;integer n;begin
 n=0;while(!dut.u_uart.idle_certified&&n<50000)begin step;n++;end
 check(dut.u_uart.idle_certified,"fresh idle monitor certifies quiescent actual top path");
end endtask
task idle_fault_then_recover(input string label);integer n;begin
 await_idle_certificate;
 peer_reply=0;
 while(peer_receiving)step;
 tick(100);
 idle_lines=tx_lines;idle_holds=boot_holds;idle_resets=boot_resets;
 malformed;tick(3);
 check(!dut.uart_link_ready,{label," framing fault fences command bytes"});
 tick(12000);
 check(!dut.uart_link_ready,{label," silence never clears fault"});
 check(!dut.report_recovery_required&&!dut.copy_recovery&&!dut.u_plot_transport.owner_valid,
  {label," idle receive-only fault creates no task/recovery owner lock"});
 check(tx_lines==idle_lines&&boot_holds==idle_holds&&boot_resets==idle_resets,
  {label," sends no motion, hold or reset while requalifying"});
 peer_reply=1;n=0;
 while(!dut.uart_link_ready&&n<50000)begin step;n++;end
 check(dut.uart_link_ready,{label," recovers from fresh serial Idle without KEY3 or KEY4"});
 check(tx_lines==idle_lines&&boot_holds==idle_holds&&boot_resets==idle_resets,
  {label," recovery does not replay G-code or reset controller"});
end endtask''')
    text = replace_once(text, ' repeat(5)@(negedge clk);\n for(integer k=0;k<message.len();k++)send_byte(message[k]);',
                        ' peer_receiving=1;repeat(5)@(negedge clk);\n'
                        ' for(integer k=0;k<message.len();k++)send_byte(message[k]);\n'
                        ' peer_receiving=0;')
    text = replace_once(text, '   receive("<Idle|MPos:0,0,0>\\n");',
                        '   if(peer_reply)receive("<Idle|MPos:0,0,0>\\n");')
    text = replace_once(text, ' check(queries==0,{name," issues no normal-completion status/stop/reset"});',
                        ' check(boot_holds==expected_boot_holds&&boot_resets==expected_boot_resets,\n'
                        '  {name," does not hold/reset after normal completion"});')
    text = replace_once(text, ' tick(4);rst_n=1;', ''' tick(4);if(BOOT_CASE==2)peer_reply=0;rst_n=1;
 if(BOOT_CASE==1)malformed;
 if(BOOT_CASE==2)begin
  tick(18000);check(!dut.uart_link_ready&&tx_lines==0,
   "late controller remains fenced during initial silence");peer_reply=1;
 end''')
    text = replace_once(text,
                        ' check(dut.uart_link_ready&&boot_holds==1&&boot_resets==1&&boot_queries==2,',
                        ' check(dut.uart_link_ready&&boot_holds>=1&&boot_resets==1&&boot_queries>=2&&\n'
                        '  (BOOT_CASE!=0||(boot_holds==1&&boot_queries==2)),')
    text = replace_once(text, ' boot_ready=1;tick(15);result(100);', ''' boot_ready=1;tick(15);result(100);
 expected_boot_holds=boot_holds;expected_boot_resets=boot_resets;
 check(!dut.report_recovery_required&&!dut.copy_recovery,
  "initial safe retries do not leak recovery locks into task owners");
 await_idle_certificate;
 idle_lines=tx_lines;idle_queries=queries;
 tick(160000);
 check(dut.uart_link_ready&&queries>idle_queries+20&&tx_lines==idle_lines,
  "long idle keeps actual top path ready with only read-only status probes");
 idle_fault_then_recover("before first write");''')
    text = replace_once(text, ' press1;complete("CNN second");',
                        ' idle_fault_then_recover("between CNN jobs");\n press1;complete("CNN second");')
    text = replace_once(text, ' for(integer j=0;j<12;j++)begin', ''' idle_fault_then_recover("before KEY2");
 for(integer j=0;j<12;j++)begin''')
    text = replace_once(text, 'COMMON_WRITE_UART_FAIL', 'INTEGRATED_IDLE_UART_FAIL')
    text = replace_once(text, 'COMMON_WRITE_UART_PASS cases=', 'INTEGRATED_IDLE_UART_PASS cases=')
    files = [ROOT/'01_rtl'/n for n in ('secondary_top.v', 'grbl_uart.v', 'grbl_reporter_shared_candidate.v',
             'grbl_shared_transport_candidate.v', 'grbl_line_formatter.v', 'grbl_response_parser.v',
             'grbl_vector_font_rom.v')]
    for case, name in enumerate(('normal_boot', 'boot_framing_noise', 'late_controller')):
        bench = out/('tb_common_write_uart_'+name+'.sv')
        bench.write_text(text.replace('localparam integer BOOT_CASE=0;',
                         'localparam integer BOOT_CASE='+str(case)+';'), encoding='utf-8')
        log = r.sim('integrated_idle_uart_'+name, [stub, *files, bench], 'tb_common_write_uart',
                    'INTEGRATED_IDLE_UART_PASS', novopt=True)
        r.scope.append(dict(test='actual top/report/serial UART '+name+' and post-fault KEY1/KEY2 admission',
                            records=re.findall(r'(?:PASS CHAIN|INTEGRATED_IDLE_)[^\r\n]*', log)))
    r.limits = ['Inference, DDR and network use controlled interfaces; production top/report/UART/parser/transport are real.',
                'UART baud/clock and idle intervals are scaled with four clocks per bit, physical controller NOT_RUN.',
                'No KEY3 or KEY4 input is pulsed, no readiness or response is forced, and no task is replayed during idle recovery.',
                'External Alarm/Reset and active-command errors remain the responsibility of separate locked-fault regressions.']
except Exception as exc: error = repr(exc)
result = r.finish(error)
(ROOT/'reports/INTEGRATED_IDLE_UART_LATEST.json').write_text(json.dumps(dict(status=result['status'],
    report=str(out/'RESULTS.json')), indent=2)+'\n', encoding='utf-8')
print(json.dumps(dict(status=result['status'], report=str(out/'RESULTS.json'), error=error)), flush=True)
raise SystemExit(0 if result['status']=='PASS' else 1)
