"""Delay every reporter-to-transport handshake, including formatted lines.

Uses the real reporter/formatter/transport/parser and current byte-level paper
scenarios. The added gate holds each command for13cycles and checks the full
512bit payload, length and final flag, formatter immutability, and final totals.
"""
from pathlib import Path
from datetime import datetime, timezone
import importlib.util, json, shutil

ROOT = Path(__file__).resolve().parents[1]
helper = ROOT/'tools/run_retrained_preserved_regressions.py'
spec = importlib.util.spec_from_file_location('reporter_hold_helper', helper)
h = importlib.util.module_from_spec(spec); spec.loader.exec_module(h)
out = ROOT/'reports/reporter_line_hold'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
r = h.Run(ROOT, out)
source = ROOT/'tests/paper_eject/tb_paper_eject.sv'
r.pin(Path(__file__), helper, source)
error = None
try:
    text = source.read_text(encoding='utf-8-sig')
    text = text.replace('module tb_paper_eject;', 'module tb_reporter_line_hold;')
    old = 'wire  X_busy;'
    assert text.count(old) == 1
    text = text.replace(old, old+'''
wire producer_line_ready;
wire [31:0] report_total;
wire report_total_valid;
reg [4:0] stall_count=0;
wire line_gate=(stall_count>=13);
assign producer_line_ready=S_line_ready&&line_gate;
reg held=0;
reg [511:0] held_line;
reg [6:0] held_length;
reg held_last;
integer fixed_holds=0,formatted_holds=0,hold_checks=0,total_checks=0;
always @(posedge clk)begin
 if(!rst_n)begin stall_count<=0;held<=0;end
 else begin
  if(!S_line_valid || producer_line_ready)stall_count<=0;
  else if(!line_gate)stall_count<=stall_count+1'b1;
  if(held && S_line_valid)begin
   hold_checks++;
   if(S_line!==held_line||S_length!==held_length||S_line_last!==held_last)
    $fatal(1,"reporter command changed under producer backpressure");
   if(X_start)$fatal(1,"formatter restarted before pending command accepted");
   if(reporter.line_from_formatter && X_line!==held_line)
    $fatal(1,"shared formatter did not hold its output until acceptance");
  end
  if(S_line_valid&&!producer_line_ready)begin
   if(!held)begin
    held_line<=S_line;held_length<=S_length;held_last<=S_line_last;
    if(reporter.line_from_formatter)formatted_holds++;else fixed_holds++;
   end
   held<=1;
  end else held<=0;
  if(!report_total_valid && report_total!==32'd0)
   $fatal(1,"unknown total is not zero");
  if(report_total_valid)begin
   total_checks++;
   if(report_total!==acked||busy)$fatal(1,"completed report total is not final ACK count");
  end
 end
end
''')
    old='.S_line_ready(S_line_ready),'
    assert text.count(old) == 1
    text=text.replace(old,'.S_line_ready(producer_line_ready),')
    old='.R_line_valid(S_line_valid),'
    assert text.count(old) == 1
    text=text.replace(old,'.R_line_valid(S_line_valid&&line_gate),')
    old='.I_work_frame_reset(frame_reset),.O_rebased_y_cmm(rebased_y),'
    assert text.count(old) == 1
    text=text.replace(old,old+'\n  .O_total_lines(report_total),.O_total_valid(report_total_valid),')
    old='$display("PAPER_EJECT_PASS cases=%0d",scenarios);$finish;'
    assert text.count(old) == 1
    text=text.replace(old,'''if(fixed_holds<10||formatted_holds<20||hold_checks<1000||total_checks==0)
  $fatal(1,"insufficient command hold/total coverage");
 $display("REPORTER_LINE_HOLD_PASS cases=%0d fixed=%0d formatted=%0d checks=%0d totals=%0d",scenarios,fixed_holds,formatted_holds,hold_checks,total_checks);$finish;''')
    bench=out/'tb_reporter_line_hold.sv';bench.write_text(text,encoding='utf-8')
    rom=ROOT/'model/suspect/report_text_tokens.mem';r.pin(rom)
    staged=out.parent/'model/suspect/report_text_tokens.mem'
    staged.parent.mkdir(parents=True,exist_ok=True)
    if staged.exists():assert h.sha(staged)==h.sha(rom)
    else:shutil.copyfile(rom,staged)
    files=[ROOT/'01_rtl'/x for x in ('grbl_reporter_shared_candidate.v',
        'grbl_shared_transport_candidate.v','grbl_line_formatter.v',
        'grbl_response_parser.v','grbl_vector_font_rom.v')]
    r.sim('line_hold',files+[bench],'tb_reporter_line_hold','REPORTER_LINE_HOLD_PASS')
except Exception as exc:error=str(exc)
result=r.finish(error)
print(json.dumps(dict(status=result['status'],report=str(out/'RESULTS.json'),error=error)))
raise SystemExit(0 if result['status']=='PASS' else 1)
