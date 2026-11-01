"""Compare endpoint/branch splitting against the unchanged legacy extractor.

All generated handwriting-like images are synthetic. No OCR, real-capture
quality claim, GRBL transmission, RTL simulation or TD invocation is made.
"""
from pathlib import Path
from datetime import datetime, timezone
from collections import Counter
import argparse
import ast
import colorsys
import hashlib
import importlib.util
import json
import math
import sys
import time

sys.dont_write_bytecode = True
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "model/doc_stroke_reference.py"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest().upper()


def load_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def make_image(lines=(), dots=(), width=1):
    image = Image.new("L", (320, 320), 0)
    draw = ImageDraw.Draw(image)
    for line in lines:
        draw.line(line, fill=1, width=width)
    for point in dots:
        draw.point(point, fill=1)
    return np.asarray(image, dtype=np.uint8).copy()


def fixtures():
    # The Qi-like case is a constructed stroke-connection stress pattern,
    # not a photographed or font-rendered sample of a person's handwriting.
    qi = [[(158, 80), (163, 85)], [(105, 100), (215, 100)],
          [(130, 100), (190, 160)], [(190, 100), (130, 160)],
          [(130, 160), (130, 210)], [(190, 160), (190, 210)]]
    definitions = [
        ("qi_like_connection", qi, [], 1, "Synthetic Qi-like connected strokes; not a real handwriting capture."),
        ("plus_cross", [[(160, 95), (160, 215)], [(100, 155), (220, 155)]], [], 1, "Four-way original-degree branch."),
        ("tee_sharp_branch", [[(105, 145), (215, 145)], [(160, 95), (160, 145)]], [], 1, "A vertical arrival cannot turn 90 degrees through the T branch."),
        ("why_fortyfive", [[(110, 95), (160, 145), (210, 95)], [(160, 145), (160, 205)]], [], 1, "Y branch allows an available 45-degree continuation."),
        ("two_tees_consumed_branch", [[(90, 150), (230, 150)], [(130, 100), (130, 150)], [(190, 150), (190, 205)]], [], 1, "Later visits retain original branch degree after incident edges are consumed."),
        ("branch_above_endpoints", [[(110, 185), (110, 105), (210, 105), (210, 185)], [(160, 105), (160, 205)]], [], 1, "The raster-first odd branch is skipped until true original endpoints are processed."),
        ("degree2_right_angles", [[(90, 105), (150, 105), (150, 175), (215, 175)]], [], 1, "Ordinary degree-two 90-degree bends remain a single path."),
        ("degree2_obtuse_bend", [[(90, 110), (155, 110), (115, 150)]], [], 1, "Ordinary degree-two 135-degree turn remains continuous."),
        ("rectangle_loop", [[(105, 105), (215, 105), (215, 195), (105, 195), (105, 105)]], [], 1, "Closed loop with no endpoints exercises the residual pass."),
        ("loop_with_branch", [[(105, 130), (215, 130), (215, 205), (105, 205), (105, 130)], [(160, 90), (160, 130)]], [], 1, "Endpoint arrival ends at a sharp branch while the loop remains covered."),
        ("dots_and_short_strokes", [[(125, 130), (127, 130)], [(185, 160), (185, 164)]], [(95, 100), (165, 115), (210, 185)], 1, "Preserve isolated dots, punctuation and two-pixel short strokes."),
        ("separated_characters", [[(70, 110), (70, 185), (110, 185)], [(155, 110), (195, 110)], [(175, 110), (175, 185)], [(235, 110), (235, 185)]], [(130, 190)], 1, "Disconnected glyph-like components must not receive pen-down bridges."),
        ("heavy_pen_cross", [[(160, 95), (160, 210)], [(105, 155), (215, 155)]], [], 7, "Heavy binary pen strokes undergo the existing thinning unchanged."),
        ("qi_like_heavy_pen", qi, [], 5, "Heavy synthetic Qi-like pattern; no real-capture quality inference."),
        ("blank_paper", [], [], 1, "Empty negative case must yield no paths or motion points."),
    ]
    return [{"name": name, "image": make_image(lines, dots, width), "description": description,
             "sample_type": "SYNTHETIC", "input_stroke_width_px": width}
            for name, lines, dots, width, description in definitions]


def component_count(skeleton, edges):
    unseen = {(int(x), int(y)) for y, x in zip(*np.nonzero(skeleton))}
    adjacency = {}
    for a, b in edges:
        adjacency.setdefault(a, set()).add(b)
        adjacency.setdefault(b, set()).add(a)
    count = 0
    while unseen:
        stack = [unseen.pop()]
        count += 1
        while stack:
            for nxt in adjacency.get(stack.pop(), ()):
                if nxt in unseen:
                    unseen.remove(nxt)
                    stack.append(nxt)
    return count


