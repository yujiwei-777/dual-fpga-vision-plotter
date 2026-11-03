"""Validate no-carry TH16 RTL evidence without changing production inputs."""
from pathlib import Path
import hashlib
import json
import re

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
FROZEN_SHA='B680381A4307D79BC6B259A8B33C177E5F2CD59120FF38EE902BC691438C20A0'
CANDIDATE_SHA='CD72245FA5CF73F16F35C2F655E5F13DD5F4949D14D258A7B99F9179AA219696'

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()

def log(p):
    b=p.read_bytes()
    return b.decode('utf-16' if b.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8',errors='replace')

def clean(text):
    assert 'Errors: 0, Warnings: 0' in text
    assert not re.search(r'\*\* (Warning|Error|Fatal)',text)
    assert not re.search(r'\bWarning\b',text,re.I)

def main():
    manifest=json.loads((HERE/'vectors_manifest.json').read_text())
    assert manifest['rtl_sha256']==FROZEN_SHA
    assert sha(HERE/'a4_display_spatial_nocarry.v')==CANDIDATE_SHA
    assert sha(ROOT/'model/display_spatial_reference.py')==manifest['reference_sha256']
    restored=(HERE/'a4_display_spatial_frozen.v').read_bytes().replace(b'module a4_display_spatial_frozen #(',b'module a4_display_spatial_h1 #(',1)
    assert hashlib.sha256(restored).hexdigest().upper()==FROZEN_SHA
    arithmetic=json.loads((HERE/'close_byte_check.json').read_text())
    assert arithmetic['status']=='PASS' and arithmetic['byte_pairs']==65536
    for name,h in arithmetic['source_sha256'].items():assert sha(HERE/name)==h
    clean(log(HERE/'compile.log'))
    results=[]
    for c in manifest['cases']:
        folder=HERE/c['name'];text=log(folder/'transcript.log');clean(text)
        assert 'PASS exhaustive RTL avg2 pairs=65536 TH16_byte_pairs=65536 TH16_rgb_channel_pairs=196608' in text
        match=re.search(r'PASS pixel oracle WIDTH=(\d+) HEIGHT=(\d+) cycles=(\d+) valid=(\d+) sof=(\d+) eol=(\d+).*frozen_all_cycles_including_invalid_data_equal',text)
        assert match,c['name']
        w,h,n,v,sof,eol=map(int,match.groups())
        assert (w,h,n,v)==(c['width'],c['height'],c['cycles'],c['source_pixels'])
        for filename,digest in c['inputs'].items():assert sha(folder/filename)==digest
        results.append(dict(name=c['name'],width=w,height=h,cycles=n,valid_pixels=v,sof=sof,eol=eol,
                            transcript_sha256=sha(folder/'transcript.log'),status='PASS',tags=c['tags']))
    names=['a4_display_spatial_nocarry.v','a4_display_spatial_frozen.v','close_byte_th16.vh','check_close_byte.py','close_byte_check.json',
           'ARITHMETIC_REVIEW.md','prepare_trial.py','tb_display_spatial.sv','run_nocarry.ps1','vectors_manifest.json','summarize_nocarry.py']
    report=dict(status='PASS',candidate_sha256=CANDIDATE_SHA,frozen_product_sha256=FROZEN_SHA,
                frozen_only_change='module name',reference_sha256=manifest['reference_sha256'],
                source_sha256={name:sha(HERE/name) for name in names},compile_sha256=sha(HERE/'compile.log'),cases=results,
                total_cycles=sum(c['cycles'] for c in results),total_valid_pixels=sum(c['valid_pixels'] for c in results),
                per_case_exhaustive_rtl=dict(avg2_byte_pairs=65536,th16_byte_pairs=65536,th16_rgb_channel_pairs=196608),
                independent_python_byte_pairs=65536,accepted_byte_pairs=arithmetic['accepted'],
                implementation='Boolean high-nibble equal/nonwrapping adjacent relations and explicit Boolean low-nibble ordering; threshold16 only. Same avg2, state, RAM and pipeline as frozen V5.',
                comparison='Every cycle: RGB and all five markers including invalid RGB; no unknown output. Active output checked against unchanged integer oracle; ENABLE=0 identity.',
                production_changed_during_trial=False,board_validation='NOT_RUN',physical_resources='Measure separately; no resource claim follows from Boolean source alone.')
    (HERE/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
    lines=['# No-carry TH16 comparator equivalence trial','',
           'Result: PASS, 11/11 cases. Product RTL and models were not changed by this trial. Board status: NOT_RUN.','',
           'Candidate SHA256: '+CANDIDATE_SHA,'Frozen V5 restored-name SHA256: '+FROZEN_SHA,'',
           'Only the EDGE_TH=16 RGB-neighbour predicate changes. For a=16*ah+al and b=16*bh+bl: equal high nibbles always pass; ah=bh+1 passes exactly when al<=bl; the reverse case uses al>=bl. A high-nibble gap of two or more cannot pass. Adjacent-high relations use explicit nonwrapping Boolean terms, and low-nibble ordering uses bit equality/less terms. There is no subtraction, addition or ordered comparison inside the fixed16 function. RGB still ANDs all three channel predicates. Generic non16 threshold behavior retains the original arithmetic branch.','',
           'The independent Python formula exhausts 65,536 byte pairs, including nonwrapping 0/255 boundaries, and accepts 8,176 pairs. In every RTL case, the testbench exhausts the new Boolean byte predicate against abs(a-b)<=16, checks the three RGB channel placements against frozen V5 (196,608 channel pairs), and checks avg2 on all 65,536 pairs. The stream comparison then checks all RGB and five markers every cycle including invalid RGB, rejects unknown output, and retains the unchanged independent integer-oracle/ENABLE=0 tests.','',
           'Frozen V5 differs only by module name; restoring that name reproduces the hash. Control, geometry, width-one forwarding, RAM organization, arithmetic averaging and marker pipeline are byte-identical. Vectors are independent copies from the prior combined trial, generated by the unchanged integer model, and all input hashes are checked. No canonical or historical evidence is overwritten.','',
           '| Case | Cycles | Active pixels | SOF | EOL |','|---|---:|---:|---:|---:|']
    for c in results:lines.append(f"| {c['name']} | {c['cycles']} | {c['valid_pixels']} | {c['sof']} | {c['eol']} |")
    lines += ['',f"Total: {report['total_cycles']:,} cycles; {report['total_valid_pixels']:,} active pixels.",'',
              'This establishes exact functional equivalence on the recorded cases and exhaustive byte predicates. It does not establish physical packing. Ordinary LUT usage may rise; a mapper could still choose carry resources despite Boolean source, so actual module/full-design synthesis and place are required. Threshold, RGB precision and image effect are unchanged; no additional camera/replay improvement is claimed.','',
              '| Evidence file | SHA256 |','|---|---|']
    for name,digest in report['source_sha256'].items():lines.append(f'| {name} | {digest} |')
    lines += ['',f"Compile log SHA256: {report['compile_sha256']}"]
    (HERE/'NOCARRY_VERIFICATION.md').write_text('\n'.join(lines)+'\n')
    print(json.dumps({k:report[k] for k in ('status','candidate_sha256','total_cycles','total_valid_pixels')}))

if __name__=='__main__':main()
