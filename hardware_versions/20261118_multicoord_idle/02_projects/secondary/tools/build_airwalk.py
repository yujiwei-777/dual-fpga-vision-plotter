"""Independent airwalk/load/progress source freeze and vendor build wrapper.

The retained validator and release tools are used with freshly measured scope
and inputs; no old PASS, database or bit is reused as this candidate's result.
"""
from pathlib import Path
import importlib.util, sys
sys.dont_write_bytecode=True
ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('airwalk_build',ROOT/'build_opt.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
m.CONFIG['secondary'].update(
    source='secondary_plotter_idle_preflight_20261118',
    frozen='E:/codex_secondary_cnn_key1_live_snapshot_20261118_r1',
    build='E:/codex_secondary_plotter_idle_preflight_20261118_r2')
if __name__=='__main__':m.main()
