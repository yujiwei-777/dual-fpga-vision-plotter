"""Install a retrained FC3 ROM into the independent secondary-board variant.

The classid_fix control project is never touched.  The source directory must
contain weights.mem, biases.mem, MODEL.json, and quantization.json.  The
script copies those files atomically enough for a reviewable build and emits
a hash manifest used by the later bitgen audit.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EXPORT = ROOT / "01_rtl" / "model" / "export"
REQUIRED = ("weights.mem", "biases.mem", "MODEL.json", "quantization.json")
OPTIONAL = ("quantized.npz",)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("source", type=Path, help="directory containing the new exported model")
    args = ap.parse_args()
    source = args.source.resolve()
    if not source.is_dir():
        raise SystemExit(f"model directory does not exist: {source}")
    missing = [name for name in REQUIRED if not (source / name).is_file()]
    if missing:
        raise SystemExit("missing model files: " + ", ".join(missing))

    model = json.loads((source / "MODEL.json").read_text(encoding="utf-8"))
    if model.get("background_head", False):
        raise SystemExit("background_head must be disabled for this FC3 variant")
    if model.get("input") not in (None, "RGB8 64x64 HWC"):
        raise SystemExit(f"unexpected model input: {model.get('input')!r}")
    if model.get("class_id") not in (None, "color*3+shape+1"):
        raise SystemExit(f"unexpected class mapping: {model.get('class_id')!r}")

    EXPORT.mkdir(parents=True, exist_ok=True)
    hashes: dict[str, str] = {}
    for name in REQUIRED:
        src = source / name
        dst = EXPORT / name
        tmp = dst.with_suffix(dst.suffix + ".incoming")
        shutil.copyfile(src, tmp)
        os.replace(tmp, dst)
        hashes[name] = sha256(dst)
        # The reference scripts resolve model/export relative to their own
        # directory; keep the same audited package there as well.
        ref_dst = ROOT / "model" / "export" / name
        shutil.copyfile(src, ref_dst)

    # Keep the NumPy archive beside the reference scripts as an audit input;
    # the RTL project consumes only the four files above.
    for name in OPTIONAL:
        src = source / name
        if src.is_file():
            shutil.copyfile(src, ROOT / "model" / "export" / name)

    manifest = {
        "variant": ROOT.name,
        "source_model": str(source),
        "files": {name: {"sha256": hashes[name], "bytes": (EXPORT / name).stat().st_size} for name in REQUIRED},
        "input": model.get("input", "RGB8 64x64 HWC"),
        "class_id": model.get("class_id", "color*3+shape+1"),
        "background_head": model.get("background_head", False),
        "hardware_validation": "NOT_RUN",
    }
    out = ROOT / "artifacts" / "RETRAINED_MODEL_ROM_MANIFEST.json"
    out.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
