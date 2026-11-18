"""Actual panel/font comparison plus retained control and region regressions."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, os, re, subprocess, sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'main_pcb_no_suspect_20261116'
BUILD=Path('E:/codex_main_cnn_multicoord_20261118_r1')
HDL_REL=Path('01_rtl/imgq_gain_m/main/user_source/hdl_source')
SHARED_REL=Path('01_rtl/imgq_gain_m/shared/rtl')
HDL=ROOT/HDL_REL
SIM=Path('E:/model/win64')
ENV=dict(os.environ,LM_LICENSE_FILE=str(SIM/'LICENSE.TXT'),MGLS_LICENSE_FILE=str(SIM/'LICENSE.TXT'))
OUT=ROOT/'reports/validation'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
INPUTS={}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def put(p,o):p.write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def bind(p):INPUTS[str(p.resolve())]=sha(p);return p
def paired(rel):
    p=bind(ROOT/rel);assert sha(p)==sha(bind(BUILD/rel)),str(rel)
    return p
def simulate(name,sources,marker,inc=HDL):
    out=OUT/name;out.mkdir()
    rows=[]
    for step,cmd in [('vlib',[SIM/'vlib.exe','rtl_lib']),
        ('compile',[SIM/'vlog.exe','-sv','-lint','-work','rtl_lib','+incdir+'+str(inc),*sources]),
        ('simulation',[SIM/'vsim.exe','-batch','-syncio','-quiet','-voptargs=+acc','-lib','rtl_lib',name,
            '-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'])]:
        cp=subprocess.run(list(map(str,cmd)),cwd=out,env=ENV,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
            text=True,encoding='utf-8',errors='replace',timeout=300)
        log=out/(step+'.log');log.write_text(cp.stdout,encoding='utf-8')
        rows.append({'phase':step,'exit_code':cp.returncode,'log':str(log),'sha256':sha(log)})
        assert cp.returncode==0 and not re.search(r'\*\* (?:Error|Fatal):',cp.stdout),cp.stdout[-5000:]
    assert marker in cp.stdout,cp.stdout[-4000:]
    print(name+' PASS',flush=True)
    return {'status':'PASS','marker':marker,'steps':rows}

OUT.mkdir(parents=True)
bind(Path(__file__))
manifest=json.loads((BUILD/'SOURCE_MANIFEST.json').read_text(encoding='utf-8'))
for rel,row in manifest['files'].items():assert sha(BUILD/rel)==row['sha256'],rel
changes=[]
for d in ('01_rtl','04_pin'):
    for p in sorted((ROOT/d).rglob('*')):
        if p.is_file() and p.name!='source_snapshot.json' and p.suffix not in ('.al','.prj'):
            bind(p);q=bind(BASE/p.relative_to(ROOT))
            if sha(p)!=sha(q):changes.append(p.relative_to(ROOT).as_posix())
assert changes==[(HDL_REL/n).as_posix() for n in ('design_top_wrapper.v','doc_copy_overlay.v','hdmi_mixer.v','hxa_multibox_overlay.v','isp/cartoon_96.v','isp/isp_top_basic_core.v','isp/style_transfer_96.v','operator_ui_text.v','osd_compact_panel.v','osd_operator_decimal_snapshot.v','result_overlay.v','style_controls.v')],changes
panel=paired(HDL_REL/'osd_compact_panel.v')
font=paired(HDL_REL/'osd_compact_font_rom.v')
operator=paired(HDL_REL/'operator_ui_text.v')
paired(HDL_REL/'osd_compact_glyphs.vh')
old=(BASE/HDL_REL/'osd_compact_panel.v').read_text(encoding='utf-8')
old=old.replace('module osd_compact_panel(','module osd_compact_panel_control(',1)
old=old.replace('module merged_panel_tokens(','module merged_panel_tokens_control(',1)
old=old.replace('merged_panel_tokens u_shared_tokens','merged_panel_tokens_control u_shared_tokens',1)
control=OUT/'panel_control.v';control.write_text(old,encoding='utf-8')
basebench=(ROOT/'tests/dynamic_osd/tb_dynamic_status.sv').read_text(encoding='utf-8')
prefix=basebench[:basebench.index('  task sample_panel;')].replace('module tb_dynamic_status;','module tb_no_suspect_text;')
inst=prefix[prefix.index('  osd_compact_panel dut('):prefix.index('  osd_compact_font_rom font(')]
inst=inst.replace('osd_compact_panel dut(','osd_compact_panel_control reference(')
inst=inst.replace('.pcb_suspect(pcb_suspect)',".pcb_suspect(1'b0)")
for n in ('operator_digit_addr','panel_on','panel_border','text_on','text_color','font_glyph','font_row'):
    inst=inst.replace(f'.{n}({n})',f'.{n}(base_{n})')
inst=inst.replace('.font_row_bits(font_row_bits)','.font_row_bits(base_bits)')
decl='''
  wire [5:0] base_operator_digit_addr;
  wire base_panel_on,base_panel_border,base_text_on;
  wire [23:0] base_text_color;wire [7:0] base_font_glyph;
  wire [3:0] base_font_row;wire [15:0] base_bits;
  osd_compact_font_rom base_font(.clk(clk),.glyph(base_font_glyph),.row(base_font_row),.row_bits(base_bits));
'''
tail=r'''
  integer checks=0,prefix_checks=0,s,ix,iy,k,c,st,f;
  reg remove_prefix;
  task sample_compare;
    begin
      repeat(5) @(posedge clk);#1;
      remove_prefix=operator_valid&&(operator_data[0]||operator_data[1])&&operator_data[10:8]==2&&
          x>=808&&x<1256&&y>=280&&y<296;
      if({panel_on,panel_border,text_color,font_row}!==
         {base_panel_on,base_panel_border,base_text_color,base_font_row})
        $fatal(1,"layout/color/decimal routing changed x%0d y%0d",x,y);
      if(remove_prefix)begin
        if(font_glyph!==8'h20||text_on!==0)$fatal(1,"PCB suspected-coordinate row still visible");
        prefix_checks++;
      end else if({font_glyph,text_on}!=={base_font_glyph,base_text_on})
        $fatal(1,"unrelated glyph/pixel changed x%0d y%0d got%h expected%h",x,y,font_glyph,base_font_glyph);
      if(!remove_prefix&&operator_digit_addr!==base_operator_digit_addr)$fatal(1,"numeric address changed");
      checks++;
    end
  endtask
  initial begin
    repeat(4)@(posedge clk);@(negedge clk);rst_n=1;
    pcb_mode=1;pcb_suspect=1;operator_valid=0;
    for(s=0;s<8;s++)begin
      pcb_status=s;
      for(iy=584;iy<680;iy++)for(ix=24;ix<312;ix++)begin x=ix;y=iy;sample_compare();end
    end
    operator_valid=1;operator_data=0;operator_data[0]=1;operator_data[4]=1;
    operator_data[7]=1;operator_digit=4'd7;
    for(k=1;k<=4;k++)for(st=0;st<8;st++)begin
      operator_data[10:8]=k;operator_data[13:11]=st;
      for(iy=280;iy<296;iy++)for(ix=808;ix<1256;ix++)begin x=ix;y=iy;sample_compare();end
    end
    // Other operator rows, busy/page-full/recovery, invalid input and idle.
    for(f=0;f<5;f++)begin
      operator_data[3:0]=(f==4)?0:(1<<f);operator_data[10:8]=2;
      for(iy=224;iy<424;iy+=4)for(ix=800;ix<1264;ix+=4)begin x=ix;y=iy;sample_compare();end
    end
    operator_valid=0;
    for(iy=64;iy<224;iy+=4)for(ix=864;ix<1200;ix+=4)begin x=ix;y=iy;pcb_mode=0;sample_compare();end
    if(prefix_checks==0)$fatal(1,"prefix checks missing");
    $display("NO_SUSPECT_TEXT_PASS checks=%0d prefix_checks=%0d",checks,prefix_checks);$finish;
  end
  initial begin #1000000000;$fatal(1,"timeout");end
endmodule
'''
bench=OUT/'tb_no_suspect_text.sv';bench.write_text(prefix+decl+inst+tail,encoding='utf-8')
tests={}
tests['text']=simulate('tb_no_suspect_text',[panel,font,operator,control,bench],'NO_SUSPECT_TEXT_PASS')
tests['dynamic']=simulate('tb_dynamic_status',[panel,font,operator,paired(Path('tests/dynamic_osd/tb_dynamic_status.sv'))],
    'DYNAMIC_OSD_PASS pending_writing_fault_visible idle_hidden')
tests['protocol']=simulate('tb_type21_maintenance',[paired(SHARED_REL/'hxa_packet_codec.v'),paired(SHARED_REL/'hxa_main_link.v'),
    paired(Path('tests/dynamic_osd/tb_type21_maintenance.sv'))],'TYPE21_MAINTENANCE_PASS')
assert all(sha(Path(p))==h for p,h in INPUTS.items()),'Input drift'
protected=json.loads((ROOT/'baseline_reference/PROTECTED_INPUTS.json').read_text(encoding='utf-8'))
assert all(sha(Path(p))==h for p,h in protected.items()),'Baseline drift'
put(OUT/'RESULT.json',{'status':'PASS','tests':tests,'changes':changes,'inputs':INPUTS,
    'source_manifest_sha256':sha(BUILD/'SOURCE_MANIFEST.json'),'baseline_unchanged':True,'hardware_status':'NOT_RUN',
    'scope':'Actual panel/font pixel and glyph comparison: eight PCB statuses without SUSPECT; entire PCB coordinate row blank; ordinary CNN numeric rows preserved; dynamic visibility and Type21 controls. Region suppression tested separately.'})
put(ROOT/'reports/VALIDATION_LATEST.json',{'path':str(OUT/'RESULT.json'),'sha256':sha(OUT/'RESULT.json')})
print(str(OUT/'RESULT.json'),flush=True)
