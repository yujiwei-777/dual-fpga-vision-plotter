"""Summarize golden padding causality and unchanged shape-margin gates."""
from pathlib import Path
import json
import sys
sys.dont_write_bytecode=True
import numpy as np
import torch
import run_cnn_remote_detail as base


def main():
    root=base.BASE/'secondary_pcb_a4_newline_remote_cnn_20261027'
    out=root/'02_sim/ordinary_cnn_remote_detail_golden_shift8'
    model=root/'model/export'
    q=np.load(model/'quantized.npz');w=[q[f'w{i}'] for i in range(3)];b=[q[f'b{i}'] for i in range(3)]
    params=json.loads((model/'quantization.json').read_text())
    network=base.load_module('network_confidence_impact',base.BASE/'cnn_dualhead_scratch_20261015_r6/tools/network.py')
    cache=np.load(base.BASE/'secondary_link_stability_20261020/model/fast_strict160_dataset/images_strict160.npz')
    images=cache['images'].astype(np.uint8);labels=cache['labels'].astype(np.int64)
    torch.set_num_threads(4);torch.set_num_interop_threads(1)
    scores=network.integer_scores(images,w,b,params)
    sorted_scores=np.sort(scores[:,3:].astype(np.int64),axis=1)
    margins=sorted_scores[:,-1]-sorted_scores[:,-2]
    sc=np.minimum(255,margins>>8);shapes=scores[:,3:].argmax(1)
    thresholds=np.asarray([31,28,77])[shapes]
    groups=[]
    class_ids=labels[:,0]*3+labels[:,1]+1
    for cid in range(1,10):
        sel=class_ids==cid
        groups.append({'class_id':cid,'samples':int(sel.sum()),'shape_margin_gate_pass':int((sc[sel]>=thresholds[sel]).sum()),
                       'shape_conf_min':int(sc[sel].min()),'shape_conf_median':float(np.median(sc[sel])),'shape_conf_max':int(sc[sel].max())})
    report={'status':'PASS','native_1170_integer_metrics':network.metrics(scores,labels),
        'unchanged_shape_gates':{'triangle':31,'circle':28,'square':77},
        'shape_margin_gate_pass':int((sc>=thresholds).sum()),'samples':1170,'per_class':groups,
        'new_model_confidence_shift':8,'old_model_confidence_shift':7,
        'causality':{'old_kernel_new_weights_against_zero_padding':'FAIL Conv2 first pair 0x0025 vs 0x000e',
            'old_kernel_old_weights_against_zero_padding':'FAIL Conv2 first pair 0x1700 vs 0x0400',
            'old_kernel_new_weights_against_legacy_address0':'27/27 PASS all features/logits/class/conf',
            'corrected_kernel_new_weights_against_zero_padding':'27/27 PASS all features/logits/class/conf',
            'corrected_kernel_old_weights_against_zero_padding':'27/27 PASS all features/logits/class/conf'},
        'causality_reports':{name:str(base.BASE/'cnn_remote_detail_validation_20261027'/name/'RESULTS.json') for name in (
            'probe_current_shared_workspace','old_weights_zero_padding_mismatch','new_weights_legacy_address0_confirm','probe_conv2_padding_corrected','old_weights_corrected_zero_padding')},
        'live_production_contract_hashes':{str(p):base.sha(p) for p in [root/'01_rtl/cnn_core.v',root/'01_rtl/vision_pipeline.v',model/'weights.mem',model/'biases.mem',model/'quantization.json']},
        'limits':['All1170 replay includes fitted and model-selected data; this is not independent accuracy.',
            'Shape-margin pass is a per-core diagnostic, not final Type18 accept rate; pipeline additionally uses native color statistics and candidate geometry.',
            'Remote detail examples are synthetic downsample/upsample of source ROI; independent distant real captures have not been supplied.']}
    old_model=base.BASE/'secondary_pcb_a4_origin_return_20261027/model/export'
    old_params=json.loads((old_model/'quantization.json').read_text())
    wr=np.asarray([int(x,16) for x in (old_model/'weights.mem').read_text().split()],dtype=np.uint8).view(np.int8)
    br=np.asarray([int(x,16) for x in (old_model/'biases.mem').read_text().split()],dtype=np.uint32).view(np.int32)
    old_w=[wr[:72].reshape(8,1,3,3),wr[72:1224].reshape(16,8,3,3),wr[1224:].reshape(3,4096)]
    old_b=[br[:8],br[8:24],br[24:]]
    comparisons={}
    all_conf={};all_scores={}
    for tag,ww,bb,pp,padding in [('old_model_original_core_fc7',old_w,old_b,old_params,'legacy_address0'),
                                ('old_model_corrected_padding_fc7',old_w,old_b,old_params,'zero'),
                                ('new_model_corrected_padding_fc8',w,b,params,'zero')]:
        raw=[];confs=[]
        for i in range(0,len(images),64):
            _,_,col,log,_,_,_,confidence=base.make_features(images[i:i+64],ww,bb,pp,network,padding)
            raw.append(np.c_[col,log]);confs.append(confidence)
        raw=np.concatenate(raw).astype(np.int32);confs=np.concatenate(confs)
        shape_ids=raw[:,3:].argmax(1);gates=confs>=np.asarray([31,28,77])[shape_ids]
        joint_correct=(shape_ids==labels[:,1]) & (raw[:,:3].argmax(1)==labels[:,0])
        comparisons[tag]={'integer_metrics':network.metrics(raw,labels),'shape_margin_gate_pass':int(gates.sum()),
            'joint_correct_and_shape_gate_pass':int((gates&joint_correct).sum()),'wrong_joint_but_shape_gate_pass':int((gates&~joint_correct).sum()),
            'shape_gate_by_true_class':[{ 'class_id':cid,'gate_pass':int(gates[class_ids==cid].sum()),
               'joint_correct_and_gate_pass':int((gates&joint_correct)[class_ids==cid].sum()),'samples':int((class_ids==cid).sum())} for cid in range(1,10)],
            'padding':padding,'shape_conf_shift':pp['fc_conf_shift'][1]}
        all_scores[tag]=raw;all_conf[tag]=confs
    report['same1170_baseline_comparison']=comparisons
    report['old_model_input_hashes']={str(x):base.sha(x) for x in [old_model/'weights.mem',old_model/'biases.mem',old_model/'quantization.json']}
    original=comparisons['old_model_original_core_fc7']['shape_margin_gate_pass']
    corrected=comparisons['old_model_corrected_padding_fc7']['shape_margin_gate_pass']
    replacement=comparisons['new_model_corrected_padding_fc8']['shape_margin_gate_pass']
    report['shape_gate_delta']={'padding_fix_only':corrected-original,'model_replacement_vs_corrected_old':replacement-corrected,'new_release_vs_original_old':replacement-original}
    (out/'CONTRACT_AND_GATE_AUDIT.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'shape_gate_pass':report['shape_margin_gate_pass'],'comparisons':{k:{'joint_correct':v['integer_metrics']['joint_correct'],
        'shape_gate_pass':v['shape_margin_gate_pass'],'joint_correct_and_shape_gate_pass':v['joint_correct_and_shape_gate_pass']} for k,v in comparisons.items()},
        'delta':report['shape_gate_delta']},indent=2))


if __name__=='__main__':main()
