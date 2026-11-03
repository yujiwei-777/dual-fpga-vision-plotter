"""Summarize the frozen model without fitting or changing its parameters."""
from pathlib import Path
from collections import Counter
import json,hashlib,sys
sys.dont_write_bytecode=True
import cv2
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def save(p,v):
    assert not p.exists(),str(p)
    p.write_text(json.dumps(v,indent=2,ensure_ascii=False,allow_nan=False)+'\n',encoding='utf-8')

def main():
    report=ROOT/'reports'
    data=np.load(ROOT/'data/DATASET.npz')
    rows=read(ROOT/'data/MANIFEST.json')['frames']
    logits=np.load(report/'retrained_selected_ALL_LOGITS.npy')
    pred=(logits[:,1]>logits[:,0]).astype(np.int64)
    margin=np.minimum(65535,np.abs(logits[:,1]-logits[:,0]))
    errors=[]
    for i in np.flatnonzero((data['split']=='test')&(pred!=data['labels'])&(margin>=32)):
        row=rows[int(data['manifest_index'][i])]
        errors.append(dict(dataset_index=int(i),source_json=row['source_json'],domain=row['domain'],
            truth=row['truth'],prediction='PASS' if pred[i]==0 else 'FAIL',margin=int(margin[i]),
            logits=logits[i].tolist(),crop=row['ccl']['bbox'],roi_sha256=hashlib.sha256(data['images'][i].tobytes()).hexdigest().upper()))
    assert len(errors)==8 and Counter(e['prediction'] for e in errors)=={'PASS':7,'FAIL':1}
    save(report/'TEST_ACCEPTED_ERRORS.json',dict(status='KNOWN_REMAINING_MODEL_ERRORS',errors=errors,
        selection='Every wrong accepted result in the frozen grouped test; no threshold change',hardware='NOT_RUN'))
    canvas=np.full((2*370,4*310,3),245,np.uint8)
    for k,e in enumerate(errors):
        x,y=(k%4)*310,(k//4)*370
        image=cv2.resize(data['images'][e['dataset_index']],(288,288),interpolation=cv2.INTER_NEAREST)
        canvas[y+5:y+293,x+10:x+298]=cv2.cvtColor(image,cv2.COLOR_GRAY2BGR)
        texts=[f"{k+1}: true {e['truth']}",f"out {e['prediction']}  margin {e['margin']}",Path(e['source_json']).name[:22]]
        for j,text in enumerate(texts):
            cv2.putText(canvas,text,(x+9,y+312+j*22),cv2.FONT_HERSHEY_SIMPLEX,.43,(20,20,180),1,cv2.LINE_AA)
    dest=report/'TEST_ACCEPTED_ERRORS.png';assert not dest.exists()
    assert cv2.imwrite(str(dest),canvas)
    core=read(report/'rtl_core/LATEST.json')
    contract=dict(status='MODEL_CANDIDATE_NOT_INTEGRATED',model_root=str((ROOT/'model/selected').resolve()),
        allowed_training_roots=['D:/ai/1/0/','D:/ai/1/8/1/'],existing_weights_used_for_fit=False,
        model_hashes=read(ROOT/'model/selected/MODEL.json')['hashes'],
        CCL=dict(grid=[160,90],source_sample='8*u+4,8*v+4',foreground='unsigned source Y<=112',connectivity=4,choice='largest valid component, raster first tie'),
        crop=dict(scale_numerator=1,scale_denominator=1,half_open=True,source_formula='origin+floor((2*u+1)*span/192)',input=[96,96],dtype='unsigned Y8',normalization='none',orientation='none'),
        classifier=dict(channels=[1,4,4],strides=[2,2],padding=[1,1],weight_count=308,bias_count=10,shifts=[7,7,8],conv_activation='floor(acc/128),ReLU,clip0..32767',pool='6x6 sum>>5,CHW64,MAC signed16',head='floor(acc/256),signed20',margin_min=32,classes={'0':'GOOD/PASS','1':'BAD/FAIL'},low_margin='REVIEW',score='Legacy winning-logit saturation0..255; not calibrated probability'),
        required_integration_changes=['Use new weights and matching biases together','Change PCB crop adapter from1.20 to exact1.00','Keep source-border/no-candidate/overflow REVIEW gates','Retain original CCL result box and defect_count=0','Revalidate integrated PCB/ordinaryCNN/document/keys/GRBL/HXA/DDR before physical build'],
        validation=dict(independent_integer_replay=1450,software_layer_parity=21,core_RTL=core['status'],core_RTL_cases=18,integrated='NOT_RUN',synthesis='NOT_RUN',place_route='NOT_RUN',bitgen='NOT_RUN'),
        known_test_limits=dict(BAD_falsePASS=7,BAD_test=96,GOOD_falseFAIL=1,GOOD_test=135,REVIEW=3),hardware='NOT_RUN')
    save(report/'INTEGRATION_CONTRACT.json',contract)
    seal={p.relative_to(ROOT).as_posix():sha(p) for p in sorted(ROOT.rglob('*')) if p.is_file() and '__pycache__' not in p.parts and p.name!='SHA256_DELIVERY.json'}
    save(ROOT/'SHA256_DELIVERY.json',dict(files=seal,hardware='NOT_RUN',bit_generated=False))
    assert all(sha(ROOT/p)==v for p,v in seal.items())
    print(json.dumps(dict(status='DELIVERY_SEALED',files=len(seal),errors=len(errors),model_hashes=contract['model_hashes']),indent=2))

if __name__=='__main__':main()