def expand_path(stroke):
    points = list(stroke.points)
    if stroke.closed:
        points.append(points[0])
    unit = [points[0]]
    for target in points[1:]:
        prev = unit[-1]
        dx, dy = target[0]-prev[0], target[1]-prev[1]
        assert dx == 0 or dy == 0 or abs(dx) == abs(dy), "non-collinear compressed segment"
        assert dx or dy, "zero-length segment"
        sx, sy = (dx > 0)-(dx < 0), (dy > 0)-(dy < 0)
        for _ in range(max(abs(dx), abs(dy))):
            unit.append((unit[-1][0]+sx, unit[-1][1]+sy))
    return unit


def metrics(ref, skeleton, strokes, edges, passes):
    degree = Counter(point for edge in edges for point in edge)
    counts = Counter()
    branch_sharp = branch_45 = degree2_sharp = 0
    for stroke in strokes:
        unit = expand_path(stroke)
        for a, b in zip(unit, unit[1:]):
            assert skeleton[a[1], a[0]] and skeleton[b[1], b[0]], "pen-down crosses blank pixel"
            counts[tuple(sorted((a, b)))] += 1
        for a, b, c in zip(unit, unit[1:], unit[2:]):
            incoming = ref.DIRS.index((b[0]-a[0], b[1]-a[1]))
            outgoing = ref.DIRS.index((c[0]-b[0], c[1]-b[1]))
            turn = min((outgoing-incoming) % 8, (incoming-outgoing) % 8)
            branch_sharp += int(degree[b] >= 3 and turn > 1)
            branch_45 += int(degree[b] >= 3 and turn == 1)
            degree2_sharp += int(degree[b] == 2 and turn > 1)
    assert set(counts) == edges, "missing or unexpected skeleton edge"
    assert all(value == 1 for value in counts.values()), "skeleton edge traversed more than once"
    expected_dots = {(int(x), int(y)) for y, x in zip(*np.nonzero(skeleton)) if not degree[(int(x), int(y))]}
    actual_dots = [s.points[0] for s in strokes if len(s.points) == 1 and not s.closed]
    assert len(actual_dots) == len(set(actual_dots)) and set(actual_dots) == expected_dots
    started = time.perf_counter()
    route, baseline, planned, fallback = ref.plan(strokes, passes=passes, window=32)
    planning_seconds = time.perf_counter()-started
    stream = ref.point_stream(strokes, route)
    recovered, dots = ref.expand_stream(stream)
    assert recovered == edges and set(dots) == expected_dots
    assert planned <= baseline, "planner failed its retained-baseline safeguard"
    assert len(strokes) <= 2048 and len(stream) <= 8192 and len(edges) <= 32768
    for x, y, *_ in stream:
        mx, my = ref.machine((x, y))
        assert 1000 <= mx <= 20000 and 1000 <= my <= 11688
    return {
        "edge_count": len(edges), "skeleton_components": component_count(skeleton, edges),
        "path_count": len(strokes), "point_count": len(stream), "dot_count": len(dots),
        "closed_path_count": sum(s.closed for s in strokes),
        "extraction_starts_at_original_endpoint": sum(degree[s.points[0]] == 1 for s in strokes),
        "branch_turns_over_45_degrees": branch_sharp,
        "branch_turns_exactly_45_degrees": branch_45,
        "degree2_sharp_turns_preserved": degree2_sharp,
        "draw_G1_xy_endpoints": sum(not start for _, _, start, _, _ in stream),
        "path_pen_down_events": len(strokes),
        "baseline_travel_cmm": baseline, "planned_travel_cmm": planned,
        "planner_baseline_fallback": fallback, "planner_passes": passes,
        "planning_seconds_python": planning_seconds,
        "edges_exactly_once": True, "no_pen_down_blank_bridges": True,
        "isolated_dots_preserved": True, "capacity_pass": True,
        "machine_bounds_pass": True, "route": route, "stream": stream,
        "actual_plot_time": "NOT_RUN", "hardware_planning_time": "NOT_RUN",
    }


