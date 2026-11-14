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
    source='secondary_pcb_airwalk_stroke_cont_20261113',
    frozen='E:/codex_paper_eject_secondary_opt_20261113_r3_seed2',
    build='E:/codex_paper_airwalk_secondary_20261113_r4')
if __name__=='__main__':m.main()
