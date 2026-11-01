"""Generate independent PH1P35 TD projects and fresh syn/phy runs.

The archived TD 2026.1_SP2 exported flow is retained, including its editable
reset/CDC proof hooks. Generic older DefaultFlow omits those required hooks.
No database or old bit is copied. Route and bitgen are separate invocations;
run the release gate before run_bitgen.tcl.
"""
import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
MAIN = ROOT.name.startswith("main_")
NAME = "camera_to_dsi_display_720p60_cnn_multibox" if MAIN else "secondary_cnn_multibox"
# The checked-in independent source copy may intentionally omit previous
# synthesis databases.  Prefer the root project, whose paths are relative to
# this copy, and fall back to the exported TD directory when present.  This
# prevents a copied .al from silently resolving RTL from the packed-overlay
# source tree.
_exported_base = ROOT / ("01_rtl/imgq_gain_m/main/td_project_fullfresh_20261020" if MAIN else "td_project_key1_build")
_root_project = ROOT / f"{NAME}.al"
BASE = ROOT if _root_project.exists() else _exported_base
RUN_FULL = next((p for p in (BASE / "run_full.tcl", ROOT / "tools/accepted_fc8_run_full.tcl",
                            ROOT / "td_project_key1_build/run_full.tcl") if p.is_file()),
                ROOT / "td_project_key1_build/run_full.tcl")
SDC = ROOT / ("04_pin/camera_to_dsi_display_720p60.sdc" if MAIN else "04_pin/timing.sdc")
DDR = ROOT / ("01_rtl/imgq_gain_m/main/user_source/hdl_source/ph1p35_ddr/ddr2/src" if MAIN else "main/user_source/hdl_source/ph1p35_ddr/ddr2/src")
PCB_MEMS = tuple(ROOT / "model" / f"pcb_tinycnn_{name}.mem" for name in ("weights", "bias", "first", "next", "taps"))
PCB_COMPACT_MEMS = tuple(ROOT / "model" / "compact" / f"pcb_tinycnn_{name}_compact.mem" for name in ("weights", "bias", "first", "next", "taps"))
PCB_PROGRAM_MEM = ROOT / "model" / "compact" / "pcb_tinycnn_program_compact.mem"
PCB_COMPACT_CORE = ROOT / "01_rtl/pcb_tinycnn_core_compact_rombram.v"
FULLBOARD_CORE = ROOT / "01_rtl/pcb_fullboard_spatial96.v"
FULLBOARD_MEMS = tuple(ROOT / "model/fullboard" / name for name in ("weights.mem", "biases.mem"))
FULLBOARD_BINARY_EXPERIMENTS = {
    "conv2_8": tuple(ROOT / "model/experiments/conv2_8" / name for name in ("weights.mem", "biases.mem")),
    "conv4_4": tuple(ROOT / "model/experiments/conv4_4" / name for name in ("weights.mem", "biases.mem")),
}
PCB_CLUSTER_CORE = ROOT / "01_rtl/pcb_defect_cluster.v"
DOC_PLANNER_CORE = ROOT / "01_rtl/doc_stroke_planner.v"
REPORTER_CORE = ROOT / "01_rtl/grbl_reporter.v"
STABILIZER_CORE = ROOT / "01_rtl/cnn_result_stabilizer.v"


def rel(path, directory):
    return Path(os.path.relpath(path, directory)).as_posix()


