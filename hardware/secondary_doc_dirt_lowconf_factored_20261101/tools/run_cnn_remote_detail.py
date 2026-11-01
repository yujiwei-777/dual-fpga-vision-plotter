"""Read-only model/RTL contract check using the real strict160 RGB8 cache.

Creates a new output directory, never trains or mutates a model/RTL input.
Synthetic loss of image detail is explicitly distinct from real remote frames.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True

import cv2
import numpy as np
import torch
import torch.nn.functional as F

BASE = next(p for p in Path(__file__).resolve().parents if (p / 'cnn_dualhead_scratch_20261015_r6/tools/network.py').is_file())
TOOLS = Path('E:/model/win64')


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def hexfile(path, values, digits):
    mask = (1 << (4 * digits)) - 1
    path.write_text(''.join(f'{int(v) & mask:0{digits}x}\n' for v in np.asarray(values).ravel()), encoding='ascii')


def detail(src, rng, scale_range):
    # Exact train_remote_detail.detail_transform evaluation operation.
    scale = float(rng.uniform(*scale_range))
    n = max(12, min(64, int(round(64 * scale))))
    z = cv2.resize(cv2.resize(src, (n, n), interpolation=cv2.INTER_AREA), (64, 64), interpolation=cv2.INTER_LINEAR)
    z = cv2.GaussianBlur(z, (3, 3), sigmaX=float(rng.uniform(.15, .85)))
    z = z.astype(np.float32) * float(rng.uniform(.90, 1.08)) + float(rng.uniform(-10, 10))
    z += rng.normal(0, float(rng.uniform(.3, 1.8)), z.shape)
    return np.clip(np.rint(z), 0, 255).astype(np.uint8)


def make_features(images, weights, biases, params, network, padding_mode='zero'):
    shape, colors = network.preprocess(images, params['shape_mode'])
    x = torch.from_numpy(shape).float()
    features = []
    for i in range(2):
        if i == 1 and padding_mode == 'legacy_address0':
            # The old RTL reads activation_addr=0 for every out-of-frame tap,
            # i.e. channel 0 of the first pixel, regardless of input channel.
            pads = x[:, :1, :1, :1].expand(-1, x.shape[1], x.shape[2]+2, x.shape[3]+2).clone()
            pads[:, :, 1:-1, 1:-1] = x
            x = pads
            padding = 0
        else:
            padding = 1
        acc = F.conv2d(x, torch.from_numpy(weights[i].astype(np.float32)),
                       torch.from_numpy(biases[i].astype(np.float32)), padding=padding)
        shift = params['conv_shifts'][i]
        x = F.max_pool2d(torch.floor((acc + (1 << (shift - 1))) / (1 << shift)).clamp(0, 127), 2)
        features.append(x.permute(0, 2, 3, 1).reshape(len(x), -1).numpy().astype(np.uint8))
    logits = features[1].astype(np.int64) @ weights[2].astype(np.int64).T + biases[2]
    # Production color ties favor B then G then R; shape ties favor lowest ID.
    color_ids = 2 - colors[:, ::-1].argmax(1)
    shape_ids = logits.argmax(1)
    margins_c = np.diff(np.sort(colors, axis=1)[:, -2:], axis=1)[:, 0]
    margins_s = np.diff(np.sort(logits, axis=1)[:, -2:], axis=1)[:, 0]
    cc = np.minimum(255, margins_c >> params['fc_conf_shift'][0])
    sc = np.minimum(255, margins_s >> params['fc_conf_shift'][1])
    return shape.reshape(len(x), -1), features, colors, logits, color_ids, shape_ids, cc, sc


BENCH = r'''
`timescale 1ns/1ps
module tb_remote_detail;
    localparam integer CASES = @CASES@;
    reg clk=0; always #4 clk=~clk;
    reg rst_n=0, pixel_we=0, start=0;
    reg [11:0] pixel_addr=0;
    reg [23:0] pixel_rgb=0;
    wire busy,done,bg; wire [1:0] color_id,shape_id; wire [7:0] cc,sc;
    wire sw,f1w,f2w; wire [11:0] sa,f2a; wire [12:0] f1a,ra;
    wire [15:0] sd,f1d,f2d; wire [1:0] rs; wire [7:0] rd;
    wire signed [15:0] ma; wire signed [7:0] mw; wire signed [23:0] mp;
    cnn_core #(.WEIGHTS_MEM("@WEIGHTS@"), .BIASES_MEM("@BIASES@"),
      .FC_CONF_SHIFT(@CONF_SHIFT@), .USE_SHARED_WORKSPACE(1), .EXTERNAL_MAC(1)) dut(
      .clk(clk),.rst_n(rst_n),.pixel_we(pixel_we),.pixel_addr(pixel_addr),.pixel_rgb(pixel_rgb),.start(start),
      .busy(busy),.done(done),.color_id(color_id),.shape_id(shape_id),.color_conf(cc),.shape_conf(sc),.background_reject(bg),
      .ws_shape_we(sw),.ws_shape_waddr(sa),.ws_shape_wdata(sd),.ws_f1_we(f1w),.ws_f1_waddr(f1a),.ws_f1_wdata(f1d),
      .ws_f2_we(f2w),.ws_f2_waddr(f2a),.ws_f2_wdata(f2d),.ws_rd_sel(rs),.ws_rd_addr(ra),.ws_rd_data(rd),
      .mac_a(ma),.mac_w(mw),.mac_product_ext(mp));
    vision_workspace workspace(.clk(clk),.purpose(2'd0),
      .cnn_shape_we(sw),.cnn_shape_waddr(sa),.cnn_shape_wdata(sd),.cnn_f1_we(f1w),.cnn_f1_waddr(f1a),.cnn_f1_wdata(f1d),
      .cnn_f2_we(f2w),.cnn_f2_waddr(f2a),.cnn_f2_wdata(f2d),.cnn_rd_sel(rs),.cnn_rd_addr(ra),.cnn_rd_data(rd),
      .pcb_we(1'b0),.pcb_wbank(1'b0),.pcb_waddr(15'd0),.pcb_wdata(16'd0),.pcb_rd_bank(1'b0),.pcb_rd_addr(15'd0),.pcb_rd_data());
    vision_shared_mac mac(.pcb_select(1'b0),.cnn_a(ma),.cnn_w(mw),.pcb_a(16'sd0),.pcb_w(8'sd0),
      .product(),.cnn_product(mp),.pcb_product());
    reg [23:0] pixels[0:CASES*4096-1];
    reg [7:0] shape_ref[0:CASES*4096-1],f1_ref[0:CASES*8192-1],f2_ref[0:CASES*4096-1];
    reg [31:0] results[0:CASES*10-1];
    integer c=0,i,cycles,f1count=0,f2count=0;
    initial begin
      $readmemh("pixels.mem",pixels); $readmemh("shape.mem",shape_ref);
      $readmemh("feature1.mem",f1_ref); $readmemh("feature2.mem",f2_ref); $readmemh("results.mem",results);
      repeat(5) @(negedge clk); rst_n=1;
      for(c=0;c<CASES;c=c+1) begin
        f1count=0;f2count=0;
        for(i=0;i<4096;i=i+1) begin
          @(negedge clk); pixel_we=1;pixel_addr=i;pixel_rgb=pixels[c*4096+i];
        end
        @(negedge clk);pixel_we=0;
        @(negedge clk);start=1;
        @(negedge clk);start=0;
        cycles=0;
        while(!done&&cycles<3000000) begin @(negedge clk);cycles=cycles+1;end
        if(!done) $fatal(1,"TIMEOUT case=%0d state=%0d",c,dut.state);
        if(f1count!=4096||f2count!=2048) $fatal(1,"Feature write count case=%0d f1=%0d f2=%0d",c,f1count,f2count);
        for(i=0;i<3;i=i+1) begin
          if(dut.scores[i]!==results[c*10+i]) $fatal(1,"LOGIT case=%0d index=%0d rtl=%0d expected=%0d",c,i,$signed(dut.scores[i]),$signed(results[c*10+i]));
          if(dut.color_sum[i]!==results[c*10+3+i][18:0]) $fatal(1,"COLOR SUM case=%0d index=%0d",c,i);
        end
        if(color_id!==results[c*10+6][1:0]||shape_id!==results[c*10+7][1:0]||cc!==results[c*10+8][7:0]||sc!==results[c*10+9][7:0]||bg!==0)
          $fatal(1,"CLASS/CONF case=%0d got=%0d,%0d,%0d,%0d expected=%0d,%0d,%0d,%0d",c,color_id,shape_id,cc,sc,results[c*10+6],results[c*10+7],results[c*10+8],results[c*10+9]);
        $display("PASS CNN CASE %0d cycles=%0d logits=%0d,%0d,%0d class=%0d color_conf=%0d shape_conf=%0d",c,cycles,
          $signed(dut.scores[0]),$signed(dut.scores[1]),$signed(dut.scores[2]),(color_id-1)*3+shape_id,cc,sc);
      end
      $display("PASS ALL CNN REMOTE DETAIL cases=%0d",CASES);$finish;
    end
    always @(posedge clk) if(rst_n) begin
      if(sw && sd!=={shape_ref[c*4096+sa],shape_ref[c*4096+sa-1]}) $fatal(1,"SHAPE INPUT case=%0d address=%0d",c,sa);
      if(f1w) begin
        if(f1d!=={f1_ref[c*8192+f1a],f1_ref[c*8192+f1a-1]})
          $fatal(1,"FEATURE1 case=%0d address=%0d rtl=%h expected=%h",c,f1a,f1d,{f1_ref[c*8192+f1a],f1_ref[c*8192+f1a-1]});
        f1count=f1count+1;
      end
      if(f2w) begin
        if(f2d!=={f2_ref[c*4096+f2a],f2_ref[c*4096+f2a-1]})
          $fatal(1,"FEATURE2 case=%0d address=%0d rtl=%h expected=%h",c,f2a,f2d,{f2_ref[c*4096+f2a],f2_ref[c*4096+f2a-1]});
        f2count=f2count+1;
      end
    end
endmodule
'''


def main():
    p=argparse.ArgumentParser()
    p.add_argument('--rtl-root',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--prepare-only',action='store_true')
    p.add_argument('--model',type=Path,default=BASE/'secondary_pcb_cnn_retrain_20261027/model/fc3_remote_detail_selected')
    p.add_argument('--padding-mode',choices=('zero','legacy_address0'),default='zero')
    args=p.parse_args()
    out=args.output.resolve();out.mkdir(parents=True,exist_ok=False)
    root=args.rtl_root.resolve()
    model=args.model.resolve()
    data=BASE/'secondary_link_stability_20261020/model/fast_strict160_dataset'
    npath=BASE/'cnn_dualhead_scratch_20261015_r6/tools/network.py'
    network=load_module('network_remote_check',npath)
    params=json.loads((model/'quantization.json').read_text())
    assert params['conv_shifts']==[10,8] and params['fc_conf_shift'][0]==8 and 0<=params['fc_conf_shift'][1]<=31 and params['shape_mode']=='max_rgb'
    if (model/'quantized.npz').is_file():
        pack=np.load(model/'quantized.npz')
        w=[pack[f'w{i}'] for i in range(3)];b=[pack[f'b{i}'] for i in range(3)]
    else:
        wr=np.asarray([int(x,16) for x in (model/'weights.mem').read_text().split()],dtype=np.uint8).view(np.int8)
        br=np.asarray([int(x,16) for x in (model/'biases.mem').read_text().split()],dtype=np.uint32).view(np.int32)
        w=[wr[:72].reshape(8,1,3,3),wr[72:1224].reshape(16,8,3,3),wr[1224:].reshape(3,4096)]
        b=[br[:8],br[8:24],br[24:]]
    wf=np.concatenate([x.ravel() for x in w]);bf=np.concatenate(b)
    assert len(wf)==13512 and len(bf)==27
    assert np.array_equal(wf.astype(np.uint8),np.asarray([int(x,16) for x in (model/'weights.mem').read_text().split()],dtype=np.uint8))
    assert np.array_equal(bf.astype(np.uint32),np.asarray([int(x,16) for x in (model/'biases.mem').read_text().split()],dtype=np.uint32))
    cache=np.load(data/'images_strict160.npz');images=cache['images'].astype(np.uint8);labels=cache['labels'].astype(np.int64)
    rows=json.loads((data/'records.json').read_text(encoding='utf-8'))['rows']
    torch.set_num_threads(4);torch.set_num_interop_threads(1);cv2.setNumThreads(1)
    full=network.integer_scores(images,w,b,params)
    soft_metrics=network.metrics(full,labels)
    cases=[];case_rows=[]
    for cid in range(1,10):
        ids=[i for i,r in enumerate(rows) if int(r['class_id'])==cid]
        # Pick an existing small-ROI captured frame and retain its provenance.
        ii=min(ids,key=lambda i: int(rows[i]['roi_side']))
        rng=np.random.default_rng(20261029+cid)
        for level,img in [('native',images[ii]),('mild_synthetic',detail(images[ii],rng,(.72,.84))),('strong_synthetic',detail(images[ii],rng,(.40,.54)))]:
            cases.append(img);case_rows.append({'source_index':ii,'class_id':cid,'detail':level,'record':rows[ii]})
    cases=np.stack(cases)
    shape,features,colors,logits,ci,si,cc,sc=make_features(cases,w,b,params,network,args.padding_mode)
    if args.padding_mode=='zero':
        assert np.array_equal(np.c_[colors,logits].astype(np.int32),network.integer_scores(cases,w,b,params))
    packed=(cases[...,0].astype(np.uint32)<<16)|(cases[...,1].astype(np.uint32)<<8)|cases[...,2].astype(np.uint32)
    hexfile(out/'pixels.mem',packed,6);hexfile(out/'shape.mem',shape,2)
    hexfile(out/'feature1.mem',features[0],2);hexfile(out/'feature2.mem',features[1],2)
    expected=np.c_[logits,colors,ci+1,si+1,cc,sc];hexfile(out/'results.mem',expected,8)
    for i,r in enumerate(case_rows):
        r.update(logits=logits[i].tolist(),color_sums=colors[i].tolist(),rtl_class_id=int(ci[i]*3+si[i]+1),color_conf=int(cc[i]),shape_conf=int(sc[i]),
                 legacy_shape_conf_shift7=int(min(255,(np.sort(logits[i])[-1]-np.sort(logits[i])[-2])>>7)))
    sources=[root/'01_rtl'/f for f in ('cnn_core.v','vision_workspace.v','vision_shared_mac.v')]
    paths=sources+[model/f for f in ('MODEL.json','quantization.json','weights.mem','biases.mem')]+[npath,data/'images_strict160.npz',data/'records.json',BASE/'secondary_pcb_cnn_retrain_20261027/train_remote_detail.py']
    vp=root/'01_rtl/vision_pipeline.v'
    if vp.is_file():
        pipeline_text=vp.read_text(encoding='utf-8')
        instance = re.search(r'cnn_core\s*#\((.*?)\)\s*classifier\s*\(', pipeline_text, re.S)
        assert instance, 'production classifier instance not found'
        override=re.search(r'\.FC_CONF_SHIFT\s*\(\s*(\d+)\s*\)',instance[1])
        effective_shift=int(override[1]) if override else 7
        assert effective_shift==params['fc_conf_shift'][1], f'production confidence shift={effective_shift}, model={params["fc_conf_shift"][1]}'
        paths.append(vp)
    if (model/'quantized.npz').is_file():paths.append(model/'quantized.npz')
    hashes={str(x):sha(x) for x in paths}
    bench=BENCH.replace('@CASES@',str(len(cases))).replace('@CONF_SHIFT@',str(params['fc_conf_shift'][1])).replace('@WEIGHTS@',(model/'weights.mem').as_posix()).replace('@BIASES@',(model/'biases.mem').as_posix())
    (out/'tb_remote_detail.sv').write_text(bench,encoding='utf-8')
    hashes[str(out/'tb_remote_detail.sv')]=sha(out/'tb_remote_detail.sv')
    report={'status':'REFERENCE_READY','full_native_1170':soft_metrics,'rtl_case_count':len(cases),'case_rows':case_rows,
       'contract':params,'padding_mode':args.padding_mode,'rom_layout_match':True,'input_hashes':hashes,
       'limitations':['1170 source frames overlap training/development; not independent test accuracy.','Mild/strong remote cases are synthetic detail loss; no independently captured distant frames supplied.','These tests do not prove candidate localization or board accuracy.']}
    (out/'REFERENCE_REPORT.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    print(f'REFERENCE READY native metrics={soft_metrics["joint_correct"]}/1170, RTL cases={len(cases)}',flush=True)
    if args.prepare_only:return
    license_path=TOOLS/'LICENSE.TXT';assert license_path.is_file()
    env=os.environ.copy();env.update(MGLS_LICENSE_FILE=str(license_path),LM_LICENSE_FILE=str(license_path))
    cmds=[('vlib',[str(TOOLS/'vlib.exe'),'work']),('lint',[str(TOOLS/'vlog.exe'),'-sv','-lint',*map(str,sources),str(out/'tb_remote_detail.sv')]),
       ('simulation',[str(TOOLS/'vsim.exe'),'-c','-quiet','-lib','work','tb_remote_detail','-do','onerror {quit -code 1}; run -all; quit -code 0'])]
    for name,cmd in cmds:
        log=out/f'{name}.log'
        with log.open('w',encoding='utf-8') as f:run=subprocess.run(cmd,cwd=out,env=env,stdout=f,stderr=subprocess.STDOUT)
        txt=log.read_text(encoding='utf-8',errors='replace')
        if run.returncode or re.search(r'\*\*\s+(?:Error|Fatal):',txt) or (name=='simulation' and 'PASS ALL CNN REMOTE DETAIL' not in txt):
            report['status']='FAIL';report['failed_stage']=name
            (out/'RESULTS.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
            raise SystemExit(f'{name} failed: {log}')
        print(f'PASS {name}',flush=True)
    assert all(sha(x)==v for x,v in hashes.items())
    report['status']='PASS';report['simulation_cases_passed']=len(re.findall(r'PASS CNN CASE',txt))
    (out/'RESULTS.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    print(f'PASS RTL + integer golden: {len(cases)} cases')


if __name__=='__main__':main()
