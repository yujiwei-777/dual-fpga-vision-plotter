"""Prove ordinary CNN ROM words from the read-only TD elaboration export.

Uses the emitted RAM behavioral definition to establish INIT_VALUE word order;
does not assume block-RAM bitgen layout and never modifies a TD input.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
EXPECTED = {
    "weights.mem": (8, 13512, "82FB0381424A047600E862FD0BBF55D6B23BCF347BE19F1074A9CD32847058DE"),
    "biases.mem": (32, 27, "79A3DAA7C5F3E17A2D5882FC89EEAD2AEBE153420B8D02E001655BCB23740A98"),
}


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def require(ok, text):
    if not ok:
        raise RuntimeError(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit-dir", type=Path, required=True)
    args = parser.parse_args()
    audit = args.audit_dir.resolve()
    require(audit.is_relative_to(ROOT / "02_sim"), "Audit must be in this independent project's 02_sim")
    netlist_path = audit / "elaborated_rom_evidence.v"
    before_path = audit / "rom_extraction_input_hashes.json"
    before = json.loads(before_path.read_text(encoding="utf-8-sig"))
    require(len(before) == 2 and any(p.endswith("_elaborate.db") for p in before)
            and any(p.endswith(".al") for p in before), "Missing frozen AL/elaborate DB input hashes")
    for name, expected in before.items():
        path = Path(name)
        require(path.resolve().is_relative_to(ROOT) and sha(path) == expected.upper(),
                "Read-only export changed input database/project: " + name)
    logs = [p for p in audit.glob("*.log") if "TD_ROM_EVIDENCE_EXPORT_PASS" in p.read_text(errors="replace")]
    require(logs, "TD read-only ROM export did not reach PASS marker")
    text = netlist_path.read_text(encoding="utf-8-sig", errors="strict")
    modules = list(re.finditer(r"^module \\cnn_core\([^\n]*\n(.*?)^endmodule", text, re.M | re.S))
    require(len(modules) == 1, "Expected exactly one elaborated ordinary CNN module")
    body = modules[0][0]
    require(body.startswith("module \\cnn_core(FC_CONF_SHIFT=8,USE_SHARED_WORKSPACE=1,EXTERNAL_MAC=1)"),
            "Unexpected elaborated ordinary CNN confidence/shared-MAC contract")
    require(re.search(r"\\cnn_core\(FC_CONF_SHIFT=8,USE_SHARED_WORKSPACE=1,EXTERNAL_MAC=1\)\s+g_local_cnn\$classifier\s*\(", text),
            "The audited ordinary CNN is not bound to vision_pipeline's active local classifier")
    memories = list(re.finditer(
        r"(?P<primitive>ram_r\w+)\s*#\s*\((?P<parameters>.*?)\)\s*(?P<instance>\w+)\s*\((?P<ports>.*?)\);",
        body, re.S))
    require(len(memories) == 2, "Ordinary CNN RAM count changed; explicit review is required")
    bindings = {}
    for memory in memories:
        params, ports = memory["parameters"], memory["ports"]
        if re.search(r"\.ra1\(weight_addr_q\[13:0\]\)", ports):
            leaf = "weights.mem"
        elif re.search(r"\.ra1\(bias_addr\)", ports):
            leaf = "biases.mem"
        else:
            raise RuntimeError("Unrecognized ordinary CNN RAM address connection")
        require(leaf not in bindings, "Duplicate ordinary CNN ROM: " + leaf)
        width, words, expected_sha = EXPECTED[leaf]
        require('.HAS_INIT("1")' in params, "ROM is not initialized: " + leaf)
        literal = re.search(r"\.INIT_VALUE\((\d+)'b([01xXzZ]+)\)", params)
        require(literal, "Missing concrete emitted INIT_VALUE for " + leaf)
        declared_bits, bits = int(literal[1]), literal[2]
        require(len(bits) == declared_bits and declared_bits % width == 0, "INIT literal width mismatch")
        primitive = re.search(r"^module " + re.escape(memory["primitive"]) + r"\b.*?^endmodule", text, re.M | re.S)
        require(primitive and re.search(r"ram\[i\]\s*<=\s*INIT_VALUE\[i\*" + str(width) + r"\+:" + str(width) + r"\]", primitive[0]),
                "Emitted primitive does not establish low-word-first INIT layout: " + memory["primitive"])
        source = ROOT / "model/export" / leaf
        require(sha(source) == expected_sha, "Expected selected model hash changed: " + leaf)
        expected_words = [int(word, 16) for word in source.read_text().split()]
        require(len(expected_words) == words, "Selected model word count changed: " + leaf)
        actual = []
        for index, expected_word in enumerate(expected_words):
            # Verilog packed literal is MSB first; emitted RAM indexes low bits
            # for address zero, as established from the primitive above.
            end = declared_bits - index * width
            value_bits = bits[end - width:end]
            require(set(value_bits) <= {"0", "1"}, f"Unknown initialized word in {leaf}[{index}]")
            value = int(value_bits, 2)
            require(value == expected_word, f"ROM word differs at {leaf}[{index}]: {value:x} != {expected_word:x}")
            actual.append(value)
        bindings[leaf] = {"primitive": memory["primitive"], "instance": memory["instance"],
                          "width": width, "words_compared": words, "allocated_words": declared_bits // width,
                          "all_words_equal": True, "selected_mem_sha256": expected_sha,
                          "decoded_word_bytes_sha256": hashlib.sha256(b"".join(
                              value.to_bytes(width // 8, "little") for value in actual)).hexdigest().upper(),
                          "unused_high_bits": declared_bits - words * width}
    require(set(bindings) == set(EXPECTED), "Missing selected ordinary model ROM")
    inputs = {str(Path(name).resolve()): expected.upper() for name, expected in before.items()}
    for path in [netlist_path, before_path, audit / "readonly_rom_evidence.tcl", *logs,
                 ROOT / "model/export/weights.mem", ROOT / "model/export/biases.mem"]:
        inputs[str(path.resolve())] = sha(path)
    result = {"status": "PASS", "weights_words": 13512, "bias_words": 27,
              "input_databases_unchanged": True, "ordinary_fc_conf_shift": 8,
              "hierarchy": "secondary_top.u_vision.g_local_cnn$classifier",
              "bindings": bindings, "input_hashes": inputs,
              "scope": "Current synthesized elaboration DB contains exact selected ordinary model words; this does not certify independent recognition accuracy or physical hardware.",
              "hardware_validation": "NOT_RUN"}
    (audit / "ROM_BINDING_VERIFICATION.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    report = ["# Ordinary CNN ROM binding verification", "", "Status: `PASS`. Hardware: `NOT_RUN`.", "",
              "Read-only exported the current elaboration database and verified its AL/DB hashes stayed unchanged.", "",
              "The active ordinary classifier has FC_CONF_SHIFT=8, shared workspace and external MAC enabled.",
              "The emitted RAM behavioral definitions establish low-word-first INIT_VALUE order.", "",
              "All 13,512 8-bit weights and 27 32-bit bias words match the selected model exactly.", "",
              "| File | SHA256 |", "|---|---|"]
    report += ["| " + leaf + " | `" + value[2] + "` |" for leaf, value in EXPECTED.items()]
    report += ["", result["scope"], ""]
    (audit / "ROM_BINDING_VERIFICATION.md").write_text("\n".join(report), encoding="utf-8")
    print(json.dumps({"status": result["status"], "weights_words": 13512, "bias_words": 27,
                      "input_databases_unchanged": True}, indent=2))


if __name__ == "__main__":
    main()

