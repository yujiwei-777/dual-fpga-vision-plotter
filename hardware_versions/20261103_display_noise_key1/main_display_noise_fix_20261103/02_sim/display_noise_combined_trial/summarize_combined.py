"""Bind combined RTL compression equivalence to frozen v4 and its oracle."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent
FROZEN_SHA='9FE7A1A5323340F854B312C1BBC33D72351D8065551878FA3A93A19469CF80EE'
CANDIDATE_SHA='B680381A4307D79BC6B259A8B33C177E5F2CD59120FF38EE902BC691438C20A0'

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest().upper()

def log(p):
    b=p.read_bytes()
    return b.decode('utf-16' if b.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8',errors='replace')

def clean(s):
    assert 'Errors: 0, Warnings: 0' in s
    assert not re.search(r'\*\* (Warning|Error|Fatal)',s)
    assert not re.search(r'\bWarning\b',s,re.I)

def main():
    manifest=json.loads((HERE/'vectors_manifest.json').read_text())
    assert manifest['rtl_sha256']==FROZEN_SHA
    assert sha(HERE/'a4_display_spatial_combined.v')==CANDIDATE_SHA
    frozen=(HERE/'a4_display_spatial_frozen.v').read_bytes()
    restored=frozen.replace(b'module a4_display_spatial_frozen #(',b'module a4_display_spatial_h1 #(',1)
    assert hashlib.sha256(restored).hexdigest().upper()==FROZEN_SHA
    proof=json.loads((HERE/'control_invariant.json').read_text())
    assert proof['status']=='PASS'
    results=[]
    for c in manifest['cases']:
        folder=HERE/c['name']
        text=log(folder/'transcript.log')
        clean(text)
        assert 'PASS exhaustive RTL avg2 pairs=65536' in text
        match=re.search(r'PASS pixel oracle WIDTH=(\d+) HEIGHT=(\d+) cycles=(\d+) valid=(\d+) sof=(\d+) eol=(\d+).*frozen_all_cycles_including_invalid_data_equal',text)
        assert match,c['name']
        w,h,n,v,sof,eol=map(int,match.groups())
        assert (w,h,n,v)==(c['width'],c['height'],c['cycles'],c['source_pixels'])
        for filename,digest in c['inputs'].items():
            assert sha(folder/filename)==digest,(c['name'],filename)
        results.append(dict(name=c['name'],width=w,height=h,cycles=n,valid_pixels=v,sof=sof,eol=eol,
                            transcript_sha256=sha(folder/'transcript.log'),status='PASS',tags=c['tags']))
    clean(log(HERE/'compile.log'))
    source_names=['a4_display_spatial_combined.v','a4_display_spatial_frozen.v','tb_display_spatial.sv',
                  'run_combined.ps1','summarize_combined.py','vectors_manifest.json','prove_control.py','control_invariant.json']
    report=dict(status='PASS',candidate_sha256=CANDIDATE_SHA,frozen_product_sha256=FROZEN_SHA,
                frozen_only_change='module name',reference_sha256=manifest['reference_sha256'],
                source_sha256={n:sha(HERE/n) for n in source_names},compile_sha256=sha(HERE/'compile.log'),
                cases=results,total_cycles=sum(c['cycles'] for c in results),
                total_valid_pixels=sum(c['valid_pixels'] for c in results),
                rtl_avg2_exhaustive_pairs_per_case=65536,
                control_invariant=proof,
                comparison='Every cycle: RGB and all five markers, including invalid RGB; reject X. Independent integer oracle on active pixels; ENABLE=0 identity.',
                production_changed=False,td_run=False,board_validation='NOT_RUN')
    (HERE/'verification.json').write_text(json.dumps(report,indent=2)+'\n')
    lines=['# Combined resource compression: independent equivalence trial','',
           'Result: PASS, 11/11 cases. Product RTL and models are unchanged. No TD run or board test.','',
           'Three exact transformations are combined:','',
           '1. Omit RAM forwarding for IMG_WIDTH>1; retain the original explicit forwarding for width one.',
           '2. Compute rounded average as (a>>1)+(b>>1)+(a[0]|b[0]), using an 8-bit result; avoid 9-bit sum plus one followed by truncation.',
           '3. Select the filtered result after the average instead of muxing its neighbour input: use ? avg2(C,N) : C. This is identical because avg2(C,C)=C.','',
           'Threshold16, all RGB8 precision, line RAM contents, control, two-stage marker pipeline and ENABLE=0 semantics remain unchanged. No image-quality parameter changes. The row RAM still stores horizontal pass H, never final vertical output.','',
           'Every RTL case first exhausts all 65,536 byte-pair inputs to the revised avg2 against the frozen RTL avg2. The stream test compares all output RGB bits and all five markers against the frozen product on every cycle, including invalid RGB. It rejects unknown output data and retains exact independent integer-oracle and ENABLE=0 tests. Restoring the frozen module name reproduces the recorded product SHA256.','',
           'Control invariant: for width>1, ordinary adjacent valid pixels read and write different addresses. End-of-row addresses also differ except for an incomplete single-pixel row, whose upper validity is false. SOF clears upper validity. DE gaps retire the pending write before another read; missing EOL clears row validity. Invalid output takes p_data because p_valid=0. Exhaustive reachable-state enumeration with arbitrary DE/SOF/EOL confirms zero unmasked collisions for widths2,3,7,16 and the tested heights. Width1 has genuine unmasked collisions, so forwarding is retained. The control proof is supplemental, not a replacement for RTL tests.','',
           '| Case | Cycles | Active pixels | SOF | EOL |','|---|---:|---:|---:|---:|']
    for c in results:
        lines.append(f"| {c['name']} | {c['cycles']} | {c['valid_pixels']} | {c['sof']} | {c['eol']} |")
    lines += ['',f"Total: {report['total_cycles']:,} cycles and {report['total_valid_pixels']:,} active pixels.",'',
              'Expected production savings include 25 forwarding registers, the forwarding comparator/mux, and an opportunity for simpler carry/MUX packing. Actual resources, placement and timing must be measured separately. This evidence proves output equivalence; historical image replay needs no recalculation because every output is unchanged. Board status remains NOT_RUN.','',
              '| File | SHA256 |','|---|---|']
    for n,digest in report['source_sha256'].items():
        lines.append(f'| {n} | {digest} |')
    lines += ['',f'Frozen restored-name SHA256: {FROZEN_SHA}',f"Compile log SHA256: {report['compile_sha256']}"]
    (HERE/'COMBINED_VERIFICATION.md').write_text('\n'.join(lines)+'\n')
    print(json.dumps({k:report[k] for k in ('status','candidate_sha256','total_cycles','total_valid_pixels')}))

if __name__=='__main__':
    main()
