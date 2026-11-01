from pathlib import Path
import hashlib
import json
import sys

sys.path.insert(0, str(Path(__file__).parent))
from text_trace_reference import trace


def image():
    return [[255] * 320 for _ in range(180)]


cases = {}
im = image()
cases["blank"] = len(trace(im)) == 0
im = image(); im[90][140] = 0
cases["single_pixel_ignored"] = len(trace(im)) == 0
im = image()
for y in range(40, 70):
    for x in range(40, 280):
        if y in (40, 69) or x in (40, 279):
            im[y][x] = 0
r = trace(im)
cases["box_has_horizontal_and_vertical"] = len(r) >= 2 and r[-1][0] == r[-1][2]
im = image()
for y in range(180):
    for x in range(320):
        if y % 2 == 0:
            im[y][x] = 0
r = trace(im)
cases["bounded_256"] = len(r) <= 256

out = {"cases": cases, "pass": all(cases.values()), "reference": "row-centre-plus-envelope-v1"}
print(json.dumps(out, indent=2))
if not out["pass"]:
    raise SystemExit(1)
