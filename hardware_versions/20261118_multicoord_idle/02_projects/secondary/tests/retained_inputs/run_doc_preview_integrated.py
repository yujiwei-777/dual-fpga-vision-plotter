"""Real captured-Y -> planner -> preview/KEY1 -> shared GRBL transport.

Run the exact selected baseline as a control in a separate library, with
both simulations writing only new report directories. Compare point streams
and complete G-code. No frontend/planner/result boundary is forced.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse, hashlib, json, os, re, shutil, subprocess, sys
sys.dont_write_bytecode=True

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'secondary_pcb_key2_x0_rezero_20261104'
SIM=Path('E:/model/win64')
FIXTURES=ROOT.parent/'secondary_doc_dirt_lowconf_factored_20261101/reports/dirt_qualification/fixtures'

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p):return Path(p).read_text(encoding='utf-8-sig',errors='replace')

BENCH=r'''
`timescale 1ns/1ps
module tb_doc_preview_integrated;
reg clk=0;always #4 clk=~clk;
reg rst_n=0,start=0,cancel=0,rearm=0,reset_job=0,key1_release=0,preview_sent=0;
wire busy,done,recovery_required,uart_owner,pixel_request,pixel_invalidate;
wire [10:0]pixel_x;wire [9:0]pixel_y;
wire [15:0]edge_count;wire [11:0]path_count;wire [13:0]point_count;
reg [8:0]preview_read_addr=0;wire [7:0]preview_read_data;
wire preview_valid;wire [31:0]preview_job_id;
wire [7:0]tx_data,rt_data;wire tx_valid,rt_valid;
reg tx_done=0,rx_valid=0;reg[7:0]rx_data=0;
reg pixel_valid=0,pending=0;reg[7:0]pixel_luma=0;
integer cycle=0,latency=0,address=0,requests=0;
wire pixel_ready=!pending&&(cycle%13!=5);
wire tx_ready=(cycle%7!=1)&&(cycle%11!=2);
wire rt_ready=cycle%7!=3;
reg[7:0]source_y[0:921599];
integer fh,points1,points2,bitmap_fh,tx_bytes=0,lines=0,queries=0;
integer reply_delay=0,reply_i=0,reply_len=0,i,n1=0,n2=0;
reg[255:0]reply=0;
@DECLARATIONS@
doc_copy_pipeline_shared_candidate #(.PLANNER_OPT_PASSES(0),.EXTERNAL_ADMISSION_GUARD(1)) dut(
 .clk(clk),.rst_n(rst_n),.start(start),.cancel(cancel),.rearm(rearm),.reset_job(reset_job),
 @PREVIEW_PORTS@
 .admission_inhibit(1'b0),.job_id(32'h11223344),.paper_width_px(16'd0),
 .busy(busy),.done(done),.recovery_required(recovery_required),.status_ready(1'b1),
 .pixel_request(pixel_request),.pixel_invalidate(pixel_invalidate),.pixel_x(pixel_x),.pixel_y(pixel_y),
 .pixel_ready(pixel_ready),.pixel_valid(pixel_valid),.pixel_luma(pixel_luma),
 .tx_ready(tx_ready),.tx_done(tx_done),.rx_data(rx_data),.rx_valid(rx_valid),.rx_error(1'b0),
 .link_ready(1'b1),.rt_ready(rt_ready),.uart_owner(uart_owner),
 .edge_count(edge_count),.path_count(path_count),.point_count(point_count),
 @PIPELINE_PORTS@);
grbl_shared_transport_candidate transport(
 .clk(clk),.rst_n(rst_n),.I_doc_owner(uart_owner||busy),.I_report_claim(1'b0),
 .link_ready(1'b1),.tx_ready(tx_ready),.tx_done(tx_done),.rt_ready(rt_ready),
 .rx_data(rx_data),.rx_valid(rx_valid),.rx_error(1'b0),
 .tx_data(tx_data),.tx_valid(tx_valid),.rt_data(rt_data),.rt_valid(rt_valid),
 @TRANSPORT_PORTS@);
task tick(input integer n);repeat(n)@(negedge clk);endtask
task press;begin key1_release=1;tick(1);key1_release=0;end endtask
initial begin
 $readmemh("source_y.mem",source_y);
 fh=$fopen("gcode.txt","w");points1=$fopen("preview_points.txt","w");
 points2=$fopen("draw_points.txt","w");bitmap_fh=$fopen("preview_bitmap.mem","w");
 tick(5);rst_n=1;tick(4);start=1;tick(1);start=0;
`ifdef PREVIEW
 press(); // While acquiring the image: this must be discarded.
 wait(preview_valid||done);tick(4);
 if(done||dut.public_state!=7||!dut.u_planner.prepared||n1==0||tx_bytes!=0)
   $fatal(1,"real pipeline did not hold a committed, previewed plan without motion");
 if(preview_job_id!==32'h11223344)$fatal(1,"preview job mismatch");
 for(i=0;i<450;i=i+1)begin preview_read_addr=i;tick(2);$fdisplay(bitmap_fh,"%02x",preview_read_data);end
 press();tick(20);if(tx_bytes||dut.public_state!=7)$fatal(1,"KEY1 without ACK moved machine");
 preview_sent=1;tick(3);preview_sent=0;tick(20);
 if(tx_bytes)$fatal(1,"ACK alone moved machine");
 press();tick(4);
`endif
 wait(done);tick(5);
 if(dut.public_state!=4||recovery_required||n2==0||S_acked_lines!=lines)
   $fatal(1,"real pipeline completion failed state=%0d error=%0d points=%0d lines=%0d acked=%0d",
            dut.public_state,dut.public_error,n2,lines,S_acked_lines);
`ifdef PREVIEW
 if(n1!=n2||preview_valid)$fatal(1,"preview/draw count or terminal invalidation failed");
 press();tick(20);if(busy)$fatal(1,"completed task restarted without a new frame");
`endif
 $fclose(fh);$fclose(points1);$fclose(points2);$fclose(bitmap_fh);
 $display("DOC_PREVIEW_INTEGRATED_PASS points=%0d lines=%0d queries=%0d requests=%0d cycles=%0d",n2,lines,queries,requests,cycle);
 $finish;
end
always @(posedge clk)begin
 cycle<=cycle+1;pixel_valid<=0;
 if(rst_n)begin
  if(pixel_request&&pixel_ready)begin
   if(pixel_x>1279||pixel_y>719)$fatal(1,"source pixel outside frame");
   address=pixel_y*1280+pixel_x;latency=2+cycle%3;pending<=1;requests=requests+1;
  end else if(pending)begin
   if(latency>0)latency=latency-1;
   else begin pixel_luma<=source_y[address];pixel_valid<=1;pending<=0;end
  end
  if(dut.point_valid&&dut.point_ready)begin
`ifdef PREVIEW
   if(dut.state==dut.PREVIEW_EMIT)begin
    $fdisplay(points1,"%06x",{dut.point_dot,dut.point_end,dut.point_start,dut.point_y,dut.point_x});n1=n1+1;
   end else
`endif
   begin
    $fdisplay(points2,"%06x",{dut.point_dot,dut.point_end,dut.point_start,dut.point_y,dut.point_x});n2=n2+1;
   end
  end
 end
 if(cycle>170000000)$fatal(1,"pipeline watchdog state=%0d planner=%0d",dut.state,dut.u_planner.state);
end
// Abstract UART byte acceptance/completion and real parser replies. A '?' is
// answered with Idle; each complete line has exactly one delayed ok.
always @(posedge clk)begin
 tx_done<=0;rx_valid<=0;
 if(rst_n)begin
  if(tx_valid&&tx_ready)begin
   tx_done<=1;tx_bytes=tx_bytes+1;
   if(tx_data==10)begin
    $fwrite(fh,"\n");lines=lines+1;
    if(reply_len)$fatal(1,"multiple motion commands in flight");
    reply=0;reply[7:0]="o";reply[15:8]="k";reply[23:16]=10;
    reply_i=0;reply_len=3;reply_delay=8;
   end else $fwrite(fh,"%c",tx_data);
  end
  if(rt_valid&&rt_ready)begin
   tx_done<=1;queries=queries+1;
   if(rt_data!=8'h3f||reply_len)$fatal(1,"unexpected realtime command");
   reply=0;reply[7:0]="<";reply[15:8]="I";reply[23:16]="d";reply[31:24]="l";reply[39:32]="e";
   reply[47:40]="|";reply[55:48]=">";reply[63:56]=10;
   reply_i=0;reply_len=8;reply_delay=8;
  end
  if(reply_delay>0)reply_delay=reply_delay-1;
  else if(reply_len>0)begin
   rx_valid<=1;rx_data<=reply[reply_i*8+:8];reply_i=reply_i+1;reply_len=reply_len-1;reply_delay=2;
  end
 end
end
endmodule
'''

def bench(root,preview):
    header=read(root/'01_rtl/doc_copy_pipeline_shared_candidate.v').split(');',1)[0]
    ports=re.findall(r'\b(input|output)\s+(?:wire|reg)\s+(\[[^\]]+\]\s*)?([SX]_\w+)\b',header)
    assert len(ports)==38,len(ports)
    decl='\n'.join('wire '+(width or '')+name+';' for _,width,name in ports)
    connections=[]
    for _,_,name in ports:
        if name.startswith('S_'):connections.append('.D_'+name[2:]+'('+name+')')
        else:connections.append('.D_fmt_'+name[2:]+'('+name+')')
    transport_header=read(root/'01_rtl/grbl_shared_transport_candidate.v').split(');',1)[0]
    for direction,width,name in re.findall(r'\b(input|output)\s+(?:wire|reg)\s+(\[[^\]]+\]\s*)?(R_\w+)\b',transport_header):
        connections.append('.'+name+("('0)" if direction=='input' else '()'))
    preview_ports=''
    if preview:
        preview_ports=','.join('.'+name+'('+name+')' for name in ['key1_release','preview_sent','preview_valid','preview_job_id','preview_read_addr','preview_read_data'])+','
    return BENCH.replace('@DECLARATIONS@',decl).replace('@PREVIEW_PORTS@',preview_ports).replace('@PIPELINE_PORTS@',','.join('.'+name+'('+name+')' for _,_,name in ports)).replace('@TRANSPORT_PORTS@',',\n '.join(connections))

def main():
    p=argparse.ArgumentParser();p.add_argument('--fixture',choices=['ink2358','strokes_on_fixed_dirt'],default='ink2358');a=p.parse_args()
    out=ROOT/'reports/doc_preview/integrated'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ');out.mkdir(parents=True)
    source=FIXTURES/a.fixture/'source_y.mem';reference=ROOT/'tools/run_doc_preview.py'
    pins={str(source):sha(source),str(Path(__file__).resolve()):sha(__file__),str(reference):sha(reference)}
    env=dict(os.environ,LM_LICENSE_FILE=str(SIM/'LICENSE.TXT'),MGLS_LICENSE_FILE=str(SIM/'LICENSE.TXT'))
    rows=[]
    for label,design,preview in [('baseline',BASE,False),('preview',ROOT,True)]:
        run=out/label;run.mkdir();shutil.copyfile(source,run/'source_y.mem')
        tb=run/'tb_doc_preview_integrated.sv';tb.write_text(bench(design,preview),encoding='ascii')
        files=[design/'01_rtl'/n for n in ['doc_copy_pipeline_shared_candidate.v','doc_image_frontend.v','doc_stroke_planner.v','doc_stroke_bram.v','doc_machine_map.v','doc_grbl_plotter_shared_candidate.v','grbl_shared_transport_candidate.v','grbl_response_parser.v','grbl_line_formatter.v']]
        for f in files+[tb]:pins[str(f)]=sha(f)
        commands=[('vlib',[SIM/'vlib.exe','work']),('lint',[SIM/'vlog.exe','-sv','-lint','+define+DOC_BEHAVIORAL_RAM']+(['+define+PREVIEW'] if preview else [])+files+[tb]),('simulation',[SIM/'vsim.exe','-batch','-syncio','-voptargs=+acc','work.tb_doc_preview_integrated','-do','onerror {quit -code 2}; onbreak {quit -code 3}; run -all; quit -code 0'])]
        for name,cmd in commands:
            log=run/(name+'.log')
            with log.open('w')as stream:cp=subprocess.run(list(map(str,cmd)),cwd=run,env=env,stdout=stream,stderr=subprocess.STDOUT,timeout=1200)
            text=read(log);ok=cp.returncode==0 and not re.search(r'\*\*\s+(?:Error|Fatal):',text) and (name!='simulation' or 'DOC_PREVIEW_INTEGRATED_PASS' in text)
            rows.append(dict(test=label+'/'+name,status='PASS'if ok else'FAIL',log=str(log),log_sha256=sha(log)))
            print(label+'/'+name+': '+rows[-1]['status'],flush=True)
            if not ok:raise RuntimeError(text[-5000:])
    assert (out/'baseline/draw_points.txt').read_bytes()==(out/'preview/draw_points.txt').read_bytes(),'baseline/current point difference'
    assert (out/'preview/preview_points.txt').read_bytes()==(out/'preview/draw_points.txt').read_bytes(),'preview/final point difference'
    assert (out/'baseline/gcode.txt').read_bytes()==(out/'preview/gcode.txt').read_bytes(),'baseline/current G-code difference'
    from run_doc_preview import raster
    points=[]
    for line in (out/'preview/preview_points.txt').read_text().splitlines():
        v=int(line,16);points.append((v&511,(v>>9)&511,(v>>18)&1,(v>>19)&1,(v>>20)&1))
    bitmap=bytes(int(x,16)for x in(out/'preview/preview_bitmap.mem').read_text().splitlines())
    assert bitmap==raster(points),'integer raster and actual committed paths differ'
    assert all(sha(f)==h for f,h in pins.items()),'source drift'
    result=dict(status='PASS',source_sha256=pins,commands=rows,fixture=a.fixture,baseline=str(BASE),
        assertions=['real captured source Y frontend; no forced boundaries','same complete planned point stream as selected baseline','preview/final traversals exactly equal','no G-code before fresh KEY1 after matching ACK','ACK held across subsequent network-signal loss','complete emitted G-code equal to baseline','450-byte preview equals independent original-grid eight-neighbour projection','terminal invalidation and no automatic replay'],
        points=len(points),gcode_lines=len((out/'preview/gcode.txt').read_text().splitlines()),
        artifact_sha256={str(f):sha(f)for folder in ['baseline','preview']for f in(out/folder).glob('*.txt')},
        limitations=['Abstract pixel and UART interfaces; physical DDR, HXA packet transfer, actual mechanics and hardware signoff are separate.','Matching the selected baseline does not claim new independent handwriting quality.'],hardware='NOT_RUN')
    (out/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(dict(status='PASS',report=str(out/'RESULT.json'),points=result['points'],gcode_lines=result['gcode_lines'])),flush=True)

if __name__=='__main__':main()
