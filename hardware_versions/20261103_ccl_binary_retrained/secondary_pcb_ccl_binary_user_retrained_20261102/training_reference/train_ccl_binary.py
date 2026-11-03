"""Scratch training of hardware-matched C4/C4 PCB binary models.

Only the approved dataset is used; validation chooses checkpoints and seeds.
The grouped test set is evaluated once after all candidates are frozen.
No FPGA project, old model, work/ backup or bitstream is modified.
"""
from pathlib import Path
from collections import Counter
import copy, hashlib, importlib.util, json, math, os, random, sys, time
os.environ.setdefault('OMP_NUM_THREADS','4')
os.environ.setdefault('MKL_NUM_THREADS','4')
sys.dont_write_bytecode=True
import numpy as np
import torch
from torch import nn
from torch.nn import functional as F

ROOT=Path(__file__).resolve().parent
BASE=ROOT.parent/'secondary_pcb_ccl_binary_roi120_20261102'
SHIFTS=[7,7,8]
SEEDS=[20261102,20261103]
EPOCHS=120

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def save(p,v):
    p=Path(p);p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(json.dumps(v,ensure_ascii=False,indent=2,allow_nan=False)+'\n',encoding='utf-8')

class QuantizeSTE(torch.autograd.Function):
    @staticmethod
    def forward(ctx,v,scale,low,high):
        return torch.clamp(torch.round(v*scale),low,high)/scale
    @staticmethod
    def backward(ctx,grad):
        return grad,None,None,None

def ste_round(v,scale,low,high):
    return QuantizeSTE.apply(v,scale,low,high)

class FloorSTE(torch.autograd.Function):
    @staticmethod
    def forward(ctx,v):
        return torch.floor(v*128)/128
    @staticmethod
    def backward(ctx,grad):
        return grad

def ste_floor(v):
    return FloorSTE.apply(v)

class HardwareNet(nn.Module):
    def __init__(self):
        super().__init__()
        self.c1=nn.Conv2d(1,4,3,stride=2,padding=1)
        self.c2=nn.Conv2d(4,4,3,stride=2,padding=1)
        self.head=nn.Linear(64,2)
        self.qat=False
    def layer(self,x,layer,shift,conv):
        w,b=layer.weight,layer.bias
        if self.qat:
            w=ste_round(w,2**shift,-127,127)
            b=ste_round(b,128*2**shift,-(1<<26),(1<<26)-1)
        y=F.conv2d(x,w,b,stride=2,padding=1) if conv else F.linear(x,w,b)
        if self.qat:y=ste_floor(y)
        return torch.clamp(y,0,32767/128) if conv else y
    def forward(self,x):
        x=self.layer(x,self.c1,7,True)
        x=self.layer(x,self.c2,7,True)
        x=x.reshape(-1,4,4,6,4,6).sum((3,5))/32
        if self.qat:x=ste_floor(x)
        return self.layer(x.flatten(1),self.head,8,False)

def arrays(net):
    out={}
    for i,layer in enumerate([net.c1,net.c2,net.head],1):
        scale=2**SHIFTS[i-1]
        out['w'+str(i)]=np.clip(np.rint(layer.weight.detach().numpy()*scale),-127,127).astype(np.int8)
        out['b'+str(i)]=np.rint(layer.bias.detach().numpy()*128*scale).astype(np.int32)
    return out

