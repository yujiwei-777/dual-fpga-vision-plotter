"""Bind new CART/luma checks and still-identical protocol regression evidence."""
from pathlib import Path
import argparse, hashlib, json, shutil
ROOT=Path(__file__).resolve().parents[1]
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def bundle(sim,out,hxa=None,motion=None,fifo=None):
    sim,out=sim.resolve(),out.resolve()
    hxa=hxa.resolve() if hxa else None
    motion=motion.resolve() if motion else None
    fifo=fifo.resolve() if fifo else None
    out.mkdir(parents=True,exist_ok=False)
    results=json.loads((sim/'REGRESSIONS.json').read_text())
    hashes=json.loads((sim/'INPUTS.json').read_text())
    for name in results:
        shutil.copy2(sim/(name+'.log'),out/(name+'.log'))
    previous=ROOT/'artifacts/cart_refine_20260925/evidence_a3'
    previous_hashes=json.loads((previous/'INPUTS.json').read_text())
    # Only reuse protocol/motion evidence when ALL its tracked inputs are exact.
    refreshed={}
    if hxa:
        hr=json.loads((hxa/'after/summary.json').read_text())
        assert hr['status']=='PASS'
        refreshed.update({Path(p).relative_to(ROOT).as_posix():h for p,h in hr['source_sha256'].items()})
    if motion:
        assert json.loads((motion/'RESULTS.json').read_text())['status']=='PASS'
        refreshed.update(json.loads((motion/'INPUTS.json').read_text()))
    for rel,digest in previous_hashes.items():
        if rel not in hashes:
            if rel in refreshed:continue
            assert sha(ROOT/rel)==digest, 'stale prior regression: '+rel
            hashes[rel]=digest
    hashes.update(refreshed)
    for name in ('hxa_integration','motion_sensitive'):
        if name=='hxa_integration' and hxa:log=hxa/'after/simulation.log'
        elif name=='motion_sensitive' and motion:log=motion/'simulation.log'
        else:
            assert json.loads((previous/'REGRESSIONS.json').read_text())[name]=='PASS'
            log=previous/(name+'.log')
        shutil.copy2(log,out/(name+'.log'))
        results[name]='PASS'
    if fifo:
        log=fifo/'simulation.log'
        assert 'PASS' in log.read_text() and '** Fatal:' not in log.read_text()
        for patch in json.loads((fifo/'PATCH_MANIFEST.json').read_text()):
            rel=patch['path'];assert sha(ROOT/rel)==patch['after_sha256']
            hashes[rel]=patch['after_sha256']
        for fn in ('tb_udp_metadata_fifo.sv','udp_pkg_buf_before.v'):
            path=fifo/fn;hashes[path.relative_to(ROOT).as_posix()]=sha(path)
        shutil.copy2(log,out/'udp_metadata_fifo.log');results['udp_metadata_fifo']='PASS'
    luma=ROOT/'artifacts/cart_closure_20260925/luma'
    lr=json.loads((luma/'RESULTS.json').read_text())
    rel='main/user_source/hdl_source/isp/isp_luma_stat.v'
    assert lr['simulation']=='PASS' and sha(ROOT/rel)==lr['sha256']
    hashes[rel]=lr['sha256']
    for fn in ('before.v','reference.v','tb.sv','check.py'):
        path=luma/fn; hashes[path.relative_to(ROOT).as_posix()]=sha(path)
    shutil.copy2(luma/'simulation.log',out/'luma_equivalence.log')
    results['luma_equivalence']='PASS'
    for rel,digest in hashes.items():assert sha(ROOT/rel)==digest,rel
    (out/'REGRESSIONS.json').write_text(json.dumps(results,indent=2))
    (out/'INPUTS.json').write_text(json.dumps(hashes,indent=2))
    print(json.dumps(results,indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--sim',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--hxa',type=Path);p.add_argument('--motion',type=Path);p.add_argument('--fifo',type=Path)
    a=p.parse_args();bundle(a.sim,a.output,a.hxa,a.motion,a.fifo)
