"""Read-only selected-model arithmetic/serialization audit and fresh RTL vectors."""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,importlib.util,json,sys
import numpy as np
import torch
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2];OUT=Path(__file__).parent
BASE=ROOT.parent/'secondary_pcb_ccl_binary_roi120_20261102'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def save(p,x):Path(p).write_text(json.dumps(x,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
def module(name,p):
    spec=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
def mem(p,a,bits):Path(p).write_text(''.join(f'{int(x)&((1<<bits)-1):0{bits//4}x}\n'for x in np.asarray(a).ravel()),encoding='ascii')
def main():
    torch.set_num_threads(2);torch.backends.mkldnn.enabled=False
    train=module('audit_training',ROOT/'train_ccl_binary.py');vr=module('audit_integer',BASE/'tools/binary_validation_reference.py');sw=module('audit_batch',BASE/'tools/binary_scale_sweep.py')
    freeze=read(ROOT/'reports/SELECTION_BEFORE_TEST.json');model=ROOT/'model/selected';checkpoint=ROOT/'candidates'/('seed_'+str(freeze['seed']))/'CHECKPOINT.pt'
    assert all(sha(model/name)==h for name,h in freeze['hashes'].items())
    net=train.HardwareNet().double();net.load_state_dict(torch.load(checkpoint,map_location='cpu',weights_only=True));net.eval();net.qat=True
    w=np.array([int(x,16)for x in(model/'weights.mem').read_text().split()],np.uint8).view(np.int8)
    b=np.array([int(x,16)for x in(model/'biases.mem').read_text().split()],np.uint32).view(np.int32)
    assert len(w)==308 and len(b)==10
    q={'w1':w[:36].reshape(4,1,3,3),'w2':w[36:180].reshape(4,4,3,3),'w3':w[180:].reshape(2,64),'b1':b[:4],'b2':b[4:8],'b3':b[8:]}
    from_ckpt=train.arrays(net);stored=np.load(model/'QUANTIZED.npz')
    for k in q:assert np.array_equal(q[k],from_ckpt[k])and np.array_equal(q[k],stored[k]),k
    # Independent absolute-value prefix bound, conservative for every legal Y8.
    a1=np.abs(q['b1'].astype(np.int64))+np.abs(q['w1'].astype(np.int64)).sum((1,2,3))*255;f1max=np.minimum(a1>>7,32767)
    a2=np.abs(q['b2'].astype(np.int64))+(np.abs(q['w2'].astype(np.int64))*f1max[None,:,None,None]).sum((1,2,3));f2max=np.minimum(a2>>7,32767)
    pooled=(f2max*36)>>5;head=np.abs(q['b3'].astype(np.int64))+(np.abs(q['w3'].astype(np.int64))*np.repeat(pooled,16)[None,:]).sum(1)
    assert max(a1.max(),a2.max(),head.max())<2**26 and pooled.max()<32768 and(head>>8).max()<2**19
    bounds={'status':'PASS_ALL_UNSIGNED_Y8_PREFIX_BOUNDS','conv1_abs_prefix':a1.tolist(),'conv2_abs_prefix':a2.tolist(),'pool_operand_abs_bound':pooled.tolist(),'head_abs_prefix':head.tolist(),'logits_abs_bound':(head>>8).tolist(),'accumulator_bits':27,'pool_MAC_operand_bits':16,'logit_bits':20}
    data=np.load(ROOT/'data/DATASET.npz');rows=read(ROOT/'data/MANIFEST.json')['frames'];mi=data['manifest_index'];groups=np.array([rows[int(i)]['domain']+'/'+rows[int(i)]['group']for i in mi]);chosen=[];case_meta=[]
    for group in sorted(set(groups)):
        ids=np.flatnonzero(groups==group)
        for pos in(0,len(ids)//2,len(ids)-1):
            i=int(ids[pos]);r=rows[int(mi[i])];chosen.append(data['images'][i]);case_meta.append({'name':group.replace('/','_')+'_'+str(pos),'dataset_index':i,'manifest_index':int(mi[i]),'source_json':r['source_json'],'group':group,'split':str(data['split'][i])})
    assert len(chosen)==15 and len(set(groups))==5
    for value in(0,128,255):chosen.append(np.full((96,96),value,np.uint8));case_meta.append({'name':'constant_'+str(value)})
    rng=np.random.default_rng(20261102)
    for k in range(3):chosen.append(rng.integers(0,256,(96,96),dtype=np.uint8));case_meta.append({'name':'uniform_random_'+str(k),'seed':20261102})
    images=np.stack(chosen);x=torch.tensor(images[:,None].astype(np.float64)/128)
    with torch.no_grad():
        t1=net.layer(x,net.c1,7,True);t2=net.layer(t1,net.c2,7,True);tp=train.ste_floor(t2.reshape(-1,4,4,6,4,6).sum((3,5))/32).reshape(-1,64);tl=net.layer(tp,net.head,8,False)
        whole=net(x);assert torch.equal(whole,tl)
    qat={'conv1':(t1*128).numpy().astype(np.int64),'conv2':(t2*128).numpy().astype(np.int64),'pool':(tp*128).numpy().astype(np.int64),'logits':(tl*128).numpy().astype(np.int64)}
    batch_results,batch=sw.BatchModel(q).run(list(images),True);allfeatures=[];results=[]
    for i,roi in enumerate(images):
        result,features=vr.infer(roi,q)
        for k in('conv1','conv2','pool','logits'):
            assert np.array_equal(features[k],qat[k][i]),('QAT',i,k)
            assert np.array_equal(features[k],batch[k][i]),('BATCH',i,k)
        assert result['logits']==batch_results[i]['logits']and result['margin']==batch_results[i]['margin']
        allfeatures.append(features);results.append({**case_meta[i],**result})
    vectors=OUT/'rtl_vectors';vectors.mkdir(exist_ok=False)
    for k,name,bits in [('roi','input_pixels',8),('conv1','expected_f1',16),('conv2','expected_f2',16),('pool','expected_pool',16),('logits','expected_logits',32)]:
        a=np.stack([f[k]for f in allfeatures]);a=a.transpose(0,2,3,1)if k in('conv1','conv2')else a;mem(vectors/(name+'.mem'),a,bits)
    save(vectors/'INDEX.json',results);save(OUT/'INDEPENDENT_BOUNDS.json',bounds)
    template=BASE.parent/'secondary_pcb_centered_new_capture_mix_20261029_hw/02_sim/new_capture_mix_regression_r5_20261029/tb_real_pcb_core.sv'
    bench=template.read_text().replace('SAMPLE_COUNT=15','SAMPLE_COUNT='+str(len(images))).replace('vision_workspace workspace(','vision_workspace_goodonly workspace(')
    bench=bench.replace('assign mac_product_ext=mac_a*mac_w;','vision_shared_mac mac(.pcb_select(1\'b1),.cnn_a(16\'sd0),.cnn_w(8\'sd0),.pcb_a(mac_a),.pcb_w(mac_w),.product(),.cnn_product(),.pcb_product(mac_product_ext));')
    bench=bench.replace('../../model/experiments/conv4_4/',model.as_posix()+'/').replace('rtl_vectors/',vectors.as_posix()+'/')
    (OUT/'tb_retrained_pcb_core.sv').write_text(bench,encoding='ascii')
    sources=[BASE/'01_rtl/vision_workspace_goodonly.v',BASE/'01_rtl/vision_shared_mac.v',BASE/'01_rtl/pcb_fullboard_spatial96.v',OUT/'tb_retrained_pcb_core.sv']
    (OUT/'run.do').write_text('\n'.join(['onerror {quit -code 2}','onbreak {quit -code 3}','vlib work','vlog -sv -lint '+' '.join('"'+p.as_posix()+'"'for p in sources),'vsim -voptargs=+acc work.tb_real_pcb_core','run -all','quit -code 0','']),encoding='ascii')
    report={'status':'PASS_SELECTED_MEM_CHECKPOINT_QAT_INTEGER_EXACT','cases':len(images),'real_source_cases':15,'synthetic_cases':6,'selected_seed':freeze['seed'],'model_hashes':{p.name:sha(p)for p in(model/'weights.mem',model/'biases.mem')},'layers':['conv1','conv2','pool','logits'],'bias_scale':[16384,16384,32768],'weight_scale':[128,128,256],'RTL':'PREPARED_NOT_RUN','hardware':'NOT_RUN','limitations':['Numerical exactness is not defect accuracy or independent capture generalization.','Existing CCL crop120 RTL adapter is not claimed equal to the newly trained crop100 input contract.']}
    save(OUT/'SELECTED_MODEL_PARITY.json',report)
    inputs=[Path(__file__),ROOT/'train_ccl_binary.py',ROOT/'data/MANIFEST.json',ROOT/'data/DATASET.npz',ROOT/'reports/SELECTION_BEFORE_TEST.json',checkpoint,*sources,*list(model.iterdir())]
    save(OUT/'SOURCE_SHA256.json',{str(p):sha(p)for p in inputs if p.is_file()});print(json.dumps(report,indent=2))
if __name__=='__main__':main()
