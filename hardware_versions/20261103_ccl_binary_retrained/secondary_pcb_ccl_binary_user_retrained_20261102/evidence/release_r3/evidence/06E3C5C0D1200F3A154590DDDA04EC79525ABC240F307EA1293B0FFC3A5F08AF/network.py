"""Color-independent shape CNN and full-precision RGB channel sums.

Native RGB8 is the sole public input. All preprocessing is integer-defined.
No old checkpoint is loaded. Text ROM order: conv1, conv2, shape FC.
"""
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import numpy as np
import torch
from torch import nn
import torch.nn.functional as F


WEIGHT_COUNT = 13512
BIAS_COUNT = 27


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write_json(path, value):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False, allow_nan=False) + '\n', encoding='utf-8')


def preprocess(images, mode):
    images = np.asarray(images)
    if images.dtype != np.uint8 or images.ndim != 4 or images.shape[1:] != (64, 64, 3):
        raise ValueError('Expected nonempty RGB8 Nx64x64x3')
    if not len(images):
        raise ValueError('Empty input')
    maximum = images.max(axis=3)
    if mode == 'max_rgb':
        shape = maximum >> 1
    elif mode == 'chroma':
        shape = (maximum - images.min(axis=3)) >> 1
    else:
        raise ValueError('Unknown shape input')
    color = (images.astype(np.int64) >> 1).sum(axis=(1, 2))
    return shape[:, None].copy(), color


def tensor(images, mode):
    shape, color = preprocess(images, mode)
    return torch.from_numpy(shape).float()/128., torch.from_numpy(color).double()


class FactoredCNN(nn.Module):
    def __init__(self, mode):
        super().__init__()
        self.mode = mode
        self.conv1 = nn.Conv2d(1, 8, 3, padding=1)
        self.conv2 = nn.Conv2d(8, 16, 3, padding=1)
        self.shape_fc = nn.Linear(4096, 3)

    def features(self, x):
        first = F.relu(self.conv1(x))
        second = F.relu(self.conv2(F.max_pool2d(first, 2)))
        return first, second, F.max_pool2d(second, 2)

    def forward(self, inputs):
        x, color = inputs
        _, _, x = self.features(x)
        shape = self.shape_fc(x.permute(0, 2, 3, 1).reshape(len(x), -1))
        # Independent statistics are output scores, not trainable color logits.
        return torch.cat((color, shape.double()), dim=1)


def loss_fn(scores, labels):
    return F.cross_entropy(scores[:, 3:], labels[:, 1], label_smoothing=.02)


def metrics(scores, labels):
    scores, labels = np.asarray(scores), np.asarray(labels)
    predictions = np.stack((scores[:, :3].argmax(1), scores[:, 3:].argmax(1)), axis=1)
    correct = predictions == labels
    joint = correct.all(axis=1)
    actual, predicted = labels[:, 0]*3+labels[:, 1], predictions[:, 0]*3+predictions[:, 1]
    confusion = np.zeros((9, 9), np.int64)
    np.add.at(confusion, (actual, predicted), 1)
    per_class = []
    for i in range(9):
        mask = actual == i
        per_class.append({'class_id': i+1, 'samples': int(mask.sum()), 'correct': int(joint[mask].sum()),
                          'joint_accuracy': float(joint[mask].mean()) if mask.any() else None})
    return {'samples': len(labels), 'color_correct': int(correct[:, 0].sum()), 'shape_correct': int(correct[:, 1].sum()),
            'joint_correct': int(joint.sum()), 'color_accuracy': float(correct[:, 0].mean()),
            'shape_accuracy': float(correct[:, 1].mean()), 'joint_accuracy': float(joint.mean()),
            'confusion_9x9': confusion.tolist(), 'per_class': per_class, 'background_head': False}


@torch.no_grad()
def float_scores(model, images):
    model.eval()
    return np.concatenate([model(tensor(images[i:i+64], model.mode)).numpy() for i in range(0, len(images), 64)])


def fractional_bits(maximum):
    return min(15, max(-8, int(math.floor(math.log2(127./max(float(maximum), 1e-9))))))


@torch.no_grad()
def calibrate(model, train_images):
    model.eval()
    maxima = [0., 0.]
    for i in range(0, len(train_images), 64):
        x, _ = tensor(train_images[i:i+64], model.mode)
        first, second, _ = model.features(x)
        maxima = [max(maxima[0], float(first.max())), max(maxima[1], float(second.max()))]
    ab = [7] + [max(-8, fractional_bits(v)-1) for v in maxima]
    layers = (model.conv1, model.conv2, model.shape_fc)
    wb = [fractional_bits(float(layer.weight.abs().max())) for layer in layers]
    shifts = [ab[i]+wb[i]-ab[i+1] for i in range(2)]
    if not all(1 <= s <= 23 for s in shifts):
        raise ValueError('Unsupported conv shift')
    return {'shape_mode': model.mode, 'activation_fraction_bits': ab, 'weight_fraction_bits': wb,
            'conv_shifts': shifts, 'calibration_maxima': maxima, 'calibration_source': 'training_partition_only',
            'fc_conf_shift': [8, max(0, ab[2]+wb[2]-5)],
            'shape_fc_logit_fraction_bits': ab[2]+wb[2],
            'color_score_format': 'unsigned19 channel SUM of RGB8>>1, no division',
            'rounding': 'floor(acc/2**shift+0.5)', 'activation_clamp': [0, 127],
            'flatten': 'HWC', 'output_order': ['red', 'green', 'blue', 'triangular_prism', 'cylinder', 'cuboid']}