def load_project():
    # Older TD saves literal '&' inside UsedInP&R XML attributes.
    text = (BASE / f"{NAME}.al").read_text(encoding="utf-8-sig")
    text = re.sub(r"&(?!amp;|lt;|gt;|quot;|apos;|#\d+;)", "&amp;", text)
    # TD also uses double-colon pseudo-XML tags without XML namespaces.
    text = text.replace("::", "_TD_DOUBLE_COLON_")
    tree = ET.fromstring(text)
    if tree.findtext("HardWare/Device") != "PH1P35MDG324":
        raise ValueError("unexpected device")
    files = []
    for group in tree.find("Source_Files"):
        seen = set()
        for entry in list(group):
            path = Path(entry.attrib["Path"])
            if not path.is_absolute():
                path = BASE / path
            try:
                path = path.resolve(strict=True)
            except FileNotFoundError:
                # This source-only independent copy omits the historical
                # timing-experiment checkout. The equivalent compact module
                # is checked in under 01_rtl and is excluded by the active
                # fullboard selection, but must still resolve during import.
                if path.name == "pcb_tinycnn_core_compact.v" and PCB_COMPACT_CORE.is_file():
                    path = PCB_COMPACT_CORE.resolve(strict=True)
                else:
                    raise
            if not path.is_relative_to(ROOT):
                raise ValueError(f"external source dependency: {path}")
            if path in seen:
                group.remove(entry)
                continue
            seen.add(path)
            entry.set("Path", str(path))
            files.append(path)
    # The root project contains several historical PCB classifier experiments.
    # They all declare the same module name, so leaving more than one in the
    # generated source closure makes TD silently let the last file overwrite
    # the selected implementation (HDL-7201/HDL-7307).  Keep only the
    # explicitly selected compact core; this also makes the source snapshot
    # describe the implementation that was actually elaborated.
    verilog=tree.find("Source_Files/Verilog")
    selected_name=PCB_COMPACT_CORE.name
    for entry in list(verilog):
        path=Path(entry.attrib["Path"])
        if not path.is_absolute():
            path=BASE/path
        if path.name in {"pcb_tinycnn_core_compact.v", "pcb_tinycnn_core_compact_rombram.v", "pcb_tinycnn_core_compact_packed16.v"} and path.name != selected_name:
            verilog.remove(entry)
    # Complete document pipeline is built from this independent source tree.
    verilog=tree.find("Source_Files/Verilog")
    known={Path(e.attrib["Path"]).resolve() for e in verilog}
    # Ordinary-CNN target stability is an explicit required production input.
    # It must resolve inside this independent copy before a run is frozen.
    stabilizer = STABILIZER_CORE.resolve(strict=True)
    if not stabilizer.is_relative_to(ROOT):
        raise ValueError(f"external stabilizer dependency: {stabilizer}")
    if stabilizer not in known:
        entry=ET.Element("File", Path=str(stabilizer))
        info=ET.SubElement(entry,"FileInfo")
        for key,value in (("UsedInSyn","true"),("UsedInP&R","true"),("BelongTo","design_1")):
            ET.SubElement(info,"Attr",Name=key,Val=value)
        verilog.insert(0, entry)
        known.add(stabilizer)
    default_compact_core = (ROOT / "02_sim/pcb_tapcompact_20261024/pcb_tinycnn_core_compact.v").resolve()
    if PCB_COMPACT_CORE.resolve() != default_compact_core:
        for entry in list(verilog):
            path = Path(entry.attrib["Path"])
            if not path.is_absolute():
                path = BASE / path
            if path.resolve() == default_compact_core:
                verilog.remove(entry)
                known.discard(default_compact_core)
    default_cluster_core = (ROOT / "01_rtl/pcb_defect_cluster.v").resolve()
    if PCB_CLUSTER_CORE.resolve() != default_cluster_core:
        for entry in list(verilog):
            path = Path(entry.attrib["Path"])
            if not path.is_absolute():
                path = BASE / path
            if path.resolve() == default_cluster_core:
                verilog.remove(entry)
                known.discard(default_cluster_core)
    default_doc_planner = (ROOT / "01_rtl/doc_stroke_planner.v").resolve()
    if DOC_PLANNER_CORE.resolve() != default_doc_planner:
        for entry in list(verilog):
            path = Path(entry.attrib["Path"])
            if not path.is_absolute():
                path = BASE / path
            if path.resolve() == default_doc_planner:
                verilog.remove(entry)
                known.discard(default_doc_planner)
        entry=ET.Element("File", Path=str(DOC_PLANNER_CORE.resolve()))
        info=ET.SubElement(entry,"FileInfo")
        for key,value in (("UsedInSyn","true"),("UsedInP&R","true"),("BelongTo","design_1")):
            ET.SubElement(info,"Attr",Name=key,Val=value)
        verilog.insert(0, entry)
        known.add(DOC_PLANNER_CORE.resolve())
    # The GRBL reporter override is used only for timing experiments.  Keep
    # the normal source selected unless an explicit independent copy is
    # requested for a run.
    default_reporter = (ROOT / "01_rtl/grbl_reporter.v").resolve()
    if REPORTER_CORE.resolve() != default_reporter:
        for entry in list(verilog):
            path = Path(entry.attrib["Path"])
            if not path.is_absolute():
                path = BASE / path
            if path.resolve() == default_reporter:
                verilog.remove(entry)
                known.discard(default_reporter)
        entry=ET.Element("File", Path=str(REPORTER_CORE.resolve()))
        info=ET.SubElement(entry,"FileInfo")
        for key,value in (("UsedInSyn","true"),("UsedInP&R","true"),("BelongTo","design_1")):
            ET.SubElement(info,"Attr",Name=key,Val=value)
        verilog.insert(0, entry)
        known.add(REPORTER_CORE.resolve())
    # Shared CNN/PCB storage is optional while the standalone experiment is
    # being developed.  Once vision_workspace.v is present, make it part of
    # the generated TD project automatically; keeping the insertion here
    # avoids hand-editing generated .al/.prj files and preserves the source
    # closure check below.
    optional_shared = ROOT / "01_rtl/vision_workspace.v"
    if optional_shared.exists() and optional_shared.resolve() not in known:
        entry=ET.Element("File", Path=str(optional_shared.resolve()))
        info=ET.SubElement(entry,"FileInfo")
        for key,value in (("UsedInSyn","true"),("UsedInP&R","true"),("BelongTo","design_1")):
            ET.SubElement(info,"Attr",Name=key,Val=value)
        verilog.insert(0, entry)
        known.add(optional_shared.resolve())
    optional_mac = ROOT / "01_rtl/vision_shared_mac.v"
    if optional_mac.exists() and optional_mac.resolve() not in known:
        entry=ET.Element("File", Path=str(optional_mac.resolve()))
        info=ET.SubElement(entry,"FileInfo")
        for key,value in (("UsedInSyn","true"),("UsedInP&R","true"),("BelongTo","design_1")):
            ET.SubElement(info,"Attr",Name=key,Val=value)
        verilog.insert(0, entry)
        known.add(optional_mac.resolve())
    # The compact PCB classifier is an independent core.  Include it in the
    # generated source closure; the top-level parameter selects it for this
    # variant while the original core remains available for comparison.
    if PCB_COMPACT_CORE.exists() and PCB_COMPACT_CORE.resolve() not in known:
        entry=ET.Element("File", Path=str(PCB_COMPACT_CORE.resolve()))
        info=ET.SubElement(entry,"FileInfo")
        for key,value in (("UsedInSyn","true"),("UsedInP&R","true"),("BelongTo","design_1")):
            ET.SubElement(info,"Attr",Name=key,Val=value)
        verilog.insert(0, entry)
        known.add(PCB_COMPACT_CORE.resolve())
    if PCB_CLUSTER_CORE.exists() and PCB_CLUSTER_CORE.resolve() not in known:
        entry=ET.Element("File", Path=str(PCB_CLUSTER_CORE.resolve()))
        info=ET.SubElement(entry,"FileInfo")
        for key,value in (("UsedInSyn","true"),("UsedInP&R","true"),("BelongTo","design_1")):
            ET.SubElement(info,"Attr",Name=key,Val=value)
        verilog.insert(0, entry)
        known.add(PCB_CLUSTER_CORE.resolve())
    if FULLBOARD_CORE.exists() and FULLBOARD_CORE.resolve() not in known:
        entry=ET.Element("File", Path=str(FULLBOARD_CORE.resolve()))
        info=ET.SubElement(entry,"FileInfo")
        for key,value in (("UsedInSyn","true"),("UsedInP&R","true"),("BelongTo","design_1")):
            ET.SubElement(info,"Attr",Name=key,Val=value)
        verilog.insert(0, entry)
        known.add(FULLBOARD_CORE.resolve())
    for path in sorted((ROOT/"01_rtl").glob("doc_*.v")):
        if path.name.startswith("doc_stroke_planner") and path.resolve() != DOC_PLANNER_CORE.resolve():
            continue
        if path.resolve() not in known:
            entry=ET.SubElement(verilog,"File",Path=str(path.resolve()))
            info=ET.SubElement(entry,"FileInfo")
            for key,value in (("UsedInSyn","true"),("UsedInP&R","true"),("BelongTo","design_1")):
                ET.SubElement(info,"Attr",Name=key,Val=value)
    # The activity of constraints is explicit; never inherit stale timing.sdc.
    for tag, path in (("ADC_FILE", ROOT / "04_pin/pin.adc"), ("SDC_FILE", SDC)):
        entries = tree.findall(f"Source_Files/{tag}/File")
        if len(entries) != 1:
            raise ValueError(f"expected exactly one {tag}")
        entries[0].set("Path", str(path.resolve(strict=True)))
    # TD compares CompileOrder across source languages, IP and constraints.
    for order, entry in enumerate(tree.findall("Source_Files/*/File"), 1):
        info=entry.find("FileInfo")
        if info is None:
            info=ET.SubElement(entry,"FileInfo")
        attr=info.find("Attr[@Name='CompileOrder']")
        if attr is None:
            attr=ET.SubElement(info,"Attr",Name="CompileOrder")
        attr.set("Val",str(order))
    for node in tree.iter():
        for key, value in list(node.attrib.items()):
            if value == "constraint_1":
                node.set(key, "constrain_1")
    if tree.find("UCode") is None:
        ET.SubElement(tree, "UCode").text = "00000000"
    return tree


