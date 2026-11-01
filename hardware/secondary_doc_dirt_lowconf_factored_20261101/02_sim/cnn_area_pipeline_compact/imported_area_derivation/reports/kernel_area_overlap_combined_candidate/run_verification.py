"""Run fresh integer-gold, per-cycle miter and atomic lifecycle tests; no TD."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import os
import re
import subprocess
import time

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
OUT=HERE/"verification"
SIM=Path("E:/model/win64")


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def main():
    source=HERE/"cnn_result_stabilizer.v"
    base=HERE/"cnn_result_stabilizer_r11.v"
    assert sha(source)=="8655EB872B8FD09C002FAD93331953F298BEEDA35A2FFFDCFBC9903AE5625B0C"
    assert sha(base)==sha(ROOT/"01_rtl/cnn_result_stabilizer.v")=="8D44203B9395F92441F09BD856AD77F4A4695343DD4D58AFB544C03DD2819D36"
    assert sha(ROOT/"01_rtl/vision_pipeline.v")=="C7B43FE8727F1145C2EF060CE9DC464029AF74CB4BD372DF10E1395E5D878413"
    assert sha(OUT/"vectors.txt")==sha(ROOT/"02_sim/cnn_stability/vectors.txt")=="C8B5BF256C7043503782213E9887EAFF0BF58C12FE85E920A4A60E2FB0D131D3"
    for name in ("LICENSE.TXT","vlib.exe","vlog.exe","vsim.exe"):
        assert (SIM/name).is_file(), name
    assert not (OUT/"RESULTS.json").exists() and not (OUT/"RUNNING.json").exists()
    inputs=[source,base,ROOT/"01_rtl/cnn_result_stabilizer.v",ROOT/"01_rtl/vision_pipeline.v",
        ROOT/"tools/cnn_stability_reference.py",ROOT/"02_sim/cnn_stability/vectors.txt",
        ROOT/"02_sim/cnn_stability/reference_trace.jsonl",*OUT.glob("*.sv"),*OUT.glob("*.txt"),
        HERE/"prepare_candidate.py",HERE/"PREPARATION.json",Path(__file__)]
    hashes={str(p):sha(p) for p in inputs}
    env=os.environ.copy()
    env.update(MGLS_LICENSE_FILE=str(SIM/"LICENSE.TXT"),LM_LICENSE_FILE=str(SIM/"LICENSE.TXT"))
    records=[]
    started=time.monotonic()
    running={"pid":os.getpid(),"started_utc":datetime.now(timezone.utc).isoformat(),"input_hashes":hashes}
    (OUT/"RUNNING.json").write_text(json.dumps(running,indent=2))

    def run(label,args,required=None):
        logfile=OUT/(label+".log")
        assert not logfile.exists(), logfile
        process=subprocess.run([str(a) for a in args],cwd=OUT,env=env,
            stdin=subprocess.DEVNULL,creationflags=getattr(subprocess,"CREATE_NO_WINDOW",0),
            stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=240)
        logfile.write_text(process.stdout)
        if process.returncode or re.search(r"\*\*\s+(?:Error|Fatal):",process.stdout):
            raise RuntimeError(label+"\n"+process.stdout[-8000:])
        passes=[line.strip("# ") for line in process.stdout.splitlines() if line.startswith("# PASS ")]
        if required:
            assert required in process.stdout, (label,process.stdout[-8000:])
            record={"test":label,"checks":passes,"elapsed_total_seconds":round(time.monotonic()-started,3)}
            records.append(record)
            (OUT/"PROGRESS.json").write_text(json.dumps(records,indent=2))
            print(label,"; ".join(passes),flush=True)
        return process.stdout

    run("vlib",[SIM/"vlib.exe","work"])
    benches=sorted(OUT.glob("tb_*.sv"))
    run("compile",[SIM/"vlog.exe","-sv","-lint","-work","work",
        OUT/"cnn_result_stabilizer_baseline.sv",source,*benches])

    def sim(label,bench,params=(),required="PASS"):
        return run(label,[SIM/"vsim.exe","-batch","-syncio","-quiet","-novopt","-suppress","12110",
            "-lib","work",bench,*params,"-do","onerror {quit -code 1}; run -all; quit -f"],required)

    text=sim("default_unchanged_integer_gold","tb_cnn_stability_serial",required="PASS SERIAL_GOLD checks=2453 vectors=2485")
    match=re.search(r"PASS SERIAL_GOLD checks=(\d+) vectors=(\d+) emitted=(\d+) bank_reuses=(\d+) clear_boundaries=(\d+) max_latency_cycles=(\d+)",text)
    gold={key:int(value) for key,value in zip(("checks","vectors","serial_records","bank_reuses","clear_boundaries","max_cycles"),match.groups())}
    parameter_sets=[(1,0,1),(2,1,2),(3,2,3),(4,0,4),(15,15,15)]
    modes=[]
    # All supported public configuration families, unchanged shift=0 behavior.
    for bits in (20,22,24,32):
        for reader in (0,1):
            for coord in (0,3):
                modes.append((bits,0,coord,reader,(3,2,3),bits,"generic_vectors.txt"))
    # Confirmation/hold/lost extremes at the exact legacy default.
    for reader in (0,1):
        for params in parameter_sets:
            mode=(32,0,0,reader,params,32,"generic_vectors.txt")
            if mode not in modes:modes.append(mode)
    # Production code width, both candidate readers, all counter parameters.
    for reader in (0,1):
        for params in parameter_sets:
            modes.append((22,6,3,reader,params,24,"aligned_a22_s6.txt"))
    # One-bit code paths verify max(code-width,distance-width), zero extension
    # and nonzero high-mask behavior at the largest supported area width.
    for bits,shift in ((20,1),(20,19),(32,31)):
        for reader in (0,1):
            modes.append((bits,shift,0,reader,(3,2,3),bits,f"aligned_a{bits}_s{shift}.txt"))
    for bits,shift,coord,reader,(confirm,hold,lost),base_bits,vectors in modes:
        label=f"miter_a{bits}s{shift}_c{coord}_e{reader}_p{confirm}_{hold}_{lost}"
        sim(label,"tb_area_grid_equivalence",[
            f"-gAREA_BITS={bits}",f"-gBASE_AREA_BITS={base_bits}",f"-gAREA_SHIFT={shift}",
            f"-gCOORD_SHIFT={coord}",f"-gEXTERNAL_CANDIDATE_READER={reader}",
            f"-gCONFIRM_RESULTS={confirm}",f"-gHOLD_RESULTS={hold}",f"-gLOST_RESULTS={lost}",
            "+vectors="+vectors],"PASS AREA_GRID_EQUIVALENCE")
    sim("payload_atomic_prod","tb_cnn_stability_ram",["-gAREA_BITS=22"],"PASS WIDE_RAM_ATOMIC")
    for reader in (0,1):
        sim(f"metadata_atomic_prod_reader{reader}","tb_cnn_stability_metadata_atomic",
            ["-gAREA_BITS=22",f"-gEXTERNAL_CANDIDATE_READER={reader}"],"PASS METADATA_ATOMIC")
    assert hashes=={str(p):sha(p) for p in inputs},"Input changed during tests"
    summary={"status":"PASS_SCRATCH_RTL_ONLY","production_modified":False,"hardware_status":"NOT_RUN",
        "candidate_sha256":sha(source),"r11_sha256":sha(base),"input_hashes":hashes,
        "integer_gold":gold,"miter_configurations":len(modes),"records":records,
        "elapsed_seconds":round(time.monotonic()-started,3),
        "evidence_hashes":{p.name:sha(p) for p in OUT.glob("*.log")},
        "limits":["Kernel only; no complete pipeline, DDR, HXA, PCB arithmetic, board synthesis or bitgen",
            "Default 2453 gold reused byte-for-byte; specialized mode uses aligned observations and frozen-R11 per-cycle oracle",
            "1170 actual ordinary replay frames retained in production area6 domain; they overlap training/development",
            "Two-state directed/random simulation; not formal proof over arbitrary X/Z or all event sequences",
            "No physical ERAM/LUT saving established until the separate local TD probe runs"]}
    (OUT/"RESULTS.json").write_text(json.dumps(summary,indent=2)+"\n")
    print(json.dumps({"status":summary["status"],"miter_configurations":len(modes),"integer_gold":gold,"elapsed_seconds":summary["elapsed_seconds"]},indent=2),flush=True)


if __name__=="__main__":
    main()
