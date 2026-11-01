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
    print("RELEASE_VERIFY_PASS: source bundle and bit identities; hardware=PASS_USER_REPORTED")

if __name__ == "__main__":
    main()
