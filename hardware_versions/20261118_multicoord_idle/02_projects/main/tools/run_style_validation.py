"""Focused key/CDC, pixel palette, stream equivalence and removed-style checks."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,re,os,subprocess
ROOT=Path(__file__).resolve().parents[1]
BUILD=Path('E:/codex_main_cnn_multicoord_20261118_r1')
BASE=ROOT.parent/'main_pcb_no_suspect_20261116'
HDLREL=Path('01_rtl/imgq_gain_m/main/user_source/hdl_source');HDL=ROOT/HDLREL
OUT=ROOT/'reports/style_validation'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
ENV=dict(os.environ,LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT',MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT')
INPUTS={}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def put(p,o):Path(p).write_text(json.dumps(o,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def bind(p):p=Path(p);INPUTS[str(p.resolve())]=sha(p);return p
def paired(rel):
 p=bind(ROOT/rel);assert sha(p)==sha(bind(BUILD/rel));return p
def sim(name,sources,marker):
 out=OUT/name;out.mkdir();rows=[]
 for step,cmd in [('vlib',['E:/model/win64/vlib.exe','rtl_lib']),('compile',['E:/model/win64/vlog.exe','-sv','-lint','-work','rtl_lib','+incdir+'+str(HDL),*map(str,sources)]),('simulation',['E:/model/win64/vsim.exe','-batch','-syncio','-quiet','-voptargs=+acc','-lib','rtl_lib',name,'-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'])]:
  cp=subprocess.run(cmd,cwd=out,env=ENV,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',timeout=300)
  log=out/(step+'.log');log.write_text(cp.stdout,encoding='utf-8');rows.append(dict(exit_code=cp.returncode,log=str(log),sha256=sha(log)))
  assert cp.returncode==0 and not re.search(r'\*\* (?:Error|Fatal):',cp.stdout),cp.stdout[-6000:]
 assert marker in cp.stdout,cp.stdout[-6000:]
 print(name+' PASS',flush=True);return dict(status='PASS',marker=marker,steps=rows)
OUT.mkdir(parents=True);bind(__file__)
for rel,row in json.loads((BUILD/'SOURCE_MANIFEST.json').read_text())['files'].items():assert sha(BUILD/rel)==row['sha256']
ref=bind(BASE/HDLREL/'isp/style_transfer_96.v').read_text(encoding='utf-8')
ref=ref.replace('module style_transfer_96 #(','module style_transfer_96_control #(',1)
ref=ref.replace("parameter [7:0] CART_QUANT_MASK = 8'hf0,", "parameter [7:0] CART_QUANT_MASK = 8'hf0,\n    parameter CART_FULL_RANGE_PALETTE=1'b0,")
ref=ref.replace('.QUANT_MASK(CART_QUANT_MASK)) u_cart(','.QUANT_MASK(CART_QUANT_MASK),.FULL_RANGE_PALETTE(CART_FULL_RANGE_PALETTE)) u_cart(')
ref=ref.replace("parameter CART_FULL_RANGE_PALETTE=1'b0,", "parameter CART_FULL_RANGE_PALETTE=1'b0,\n    parameter integer CART_PALETTE_BITS=3,")
ref=ref.replace('.FULL_RANGE_PALETTE(CART_FULL_RANGE_PALETTE)) u_cart(','.FULL_RANGE_PALETTE(CART_FULL_RANGE_PALETTE),.PALETTE_BITS(CART_PALETTE_BITS)) u_cart(')
reference=OUT/'style_transfer_control.v';reference.write_text(ref,encoding='utf-8');bind(reference)
tests={}
tests['controls']=sim('tb_style_revision_controls',[paired(HDLREL/'style_controls.v'),paired(HDLREL/'pcb_teach_key.v'),paired(Path('tests/style_revision/tb_style_revision_controls.sv'))],'STYLE_REVISION_CONTROLS_PASS')
tests['cartoon']=sim('tb_style_revision_cartoon',[paired(HDLREL/'isp/cartoon_96.v'),paired(Path('tests/style_revision/tb_style_revision_cartoon.sv'))],'STYLE_REVISION_CARTOON_PASS')
tests['flow']=sim('tb_style_revision_flow',[paired(HDLREL/'isp/cartoon_96.v'),paired(HDLREL/'isp/style_transfer_96.v'),reference,paired(Path('tests/style_revision/tb_style_revision_flow.sv'))],'STYLE_REVISION_FLOW_PASS')
assert all(sha(p)==v for p,v in INPUTS.items())
put(OUT/'RESULT.json',dict(status='PASS',tests=tests,inputs=INPUTS,source_manifest_sha256=sha(BUILD/'SOURCE_MANIFEST.json'),hardware_status='NOT_RUN'))
put(ROOT/'reports/STYLE_VALIDATION_LATEST.json',dict(path=str(OUT/'RESULT.json'),sha256=sha(OUT/'RESULT.json')))
print(str(OUT/'RESULT.json'))
