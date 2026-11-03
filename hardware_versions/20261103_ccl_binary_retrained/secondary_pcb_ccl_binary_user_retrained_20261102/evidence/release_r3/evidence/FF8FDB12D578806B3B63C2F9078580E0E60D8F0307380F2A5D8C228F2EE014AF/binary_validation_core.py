"""Prepare/run new-model-independent integer vs RTL core verification.
Default prepares only. --run requires caller coordination of ModelSim.
"""
from datetime import datetime,timezone
from pathlib import Path
import argparse,json,os,re,subprocess,sys
sys.dont_write_bytecode=True
import binary_validation_reference as ref
ROOT=ref.ROOT;OUT=ref.OUT
TEMPLATE=ROOT.parent/'secondary_pcb_centered_new_capture_mix_20261029_hw/02_sim/new_capture_mix_regression_r5_20261029/tb_real_pcb_core.sv'
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--run',action='store_true');p.add_argument('--design',type=Path,default=ROOT);args=p.parse_args()
    design=args.design.resolve();index=ref.read(OUT/'fixtures/INDEX.json');n=index['core_cases']
    run=OUT/'core'/('run_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'));run.mkdir(parents=True,exist_ok=False)
    bench=TEMPLATE.read_text().replace('SAMPLE_COUNT=15','SAMPLE_COUNT='+str(n))
    bench=bench.replace('vision_workspace workspace(', 'vision_workspace_goodonly workspace(')
    bench=bench.replace('assign mac_product_ext=mac_a*mac_w;', 'vision_shared_mac mac(.pcb_select(1\'b1),.cnn_a(16\'sd0),.cnn_w(8\'sd0),.pcb_a(mac_a),.pcb_w(mac_w),.product(),.cnn_product(),.pcb_product(mac_product_ext));')
    bench=bench.replace('../../model/experiments/conv4_4/',(design/'model/experiments/conv4_4').as_posix()+'/')
    bench=bench.replace('rtl_vectors/',(OUT/'fixtures').as_posix()+'/')
    (run/'tb_real_pcb_core.sv').write_text(bench,encoding='ascii')
    sources=[design/'01_rtl/vision_workspace_goodonly.v',design/'01_rtl/vision_shared_mac.v',design/'01_rtl/pcb_fullboard_spatial96.v',run/'tb_real_pcb_core.sv']
    (run/'run.do').write_text('\n'.join(['onerror {quit -code 2}','onbreak {quit -code 3}','vlib work','vlog -sv '+' '.join('"'+x.as_posix()+'"' for x in sources),'vsim -voptargs=+acc work.tb_real_pcb_core','run -all','quit -code 0','']),encoding='ascii')
    pins={str(p):ref.sha(p) for p in sources+[Path(__file__),TEMPLATE,OUT/'fixtures/SHA256.json']+list((design/'model/experiments/conv4_4').glob('*.mem'))}
    ref.save(run/'SOURCE_SHA256.json',pins)
    result={'status':'PREPARED','cases':n,'design':str(design),'run_directory':str(run),'RTL':'NOT_RUN','hardware':'NOT_RUN','source_hashes':pins}
    if args.run:
        env=dict(os.environ);env['MGLS_LICENSE_FILE']=env['LM_LICENSE_FILE']='E:/model/win64/LICENSE.TXT'
        with(run/'SIM.log').open('w',encoding='utf-8') as log:proc=subprocess.run(['E:/model/win64/vsim.exe','-batch','-syncio','-do','run.do'],cwd=run,env=env,stdout=log,stderr=subprocess.STDOUT)
        log=(run/'SIM.log').read_text(encoding='utf-8',errors='replace');marker=f'BINARY_C4_4_GOLDEN_PASS samples={n} sat=0'
        unchanged=all(ref.sha(Path(p))==h for p,h in pins.items());ok=proc.returncode==0 and marker in log and not re.search(r'\*\*\s+(Error|Fatal):',log) and unchanged
        result.update(status='PASS' if ok else 'FAIL',RTL='PASS' if ok else 'FAIL',returncode=proc.returncode,source_unchanged=unchanged,samples_passed=log.count('BINARY_C4_4_SAMPLE_PASS'),marker=marker,log_sha256=ref.sha(run/'SIM.log'))
    ref.save(run/'RESULTS.json',result);print(json.dumps({k:v for k,v in result.items() if k!='source_hashes'},indent=2))
    return 1 if result['status']=='FAIL' else 0
if __name__=='__main__':raise SystemExit(main())
