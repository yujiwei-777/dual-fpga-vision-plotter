"""Run the existing complete motion pipeline regression in a fresh directory."""
from pathlib import Path
import argparse,hashlib,json,os,re,subprocess
ROOT=Path(__file__).resolve().parents[1]
def run(out):
    out=out.resolve();out.mkdir(parents=True,exist_ok=False)
    files=[ROOT/p for p in (
        'main/user_source/hdl_source/motion_post_hist_adapter.v',
        'main/user_source/hdl_source/isp/motion_detect.v',
        'main/user_source/hdl_source/isp/motion_region_select.v',
        'main/02_sim/tb_motion_post_hist_sensitive.sv')]
    hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
    env=os.environ.copy();env.update(MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT',LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT')
    for name,args in (
        ('vlib',['vlib.exe','sim']),
        ('lint',['vlog.exe','-sv','-lint','-work','sim',*map(str,files)]),
        ('simulation',['vsim.exe','-c','-quiet','-lib','sim','tb_motion_post_hist_sensitive','-do','onerror {quit -code 1}; run -all; quit -code 0'])):
        with (out/(name+'.log')).open('w') as log:
            p=subprocess.run(['E:/model/win64/'+args[0],*args[1:]],cwd=out,env=env,stdout=log,stderr=subprocess.STDOUT)
        text=(out/(name+'.log')).read_text(errors='replace')
        assert p.returncode==0 and not re.search(r'\*\* (?:Error|Fatal):',text),name
        if name=='simulation':assert re.search(r'\bPASS\b',text)
    assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==h for p,h in hashes.items())
    (out/'INPUTS.json').write_text(json.dumps(hashes,indent=2))
    (out/'RESULTS.json').write_text(json.dumps({'status':'PASS'},indent=2))
    print('PASS motion regression')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);run(p.parse_args().output)
