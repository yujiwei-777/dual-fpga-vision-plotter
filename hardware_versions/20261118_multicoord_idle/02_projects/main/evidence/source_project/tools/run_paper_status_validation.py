"""Verify real production paper-status-off panel/font and default compatibility."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,re,os,subprocess
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent/'main_cartoon_bolder_20261118'
BUILD=Path('E:/codex_main_cnn_multicoord_20261118_r1')
REL=Path('01_rtl/imgq_gain_m/main/user_source/hdl_source');HDL=ROOT/REL
OUT=ROOT/'reports/paper_status_validation'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
ENV=dict(os.environ,LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT',MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT');INPUTS={}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def bind(p):p=Path(p).resolve();INPUTS[str(p)]=sha(p);return p
def paired(rel):p=bind(ROOT/rel);assert sha(p)==sha(bind(BUILD/rel)),str(rel);return p
def put(p,o):Path(p).write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
OUT.mkdir(parents=True);bind(__file__)
for rel,row in json.loads((BUILD/'SOURCE_MANIFEST.json').read_text())['files'].items():assert sha(BUILD/rel)==row['sha256']
changes=[]
for d in ('01_rtl','04_pin'):
 for p in sorted((ROOT/d).rglob('*')):
  if p.is_file() and p.name!='source_snapshot.json' and p.suffix not in ('.al','.prj'):
   q=bind(BASE/p.relative_to(ROOT));bind(p)
   if sha(p)!=sha(q):changes.append(p.relative_to(ROOT).as_posix())
assert changes==[(REL/n).as_posix() for n in ('doc_copy_overlay.v','hdmi_mixer.v','hxa_multibox_overlay.v','operator_ui_text.v','osd_compact_panel.v','osd_operator_decimal_snapshot.v','result_overlay.v')],changes
mixer=paired(REL/'hdmi_mixer.v');mix=mixer.read_text(encoding='utf-8')
assert mix.count("osd_compact_panel #(.PAPER_STATUS_ENABLE(1'b0)) u_osd_compact_panel(")==1
prior=(ROOT.parent/'main_doc_center80_cartoon_paperfree_20261118'/REL/'hdmi_mixer.v').read_text(encoding='utf-8')
expected=prior.replace('wire [5:0] S_operator_digit_addr;','wire [6:0] S_operator_digit_addr;').replace('.operator_data(I_operator_data),.operator_digit_addr(S_operator_digit_addr)', '.operator_data(I_operator_data),.multi_boxes(I_multi_boxes),.operator_digit_addr(S_operator_digit_addr)').replace(".multi_active((I_multi_valid===1'b1)&&I_ovl_on),",".multi_active((I_multi_valid===1'b1)&&I_ovl_on),\n        .recognition_enable(I_ovl_on),")
assert mix==expected,'Unexpected current mixer delta'
assert prior.replace("osd_compact_panel #(.PAPER_STATUS_ENABLE(1'b0)) u_osd_compact_panel(",'osd_compact_panel u_osd_compact_panel(')==(BASE/REL/'hdmi_mixer.v').read_text(encoding='utf-8')
top=paired(REL/'design_top_wrapper.v');assert '.I_operator_valid(S_operator_valid_px && !S_mode_cnn_px)' in top.read_text(encoding='utf-8')
oldpanel=bind(BASE/REL/'osd_compact_panel.v').read_text(encoding='utf-8').replace('module osd_compact_panel(','module osd_compact_panel_control(',1).replace('module merged_panel_tokens(','module merged_panel_tokens_control(',1).replace('merged_panel_tokens u_shared_tokens','merged_panel_tokens_control u_shared_tokens',1).replace('operator_ui_text u_operator_text','operator_ui_text_control u_operator_text',1)
oldtext=bind(BASE/REL/'operator_ui_text.v').read_text(encoding='utf-8').replace('module operator_ui_text(','module operator_ui_text_control(',1)
control=OUT/'panel_control.v';control.write_text(oldpanel,encoding='utf-8');bind(control)
textcontrol=OUT/'operator_text_control.v';textcontrol.write_text(oldtext,encoding='utf-8');bind(textcontrol)
benchbase=paired(Path('tests/dynamic_osd/tb_dynamic_status.sv')).read_text(encoding='utf-8')
prefix=benchbase[:benchbase.index('  task sample_panel;')].replace('module tb_dynamic_status;','module tb_paper_status;')
prefix=prefix.replace('  osd_compact_panel dut(',"  osd_compact_panel #(.PAPER_STATUS_ENABLE(1'b0)) dut(")
inst=prefix[prefix.index('  osd_compact_panel #'):prefix.index('  osd_compact_font_rom font(')]
decl='\n  wire[152:0] sanitized=operator_data & ~(153\'d1<<2);\n'
for name,module,data in [('default','osd_compact_panel','operator_data'),('old','osd_compact_panel_control','operator_data'),('clean','osd_compact_panel_control','sanitized')]:
 decl+=f"  wire[5:0] {name}_operator_digit_addr;wire {name}_panel_on,{name}_panel_border,{name}_text_on;wire[23:0]{name}_text_color;wire[7:0]{name}_font_glyph;wire[3:0]{name}_font_row;wire[15:0]{name}_bits;\n"
 copy=inst.replace("osd_compact_panel #(.PAPER_STATUS_ENABLE(1'b0)) dut(",module+' '+name+'_dut(').replace('.operator_data(operator_data)',f'.operator_data({data})')
 for n in ('operator_digit_addr','panel_on','panel_border','text_on','text_color','font_glyph','font_row'):copy=copy.replace(f'.{n}({n})',f'.{n}({name}_{n})')
 copy=copy.replace('.font_row_bits(font_row_bits)',f'.font_row_bits({name}_bits)')
 decl+=copy+f'  osd_compact_font_rom {name}_font(.clk(clk),.glyph({name}_font_glyph),.row({name}_font_row),.row_bits({name}_bits));\n'
tail=r"""
 integer checks=0,blank_pixels=0,default_checks=0,preserved_checks=0,hidden_full=0,red_checks=0,fx,st,k,ix,iy,v,which;
 reg is_paper_row;
 task sample;
 begin
  repeat(5)@(posedge clk);#1;
  if({default_panel_on,default_panel_border,default_text_on,default_text_color,default_font_glyph,default_font_row,default_operator_digit_addr}!==
     {old_panel_on,old_panel_border,old_text_on,old_text_color,old_font_glyph,old_font_row,old_operator_digit_addr})$fatal(1,"default1 changed x%0d y%0d",x,y);
  default_checks++;
  is_paper_row=(x>=808&&x<1256&&y>=328&&y<344)&&dut.operator_show;
  if(is_paper_row)begin
   if(font_glyph!==8'h20||text_on!==0)$fatal(1,"paper remaining row not blank x%0d y%0d glyph%h",x,y,font_glyph);
   blank_pixels++;
  end else begin
   if({panel_on,panel_border,text_on,text_color,font_glyph,font_row,operator_digit_addr}!==
      {clean_panel_on,clean_panel_border,clean_text_on,clean_text_color,clean_font_glyph,clean_font_row,clean_operator_digit_addr})$fatal(1,"nonpaper output changed x%0d y%0d f%h state%0d",x,y,operator_data[3:0],operator_data[13:11]);
   preserved_checks++;
  end
  if(x>=800&&x<1264&&y>=224&&y<424&&operator_valid&&operator_data[3:0]==4)begin
   if(panel_on!==0||panel_border!==0||text_on!==0)$fatal(1,"full-only panel visible");hidden_full++;
  end
  if(dut.operator_show&&x>=808&&x<1256&&y>=232&&y<248)begin
   if(operator_data[3]||operator_data[13:11]==5)begin
    if(text_color!==24'hff6060)$fatal(1,"real recovery/error color removed %h",text_color);red_checks++;
   end else if(text_color!==24'hffe070)$fatal(1,"full bit turned normal text red %h",text_color);
  end
  checks++;
 end endtask
 initial begin
  repeat(5)@(posedge clk);@(negedge clk);rst_n=1;operator_valid=1;
  // All active flag/kind/state combinations, plus invalid metadata; every row sampled.
  for(v=0;v<2;v++)for(fx=0;fx<16;fx++)for(st=0;st<8;st++)for(k=1;k<=4;k++)begin
   operator_valid=v;operator_data=0;operator_data[3:0]=fx;operator_data[10:8]=k;operator_data[13:11]=st;
   operator_data[7]=1;operator_data[63:60]=(k==3)?5:1;operator_data[152:150]=(st==5)?4:0;operator_data[149:142]=(st==5)?6:0;operator_digit=7;
   for(iy=232;iy<424;iy+=24)for(ix=808;ix<1256;ix+=47)begin x=ix;y=iy;sample();end
  end
  // Entire former paper remaining line: no text pixels at any column/row.
  operator_valid=1;
  for(fx=1;fx<16;fx+=4)begin
   operator_data=0;operator_data[3:0]=fx;operator_data[7]=1;
   for(iy=328;iy<344;iy++)for(ix=808;ix<1256;ix++)begin x=ix;y=iy;sample();end
  end
  // Paper feed/eject and progress/error footer tokens remain equal except paper row.
  for(k=0;k<8;k++)begin
   operator_data=0;operator_data[1]=1;operator_data[7]=1;operator_data[152:150]=k;operator_data[63:60]=k;
   for(iy=352;iy<424;iy+=4)for(ix=808;ix<1256;ix+=4)begin x=ix;y=iy;sample();end
  end
  // Ordinary multi-object CNN summary / motion count / all PCB statuses.
  operator_data=0;operator_valid=1;
  for(st=0;st<8;st++)begin
   pcb_mode=st[0];pcb_status=st;
   for(iy=64;iy<224;iy+=11)for(ix=864;ix<1200;ix+=13)begin x=ix;y=iy;sample();end
   for(iy=584;iy<680;iy+=7)for(ix=24;ix<312;ix+=13)begin x=ix;y=iy;sample();end
  end
  if(blank_pixels==0||hidden_full==0||red_checks==0)$fatal(1,"missing coverage");
  $display("PAPER_STATUS_DISABLED_PASS checks=%0d default=%0d blank_pixels=%0d preserved=%0d full_hidden=%0d real_error_red=%0d",checks,default_checks,blank_pixels,preserved_checks,hidden_full,red_checks);$finish;
 end
 initial begin #1000000000;$fatal(1,"timeout");end
endmodule
"""
bench=OUT/'tb_paper_status.sv';bench.write_text(prefix+decl+tail,encoding='utf-8');bind(bench)
sources=[paired(REL/n) for n in ('osd_compact_panel.v','osd_compact_font_rom.v','operator_ui_text.v')]+[control,textcontrol,bench];paired(REL/'osd_compact_glyphs.vh');rows=[]
for step,cmd in [('vlib',['E:/model/win64/vlib.exe','rtl_lib']),('compile',['E:/model/win64/vlog.exe','-sv','-lint','-work','rtl_lib','+incdir+'+str(HDL),*map(str,sources)]),('simulation',['E:/model/win64/vsim.exe','-batch','-syncio','-quiet','-voptargs=+acc','-lib','rtl_lib','tb_paper_status','-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'])]:
 cp=subprocess.run(cmd,cwd=OUT,env=ENV,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',timeout=300)
 log=OUT/(step+'.log');log.write_text(cp.stdout,encoding='utf-8');rows.append(dict(exit_code=cp.returncode,log=str(log),sha256=sha(log)))
 assert cp.returncode==0 and not re.search(r'\*\* (?:Error|Fatal):',cp.stdout),cp.stdout[-6000:]
assert 'PAPER_STATUS_DISABLED_PASS' in cp.stdout,cp.stdout[-6000:]
assert all(sha(p)==h for p,h in INPUTS.items())
put(OUT/'RESULT.json',dict(status='PASS',test=dict(status='PASS',marker='PAPER_STATUS_DISABLED_PASS',steps=rows),changes=changes,inputs=INPUTS,source_manifest_sha256=sha(BUILD/'SOURCE_MANIFEST.json'),hardware_status='NOT_RUN',scope='Actual production parameter0 panel/font compared with separate real prior operator token decoder/panel/font. Default1 compatibility, full bit visibility/color removed, complete remaining line empty, all other fields/modes preserve behavior. Small video geometry and static pixels; physical HDMI NOT_RUN.'))
put(ROOT/'reports/PAPER_STATUS_VALIDATION_LATEST.json',dict(path=str(OUT/'RESULT.json'),sha256=sha(OUT/'RESULT.json')))
print(cp.stdout[-1000:]);print(OUT/'RESULT.json')
