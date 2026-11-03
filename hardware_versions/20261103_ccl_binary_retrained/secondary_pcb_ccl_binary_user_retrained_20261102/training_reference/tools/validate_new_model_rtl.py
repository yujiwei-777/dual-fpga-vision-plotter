"""Independent new-model core RTL regression; no synthesis or old-model writes."""
from collections import defaultdict
from datetime import datetime, timezone
import argparse, hashlib, importlib.util, json, os, re, subprocess, sys
from pathlib import Path
sys.dont_write_bytecode = True
import numpy as np
ROOT=Path(__file__).resolve().parents[1];BASE=ROOT.parent
DESIGN=BASE/'secondary_pcb_ccl_binary_roi120_20261102'
OUT=ROOT/'reports/rtl_core';MODEL=ROOT/'model/selected'
REFERENCE=DESIGN/'tools/binary_validation_reference.py'
TEMPLATE=BASE/'secondary_pcb_centered_new_capture_mix_20261029_hw/02_sim/new_capture_mix_regression_r5_20261029/tb_real_pcb_core.sv'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def save(p,v):Path(p).write_text(json.dumps(v,indent=2,ensure_ascii=False,allow_nan=False)+'\n',encoding='utf-8')
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--run',action='store_true');args=parser.parse_args()
    model=read(MODEL/'MODEL.json')
    assert model['crop_scale']==1 and model['shifts']==[7,7,8]
    assert model['weight_count']==308 and model['bias_count']==10
    assert all(sha(MODEL/n)==h for n,h in model['hashes'].items())
    w=np.array([int(t,16) for t in (MODEL/'weights.mem').read_text().split()],np.uint8).view(np.int8)
    b=np.array([int(t,16) for t in (MODEL/'biases.mem').read_text().split()],np.uint32).view(np.int32)
    assert(len(w),len(b))==(308,10)
    m={'w1':w[:36].reshape(4,1,3,3),'w2':w[36:180].reshape(4,4,3,3),'w3':w[180:].reshape(2,64),'b1':b[:4],'b2':b[4:8],'b3':b[8:]}
    spec=importlib.util.spec_from_file_location('independent_rtl_integer_reference',REFERENCE);ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref)
    manifest=read(ROOT/'data/MANIFEST.json')['frames']
    with np.load(ROOT/'data/DATASET.npz',allow_pickle=False) as data:images=data['images'].copy();indices=data['manifest_index'].copy()
    groups=defaultdict(list)
    for dataset_index,manifest_index in enumerate(indices):
        row=manifest[int(manifest_index)]
        assert row['dataset_index']==dataset_index and row['gate']=='VALID'
        assert row['roi_sha256']==hashlib.sha256(images[dataset_index].tobytes()).hexdigest().upper()
        groups[(row['domain'],row['group'])].append((dataset_index,row))
    assert len(groups)==5
    selected=[]
    for group in sorted(groups):
        rows=sorted(groups[group],key=lambda item:(item[1]['frame_id'],item[1]['source_json']))
        for i in(0,len(rows)//2,len(rows)-1):
            dataset_index,row=rows[i]
            selected.append({'name':f'real_{len(selected):02d}','selection_group':list(group),'selection_rule':'valid original-box candidates first/middle/last sorted frame_id/path','selection_index':i,'selection_group_size':len(rows),'dataset_index':dataset_index,'source':row})
    run=OUT/('run_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'));fixtures=run/'fixtures';fixtures.mkdir(parents=True,exist_ok=False)
    save(run/'SELECTION_BEFORE_INFERENCE.json',selected);records=[];features=[]
    for record in selected:
        result,arrays=ref.infer(images[record['dataset_index']],m);assert result['activation_saturations']==0
        records.append({**record,'core_case':len(records),**result});features.append(arrays)
    for name,value in[('black',0),('gray128',128),('white',255)]:
        result,arrays=ref.infer(np.full((96,96),value,np.uint8),m);assert result['activation_saturations']==0
        records.append({'name':'synthetic_'+name,'core_case':len(records),**result});features.append(arrays)
    assert len(records)==18
    names={'roi':'input_pixels','conv1':'expected_f1','conv2':'expected_f2','pool':'expected_pool','logits':'expected_logits'}
    for name,bits in[('roi',8),('conv1',16),('conv2',16),('pool',16),('logits',32)]:
        array=np.stack([f[name] for f in features]);array=array.transpose(0,2,3,1) if name in('conv1','conv2') else array
        ref.mem(fixtures/(names[name]+'.mem'),array,bits)
    save(fixtures/'INDEX.json',{'core_cases':18,'real_cases':15,'synthetic_cases':3,'cases':records,'model_hashes':model['hashes'],'reference':'int64 conv/infer called with explicit new model arrays; old freeze loader not called'})
    bench=TEMPLATE.read_text().replace('SAMPLE_COUNT=15','SAMPLE_COUNT=18').replace('vision_workspace workspace(','vision_workspace_goodonly workspace(')
    bench=bench.replace('assign mac_product_ext=mac_a*mac_w;',"vision_shared_mac mac(.pcb_select(1'b1),.cnn_a(16'sd0),.cnn_w(8'sd0),.pcb_a(mac_a),.pcb_w(mac_w),.product(),.cnn_product(),.pcb_product(mac_product_ext));")
    bench=bench.replace('../../model/experiments/conv4_4/',MODEL.as_posix()+'/').replace('rtl_vectors/',fixtures.as_posix()+'/')
    bench=bench.replace('repeat(4) @(negedge clk); rst_n=1;', '''$display("NEW_MODEL_CORE_PARAMETERS C1=%0d C2=%0d HEAD_CLASSES=%0d C1_SHIFT=%0d C2_SHIFT=%0d HEAD_SHIFT=%0d WEIGHT_COUNT=%0d BIAS_COUNT=%0d EXTERNAL_MAC=%0d SHARED_WORKSPACE=%0d",dut.C1_CHANNELS,dut.C2_CHANNELS,dut.HEAD_CLASSES,dut.C1_SHIFT,dut.C2_SHIFT,dut.HEAD_SHIFT,dut.WEIGHT_COUNT,dut.BIAS_COUNT,dut.EXTERNAL_MAC,dut.USE_SHARED_WORKSPACE);
    $display("NEW_MODEL_ROM weights=%s biases=%s",dut.WEIGHTS_MEM,dut.BIASES_MEM);
    if(dut.C1_CHANNELS!=4 || dut.C2_CHANNELS!=4 || dut.HEAD_CLASSES!=2 || dut.C1_SHIFT!=7 || dut.C2_SHIFT!=7 || dut.HEAD_SHIFT!=8 || dut.WEIGHT_COUNT!=308 || dut.BIAS_COUNT!=10 || dut.EXTERNAL_MAC!=1 || dut.USE_SHARED_WORKSPACE!=1) $fatal(1,"wrong model/core contract");
    if($size(workspace.bank0)<9216 || $size(workspace.bank1)<4608) $fatal(1,"workspace too small");
    repeat(4) @(negedge clk); rst_n=1;''')
    assert not re.search(r'\b(force|release)\b',bench,re.I),'force/release prohibited'
    assert MODEL.as_posix()+'/weights.mem' in bench and '../../model/' not in bench and 'rtl_vectors/' not in bench
    assert len(re.findall(r'\$fatal',bench))>=10
    (run/'tb_real_pcb_core.sv').write_text(bench,encoding='ascii')
    sources=[DESIGN/'01_rtl/vision_workspace_goodonly.v',DESIGN/'01_rtl/vision_shared_mac.v',DESIGN/'01_rtl/pcb_fullboard_spatial96.v',run/'tb_real_pcb_core.sv']
    (run/'run.do').write_text('\n'.join(['onerror {quit -code 2}','onbreak {quit -code 3}','vlib work','vlog -sv '+' '.join('"'+p.as_posix()+'"' for p in sources),'vsim -voptargs=+acc work.tb_real_pcb_core','run -all','quit -code 0','']),encoding='ascii')
    pins={str(p.resolve()):sha(p) for p in sources+[Path(__file__),TEMPLATE,REFERENCE,MODEL/'MODEL.json',MODEL/'weights.mem',MODEL/'biases.mem',ROOT/'data/DATASET.npz',ROOT/'data/MANIFEST.json']+list(fixtures.iterdir())}
    save(run/'SOURCE_SHA256.json',pins)
    result={'status':'PREPARED','RTL':'NOT_RUN','hardware':'NOT_RUN','run_directory':str(run),'real_cases':15,'synthetic_cases':3,'core_contract':'C4/C4/FC64->2, shifts7/7/8, unsigned Y8, workspace16, PCB MAC16x8','new_model_hashes':model['hashes'],'checks':['all Conv1 9216 values/case','all Conv2 2304 values/case','pool64 values checked for each of two heads/case','both logits','class','score','margin','saturation count zero','runtime parameters and workspace capacity','source/fixture/model hashes unchanged'],'numerical_force':False,'limitations':['core only; no CCL/crop/transport/fullboard regression','diagnostic first/middle/last samples, not accuracy estimate','no synthesis, place/route or hardware execution']}
    save(run/'RESULTS.json',result);print(json.dumps(result,indent=2),flush=True)
    if args.run:
        env=dict(os.environ);env['MGLS_LICENSE_FILE']=env['LM_LICENSE_FILE']='E:/model/win64/LICENSE.TXT'
        with(run/'SIM.log').open('w',encoding='utf-8') as log:proc=subprocess.run(['E:/model/win64/vsim.exe','-batch','-syncio','-do','run.do'],cwd=run,env=env,stdout=log,stderr=subprocess.STDOUT)
        log=(run/'SIM.log').read_text(encoding='utf-8',errors='replace');marker='BINARY_C4_4_GOLDEN_PASS samples=18 sat=0'
        unchanged=all(sha(Path(path))==digest for path,digest in pins.items());sample_lines=[line.strip() for line in log.splitlines() if 'BINARY_C4_4_SAMPLE_PASS' in line]
        ok=proc.returncode==0 and marker in log and len(sample_lines)==18 and unchanged and not re.search(r'\*\*\s+(Error|Fatal):',log)
        result.update(status='PASS' if ok else 'FAIL',RTL='PASS' if ok else 'FAIL',returncode=proc.returncode,source_model_fixture_unchanged=unchanged,samples_passed=len(sample_lines),sample_lines=sample_lines,final_marker=marker,log_sha256=sha(run/'SIM.log'))
        save(run/'RESULTS.json',result);save(OUT/'LATEST.json',{'run_directory':str(run),'status':result['status'],'results_sha256':sha(run/'RESULTS.json'),'hardware':'NOT_RUN'});print(json.dumps(result,indent=2),flush=True)
    return 1 if result['status']=='FAIL' else 0
if __name__=='__main__':raise SystemExit(main())