@torch.no_grad()
def quantize(model, params):
    ab, wb = params['activation_fraction_bits'], params['weight_fraction_bits']
    weights, biases = [], []
    for i, layer in enumerate((model.conv1, model.conv2, model.shape_fc)):
        input_bits = ab[i]
        weights.append(np.clip(np.floor(layer.weight.numpy()*2.**wb[i]+.5), -128, 127).astype(np.int8))
        bias = np.floor(layer.bias.numpy()*2.**(input_bits+wb[i])+.5).astype(np.int64)
        if np.any(bias < -(1 << 31)) or np.any(bias >= (1 << 31)):
            raise OverflowError('Bias overflow')
        biases.append(bias.astype(np.int32))
    return weights, biases


def fake_round(x):
    return x + (torch.floor(x+.5)-x).detach()


def qat_forward(model, inputs, params):
    x, color = inputs
    ab, wb = params['activation_fraction_bits'], params['weight_fraction_bits']
    def layer_values(layer, i, input_bits):
        weight = fake_round(layer.weight*2.**wb[i]).clamp(-128, 127)/2.**wb[i]
        bias = fake_round(layer.bias*2.**(input_bits+wb[i]))/2.**(input_bits+wb[i])
        return weight, bias
    for i, layer in enumerate((model.conv1, model.conv2)):
        weight, bias = layer_values(layer, i, ab[i])
        x = F.conv2d(x, weight, bias, padding=1)
        x = F.max_pool2d(fake_round(x*2.**ab[i+1]).clamp(0, 127)/2.**ab[i+1], 2)
    weight, bias = layer_values(model.shape_fc, 2, ab[2])
    shape = F.linear(x.permute(0, 2, 3, 1).reshape(len(x), -1), weight, bias)
    return torch.cat((color, shape.double()), dim=1)


@torch.no_grad()
def integer_scores(images, weights, biases, params, return_features=False):
    for i in range(2):
        bound = 127*np.abs(weights[i].astype(np.int64)).sum((1, 2, 3))+np.abs(biases[i].astype(np.int64))
        if np.any(bound+(1 << (params['conv_shifts'][i]-1)) >= 1 << 24):
            raise OverflowError('Exact float conv bound exceeded')
    for i in (2,):
        if np.any(127*np.abs(weights[i].astype(np.int64)).sum(1)+np.abs(biases[i].astype(np.int64)) >= 1 << 31):
            raise OverflowError('FC overflow')
    scores, vectors = [], []
    for first in range(0, len(images), 64):
        shape, color = preprocess(images[first:first+64], params['shape_mode'])
        x = torch.from_numpy(shape).float()
        for i in range(2):
            acc = F.conv2d(x, torch.from_numpy(weights[i].astype(np.float32)), torch.from_numpy(biases[i].astype(np.float32)), padding=1)
            shift = params['conv_shifts'][i]
            x = F.max_pool2d(torch.floor((acc+(1 << (shift-1)))/(1 << shift)).clamp(0, 127), 2)
        vector = x.permute(0, 2, 3, 1).reshape(len(x), -1).numpy().astype(np.int64)
        shape_score = vector @ weights[2].astype(np.int64).T+biases[2]
        color_score = color
        scores.append(np.concatenate((color_score, shape_score), axis=1).astype(np.int32))
        vectors.append(vector)
    result = np.concatenate(scores)
    return (np.concatenate(vectors), result) if return_features else result


def export(folder, model, params, metadata):
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=False)
    weights, biases = quantize(model, params)
    fw, fb = np.concatenate([v.ravel() for v in weights]), np.concatenate(biases)
    if len(fw) != WEIGHT_COUNT or len(fb) != BIAS_COUNT:
        raise AssertionError('Unexpected ROM size')
    (folder/'weights.mem').write_text(''.join(f'{int(v)&255:02x}\n' for v in fw), encoding='ascii')
    (folder/'biases.mem').write_text(''.join(f'{int(v)&0xffffffff:08x}\n' for v in fb), encoding='ascii')
    np.savez_compressed(folder/'quantized.npz', **{f'w{i}': v for i, v in enumerate(weights)}, **{f'b{i}': v for i, v in enumerate(biases)})
    torch.save(model.state_dict(), folder/'cnn_float.pt')
    write_json(folder/'quantization.json', params)
    write_json(folder/'MODEL.json', {'status': 'DEVELOPMENT_ONLY', 'architecture': 'factored color/shape',
        'input': 'RGB8 64x64 HWC', 'shape_preprocessing': params['shape_mode'],
        'color_preprocessing': 'sum(RGB8 >> 1, axes=(0,1)), no division',
        'shape_network': '1to8 Conv3x3-ReLU-Pool2; 8to16 Conv3x3-ReLU-Pool2; HWC4096-FC3',
        'color_network': '19bit channel sums -> argmax; no learned weights', 'output_order': params['output_order'],
        'rom_order': ['conv1 OIyx', 'conv2 OIyx', 'shape FC O-HWC'],
        'weights': WEIGHT_COUNT, 'biases': BIAS_COUNT, 'class_id': 'color*3+shape+1',
        'background_head': False, 'initialization': 'random', 'pretrained_checkpoint_loaded': False,
        'confidence': 'per-head best-second margin shifted/clamped, not probability',
        'rtl_compatibility': 'Requires maxRGB preprocessing, color SUM comparison and FC3 RTL; not loadable by legacy FC4/FC6 core',
        'board_validation': 'NOT_RUN', 'bit_generated': False, **metadata})
    return {p.name: sha(p) for p in folder.iterdir() if p.is_file()}
