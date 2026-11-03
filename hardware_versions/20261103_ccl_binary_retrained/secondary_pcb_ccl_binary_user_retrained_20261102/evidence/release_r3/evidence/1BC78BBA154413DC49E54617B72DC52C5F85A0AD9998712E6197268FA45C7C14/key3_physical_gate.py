"""Read-only supplement to the normal routed release/DRC/timing gates.

check(root, runs) accepts only fresh, current-database KEY3/reset/CDC proofs.
It returns evidence and does not write a PASS report or generate a bit.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re

NAME = "secondary_cnn_multibox"
RESET_INSTANCES = {
    "u_reset125", "u_store_resetddr", "u_rgmii_rx_reset",
    "u_udp_stack/mac_layer_inst/mac_rx_inst/u_rx_input_reset",
    "u_udp_stack/mac_layer_inst/mac_rx_inst/u_mac_read_reset",
}
KEY3_COMMAND = "set_false_path -from [get_ports {I_key3_n}] -to [get_regs {u_board_reset/key_meta}]"
GROUP_COUNTS = {"gray_d": 52, "control_d": 5, "control_q": 9, "control_regs": 5,
                "link_d": 1, "request_q": 162, "return_q": 128, "return_d": 128,
                "stage2_d": 118, "same_domain_d": 60}


def require(condition, message):
    if not condition:
        raise RuntimeError("Current KEY3 physical proof: " + message)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest().upper()


def read(path):
    return Path(path).read_text(encoding="utf-8-sig")


def local(root, value):
    path = Path(value)
    path = (path if path.is_absolute() else root / path).resolve()
    require(path.is_relative_to(root) and "work" not in {x.lower() for x in path.parts},
            "proof path escapes independent project: " + str(path))
    return path


def fields(line):
    return dict(re.findall(r"(?:^|\s)([A-Z][A-Z0-9_]*)=(\S+)", line))


def tcl_list(value):
    """Parse literal Tcl lists only; never evaluate a command or substitution."""
    words, at = [], 0
    while at < len(value):
        while at < len(value) and value[at].isspace():
            at += 1
        if at == len(value):
            break
        out = []
        if value[at] == "{":
            depth, at = 1, at + 1
            while at < len(value) and depth:
                c = value[at]
                if c == "\\" and at + 1 < len(value):
                    out.extend(value[at:at + 2]); at += 2; continue
                if c == "{": depth += 1
                if c == "}": depth -= 1
                if depth: out.append(c)
                at += 1
            require(depth == 0, "unbalanced literal Tcl list")
        elif value[at] == '"':
            at += 1
            while at < len(value) and value[at] != '"':
                if value[at] == "\\" and at + 1 < len(value): at += 1
                out.append(value[at]); at += 1
            require(at < len(value), "unbalanced literal Tcl quote")
            at += 1
        else:
            while at < len(value) and not value[at].isspace():
                if value[at] == "\\" and at + 1 < len(value): at += 1
                out.append(value[at]); at += 1
        require(at == len(value) or value[at].isspace(), "invalid literal Tcl list separator")
        words.append("".join(out))
    return words


def selectors(line):
    """Extract get_pins/get_regs/get_ports selectors, respecting literal [n]."""
    result, at = [], 0
    while at < len(line):
        if line[at] != "[": at += 1; continue
        begin, at, bracket, brace = at, at + 1, 1, 0
        while at < len(line) and bracket:
            c = line[at]
            if c == "\\": at += 2; continue
            if c == "{": brace += 1
            elif c == "}": brace -= 1
            elif not brace and c == "[": bracket += 1
            elif not brace and c == "]": bracket -= 1
            at += 1
        require(bracket == 0 and brace == 0, "unbalanced generated SDC selector")
        words = tcl_list(line[begin + 1:at - 1])
        if not words or words[0] not in {"get_pins", "get_regs", "get_ports"}: continue
        payload = [word for word in words[1:] if word != "-nowarn"]
        require(len(payload) == 1, "unexpected generated selector options")
        role = re.search(r"(-from|-to|-through)\s*$", line[:begin])
        require(role is not None, "selector has no explicit timing role")
        result.append((role[1], words[0], set(tcl_list(payload[0]))))
    return result


def commands(text):
    return [line.strip() for line in text.splitlines() if line.strip().startswith("set_")]


def reset_targets(text):
    result = []
    for command in commands(text):
        if not command.startswith("set_false_path -to "): continue
        chosen = selectors(command)
        if len(chosen) == 1 and chosen[0][:2] == ("-to", "get_pins"):
            result.extend(chosen[0][2])
    return set(result)


def checked_snapshot(root, path):
    value = json.loads(read(path))
    require(value.get("passed") is True and not value.get("errors"), "source snapshot failed")
    require(Path(value["project_root"]).resolve() == root, "snapshot belongs to another project")
    canonical = [{key: item[key] for key in ("path", "kind", "sha256")}
                 for item in sorted(value["files"], key=lambda item: item["path"].lower())]
    require(hashlib.sha256(json.dumps(canonical, sort_keys=True).encode()).hexdigest().upper()
            == value["manifest_sha256"], "snapshot manifest digest differs")
    bound = {}
    for item in value["files"]:
        source = local(root, item["path"])
        require(source.is_file() and sha(source) == item["sha256"].upper(), "frozen input changed: " + str(source))
        require(source not in bound, "duplicate snapshot source")
        bound[source] = item["sha256"].upper()
    for rel in ("01_rtl/secondary_top.v", "04_pin/timing.sdc", "04_pin/apply_reset_exceptions.tcl",
                "04_pin/apply_cdc_exceptions.tcl", "04_pin/prove_key3_supervisor.tcl"):
        require(root / rel in bound, "runtime-proof source absent from pre-build snapshot: " + rel)
    return value, bound


def verify_key3(text, phase):
    lines = text.splitlines()
    require(lines.count("KEY3_PROOF_STAGE " + phase) == 1 and lines.count("KEY3_PROOF_PASS") == 1,
            "KEY3 proof lacks unique phase/pass markers: " + phase)
    require(not any("ERROR" in line or "UNPROVEN" in line for line in lines), "KEY3 proof reports failure")
    stages = {}
    for line in lines:
        match = re.match(r"KEY3_STAGE_PROVEN (META|SYNC)\s", line)
        if not match: continue
        require(match[1] not in stages, "duplicate KEY3 stage")
        value = fields(line)
        require({"Q", "QNET", "D", "DNET", "CLK", "ASYNC_PIN", "ASYNC", "MODE", "ASYNC_VALUE"} <= value.keys(),
                "incomplete KEY3 stage record")
        require(value["ASYNC_VALUE"] == "1" and value["MODE"] in {"GATE", "PHYSICAL"},
                "KEY3 stage has wrong asynchronous value/mapping")
        stages[match[1]] = value
    require(set(stages) == {"META", "SYNC"}, "KEY3 META/SYNC actual mapping incomplete")
    summary = [fields(line) for line in lines if line.startswith("KEY3_SUPERVISOR_PROVEN ")]
    require(len(summary) == 1, "KEY3 supervisor summary missing/duplicated")
    sup = summary[0]
    require({"CLK", "ASYNC", "OUTPUT", "CLOCK_NET", "POR_NET", "OUTPUT_NET", "INPUT_NET", "SELF_RESET", "REGISTER_COUNT"} <= sup.keys(),
            "KEY3 supervisor lacks actual source net identities")
    require(sup["CLK"] == "I_sys_clk" and sup["ASYNC"] == "por_release" and
            sup["OUTPUT"] == "board_release" and sup["SELF_RESET"] == "0", "KEY3 logical source contract changed")
    require(stages["SYNC"]["DNET"] == stages["META"]["QNET"], "KEY3 second stage does not consume META")
    sources = [fields(line) for line in lines if line.startswith("KEY3_KEY_SOURCE ")]
    require(len(sources) == 1 and sources[0].get("LOGICAL") == "I_key3_n" and
            sources[0].get("PORT_NET") == sup["INPUT_NET"] and sources[0].get("SOURCE_NET") and
            sources[0].get("SOURCE_NET") == sources[0].get("META_D_SOURCE_NET"),
            "KEY3 META D does not trace to the actual key input source")
    expected_registers = {"u_board_reset/key_meta": "1", "u_board_reset/key_sync": "1", "u_board_reset/key_sample": "1",
        "u_board_reset/sample_valid[0]": "0", "u_board_reset/sample_valid[1]": "0", "board_release": "0"}
    expected_registers.update({"u_board_reset/stable_count[" + str(bit) + "]": "0" for bit in range(20)})
    registers = {}
    for line in lines:
        if not line.startswith("KEY3_REGISTER_PROVEN "): continue
        value = fields(line)
        logical = value.get("LOGICAL")
        require(logical not in registers and logical in expected_registers, "unknown/duplicate supervisor register")
        require({"Q", "QNET", "CLK", "ASYNC_PIN", "ASYNC", "ASYNC_VALUE", "MODE"} <= value.keys(),
                "supervisor register actual mapped endpoints incomplete")
        require(value["ASYNC_VALUE"] == expected_registers[logical] and value["MODE"] in {"GATE", "PHYSICAL"},
                "supervisor register asynchronous value/mapping differs")
        require(value["ASYNC"] != sup["OUTPUT_NET"] and "CLOCK_PROOF=" in line and "ASYNC_PROOF=" in line,
                "supervisor register reset source/clock lacks runtime proof")
        registers[logical] = value
    require(set(registers) == set(expected_registers) and sup["REGISTER_COUNT"] == "26",
            "supervisor proof did not enumerate the exact 26 current registers")
    require(len({v["Q"] for v in registers.values()}) == len({v["QNET"] for v in registers.values()}) == 26,
            "supervisor register proof merged distinct state")
    for stage in stages.values():
        # The Tcl hook independently proves direct or legal SCLK-equivalent
        # clocks; record both the actual stage clocks and expected source.
        require(stage["CLK"] != "" and stage["ASYNC"] != sup["OUTPUT_NET"], "invalid KEY3 clock/reset mapping")
    return {"stages": stages, "supervisor": sup, "key_source": sources[0], "registers": registers}


def verify_resets(text, generated_sdc, exact_sdc, effective_sdc, ignored, loaded, output_net):
    instances, records, applied = {}, {}, []
    for line in text.splitlines():
        if line.startswith("INSTANCE_PROVEN "):
            name = line.split()[1]
            require(name not in instances, "duplicate reset instance proof")
            instances[name] = fields(line)
        match = re.match(r"(?:LOGICAL|PHYSICAL)_PROVEN (.+?)/sync_ff\[([01])\]\s", line)
        if match:
            value = fields(line)
            require({"Q", "NET", "D", "DNET", "CLK", "ASYNC_PIN", "ASYNC"} <= value.keys(), "incomplete reset mapping record")
            require("RESET_MODES_PROVEN" in line and "ASYNC_RESET=RESET" in line, "reset primitive modes not proved")
            records.setdefault(match[1], {"0": [], "1": []})[match[2]].append((value, line))
        if line.startswith("APPLIED_ASYNC_PIN "):
            applied.append(line.split()[1])
    require(set(instances) == RESET_INSTANCES == set(records), "reset proof instance set differs from exact five")
    proof_pins = set()
    for name, value in instances.items():
        first, second = records[name]["0"], records[name]["1"]
        require(len(first) == 1 and len(second) >= 1 and value.get("STAGE0") == "1" and
                int(value.get("STAGE1", "0")) == len(second), "reset stage/clone mapping differs: " + name)
        require("D_CONST_ONE" in first[0][1], "reset first-stage constant was not proved: " + name)
        require(all(v["DNET"] == first[0][0]["NET"] and "D_STAGE0" in line for v, line in second),
                "reset second-stage D chain differs: " + name)
        polarity = "SIG" if name.endswith("u_rx_input_reset") else "INV"
        require(all("ASSERT=" + polarity in line for _, line in first + second), "reset assertion polarity differs")
        if name in {"u_reset125", "u_store_resetddr"}:
            require(value.get("ASYNC") == output_net, "reset still uses POR instead of current board release: " + name)
        proof_pins.update(v["ASYNC_PIN"] for v, _ in first + second)
    require(len(applied) == len(set(applied)) and set(applied) == proof_pins and proof_pins, "applied reset pins differ from actual mapped proof")
    generated = reset_targets(generated_sdc)
    require(generated == proof_pins, "generated reset SDC differs from proved actual pins")
    for label, sdc in (("exact", exact_sdc), ("effective", effective_sdc)):
        targets = reset_targets(sdc)
        require(proof_pins <= targets and {x for x in targets if x.endswith((".asr", ".sr"))} == proof_pins,
                label + " reset exception endpoint set differs")
    count = re.findall(r"^EFFECTIVE_RESET_PIN_CONSTRAINTS (\d+)$", loaded, re.M)
    require(count == [str(len(proof_pins))], "effective reset pin count differs from actual endpoint set")
    summary = re.findall(r"^APPLIED_RESET_EXCEPTIONS (\d+) unique asynchronous pins; (\d+) proven synchronizers;", text, re.M)
    require(summary == [(str(len(proof_pins)), "5")], "reset summary does not match actual proved instances/endpoints")
    rows = []
    for line in ignored.splitlines():
        match = re.match(r"\s*(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(set_.*)$", line)
        if match: rows.append((tuple(map(int, match.groups()[:4])), match[5].strip()))
    for pin in proof_pins:
        matches = [numbers for numbers, command in rows if command.startswith("set_false_path -to ") and
                   selectors(command) == [("-to", "get_pins", {pin})]]
        require(len(matches) == 2 and all(a > 0 and b == a and c == d == 0 for a, b, c, d in matches),
                "reset exception missing/shadowed/ignored at max/min: " + pin)
    key_rows = [n for n, c in rows if c == KEY3_COMMAND]
    require(len(key_rows) == 2 and all(n == (1, 1, 0, 0) for n in key_rows), "KEY3 first-stage exception not effective at max/min")
    return {"instances": instances, "applied_async_pins": sorted(proof_pins)}


def verify_cdc(text, generated_sdc, exact_sdc, effective_sdc):
    groups = {}
    for match in re.finditer(r"^CDC_GROUP (\w+) COUNT=(\d+) PINS=(.*)$", text, re.M):
        name, count, body = match.groups()
        require(name not in groups, "duplicate CDC group")
        pins = tcl_list(body)
        require(len(pins) == len(set(pins)) == int(count), "CDC group count differs from actual endpoint list")
        groups[name] = set(pins)
    require({name: len(pins) for name, pins in groups.items()} == GROUP_COUNTS, "CDC actual group identity/count differs")
    expected = [
        ([("-through", "get_pins", groups["request_q"])], "7.000"),
        ([("-through", "get_pins", groups["return_q"]), ("-to", "get_pins", groups["return_d"])], "7.500"),
        ([("-through", "get_pins", groups["control_q"]), ("-to", "get_regs", groups["control_regs"])], "7.500"),
        ([("-to", "get_pins", groups["gray_d"])], "7.500"),
    ]
    for label, sdc in (("generated", generated_sdc), ("exact", exact_sdc), ("effective", effective_sdc)):
        maximums = [command for command in commands(sdc) if command.startswith("set_max_delay ")]
        sets = [selectors(command) for command in maximums]
        require(len(maximums) == 4, label + " CDC max-delay command count differs")
        for target, budget in expected:
            found = [command for command, chosen in zip(maximums, sets) if chosen == target]
            require(len(found) == 1 and found[0].endswith("-datapath_only " + budget),
                    label + " CDC max-delay actual endpoints/budget differ")
        for command in commands(sdc):
            if not command.startswith(("set_false_path ", "set_max_delay ")): continue
            for role, kind, pins in selectors(command):
                if role == "-to" and kind == "get_pins":
                    require(not pins & (groups["stage2_d"] | groups["same_domain_d"]),
                            label + " cuts/bounds a timed second-stage or same-domain Gray endpoint")
    return {name: sorted(pins) for name, pins in groups.items()}


def check(root, runs):
    root = Path(root).resolve()
    runs = local(root, runs)
    syn, phy = runs / "syn_1", runs / "phy_1"
    require((syn / ".read_design.begin.f").is_file() and (phy / ".opt_route.end.f").is_file(), "fresh synthesis/route markers missing")
    require(not any(list(path.glob(".*.error.f")) or (path / ".stop.f").exists() for path in (syn, phy)), "failed/stopped run cannot pass")
    snapshots, bound = {}, {}
    for phase, directory in (("syn", syn), ("phy", phy)):
        path = directory / "source_snapshot.json"
        value, inputs = checked_snapshot(root, path)
        require(Path(value["run"]).resolve() == directory, "snapshot belongs to wrong run")
        snapshots[phase] = {"path": str(path), "sha256": sha(path), "manifest_sha256": value["manifest_sha256"]}
        bound.update(inputs)
    database = phy / (NAME + "_pr.db")
    require(database.is_file(), "routed database missing")
    beginning = (syn / ".read_design.begin.f").stat().st_mtime_ns
    evidence = {}
    def evidence_text(path):
        path = local(root, path)
        require(path.is_file() and path.stat().st_mtime_ns >= beginning, "missing/stale current-run proof: " + str(path))
        evidence[path.relative_to(root).as_posix()] = sha(path)
        return read(path)
    phases = {}
    for phase, directory in (("gate", syn), ("place_begin", phy), ("place_end", phy), ("route_begin", phy), ("route_end", phy)):
        phases[phase] = verify_key3(evidence_text(directory / ("secondary_key3_" + phase + ".rpt")), phase)
    loaded = evidence_text(phy / "secondary_loaded_route_end.rpt")
    for tag, name in (("EXACT_SDC", "secondary_exact_route_end.sdc"), ("EFFECTIVE_SDC", "secondary_effective_route_end.sdc")):
        values = re.findall(r"^" + tag + r" (.+)$", loaded, re.M)
        require(len(values) == 1 and local(root, values[0]) == phy / name, "loaded SDC report refers to another run")
    texts = {name: evidence_text(phy / name) for name in (
        "secondary_reset_route_end.rpt", "secondary_reset_route_end.sdc", "secondary_cdc_route_end.rpt",
        "secondary_cdc_route_end.sdc", "secondary_exact_route_end.sdc", "secondary_effective_route_end.sdc",
        "secondary_effective_route_end.ignored.rpt")}
    effective = texts["secondary_effective_route_end.sdc"]
    require(commands(effective).count(KEY3_COMMAND) == 1, "current effective KEY3 first-stage falsepath differs")
    actual_sync = phases["route_end"]["stages"]["SYNC"]
    for command in commands(effective):
        if not command.startswith(("set_false_path ", "set_max_delay ")): continue
        for role, kind, pins in selectors(command):
            require(not (role == "-to" and ((kind == "get_pins" and actual_sync["D"] in pins) or
                    (kind == "get_regs" and "u_board_reset/key_sync" in pins))), "KEY3 second stage must remain timed")
    resets = verify_resets(texts["secondary_reset_route_end.rpt"], texts["secondary_reset_route_end.sdc"],
        texts["secondary_exact_route_end.sdc"], effective, texts["secondary_effective_route_end.ignored.rpt"], loaded,
        phases["route_end"]["supervisor"]["OUTPUT_NET"])
    cdc = verify_cdc(texts["secondary_cdc_route_end.rpt"], texts["secondary_cdc_route_end.sdc"],
                     texts["secondary_exact_route_end.sdc"], effective)
    require("EFFECTIVE_SMD_PATHS 290 128 9 52" in loaded, "current CDC effective path count changed")
    return {"status": "PASS_CURRENT_RESET_KEY3_PROOFS", "root": str(root), "runs": str(runs),
        "database_sha256": sha(database), "physical_al_sha256": sha(phy / (NAME + ".al")),
        "snapshots": snapshots, "runtime_source_sha256": {str(path.relative_to(root)): digest for path, digest in bound.items()
             if path.suffix.lower() in {".tcl", ".sdc"}}, "key3_phases": phases,
        "reset_proof": resets, "cdc_actual_endpoint_groups": cdc, "evidence_sha256": evidence,
        "physical_acceptance": "SUPPLEMENT_ONLY_OTHER_RELEASE_GATES_REQUIRED", "hardware_status": "NOT_RUN"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--runs", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(check(args.root, args.runs), indent=2))
