"""Run the prepared TD query against the completed DB without modifying it."""
import hashlib
import json
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RUN = ROOT / '01_rtl/imgq_gain_m/main/td_project_display_noise_v8'
DB = RUN / 'camera_to_dsi_display_720p60_cnn_multibox_gate.db'
SCRIPT = HERE / 'read_v8_parameters.tcl'
LOG = HERE / 'console_readback_v2.log'
RECEIPT = HERE / 'actual_readback_run_v2.json'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()

if LOG.exists() or RECEIPT.exists():
    raise SystemExit('Refusing to overwrite actual readback evidence')
if not (RUN / '.opt_gate.end.f').is_file() or (RUN / '.opt_gate.error.f').exists():
    raise SystemExit('Completed successful synthesis is required')
before = sha(DB)
script_hash = sha(SCRIPT)
with LOG.open('wb') as output:
    result = subprocess.run(['E:/td/bin/td_commands_prompt.exe', SCRIPT.as_posix()],
                            cwd=HERE, stdout=output, stderr=subprocess.STDOUT)
after = sha(DB)
receipt = {
    'db': str(DB), 'db_sha256_before': before, 'db_sha256_after': after,
    'db_unchanged': before == after,
    'script': str(SCRIPT), 'script_sha256': script_hash,
    'script_unchanged': script_hash == sha(SCRIPT),
    'log': str(LOG), 'log_sha256': sha(LOG),
    'process_exit_code': result.returncode,
    'readback_query_pass_marker': b'PARAM_READBACK_QUERY_MATCHES=6' in LOG.read_bytes(),
    'scope': 'Independent DB parameter query, not physical acceptance',
}
RECEIPT.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
print(json.dumps(receipt, indent=2))
raise SystemExit(0 if before == after and receipt['script_unchanged'] else 1)
