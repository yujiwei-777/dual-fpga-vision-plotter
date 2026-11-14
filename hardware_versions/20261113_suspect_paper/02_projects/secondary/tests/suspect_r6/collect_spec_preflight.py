"""Bind actual r6 regressions; physical reservations remain fail-closed."""
from pathlib import Path
from datetime import datetime, timezone
import json, sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
import collect_suspect_trial_gate as c
from suspect_gate_validation import EvidenceVerifier
RUN=Path('E:/codex_pcb_suspect_secondary_20261107_r6')
MANIFEST=RUN/'SOURCE_MANIFEST.json'
EXPECTED='7320972BB5D1E5234C401E90583DF9E4CFA1A28B70A2EC0B3376E8964164BE19'
assert c.sha(MANIFEST)==EXPECTED
frozen=c.load(MANIFEST)['files']
SPEC=ROOT/'tools/suspect_trial_evidence_spec.json'
CONFIG=ROOT/'tools/suspect_gate_config.json'
OUT=ROOT/'reports/suspect_trial'/('r6_functional_preflight_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
OUT.mkdir(parents=True,exist_ok=False)
(OUT/'SPEC_BEFORE.json').write_bytes(SPEC.read_bytes())
(OUT/'CONFIG_BEFORE.json').write_bytes(CONFIG.read_bytes())
spec=c.load(SPEC);config=c.load(CONFIG)
suite=ROOT/'reports/suspect_trial/r6_functional_20261108T032137_389856Z'
publication=ROOT/'reports/suspect_trial/r6_publication_20261108T032909_287909Z'
core=ROOT/'reports/suspect_trial/r6_core_20261108T032233_164034Z'
report=ROOT/'reports/suspect_trial_report_center/20261108T032350_063744Z'
key2=ROOT/'reports/doc_key1/key2_center/20261108T032352_550623Z'
key1=ROOT/'reports/suspect_trial_key1/20261108T032433_063459Z'
unit=ROOT/'reports/doc_key1_unit/run_20261108T032433_050458Z'
integrated=ROOT/'reports/doc_key1/integrated/20261108T032433_088861Z'
document=ROOT/'reports/suspect_trial/r6_document_symbolic_20261108T032625_073686Z'
uart=ROOT/'reports/suspect_trial/r5_uart_production_independent/20261108T024207_778070Z'
physical=ROOT/'reports/suspect_trial/physical_r6/CURRENT_CDC_DDR.json'
def log(p,marker):return dict(path=str(p),pass_marker=marker)
def setcat(name,reports,logs):
    row=spec['categories'][name]
    row['reports']=list(dict.fromkeys(map(str,reports)))
    row['logs']=logs
    row['required_sources']=config['required_sources'][name]
setcat('ordinary_cnn',[suite/'ordinary/integer27/RESULTS.json',publication/'RESULTS.json',suite/'top_metadata/RESULTS.json'],[
    log(suite/'ordinary/integer27/simulation.log','PASS ALL CNN REMOTE DETAIL cases=27'),
    log(publication/'publication_simulation.log','PASS CNN_PUBLICATION_INTEGRATION')])
setcat('pcb',[suite/'pipeline/RESULTS.json',suite/'adapter/RESULTS.json',core/'RESULT.json'],[
    log(suite/'pipeline/pipeline_simulation.log','BINARY_FULLPIPELINE_GOLDEN_PASS frames=13 cancels=4'),
    log(suite/'adapter/adapter_simulation.log','SUSPECT_ADAPTER_GOLDEN_PASS tests=24'),
    log(core/'simulation.log','SUSPECT_CORE_GOLDEN_PASS tests=22')])
setcat('suspect_region',[core/'RESULT.json',suite/'adapter/RESULTS.json',suite/'pipeline/RESULTS.json',report/'RESULT.json',key1/'RESULTS.json',suite/'sharehold/RESULTS.json'],[
    log(core/'simulation.log','SUSPECT_CORE_GOLDEN_PASS tests=22'),
    log(suite/'pipeline/pipeline_simulation.log','BINARY_FULLPIPELINE_GOLDEN_PASS frames=13 cancels=4'),
    log(report/'simulation.log','SUSPECT_REPORT_REGRESSION_PASS cases=12'),
    log(key1/'snapshot_simulation.log','SUSPECT_KEY1_SNAPSHOT_PASS checks=21'),
    log(suite/'sharehold/sharehold_simulation.log','BINARY_FULLPIPELINE_GOLDEN_PASS frames=13 cancels=4')])
setcat('document',[document/'RESULTS.json',integrated/'RESULT.json',uart/'RESULT.json'],[
    log(document/'ink2358_simulation.log','PASS CAPTURE_INTEGRATED'),
    log(integrated/'confirm/simulation.log','DOC_KEY1_INTEGRATED_PASS points=351 lines=417'),
    log(uart/'case_0.log','UART_RX_MITER_PASS')])
setcat('doc_key1_confirm',[integrated/'RESULT.json',unit/'RESULT.json',suite/'controls/RESULTS.json'],[
    log(integrated/'confirm/simulation.log','DOC_KEY1_INTEGRATED_PASS points=351 lines=417'),
    log(unit/'simulation.log','DOC_FRESH_KEY1_REGRESSION_PASS cases=11 checks=67'),
    log(suite/'controls/key1_simulation.log','PASS KEY1 job guard')])
setcat('writing_key2',[key2/'RESULT.json',report/'RESULT.json',suite/'plotter/RESULTS.json',suite/'controls/RESULTS.json',uart/'RESULT.json'],[
    log(key2/'simulation.log','KEY2_ZERO_REGRESSION_PASS cases=15'),
    log(report/'simulation.log','SUSPECT_REPORT_REGRESSION_PASS cases=12'),
    log(suite/'plotter/transport_simulation.log','POSE7_PLOTTER_REGRESSION_PASS cases=13'),
    log(uart/'case_0.log','UART_RX_MITER_PASS')])
setcat('cancel_reentry',[suite/'pipeline/RESULTS.json',suite/'controls/RESULTS.json',suite/'key3/RESULTS.json',suite/'top_reset/RESULTS.json',suite/'hxa/RESULTS.json',suite/'reader/RESULTS.json',key1/'RESULTS.json',suite/'plotter/RESULTS.json',uart/'RESULT.json'],[
    log(suite/'pipeline/pipeline_simulation.log','BINARY_FULLPIPELINE_GOLDEN_PASS frames=13 cancels=4'),
    log(suite/'controls/top_control_simulation.log','POSE7_TOP_CONTROL_PASS checks=50'),
    log(suite/'top_reset/top_reset_simulation.log','PASS KEY3_TOP_RESET_ALL checks=26'),
    log(suite/'hxa/tb_pose7_hxa_crc_network.log','POSE7_HXA_CRC_NETWORK_PASS cases=11'),
    log(suite/'reader/reader_mailbox_simulation.log','POSE7_REAL_READER_PASS cases=12'),
    log(suite/'plotter/transport_simulation.log','POSE7_PLOTTER_REGRESSION_PASS cases=13'),
    log(uart/'case_0.log','UART_RX_MITER_PASS')])
setcat('fifo',[suite/'hxa/RESULTS.json',suite/'controls/RESULTS.json',suite/'top_reset/RESULTS.json',physical],[
    log(suite/'hxa/tb_pose7_fifo4.log','POSE7_FIFO4_PASS:'),
    log(suite/'hxa/tb_pose7_hxa_crc_network.log','POSE7_HXA_CRC_NETWORK_PASS cases=11'),
    log(suite/'controls/top_control_simulation.log','POSE7_TOP_CONTROL_PASS checks=50'),
    log(suite/'top_reset/top_reset_simulation.log','PASS KEY3_TOP_RESET_ALL checks=26')])
setcat('ddr',[suite/'reader/RESULTS.json',physical],[log(suite/'reader/reader_mailbox_simulation.log','POSE7_REAL_READER_PASS cases=12')])
setcat('cdc',[physical],[log(RUN/'signoff/readonly/console_readonly.log','TD_READONLY_REIMPORT_PASS'),log(RUN/'signoff/readonly/current_cdc_mapping.rpt','CURRENT_PHYSICAL_CDC_READONLY_PASS')])
config['toolchain_extra']=list(dict.fromkeys(config['toolchain_extra']+[
    'tests/suspect_r6/collect_spec_preflight.py','tests/suspect_r6/run_current.py',
    'tests/suspect_r6/run_core.py','tests/suspect_r6/run_document.py','tests/suspect_r6/run_publication.py',
    'tools/run_retrained_preserved_regressions.py','tools/run_suspect_report_regression.py',
    'tools/run_suspect_key1_snapshot.py','tools/run_doc_key1_integrated.py',
    'tools/run_doc_key1_key2_regression.py','tools/run_doc_key1_unit.py']))
c.put(CONFIG,config);c.put(SPEC,spec)
categories={};union={};all_files=set()
for name in ('ordinary_cnn','pcb','suspect_region','document','doc_key1_confirm','writing_key2','cancel_reentry'):
    row=spec['categories'][name];sources={};verified=set();bound_logs=set();reports=[]
    strict=EvidenceVerifier(ROOT,RUN,config)
    try:
        for filename in row['reports']:
            path=Path(filename);value=c.load(path)
            c.report_pass(value,path)
            strict.hashed(path,c.sha(path),report=True)
            c.tested_inputs(value,path.parent,frozen,sources,verified,bound_logs)
            reports.append(dict(path=str(path),sha256=c.sha(path)))
        for entry in row['logs']:
            path=Path(entry['path']);digest=c.sha(path)
            assert (path,digest) in bound_logs,'Unbound selected log '+str(path)
            text=path.read_text(encoding='utf-8-sig',errors='replace')
            assert entry['pass_marker'] in text and not c.BAD_LOG.search(text),'Log marker/error '+str(path)
        selected=[dict(path=entry['path'],sha256=c.sha(entry['path']),pass_marker=entry['pass_marker']) for entry in row['logs']]
        strict.logs(selected,SPEC)
        assert strict.unpaired_log_hashes<=set(strict.checked.values()),'Unpaired raw log hash'
        assert set(row['required_sources'])<=set(sources),'Missing tested sources '+str(sorted(set(row['required_sources'])-set(sources)))
        categories[name]=dict(status='PASS',reports=reports,sources=sources,verified_files=len(verified),
            strict_recursive_verified_files=len(strict.checked),strict_recursive_json_files=len(strict.visited_json),selected_logs=selected)
        union.update(sources);all_files.update(verified)
    except Exception as exc:categories[name]=dict(status='FAIL',error=str(exc))
    print(name+' '+categories[name]['status'],flush=True)
    if categories[name]['status']=='FAIL':print(categories[name]['error'],flush=True)
missing=set(config['changed_sources'])-set(union)
passed=all(row['status']=='PASS' for row in categories.values()) and not missing
result=dict(status='PASS_SEVEN_FUNCTIONAL_CATEGORIES' if passed else 'FAIL',
    source_manifest=str(MANIFEST),source_manifest_sha256=EXPECTED,categories=categories,source_sha256=union,
    all_verified_files=len(all_files),missing_changed_sources=sorted(missing),
    spec=dict(path=str(SPEC),sha256=c.sha(SPEC)),config=dict(path=str(CONFIG),sha256=c.sha(CONFIG)),
    runner=dict(path=str(Path(__file__)),sha256=c.sha(Path(__file__))),
    collect_tool=dict(path=str(ROOT/'tools/collect_suspect_trial_gate.py'),sha256=c.sha(ROOT/'tools/collect_suspect_trial_gate.py')),
    recursive_verifier='EvidenceVerifier hashes/walk/status/logs for every raw selected report; historical dependencies never skipped.',
    physical_signoff='NOT_RUN_BY_THIS_PREFLIGHT',hardware='NOT_RUN',localization_accuracy='EXPLORATORY_NOT_PASSED')
c.put(OUT/'RESULT.json',result)
c.put(OUT/'PRODUCTION_COVERAGE.json',dict(status='PASS' if not missing else 'FAIL',source_manifest_sha256=EXPECTED,
    changed_sources=config['changed_sources'],covered_source_sha256=union,missing_changed_sources=sorted(missing)))
print(json.dumps(dict(status=result['status'],report=str(OUT/'RESULT.json'),sha256=c.sha(OUT/'RESULT.json'))),flush=True)
raise SystemExit(0 if passed else 1)
