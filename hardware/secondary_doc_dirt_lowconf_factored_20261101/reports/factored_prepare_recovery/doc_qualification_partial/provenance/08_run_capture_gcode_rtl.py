# Adapted from the prior independently passing four-case capture G-code harness.
# Only fixed-region candidate/source request count changes; production backend is read-only.
"""Real captured YUYV -> frontend -> production planner -> simulated GRBL.

Uses current, unmodified backend RTL and compares every frontend canvas bit,
skeleton bit, planned point, machine coordinate and G-code byte with the
integer model. The simulated UART peer sends real parser inputs; no hardware.
"""
from pathlib import Path
import importlib.util
import json
import os
import re
import subprocess
from datetime import datetime,timezone
import numpy as np
import fixed_ink_reference as fixed
ref=fixed.original

OUT=fixed.ROOT/'capture_gcode_rtl'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
SIM=Path('E:/model/win64')
SPEC=importlib.util.spec_from_file_location('backend_suite',ref.BASE/'tools/run_stroke_split_regression.py')
suite=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(suite)

FE=r'''
reg fe_start=0;
wire fe_busy,fe_done,fe_error,fe_request;
wire [7:0] fe_error_code;
wire [10:0] fe_x;
wire [9:0] fe_y;
reg fe_valid=0,fe_pending=0;
wire fe_ready=(clocks%13!=5)&&!fe_pending;
reg [7:0] fe_luma;
reg [7:0] source_y[0:921599];
integer fe_latency=0,fe_address=0,fe_count=0,fe_requests=0;
doc_image_frontend fe(.clk(clk),.rst_n(rst_n),.start(fe_start),.cancel(cancel),
 .busy(fe_busy),.done(fe_done),.error(fe_error),.error_code(fe_error_code),
 .pixel_request(fe_request),.pixel_invalidate(),.pixel_x(fe_x),.pixel_y(fe_y),
 .pixel_ready(fe_ready),.pixel_valid(fe_valid),.pixel_luma(fe_luma),
 .ink_valid(load_valid),.ink_addr(load_addr),.ink_bit(load_bit),
 .ink_ready(load_ready),.corners());
always @(posedge clk)begin
 fe_valid<=0;
 if(rst_n)begin
   if(fe_request&&fe_ready)begin
     if(fe_x>1279||fe_y>719)$fatal(1,"frontend out-of-range source");
     fe_address=fe_y*1280+fe_x;fe_latency=2;fe_pending<=1;fe_requests=fe_requests+1;
   end else if(fe_pending)begin
     if(fe_latency>0)fe_latency=fe_latency-1;
     else begin fe_valid<=1;fe_luma<=source_y[fe_address];fe_pending<=0;end
   end
   if(load_valid&&load_ready)begin
     if(load_addr!==fe_count||load_bit!==image[fe_count])
       $fatal(1,"frontend bit mismatch address %0d expected index %0d",load_addr,fe_count);
     fe_count=fe_count+1;
   end
 end
end
'''

def bench():
    s=suite.BENCH
    s=s.replace('reg rst_n=0,start=0,cancel=0,load_valid=0,load_bit=0,emit_start=0;\nreg [16:0] load_addr=0;',
        'reg rst_n=0,start=0,cancel=0,emit_start=0;\nwire load_valid,load_bit;wire [16:0] load_addr;')
    a=s.index(' for(i=22400;i<80000;i=i+1)begin')
    b=s.index(' while(!prepared&&!error)begin',a)
    s=s[:a]+''' $readmemh("source_y.mem",source_y);
 @(negedge clk);fe_start=1;
 @(negedge clk);fe_start=0;
 while(!fe_done&&!fe_error)begin
   @(negedge clk);cycles=cycles+1;
   if(cycles>40000000)$fatal(1,"frontend watchdog");
 end
 if(fe_error||fe_count!=102400||fe_requests!=SOURCE_REQUESTS)
   $fatal(1,"frontend error/counts %0d %0d %0d",fe_error,fe_count,fe_requests);
 @(negedge clk);start=1;
 @(negedge clk);start=0;
'''+s[b:]
    s=s.replace('initial begin',FE+'\ninitial begin',1)
    s=s.replace('PASS STROKE_SPLIT full thin graph paths mapper Gcode','PASS CAPTURE_INTEGRATED frontend thin graph paths mapper Gcode')
    return s

