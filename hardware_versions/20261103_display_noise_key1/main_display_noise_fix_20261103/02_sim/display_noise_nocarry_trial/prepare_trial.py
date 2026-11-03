"""Build a self-contained comparator-only trial against the frozen V5 RTL."""
from pathlib import Path
import hashlib
import json
import re
import shutil

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
COMBINED=HERE.parent/'display_noise_combined_trial'
PRODUCT=ROOT/'01_rtl/imgq_gain_m/main/user_source/hdl_source/a4_display_spatial_h1.v'
FROZEN='B680381A4307D79BC6B259A8B33C177E5F2CD59120FF38EE902BC691438C20A0'

def main():
    source=PRODUCT.read_bytes()
    assert hashlib.sha256(source).hexdigest().upper()==FROZEN
    assert not (HERE/'a4_display_spatial_nocarry.v').exists()
    start=source.index(b'    function close_rgb;')
    end=source.index(b'    endfunction',start)+len(b'    endfunction')
    function=(HERE/'close_byte_th16.vh').read_bytes()
    replacement=function+b'''    function close_rgb;
        input [23:0] a,b;
        reg signed [8:0] dr,dg,db;
        begin
            if(EDGE_TH==16) begin
                close_rgb=close_byte_th16(a[23:16],b[23:16])&&
                          close_byte_th16(a[15:8],b[15:8])&&
                          close_byte_th16(a[7:0],b[7:0]);
            end else begin
                dr=$signed({1'b0,a[23:16]})-$signed({1'b0,b[23:16]});
                dg=$signed({1'b0,a[15:8]})-$signed({1'b0,b[15:8]});
                db=$signed({1'b0,a[7:0]})-$signed({1'b0,b[7:0]});
                close_rgb=within_edge(dr)&&within_edge(dg)&&within_edge(db);
            end
        end
    endfunction'''.replace(b'\n',b'\r\n')
    candidate=source[:start]+replacement+source[end:]
    (HERE/'a4_display_spatial_nocarry.v').write_bytes(candidate)
    candidate_sha=hashlib.sha256(candidate).hexdigest().upper()
    frozen=source.replace(b'module a4_display_spatial_h1 #(',b'module a4_display_spatial_frozen #(',1)
    (HERE/'a4_display_spatial_frozen.v').write_bytes(frozen)
    tb=(COMBINED/'tb_display_spatial.sv').read_bytes()
    before=b'                if(dut.avg2(aa[7:0],bb[7:0])!==frozen.avg2(aa[7:0],bb[7:0]))'
    additions=b'''                if(dut.close_byte_th16(aa[7:0],bb[7:0]) !== ((aa>bb)?(aa-bb<=16):(bb-aa<=16)))
                    $fatal(1,"TH16 Boolean predicate mismatch a=%0d b=%0d",aa,bb);
                if(dut.close_rgb({aa[7:0],16'h8080},{bb[7:0],16'h8080})!==frozen.close_rgb({aa[7:0],16'h8080},{bb[7:0],16'h8080}))
                    $fatal(1,"red TH16 mismatch a=%0d b=%0d",aa,bb);
                if(dut.close_rgb({8'h80,aa[7:0],8'h80},{8'h80,bb[7:0],8'h80})!==frozen.close_rgb({8'h80,aa[7:0],8'h80},{8'h80,bb[7:0],8'h80}))
                    $fatal(1,"green TH16 mismatch a=%0d b=%0d",aa,bb);
                if(dut.close_rgb({16'h8080,aa[7:0]},{16'h8080,bb[7:0]})!==frozen.close_rgb({16'h8080,aa[7:0]},{16'h8080,bb[7:0]}))
                    $fatal(1,"blue TH16 mismatch a=%0d b=%0d",aa,bb);
'''.replace(b'\n',b'\r\n')
    assert tb.count(before)==1
    tb=tb.replace(before,additions+before,1)
    tb=tb.replace(b'$display("PASS exhaustive RTL avg2 pairs=65536");',b'$display("PASS exhaustive RTL avg2 pairs=65536 TH16_byte_pairs=65536 TH16_rgb_channel_pairs=196608");',1)
    (HERE/'tb_display_spatial.sv').write_bytes(tb)
    runner=(COMBINED/'run_combined.ps1').read_bytes()
    runner=runner.replace(b'a4_display_spatial_combined.v',b'a4_display_spatial_nocarry.v').replace(FROZEN.encode(),candidate_sha.encode()).replace(b'combined_lib',b'nocarry_lib')
    (HERE/'run_nocarry.ps1').write_bytes(runner)
    manifest=json.loads((COMBINED/'vectors_manifest.json').read_text())
    manifest['rtl_sha256']=FROZEN
    manifest['vector_provenance']='Copied byte-for-byte from combined trial; unchanged integer algorithm and reference hash.'
    (HERE/'vectors_manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    for c in manifest['cases']:
        folder=HERE/c['name']
        assert not folder.exists()
        folder.mkdir()
        for filename in ('stim.mem','expected.mem','source.mem'):
            shutil.copyfile(COMBINED/c['name']/filename,folder/filename)
    print(json.dumps(dict(candidate_sha256=candidate_sha,frozen_sha256=FROZEN)))

if __name__=='__main__':main()
