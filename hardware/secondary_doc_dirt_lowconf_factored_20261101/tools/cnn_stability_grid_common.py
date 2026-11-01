"""Read-only production/grid preconditions shared by the R10 grid regressions."""
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT / "reports/coordinate_grid_review"
SOURCE = ROOT / "01_rtl/cnn_result_stabilizer.v"
BASE = REVIEW / "scratch/cnn_result_stabilizer_baseline.v"
BASE_SHA256 = "7CDB56AC96D9BCF66037E68320D8B0D45D3B5E4B27689BFDF58B9D9242BB8A40"
OUT = ROOT / "02_sim/cnn_stability_grid"
SIM = Path("E:/model/win64")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def preconditions():
    require(SOURCE.is_file() and BASE.is_file(), "Production kernel and frozen baseline are required")
    require(sha(BASE) == BASE_SHA256, "Frozen pre-grid baseline identity drifted")
    text = SOURCE.read_text(encoding="utf-8")
    require(bool(re.search(r"\bparameter\s+integer\s+COORD_SHIFT\s*=", text)),
            "Production kernel has no COORD_SHIFT: promote the reviewed candidate before running; this runner never edits RTL")
    require(sha(SOURCE) != BASE_SHA256, "Production is still the original pre-grid kernel")
    for name in ("LICENSE.TXT", "vlib.exe", "vlog.exe", "vsim.exe"):
        require((SIM / name).is_file(), "Missing ModelSim file: " + str(SIM / name))
    return {str(path.resolve()): sha(path) for path in (SOURCE, BASE, Path(__file__).resolve())}


def prepare_out(name):
    preconditions()
    path = OUT / name
    require(path.resolve().is_relative_to(OUT.resolve()), "Grid outputs must stay inside the new suite")
    require(not path.exists(), "Never overwrite existing grid evidence: " + str(path))
    path.mkdir(parents=True, exist_ok=False)
    return path


def replace_exact(text, old, new, count=1):
    require(text.count(old) == count, "Unexpected original bench structure: " + repr(old))
    return text.replace(old, new)
