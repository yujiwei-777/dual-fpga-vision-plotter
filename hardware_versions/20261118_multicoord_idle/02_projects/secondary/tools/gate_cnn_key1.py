"""Collect actual fresh current regression receipts for the existing signoff gate."""
from pathlib import Path
import json, subprocess, sys
ROOT=Path(__file__).resolve().parents[1]
BUILD=Path('E:/codex_secondary_plotter_idle_preflight_20261118_r2')
patterns={
 'preserved':'preserved_airwalk_r4/*/RESULTS.json',
 'document_integrated':'doc_mapper_r4/*/RESULT.json',
 'doc_total_ack':'doc_total_ack/*/RESULTS.json',
 'common_write':'common_write_completion/*/RESULTS.json',
 'paper_eject':'paper_eject/*/RESULTS.json',
 'paper_document':'paper_document/*/RESULTS.json',
 'paper_unlimited':'paper_unlimited/*/RESULTS.json',
 'no_suspect':'no_suspect_paper/*/RESULTS.json',
 'write_repeat':'write_repeat_targeted/*/current_fixed/RESULTS.json',
 'initial_uart':'initial_uart/*/RESULTS.json',
 'idle_monitor':'idle_monitor/*/RESULTS.json',
 'startup_retry':'startup_retry/*/RESULTS.json',
 'integrated_idle_uart':'integrated_idle_uart/*/RESULTS.json',
 'font_flow':'font_flow/*/RESULTS.json',
 'maintenance':'unlimited_maintenance/*/RESULTS.json',
 'center80':'doc_center80/*/RESULTS.json',
 'production_doc_feed':'production_doc_feed/*/RESULTS.json',
 'continuous_cnn_key1':'continuous_cnn_key1/*/RESULTS.json',
 'continuous_cnn_uart':'continuous_cnn_uart/*/RESULTS.json',
}
groups={}
for name,pattern in patterns.items():
    good=[p for p in (ROOT/'reports').glob(pattern)
          if json.loads(p.read_text(encoding='utf-8-sig')).get('status','').startswith('PASS')]
    assert good,(name,pattern)
    groups[name]=max(good,key=lambda p:p.stat().st_mtime)
command=[sys.executable,'-B',str(ROOT/'tools/signoff_airwalk.py'),'functional','--run',str(BUILD)]
for name,path in groups.items():command+=['--evidence',name+'='+str(path)]
out=ROOT/'reports/CURRENT_FUNCTIONAL_GROUPS.json'
out.write_text(json.dumps({k:str(p) for k,p in groups.items()},indent=2)+'\n',encoding='utf-8')
raise SystemExit(subprocess.run(command,cwd=ROOT).returncode)