def write_project(tree, directory, suffix):
    out = copy.deepcopy(tree)
    out.set("Path", directory.as_posix())
    for entry in out.findall("Source_Files/*/File"):
        entry.set("Path", rel(Path(entry.attrib["Path"]), directory))
    ET.indent(out)
    payload=ET.tostring(out,encoding="unicode").replace("_TD_DOUBLE_COLON_", "::")
    (directory / f"{NAME}.{suffix}").write_text('<?xml version="1.0" encoding="UTF-8"?>\n'+payload+'\n',encoding="utf-8")
    model_dir = directory / "model"
    model_dir.mkdir(exist_ok=True)
    for source in PCB_MEMS:
        destination = model_dir / source.name
        if source.resolve() != destination.resolve():
            shutil.copy2(source, destination)
    fullboard_dir = model_dir / "fullboard"
    fullboard_dir.mkdir(exist_ok=True)
    for source in FULLBOARD_MEMS:
        destination = fullboard_dir / source.name
        if source.resolve() != destination.resolve():
            shutil.copy2(source, destination)
    for candidate, sources in FULLBOARD_BINARY_EXPERIMENTS.items():
        candidate_dir = model_dir / "experiments" / candidate
        candidate_dir.mkdir(parents=True, exist_ok=True)
        for source in sources:
            if not source.is_file():
                raise FileNotFoundError(source)
            destination = candidate_dir / source.name
            if source.resolve() != destination.resolve():
                shutil.copy2(source, destination)
    if PCB_COMPACT_MEMS[0].exists():
        compact_dir = model_dir / "compact"
        compact_dir.mkdir(exist_ok=True)
        for source in PCB_COMPACT_MEMS:
            destination = compact_dir / source.name
            if source.resolve() != destination.resolve():
                shutil.copy2(source, destination)
        if PCB_PROGRAM_MEM.exists():
            destination = compact_dir / PCB_PROGRAM_MEM.name
            if PCB_PROGRAM_MEM.resolve() != destination.resolve():
                shutil.copy2(PCB_PROGRAM_MEM, destination)


