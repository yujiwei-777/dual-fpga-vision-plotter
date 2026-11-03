"""Compile all declared Verilog; report syntax separately from RTL simulation."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import os
import re
import subprocess
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]


def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest().upper()


def main():
    out=Path('E:/')/('codex_pose7_syntax_'+datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S_%fZ'))
    out.mkdir()
    project=ROOT/'secondary_cnn_multibox.al'
    tree=ET.fromstring(project.read_text(encoding='utf-8-sig').replace('::','_TD_DOUBLE_COLON_'))
    nodes=tree.findall('Source_Files/Verilog/File')
    nodes.sort(key=lambda n:int(next(a.attrib['Val'] for a in n.findall('FileInfo/Attr') if a.attrib['Name']=='CompileOrder')))
    files=[(ROOT/n.attrib['Path']).resolve() for n in nodes]
    assert all(p.is_relative_to(ROOT) and p.is_file() for p in files)
    hashes={str(p):sha(p) for p in files+[project]}
    env=os.environ.copy()
    env.update(LM_LICENSE_FILE='E:/model/win64/LICENSE.TXT',MGLS_LICENSE_FILE='E:/model/win64/LICENSE.TXT')
    commands=[('vlib',['E:/model/win64/vlib.exe','rtl_lib']),
              ('compile',['E:/model/win64/vlog.exe','-work','rtl_lib','+define+SYNTHESIS',
                          *['+incdir+'+p for p in sorted({p.parent.as_posix() for p in files})],*map(str,files)])]
    for name,cmd in commands:
        cp=subprocess.run(cmd,cwd=out,env=env,capture_output=True)
        (out/(name+'.log')).write_bytes(cp.stdout+cp.stderr)
        text=(out/(name+'.log')).read_text(errors='replace')
        assert cp.returncode==0 and not re.search(r'\*\*\s+(Error|Fatal):',text),text[-6000:]
    assert all(sha(p)==v for p,v in hashes.items()),'Source changed during compile'
    result={'status':'SYNTAX_PASS_NOT_ELABORATED','declared_verilog':len(files),'output':str(out),
            'inputs':hashes,'hardware':'NOT_RUN'}
    (ROOT/'reports/pose7/SYNTAX.json').write_text(json.dumps(result,indent=2))
    print(json.dumps({k:v for k,v in result.items() if k!='inputs'},indent=2))


if __name__=='__main__':main()
