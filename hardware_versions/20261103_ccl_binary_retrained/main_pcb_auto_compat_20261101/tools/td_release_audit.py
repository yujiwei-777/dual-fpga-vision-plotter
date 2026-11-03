#!/usr/bin/env python3
"""Read-only TD input manifest and fail-closed pre-bitgen acceptance.

Run snapshot BEFORE starting a fresh build. gate never changes RTL, constraints,
databases or bitstreams. A retrospective snapshot cannot certify an old run.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

VERSION = 1
HDL = {".v", ".sv", ".vhd", ".vhdl", ".vh", ".svh"}
NULL_MEM = {"", "none", "null", "unused"}


def read(path):
    return path.read_text(encoding="utf-8-sig", errors="replace")


def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest().upper()


def xml(path):
    # TD 2026.1 writes the literal UsedInP&R attribute value in some .al files.
    text = re.sub(r"&(?!#?\w+;)", "&amp;", read(path))
    # Its .al strategy tags also use C++-style names, not XML namespaces.
    text = re.sub(r"(<\/?[A-Za-z_][\w:]*)::", lambda m: m[1] + "__", text)
    return ET.fromstring(text)


def local(tag):
    return tag.rsplit("}", 1)[-1]


def canonical(path):
    return str(path.resolve()).replace("\\", "/")


def inside(path, root):
    return path.resolve().is_relative_to(root.resolve())


def plain_hdl(text):
    # Preserve quoted text while stripping HDL comments.
    return re.sub(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/',
                  lambda m: m[0] if m[0].startswith('"') else " ", text, flags=re.S)


def put_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def collect(args):
    root, run = args.root.resolve(), args.run.resolve()
    al = (args.al or run / (args.name + ".al")).resolve()
    config = json.loads(read(args.config)) if args.config else {}
    errors, notes, dependencies = [], [], []
    files, pending = {}, []
    inactive = config.get("inactive_memory_references", [])

    def add(path, kind, origin):
        path = path.resolve()
        key = canonical(path)
        if not inside(path, root):
            errors.append(f"Dependency escapes independent project: {key} ({origin})")
            return
        # resolve() follows directory junctions. Also reject any resolved work/ path.
        if "work" in [p.lower() for p in path.parts]:
            errors.append(f"Protected work/ dependency: {key} ({origin})")
            return
        if not path.is_file():
            errors.append(f"Missing {kind}: {key} ({origin})")
            return
        if key not in files:
            files[key] = {"path": key, "kind": kind, "origins": [],
                          "bytes": path.stat().st_size, "mtime_ns": path.stat().st_mtime_ns,
                          "sha256": sha(path)}
            if path.suffix.lower() in HDL | {".xml", ".ipc"}:
                pending.append(path)
        files[key]["origins"].append(origin)

    if not inside(run, root):
        errors.append("Run directory is outside independent project")
    add(al, "project", "command line")
    active = []
    if al.is_file():
        try:
            project = xml(al)
            for section in project.findall("./Source_Files/*"):
                for node in section.findall("./File"):
                    attrs = {a.get("Name"): a.get("Val", "").lower()
                             for a in node.findall("./FileInfo/Attr")}
                    if attrs.get("AutoExcluded") == "true":
                        continue
                    if attrs.get("UsedInSyn") == "false" and attrs.get("UsedInP&R") == "false":
                        continue
                    value = node.get("Path", "")
                    if not value:
                        errors.append(f"Empty active {section.tag} reference")
                        continue
                    path = Path(value)
                    if not path.is_absolute():
                        path = al.parent / path
                    active.append((path.resolve(), section.tag))
                    add(path, section.tag, f"{al.name}:{section.tag}")
            orders = {}
            for node in project.findall("./Source_Files/Verilog/File") + project.findall("./Source_Files/VHDL/File"):
                attrs = {a.get("Name"): a.get("Val") for a in node.findall("./FileInfo/Attr")}
                if attrs.get("AutoExcluded", "false").lower() == "true":
                    continue
                order = attrs.get("CompileOrder")
                if order in orders:
                    notes.append(f"Duplicate CompileOrder {order}: {orders[order]} and {node.get('Path')}")
                orders[order] = node.get("Path")
        except (ET.ParseError, OSError) as exc:
            errors.append(f"Cannot parse .al: {exc}")
    for extra in args.extra or []:
        add(extra, "explicit_dependency", "--extra")
    if args.config:
        add(args.config, "audit_configuration", "--config")
    for value in config.get("extra_files", []):
        add(root / value, "configured_dependency", "config.extra_files")

    # Expand actual IP-XACT file sets, not every file in an old copied directory.
    cursor = 0
    while cursor < len(pending):
        path = pending[cursor]
        cursor += 1
        if path.suffix.lower() not in {".xml", ".ipc"}:
            continue
        try:
            component = xml(path)
        except ET.ParseError:
            if path.suffix.lower() == ".xml":
                errors.append(f"Cannot parse active IP XML: {canonical(path)}")
            continue
        for node in component.iter():
            if local(node.tag) != "file":
                continue
            for child in node:
                if local(child.tag) == "name" and child.text:
                    add(path.parent / child.text.strip(), "ip_fileset", canonical(path))

    def exempt(path, expr):
        rel = str(path.relative_to(root)).replace("\\", "/")
        for entry in inactive:
            if entry.get("source") == rel and entry.get("expression") == expr and entry.get("reason"):
                return entry["reason"]
        return None

    def memory(path, expr, literal):
        rel = str(path.relative_to(root)).replace("\\", "/")
        for entry in config.get("resolved_memory_references", []):
            if entry.get("source") == rel and entry.get("expression") == expr and entry.get("reason"):
                literal = entry.get("literal")
                notes.append(f"Reviewed memory override {rel}:{expr}: {entry['reason']}")
        reason = exempt(path, expr)
        item = {"source": canonical(path), "expression": expr, "literal": literal}
        if reason:
            item.update(status="excluded_inactive", reason=reason)
            dependencies.append(item)
            return
        if literal is None:
            item["status"] = "unresolved"
            errors.append(f"Unresolved memory expression {expr} in {canonical(path)}; supply reviewed config evidence")
        elif literal.lower() in NULL_MEM:
            # Empty default parameters need instance-override evidence, never silently pass.
            item["status"] = "unresolved_empty_default"
            errors.append(f"Empty memory default {expr} in {canonical(path)}; supply reviewed config evidence")
        else:
            raw = Path(literal.replace("\\", "/"))
            candidates = [raw] if raw.is_absolute() else [run / raw, path.parent / raw]
            resolved = list(dict.fromkeys(p.resolve() for p in candidates if p.is_file()))
            item["candidates"] = [canonical(p) for p in candidates]
            item["resolved"] = [canonical(p) for p in resolved]
            if not resolved:
                errors.append(f"Missing readmem dependency {literal} ({canonical(path)}, {expr})")
                item["status"] = "missing"
            else:
                item["status"] = "present"
                if len({sha(p) for p in resolved}) > 1:
                    errors.append(f"Ambiguous memory path has different content: {literal} ({canonical(path)})")
                for p in resolved:
                    add(p, "readmem_dependency", f"{canonical(path)}:{expr}")
        dependencies.append(item)

    # HDL dependency scan is conservative, not an HDL elaborator. Explicit,
    # documented inactive expressions/override evidence must be supplied in config.
    known_headers = [Path(k) for k in files if Path(k).suffix.lower() in {".vh", ".svh"}]
    for key in list(files):
        path = Path(key)
        if path.suffix.lower() not in HDL:
            continue
        text = plain_hdl(read(path))
        strings = dict(re.findall(r'\b(\w+)\s*=\s*"([^"\n]*)"', text))
        for match in re.finditer(r'\$readmem[hb]\s*\(\s*("[^"\n]*"|\w+)', text):
            expr = match[1]
            literal = expr[1:-1] if expr.startswith('"') else strings.get(expr)
            memory(path, expr, literal)
        for match in re.finditer(r'`include\s+"([^"\n]+)"', text):
            value = match[1]
            rel = str(path.relative_to(root)).replace("\\", "/")
            excluded = [e for e in config.get("inactive_include_references", [])
                        if e.get("source") == rel and e.get("include") == value and e.get("reason")]
            if excluded:
                notes.append(f"Reviewed inactive include {rel}:{value}: {excluded[0]['reason']}")
                continue
            options = [path.parent / value, run / value]
            options += [p for p in known_headers if p.name == Path(value).name]
            resolved = list(dict.fromkeys(p.resolve() for p in options if p.is_file()))
            if not resolved:
                errors.append(f"Unresolved include {value} in {key}")
            for p in resolved:
                add(p, "include", key)
    ordered = sorted(files.values(), key=lambda x: x["path"].lower())
    content = [{k: item[k] for k in ("path", "kind", "sha256")} for item in ordered]
    digest = hashlib.sha256(json.dumps(content, sort_keys=True).encode()).hexdigest().upper()
    return {"schema_version": VERSION, "generated_utc": datetime.now(timezone.utc).isoformat(),
            "generated_ns": __import__("time").time_ns(), "project_root": canonical(root),
            "run": canonical(run), "name": args.name, "al": canonical(al),
            "manifest_sha256": digest, "files": ordered, "memory_references": dependencies,
            "errors": sorted(set(errors)), "notes": sorted(set(notes)),
            "passed": not errors}


def snapshot(args):
    result = collect(args)
    put_json(args.output or args.run / "source_snapshot.json", result)
    print(json.dumps({k: result[k] for k in ("passed", "manifest_sha256", "errors", "notes")}, indent=2))
    return 0 if result["passed"] else 1


def project_semantics(path):
    """Syn/phy .al copies may only differ in run-directory metadata."""
    project = xml(path)
    sources = []
    for section in project.findall("./Source_Files/*"):
        for node in section.findall("./File"):
            source = Path(node.get("Path", ""))
            if not source.is_absolute():
                source = path.parent / source
            sources.append((section.tag, canonical(source),
                            [(a.get("Name"), a.get("Val")) for a in node.findall("./FileInfo/Attr")]))
    def element(name):
        node = project.find(name)
        return ET.tostring(node, encoding="unicode") if node is not None else None
    return {"sources": sources, "hardware": element("./HardWare"), "top": element("./TOP_MODULE")}


def verify_ddr_binding(path, args):
    """Narrow exception for a frozen shared DDR ROM omitted by a glob snapshot.

    No snapshot is rewritten. The current build DB must contain every initialized
    52-bit word, and the historical manifest must predate this build.
    """
    value = json.loads(read(path))
    root = args.root.resolve()
    syn = (args.syn_run or (args.run.parent / "syn_1" if args.run.name == "phy_1" else args.run)).resolve()
    failures, accepted = [], {}
    if value.get("type") != "frozen_ddr_rom_database_binding" or value.get("name") != args.name:
        return {}, [f"Invalid supplemental binding format/project: {path}"]
    for item in value.get("files", []):
        try:
            target = (root / item["path"]).resolve()
            hist = item["historical_manifest"]
            hp = Path(hist["path"])
            db = Path(item["database"]["path"])
            np = Path(item["extracted_netlist"]["path"])
            bp = Path(item["extraction_input_hashes"]["path"])
            if not inside(target, root) or target.name != "ddrphy_cfg_rom.txt":
                raise ValueError("Supplement only supports an in-project ddrphy_cfg_rom.txt")
            for p, digest in [(target, item["sha256"]), (hp, hist["sha256"]),
                              (db, item["database"]["sha256"]), (np, item["extracted_netlist"]["sha256"]),
                              (bp, item["extraction_input_hashes"]["sha256"])]:
                if not p.is_file() or sha(p) != digest.upper():
                    raise ValueError(f"Supplemental evidence hash mismatch: {p}")
            if db.resolve() != (syn / (args.name + "_elaborate.db")).resolve():
                raise ValueError("Supplemental DB is not this build's elaboration database")
            before = json.loads(read(bp))
            if before.get(canonical(db)) != sha(db):
                raise ValueError("Elaboration DB changed during ROM extraction")
            al = syn / (args.name + ".al")
            if before.get(canonical(al)) != sha(al):
                raise ValueError("Project .al changed during ROM extraction")
            history = json.loads(read(hp))
            entry = [f for f in history["files"] if f["path"].replace("\\", "/") == hist["entry_path"]]
            if len(entry) != 1 or entry[0]["sha256"].upper() != sha(target):
                raise ValueError("Historical frozen ROM hash does not match")
            start = syn / ".read_design.begin.f"
            if hp.stat().st_mtime_ns > start.stat().st_mtime_ns or target.stat().st_mtime_ns > start.stat().st_mtime_ns:
                raise ValueError("Historical evidence or target ROM is newer than synthesis")
            net = read(np)
            module = re.search(r'module \\ph1p_ddrphy_init\(ROM_LEN=45,ROM_INIT="ddrphy_cfg_rom.txt"\).*?\nendmodule', net, re.S)
            if not module:
                raise ValueError("Current DB netlist lacks expected DDR init module/parameters")
            ram = re.search(r'ram_r6x52\s*#\(.*?\.HAS_INIT\("1"\).*?\.INIT_VALUE\(3328\x27b([01x]+)\)', module[0], re.S)
            if not ram or len(ram[1]) != 3328:
                raise ValueError("Expected initialized 64x52 DDR ROM is absent")
            words = [int(x.replace("_", ""), 16) for x in read(target).split()]
            if len(words) != 45:
                raise ValueError("Expected 45 DDR configuration words")
            bits = ram[1]
            for i, word in enumerate(words):
                actual = bits[len(bits) - 52 * (i + 1):len(bits) - 52 * i]
                if "x" in actual or int(actual, 2) != word:
                    raise ValueError(f"Current DB DDR ROM word {i} differs from frozen input")
            accepted[canonical(target)] = sha(target)
        except (KeyError, ValueError, OSError) as exc:
            failures.append(f"Supplemental DDR binding rejected: {exc}")
    if not accepted and not failures:
        failures.append("Supplemental binding has no verified file")
    return accepted, failures


def gate(args):
    run = args.run.resolve()
    failures, evidence, metrics, resources = [], {}, {}, {}
    current = collect(args)
    failures += current["errors"]
    snapshot_path = args.snapshot or run / "source_snapshot.json"
    supplemental = {}
    for p in getattr(args, "supplemental", None) or []:
        try:
            verified, problems = verify_ddr_binding(p, args)
            supplemental.update(verified)
            failures += problems
            evidence[canonical(p)] = {"sha256": sha(p)}
        except (OSError, ValueError) as exc:
            failures.append(f"Supplemental evidence failed: {exc}")
    try:
        before = json.loads(read(snapshot_path))
        if "manifest_sha256" in before:
            if not before.get("passed"):
                failures.append("Pre-build input snapshot did not pass")
            if before.get("manifest_sha256") != current["manifest_sha256"]:
                old_files = {f["path"]: f["sha256"] for f in before["files"] if f["kind"] != "project"}
                new_files = {f["path"]: f["sha256"] for f in current["files"] if f["kind"] != "project"}
                same = old_files == new_files
                try:
                    old_al = Path(before["al"])
                    old_entry = next(f for f in before["files"] if f["kind"] == "project")
                    same = same and sha(old_al) == old_entry["sha256"]
                    same = same and project_semantics(old_al) == project_semantics(Path(current["al"]))
                except (KeyError, OSError, StopIteration, ET.ParseError):
                    same = False
                if not same:
                    failures.append("Source/constraint/IP/MEM hashes differ from pre-build snapshot")
        else:
            # The independent generator also records a pre-build complete source
            # tree snapshot: project_root/name/files[{relative path,sha256}].
            # Verify every captured file and coverage of each active dependency.
            snaproot = Path(before.get("project_root", "")).resolve()
            captured, captured_hashes = {}, set()
            for item in before.get("files", []):
                p = (snaproot / item["path"]).resolve()
                expected = item.get("sha256", "").upper()
                captured[canonical(p)] = expected
                captured_hashes.add(expected)
                if not inside(p, args.root) or not p.is_file() or sha(p) != expected:
                    failures.append(f"Generator snapshot mismatch/missing source: {canonical(p)}")
            if not captured:
                failures.append("Generator snapshot has no files")
            for item in current["files"]:
                if item["kind"] in {"project", "audit_configuration", "explicit_dependency"}:
                    continue
                if item["path"] in captured:
                    continue
                if supplemental.get(item["path"]) == item["sha256"]:
                    continue
                # Run-local staged MEM/IP inputs may be copies of frozen sources.
                # Exact bytes must match a captured source; mtimes are checked below.
                if inside(Path(item["path"]), run) and item["sha256"] in captured_hashes:
                    continue
                failures.append(f"Active input is not covered by generator snapshot: {item['path']}")
            if snaproot != args.root.resolve():
                failures.append("Generator snapshot belongs to another project root")
        allowed_run = canonical((args.syn_run or (run.parent / "syn_1" if run.name == "phy_1" else run)).resolve())
        if before.get("name") != args.name or (before.get("run") and before["run"] not in {canonical(run), allowed_run}):
            failures.append("Snapshot belongs to a different project or run")
    except (OSError, ValueError) as exc:
        failures.append(f"Missing/invalid pre-build snapshot: {exc}")
        before = {}

    def required(name):
        path = run / name
        if not path.is_file():
            failures.append(f"Missing build evidence: {name}")
            return "", None
        evidence[name] = {"sha256": sha(path), "mtime_ns": path.stat().st_mtime_ns}
        return read(path), path

    timing, timing_path = required(args.name + "_pr.timing")
    area, area_path = required(args.name + "_phy.area")
    status, status_path = required("route_flow.status")
    _, route_end = required(".opt_route.end.f")
    syn_run = (args.syn_run or (run.parent / "syn_1" if run.name == "phy_1" else run)).resolve()
    start = syn_run / ".read_design.begin.f"
    if not start.is_file():
        failures.append(f"Missing synthesis start marker: {canonical(start)}")
        start = None
    else:
        evidence[canonical(start)] = {"sha256": sha(start), "mtime_ns": start.stat().st_mtime_ns}
    db = run / (args.name + "_pr.db")
    if not db.is_file():
        failures.append("Missing routed database")
    else:
        evidence[db.name] = {"sha256": sha(db), "mtime_ns": db.stat().st_mtime_ns}
    if (run / ".stop.f").exists() or list(run.glob(".*.error.f")):
        failures.append("Stop or failed-step marker exists in run")
    if start:
        if before.get("generated_ns", snapshot_path.stat().st_mtime_ns if snapshot_path.is_file() else 2**64) > start.stat().st_mtime_ns:
            failures.append("Snapshot was not captured before read_design began")
        newer = [f["path"] for f in current["files"]
                 if f["kind"] != "audit_configuration" and f["mtime_ns"] > start.stat().st_mtime_ns]
        if newer:
            failures.append("Inputs changed after synthesis began: " + "; ".join(newer))
    if start and route_end:
        for path in (timing_path, area_path, status_path, db if db.is_file() else None):
            if path and not start.stat().st_mtime_ns <= path.stat().st_mtime_ns <= route_end.stat().st_mtime_ns + 2_000_000_000:
                failures.append(f"Stale/inconsistent route evidence: {path.name}")
    for key in ("SWNS", "STNS", "HWNS", "HTNS"):
        match = re.search(rf"\b{key}:\s*([-+]?\d+(?:\.\d+)?)ns", timing)
        if not match:
            failures.append(f"Missing final timing metric {key}")
        else:
            value = float(match[1])
            metrics[key] = value
            if value < 0 or (key.endswith("TNS") and value != 0):
                failures.append(f"{key}={value} ns fails acceptance")
    for label, passed in (
        ("routed timing", bool(re.search(r"Confidence\s*:\s*Routed", timing))),
        ("both timing corners", bool(re.search(r"Check Corner\s*:\s*Both \(Slow and Fast\)", timing))),
        ("Slow max/min checked", bool(re.search(r"^Slow\s*\|\s*yes\s+yes", timing, re.M))),
        ("Fast max/min checked", bool(re.search(r"^Fast\s*\|\s*yes\s+yes", timing, re.M))),
        ("final timing mode", bool(re.search(r"Timing Mode\s*:\s*final", status))),
        ("route actually called", bool(re.search(r"^\s*route\s*\|\s*[1-9]\d*\s*\|", status, re.M))),
    ):
        if not passed:
            failures.append("Missing evidence: " + label)
    # Strict inequality uses unrounded counts, not rounded report percentages.
    for resource, limit in (("slice", 95), ("eram", 90), ("dsp", 95)):
        match = re.search(rf"^#{resource}\s+(\d+)\s+out of\s+(\d+)\s+([\d.]+)%", area, re.M | re.I)
        if not match or int(match[2]) == 0:
            failures.append(f"Missing/invalid {resource} resource report")
            continue
        used, total = int(match[1]), int(match[2])
        pct = used * 100.0 / total
        resources[resource] = {"used": used, "total": total, "percent": pct, "strict_limit_percent": limit}
        if used * 100 >= total * limit:
            failures.append(f"{resource}={pct:.5f}% requires <{limit}%")
    log_paths = args.log or []
    if not log_paths:
        for directory in dict.fromkeys([syn_run, run]):
            candidates = sorted(directory.glob("td_*.log"), key=lambda p: p.stat().st_mtime_ns)
            if candidates:
                log_paths.append(candidates[-1])
    if not log_paths:
        failures.append("No synthesis/implementation log supplied/found")
    warnings = []
    for path in log_paths:
        if not path.is_file():
            failures.append(f"Missing build log: {path}")
            continue
        evidence[canonical(path)] = {"sha256": sha(path)}
        for number, line in enumerate(read(path).splitlines(), 1):
            missing_rom = bool(re.search(r"HDL-5105|(?:readmem[hb]|initiali[sz]ation|INIT_FILE|\.mem|ROM).*?(?:not found|cannot open|could not open|failed to open|does not exist|missing)", line, re.I))
            fatal = bool(re.search(r"(?:[A-Z]+-\d+\s*(?:ERROR|FATAL)|\bBUILD_FAILED\b|\bMAPPING_ERROR\b|^\s*(?:ERROR|FATAL)\s*[:\[])" , line))
            if missing_rom or fatal:
                failures.append(f"{path.name}:{number}: {line.strip()}")
            if re.search(r"RTCLK-5078|USR-6113|USR-8159|SLATR-103[68]", line):
                warnings.append({"file": canonical(path), "line": number, "text": line.strip()})
    result = {"schema_version": VERSION, "passed": not failures,
              "bitgen_allowed": not failures, "run": canonical(run), "name": args.name,
              "generated_utc": datetime.now(timezone.utc).isoformat(),
              "timing_ns": metrics, "resources": resources,
              "source_manifest_sha256": current["manifest_sha256"],
              "snapshot": canonical(snapshot_path), "failures": sorted(set(failures)),
              "tracked_warnings": warnings, "evidence": evidence,
              "hardware_status": "NOT_RUN", "scope": "Build gates only; CDC/DDR/DRC and hardware review remain required"}
    put_json(args.output or run / "release_gate.json", result)
    print(json.dumps({k: result[k] for k in ("passed", "timing_ns", "resources", "failures")}, indent=2))
    return 0 if result["passed"] else 1


def reimport(args):
    run, out = args.run.resolve(), args.audit_dir.resolve()
    if not inside(run, args.root) or not inside(out, args.root):
        raise ValueError("Run/audit directories must stay inside independent project")
    out.mkdir(parents=True, exist_ok=True)
    template = '''# Read-only routed-database audit. No clear_sdc/read_sdc, export_db,
# place, route, optimize, bitgen or project-save commands are permitted here.
set build {@RUN@}
set audit {@OUT@}
set name {@NAME@}
cd $build
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project "$build/$name.al" -noanalyze
    import_db "$build/${name}_pr.db"
    update_timing -mode final
    report_timing_status -file "$audit/readonly.ts"
    report_timing_summary -file "$audit/readonly.timing"
    report_timing_exception -file "$audit/readonly.exceptions"
    check_timing -verbose -file "$audit/readonly.check"
    report_area -io_info -file "$audit/readonly.area"
    report_clock_utilization -file "$audit/readonly.clocks"
    flow_status -file "$audit/readonly.flow"
    puts TD_READONLY_REIMPORT_PASS
} reason]} {
    puts "TD_READONLY_REIMPORT_FAIL: $reason"
    exit 1
}
exit 0
'''
    template = template.replace("@RUN@", canonical(run)).replace("@OUT@", canonical(out)).replace("@NAME@", args.name)
    path = args.output or out / "readonly_reimport.tcl"
    path.write_text(template, encoding="utf-8")
    # Preserve DB/AL hashes outside TD before running this script; compare after.
    put_json(out / "readonly_input_hashes.json", {canonical(p): sha(p) for p in
             [run / (args.name + ".al"), run / (args.name + "_pr.db")] if p.is_file()})
    print(canonical(path))
    return 0


def verify_readonly(args):
    out = args.audit_dir.resolve()
    prefix = args.report_prefix
    marker = args.readonly_marker
    expected = json.loads(read(out / "readonly_input_hashes.json"))
    failures = []
    for value, digest in expected.items():
        path = Path(value)
        if not path.is_file() or sha(path) != digest:
            failures.append(f"Read-only input changed: {value}")
    timing_path = out / f"{prefix}.timing"
    timing = read(timing_path) if timing_path.is_file() else ""
    for key in ("SWNS", "STNS", "HWNS", "HTNS"):
        match = re.search(rf"\b{key}:\s*([-+]?\d+(?:\.\d+)?)ns", timing)
        if not match or float(match[1]) < 0 or (key.endswith("TNS") and float(match[1]) != 0):
            failures.append(f"Read-only timing failed/missing: {key}")
    for name in (f"{prefix}.ts", f"{prefix}.timing", f"{prefix}.exceptions", f"{prefix}.check",
                 f"{prefix}.area", f"{prefix}.clocks", f"{prefix}.flow"):
        if not (out / name).is_file():
            failures.append(f"Read-only report missing: {name}")
    logs = args.log or list(out.glob("td_*.log"))
    if not logs or not any(marker in read(p) for p in logs if p.is_file()):
        failures.append("Read-only completion marker not present in supplied logs")
    result = {"passed": not failures, "failures": failures, "hardware_status": "NOT_RUN",
              "scope": "Database/AL unchanged and timing/reports produced; inspect CDC/DRC report content separately"}
    put_json(args.output or out / "readonly_verification.json", result)
    print(json.dumps(result, indent=2))
    return 0 if result["passed"] else 1


def rom_template(args):
    run, out = args.run.resolve(), args.audit_dir.resolve()
    if not inside(run, args.root) or not inside(out, args.root):
        raise ValueError("Run/audit directories must stay inside independent project")
    out.mkdir(parents=True, exist_ok=True)
    db = run / (args.name + "_elaborate.db")
    al = run / (args.name + ".al")
    if not db.is_file() or not al.is_file():
        raise ValueError("Elaborated DB and .al must exist before extracting ROM evidence")
    template = '''# Read-only elaboration evidence export. Writes only a new audit netlist.
cd {@RUN@}
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project {@AL@} -noanalyze
    import_db {@DB@}
    write_verilog {@OUT@/elaborated_rom_evidence.v}
    puts TD_ROM_EVIDENCE_EXPORT_PASS
} reason]} {
    puts "TD_ROM_EVIDENCE_EXPORT_FAIL: $reason"
    exit 1
}
exit 0
'''
    for key, value in {"RUN": canonical(run), "AL": canonical(al), "DB": canonical(db), "OUT": canonical(out)}.items():
        template = template.replace("@" + key + "@", value)
    path = args.output or out / "readonly_rom_evidence.tcl"
    path.write_text(template, encoding="utf-8")
    put_json(out / "rom_extraction_input_hashes.json", {canonical(p): sha(p) for p in (db, al)})
    print(canonical(path))
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("snapshot", "gate", "reimport-template", "verify-readonly", "rom-template"))
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--al", type=Path)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--extra", action="append", type=Path)
    parser.add_argument("--snapshot", type=Path)
    parser.add_argument("--supplemental", action="append", type=Path,
                        help="Historical DDR ROM freeze plus this-build database INIT binding; never rewrites snapshot")
    parser.add_argument("--syn-run", type=Path)
    parser.add_argument("--log", action="append", type=Path)
    parser.add_argument("--audit-dir", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--report-prefix", default="readonly",
                        help="Report filename prefix produced by the read-only Tcl script")
    parser.add_argument("--readonly-marker", default="TD_READONLY_REIMPORT_PASS",
                        help="Completion marker emitted by the read-only Tcl script")
    args = parser.parse_args()
    if args.command in {"reimport-template", "verify-readonly", "rom-template"} and not args.audit_dir:
        parser.error(f"{args.command} requires --audit-dir")
    try:
        return {"snapshot": snapshot, "gate": gate, "reimport-template": reimport,
                "verify-readonly": verify_readonly, "rom-template": rom_template}[args.command](args)
    except (OSError, ValueError, ET.ParseError) as exc:
        print(f"AUDIT_ERROR: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