def font(size):
    for path in ("C:/Windows/Fonts/arial.ttf", "C:/Windows/Fonts/segoeui.ttf"):
        if Path(path).is_file():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def draw_panel(ref, skeleton, strokes, metric, title):
    scale, margin, header = 2, 22, 100
    image = Image.new("RGB", (320*scale+2*margin, 180*scale+header+margin), "white")
    draw = ImageDraw.Draw(image)
    draw.text((margin, 10), title, fill="#172238", font=font(21))
    draw.text((margin, 39), f"paths {metric['path_count']}   points {metric['point_count']}   sharp branch turns {metric['branch_turns_over_45_degrees']}", fill="#334155", font=font(16))
    draw.text((margin, 64), f"travel {metric['planned_travel_cmm']/100:.2f} mm | ring = start, arrow = direction", fill="#475569", font=font(15))
    transform = lambda p: (margin+p[0]*scale, header+(p[1]-70)*scale)
    for y, x in zip(*np.nonzero(skeleton)):
        xx, yy = transform((int(x), int(y)))
        draw.rectangle((xx, yy, xx+1, yy+1), fill="#d9dde3")
    for order, (index, reverse, seam) in enumerate(metric["route"], 1):
        stroke = strokes[index]
        points = list(stroke.points)
        if stroke.closed:
            points = [points[(seam+(-k if reverse else k)) % len(points)] for k in range(len(points))]
            points.append(points[0])
        elif reverse:
            points.reverse()
        color = tuple(int(v*205) for v in colorsys.hsv_to_rgb((order*0.61803398875) % 1, .85, 1))
        positions = [transform(point) for point in points]
        if len(positions) > 1:
            draw.line(positions, fill=color, width=3)
            a, b = positions[:2]
            length = math.hypot(b[0]-a[0], b[1]-a[1])
            if length:
                ux, uy = (b[0]-a[0])/length, (b[1]-a[1])/length
                reach = min(18.0, length*.75)
                tip = (a[0]+ux*reach, a[1]+uy*reach)
                draw.polygon([tip, (tip[0]-ux*8-uy*4, tip[1]-uy*8+ux*4),
                              (tip[0]-ux*8+uy*4, tip[1]-uy*8-ux*4)], fill=color)
        start = positions[0]
        draw.ellipse((start[0]-4, start[1]-4, start[0]+4, start[1]+4), outline=color, width=2)
        label = str(order)
        box = draw.textbbox((start[0]+5, start[1]-17), label, font=font(15))
        draw.rectangle((box[0]-1, box[1]-1, box[2]+1, box[3]+1), fill="white")
        draw.text((start[0]+5, start[1]-17), label, fill=color, font=font(15))
    draw.rectangle((margin, header, margin+639, header+359), outline="#cbd5e1")
    return image


