from pathlib import Path
import subprocess,sys,json,datetime
ROOT=Path(__file__).resolve().parents[1]
stamp=datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
out=ROOT/'reports/preserved_suite_runs'/stamp;out.mkdir(parents=True)
rows=[]
jobs=[('preserved',['tools/run_r4_preserved_regressions.py','--run','E:/codex_secondary_plotter_idle_preflight_20261118_r2']),('document_integrated',['tests/operator_ui/run_doc_mapper_integrated.py']),('doc_total_ack',['tests/run_doc_total_ack.py']),('common_write',['tools/run_common_write_completion.py']),('paper_eject',['tools/run_paper_eject_regression.py']),('paper_document',['tools/run_paper_document_regression.py']),('paper_unlimited',['tools/run_paper_unlimited.py']),('no_suspect',['tools/run_no_suspect_paper.py']),('write_repeat',['tools/run_write_repeat_targeted.py']),('initial_uart',['tools/run_initial_uart.py']),('maintenance',['tools/run_unlimited_maintenance.py'])]
for name,args in jobs:
 log=out/('suite_'+name+'.log')
 with log.open('x',encoding='utf-8') as f:cp=subprocess.run([sys.executable,'-B',str(ROOT/args[0]),*args[1:]],cwd=ROOT,stdout=f,stderr=subprocess.STDOUT)
 rows.append(dict(name=name,returncode=cp.returncode,log=str(log)))
 (ROOT/'reports/CURRENT_TEST_INDEX.json').write_text(json.dumps(dict(status='RUNNING',commands=rows),indent=2),encoding='utf-8')
 print(name,cp.returncode,flush=True)
 if cp.returncode:raise SystemExit(cp.returncode)
(ROOT/'reports/CURRENT_TEST_INDEX.json').write_text(json.dumps(dict(status='PASS',commands=rows),indent=2),encoding='utf-8')