def bound_proof(q):
    limits=np.array([255],dtype=np.int64);reports=[]
    for i in (1,2):
        w=q['w'+str(i)].astype(np.int64);b=q['b'+str(i)].astype(np.int64)
        low=b+(np.minimum(w,0)*limits[None,:,None,None]).sum((1,2,3))
        high=b+(np.maximum(w,0)*limits[None,:,None,None]).sum((1,2,3))
        assert np.all(low>=-(1<<26)) and np.all(high<(1<<26)) and np.all(np.abs(b)<(1<<26))
        limits=np.clip(high>>7,0,32767)
        reports.append(dict(layer=i,acc_min=low.tolist(),acc_max=high.tolist(),activation_max=limits.tolist()))
    pooled=(36*limits)>>5
    assert np.all(pooled<32768),'Pool would reinterpret positive values as signed16'
    feature_limits=np.repeat(pooled,16)
    w=q['w3'].astype(np.int64);b=q['b3'].astype(np.int64)
    low=b+(np.minimum(w,0)*feature_limits).sum(1)
    high=b+(np.maximum(w,0)*feature_limits).sum(1)
    assert np.all(low>=-(1<<26)) and np.all(high<(1<<26)) and np.all(np.abs(b)<(1<<26))
    assert np.all((low>>8)>=-(1<<19)) and np.all((high>>8)<(1<<19))
    return dict(status='PROVED_FULL_UNSIGNED_Y8_INPUT_RANGE',conv=reports,pool_max=pooled.tolist(),head_min=low.tolist(),head_max=high.tolist(),logits_min=(low>>8).tolist(),logits_max=(high>>8).tolist())

def integer_logits(q,images):
    model=SW.BatchModel(q);out=[]
    for j in range(0,len(images),64):out.extend(model.run(list(images[j:j+64])))
    return np.array([r['logits'] for r in out],dtype=np.int64)

def metrics(logits,truth):
    pred=(logits[:,1]>logits[:,0]).astype(np.int64)
    margin=np.minimum(65535,np.abs(logits[:,1]-logits[:,0]));review=margin<32
    return dict(n=len(truth),correct=int((pred==truth).sum()),
        accuracy=float((pred==truth).mean()) if len(truth) else None,
        GOOD=dict(n=int((truth==0).sum()),PASS=int(((truth==0)&(pred==0)&~review).sum()),REVIEW=int(((truth==0)&review).sum()),FAIL=int(((truth==0)&(pred==1)&~review).sum())),
        BAD=dict(n=int((truth==1).sum()),PASS=int(((truth==1)&(pred==0)&~review).sum()),REVIEW=int(((truth==1)&review).sum()),FAIL=int(((truth==1)&(pred==1)&~review).sum())),
        margin_min=int(margin.min()) if len(truth) else None,margin_median=float(np.median(margin)) if len(truth) else None)

def grouped_metrics(logits,truth,groups):
    return dict(ALL=metrics(logits,truth),groups={str(g):metrics(logits[groups==g],truth[groups==g]) for g in sorted(set(groups))})

def selection_key(report):
    vals=[];wrong=[];review=[]
    for r in report['groups'].values():
        n=max(1,r['n']);w=r['GOOD']['FAIL']+r['BAD']['PASS'];rv=r['GOOD']['REVIEW']+r['BAD']['REVIEW']
        vals.append((r['n']-w-rv-2*w-.25*rv)/n);wrong.append(w/n);review.append(rv/n)
    return (float(np.mean(vals)),-float(np.max(wrong)),-float(np.mean(review)))

def augment(x):
    n=len(x)
    gain=.94+torch.rand(n,1,1,1)*.12
    offset=(torch.rand(n,1,1,1)*2-1)*6/128
    y=x*gain+offset+torch.randn_like(x)*(.6/128)
    return torch.clamp(torch.round(y*128),0,255)/128

def export(net,dest):
    q=arrays(net);proof=bound_proof(q)
    dest.mkdir(parents=True,exist_ok=False)
    ww=np.concatenate([q['w'+str(i)].ravel() for i in (1,2,3)])
    bb=np.concatenate([q['b'+str(i)].ravel() for i in (1,2,3)])
    assert len(ww)==308 and len(bb)==10
    (dest/'weights.mem').write_text(''.join(f'{int(v)&255:02x}\n' for v in ww),encoding='ascii')
    (dest/'biases.mem').write_text(''.join(f'{int(v)&0xffffffff:08x}\n' for v in bb),encoding='ascii')
    np.savez_compressed(dest/'QUANTIZED.npz',**q)
    save(dest/'ARITHMETIC_BOUNDS.json',proof)
    save(dest/'MODEL.json',dict(architecture='96x96 unsigned source Y8, Conv3x3 stride2 pad1 1->4->4,6x6 sum>>5,FC64->2',
         classes={'0':'GOOD','1':'BAD'},shifts=SHIFTS,margin_min=32,crop_scale=1,
         crop='Original shared CCL half-open bbox; exact source point sampling origin+floor((2*u+1)*span/192)',
         weight_count=308,bias_count=10,trained_from_scratch=True,
         source_roots=['D:/ai/1/0/','D:/ai/1/8/1/'],hardware='NOT_RUN',RTL='NOT_RUN_FOR_THIS_MODEL',
         hashes={p.name:sha(p) for p in [dest/'weights.mem',dest/'biases.mem']}))
    return q

