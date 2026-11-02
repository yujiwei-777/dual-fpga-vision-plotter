"""Train a remote-detail model without changing the strict160 FPGA contract.

The ROI is already cropped to the object before the 64x64 input is formed, so
distance is simulated by reducing source detail and reconstructing the same
64x64 crop.  The target is not shrunk into a new border canvas.
"""
from __future__ import annotations

import copy
import json
import random
import shutil
import sys
from pathlib import Path

import cv2
import numpy as np
import torch
import torch.nn.functional as F

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
import train_model as base  # type: ignore

network = base.network
BASE_OUT = HERE / "model" / "fc3_all1170_selected"
OUT = HERE / "model" / "fc3_remote_detail_selected"
SEED = 20261029


def detail_transform(src: np.ndarray, rng: np.random.Generator,
                     scale_range=(0.45, 0.75), blur_range=(0.15, 0.85),
                     noise_range=(0.3, 1.8)) -> np.ndarray:
    scale = float(rng.uniform(*scale_range))
    n = max(12, min(64, int(round(64 * scale))))
    low = cv2.resize(src, (n, n), interpolation=cv2.INTER_AREA)
    z = cv2.resize(low, (64, 64), interpolation=cv2.INTER_LINEAR)
    z = cv2.GaussianBlur(z, (3, 3), sigmaX=float(rng.uniform(*blur_range)))
    z = z.astype(np.float32) * float(rng.uniform(0.90, 1.08)) + float(rng.uniform(-10, 10))
    z += rng.normal(0, float(rng.uniform(*noise_range)), z.shape)
    return np.clip(np.rint(z), 0, 255).astype(np.uint8)


