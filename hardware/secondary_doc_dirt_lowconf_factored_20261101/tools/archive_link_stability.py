"""Archive a new diagnostic bit only after implementation and reimport pass."""
import argparse
from datetime import datetime,timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
from types import SimpleNamespace

from td_release_audit import collect


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root",type=Path,required=True)
    parser.add_argument("--run",type=Path,required=True)
    parser.add_argument("--name",required=True)
    parser.add_argument("--bit-name",required=True)
    parser.add_argument("--readonly",type=Path,required=True)
    parser.add_argument("--readonly-input-hashes",type=Path,required=True)
    parser.add_argument("--bitgen-log",type=Path,required=True)
    parser.add_argument("--config",type=Path)
    parser.add_argument("--baseline-bit",type=Path,required=True)
    parser.add_argument("--baseline-sha256",required=True)
    args=parser.parse_args()
    root,run=args.root.resolve(),args.run.resolve()
    if not run.is_relative_to(root) or "work" in root.parts:
        raise ValueError("archive root must be the independent development copy")
    gate_path=run/"release_gate.json"
    gate=json.loads(gate_path.read_text(encoding="utf-8-sig"))
    if not gate.get("passed") or not gate.get("bitgen_allowed"):
        raise ValueError("release gate has not passed")
    if Path(gate["run"]).resolve()!=run or gate["name"]!=args.name:
        raise ValueError("release gate belongs to another build")
    for filename,proof in gate["evidence"].items():
        path=Path(filename)
        if not path.is_absolute():
            path=run/path
        if not path.is_file() or sha(path)!=proof["sha256"].upper():
            raise ValueError(f"release evidence changed: {path}")
    inputs=collect(SimpleNamespace(root=root,run=run,name=args.name,al=None,
                   config=args.config or root/"tools/release_audit_config.json",extra=None))
    if not inputs["passed"] or inputs["manifest_sha256"]!=gate["source_manifest_sha256"]:
        raise ValueError("active source/MEM inputs no longer match the release gate")
    readonly=json.loads(args.readonly.read_text(encoding="utf-8-sig"))
    if not readonly.get("passed"):
        raise ValueError("read-only reimport has not passed")
    readonly_inputs=json.loads(args.readonly_input_hashes.read_text(encoding="utf-8-sig"))
    for path in (run/(args.name+".al"),run/(args.name+"_pr.db")):
        expected=next((value for key,value in readonly_inputs.items() if Path(key).resolve()==path),None)
        if not expected or sha(path)!=expected.upper():
            raise ValueError(f"read-only input no longer matches: {path}")
    if (run/".stop.f").exists() or list(run.glob(".*.error.f")):
        raise ValueError("stop or error marker in accepted run")
    if sha(args.baseline_bit)!=args.baseline_sha256.upper():
        raise ValueError("baseline bit does not match the preserved control")
    source=run/(args.name+".bit")
    sequence=[run/".opt_route.end.f",run/".bitgen.begin.f",source,run/".bitgen.end.f"]
    if not all(p.is_file() for p in sequence) or source.stat().st_size==0:
        raise ValueError("bitgen evidence is incomplete")
    timestamps=[p.stat().st_mtime_ns for p in sequence]
    if timestamps!=sorted(timestamps):
        raise ValueError("bitgen markers and bit are stale/inconsistent")
    log=args.bitgen_log.read_text(encoding="utf-8-sig",errors="replace")
    if (args.bitgen_log.stat().st_mtime_ns<timestamps[-1] or
        f'finish command "import_db {args.name}_pr.db"' not in log or
        f'finish command "bitgen -bit {args.name}.bit"' not in log or
        'export_flow_status -s bitgen -e bitgen' not in log or
        re.search(r'(?im)^\s*(ERROR|FATAL)\b|Oops!|coredump|BUILD_FAILED',log)):
        raise ValueError("this invocation has no successful bitgen log")
    digest=sha(source)
    if Path(args.bit_name).name!=args.bit_name or not args.bit_name.endswith(".bit"):
        raise ValueError("bit-name must be a single .bit filename")
    destinations=[root/"artifacts"/args.bit_name,root/"05_boot/best_result"/args.bit_name]
    for destination in destinations:
        destination.parent.mkdir(parents=True,exist_ok=True)
        if destination.exists() and sha(destination)!=digest:
            raise ValueError(f"refusing to overwrite previous bit: {destination}")
        if not destination.exists():
            shutil.copy2(source,destination)
        if sha(destination)!=digest:
            raise ValueError("copy hash mismatch")
    meta={"generated_utc":datetime.now(timezone.utc).isoformat(),"hardware_status":"NOT_RUN",
          "top": "design_top_wrapper" if args.name.startswith("camera_") else "secondary_top",
          "device":"PH1P35MDG324","speed":3,"bit":args.bit_name,"sha256":digest,
          "bytes":source.stat().st_size,"build_run":str(run),
          "timing_ns":gate["timing_ns"],"resources":gate["resources"],
          "baseline_bit_sha256":args.baseline_sha256.upper(),
          "evidence":{"release_gate":{"path":str(gate_path),"sha256":sha(gate_path)},
                      "readonly_reimport":{"path":str(args.readonly.resolve()),"sha256":sha(args.readonly)},
                      "readonly_inputs":{"path":str(args.readonly_input_hashes.resolve()),"sha256":sha(args.readonly_input_hashes)},
                      "routed_database":{"path":str(run/(args.name+"_pr.db")),"sha256":sha(run/(args.name+"_pr.db"))},
                      "bitgen_script":{"path":str(run/"run_bitgen.tcl"),"sha256":sha(run/"run_bitgen.tcl")},
                      "bitgen_log":{"path":str(args.bitgen_log.resolve()),"sha256":sha(args.bitgen_log)}},
          "bitgen_marker_mtime_ns":dict(zip([p.name for p in sequence],timestamps))}
    artifact_dir=root/"artifacts"
    (artifact_dir/(args.bit_name+".json")).write_text(json.dumps(meta,indent=2)+"\n",encoding="utf-8")
    (artifact_dir/(args.bit_name+".sha256")).write_text(digest+"  "+args.bit_name+"\n",encoding="ascii")
    print(json.dumps(meta,indent=2))


if __name__=="__main__":
    main()
