"""Source-bound per-target centre glyphs, moving pixel pipeline and mode gates."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,os,re,subprocess
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent/'main_doc_center80_cartoon_paperfree_20261118'
BUILD=Path('E:/codex_main_cnn_multicoord_20261118_r1')
HDL=ROOT/'01_rtl/imgq_gain_m/main/user_source/hdl_source'
AUD=ROOT.parent/'audit_multicoord_idle_20261118'
OUT=ROOT/'reports/multicoord'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ');OUT.mkdir(parents=True)
SIM=Path('E:/model/win64');ENV=dict(os.environ,LM_LICENSE_FILE=str(SIM/'LICENSE.TXT'),MGLS_LICENSE_FILE=str(SIM/'LICENSE.TXT'))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
inputs={};tests={}
def pin(p):p=Path(p).resolve();inputs[str(p)]=sha(p);return p
def run(name,files,top,marker):
 out=OUT/name;out.mkdir();steps=[]
 for label,args in [('vlib',[SIM/'vlib.exe','rtl_lib']),('compile',[SIM/'vlog.exe','-sv','-lint','-work','rtl_lib','+incdir+'+str(HDL),*map(pin,files)]),('simulation',[SIM/'vsim.exe','-batch','-quiet','-lib','rtl_lib',top,'-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'])]:
  log=out/(label+'.log')
  with log.open('xb') as f:cp=subprocess.run(list(map(str,args)),cwd=out,env=ENV,stdout=f,stderr=subprocess.STDOUT,timeout=300)
  t=log.read_text(errors='replace');assert cp.returncode==0 and not re.search(r'\*\* (?:Error|Fatal):',t),t[-4000:]
  steps.append(dict(command=list(map(str,args)),exit_code=cp.returncode,log=str(log),sha256=sha(log)))
 assert marker in t,t[-4000:]
 tests[name]=dict(status='PASS',marker=marker,steps=steps);print(name,'PASS',flush=True)
pin(__file__);pin(HDL/'osd_compact_glyphs.vh')
for rel,row in json.loads((BUILD/'SOURCE_MANIFEST.json').read_text())['files'].items():
 assert sha(BUILD/rel)==row['sha256']
 if rel.startswith(('01_rtl/','04_pin/')) and not rel.endswith(('.al','.prj','source_snapshot.json')):assert sha(ROOT/rel)==row['sha256']
base=(AUD/'tb_multicoord.sv').read_text();pin(AUD/'tb_multicoord.sv')
# Every cycle advances to a new glyph/column/slot. Expected font bits follow
# exactly the same two-edge pixel latency as the real synchronous ROM.
head=base[:base.index('integer a,b,c,d;')]
tail=r'''
reg [15:0] expect_bits[0:4095];reg[7:0] want_char;
reg[3:0] want_row,want_col;reg[15:0] expected_pixels[0:2];
integer s,c,r,j,cyc=0,a,b,k;
reg [15:0] xx,yy;
initial begin
 for(k=0;k<4096;k++)expect_bits[k]=font.glyph_rom[k];
 tick(4);rst_n=1;
 for(s=0;s<4;s++)begin
  boxes[s*128+:16]=s*200;boxes[s*128+32+:16]=s*200+140;
  boxes[s*128+16+:16]=s*100;boxes[s*128+48+:16]=s*100+80;
 end
 snap;
 for(s=0;s<4;s++)for(r=0;r<16;r++)for(c=0;c<13;c++)for(j=0;j<16;j++)begin
  xx=bcd(s*200+70);yy=bcd(s*100+40);
  want_char=" ";
  case(c)
   0:want_char="X";1,8:want_char=":";7:want_char="Y";
   2,3,4,5:want_char=8'h30+((xx>>((5-c)*4))&15);
   9,10,11,12:want_char=8'h30+((yy>>((12-c)*4))&15);
  endcase
  @(negedge clk);x=872+c*16+j;y=164+s*40+r;
  expected_pixels[cyc%3]=(expect_bits[{want_char,4'(r)}]>>(15-j))&1;
  @(posedge clk);#1;
  if(cyc>=1&&text!==expected_pixels[(cyc-1)%3][0])
   $fatal(1,"pixel pipeline mismatch cycle%0d slot%0d col%0d row%0d got%b expected%b",cyc,s,c,r,text,expected_pixels[(cyc-1)%3][0]);
  cyc++;
 end
 $display("MULTICOORD_PIXEL_PIPELINE_PASS pixels=%0d",cyc);$finish;
end
endmodule
'''
bench=OUT/'tb_multicoord_pixels.sv';bench.write_text((head+tail).replace('module tb_multicoord;','module tb_multicoord_pixels;'))
files=[HDL/n for n in ('osd_operator_decimal_snapshot.v','osd_compact_panel.v','osd_compact_font_rom.v','operator_ui_text.v')]
run('coordinates',files+[AUD/'tb_multicoord.sv'],'tb_multicoord','MULTICOORD_PASS')
run('pixels',files+[bench],'tb_multicoord_pixels','MULTICOORD_PIXEL_PIPELINE_PASS')
run('operator',[HDL/n for n in ('osd_compact_panel.v','osd_compact_font_rom.v','operator_ui_text.v')]+[ROOT/'tests/dynamic_osd/tb_dynamic_status.sv'],'tb_dynamic_status','DYNAMIC_OSD_PASS')
shared=ROOT/'01_rtl/imgq_gain_m/shared/rtl'
run('protocol',[shared/'hxa_packet_codec.v',shared/'hxa_main_link.v',ROOT/'tests/dynamic_osd/tb_type21_maintenance.sv'],'tb_type21_maintenance','TYPE21_MAINTENANCE_PASS')
assert all(sha(p)==h for p,h in inputs.items())
r=dict(status='PASS',source_manifest_sha256=sha(BUILD/'SOURCE_MANIFEST.json'),inputs=inputs,tests=tests,hardware_status='NOT_RUN')
(OUT/'RESULT.json').write_text(json.dumps(r,indent=2)+'\n')
(ROOT/'reports/MULTICOORD_LATEST.json').write_text(json.dumps(dict(path=str(OUT/'RESULT.json'),sha256=sha(OUT/'RESULT.json')),indent=2)+'\n')