def train_batch(srcs: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    out = []
    for src in srcs:
        if rng.random() < 0.25:
            out.append(detail_transform(src, rng, (0.78, 1.0), (0.05, 0.35), (0.1, 0.8)))
        else:
            out.append(detail_transform(src, rng))
    return np.stack(out)


def make_eval(srcs: np.ndarray, seed: int, scale_range: tuple[float, float]) -> np.ndarray:
    rng = np.random.default_rng(seed)
    return np.stack([detail_transform(x, rng, scale_range) for x in srcs])


def metrics(model, images, labels, params, qat):
    if qat:
        w, b = network.quantize(model, params)
        raw = network.integer_scores(images, w, b, params)
    else:
        raw = network.float_scores(model, images)
    return network.metrics(raw, labels)


def train_phase(model, teacher, images, labels, train, rows, dev_images, dev_labels,
                remote_sets, epochs, qat, rng, params=None):
    opt = torch.optim.AdamW([p for p in model.parameters() if p.requires_grad],
                            lr=4.0e-5 if not qat else 8.0e-6, weight_decay=6e-5)
    sch = torch.optim.lr_scheduler.CosineAnnealingLR(opt, epochs,
                                                     eta_min=8.0e-6 if not qat else 2.0e-6)
    best = None
    for ep in range(1, epochs + 1):
        model.train()
        weights = np.asarray([2.3 if rows[int(i)].get("status") == "confirmed" else 1.0
                              for i in train], np.float64)
        order = train[rng.choice(len(train), len(train) * 2, replace=True,
                                 p=weights / weights.sum())]
        for st in range(0, len(order), 64):
            sel = order[st:st + 64]
            remote = network.tensor(train_batch(images[sel], rng), "max_rgb")
            native = network.tensor(images[sel], "max_rgb")
            pred_r = network.qat_forward(model, remote, params) if qat else model(remote)
            pred_n = network.qat_forward(model, native, params) if qat else model(native)
            with torch.no_grad():
                teach = teacher(native)
            loss = (network.loss_fn(pred_r, torch.from_numpy(labels[sel]))
                    + network.loss_fn(pred_n, torch.from_numpy(labels[sel]))
                    + 0.35 * F.mse_loss(torch.tanh(pred_n[:, 3:] / 32),
                                        torch.tanh(teach[:, 3:] / 32)))
            opt.zero_grad(set_to_none=True)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(model.parameters(), 3)
            opt.step()
        sch.step()
        nm = metrics(model, dev_images, dev_labels, params, qat)
        rm = [metrics(model, x, dev_labels, params, qat) for x in remote_sets]
        remote_acc = float(np.mean([m["shape_accuracy"] for m in rm]))
        eligible = int(nm["shape_accuracy"] >= 0.95)
        key = (eligible, remote_acc, nm["shape_accuracy"])
        print(json.dumps({"qat": qat, "epoch": ep, "normal": nm["shape_accuracy"],
                          "remote": remote_acc}, ensure_ascii=False), flush=True)
        if best is None or key > best[0]:
            best = (key, {k: v.detach().clone() for k, v in model.state_dict().items()}, ep,
                    {"normal": nm, "remote": rm, "remote_accuracy": remote_acc})
    model.load_state_dict(best[1])
    return best


def main():
    torch.set_num_threads(4)
    torch.set_num_interop_threads(1)
    cv2.setNumThreads(1)
    random.seed(SEED)
    np.random.seed(SEED)
    torch.manual_seed(SEED)
    torch.use_deterministic_algorithms(True)
    images, labels, rows = base.load_data()
    train, dev = base.stratified_split(rows)
    dev_images, dev_labels = images[dev], labels[dev]
    remote_sets = [
        make_eval(dev_images, SEED + 1, (0.72, 0.84)),
        make_eval(dev_images, SEED + 2, (0.56, 0.70)),
        make_eval(dev_images, SEED + 3, (0.40, 0.54)),
    ]
    base_q = np.load(BASE_OUT / "quantized.npz")
    base_p = json.loads((BASE_OUT / "quantization.json").read_text(encoding="utf-8"))
    baseline = {
        "normal": network.metrics(network.integer_scores(dev_images,
            [base_q[f"w{i}"] for i in range(3)], [base_q[f"b{i}"] for i in range(3)], base_p), dev_labels),
        "remote": [network.metrics(network.integer_scores(x,
            [base_q[f"w{i}"] for i in range(3)], [base_q[f"b{i}"] for i in range(3)], base_p), dev_labels)
                   for x in remote_sets],
    }
    model = network.FactoredCNN("max_rgb")
    model.load_state_dict(torch.load(BASE_OUT / "cnn_float.pt", map_location="cpu", weights_only=True))
    teacher = copy.deepcopy(model).eval()
    for p in teacher.parameters():
        p.requires_grad_(False)
    rng = np.random.default_rng(SEED)
    fp = train_phase(model, teacher, images, labels, train, rows, dev_images, dev_labels,
                     remote_sets, 14, False, rng)
    params = network.calibrate(model, images[train])
    qp = train_phase(model, teacher, images, labels, train, rows, dev_images, dev_labels,
                     remote_sets, 8, True, rng, params)
    params = network.calibrate(model, images[train])
    shutil.rmtree(OUT, ignore_errors=True)
    hashes = network.export(OUT, model, params, {
        "training_seed": SEED, "training_rows": int(len(train)), "validation_rows": int(len(dev)),
        "initialization": "fc3_all1170_selected/cnn_float.pt",
        "remote_augmentation": {"method": "downsample_then_upsample_same_64x64_crop",
            "train_scale": "0.45..0.75 for 75%; 0.78..1.00 for 25%",
            "eval_scales": ["0.72..0.84", "0.56..0.70", "0.40..0.54"],
            "rgb128_border": False},
        "source_frames": 1170, "confirmed_samples_in_training": True,
        "board_validation": "NOT_RUN", "bit_generated": False})
    q = np.load(OUT / "quantized.npz")
    w, b = [q[f"w{i}"] for i in range(3)], [q[f"b{i}"] for i in range(3)]
    new = {"normal": network.metrics(network.integer_scores(dev_images, w, b, params), dev_labels),
           "remote": [network.metrics(network.integer_scores(x, w, b, params), dev_labels) for x in remote_sets],
           "all_1170_fit_check": network.metrics(network.integer_scores(images, w, b, params), labels)}
    def status_metrics(pkg_w, pkg_b, indices):
        out = {}
        for status in ("auto_labeled", "confirmed"):
            ii = np.asarray([i for i in indices if rows[int(i)].get("status") == status], dtype=np.int64)
            out[status] = network.metrics(network.integer_scores(images[ii], pkg_w, pkg_b, params), labels[ii])
        return out
    baseline["status_on_dev"] = status_metrics(
        [base_q[f"w{i}"] for i in range(3)], [base_q[f"b{i}"] for i in range(3)], dev)
    new["status_on_dev"] = status_metrics(w, b, dev)
    report = {
        "status": "FC3_REMOTE_DETAIL_RETRAIN_COMPLETE", "source": str(base.DATA),
        "split": {"seed": SEED, "train_rows": int(len(train)), "dev_rows": int(len(dev))},
        "baseline_current_model": baseline, "new_model": new,
        "float_phase_best": {"epoch": fp[2], "metrics": fp[3]},
        "qat_phase_best": {"epoch": qp[2], "metrics": qp[3]}, "hashes": hashes,
        "architecture_contract": {"classes": 9, "class_id": "1..9", "fc3": True,
            "input": "RGB8 64x64", "weights": 13512, "biases": 27, "background_head": False},
        "source_hashes": {"images_strict160.npz": base.sha(base.DATA / "images_strict160.npz"),
                          "records.json": base.sha(base.DATA / "records.json"),
                          "base_model_quantized.npz": base.sha(BASE_OUT / "quantized.npz")},
        "board_validation": "NOT_RUN", "bit_generated": False,
        "notes": ["Synthetic remote detail uses downsample/upsample because the ROI is recropped to 64x64.",
                   "No real long-distance frames are present; validate distance on the camera before ROM replacement.",
                   "The existing all-1170 model is unchanged."]}
    reports = HERE / "reports"
    reports.mkdir(exist_ok=True)
    (reports / "REMOTE_DETAIL_TRAINING_REPORT.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
