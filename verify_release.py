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
    print("RELEASE_VERIFY_PASS: original pair=PASS_USER_REPORTED; pose7 pair=NOT_RUN")

if __name__ == "__main__":
    main()
