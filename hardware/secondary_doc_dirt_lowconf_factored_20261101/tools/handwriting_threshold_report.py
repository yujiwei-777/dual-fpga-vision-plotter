"""Deterministic integer threshold comparison for the 320x180 document path.

This is a development report, not a claim of camera or plotter performance.
It generates known black-ink masks, applies the same 4x4-center sampling
contract used by the frontend, and compares fixed, Otsu, and local-background
thresholds.  The current RTL remains fixed Y <= 112 until real handwriting and
blank-paper captures are available.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import cv2
import numpy as np


W, H = 320, 180
SEED = 20261024


def paper_background(rng: np.random.Generator, index: int) -> np.ndarray:
    background = np.full((H, W), 226.0, np.float32)
    scenario = index % 5
    yy, xx = np.mgrid[0:H, 0:W]
    if scenario == 1:
        background += 30.0 * xx / (W - 1) - 15.0
    elif scenario == 2:
        background -= 27.0 * np.exp(-((xx - 80.0) ** 2 + (yy - 92.0) ** 2) / 6000.0)
    elif scenario == 3:
        background -= 22.0 * np.exp(-((xx - 250.0) ** 2 + (yy - 40.0) ** 2) / 3800.0)
        background += 12.0 * yy / (H - 1)
    elif scenario == 4:
        background += rng.normal(0.0, 2.0, (H, W))
    background += rng.normal(0.0, 1.4 if scenario != 4 else 2.8, (H, W))
    return np.clip(np.rint(background), 0, 255).astype(np.uint8)


def draw_truth(rng: np.random.Generator, index: int) -> tuple[np.ndarray, np.ndarray]:
    truth = np.zeros((H, W), np.uint8)
    # Separate strokes, dots, a loop, and a crossing. The coordinates are in
    # the active 320x180 grid so the result is directly comparable to RTL.
    shift = int(index % 7) - 3
    cv2.line(truth, (22, 28 + shift), (132, 44 + shift), 1, 1)
    cv2.line(truth, (45, 15), (50, 126), 1, 1)
    cv2.line(truth, (174, 30), (269, 28), 1, 2 if index % 3 == 0 else 1)
    cv2.line(truth, (174, 30), (215, 126), 1, 1)
    cv2.circle(truth, (278, 92), 22 + index % 4, 1, 1)
    truth[145 + index % 3, 62 + index % 5] = 1
    truth[151 + index % 4, 70 + index % 6] = 1

    # Ink contrast varies deliberately; the weakest cases expose threshold
    # behavior without introducing an unmodelled camera color pipeline.
    ink_level = 48.0 + float((index * 17) % 76)
    image = paper_background(rng, index)
    image[truth != 0] = np.uint8(ink_level)
    return image, truth


def otsu_integer(image: np.ndarray) -> int:
    hist = np.bincount(image.ravel(), minlength=256).astype(np.int64)
    total = int(image.size)
    sum_total = int(np.dot(np.arange(256, dtype=np.int64), hist))
    w0 = 0
    sum0 = 0
    best_num = -1
    best_t = 0
    for t in range(256):
        w0 += int(hist[t])
        sum0 += t * int(hist[t])
        w1 = total - w0
        if w0 == 0 or w1 == 0:
            continue
        # Compare the unnormalized between-class variance to avoid division.
        d = sum0 * w1 - (sum_total - sum0) * w0
        score = d * d
        if score > best_num:
            best_num = score
            best_t = t
    return best_t


def masks(image: np.ndarray) -> dict[str, np.ndarray]:
    result: dict[str, np.ndarray] = {"fixed112": image <= 112}
    t = otsu_integer(image)
    result["otsu"] = image <= t
    for radius in (5, 9, 15):
        local = cv2.blur(image, (radius, radius), borderType=cv2.BORDER_REFLECT)
        for c in (6, 10, 14):
            result[f"local{radius}_c{c}"] = image.astype(np.int16) < (local.astype(np.int16) - c)
    med = cv2.medianBlur(image, 3)
    hi = cv2.dilate(image, np.ones((3, 3), np.uint8))
    lo = cv2.erode(image, np.ones((3, 3), np.uint8))
    flat = (hi.astype(np.int16) - lo.astype(np.int16)) <= 28
    edge_preserved = np.where(flat, med, image)
    local9 = cv2.blur(edge_preserved, (9, 9), borderType=cv2.BORDER_REFLECT)
    result["local9_c10_edge_median"] = edge_preserved.astype(np.int16) < (local9.astype(np.int16) - 10)
    return result


def metric(pred: np.ndarray, truth: np.ndarray) -> dict[str, float]:
    p = pred.astype(bool)
    t = truth.astype(bool)
    tp = int(np.count_nonzero(p & t))
    fp = int(np.count_nonzero(p & ~t))
    fn = int(np.count_nonzero(~p & t))
    precision = tp / (tp + fp) if tp + fp else 1.0
    recall = tp / (tp + fn) if tp + fn else 1.0
    f1 = 2.0 * precision * recall / (precision + recall) if precision + recall else 1.0
    return {
        "precision": precision,
        "recall": recall,
        "f1": f1,
        "false_pixels": float(fp),
        "truth_pixels": float(tp + fn),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, default=Path("artifacts/handwriting_threshold_report_20261024.json"))
    parser.add_argument("--samples", type=int, default=100)
    args = parser.parse_args()
    rng = np.random.default_rng(SEED)
    aggregate: dict[str, list[dict[str, float]]] = {}
    blank_aggregate: dict[str, list[dict[str, float]]] = {}
    otsu_values: list[int] = []
    for i in range(args.samples):
        image, truth = draw_truth(rng, i)
        otsu_values.append(otsu_integer(image))
        for name, pred in masks(image).items():
            aggregate.setdefault(name, []).append(metric(pred, truth))
        blank = paper_background(rng, i)
        empty_truth = np.zeros((H, W), np.uint8)
        for name, pred in masks(blank).items():
            blank_aggregate.setdefault(name, []).append(metric(pred, empty_truth))

    summary = {}
    for name, values in aggregate.items():
        summary[name] = {
            key: float(np.mean([item[key] for item in values]))
            for key in ("precision", "recall", "f1", "false_pixels")
        }
        summary[name]["blank_false_pixels"] = float(np.mean(
            [item["false_pixels"] for item in blank_aggregate[name]]))
        summary[name]["blank_false_pixel_rate"] = summary[name]["blank_false_pixels"] / (W * H)
    ranked = sorted(summary, key=lambda name: (summary[name]["f1"], summary[name]["precision"]), reverse=True)
    result = {
        "contract": {
            "grid": [W, H],
            "sample": "(4*x+2, 4*y+2) equivalent active raster",
            "rtl_current": "fixed Y <= 112",
            "real_capture_status": "NOT_AVAILABLE",
        },
        "synthetic": {
            "seed": SEED,
            "samples": args.samples,
            "scenarios": ["flat", "gradient", "left_shadow", "right_shadow", "grain"],
            "ground_truth": "known 1-4 sample grid strokes, dots, loop and crossing",
            "otsu_threshold_mean": float(np.mean(otsu_values)),
            "otsu_threshold_min": int(min(otsu_values)),
            "otsu_threshold_max": int(max(otsu_values)),
        },
        "summary": summary,
        "ranked_by_f1": ranked,
        "path_proxy": path_proxy(rng),
        "decision": {
            "hardware": "KEEP_FIXED112",
            "reason": "Otsu/local candidates need a histogram or line buffers and are not validated on real black-pen captures.",
            "next_gate": "Repeat on labeled black-pen and blank-paper captures before changing RTL.",
        },
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"out": str(args.out), "ranked_by_f1": ranked[:5]}, indent=2))


def path_proxy(rng: np.random.Generator) -> dict[str, object]:
    # Run the checked integer thinning/planner only on a representative clean
    # pattern and its shadowed counterpart; threshold sweeps stay lightweight.
    import sys
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "model"))
    from doc_stroke_reference import CapacityError, prepare

    rows = {}
    for index in (0, 2):
        image, _ = draw_truth(rng, index)
        for name in ("fixed112", "otsu", "local9_c10", "local9_c10_edge_median"):
            canvas = np.zeros((320, 320), np.uint8)
            canvas[70:250, :] = masks(image)[name].astype(np.uint8)
            try:
                r = prepare(canvas)
                rows[f"scenario_{index}_{name}"] = {
                    "edge_count": r["edge_count"],
                    "path_count": r["path_count"],
                    "point_count": r["point_count"],
                    "planned_travel_distance_cmm": r["planned_distance"],
                    "baseline_travel_distance_cmm": r["baseline_distance"],
                    "dot_count": len(r["dots"]),
                    "planner_capacity": "PASS",
                }
            except CapacityError as exc:
                rows[f"scenario_{index}_{name}"] = {"planner_capacity": "FAIL", "error": str(exc)}
    return rows


if __name__ == "__main__":
    main()
