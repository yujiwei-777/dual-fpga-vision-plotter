"""Independent int64 all-image replay and policy/selection audit; no fitting."""
from pathlib import Path
from collections import Counter
import importlib.util,json,hashlib,sys,time
import numpy as np
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2];OUT=Path(__file__).parent
BASE=ROOT.parent/'secondary_pcb_ccl_binary_roi120_20261102'
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def save(p,x):Path(p).write_text(json.dumps(x,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
def module(name,p):
    spec=importlib.util.spec_from_file_location(name,p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
def main():
    began=time.perf_counter();vr=module('full_independent',BASE/'tools/binary_validation_reference.py');train=module('full_training_audit',ROOT/'train_ccl_binary.py')
    data=np.load(ROOT/'data/DATASET.npz');manifest=read(ROOT/'data/MANIFEST.json');rows=manifest['frames'];mi=data['manifest_index'];images=data['images'];split=data['split'];truth=data['labels']
    selected=ROOT/'model/selected';w=np.array([int(v,16)for v in(selected/'weights.mem').read_text().split()],np.uint8).view(np.int8);b=np.array([int(v,16)for v in(selected/'biases.mem').read_text().split()],np.uint32).view(np.int32)
    q={'w1':w[:36].reshape(4,1,3,3),'w2':w[36:180].reshape(4,4,3,3),'w3':w[180:].reshape(2,64),'b1':b[:4],'b2':b[4:8],'b3':b[8:]}
    batch_logits=np.load(ROOT/'reports/retrained_selected_ALL_LOGITS.npy');output=[]
    for i,roi in enumerate(images):
        r=rows[int(mi[i])];assert r['label']==int(truth[i])and r['split']==str(split[i])and r['dataset_index']==i
        assert hashlib.sha256(roi.tobytes()).hexdigest().upper()==r['roi_sha256']
        source=Path(r['source_json']).resolve();allowed=[Path('D:/ai/1/0').resolve(),Path('D:/ai/1/8/1').resolve()];assert any(source.is_relative_to(a)for a in allowed)
        result,_=vr.infer(roi,q);assert result['logits']==batch_logits[i].tolist(),i;output.append(result['logits'])
    policy=read(ROOT/'reports/TRAINING_POLICY_BEFORE_RUN.json');assert policy['script_sha256']==sha(ROOT/'train_ccl_binary.py')and policy['dataset_sha256']==sha(ROOT/'data/DATASET.npz')and policy['manifest_sha256']==sha(ROOT/'data/MANIFEST.json')
    frozen=read(ROOT/'reports/SELECTION_BEFORE_TEST.json');assert all(sha(selected/n)==h for n,h in frozen['hashes'].items())
    candidates=[read(p)for p in(ROOT/'candidates').glob('*/FROZEN.json')];assert all(c['test_used_for_selection']is False for c in candidates)
    best=max(candidates,key=lambda c:tuple(c['selection_key']));assert best['seed']==frozen['seed']
    assert all(tuple(train.selection_key(c['validation']))==tuple(c['selection_key'])for c in candidates)
    report=read(ROOT/'reports/TRAINING_REPORT.json');logits=np.array(output,np.int64)
    for sp in('train','validation','test','guard'):
        assert train.metrics(logits[split==sp],truth[split==sp])==report['results']['retrained_selected'][sp]['ALL']
    result={'status':'PASS','all_dataset_logits_exact':len(images),'dataset_role_counts':dict(Counter(str(s)for s in split)),'allowed_root_validation':'PASS_ALL_ELIGIBLE_IMAGES','roi_hashes_match_manifest':'PASS_ALL_ELIGIBLE_IMAGES','training_policy_hash_matches_actual_script':True,'training_policy_hash_matches_dataset_and_manifest':True,'selected_model_matches_before_test_freeze':True,'selected_seed_is_best_validation_key':True,'test_selection_code_review':'train_seed reads only train/validation for optimization and checkpoint metrics; main selects seeds from validation keys, writes SELECTION_BEFORE_TEST before full test replay','test_results_recomputed':report['results']['retrained_selected']['test']['ALL'],'seconds':time.perf_counter()-began,'RTL':'NOT_RUN_BY_THIS_AUDIT','hardware':'NOT_RUN','limitations':['All captures were observed in prior development; blocked same-session splits do not prove new-board/background generalization.','This numerical audit does not resolve the seven BAD falsePASS results in grouped test.']}
    save(OUT/'FULL_REPLAY_AUDIT.json',result);print(json.dumps(result,indent=2))
if __name__=='__main__':main()
