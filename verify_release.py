"""Verify the immutable hardware bundle and bit-bound acceptance statement."""
from pathlib import Path
import hashlib
import json
import subprocess
import sys

ROOT = Path(__file__).resolve().parent
BUNDLE = ROOT / "hardware"

def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(data)
    return digest.hexdigest().upper()

def main():
    subprocess.run([sys.executable, "-B", str(BUNDLE / "verify_package.py")], check=True)
    manifest = json.loads((BUNDLE / "PACKAGE_MANIFEST.json").read_text(encoding="utf-8-sig"))
    acceptance = json.loads((ROOT / "release/HARDWARE_ACCEPTANCE.json").read_text(encoding="utf-8"))
    if acceptance["status"] != "PASS_USER_REPORTED":
        raise ValueError("Unexpected hardware acceptance statement")
    for project in manifest["projects"]:
        key = project["board"] + "_bit_sha256"
        bit = BUNDLE / project["directory"] / project["bit"]
        if sha256(bit) != acceptance[key] or acceptance[key] != project["bit_sha256"]:
            raise ValueError("Bit/acceptance identity mismatch: " + project["board"])
    new_bundle = ROOT / "hardware_versions/20261102_pose7_auto"
    subprocess.run([sys.executable, "-B", str(new_bundle / "verify_package.py")], check=True)
    current = json.loads((ROOT / "release/20261102_pose7_auto/HARDWARE_ACCEPTANCE.json").read_text(encoding="utf-8"))
    new_manifest = json.loads((new_bundle / "PACKAGE_MANIFEST.json").read_text(encoding="utf-8"))
    if current["status"] != "NOT_RUN":
        raise ValueError("Unexpected pose7 hardware acceptance status")
    for project in new_manifest["projects"]:
        if project["bit_sha256"] != current[project["board"] + "_bit_sha256"]:
            raise ValueError("Pose7 bit/acceptance identity mismatch")
    identity = json.loads((ROOT / "release/20261102_pose7_auto/SOURCE_IDENTITY.json").read_text(encoding="utf-8"))
    if sha256(new_bundle / "PACKAGE_MANIFEST.json") != identity["hardware_manifest_sha256"]:
        raise ValueError("Pose7 source identity mismatch")
    binary_bundle = ROOT / "hardware_versions/20261103_ccl_binary_retrained"
    subprocess.run([sys.executable, "-B", str(binary_bundle / "verify_package.py")], check=True)
    binary_manifest = json.loads((binary_bundle / "PACKAGE_MANIFEST.json").read_text(encoding="utf-8"))
    binary_release = ROOT / "release/20261103_ccl_binary_retrained"
    binary_acceptance = json.loads((binary_release / "HARDWARE_ACCEPTANCE.json").read_text(encoding="utf-8"))
    binary_identity = json.loads((binary_release / "SOURCE_IDENTITY.json").read_text(encoding="utf-8"))
    if binary_acceptance["status"] != "NOT_RUN" or binary_identity["hardware_acceptance"] != "NOT_RUN":
        raise ValueError("Unexpected binary paired hardware acceptance")
    if sha256(binary_bundle / "PACKAGE_MANIFEST.json") != binary_identity["hardware_manifest_sha256"]:
        raise ValueError("Binary source identity mismatch")
    for project in binary_manifest["projects"]:
        digest = project["bit_sha256"]
        if digest != binary_acceptance[project["board"] + "_bit_sha256"]:
            raise ValueError("Binary bit/acceptance mismatch")
        if sha256(binary_bundle / project["directory"] / project["bit"]) != digest:
            raise ValueError("Binary bit identity mismatch")
    secondary = binary_bundle / "secondary_pcb_ccl_binary_user_retrained_20261102"
    freeze = json.loads((secondary / "evidence/release_r3/RELEASE_MANIFEST.json").read_text(encoding="utf-8"))
    if sha256(secondary / "evidence/SOURCE_MANIFEST.json") != binary_identity["secondary_frozen_manifest_sha256"]:
        raise ValueError("Binary frozen input manifest mismatch")
    for name, digest in freeze["model_freeze"]["assets"].items():
        if sha256(secondary / "model/experiments/conv4_4" / name) != digest:
            raise ValueError("Active binary model mismatch: " + name)
    key1_bundle = ROOT / "hardware_versions/20261103_ccl_binary_key1_write"
    subprocess.run([sys.executable, "-B", str(key1_bundle / "verify_package.py")], check=True)
    key1_release = ROOT / "release/20261103_ccl_binary_key1_write"
    key1_manifest = json.loads((key1_bundle / "PACKAGE_MANIFEST.json").read_text(encoding="utf-8"))
    key1_identity = json.loads((key1_release / "SOURCE_IDENTITY.json").read_text(encoding="utf-8"))
    key1_acceptance = json.loads((key1_release / "HARDWARE_ACCEPTANCE.json").read_text(encoding="utf-8"))
    if key1_identity["hardware_acceptance"] != "NOT_RUN" or key1_acceptance["status"] != "NOT_RUN":
        raise ValueError("Unexpected KEY1 pair hardware status")
    if sha256(key1_bundle / "PACKAGE_MANIFEST.json") != key1_identity["hardware_manifest_sha256"]:
        raise ValueError("KEY1 package source identity mismatch")
    for project in key1_manifest["projects"]:
        digest = project["bit_sha256"]
        if digest != key1_acceptance[project["board"] + "_bit_sha256"]:
            raise ValueError("KEY1 bit/acceptance mismatch")
        if sha256(key1_bundle / project["directory"] / project["bit"]) != digest:
            raise ValueError("KEY1 artifact mismatch")
    key1_secondary = key1_bundle / "secondary_pcb_ccl_binary_key1_write_20261103"
    if sha256(key1_secondary / "evidence/SOURCE_MANIFEST.json") != key1_identity["secondary_frozen_manifest_sha256"]:
        raise ValueError("KEY1 frozen manifest mismatch")
    if sha256(key1_secondary / "01_rtl/secondary_top.v") != key1_identity["secondary_top_sha256"]:
        raise ValueError("KEY1 top RTL mismatch")
    for name in ["weights.mem", "biases.mem"]:
        if sha256(key1_secondary / "model/experiments/conv4_4" / name) != sha256(secondary / "model/experiments/conv4_4" / name):
            raise ValueError("KEY1 PCB model changed")
    gate = json.loads((key1_secondary / "reports/retrained/release_20261103/bitgen_evidence_gate.json").read_text(encoding="utf-8"))
    if not all(gate["checks"].values()) or gate["source_manifest_sha256"] != key1_identity["secondary_frozen_manifest_sha256"]:
        raise ValueError("KEY1 evidence gate mismatch")
    print("RELEASE_VERIFY_PASS: original=PASS_USER_REPORTED; pose7/CCL binary/KEY1=NOT_RUN")

if __name__ == "__main__":
    main()
