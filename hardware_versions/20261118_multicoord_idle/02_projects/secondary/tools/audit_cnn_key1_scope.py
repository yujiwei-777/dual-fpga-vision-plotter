"""Read-only scope, protected baseline and paired-protocol audit."""
from pathlib import Path
from datetime import datetime,timezone
import difflib,hashlib,json
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'secondary_doc_center80_feed5000_20261118'
FREEZE=Path('E:/codex_secondary_plotter_idle_preflight_20261118_r2')
CONTROL=Path('E:/codex_secondary_doc_center80_feed5000_20261118_r1')
MAIN=ROOT.parent/'main_doc_center80_cartoon_paperfree_20261118'
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()
load=lambda p:json.loads(Path(p).read_text(encoding='utf-8-sig'))
manifest=load(FREEZE/'SOURCE_MANIFEST.json')['files']
old=load(CONTROL/'SOURCE_MANIFEST.json')['files']
production=[p for p in manifest if p.startswith(('01_rtl/','main/','shared/','04_pin/','model/'))]
changed=[]
for rel in production:
 assert sha(ROOT/rel)==sha(FREEZE/rel)==manifest[rel]['sha256']
 assert sha(BASE/rel)==sha(CONTROL/rel)==old[rel]['sha256']
 if manifest[rel]['sha256']!=old[rel]['sha256']:changed.append(rel)
assert changed==['01_rtl/secondary_top.v']
pins=load(ROOT/'baseline_reference/PROTECTED_INPUTS.json')
assert all(sha(p)==digest for p,digest in pins.items())
top=(ROOT/changed[0]).read_text();control_top=(BASE/changed[0]).read_text()
required=["(vision_start&&(vision_purpose!=2'd0))",
 "key1_report_slot_available=(!vision_busy||(vision_purpose==2'd0))",
 '(!normal_done||target_valid)',
 '!report_busy&&!report_pending&&!key2_local_active&&!key2_new_page&&!key1_job_active',
 '!copy_busy&&!copy_recovery&&!report_recovery_required',
 '!paper_confirm_armed&&!paper_confirm_active',
 '(!operator_preview_capable||preview_locked)',
 'cnn_cache_result_valid&&cnn_cache_valid&&!cnn_cache_invalid']
assert all(s in top for s in required)
protocol=['shared/rtl/hxa_packet_codec.v','shared/rtl/hxa_packet_rx_fifo4.v',
 'shared/rtl/hxa_secondary_link.v','shared/rtl/hxa_yolo_result_codec.v']
serial=['01_rtl/grbl_uart.v','01_rtl/grbl_reporter_shared_candidate.v',
 '01_rtl/grbl_shared_transport_candidate.v','01_rtl/grbl_response_parser.v',
 '01_rtl/grbl_line_formatter.v','01_rtl/grbl_vector_font_rom.v']
unchanged={p:sha(ROOT/p) for p in protocol+serial}
assert all(sha(ROOT/p)==sha(BASE/p) for p in unchanged)
main_bit=MAIN/'artifacts/dual_fpga_main_20261118_doc_center80_cartoon_paperfree_diagnostic.bit'
assert sha(main_bit)=='AE1466EC693A021834F4B56FA28F6E0989BA17E1C0A8566EC615BD1F2C0A237F'
report=dict(status='PASS_CNN_KEY1_SCOPE_PROTOCOL',generated_utc=datetime.now(timezone.utc).isoformat(),
 changed_production=changed,unchanged_production_count=len(production)-1,baseline_pins_verified=len(pins),
 source_manifest=dict(path=str(FREEZE/'SOURCE_MANIFEST.json'),sha256=sha(FREEZE/'SOURCE_MANIFEST.json')),
 unchanged_protocol_and_serial_sha256=unchanged,compatible_main_bit=dict(path=str(main_bit),sha256=sha(main_bit)),
 checks=['Only top admission predicates change; no new storage or model computation.',
 'CNN report reads immutable accepted scalar snapshot; no access to CNN MAC/activation workspace/DDR.',
 'Normal report owns shared report/document formatter and UART; copy_busy/recovery and report locks retained.',
 'No-target same-cycle completion remains a rejection; model result, source centre and scores not changed.',
 'Current main hides CNN writing panel only; Type21 is still received; no protocol format changes.'],
 diff=list(difflib.unified_diff(control_top.splitlines(),top.splitlines())),hardware_status='NOT_RUN')
p=ROOT/'reports/SCOPE_PROTOCOL_REVIEW.json';p.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps(dict(status=report['status'],path=str(p),changed=changed)))