def strip_stream(metric):
    return {key: value for key, value in metric.items() if key not in ("route", "stream")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "reports/stroke_split_reference")
    args = parser.parse_args()
    output = args.output.resolve()
    assert output.is_relative_to(ROOT) and "work" not in [part.lower() for part in output.parts]
    ref = load_module(REFERENCE, "stroke_split_new_reference")
    source = Path(ref.REFERENCE_SOURCE["path"])
    assert sha(source) == ref.REFERENCE_SOURCE["sha256"], "original reference changed"
    old = load_module(source, "stroke_split_legacy_reference")
    before = {str(path): sha(path) for path in (REFERENCE, source, Path(__file__).resolve())}
    old_ast, new_ast = ast.parse(source.read_text()), ast.parse(REFERENCE.read_text())
    functions = lambda tree: {node.name: ast.dump(node, include_attributes=False) for node in tree.body if isinstance(node, ast.FunctionDef)}
    old_functions, new_functions = functions(old_ast), functions(new_ast)
    unchanged = ["thin", "graph_edges", "machine", "distance", "squared", "endpoints", "route_cost", "plan", "point_stream", "expand_stream"]
    assert all(old_functions[name] == new_functions[name] for name in unchanged)
    output.mkdir(parents=True, exist_ok=True)
    run = output / datetime.now(timezone.utc).strftime("run_%Y%m%dT%H%M%S_%fZ")
    run.mkdir(exist_ok=False)
    errors, results, comparisons = [], [], []
    for case in fixtures():
        name, image = case["name"], case["image"]
        directory = run / name
        directory.mkdir()
        skeleton, pairs = ref.thin(image)
        edges = ref.graph_edges(skeleton)
        Image.fromarray(255-image*255).save(directory / "synthetic_input.png")
        Image.fromarray(255-skeleton*255).save(directory / "skeleton.png")
        start = time.perf_counter()
        legacy, legacy_edges = ref.extract(skeleton, policy="legacy")
        legacy_seconds = time.perf_counter()-start
        original_legacy, original_edges = old.extract(skeleton)
        assert [(s.points, s.closed) for s in legacy] == [(s.points, s.closed) for s in original_legacy], name+" legacy drift"
        assert legacy_edges == original_edges == edges
        start = time.perf_counter()
        current, current_edges = ref.extract(skeleton)
        current_seconds = time.perf_counter()-start
        assert current_edges == edges
        policies = {}
        for policy, strokes, seconds in (("legacy", legacy, legacy_seconds), ("endpoint_branch45", current, current_seconds)):
            modes = {str(passes): metrics(ref, skeleton, strokes, edges, passes) for passes in (0, 2)}
            modes["0"]["extraction_seconds_python"] = seconds
            if policy == "endpoint_branch45":
                assert all(mode["branch_turns_over_45_degrees"] == 0 for mode in modes.values()), name+" sharp branch remains"
            policies[policy] = {"strokes": [{"points": s.points, "closed": s.closed} for s in strokes],
                                "planning": modes}
        if name in ("degree2_right_angles", "degree2_obtuse_bend"):
            assert len(current) == 1 and policies["endpoint_branch45"]["planning"]["0"]["degree2_sharp_turns_preserved"] > 0
        if name == "branch_above_endpoints":
            degree = Counter(point for edge in edges for point in edge)
            assert degree[legacy[0].points[0]] >= 3 and degree[current[0].points[0]] == 1
        if name == "why_fortyfive":
            assert policies["endpoint_branch45"]["planning"]["0"]["branch_turns_exactly_45_degrees"] > 0
        if name == "blank_paper":
            assert not current
        payload = {key: value for key, value in case.items() if key != "image"}
        payload.update(thinning_pairs=pairs, policies=policies)
        (directory / "paths.json").write_text(json.dumps(payload, indent=2)+"\n", encoding="utf-8")
        left = draw_panel(ref, skeleton, legacy, policies["legacy"]["planning"]["0"], "LEGACY | SYNTHETIC")
        right = draw_panel(ref, skeleton, current, policies["endpoint_branch45"]["planning"]["0"], "ENDPOINT + BRANCH <=45 DEG | SYNTHETIC")
        comparison = Image.new("RGB", (left.width+right.width+16, left.height+50), "#edf2f7")
        draw = ImageDraw.Draw(comparison)
        draw.text((22, 12), name, fill="#172238", font=font(23))
        comparison.paste(left, (0, 50));comparison.paste(right, (left.width+16, 50))
        comparison.save(directory / "comparison.png")
        comparisons.append((name, comparison))
        results.append({"name": name, "sample_type": "SYNTHETIC", "thinning_pairs": pairs,
                        "legacy": {key: strip_stream(value) for key, value in policies["legacy"]["planning"].items()},
                        "endpoint_branch45": {key: strip_stream(value) for key, value in policies["endpoint_branch45"]["planning"].items()},
                        "legacy_matches_exact_original": True})
        print(name+": PASS paths "+str(len(legacy))+" -> "+str(len(current)), flush=True)
    capacity = []
    probe = make_image([[(105, 125), (115, 125)]])
    for limits, expected in (({"max_edges": 0}, 2), ({"max_paths": 0}, 3), ({"max_points": 1}, 4)):
        try:
            ref.extract(probe, **limits)
        except ref.CapacityError as error:
            assert error.code == expected
            capacity.append({"limits": limits, "error_code": error.code, "status": "PASS"})
        else:
            raise AssertionError("capacity overflow accepted")
    thumbs = []
    for _, comparison in comparisons:
        thumb = comparison.copy();thumb.thumbnail((900, 340));thumbs.append(thumb)
    tile_h = max(image.height for image in thumbs)+12
    overview = Image.new("RGB", (1800, math.ceil(len(thumbs)/2)*tile_h), "#e2e8f0")
    for index, thumb in enumerate(thumbs):
        overview.paste(thumb, ((index % 2)*900, (index//2)*tile_h))
    overview.save(run / "COMPARISON_OVERVIEW.png")
    after = {str(path): sha(path) for path in (REFERENCE, source, Path(__file__).resolve())}
    assert before == after, "reference or runner changed during comparison"
    artifacts = sorted(path for path in run.rglob("*") if path.is_file())
    result = {
        "status": "PASS", "errors": errors, "created_utc": datetime.now(timezone.utc).isoformat(),
        "reference_source": ref.REFERENCE_SOURCE, "input_hashes": before, "input_hashes_after": after,
        "unchanged_integer_functions_ast_verified": unchanged, "case_count": len(results),
        "cases": results, "capacity_rejection_cases": capacity,
        "evidence_hashes": {str(path.relative_to(output)): sha(path) for path in artifacts},
        "run_directory": str(run), "hardware_status": "NOT_RUN",
        "limits": ["All images are synthetic; no confirmed photographed Qi/handwriting sample was used.",
                   "No claim of improved real handwriting readability or actual machine drawing time.",
                   "Nearest-neighbor, 2-opt, machine mapping and integer distance functions retain their original implementations.",
                   "Plots show camera-grid coordinates; machine mapping and existing downstream mirror remain unchanged."],
    }
    payload = json.dumps(result, indent=2)+"\n"
    (run / "RESULTS.json").write_text(payload, encoding="utf-8")
    (output / "RESULTS.json").write_text(payload, encoding="utf-8")
    print(json.dumps({"status": "PASS", "case_count": len(results), "results": str(output / "RESULTS.json"),
                      "results_sha256": sha(output / "RESULTS.json"), "overview": str(run / "COMPARISON_OVERVIEW.png")}, indent=2))


if __name__ == "__main__":
    main()