def train_seed(seed,images,truth,split,groups):
    random.seed(seed);np.random.seed(seed);torch.manual_seed(seed)
    net=HardwareNet().double();optimizer=torch.optim.AdamW(net.parameters(),lr=.0025,weight_decay=1e-4)
    scheduler=torch.optim.lr_scheduler.CosineAnnealingLR(optimizer,EPOCHS,eta_min=.00008)
    tx=torch.from_numpy(images[:,None].astype(np.float64)/128);ty=torch.from_numpy(truth.astype(np.int64))
    tr=np.flatnonzero(split=='train');va=np.flatnonzero(split=='validation')
    # Each class has equal aggregate weight, then equal domain/subtype weight.
    weights=np.zeros(len(images),np.float64)
    for label in (0,1):
        gs=sorted(set(groups[tr][truth[tr]==label]))
        for group in gs:
            ids=tr[(truth[tr]==label)&(groups[tr]==group)]
            weights[ids]=.5/len(gs)/len(ids)
    probabilities=torch.from_numpy(weights[tr]);history=[];best_key=None;best_state=None
    dest=ROOT/'candidates'/('seed_'+str(seed));dest.mkdir(parents=True,exist_ok=False)
    began=time.perf_counter()
    for epoch in range(1,EPOCHS+1):
        net.train();net.qat=epoch>25
        order=tr[torch.multinomial(probabilities,len(tr),replacement=True).numpy()]
        total=0.
        for pos in range(0,len(order),48):
            ids=order[pos:pos+48];clean=tx[ids];input_x=clean if torch.rand(())<.35 else augment(clean)
            optimizer.zero_grad(set_to_none=True)
            logits=net(input_x)
            loss=F.cross_entropy(logits,ty[ids])
            loss.backward();torch.nn.utils.clip_grad_norm_(net.parameters(),5);optimizer.step()
            total+=float(loss.detach())*len(ids)
        scheduler.step()
        if epoch==1 or epoch%10==0 or epoch==26:
            row=dict(epoch=epoch,loss=total/len(order),qat=net.qat,seconds=time.perf_counter()-began)
            if net.qat:
                q=arrays(net)
                try:
                    bound_proof(q)
                    valid=grouped_metrics(integer_logits(q,images[va]),truth[va],groups[va])
                    key=selection_key(valid);row.update(validation=valid,selection_key=list(key))
                    if best_key is None or key>best_key:
                        best_key=key;best_state=copy.deepcopy(net.state_dict());row['best']=True
                except AssertionError as ex:row['export_rejected']=str(ex)
            history.append(row);save(dest/'HISTORY.json',history)
            print('TRAIN',seed,'epoch',epoch,'loss',round(row['loss'],4),'key',row.get('selection_key'),'seconds',round(row['seconds'],1),flush=True)
    assert best_state is not None,'No exportable QAT checkpoint'
    net.load_state_dict(best_state);net.qat=True
    q=export(net,dest/'model')
    torch.save(net.state_dict(),dest/'CHECKPOINT.pt')
    validation=grouped_metrics(integer_logits(q,images[va]),truth[va],groups[va])
    save(dest/'FROZEN.json',dict(seed=seed,selection_key=list(best_key),validation=validation,model_hashes={p.name:sha(p) for p in (dest/'model').glob('*.mem')},test_used_for_selection=False))
    return dict(seed=seed,key=best_key,model=q,path=dest,validation=validation)

