"""Simulate actual panel/font with the exact mode-gated production top expression."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,re,os,subprocess
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent/'main_style_vivid_cnn_panel_hidden_20261117'
BUILD=Path('E:/codex_main_cnn_multicoord_20261118_r1')
REL=Path('01_rtl/imgq_gain_m/main/user_source/hdl_source');HDL=ROOT/REL
OUT=ROOT/'reports/cnn_panel_validation'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
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
assert changes==[(REL/n).as_posix() for n in ('doc_copy_overlay.v','hdmi_mixer.v','isp/cartoon_96.v','isp/isp_top_basic_core.v','isp/style_transfer_96.v','operator_ui_text.v','osd_compact_panel.v')],changes
top=paired(REL/'design_top_wrapper.v');s=top.read_text(encoding='utf-8')
assert s.count("wire S_mode_cnn_px=(S_mode_sel_px==2'd0);")==1
expr=re.findall(r'\.I_operator_valid\(([^)]*)\)',s);assert expr==['S_operator_valid_px && !S_mode_cnn_px'],expr
old=(BASE/REL/'design_top_wrapper.v').read_text(encoding='utf-8')
assert s==old,'Unexpected top change'
benchbase=paired(Path('tests/dynamic_osd/tb_dynamic_status.sv')).read_text(encoding='utf-8')
prefix=benchbase[:benchbase.index('  task sample_panel;')].replace('module tb_dynamic_status;','module tb_cnn_panel_hidden;')
prefix=prefix.replace('  osd_compact_panel dut(',"  reg [1:0] S_mode_sel_px=0;\n  wire S_mode_cnn_px=(S_mode_sel_px==2'd0);\n  wire S_operator_valid_px=operator_valid;\n  osd_compact_panel dut(")
prefix=prefix.replace('.operator_valid(operator_valid)','.operator_valid('+expr[0]+')')
instance=prefix[prefix.index('  osd_compact_panel dut('):prefix.index('  osd_compact_font_rom font(')]
instance=instance.replace('osd_compact_panel dut(','osd_compact_panel reference(').replace('.operator_valid('+expr[0]+')','.operator_valid(operator_valid)')
for n in ('operator_digit_addr','panel_on','panel_border','text_on','text_color','font_glyph','font_row'):
 instance=instance.replace('.'+n+'('+n+')','.'+n+'(base_'+n+')')
instance=instance.replace('.font_row_bits(font_row_bits)','.font_row_bits(base_bits)')
decl="""
  wire [5:0] base_operator_digit_addr;
  wire base_panel_on,base_panel_border,base_text_on;
  wire [23:0] base_text_color;wire [7:0] base_font_glyph;
  wire [3:0] base_font_row;wire [15:0] base_bits;
  osd_compact_font_rom base_font(.clk(clk),.glyph(base_font_glyph),.row(base_font_row),.row_bits(base_bits));
