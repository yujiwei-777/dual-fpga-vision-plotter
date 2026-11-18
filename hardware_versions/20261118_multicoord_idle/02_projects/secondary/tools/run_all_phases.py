from pathlib import Path
import subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
for phase in ('syn','place','route'):
    print('START '+phase,flush=True)
    cp=subprocess.run([sys.executable,'-B',str(ROOT/'tools/build_airwalk.py'),'secondary',phase],cwd=ROOT)
    if cp.returncode:sys.exit(cp.returncode)
    print('COMPLETE '+phase,flush=True)
