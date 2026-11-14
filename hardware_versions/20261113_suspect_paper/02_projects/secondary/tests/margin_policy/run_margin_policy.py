"""Compile current wrapper and verify asymmetric status publication boundaries."""
from pathlib import Path
import os,subprocess,json,hashlib,re
ROOT=Path(__file__).resolve().parents[2];OUT=ROOT/'reports/margin_policy';OUT.mkdir(parents=True,exist_ok=True)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
src=[ROOT/'01_rtl/pcb_ccl_binary_core.v',ROOT/'01_rtl/pcb_fullboard_spatial96.v',Path(__file__).with_name('tb_margin_policy.sv')]
env=dict(os.environ,LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT',MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT');commands=[]
for name,argv in [('vlib',['E:/model/win64/vlib.exe','rtl_lib']),('compile',['E:/model/win64/vlog.exe','-sv','-lint','-work','rtl_lib',*map(str,src)]),('simulation',['E:/model/win64/vsim.exe','-batch','-syncio','-quiet','-voptargs=+acc','-lib','rtl_lib','tb_margin_policy','-do','onerror {quit -code 1}; onbreak {quit -code 2}; run -all; quit -f'])]:
 with (OUT/(name+'.log')).open('w',encoding='utf-8') as f:p=subprocess.run(argv,cwd=OUT,env=env,stdout=f,stderr=subprocess.STDOUT,timeout=180)
 text=(OUT/(name+'.log')).read_text(encoding='utf-8-sig',errors='replace');passed=p.returncode==0 and not re.search(r'\*\*\s+(?:Error|Fatal):',text)
 if name=='simulation':passed=passed and 'MARGIN_POLICY_GOLDEN_PASS tests=7' in text
 commands.append({'name':name,'argv':argv,'returncode':p.returncode,'passed':passed});assert passed,text[-3000:]
result={'status':'PASS','tests':7,'scope':'Wrapper publication boundaries only; no CNN arithmetic changed','source_hashes':{str(p):sha(p) for p in src},'commands':commands,'hardware':'NOT_RUN','policy':'GOOD PASS margin>=192;BAD FAIL margin>=32;otherwise REVIEW reason3'}
(OUT/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8');print(json.dumps(result,indent=2))
