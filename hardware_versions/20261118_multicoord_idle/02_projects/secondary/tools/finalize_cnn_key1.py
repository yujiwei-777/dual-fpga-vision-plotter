"""Publish only after current physical, functional and bitgen receipts pass."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'secondary_cnn_key1_live_snapshot_20261118'
BUILD=Path('E:/codex_secondary_plotter_idle_preflight_20261118_r2')
MAIN=ROOT.parent/'main_cnn_multicoord_20261118'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
load=lambda p:json.loads(Path(p).read_text(encoding='utf-8-sig'))
def evidence(p):return dict(path=str(p),sha256=sha(p))
def put(p,v):
 p.parent.mkdir(parents=True,exist_ok=True)
 p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

destination=ROOT/'artifacts/RELEASE_REPORT.json'
assert not destination.exists(),'Preserve prior release receipt'
bitgen=BUILD/'signoff/bitgen/BITGEN_RECEIPT.json'
bg=load(bitgen);assert bg['status']=='BITGEN_PASS' and bg['inputs_unchanged']
bit=Path(bg['artifact']['path']);assert sha(bit)==bg['artifact']['sha256']
plan=load(BUILD/'BUILD_PLAN.json');manifest=BUILD/'SOURCE_MANIFEST.json'
assert sha(manifest)==plan['source_manifest_sha256']==bg['source_manifest']['sha256']
gate=ROOT/'reports/airwalk_signoff'/BUILD.name/'FUNCTIONAL_GATE.json'
fg=load(gate);assert fg['status']=='PASS_CURRENT_FUNCTIONAL_GATE'
assert fg['source_manifest_sha256']==sha(manifest)
assert {'continuous_cnn_key1','continuous_cnn_uart','idle_monitor','startup_retry','integrated_idle_uart','font_flow'}<=fg['groups'].keys()
physical=BUILD/'signoff/readonly/PHYSICAL_REVIEW.json'
assert load(physical)['passed']
pre=BUILD/'signoff/PREBITGEN_GATE.json'
assert load(pre)['bitgen_allowed'] and load(pre)['source_manifest_sha256']==sha(manifest)
route=BUILD/'RELEASE_GATE.json';rg=load(route)
assert rg['passed']
assert all(rg['timing_ns'][k]>=0 for k in ('SWNS','HWNS'))
assert all(rg['timing_ns'][k]==0 for k in ('STNS','HTNS'))
for name,limit in [('slice',95),('eram',90),('dsp',95)]:assert rg['resources'][name]['percent']<limit
frozen=load(manifest)['files'];changes=[]
for rel,row in frozen.items():
 assert sha(BUILD/rel)==row['sha256'],rel
 if rel.startswith(('01_rtl/','shared/','main/','model/','04_pin/')):
  assert sha(ROOT/rel)==row['sha256'],rel
  if sha(BASE/rel)!=row['sha256']:changes.append(rel)
assert set(changes)=={'01_rtl/secondary_top.v','01_rtl/grbl_uart.v','01_rtl/grbl_reporter_shared_candidate.v'},changes
protected=load(ROOT/'baseline_reference/PROTECTED_INPUTS.json')
assert all(sha(p)==h for p,h in protected.items())
main_release=load(MAIN/'artifacts/RELEASE_REPORT.json')
assert main_release['status']=='PASS_DIAGNOSTIC_NOT_RUN' and main_release['inputs_unchanged']
main_bit=Path(main_release['bit']['path'])
assert sha(main_bit)==main_release['bit']['sha256']
value=dict(status='PASS_DIAGNOSTIC_NOT_RUN',hardware_status='NOT_RUN',
 bit=evidence(bit),bid=bg['bid'],source_manifest=evidence(manifest),bitgen_receipt=evidence(bitgen),
 functional_gate=evidence(gate),physical_signoff=evidence(physical),prebitgen_gate=evidence(pre),
 route_gate=evidence(route),post_bitgen_integrity=evidence(BUILD/'signoff/bitgen/POST_BITGEN_INTEGRITY.json'),
 timing_ns=rg['timing_ns'],resources=rg['resources'],inputs_unchanged=True,
 compatible_main_bit=evidence(main_bit),production_changes=changes,
 baseline_protected_inputs_verified=len(protected),completed_utc=datetime.now(timezone.utc).isoformat(),
 fix='KEY2 is admissible during ordinary CNN inference; idle UART status queries and stopped-state requalification prevent receive-only idle faults from permanently blocking writes; startup-only noise/late stopped status retries the full guarded handshake; exact connected glyph corners remain pen-down at F5000.',
 limitations=['Physical FPGA/GRBL operation remains NOT_RUN.',
 'No target, explicit cancel, mode/session change, competing task, paper maintenance and real UART/GRBL recovery remain admission barriers.',
 'Alarm, moving/unknown startup status and faults during active commands require explicit recovery. No automatic unlock, homing, G-code replay or coordinate reset after runtime faults.',
 'The physical startup/long-idle fault cause is not proven without real UART capture. Simulations cover identified lock paths.',
 'A capable paired main still samples the coherent preview before a local KEY1 report is admitted.',
 'Final GRBL ok is command acceptance, not physical motion completion.'])
put(destination,value)
put(ROOT/'reports/COMPLETION.json',value)
put(ROOT/'reports/PROGRESS.json',dict(status='COMPLETE_DIAGNOSTIC_NOT_RUN',bit=evidence(bit),compatible_main_bit=evidence(main_bit),hardware_status='NOT_RUN'))
print(json.dumps(dict(status=value['status'],bit=str(bit),sha256=sha(bit),timing_ns=rg['timing_ns'],resources=rg['resources']),ensure_ascii=False))
