"""Isolated equivalent SUSPECT center/cross area comparisons; never board-builds."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, os, re, subprocess, sys
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/cross_area'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
OUT.mkdir(parents=True)
TD=Path('E:/td/bin/td_commands_prompt.exe')
RECIPE=ROOT.parent/'main_pcb_operator_ui_cn_font_shift1_dynamic_osd_20261113/baseline_reference/font_shift1_reports/area/20261113T001002_579173Z'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
def write(p,v):p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

header='''module module_area_top(input wire clk,rst_n,commit,
 input wire [10:0] raw_x0,raw_x1,input wire [9:0] raw_y0,raw_y1,
 input wire [11:0] px,py,
 output reg [10:0] x0,x1,output reg [9:0] y0,y1,output reg hit);
'''
body='''
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin x0<=0;x1<=0;y0<=0;y1<=0;end
  else if(commit)begin x0<=raw_x0;x1<=raw_x1-1'b1;y0<=raw_y0;y1<=raw_y1-1'b1;end
 end
 wire box_in=(px>=x0)&&(px<=x1)&&(py>=y0)&&(py<=y1);
 wire border=(px<=x0+11'd2)||(px+11'd2>=x1)||(py<=y0+10'd2)||(py+10'd2>=y1);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)hit<=0;else hit<=box_in&&(border||cross_hit);
 end
endmodule
'''
registered='''
 reg [10:0] cx;reg [9:0] cy;
 wire [11:0] sx={1'b0,raw_x0}+{1'b0,raw_x1};
 wire [10:0] sy={1'b0,raw_y0}+{1'b0,raw_y1};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin cx<=0;cy<=0;end
  else if(commit)begin cx<=sx[11:1];cy<=sy[10:1];end
 end
'''
derived='''
 wire [11:0] sx={1'b0,x0}+{1'b0,x1}+12'd1;
 wire [10:0] sy={1'b0,y0}+{1'b0,y1}+11'd1;
 wire [10:0] cx=sx[11:1];wire [9:0] cy=sy[10:1];
'''
range_cross='''
 wire cross_hit=((px=={1'b0,cx})&&(py+12'd4>={2'd0,cy})&&(py<={2'd0,cy}+12'd4))||
 ((py=={2'd0,cy})&&(px+12'd4>={1'b0,cx})&&(px<={1'b0,cx}+12'd4));
'''
modular_cross='''
 wire [11:0] dx=px+12'd4-{1'b0,cx};
 wire [11:0] dy=py+12'd4-{2'd0,cy};
 wire cross_hit=((dx==12'd4)&&(dy<=12'd8))||((dy==12'd4)&&(dx<=12'd8));
'''
equality_modular='''
 wire [11:0] dx=px+12'd4-{1'b0,cx};
 wire [11:0] dy=py+12'd4-{2'd0,cy};
 wire cross_hit=((px=={1'b0,cx})&&(dy<=12'd8))||((py=={2'd0,cy})&&(dx<=12'd8));
'''
narrow_modular='''
 wire [10:0] dx=px[10:0]+11'd4-cx;
 wire [9:0] dy=py[9:0]+10'd4-cy;
 wire cross_hit=((dx==11'd4)&&(dy<=10'd8))||((dy==10'd4)&&(dx<=11'd8));
'''
natural_range='''
 wire [10:0] nx=px[10:0];wire [9:0] ny=py[9:0];
 wire cross_hit=((nx==cx)&&(ny+10'd4>=cy)&&(ny<=cy+10'd4))||
 ((ny==cy)&&(nx+11'd4>=cx)&&(nx<=cx+11'd4));
'''
dot_cross='''
 wire [10:0] nx=px[10:0];wire [9:0] ny=py[9:0];
 wire cross_hit=(nx==cx)&&(ny==cy);
'''
radius1_cross='''
 wire [10:0] nx=px[10:0];wire [9:0] ny=py[9:0];
 wire cross_hit=((nx==cx)&&(ny+10'd1>=cy)&&(ny<=cy+10'd1))||
 ((ny==cy)&&(nx+11'd1>=cx)&&(nx<=cx+11'd1));
'''
dotted_cross='''
 wire [10:0] nx=px[10:0];wire [9:0] ny=py[9:0];
 wire cross_hit=((nx==cx)&&(ny[2:0]==cy[2:0]))||
 ((ny==cy)&&(nx[2:0]==cx[2:0]));
'''
derived_no_ripple='''
 (* use_ripple = 0 *) wire [11:0] sx;
 (* use_ripple = 0 *) wire [10:0] sy;
 assign sx={1'b0,x0}+{1'b0,x1}+12'd1;
 assign sy={1'b0,y0}+{1'b0,y1}+11'd1;
 wire [10:0] cx=sx[11:1];wire [9:0] cy=sy[10:1];
'''
variants={'A_registered_range':registered+range_cross,
          'B_derived_modular':derived+modular_cross,
          'C_registered_modular':registered+modular_cross,
          'D_derived_range':derived+range_cross,
          'E_derived_equality_modular':derived+equality_modular,
          'F_derived_narrow_modular':derived+narrow_modular,
          'G_derived_natural_range':derived+natural_range,
          'H_derived_natural_range_border':derived+natural_range,
          'I_derived_dot_border':derived+dot_cross,
          'J_derived_radius1_border':derived+radius1_cross,
          'L_derived_dotted_cross_border':derived+dotted_cross,
          'M_dotted_no_ripple_center':derived_no_ripple+dotted_cross,
          'N_short_cross_no_ripple_center':derived_no_ripple+natural_range}

# Exhaustive 1-D predicate proof over every legal center and video sample;
# cross is a Boolean combination of these axis predicates.
axis_checks=0
for length in (1280,720):
 p=np.arange(length,dtype=np.int64)[:,None]
 c=np.arange(length,dtype=np.int64)[None,:]
 current=(p+4>=c)&(p<=c+4)
 modular=((p+4-c)&4095)<=8
 assert np.array_equal(current,modular)
 mask=2047 if length==1280 else 1023
 assert np.array_equal(current,((p+4-c)&mask)<=8)
 assert np.array_equal(current,((((p+4)&mask)>=c)&(p<=((c+4)&mask))))
 assert np.array_equal(p<=c+2,(p&mask)<=((c+2)&mask))
 assert np.array_equal(p+2>=c,((p+2)&mask)>=(c&mask))
 axis_checks+=length*length
# Every legal half-open axis interval: raw center equals reconstructed inclusive center.
interval_checks=0
for length in (1280,720):
 for end in range(1,length+1):
  start=np.arange(end,dtype=np.int64)
  assert np.array_equal((start+end)//2,(start+(end-1)+1)//2)
  interval_checks+=end
# Full frame pixels for deterministic edge/parity boxes, plus reproducible small boxes.
rng=np.random.default_rng(20261113)
boxes=[(0,1,0,1),(0,1280,0,720),(1279,1280,719,720),
 (0,9,0,9),(1271,1280,711,720),(5,17,6,21),(5,18,6,22),(200,202,100,104)]
full_checks=0
p=np.arange(1280,dtype=np.int64)[None,:]
q=np.arange(720,dtype=np.int64)[:,None]
for x0,xr,y0,yr in boxes:
 cx=(x0+xr)//2;cy=(y0+yr)//2
 a=((p==cx)&(q+4>=cy)&(q<=cy+4))|((q==cy)&(p+4>=cx)&(p<=cx+4))
 dx=(p+4-cx)&4095;dy=(q+4-cy)&4095
 b=((dx==4)&(dy<=8))|((dy==4)&(dx<=8))
 assert np.array_equal(a,b)
 full_checks+=1280*720
random_checks=0
for _ in range(4096):
 x0=int(rng.integers(0,1280));y0=int(rng.integers(0,720))
 xr=min(1280,x0+int(rng.integers(1,34)));yr=min(720,y0+int(rng.integers(1,34)))
 cx=(x0+xr)//2;cy=(y0+yr)//2
 x=np.arange(max(0,x0-6),min(1280,xr+6),dtype=np.int64)[None,:]
 y=np.arange(max(0,y0-6),min(720,yr+6),dtype=np.int64)[:,None]
 a=((x==cx)&(y+4>=cy)&(y<=cy+4))|((y==cy)&(x+4>=cx)&(x<=cx+4))
 dx=(x+4-cx)&4095;dy=(y+4-cy)&4095
 b=((dx==4)&(dy<=8))|((dy==4)&(dx<=8))
 assert np.array_equal(a,b)
 random_checks+=a.size
software={'status':'PASS','axis_exhaustive_checks':axis_checks,
 'interval_exhaustive_checks':interval_checks,'full_frame_checks':full_checks,
 'random_small_box_count':4096,'random_small_box_pixel_checks':random_checks,
 'seed':20261113,'domain':'Legal active video x=0..1279 y=0..719; valid half-open nonempty source boxes.'}
write(OUT/'SOFTWARE_EQUIVALENCE.json',software)
print('SOFTWARE_EQUIVALENCE_PASS '+str(software),flush=True)

# Real RTL miter for three separately generated modules; compare full box outputs and hit.
sv=['module tb; reg clk=0;always #5 clk=~clk;reg rst_n=0,commit=0;',
 'reg [10:0] rx0=0,rx1=1;reg [9:0] ry0=0,ry1=1;reg [11:0] px=0,py=0;']
for idx,(name,variant) in enumerate(variants.items()):
 module_body=body
 if name[0]in'HIJLMN':
  module_body=module_body.replace('wire border=(px<=x0+11\'d2)||(px+11\'d2>=x1)||(py<=y0+10\'d2)||(py+10\'d2>=y1);',
   'wire border=(nx<=x0+11\'d2)||(nx+11\'d2>=x1)||(ny<=y0+10\'d2)||(ny+10\'d2>=y1);')
 src=header+variant+module_body
 directory=OUT/name;directory.mkdir()
 (directory/'module_area_top.v').write_text(src,encoding='utf-8')
 (OUT/(name+'.v')).write_text(src.replace('module module_area_top','module cross_'+str(idx),1),encoding='utf-8')
 sv.append(f'wire [42:0] result{idx};cross_{idx} d{idx}(.clk(clk),.rst_n(rst_n),.commit(commit),.raw_x0(rx0),.raw_x1(rx1),.raw_y0(ry0),.raw_y1(ry1),.px(px),.py(py),.x0(result{idx}[42:32]),.x1(result{idx}[31:21]),.y0(result{idx}[20:11]),.y1(result{idx}[10:1]),.hit(result{idx}[0]));')
sv.append('''
 wire [10:0] bx0=result0[42:32],bx1=result0[31:21];
 wire [9:0] by0=result0[20:11],by1=result0[10:1];
 wire [11:0] rsx={1'b0,bx0}+{1'b0,bx1}+12'd1;
 wire [10:0] rsy={1'b0,by0}+{1'b0,by1}+11'd1;
 wire [10:0] rcx=rsx[11:1];wire [9:0] rcy=rsy[10:1];
 wire rin=(px>=bx0)&&(px<=bx1)&&(py>=by0)&&(py<=by1);
 wire rborder=(px<=bx0+11'd2)||(px+11'd2>=bx1)||(py<=by0+10'd2)||(py+10'd2>=by1);
 reg ri,rj,rl;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin ri<=0;rj<=0;rl<=0;end
  else begin
   ri<=rin&&(rborder||((px==rcx)&&(py==rcy)));
   rj<=rin&&(rborder||((px==rcx)&&(py+12'd1>=rcy)&&(py<=rcy+12'd1))||((py==rcy)&&(px+12'd1>=rcx)&&(px<=rcx+12'd1)));
   rl<=rin&&(rborder||((px==rcx)&&(py[2:0]==rcy[2:0]))||((py==rcy)&&(px[2:0]==rcx[2:0])));
  end
 end
 integer i,j,k,nx,ny,checks=0;reg [31:0] seed=32'h20261113;
 function [31:0] rnd;begin seed=seed^(seed<<13);seed=seed^(seed>>17);seed=seed^(seed<<5);rnd=seed;end endfunction
 task check;begin @(posedge clk);#1;checks=checks+1;if(result0!==result1||result0!==result2||result0!==result3||result0!==result4||result0!==result5||result0!==result6||result0!==result7||result8[42:1]!==result0[42:1]||result9[42:1]!==result0[42:1]||result10[42:1]!==result0[42:1]||result8[0]!==ri||result9[0]!==rj||result10[0]!==rl||result11!==result10||result12!==result0)begin
 $display("MISMATCH %h %h %h %h %h %h %h %h",result0,result1,result2,result3,result4,result5,result6,result7);$fatal(1);end end endtask
 initial begin
 #2;check();@(negedge clk);rst_n=1;
 for(i=0;i<2048;i=i+1)begin
  @(negedge clk);rx0=rnd()%1280;ry0=rnd()%720;rx1=rx0+1+rnd()%(1280-rx0);ry1=ry0+1+rnd()%(720-ry0);commit=1;
  check();@(negedge clk);commit=0;
  for(j=0;j<17;j=j+1)for(k=0;k<17;k=k+1)begin
   nx=((rx0+rx1)/2)+j-8;ny=((ry0+ry1)/2)+k-8;
   px=nx<0?0:(nx>1279?1279:nx);py=ny<0?0:(ny>719?719:ny);
   check();@(negedge clk);
  end
  px=rnd()%1280;py=rnd()%720;check();
 end
 $display("CROSS_EQUIVALENCE_PASS checks=%0d",checks);$finish;
 end
endmodule
''')
(OUT/'tb.sv').write_text('\n'.join(sv),encoding='utf-8')
env=dict(os.environ,LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT',MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT')
sim=[]
for label,cmd in [('vlib',['E:/model/win64/vlib.exe','rtl_lib']),
 ('vlog',['E:/model/win64/vlog.exe','-sv','-work','rtl_lib',*[name+'.v' for name in variants],'tb.sv']),
 ('vsim',['E:/model/win64/vsim.exe','-batch','-syncio','-quiet','-lib','rtl_lib','tb','-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'])]:
 p=subprocess.run(cmd,cwd=OUT,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',timeout=300)
 (OUT/(label+'.log')).write_text(p.stdout,encoding='utf-8')
 sim.append({'step':label,'returncode':p.returncode,'log_sha256':sha(OUT/(label+'.log'))})
 assert p.returncode==0,(label,p.stdout)
assert 'CROSS_EQUIVALENCE_PASS' in (OUT/'vsim.log').read_text(encoding='utf-8')
print('RTL_EQUIVALENCE_PASS',flush=True)

area={}
for name in variants:
 if len(sys.argv)>1 and not any(name.startswith(prefix)for prefix in sys.argv[1:]):continue
 directory=OUT/name
 al=(RECIPE/'module_area.al').read_text(encoding='utf-8-sig')
 al=re.sub(r'&(?!#?\w+;)', '&amp;',al)
 al=re.sub(r'Path="[^"]*"',lambda m:m.group(0),al) # Parse below; no path interpolation into shell.
 import xml.etree.ElementTree as ET
 al=al.replace('BitgenProperty::GeneralOption','BitgenProperty_TD_GeneralOption')
 tree=ET.fromstring(al);tree.set('Path',directory.as_posix())
 sources=tree.find('Source_Files/Verilog')
 for child in list(sources):sources.remove(child)
 f=ET.SubElement(sources,'File',Path=(directory/'module_area_top.v').as_posix());info=ET.SubElement(f,'FileInfo')
 for attr,val in [('UsedInSyn','true'),('UsedInP&R','true'),('BelongTo','design_1'),('CompileOrder','1')]:ET.SubElement(info,'Attr',Name=attr,Val=val)
 ET.indent(tree)
 (directory/'module_area.al').write_text('<?xml version="1.0" encoding="UTF-8"?>\n'+ET.tostring(tree,encoding='unicode').replace('BitgenProperty_TD_GeneralOption','BitgenProperty::GeneralOption')+'\n',encoding='utf-8')
 (directory/'run.tcl').write_text((RECIPE/'run.tcl').read_text(encoding='utf-8'),encoding='utf-8')
 with (directory/'td.log').open('wb') as log:p=subprocess.run([str(TD),'run.tcl'],cwd=directory,stdout=log,stderr=subprocess.STDOUT,timeout=300)
 log=(directory/'td.log').read_text(encoding='utf-8',errors='replace')
 assert p.returncode==0 and 'MODULE_AREA_GATE_PASS' in log,(name,log[-3000:])
 report=(directory/'module_area_after_legalize.area').read_text(encoding='utf-8')
 def stat(key):
  m=re.search(r'^'+re.escape(key)+r'\s+(\d+)\b',report,re.M);return int(m[1]) if m else None
 area[name]={'slices':stat('#slice*')if stat('#slice*')is not None else stat('#slice'),'registers':stat('#reg'),'lut':stat('#lut'),
             'lslice':stat('#lslice'),'mslice':stat('#mslice'),'eram':stat('#eram'),'dsp':stat('#dsp'),
             'report_sha256':sha(directory/'module_area_after_legalize.area'),
             'source_sha256':sha(directory/'module_area_top.v'),'log_sha256':sha(directory/'td.log')}
 gate=(directory/'module_area_gate.area').read_text(encoding='utf-8')
 area[name]['gate_slices_before_legalize']=int(re.search(r'^#slice\*?\s+(\d+)',gate,re.M)[1])
 area[name]['gate_raw_lut_before_legalize']=int(re.search(r'^#lut\s+(\d+)',gate,re.M)[1])
 print(name+' '+json.dumps(area[name]),flush=True)
 write(OUT/'PARTIAL_AREA.json',area)
result={'status':'PASS','area':area,'software':software,'rtl':sim,
 'scope':'Isolated exact-function registered rectangle + cross + one hit pipeline FF. Shared box registers 42 bits are retained by output ports. No whole-board build, placement, timing or bitgen.',
 'actual_source_rtl_modified':False,'hardware':'NOT_RUN','script_sha256':sha(Path(__file__))}
write(OUT/'RESULT.json',result)
print('RESULT '+str(OUT/'RESULT.json'),flush=True)
