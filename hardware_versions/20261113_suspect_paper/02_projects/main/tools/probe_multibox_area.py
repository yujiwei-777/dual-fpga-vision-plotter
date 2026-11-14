"""Isolated exact-function four-target badge arithmetic area candidate.

Changes only new report files.  Actual production module/glyph initialization
is copied intact, and both original and candidate are synthesized afresh.
"""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, os, re, subprocess, sys
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'01_rtl/imgq_gain_m/main/user_source/hdl_source/hxa_multibox_overlay.v'
REPORT=ROOT/'reports/multibox_area_candidate'
OUT=REPORT/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
RECIPE=ROOT/'reports/cross_area/20261113T140845_143382Z/M_dotted_no_ripple_center'
TD=Path('E:/td/bin/td_commands_prompt.exe')
ENV=dict(os.environ,LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT',MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT')

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def put(p,obj):p.write_text(json.dumps(obj,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
def run(directory,label,command,timeout=300,env=None):
    log=directory/(label+'.log')
    with log.open('xb') as stream:
        cp=subprocess.run(command,cwd=directory,stdout=stream,stderr=subprocess.STDOUT,env=env,timeout=timeout)
    row={'command':command,'returncode':cp.returncode,'log':str(log),'log_sha256':sha(log)}
    put(directory/(label+'.receipt.json'),row)
    text=log.read_text(encoding='utf-8',errors='replace')
    if cp.returncode or re.search(r'\*\*\s+(?:Error|Fatal):|\bMODULE_AREA_GATE_FAIL\b',text):
        raise RuntimeError(str(row)+'\n'+text[-4000:])
    return row

def candidate(text):
    needle='    reg [11:0] bcd[0:3];'
    assert text.count(needle)==1
    added='''    // Shared modulo offsets replace repeated badge comparisons and
    // selected text subtractions. Default loader guarantees x<=1136 and
    // y<=1007 even for malformed raw input; negative wraps cannot hit.
    wire [10:0] badge_dx[0:3];
    wire [9:0] badge_dy[0:3];
    generate for(genvar d=0;d<4;d=d+1)begin:g_badge_delta
      (* use_ripple = 0 *) wire [10:0] dx;
      (* use_ripple = 0 *) wire [9:0] dy;
      assign dx=I_x[10:0]-badge_x[d];
      assign dy=I_y[9:0]-badge_y[d];
      assign badge_dx[d]=dx;
      assign badge_dy[d]=dy;
    end endgenerate
'''
    text=text.replace(needle,added+needle)
    old='''        if(slot_valid[j]&&px>=badge_x[j]&&px<badge_x[j]+11'd144&&
          py>=badge_y[j]&&py<badge_y[j]+10'd16)begin
          label_hit_c=1;dx_c=px-badge_x[j];row_c=py-badge_y[j];'''
    new='''        if(slot_valid[j]&&((IMG_WIDTH==1280&&IMG_HEIGHT==720&&BADGE_W==144)?
          (badge_dx[j]<11'd144&&badge_dy[j]<10'd16):
          (px>=badge_x[j]&&px<badge_x[j]+11'd144&&py>=badge_y[j]&&py<badge_y[j]+10'd16)))begin
          label_hit_c=1;
          if(IMG_WIDTH==1280&&IMG_HEIGHT==720&&BADGE_W==144)begin
            dx_c=badge_dx[j][7:0];row_c=badge_dy[j][3:0];
          end else begin dx_c=px-badge_x[j];row_c=py-badge_y[j];end'''
    assert text.count(old)==1
    return text.replace(old,new)

BENCH=r'''
`timescale 1ns/1ps
module tb;
reg clk=0;always #2 clk=~clk;
reg rst_n=0,frame_start=0,online=0,update=0,valid=0;
reg [11:0] x=0,y=0;reg [2:0] count=0;reg [511:0] boxes=0;
wire ha,hb;wire [23:0] ca,cb;wire [47:0] ba,bb;wire [3:0] sa,sb;
hxa_multibox_overlay_control a(.I_clk(clk),.I_rst_n(rst_n),.I_x(x),.I_y(y),
 .I_frame_start(frame_start),.I_aux_online(online),.I_update(update),.I_valid(valid),
 .I_count(count),.I_boxes(boxes),.O_hit(ha),.O_color(ca),.O_summary_bcd(ba),.O_summary_slots(sa));
hxa_multibox_overlay_candidate b(.I_clk(clk),.I_rst_n(rst_n),.I_x(x),.I_y(y),
 .I_frame_start(frame_start),.I_aux_online(online),.I_update(update),.I_valid(valid),
 .I_count(count),.I_boxes(boxes),.O_hit(hb),.O_color(cb),.O_summary_bcd(bb),.O_summary_slots(sb));
integer checks=0,frames=0,hits=0,i,j,k,r,n,tx,ty;
reg [31:0] seed=32'h20261113;
function [31:0] rnd;begin seed=seed^(seed<<13);seed=seed^(seed>>17);seed=seed^(seed<<5);rnd=seed;end endfunction
task tick;begin
 @(posedge clk);#0.2;checks=checks+1;
 if({ha,ca,ba,sa}!=={hb,cb,bb,sb})begin
  $display("MISMATCH check=%0d xy=%0d,%0d hits=%b,%b colors=%h,%h bcd=%h,%h slots=%h,%h",checks,x,y,ha,hb,ca,cb,ba,bb,sa,sb);$fatal(1);
 end
 if(ha)hits=hits+1;
 @(negedge clk);
end endtask
task boxset(input integer slot,input integer x0,y0,x1,y1,cl,conf);begin
 boxes[slot*128+:128]={32'd0,8'd0,conf[7:0],cl[15:0],y1[15:0],x1[15:0],y0[15:0],x0[15:0]};
end endtask
task publish;begin update=~update;repeat(8)tick();end endtask
task fullframe;begin
 frame_start=1;tick();frame_start=0;
 for(ty=0;ty<720;ty=ty+1)for(tx=0;tx<1280;tx=tx+1)begin x=tx;y=ty;tick();end
 frames=frames+1;
end endtask
initial begin
 repeat(4)tick();rst_n=1;valid=1;count=4;
 boxset(0,0,0,300,200,1,100);boxset(1,160,100,700,600,5,0);
 boxset(2,1000,650,1280,720,9,99);boxset(3,1240,700,1280,720,3,37);
 publish();fullframe();
 // Four fully overlapping target/badge layers exercise slot-zero priority.
 for(i=0;i<4;i=i+1)boxset(i,600,300,800,500,i+1,90+i);
 publish();online=1;frame_start=1;tick();frame_start=0;fullframe();
 // Extreme malformed source words retain default modulo equivalence.
 boxset(0,65535,65535,65535,65535,15,255);
 boxset(1,2047,1023,0,0,0,128);
 boxset(2,1136,16,1280,719,7,9);
 boxset(3,0,0,0,0,2,10);publish();fullframe();
 // Exhaust complete natural coordinate axes around randomized loaded badges.
 for(i=0;i<128;i=i+1)begin
  for(k=0;k<4;k=k+1)boxset(k,rnd(),rnd(),rnd(),rnd(),1+rnd()%9,rnd()%256);
  count=rnd()%8;valid=(i%9)!=0;publish();
  for(k=0;k<4;k=k+1)begin
   for(j=0;j<2048;j=j+1)begin x=j;y=a.badge_y[k]+((j%19)-2);tick();end
   for(j=0;j<1024;j=j+1)begin y=j;x=a.badge_x[k]+((j%147)-2);tick();end
  end
 end
 // Alias high input bits, resets, cancellations, update coalescing, link edges.
 for(i=0;i<100000;i=i+1)begin
  x=rnd();y=rnd();
  if(i%29==0)begin count=rnd()%8;valid=rnd()%2;update=~update;end
  if(i%89==0)for(k=0;k<4;k=k+1)boxset(k,rnd(),rnd(),rnd(),rnd(),rnd(),rnd());
  frame_start=i%701==0;if(i%409==0)online=~online;
  rst_n=i%7919!=0;tick();
 end
 rst_n=1;repeat(4)tick();
 $display("MULTIBOX_BADGE_EQUIVALENCE_PASS checks=%0d full_frames=%0d hit_cycles=%0d seed=20261113",checks,frames,hits);$finish;
end
endmodule
'''

def area(name,source):
    directory=OUT/name;directory.mkdir()
    local=directory/'hxa_multibox_overlay.v';local.write_text(source,encoding='utf-8')
    # Expose every real output. Identical serial input wrappers keep package
    # IO count below 160 without tying off or folding any functional bits.
    # Common wrapper FF/LUT overhead is included in both absolute totals.
    top=source+'''
module module_area_top(
 input wire I_clk,I_rst_n,
 input wire [11:0] I_x,I_y,
 input wire I_frame_start,I_aux_online,I_update,I_valid,
 input wire [2:0] I_count,
 input wire I_box_shift,input wire [31:0] I_box_serial,
 output wire O_hit,output wire [23:0] O_color,
 output wire [47:0] O_summary_bcd,output wire [3:0] O_summary_slots
);
 reg [511:0] serial_boxes;
 always @(posedge I_clk)if(I_box_shift)serial_boxes<={serial_boxes[479:0],I_box_serial};
 hxa_multibox_overlay actual(.I_clk(I_clk),.I_rst_n(I_rst_n),.I_x(I_x),.I_y(I_y),
 .I_frame_start(I_frame_start),.I_aux_online(I_aux_online),.I_update(I_update),.I_valid(I_valid),
 .I_count(I_count),.I_boxes(serial_boxes),.O_hit(O_hit),.O_color(O_color),
 .O_summary_bcd(O_summary_bcd),.O_summary_slots(O_summary_slots));
endmodule
'''
    (directory/'module_area_top.v').write_text(top,encoding='utf-8')
    al=(RECIPE/'module_area.al').read_text(encoding='utf-8-sig')
    al=re.sub(r'&(?!#?\w+;)', '&amp;',al).replace('BitgenProperty::GeneralOption','BitgenProperty_TD_GeneralOption')
    tree=ET.fromstring(al);tree.set('Path',directory.as_posix())
    files=tree.find('Source_Files/Verilog')
    for child in list(files):files.remove(child)
    f=ET.SubElement(files,'File',Path=(directory/'module_area_top.v').as_posix());info=ET.SubElement(f,'FileInfo')
    for attr,val in [('UsedInSyn','true'),('UsedInP&R','true'),('BelongTo','design_1'),('CompileOrder','1')]:ET.SubElement(info,'Attr',Name=attr,Val=val)
    ET.indent(tree)
    (directory/'module_area.al').write_text('<?xml version="1.0" encoding="UTF-8"?>\n'+ET.tostring(tree,encoding='unicode').replace('BitgenProperty_TD_GeneralOption','BitgenProperty::GeneralOption')+'\n',encoding='utf-8')
    (directory/'run.tcl').write_text((RECIPE/'run.tcl').read_text(encoding='utf-8'),encoding='utf-8')
    row=run(directory,'td',[str(TD),'run.tcl'])
    text=(directory/'td.log').read_text(encoding='utf-8',errors='replace')
    assert text.splitlines().count('MODULE_AREA_GATE_PASS')==1 and not re.search(r'\b(?:ERROR|FATAL)\b',text)
    assert (directory/'.module_gate.end.f').is_file()
    report=(directory/'module_area_after_legalize.area').read_text(encoding='utf-8')
    gate=(directory/'module_area_gate.area').read_text(encoding='utf-8')
    def stat(key,text=report):
        m=re.search(r'^'+re.escape(key)+r'\s+(\d+)\b',text,re.M);return int(m[1])if m else None
    result={'slices':stat('#slice*') if stat('#slice*') is not None else stat('#slice'),
            'registers':stat('#reg'),'raw_lut':stat('#lut',gate),'lslice':stat('#lslice'),
            'eram':stat('#eram'),'dsp':stat('#dsp'),'source_sha256':sha(local),
            'gate_report_sha256':sha(directory/'module_area_gate.area'),
            'legalized_report_sha256':sha(directory/'module_area_after_legalize.area'),'execution':row}
    put(directory/'AREA_RESULT.json',result)
    print(name+' '+json.dumps(result),flush=True)
    return result

def main():
    OUT.mkdir(parents=True)
    before=sha(BASE);original=BASE.read_text(encoding='utf-8');changed=candidate(original)
    (OUT/'original.v').write_text(original.replace('module hxa_multibox_overlay #(', 'module hxa_multibox_overlay_control #(',1),encoding='utf-8')
    (OUT/'candidate.v').write_text(changed.replace('module hxa_multibox_overlay #(', 'module hxa_multibox_overlay_candidate #(',1),encoding='utf-8')
    (OUT/'tb.sv').write_text(BENCH,encoding='utf-8')
    put(OUT/'INPUTS.json',{'production_source':str(BASE),'production_sha256':before,'runner_sha256':sha(__file__),
                         'recipe':str(RECIPE),'recipe_project_sha256':sha(RECIPE/'module_area.al'),
                         'recipe_tcl_sha256':sha(RECIPE/'run.tcl')})
    rows=[]
    rows.append(run(OUT,'vlib',['E:/model/win64/vlib.exe','rtl_lib'],env=ENV))
    rows.append(run(OUT,'compile',['E:/model/win64/vlog.exe','-sv','-work','rtl_lib','original.v','candidate.v','tb.sv'],env=ENV))
    rows.append(run(OUT,'simulation',['E:/model/win64/vsim.exe','-batch','-syncio','-quiet','-lib','rtl_lib','tb',
        '-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'],env=ENV))
    simulation=(OUT/'simulation.log').read_text(encoding='utf-8')
    assert simulation.count('MULTIBOX_BADGE_EQUIVALENCE_PASS ')==1
    marker=next(line for line in simulation.splitlines() if 'MULTIBOX_BADGE_EQUIVALENCE_PASS ' in line)
    print(marker,flush=True)
    areas={}
    areas['baseline']=area('baseline',original)
    areas['candidate']=area('candidate',changed)
    assert sha(BASE)==before,'Production input drift'
    saving=areas['baseline']['raw_lut']-areas['candidate']['raw_lut']
    result={'status':'PASS','rtl_marker':marker,'simulation':rows,'area':areas,'raw_lut_saving':saving,
            'production_input_unchanged':True,'production_rtl_modified':False,'hardware_status':'NOT_RUN',
            'scope':'Real four-target module and actual initialized glyph ROM, targeted full output miter plus independent fresh area-only synthesis. Identical 32-bit serial-box input wrapper overhead included in both area totals to fit physical IO limit. No whole-board place/route or bitgen.',
            'recommendation':'DO_NOT_INTEGRATE_INSUFFICIENT_SAVINGS' if saving<50 else 'AREA_CANDIDATE_FOR_WHOLE_BOARD_VERIFICATION'}
    put(OUT/'RESULT.json',result)
    print('RESULT '+str(OUT/'RESULT.json'),flush=True)

if __name__=='__main__':main()
