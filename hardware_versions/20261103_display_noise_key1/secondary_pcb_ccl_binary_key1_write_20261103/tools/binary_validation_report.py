"""Seal this round's completed numerical/control evidence, excluding libraries."""
from pathlib import Path
import json,hashlib
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'reports/retrained/binary_validation'
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest().upper()
pipeline=OUT/'pipeline/run_20261102T144848_906613Z';adapter=OUT/'adapter/run_20261102T145517_147594Z'
pp=load(pipeline/'RESULTS.json');aa=load(adapter/'RESULTS.json');sw=load(OUT/'SOFTWARE_REPLAY.json')
assert pp['status']==aa['status']=='PASS' and pp['sources_unchanged'] and aa['sources_unchanged']
frozen=Path('E:/codex_pcb_binary_ccl_retrained_20261102_r1');manifest=load(frozen/'SOURCE_MANIFEST.json')['files']
checked={}
for rel,v in pp['frozen_design_inputs'].items():
    assert sha(frozen/rel)==v==manifest[rel]['sha256']==sha(ROOT/rel)
    checked[rel]=v
summary={'status':'PASS','contract':'CCL original box x1.00; unsigned source Y8 96x96; cfg 50434233','frozen_manifest_sha256':pp['frozen_manifest_sha256'],'software':sw,'pipeline':pp,'adapter':aa,'branch_and_frozen_match':checked,'coverage':{'selected_real_sources':15,'source_groups':5,'synthetic_pipeline_inputs':['blank','source_border','label_overflow'],'complete_frame_checks':22,'cancel_and_reentry_stages':['CCL accepted read','ROI accepted read','Conv2'],'adapter_control_tests':20,'all_CCL_addresses_per_frame':14400,'all_ROI_addresses_per_valid_frame':9216,'conv1_writes_per_valid_frame':9216,'conv2_writes_per_valid_frame':2304,'pool_checks_per_valid_frame':128},'limitations':['Diagnostic sources selected first/middle/last by group before scoring, not accuracy estimation or blind independent tests.','A selected GOOD returning FAIL and a true low-margin missing-pad REVIEW remain expected values; no tuning during verification.','Abstract pixel responses use 2..4 clocks; physical DDR and board timing are not covered.','Adapter controls shorten I/O timeout parameters; no terminal class/logit force.','Ordinary empty alternation covered here; full ordinary CNN numerical and feature regressions are separate.','Lint, synthesis, place/route, timing, DRC, reimport and bitgen are not claimed by this report.'],'hardware':'NOT_RUN'}
(OUT/'SUMMARY.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
readme='''# Retrained binary PCB numerical and safety verification

Status: PASS for the tests described here. Hardware: NOT_RUN.

Frozen source: E:/codex_pcb_binary_ccl_retrained_20261102_r1. Manifest SHA256 D64A5038FD648AC15855DCA02C769CE15EDCAA0553CF6D60E2BD8C7088545C73. RTL/model hashes were checked against that manifest before execution, stayed unchanged after execution, and equal the new independent branch. No previous run is counted as fresh evidence.

Contract: retrained binary C4/C4, original CCL half-open crop x1.00, unsigned source Y8 sampled to 96x96 using origin+floor((2*u+1)*span/192), config50434233. This is not the older x1.2 input contract. Model hashes are in SUMMARY.json.

The independent integer reference uses OpenCV four-connected CCL, explicit integer sampling and int64 convolution/pool/head with scalar spot checks. A second local flood-fill computes full CCL outputs independently of RTL. Fifteen frames were selected first/middle/last from five approved domain/subtype groups before inference. Raw SHA256, frame CRC32, dimensions, transport counters, metadata CCL and trained ROI hashes are checked. Address sweeps cover every axis span from1..1280 and1..720 with boundary/center origins.

Fullpipeline: 18 input fixtures (15real plus blank/source-border/overflow), three cancellation/reentry stages and ordinary empty-task alternation yield22 complete frame checks. Real vision_pipeline, CCL, adapter, shared workspace/MAC and classifier are simulated. All CCL addresses/masks, top4 boxes/areas,9216 ROI addresses/Y bytes, every Conv1/Conv2 write, pool, logits/class/score/margin/status, bbox/job/config and PCB validity fields are compared. Gates clear stale boxes and do not enter CNN. Localized defect fields remain zero. The true low-margin sample verifies REVIEW with pcb_checked=0.

Fresh fullpipeline evidence: pipeline/run_20261102T144848_906613Z/RESULTS.json (22frames,3cancels,ordinary empty PASS,0errors/warnings).

Fresh adapter evidence: adapter/run_20261102T145517_147594Z/RESULTS.json (20controls). Covers no candidate, overflow, invalid count, invalid model/frame, four source borders, malformed geometry, ready timeout, response timeout with late response, pending cancel with late drain/reentry, abort timeout lock, cancel before acceptance, active restart, truncation-largest policy and same-cycle response/cancel. Persistent locks reject restart and late-response unlock. Actual classifier/workspace/MAC are instantiated; classification outputs are never forced. I/O timeout parameters are shortened only in this isolated bench.

The15 selected real sources produce5PASS,9FAIL,1REVIEW; one GOOD is FAIL. They prove numerical equality, not high accuracy. The failure was retained without threshold/sample tuning. Grouped held-out quality and false-PASS limitations remain in the independent training audit.

Physical DDR, new capture quality, writing hardware, full ordinary CNN numerical regression, lint, CDC/FIFO/DDR system checks, synthesis, routing, DRC, reimport and bitgen are outside this report. No board success is claimed. SUMMARY.json and source/fixture SHA256 files bind exact evidence.
'''
(OUT/'README.md').write_text(readme,encoding='utf-8')
files=[p for p in OUT.rglob('*') if p.is_file() and p.name!='ARTIFACT_SHA256.json' and 'work' not in p.relative_to(OUT).parts]
files += [ROOT/'tools'/n for n in ['binary_validation_reference.py','binary_validation_pipeline.py','binary_validation_adapter.py',Path(__file__).name]]
(OUT/'ARTIFACT_SHA256.json').write_text(json.dumps({str(p):sha(p) for p in files},indent=2)+'\n',encoding='utf-8')
print(json.dumps({'status':'PASS','summary':str(OUT/'SUMMARY.json'),'sealed_files':len(files)},indent=2))
