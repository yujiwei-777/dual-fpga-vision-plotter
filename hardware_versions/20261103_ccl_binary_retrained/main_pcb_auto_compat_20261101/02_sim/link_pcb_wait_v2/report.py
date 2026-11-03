from pathlib import Path
import datetime
import hashlib
import json

r = Path(__file__).resolve().parents[2]
d = Path(__file__).resolve().parent
old = json.loads((r/'reports/recovered_link_pcb_wait_regression.json').read_text())
files = [r/'01_rtl/imgq_gain_m/shared/rtl/hxa_main_link.v',
         r/'01_rtl/imgq_gain_m/shared/rtl/hxa_packet_codec.v',
         d/'tb_link_pcb_wait.sv', d/'run.ps1', d/'compile.log', d/'transcript_batch_final.log']
hashes = {p.relative_to(r).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest().upper() for p in files}
log = (d/'transcript_batch_final.log').read_text()
assert 'PASS ALL packet-level PCB compatibility' in log
assert 'Errors: 0, Warnings: 0' in log and '** Fatal:' not in log
old.update(generated_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
    timer_implementation='independent 15-bit downcounter; active is reduction OR, not a flip-flop',
    process_exit_code=0, sha256=hashes, remaining_after_11_seconds=19000,
    cached_ack_remaining_before=25000, cached_ack_remaining_after=25000,
    previous_attempt='02_sim/link_pcb_wait/attempt1', test_directory='02_sim/link_pcb_wait_v2')
(r/'reports/recovered_link_pcb_wait_regression_v2.json').write_text(json.dumps(old, indent=2), encoding='utf-8')
report = '''# Countdown PCB wait regression v2

PASS: ModelSim batch exit 0; compiler and simulator both 0 errors / 0 warnings.

Full real packet regression was rerun against the independent downcounter. FRAME_ACK loads 30000ms; after 11000ms remaining is exactly 19000. Repeated prior-task Type8 during a new job at 25000ms remaining is ACKed without extending its deadline. Remaining=1 produces no premature cancellation; the next boundary cancels at exactly 30000ms with wire reason 12. Ordinary CNN remains 2000ms. Mode cancellation reason 5 and real 3-second lease loss reason 4 both pass.

Five complete 1280-packet frames / 6400 DATA, 188 heartbeats, 3 ACK, 5 CANCEL. No protocol-state force, no shortened frame; actual tick_ms at CLK_HZ=5000000. Physical CDC/DDR/PHY and board verification are separate acceptance steps.

Attempt 1 source/logs remain in 02_sim/link_pcb_wait/attempt1; v2 source, launcher, compile and final clean simulation logs are in 02_sim/link_pcb_wait_v2. Complete hashes are in the adjacent JSON report.
'''
(r/'reports/recovered_link_pcb_wait_regression_v2.md').write_text(report, encoding='utf-8')
print(json.dumps({'passed': True, 'link_sha256': hashes['01_rtl/imgq_gain_m/shared/rtl/hxa_main_link.v']}, indent=2))