"""
tail=r"""
  integer checks=0,hidden=0,preserved=0,m,v,f,ix,iy,k;
  task sample;
   begin
    repeat(5)@(posedge clk);#1;
    if(S_mode_cnn_px&&x>=800&&x<1264&&y>=224&&y<424)begin
      if(panel_on!==0||panel_border!==0||text_on!==0)$fatal(1,"CNN writing panel visible flags=%h x%0d y%0d",operator_data[3:0],x,y);
      if(operator_valid&&operator_data[3:0]!=0&&base_panel_on!==1)$fatal(1,"control panel did not exercise expected visibility");
      hidden++;
    end else begin
      if({panel_on,panel_border,text_on,text_color,font_glyph,font_row,operator_digit_addr}!==
         {base_panel_on,base_panel_border,base_text_on,base_text_color,base_font_glyph,base_font_row,base_operator_digit_addr})
        $fatal(1,"unrelated panel pixel changed mode%0d x%0d y%0d",S_mode_sel_px,x,y);
      preserved++;
    end
    checks++;
   end
  endtask
  initial begin
   repeat(5)@(posedge clk);@(negedge clk);rst_n=1;
   for(m=0;m<4;m++)for(v=0;v<2;v++)for(f=0;f<16;f++)begin
    S_mode_sel_px=m;pcb_mode=(m==1);operator_valid=v;operator_data=0;
    operator_data[3:0]=f;operator_data[10:8]=m+1;operator_data[13:11]=5;
    for(iy=224;iy<424;iy+=17)for(ix=800;ix<1264;ix+=23)begin x=ix;y=iy;sample();end
    // Ordinary CNN summary and the lower-left PCB result remain byte/pixel equal.
    for(iy=64;iy<224;iy+=17)for(ix=864;ix<1200;ix+=23)begin x=ix;y=iy;sample();end
    for(iy=584;iy<680;iy+=13)for(ix=24;ix<312;ix+=23)begin x=ix;y=iy;sample();end
   end
   // Changing view mode must not erase Type21 data or require a new packet.
   operator_valid=1;operator_data[3:0]=8;pcb_mode=0;x=800;y=224;
   S_mode_sel_px=2;sample();S_mode_sel_px=0;sample();S_mode_sel_px=1;pcb_mode=1;sample();
   S_mode_sel_px=0;pcb_mode=0;sample();S_mode_sel_px=2;sample();
   if(hidden==0||preserved==0)$fatal(1,"missing coverage");
   $display("CNN_PANEL_HIDDEN_PASS checks=%0d hidden=%0d preserved=%0d all_flags_all_modes_transition",checks,hidden,preserved);$finish;
  end
  initial begin #100000000;$fatal(1,"timeout");end
endmodule
"""
bench=OUT/'tb_cnn_panel_hidden.sv';bench.write_text(prefix+decl+instance+tail,encoding='utf-8');bind(bench)
sources=[paired(REL/n) for n in ('osd_compact_panel.v','osd_compact_font_rom.v','operator_ui_text.v')]+[top,bench]
paired(REL/'osd_compact_glyphs.vh');rows=[]
for step,cmd in [('vlib',['E:/model/win64/vlib.exe','rtl_lib']),('compile',['E:/model/win64/vlog.exe','-sv','-lint','-work','rtl_lib','+incdir+'+str(HDL),*map(str,sources)]),('simulation',['E:/model/win64/vsim.exe','-batch','-syncio','-quiet','-voptargs=+acc','-lib','rtl_lib','tb_cnn_panel_hidden','-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'])]:
 cp=subprocess.run(cmd,cwd=OUT,env=ENV,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',timeout=300)
 log=OUT/(step+'.log');log.write_text(cp.stdout,encoding='utf-8');rows.append(dict(exit_code=cp.returncode,log=str(log),sha256=sha(log)))
 assert cp.returncode==0 and not re.search(r'\*\* (?:Error|Fatal):',cp.stdout),cp.stdout[-6000:]
assert 'CNN_PANEL_HIDDEN_PASS' in cp.stdout,cp.stdout[-4000:]
assert all(sha(p)==h for p,h in INPUTS.items())
put(OUT/'RESULT.json',dict(status='PASS',test=dict(status='PASS',steps=rows),changes=changes,inputs=INPUTS,source_manifest_sha256=sha(BUILD/'SOURCE_MANIFEST.json'),hardware_status='NOT_RUN',scope='Exact top mode-gate expression driving actual panel/font miter: all four app modes, valid/invalid metadata, all pending/busy/full/recovery flags; CNN hidden and ordinary summary plus PCB/doc panel pixels preserved. Full top syntax compiled; not whole-board simulation.'))
put(ROOT/'reports/CNN_PANEL_VALIDATION_LATEST.json',dict(path=str(OUT/'RESULT.json'),sha256=sha(OUT/'RESULT.json')))
print(cp.stdout[-1200:]);print(OUT/'RESULT.json')
