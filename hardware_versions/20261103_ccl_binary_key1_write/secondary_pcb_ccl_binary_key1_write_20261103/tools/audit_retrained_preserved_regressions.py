"""Bind freshly executed preserved-function regressions to frozen build r1.

Only current-run logs are accepted. Prior report PASS strings are not evidence.
No physical CDC/DDR or board quality claim is made by this report.
"""
from pathlib import Path
from datetime import datetime,timezone
import hashlib,json,re
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'reports/retrained/regressions'
FROZEN=Path('E:/codex_pcb_binary_ccl_retrained_20261102_r1')
EXPECTED='D64A5038FD648AC15855DCA02C769CE15EDCAA0553CF6D60E2BD8C7088545C73'
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
def load(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def write(p,v):Path(p).write_text(json.dumps(v,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
def main():
    manifest=FROZEN/'SOURCE_MANIFEST.json';assert sha(manifest)==EXPECTED
    frozen=load(manifest)['files'];rows=[];bindings={};limits=[]
    suites=[OUT/'preserved_r2'/x/'RESULTS.json' for x in ('plotter','hxa','document','ordinary','publication','controls','reader','key3')]
    suites += [OUT/'top_metadata_r1/top_metadata/RESULTS.json',OUT/'top_reset_r1/top_reset/RESULTS.json']
    for result in suites:
        r=load(result);assert r['status']=='PASS' and not r['source_drift'],result
        suite_bindings={};compiled=[];declarations=[];warnings=[]
        for path,digest in r['source_hashes'].items():
            p=Path(path);actual=p
            # The first completed runner revision was captured before the
            # tool was extended with two additional suites. Preserve its real
            # execution hash rather than treating the current tool as tested.
            if p==ROOT/'tools/run_retrained_preserved_regressions.py' and sha(p)!=digest:
                actual=OUT/'preserved_r2/RUNNER_AT_EXECUTION.py'
            assert actual.is_file() and sha(actual)==digest,('input drift',path,str(actual))
            if p.is_relative_to(ROOT):
                rel=p.relative_to(ROOT).as_posix()
                if rel in frozen:
                    assert frozen[rel]['sha256']==digest and sha(FROZEN/rel)==digest,('frozen mismatch',rel)
                    suite_bindings[rel]=digest;bindings[rel]=digest
        for cmd in r['commands']:
            assert cmd['status']=='PASS' and cmd['returncode']==0
            log=Path(cmd['log']);assert sha(log)==cmd['log_sha256'];text=log.read_text(encoding='utf-8-sig',errors='replace')
            assert not re.search(r'\*\*\s+(?:Error|Fatal):',text)
            warnings+=cmd.get('warnings',[])
            if Path(cmd['command'][0]).name.lower()=='vlog.exe':
                for token in cmd['command']:
                    if token.endswith(('.v','.sv')) and Path(token).is_relative_to(ROOT):
                        rel=Path(token).relative_to(ROOT).as_posix()
                        if rel in frozen:compiled.append(rel)
        declarations=sorted(set(suite_bindings)-set(compiled))
        rows.append(dict(name=result.parent.name if result.parent.name not in ('top_metadata','top_reset') else result.parent.name,path=str(result),sha256=sha(result),status='PASS',source_sha256=suite_bindings,compiled_production=sorted(set(compiled)),other_pinned_production_inputs=declarations,scope=r['scope'],limitations=r['limitations'],warning_count=len(warnings),warning_codes=sorted(set(re.findall(r'\((?:vsim|vlog|vopt)-\d+\)','\n'.join(warnings))))))
        limits+=r['limitations']
    ordinary=load(OUT/'preserved_r2/ordinary/integer27/RESULTS.json')
    assert ordinary['status']=='PASS' and ordinary['simulation_cases_passed']==ordinary['rtl_case_count']==27
    doc=load(OUT/'preserved_r2/document/RESULTS.json');assert len(doc['scope'])==8
    for name in ('blank2418','ink2358'):
        fixture=OUT/'preserved_r2/document/fixtures'/name
        assert (fixture/'gcode.txt').read_text().splitlines()==(fixture/'expected_gcode.txt').read_text().splitlines()
    publication=load(OUT/'preserved_r2/publication/RESULTS.json')
    assert publication['scope'][0]['records']==['PASS CNN_PUBLICATION_INTEGRATION checks=170 jobs=30 starts=32']
    assert any('PASS CNN_NAMED_TOP_ALL checks=57' in x for x in load(OUT/'top_metadata_r1/top_metadata/RESULTS.json')['scope'][0]['records'])
    # Source review is bound to the real current hardware constraints, while
    # physical pair mapping and timing remain the build owner's responsibility.
    review_files=['01_rtl/hxa_ddr_store.v','01_rtl/vision_pixel_reader.v','shared/rtl/hxa_packet_rx_fifo4.v','01_rtl/secondary_top.v','04_pin/apply_cdc_exceptions.tcl','04_pin/apply_reset_exceptions.tcl','main/user_source/hdl_source/reset_sync.v']
    review_hashes={rel:sha(ROOT/rel) for rel in review_files}
    for rel,digest in review_hashes.items():assert frozen[rel]['sha256']==digest and sha(FROZEN/rel)==digest
    store=(ROOT/'01_rtl/hxa_ddr_store.v').read_text();assert all(x in store for x in ['wack_sync<={wack_sync[0],wack}','rack_sync<={rack_sync[0],rack}','wreq_sync<={wreq_sync[0],wreq}','rreq_sync<={rreq_sync[0],rreq}','cal_sync<={cal_sync[0],calibrated}','command_accepted||(app_en&&app_rdy)','data_accepted||(app_wdf_wren&&app_wdf_rdy)'])
    review=dict(status='PASS_SOURCE_REVIEW_AND_BEHAVIORAL_REGRESSION_ONLY',source_sha256=review_hashes,scope=['Both mailbox request and acknowledgement toggles use two-stage synchronization; calibrated also passes through two stages.','Address/data hold registers stay in transaction mailboxes until acknowledgement; writes acknowledge only after both command and data handshakes.','Actual unequal-clock reader/mailbox suite and reset_sync suite executed on this source; packed FIFO test ran fresh.','Fail-closed physical mapping helper remains in current frozen constraints.'],required_external_evidence=['This report does not establish synchronizer placement, metastability MTBF, static CDC structural completeness or DDR PHY calibration.','Current routed CDC mapping/helper evidence, clocks/exceptions/DRC and vendor DDR checks must be supplied by this build.'],hardware='NOT_RUN')
    write(OUT/'CDC_FIFO_DDR_SOURCE_REVIEW.json',review)
    result=dict(status='PASS',generated_utc=datetime.now(timezone.utc).isoformat(),design=str(ROOT),frozen_build=str(FROZEN),source_manifest=dict(path=str(manifest),sha256=EXPECTED,status='PASS'),evidence=rows,source_sha256=bindings,static_review=dict(path=str(OUT/'CDC_FIFO_DDR_SOURCE_REVIEW.json'),sha256=sha(OUT/'CDC_FIFO_DDR_SOURCE_REVIEW.json'),status=review['status'],source_sha256=review_hashes),fresh_execution=True,limits=sorted(set(limits))+['No physical DDR/CDC signoff or real-board PASS supplied by this software regression report.','Earlier preserved_r1 contains simulator library invocation failures; preserved_r2 used corrected logical library names and all eight suites passed.','Missing optional/output testbench connections produce recorded ModelSim warnings; these are not silently treated as warning-free full-board lint.'],hardware='NOT_RUN')
    write(OUT/'PRESERVED_REGRESSIONS_BINDING.json',result)
    print(json.dumps(dict(status='PASS',evidence_suites=len(rows),production_files_bound=len(bindings),result=str(OUT/'PRESERVED_REGRESSIONS_BINDING.json'),sha256=sha(OUT/'PRESERVED_REGRESSIONS_BINDING.json')),indent=2))
if __name__=='__main__':main()
