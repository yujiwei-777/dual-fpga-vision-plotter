"""Supplement real-frame golden with constant inputs and explicit tie/margin cases."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

sys.dont_write_bytecode = True
import numpy as np
import torch
import run_cnn_remote_detail as base


DIRECTED = r'''
    integer checks=0, ticks;
    task classify;
      input signed [31:0] a,b,c;
      input [18:0] red,green,blue;
      input [1:0] ec,es;
      input [7:0] ecc,esc;
      begin
        @(negedge clk);
        dut.scores[0]=a;dut.scores[1]=b;dut.scores[2]=c;
        dut.color_sum[0]=red;dut.color_sum[1]=green;dut.color_sum[2]=blue;
        dut.state=4'd13;dut.busy=1;
        ticks=0;
        while(!done&&ticks<8) begin @(negedge clk);ticks=ticks+1;end
        if(!done||color_id!==ec||shape_id!==es||cc!==ecc||sc!==esc)
          $fatal(1,"Directed check %0d got color=%0d shape=%0d cc=%0d sc=%0d expected=%0d,%0d,%0d,%0d",checks,color_id,shape_id,cc,sc,ec,es,ecc,esc);
        checks=checks+1;
        $display("PASS CLASSIFY BOUNDARY %0d",checks);
        @(negedge clk);
      end
    endtask
    initial begin
      repeat(5) @(negedge clk);rst_n=1;
      // Exact public contracts: colors favor highest index, shapes lowest.
      classify(0,0,0, 0,0,0, 3,1,0,0);
      classify(-1,512,512, 100,100,0, 2,2,0,0);
      classify(-300,-20,-20, 0,256,256, 3,2,0,0);
      // Independent numeric expectations for shift8 and saturation, not a copy
      // of the implementation's sorting or shifting code.
      classify(511,0,-1, 256,0,0, 1,1,1,1);
      classify(512,0,-1, 0,512,0, 2,1,2,2);
      classify(130559,0,-1, 0,0,65279, 3,1,254,255);
      classify(130560,0,-1, 65280,0,0, 1,1,255,255);
      classify(131072,0,-1, 0,70000,0, 2,1,255,255);
      classify(-1,-513,-2000, 0,0,256, 3,1,1,2);
      classify(-2147483647,-2147483135,-2147483647, 20,20,20, 3,2,0,2);
      // Restore reset and classify again to check output-state recovery.
      @(negedge clk);rst_n=0;repeat(3) @(negedge clk);rst_n=1;
      classify(0,0,0, 0,0,0, 3,1,0,0);
      $display("PASS ALL CLASSIFY BOUNDARIES checks=%0d",checks);$finish;
    end
endmodule
'''


def main():
    p=argparse.ArgumentParser();p.add_argument('--rtl-root',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();root=a.rtl_root.resolve();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    model=root/'model/export';params=json.loads((model/'quantization.json').read_text());assert params['fc_conf_shift']==[8,8]
    q=np.load(model/'quantized.npz');w=[q[f'w{i}'] for i in range(3)];b=[q[f'b{i}'] for i in range(3)]
    network=base.load_module('network_boundary_check',base.BASE/'cnn_dualhead_scratch_20261015_r6/tools/network.py')
    torch.set_num_threads(4);torch.set_num_interop_threads(1)
    images=np.zeros((5,64,64,3),np.uint8);images[1]=255;images[2,:,:,0]=255;images[3,:,:,1]=255;images[4,:,:,2]=255
    shape,features,colors,logits,ci,si,cc,sc=base.make_features(images,w,b,params,network)
    assert ci.tolist()==[2,2,0,1,2] and cc.tolist()==[0,0,255,255,255]
    packed=(images[...,0].astype(np.uint32)<<16)|(images[...,1].astype(np.uint32)<<8)|images[...,2].astype(np.uint32)
    base.hexfile(out/'pixels.mem',packed,6);base.hexfile(out/'shape.mem',shape,2)
    base.hexfile(out/'feature1.mem',features[0],2);base.hexfile(out/'feature2.mem',features[1],2)
    base.hexfile(out/'results.mem',np.c_[logits,colors,ci+1,si+1,cc,sc],8)
    bench=base.BENCH.replace('@CASES@','5').replace('@CONF_SHIFT@','8').replace('@WEIGHTS@',(model/'weights.mem').as_posix()).replace('@BIASES@',(model/'biases.mem').as_posix())
    bench=bench.replace('f1count=0;f2count=0;', 'f1count=0;f2count=0; if(c==3) begin rst_n=0; repeat(3) @(negedge clk); rst_n=1; end')
    (out/'tb_remote_detail.sv').write_text(bench,encoding='utf-8')
    directed=bench[:bench.index('    reg [23:0] pixels')].replace('module tb_remote_detail;','module tb_classify_boundaries;')+DIRECTED
    (out/'tb_classify_boundaries.sv').write_text(directed,encoding='utf-8')
    sources=[root/'01_rtl'/f for f in ('cnn_core.v','vision_workspace.v','vision_shared_mac.v')]
    inputs=sources+[root/'01_rtl/vision_pipeline.v',model/'weights.mem',model/'biases.mem',model/'quantization.json',out/'tb_remote_detail.sv',out/'tb_classify_boundaries.sv']
    hashes={str(x):base.sha(x) for x in inputs}
    env=os.environ.copy();env.update(MGLS_LICENSE_FILE=str(base.TOOLS/'LICENSE.TXT'),LM_LICENSE_FILE=str(base.TOOLS/'LICENSE.TXT'))
    commands=[('vlib',[str(base.TOOLS/'vlib.exe'),'work']),('lint',[str(base.TOOLS/'vlog.exe'),'-sv','-lint',*map(str,sources),str(out/'tb_remote_detail.sv'),str(out/'tb_classify_boundaries.sv')])]
    for top in ('tb_classify_boundaries','tb_remote_detail'):
        commands.append((top,[str(base.TOOLS/'vsim.exe'),'-c','-quiet','-lib','work',top,'-do','onerror {quit -code 1}; run -all; quit -code 0']))
    for stage,cmd in commands:
        log=out/f'{stage}.log'
        with log.open('w',encoding='utf-8') as f:r=subprocess.run(cmd,cwd=out,env=env,stdout=f,stderr=subprocess.STDOUT)
        text=log.read_text(encoding='utf-8',errors='replace')
        if r.returncode or re.search(r'\*\*\s+(?:Error|Fatal):',text) or (stage.startswith('tb_') and 'PASS ALL' not in text):raise SystemExit(f'FAIL {stage}; {log}')
        print(f'PASS {stage}',flush=True)
    assert all(base.sha(path)==h for path,h in hashes.items())
    thresholds={'COLOR_MARGIN_MIN':0,'TRIANGLE_MARGIN_MIN':31,'CIRCLE_MARGIN_MIN':28,'SQUARE_MARGIN_MIN':77}
    pipeline=(root/'01_rtl/vision_pipeline.v').read_text(encoding='utf-8')
    for name,value in thresholds.items():assert re.search(r'parameter\s+integer\s+'+name+r'\s*=\s*'+str(value)+r'\b',pipeline)
    report={'status':'PASS','constant_input_inference_cases':5,'classify_boundary_checks':11,'mid_sequence_reset_before_case':3,
      'continuous_frame_reentry':True,'thresholds_unchanged':thresholds,'input_hashes':hashes,
      'constant_inputs':['black','white','red','green','blue'],'shape_logits':logits.tolist(),
      'expected_color_tie':'B > G > R','expected_shape_tie':'lowest shape index',
      'shape_shift_boundary_cases':[0,255,256,65279,65280,65536],
      'limitations':['Directed classification checks inject score registers to isolate tie/shift/saturation contracts; they do not replace 27 full real-frame inference cases.']}
    (out/'RESULTS.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print('PASS all CNN boundary checks')


if __name__=='__main__':main()
