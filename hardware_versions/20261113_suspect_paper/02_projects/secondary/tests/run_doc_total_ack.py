"""Exercise current document generator and real shared UART/parser/formatter.

An abstract point source and mapper isolate ACK-derived progress accounting;
the actual G-code bytes, delayed ACKs and command totals are checked.
"""
from pathlib import Path
from datetime import datetime, timezone
import importlib.util, json, re

ROOT=Path(__file__).resolve().parents[1]
helper=ROOT/'tools/run_retrained_preserved_regressions.py'
spec=importlib.util.spec_from_file_location('doc_total_helper',helper)
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
out=ROOT/'reports/doc_total_ack'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
r=h.Run(ROOT,out);r.pin(Path(__file__),helper)
error=None
try:
    src=ROOT/'01_rtl/doc_grbl_plotter_shared_candidate.v'
    transport=ROOT/'01_rtl/grbl_shared_transport_candidate.v'
    header=h.read(src).split(');',1)[0]
    ports=re.findall(r'\b(input|output)\s+(?:wire|reg)\s+(\[[^\]]+\]\s*)?([SX]_\w+)\b',header)
    assert len(ports)==38,len(ports)
    decl='\n'.join('wire '+(w or '')+n+';' for _,w,n in ports)
    gen=','.join('.'+n+'('+n+')' for _,_,n in ports)
    trx=[('.D_'+n[2:] if n.startswith('S_') else '.D_fmt_'+n[2:])+'('+n+')' for _,_,n in ports]
    th=h.read(transport).split(');',1)[0]
    for direction,width,name in re.findall(r'\b(input|output)\s+(?:wire|reg)\s+(\[[^\]]+\]\s*)?(R_\w+)\b',th):
        trx.append('.'+name+("('0)" if direction=='input' else '()'))
    bench=r'''`timescale 1ns/1ps
module tb_doc_total_ack;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,start=0,points_done=0,point_valid=0;
reg [8:0]point_x=0,point_y=70;
reg point_start=0,point_end=0,point_dot=0;
wire point_ready,busy,done,error,recovery_required;
wire [31:0]acked,total;wire total_valid;
wire [7:0]tx_data,rt_data;wire tx_valid,rt_valid;
reg tx_done=0,rx_valid=0;reg [7:0]rx_data=0;
integer cycles=0,lines=0,acks=0,queries=0,line_bytes=0;
reg [511:0]last_line=0;reg [63:0]reply=0;
integer reply_i=0,reply_len=0,delay_count=0;
wire tx_ready=(cycles%5!=0);
wire mapper_start;reg mapper_done=0;
@DECL@
doc_grbl_plotter_shared_candidate #(.CLK_HZ(1000),.EXTERNAL_MAPPER(1)) dut(
 .clk(clk),.rst_n(rst_n),.start(start),.cancel(1'b0),.rearm(1'b0),.reset_job(1'b0),
 .point_valid(point_valid),.point_x(point_x),.point_y(point_y),
 .point_start(point_start),.point_end(point_end),.point_dot(point_dot),.points_done(points_done),
 .point_ready(point_ready),.busy(busy),.done(done),.error(error),.recovery_required(recovery_required),
 .acked_lines(acked),.link_ready(1'b1),.mapper_start(mapper_start),.mapper_x(),.mapper_y(),
 .tx_data(),.tx_valid(),.tx_ready(tx_ready),.tx_done(tx_done),.rx_data(rx_data),.rx_valid(rx_valid),.rx_error(1'b0),
 .rt_data(),.rt_valid(),.rt_ready(1'b1),.error_code(),.job_state(),.cancelled(),
 .mapper_x_cmm(16'd1000),.mapper_y_cmm(16'd1000),.mapper_done(mapper_done),
 .airwalk(1'b0),.total_lines(total),.total_valid(total_valid),@GEN@);
grbl_shared_transport_candidate #(.CLK_HZ(1000),.DOC_QUERY_MS(500),.DOC_PROGRESS_MS(10000)) trx(
 .clk(clk),.rst_n(rst_n),.I_doc_owner(busy),.I_report_claim(1'b0),.link_ready(1'b1),
 .tx_ready(tx_ready),.tx_done(tx_done),.rt_ready(1'b1),.rx_data(rx_data),.rx_valid(rx_valid),.rx_error(1'b0),
 .tx_data(tx_data),.tx_valid(tx_valid),.rt_data(rt_data),.rt_valid(rt_valid),@TRX@);
task tick(input integer n);repeat(n)@(negedge clk);endtask
task begin_task;
 begin
  lines=0;acks=0;queries=0;points_done=0;
  start=1;tick(1);start=0;tick(2);
  if(total_valid)$fatal(1,"old total survived accepted start");
 end
endtask
task point(input bit first,last,dot);
 begin
  point_start=first;point_end=last;point_dot=dot;point_valid=1;
  while(!point_ready)tick(1);
  tick(1);point_valid=0;point_x=point_x+10;
 end
endtask
task finish_task(input integer expected);
 begin
  points_done=1;
  wait(done);tick(3);
  if(error||recovery_required||busy||!total_valid||total!=expected||acked!=expected||lines!=expected||acks!=expected||queries!=1)
   $fatal(1,"completion mismatch exp=%0d total=%0d acked=%0d lines=%0d acks=%0d q=%0d",expected,total,acked,lines,acks,queries);
  if(last_line[79:0]!==80'h30302e30313058203047)$fatal(1,"final command not return G0 X010.00: %h",last_line[79:0]);
  tick(10);if(busy)$fatal(1,"task replayed");
 end
endtask
initial begin
 tick(5);rst_n=1;tick(5);
 begin_task();point(1,0,0);point(0,1,0);finish_task(8);
 begin_task();point(1,1,1);finish_task(8);
 begin_task();finish_task(4);
 $display("DOC_TOTAL_ACK_PASS cases=3 normal_dot_empty delayed_ack_no_final_idle");$finish;
end
always @(posedge clk)begin
 cycles<=cycles+1;tx_done<=0;rx_valid<=0;mapper_done<=mapper_start;
 if(cycles>50000)$fatal(1,"watchdog state=%0d",dut.state);
 if(rst_n)begin
  if(error)$fatal(1,"transport fault");
  if(rt_valid)begin
   queries=queries+1;tx_done<=1;
   if(lines||rt_data!=8'h3f||reply_len)$fatal(1,"unexpected status query after initial safety check");
   reply=64'h0a3e7c656c64493c;reply_i=0;reply_len=8;delay_count=8;
  end
  if(tx_valid&&tx_ready)begin
   tx_done<=1;
   if(tx_data==10)begin
    lines=lines+1;line_bytes=0;
    if(reply_len)$fatal(1,"multiple commands in flight");
    reply=64'h0a6b6f;reply_i=0;reply_len=3;delay_count=30;
   end else begin
    if(line_bytes==0)last_line=0;
    last_line[line_bytes*8+:8]=tx_data;line_bytes=line_bytes+1;
   end
  end
  if(delay_count>0)delay_count=delay_count-1;
  else if(reply_len>0)begin
   rx_valid<=1;rx_data<=reply[reply_i*8+:8];
   if(reply_i==2&&reply[7:0]=="o")acks=acks+1;
   reply_i=reply_i+1;reply_len=reply_len-1;delay_count=3;
  end
  if(busy && total_valid && total!=acks)$fatal(1,"total published before all ACKs");
 end
end
endmodule
'''.replace('@DECL@',decl).replace('@GEN@',gen).replace('@TRX@',',\n '.join(trx))
    tb=out/'tb_doc_total_ack.sv';tb.write_text(bench,encoding='ascii')
    files=[src,transport,ROOT/'01_rtl/grbl_response_parser.v',ROOT/'01_rtl/grbl_line_formatter.v']
    r.sim('doc_total',files+[tb],'tb_doc_total_ack','DOC_TOTAL_ACK_PASS')
except Exception as exc:error=str(exc)
r.limits=['Abstract point source, mapper and UART completion; actual document generator, shared transport, formatter and parser.',
          'Physical mechanics, source-image planning and DDR are covered separately.']
v=r.finish(error);print(json.dumps(dict(status=v['status'],report=str(out/'RESULTS.json'),error=error)))
raise SystemExit(0 if v['status']=='PASS' else 1)
