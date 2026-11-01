"""Direct production22/6 RTL vs fresh independent integer-reference output.

The unchanged reference implements pixel-domain association and area ordering.
A narrow eligibility adapter marks an observation's class invalid if its
coordinates/area cannot be represented exactly by the specialized kernel.
It does not alter any accepted geometry, area, confidence, or model parameters.
"""
from pathlib import Path
import hashlib
import importlib.util
import json
import os
import re
import subprocess
import sys

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
OUT=HERE/"production_reference"
SIM=Path("E:/model/win64")


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def main():
    assert not OUT.exists()
    OUT.mkdir()
    source=HERE/"cnn_result_stabilizer.v"
    model=ROOT/"tools/cnn_stability_reference.py"
    vectors=HERE/"verification/aligned_a22_s6.txt"
    original_bench=ROOT/"02_sim/cnn_stability_serial/tb_cnn_stability_serial.sv"
    assert sha(source)=="8655EB872B8FD09C002FAD93331953F298BEEDA35A2FFFDCFBC9903AE5625B0C"
    spec=importlib.util.spec_from_file_location("cnn_area_independent_reference",model)
    module=importlib.util.module_from_spec(spec)
    sys.modules[spec.name]=module
    spec.loader.exec_module(module)
    oracle=module.Stabilizer()
    rows=[]
    adaptations=0
    for i,line in enumerate(vectors.read_text().splitlines()):
        op,n,raw=line.split()
        op,n,raw=int(op),int(n),int(raw,16)
        if op in (1,2):
            oracle.clear();expected=(0,0,0)
        else:
            op=0
            adapted=raw
            for j in range(min(n,4)):
                word=(raw>>(128*j))&((1<<128)-1)
                coords=[(word>>bit)&0xffff for bit in (0,16,32,48)]
                area=(word>>96)&0xffffffff
                if any(value&7 for value in coords) or area&0xffc0003f:
                    adapted&=~(0xffff<<(128*j+64))
                    adaptations+=1
            expected=oracle.update(n,adapted)
        count,packed,uncertain=expected
        rows.append(f"{i} {op} {n} {raw:0128x} {count} {packed:0128x} {int(uncertain)}\n")
    (OUT/"vectors.txt").write_text("".join(rows))
    text=original_bench.read_text()
    old="cnn_result_stabilizer #(.EXTERNAL_CANDIDATE_READER(1))"
    assert text.count(old)==1
    text=text.replace(old,"cnn_result_stabilizer #(.AREA_BITS(22),.AREA_SHIFT(6),.COORD_SHIFT(3),.EXTERNAL_CANDIDATE_READER(1))")
    old="{384'd0,32'd10000,8'd0,8'd70,16'd2,16'd200,16'd200,16'd100,16'd100}"
    assert text.count(old)==3
    text=text.replace(old,"{384'd0,32'd10048,8'd0,8'd70,16'd2,16'd192,16'd192,16'd96,16'd96}")
    (OUT/"tb_cnn_stability_serial.sv").write_text(text)
    inputs=[source,model,vectors,original_bench,OUT/"vectors.txt",OUT/"tb_cnn_stability_serial.sv",Path(__file__)]
    hashes={str(p):sha(p) for p in inputs}
    env=os.environ.copy()
    env.update(MGLS_LICENSE_FILE=str(SIM/"LICENSE.TXT"),LM_LICENSE_FILE=str(SIM/"LICENSE.TXT"))
    commands=[("vlib",[SIM/"vlib.exe","work"]),
        ("compile",[SIM/"vlog.exe","-sv","-lint","-work","work",source,OUT/"tb_cnn_stability_serial.sv"]),
        ("simulate",[SIM/"vsim.exe","-batch","-syncio","-quiet","-novopt","-suppress","12110",
            "-lib","work","tb_cnn_stability_serial","-do","onerror {quit -code 1}; run -all; quit -f"])]
    for label,cmd in commands:
        result=subprocess.run([str(arg) for arg in cmd],cwd=OUT,env=env,
            stdin=subprocess.DEVNULL,creationflags=getattr(subprocess,"CREATE_NO_WINDOW",0),
            stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=240)
        (OUT/(label+".log")).write_text(result.stdout)
        assert result.returncode==0 and not re.search(r"\*\*\s+(?:Error|Fatal):",result.stdout),result.stdout[-6000:]
    match=re.search(r"PASS SERIAL_GOLD checks=(\d+) vectors=(\d+) emitted=(\d+) bank_reuses=(\d+) clear_boundaries=(\d+) max_latency_cycles=(\d+)",result.stdout)
    assert match
    assert hashes=={str(p):sha(p) for p in inputs}
    summary={"status":"PASS_PRODUCTION_INTEGER_REFERENCE","production_modified":False,"hardware_status":"NOT_RUN",
        "candidate_sha256":sha(source),"input_hashes":hashes,
        "checks":dict(zip(("gold_checks","events","serial_records","bank_reuses","clear_boundaries","max_latency_cycles"),map(int,match.groups()))),
        "rejected_observations_or_slots":adaptations,
        "reference_adapter":"Only non-grid coordinates or forbidden area bits -> class_id0, to invoke the unchanged oracle's invalid-candidate handling; every accepted input remains bit-identical",
        "evidence_hashes":{p.name:sha(p) for p in OUT.glob("*.log")},
        "limits":["Kernel only, no physical board or accuracy claim","The ordinary 1170-frame subset overlaps training/development","No arbitrary X/Z formal equivalence"]}
    (OUT/"RESULTS.json").write_text(json.dumps(summary,indent=2)+"\n")
    print(json.dumps({"status":summary["status"],"checks":summary["checks"],"eligibility_adapter_rejections":adaptations},indent=2))


if __name__=="__main__":
    main()
