"""Fixed dirt ROI frontend only: independent integer and RTL comparison."""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys
import time
import numpy as np

ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('fixed_dirt_reference',ROOT/'fixed_dirt_reference.py')
ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref)
SIM=Path('E:/model/win64')

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()

def golden(y):
    # Count against a local threshold, independently of the min2 RTL/model.
    blocks=y.reshape(180,4,320,4).transpose(0,2,1,3)
    result=(blocks<=112).sum(axis=(-1,-2))>=2
    gx=np.arange(288,320);gy=np.arange(112,180)
    sums=np.zeros((68,32),np.int32)
    for oy in (-10,-2,6,14):
        for ox in (-10,-2,6,14):
            sums+=y[np.clip(gy*4+oy,0,719)[:,None],np.clip(gx*4+ox,0,1279)[None,:]]
    threshold=np.minimum(112,((sums+8)>>4)-12)
    result[112:180,288:320]=(blocks[112:180,288:320]<=threshold[...,None,None]).sum(axis=(-1,-2))>=2
    canvas=np.zeros((320,320),np.uint8);canvas[70:250]=result
    assert np.array_equal(canvas,ref.canvas(y))
    return canvas

def fixtures():
    yy,xx=np.mgrid[:720,:1280]
    dirt=np.clip(220-np.rint(145*np.exp(-((xx-1260)/100)**2-((yy-670)/160)**2)),0,255).astype(np.uint8)
    strokes=dirt.copy()
    strokes[600,1100:1280]=35;strokes[400:720,1200]=35
    for i in range(160):strokes[420+i,1120+i]=40
    strokes[672,1240:1242]=30
    strokes[620,1176:1178]=35
    contract=np.full((720,1280),220,np.uint8)
    # Single source pixels on four camera borders must never be multiplied
    # by the old endpoint/clamp mapping into a two-sample ink decision.
    for x,y in ((0,0),(1279,0),(0,719),(1279,719)):contract[y,x]=1
    # Second dark pixel arrives LAST (sample 15), before/after each ROI edge.
    for gx,gy in ((287,111),(288,111),(287,112),(288,112),(319,111),(319,112),(287,179),(288,179)):
        contract[4*gy+3,4*gx+2:4*gx+4]=45
    # Equal-valued minima are separate pixels. Isolated central grain is not.
    contract[300,400:402]=60;contract[304,404]=1
    # Wide dark regions remain unchanged outside the ROI; within it the
    # adaptive condition can suppress flat interiors (a documented tradeoff).
    contract[512:672,1120:1256]=40
    rng=np.random.default_rng(20261101)
    grain=np.clip(dirt.astype(np.int16)+np.rint(rng.normal(0,2,dirt.shape)).astype(np.int16),0,255).astype(np.uint8)
    for y in range(500,708,16):
        grain[y,1160:1270]=np.clip(grain[y,1160:1270].astype(np.int16)+np.arange(110)//8-6,0,255)
    inds=rng.choice(grain.size,800,replace=False);grain.ravel()[inds]=50
    grain[640,1232:1234]=30
    return {'strokes_on_fixed_dirt':strokes,'sample15_roi_border_contract':contract,
            'gray_gradient_grain':grain,'blank':np.full((720,1280),220,np.uint8)}

def main():
    out=ROOT/(sys.argv[1] if len(sys.argv)>1 else 'simulation')
    if out.exists():raise SystemExit('Use a fresh output directory to preserve evidence.')
    out.mkdir();lic=SIM/'LICENSE.TXT';assert lic.is_file()
    env=os.environ.copy();env.update(MGLS_LICENSE_FILE=str(lic),LM_LICENSE_FILE=str(lic))
    protected=[ROOT/x for x in ('doc_image_frontend.v','tb_frontend.sv','tb_timeout.sv','run_frontend.py','fixed_dirt_reference.py')]
    old=ROOT.parent.parent/'doc_ink_noise_diagnostic_20261101/candidate_frontend'
    protected.extend(old/x for x in ('doc_image_frontend.v','RESULTS.json'))
    base=ROOT.parent.parent/'secondary_cnn_key3_stroke_compact_20261101'
    protected.extend((base/'01_rtl').glob('doc*.v'))
    protected.append(base/'artifacts/dual_fpga_secondary_20261101_cnn_key3_stroke_compact_area_sclk_diagnostic.bit')
    hashes={str(p):sha(p) for p in protected}
    def run(name,args,marker=None):
        began=time.time()
        cp=subprocess.run(list(map(str,args)),cwd=out,env=env,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
        log=out/(name+'.log');log.write_text(cp.stdout,encoding='utf-8',errors='replace')
        (out/(name+'_command.json')).write_text(json.dumps({'argv':list(map(str,args)),
            'returncode':cp.returncode,'elapsed_seconds':round(time.time()-began,3),'log_sha256':sha(log)},indent=2),encoding='utf-8')
        if cp.returncode or re.search(r'\*\*\s+(?:Error|Fatal):',cp.stdout) or marker and marker not in cp.stdout:
            raise RuntimeError(name+' failed: '+cp.stdout[-6000:])
        return re.findall(r'PASS[^\r\n]*',cp.stdout)
    run('vlib',[SIM/'vlib.exe','simlib'])
    run('compile',[SIM/'vlog.exe','-sv','-lint','-work','simlib',ROOT/'doc_image_frontend.v',ROOT/'tb_frontend.sv',ROOT/'tb_timeout.sv'])
    cases={};captures={}
    for name,pattern in [('blank2418','*00002418*.yuyv'),('ink2358','*00002358*.yuyv')]:
        paths=list(Path('D:/ai/1/6').rglob(pattern));assert len(paths)==1
        cases[name]=ref.load_y(paths[0]);captures[name]={'path':str(paths[0]),'sha256':sha(paths[0])}
    cases.update(fixtures())
    results={}
    for name,y in cases.items():
        image_path=out/(name+'_y.mem');expected_path=out/(name+'_expected.mem');actual_path=out/(name+'_actual.mem')
        image_path.write_text(''.join(f'{int(v):02x}\n' for v in y.ravel()),encoding='ascii')
        want=golden(y);expected_path.write_text(''.join(f'{int(v)}\n' for v in want.ravel()),encoding='ascii')
        if name=='blank2418':assert want.sum()==0
        if name=='ink2358':assert want.sum()==1148
        if name=='sample15_roi_border_contract':
            assert want[70+111,287] and want[70+111,288] and want[70+112,287] and want[70+112,288]
            assert not want[70,0] and not want[70,319] and not want[249,0] and not want[249,319]
        checks=run(name,[SIM/'vsim.exe','-batch','-syncio','-quiet','-lib','simlib','tb_frontend',
            '+IMAGE='+str(image_path),'+EXPECTED='+str(expected_path),'+OUTPUT='+str(actual_path),'+CASE='+name,
            '-do','onerror {quit -code 1}; run -all; quit -f'],'PASS FRONTEND')
        got=np.array([int(v) for v in actual_path.read_text().splitlines()],np.uint8)
        assert got.size==102400 and np.array_equal(got,want.ravel())
        results[name]={'status':'PASS','checks':checks,'foreground':int(want.sum()),'requests':ref.EXPECTED_READS,
            'output_bits':102400,'expected_sha256':sha(expected_path),'actual_sha256':sha(actual_path)}
        print(name+': '+checks[-1],flush=True)
    actual=out/'lifecycle_actual.mem'
    checks=run('lifecycle',[SIM/'vsim.exe','-batch','-syncio','-quiet','-lib','simlib','tb_frontend',
        '+IMAGE='+str(out/'blank_y.mem'),'+EXPECTED='+str(out/'blank_expected.mem'),'+OUTPUT='+str(actual),
        '+CASE=lifecycle','+LIFECYCLE=1','-do','onerror {quit -code 1}; run -all; quit -f'],
        'PASS RESET_DIRTY_ROI_PENDING_AND_BLANK_REENTRY')
    values=np.array([int(v) for v in actual.read_text().splitlines()],np.uint8)
    assert values.size==204800 and not values.any()
    results['lifecycle']={'status':'PASS','checks':checks,'output_bits':204800,
        'dirty_source':'all-zero luma during partial frame before cancel/reset inside ROI background probes',
        'cancel_at_request':578069,'reset_at_request':578079}
    checks=run('timeout',[SIM/'vsim.exe','-batch','-syncio','-quiet','-lib','simlib','tb_timeout',
        '-do','onerror {quit -code 1}; run -all; quit -f'],'PASS TIMEOUT_PENDING_AND_CANCEL')
    results['timeout']={'status':'PASS','checks':checks}
    assert all(sha(p)==digest for p,digest in hashes.items()),'source/input drift'
    report={'status':'PASS','hardware_status':'NOT_RUN','scope':'Standalone fixed dirt ROI frontend, exact masks and per-cell request sequences, handshake and lifecycle.',
        'parameters':{'INK_THRESHOLD':112,'LOCAL_CONTRAST_DELTA':12,'DIRT_ROI_GRID':[288,319,112,179],
            'extra_probe_cells':2176,'requests_per_frame':ref.EXPECTED_READS,'extra_requests_percent':100*(ref.EXPECTED_READS-921600)/921600},
        'source_sha256':hashes,'raw_captures':captures,'tests':results,
        'limitations':['No pixel-level handwriting labels or physical plotter check.',
            'Fixed ROI is specific to current 1280x720 SC500 position and readout; movement invalidates calibration.',
            'Within ROI uniformly dark interiors may be suppressed; strong shadow edges may remain.',
            'Exact 4x4 replaces endpoint/clamped sampling; outside ROI threshold remains two pixels at Y<=112.',
            'No production integration, synthesis or bitgen is performed.']}
    (ROOT/'RESULTS.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('PASS FIXED DIRT FRONTEND SUITE',flush=True)

if __name__=='__main__':main()