def main():
    global SW
    torch.set_num_threads(4);torch.set_num_interop_threads(1);torch.backends.mkldnn.enabled=True
    spec=importlib.util.spec_from_file_location('binary_train_integer',BASE/'tools/binary_scale_sweep.py')
    SW=importlib.util.module_from_spec(spec);spec.loader.exec_module(SW)
    manifest=read(ROOT/'data/MANIFEST.json');data=np.load(ROOT/'data/DATASET.npz')
    images=data['images'];truth=data['labels'];split=data['split']
    rows=manifest['frames']
    index=data['manifest_index']
    groups=np.array([rows[int(i)]['domain']+'/'+rows[int(i)]['group'] for i in index])
    assert all(len(set(truth[split==sp]))==2 for sp in ('train','validation','test'))
    reports=ROOT/'reports';reports.mkdir(exist_ok=True)
    policy=reports/'TRAINING_POLICY_BEFORE_RUN.json'
    assert not policy.exists(),'Do not silently overwrite prior training'
    save(policy,dict(allowed_roots=['D:/ai/1/0/','D:/ai/1/8/1/'],init='Scratch, no old-model initialization',
         seeds=SEEDS,epochs=EPOCHS,float_warmup_epochs=25,QAT=True,shifts=SHIFTS,architecture='C4/C4/FC2,308+10',
         input='Direct source Y8,96x96,original CCL bbox x1.00; no RGB conversion,normalization or orientation correction',
         balanced_sampling='Equal aggregate class weight, equal domain/subtype within class',
         augmentation='Train-only Y gain0.94..1.06,offset+-6,noise0.6;35% clean; no geometry transforms',
         split='Prepared contiguous20-frame blocks with two-frame boundary guards',
         training_dtype='float64; exact dyadic QAT coefficients and integer-floor forward',
         checkpoint_selection='Validation mean group accepted utility:correct-2*wrong-.25*review; no test selection',
         seed_selection='Same validation utility after candidates frozen; test evaluated once after selection',
         confidence_margin_min=32,model_provenance='No existing model weights used for optimization',
         script_sha256=sha(Path(__file__)),dataset_sha256=sha(ROOT/'data/DATASET.npz'),manifest_sha256=sha(ROOT/'data/MANIFEST.json'),
         hardware='NOT_RUN',limitations='Previously observed captures of limited physical boards; grouped test is not independent new captures'))
    candidates=[train_seed(seed,images,truth,split,groups) for seed in SEEDS]
    selected=max(candidates,key=lambda r:r['key'])
    import shutil
    target=ROOT/'model/selected';target.parent.mkdir(exist_ok=True)
    assert not target.exists();shutil.copytree(selected['path']/'model',target)
    freeze=dict(seed=selected['seed'],validation_selection_key=list(selected['key']),test_read_yet=False,
                hashes={p.name:sha(p) for p in target.iterdir() if p.is_file()})
    save(reports/'SELECTION_BEFORE_TEST.json',freeze)
    # Both models now immutable; perform final grouped test and full replay.
    result={}
    for name,q in [('old_frozen_control',SW.vr.load_model()),('retrained_selected',selected['model'])]:
        logits=integer_logits(q,images)
        result[name]={str(sp):grouped_metrics(logits[split==sp],truth[split==sp],groups[split==sp]) for sp in ('train','validation','test','guard')}
        np.save(reports/(name+'_ALL_LOGITS.npy'),logits)
    save(reports/'TRAINING_REPORT.json',dict(status='TRAINING_AND_INTEGER_REPLAY_COMPLETE',selected_seed=selected['seed'],
         dataset_counts=dict(Counter(str(s) for s in split)),results=result,hardware='NOT_RUN',
         RTL='NOT_RUN_FOR_NEW_WEIGHTS',synthesis='NOT_RUN_FOR_NEW_WEIGHTS',bitgen='NOT_RUN',
         limit='No blind accuracy claim; same capture sessions split with frame-block guards; no new backgrounds or physical boards'))
    print(json.dumps(dict(complete=True,selected_seed=selected['seed'],results=result),indent=2),flush=True)

if __name__=='__main__':main()
