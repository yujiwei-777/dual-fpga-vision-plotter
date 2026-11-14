from pathlib import Path
from datetime import datetime,timezone
import importlib.util,json
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('runner',ROOT/'tools/run_retrained_preserved_regressions.py')
h=importlib.util.module_from_spec(spec);spec.loader.exec_module(h)
out=ROOT/'reports/actions'/datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ')
r=h.Run(ROOT,out);error=None
try:
    r.sim('key1',[ROOT/'01_rtl/secondary_top.v',ROOT/'tests/tb_key1_actions.sv'],
          'tb_key1_actions','KEY1_ACTIONS_PASS')
    r.sim('key1_min_timing',[ROOT/'01_rtl/secondary_top.v',ROOT/'tests/key1_reference.sv',ROOT/'tests/tb_key1_min_compare.sv'],
          'tb_key1_min_compare','KEY1_MIN_COMPARE_PASS')
    r.sim('key1_min_safety',[ROOT/'01_rtl/secondary_top.v',ROOT/'tests/tb_key1_min_safety.sv'],
          'tb_key1_min_safety','KEY1_MIN_SAFETY_PASS')
    r.scope += [dict(test='KEY1 long action explicitly paper-armed; short/press/held old/new sampled timing',cycles=23931,
                    limitations='Fixed armed=1 stimulus comparison; not formal cycle equivalence.'),
                dict(test='KEY1 bounce/busy/mode/reset/inhibit/paper-armed transitions',checks=22)]

except Exception as e:error=str(e)
res=r.finish(error);print(json.dumps(dict(status=res['status'],report=str(out/'RESULTS.json'),error=error)))
raise SystemExit(0 if res['status']=='PASS' else 1)