def main():
    OUT.mkdir(parents=True,exist_ok=False)
    files=sorted(Path('D:/ai/1/6').rglob('*.yuyv'))
    selected=[next(p for p in files if p.name.startswith(stem)) for stem in ('frame_00002418_','frame_00002358_')]
    backend=[ref.BASE/'01_rtl'/n for n in ('doc_stroke_planner.v','doc_stroke_bram.v','doc_path_distance.v','doc_machine_map.v',
        'doc_grbl_plotter.v','doc_grbl_map.v','doc_grbl_streamer.v','doc_grbl_response_parser.v','grbl_line_formatter.v')]
    env=os.environ.copy();env.update(MGLS_LICENSE_FILE=str(SIM/'LICENSE.TXT'),LM_LICENSE_FILE=str(SIM/'LICENSE.TXT'))
    assert (SIM/'LICENSE.TXT').is_file()
    results={};hashes={str(p):ref.sha(p) for p in backend}
    def run(cwd,label,args,marker=None):
        p=subprocess.run([str(v) for v in args],cwd=cwd,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
        (cwd/(label+'.log')).write_text(p.stdout,encoding='utf-8',errors='replace')
        (cwd/(label+'_command.json')).write_text(json.dumps({'command':list(map(str,args)),'returncode':p.returncode},indent=2))
        assert p.returncode==0 and not re.search(r'\*\* (?:Error|Fatal):',p.stdout),p.stdout[-5000:]
        if marker:assert marker in p.stdout,p.stdout[-5000:]
        return p.stdout
    for path in selected:
        y=ref.load_y(path)
        for method in ('fixed_region',):
            case=path.stem[:14]+'_'+method;cwd=OUT/case;cwd.mkdir(exist_ok=False)
            front=(ref.BASE/'01_rtl/doc_image_frontend.v' if method=='released' else fixed.ROOT/'candidate_frontend/doc_image_frontend.v')
            assert front.is_file(),front
            image=ref.canvas(fixed.controls(y)[method]);g=ref.stroke.prepare(image,plan_passes=0)
            for name,array in (('input.mem',image),('skeleton.mem',g['skeleton']),('source_y.mem',y)):
                width=2 if name=='source_y.mem' else 1
                (cwd/name).write_text(''.join(f'{int(v):0{width}x}\n' for v in array.ravel()),encoding='ascii')
            stream=g['stream'];expected=suite.gcode(stream)
            (cwd/'expected.mem').write_text(''.join(f'{x|(yy<<9)|(s<<18)|(e<<19)|(d<<20):06x}\n' for x,yy,s,e,d in stream),encoding='ascii')
            (cwd/'expected_gcode.txt').write_text('\n'.join(expected)+'\n',encoding='ascii')
            const={key.upper():g[key] for key in ('edge_count','path_count','point_count','baseline_distance','planned_distance')}
            const.update(OPT_PASSES=0,LIMIT_EDGES=32768,LIMIT_PATHS=2048,LIMIT_POINTS=8192,EXPECT_ERROR=0,GCODE_LINES=len(expected),SOURCE_REQUESTS=fixed.REQUESTS)
            (cwd/'expected.vh').write_text('\n'.join(f'localparam {k}={v};' for k,v in const.items())+'\n',encoding='ascii')
            tb=cwd/'tb_capture_integrated.sv';tb.write_text(bench(),encoding='ascii')
            hashes[str(front)]=ref.sha(front);hashes[str(path)]=ref.sha(path)
            run(cwd,'vlib',[SIM/'vlib.exe','work'])
            run(cwd,'compile',[SIM/'vlog.exe','-sv','-lint','+define+DOC_BEHAVIORAL_RAM','-work','work',front,*backend,tb])
            log=run(cwd,'simulate',[SIM/'vsim.exe','-batch','-syncio','-quiet','-lib','work','tb_stroke_split','-do','onerror {quit -code 1}; run -all; quit -f'],'PASS CAPTURE_INTEGRATED')
            got=(cwd/'gcode.txt').read_text().splitlines();assert got==expected
            raw=[];points=[]
            for line in (cwd/'raw_paths.txt').read_text().splitlines():
                tag,a,b=line.split()
                if tag=='POINT':points.append((int(a),int(b)))
                else:
                    assert len(points)==int(b);raw.append(ref.stroke.Stroke(tuple(points),bool(int(a))));points=[]
            assert raw==g['strokes'] and not points
            results[case]={'status':'PASS','canvas_bits_checked':102400,'source_requests':const['SOURCE_REQUESTS'],
                'skeleton_bits_checked':57600,'paths':g['path_count'],'points':g['point_count'],
                'gcode_lines':len(got),'pen_down_commands':sum(line=='G1 Z+005.00 F01200' for line in got),
                'checks':re.findall(r'PASS[^\r\n]*',log)}
            print(case,results[case],flush=True)
    assert all(ref.sha(Path(p))==digest for p,digest in hashes.items()),'input drift'
    (OUT/'RESULTS.json').write_text(json.dumps({'status':'PASS','hardware_status':'NOT_RUN','input_sha256':hashes,'tests':results},indent=2),encoding='utf-8')

if __name__=='__main__':main()