def exported_flow(directory, start, end, run, parent=None):
    text = RUN_FULL.read_text(encoding="utf-8-sig")
    # Resolve literal ../... source calls from the exported run location.
    # Relative source paths in the exported script are relative to the
    # exported run directory, not necessarily to BASE after a source-only
    # copy.  Resolve against the directory containing run_full.tcl first.
    script_root = RUN_FULL.parent
    text = re.sub(r"(source\s+\{)(\.\./[^}]+)(\})", lambda m: m[1]+rel((script_root/m[2]).resolve(strict=True),directory)+m[3], text)
    text = re.sub(r"(secondary_apply_phase_timing\s+\w+\s+\{)([^}]+)(\})", lambda m: m[1]+rel(SDC,directory)+m[3], text)
    header = {
        "alRun": run,
        "ADCList": '{"' + rel(ROOT / "04_pin/pin.adc", directory) + '"}',
        "SDCList": '{"' + rel(SDC, directory) + '"}',
        "IpADCList": "{ ddr2 " + rel(DDR / "adc/ddr2.adc", directory) + " }",
        "IpSDCList": "{ ddr2 " + rel(DDR / "sdc/ddr2.sdc", directory) + " }",
        "start_step": start, "end_step": end,
        "run_type": "syn" if start == "read_design" else "phy",
    }
    for key, value in header.items():
        text, count = re.subn(rf"(?m)^set {key} .*$", f"set {key} {value}", text, count=1)
        if count != 1:
            raise ValueError(f"missing exported flow setting {key}")
    if parent:
        text = "set parent {"+parent+"}\n"+text
    # Exit instead of leaving an interactive TD process after finishing.
    text += "\nexit\n"
    return text


def snapshot(tree):
    paths = {Path(e.attrib["Path"]).resolve() for e in tree.findall("Source_Files/*/File")}
    roots = [ROOT/"01_rtl", ROOT/"04_pin"]
    roots += [ROOT/"shared", ROOT/"main"] if not MAIN else []
    extensions = {".v", ".sv", ".vh", ".vhd", ".mem", ".mif", ".hex", ".txt", ".sdc", ".adc", ".tcl", ".ipc", ".xml"}
    for source_root in roots:
        if source_root.exists():
            paths.update(p.resolve() for p in source_root.rglob("*") if p.is_file() and p.suffix.lower() in extensions
                         and not any(part.startswith("td_project") for part in p.relative_to(source_root).parts))
    if not MAIN:
        paths.update(path.resolve(strict=True) for path in PCB_MEMS)
        paths.update(path.resolve(strict=True) for path in PCB_COMPACT_MEMS)
        paths.update(path.resolve(strict=True) for path in FULLBOARD_MEMS)
        for sources in FULLBOARD_BINARY_EXPERIMENTS.values():
            paths.update(path.resolve(strict=True) for path in sources)
        if PCB_PROGRAM_MEM.exists():
            paths.add(PCB_PROGRAM_MEM.resolve(strict=True))
    records = []
    for path in sorted(paths):
        if not path.is_relative_to(ROOT):
            raise ValueError(f"source resolves outside independent copy: {path}")
        records.append({"path":rel(path,ROOT),"sha256":hashlib.sha256(path.read_bytes()).hexdigest().upper()})
    return {"project_root":ROOT.as_posix(),"name":NAME,"files":records}


def main():
    global PCB_COMPACT_CORE, PCB_CLUSTER_CORE, DOC_PLANNER_CORE, REPORTER_CORE, FULLBOARD_CORE
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", default="link_stability_Runs")
    parser.add_argument("--pcb-compact-core", type=Path,
                        help="override the PCB compact core source for this generated run")
    parser.add_argument("--pcb-cluster-core", type=Path,
                        help="override the PCB cluster source for this generated run")
    parser.add_argument("--doc-planner-core", type=Path,
                        help="override the document planner source for this generated run")
    parser.add_argument("--reporter-core", type=Path,
                        help="override the GRBL reporter source for this generated run")
    parser.add_argument("--keep-root-project", action="store_true",
                        help="leave the root .al project file unchanged")
    args=parser.parse_args()
    if args.pcb_compact_core:
        PCB_COMPACT_CORE = args.pcb_compact_core.resolve(strict=True)
        if not PCB_COMPACT_CORE.is_relative_to(ROOT):
            raise ValueError(f"PCB compact core must be inside this independent project: {PCB_COMPACT_CORE}")
    if args.pcb_cluster_core:
        PCB_CLUSTER_CORE = args.pcb_cluster_core.resolve(strict=True)
        if not PCB_CLUSTER_CORE.is_relative_to(ROOT):
            raise ValueError(f"PCB cluster core must be inside this independent project: {PCB_CLUSTER_CORE}")
    if args.doc_planner_core:
        DOC_PLANNER_CORE = args.doc_planner_core.resolve(strict=True)
        if not DOC_PLANNER_CORE.is_relative_to(ROOT):
            raise ValueError(f"document planner source must be inside this independent project: {DOC_PLANNER_CORE}")
    if args.reporter_core:
        REPORTER_CORE = args.reporter_core.resolve(strict=True)
        if not REPORTER_CORE.is_relative_to(ROOT):
            raise ValueError(f"reporter source must be inside this independent project: {REPORTER_CORE}")
    runs=(ROOT/args.runs).resolve()
    if not runs.is_relative_to(ROOT) or runs.exists():
        raise ValueError("runs must be a new directory inside the independent project")
    tree=load_project()
    proof=snapshot(tree)
    for phase,start,end,parent in (("syn_1","read_design","opt_gate",None),("phy_1","opt_place","opt_route","../syn_1")):
        directory=runs/phase
        directory.mkdir(parents=True)
        write_project(tree,directory,"al")
        write_project(tree,directory,"prj")
        flow=exported_flow(directory,start,end,phase,parent)
        (directory/"run.tcl").write_text(flow,encoding="utf-8")
        # Configuration only; never copy the flow's later loop variables.
        config_header=flow.split("# This is default flow script",1)[0]
        settings="\n".join(line for line in config_header.splitlines() if line.startswith("set "))
        (directory/"settings.cfg").write_text(settings+"\n",encoding="utf-8")
        (directory/"source_snapshot.json").write_text(json.dumps(proof,indent=2)+"\n",encoding="utf-8")
        if phase=="phy_1":
            (directory/"run_bitgen.tcl").write_text(exported_flow(directory,"bitgen","bitgen",phase),encoding="utf-8")
    if not args.keep_root_project:
        write_project(tree,ROOT,"al")
    print(json.dumps({"runs":str(runs),"source_files":len(proof["files"]),"bitgen":"REQUIRES_RELEASE_GATE"},indent=2))


if __name__=="__main__":
    main()
