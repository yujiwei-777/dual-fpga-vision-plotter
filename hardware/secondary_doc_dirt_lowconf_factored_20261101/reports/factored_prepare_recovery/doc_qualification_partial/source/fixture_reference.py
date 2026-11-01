"""Frozen integer count/reference and synthetic fixtures; ref injected by runner."""
import numpy as np

def golden(y):
    blocks = y.reshape(180, 4, 320, 4).transpose(0, 2, 1, 3)
    result = (blocks <= 112).sum(axis=(-1, -2)) >= 2
    gx = np.arange(288, 320)
    gy = np.arange(112, 180)
    sums = np.zeros((68, 32), np.int32)
    for oy in (-10, -2, 6, 14):
        for ox in (-10, -2, 6, 14):
            sums += y[np.clip(gy * 4 + oy, 0, 719)[:, None], np.clip(gx * 4 + ox, 0, 1279)[None, :]]
    threshold = np.minimum(112, (sums + 8 >> 4) - 12)
    result[112:180, 288:320] = (blocks[112:180, 288:320] <= threshold[..., None, None]).sum(axis=(-1, -2)) >= 2
    canvas = np.zeros((320, 320), np.uint8)
    canvas[70:250] = result
    assert np.array_equal(canvas, ref.canvas(y))
    return canvas

def fixtures():
    yy, xx = np.mgrid[:720, :1280]
    dirt = np.clip(220 - np.rint(145 * np.exp(-((xx - 1260) / 100) ** 2 - ((yy - 670) / 160) ** 2)), 0, 255).astype(np.uint8)
    strokes = dirt.copy()
    strokes[600, 1100:1280] = 35
    strokes[400:720, 1200] = 35
    for i in range(160):
        strokes[420 + i, 1120 + i] = 40
    strokes[672, 1240:1242] = 30
    strokes[620, 1176:1178] = 35
    contract = np.full((720, 1280), 220, np.uint8)
    for x, y in ((0, 0), (1279, 0), (0, 719), (1279, 719)):
        contract[y, x] = 1
    for gx, gy in ((287, 111), (288, 111), (287, 112), (288, 112), (319, 111), (319, 112), (287, 179), (288, 179)):
        contract[4 * gy + 3, 4 * gx + 2:4 * gx + 4] = 45
    contract[300, 400:402] = 60
    contract[304, 404] = 1
    contract[512:672, 1120:1256] = 40
    rng = np.random.default_rng(20261101)
    grain = np.clip(dirt.astype(np.int16) + np.rint(rng.normal(0, 2, dirt.shape)).astype(np.int16), 0, 255).astype(np.uint8)
    for y in range(500, 708, 16):
        grain[y, 1160:1270] = np.clip(grain[y, 1160:1270].astype(np.int16) + np.arange(110) // 8 - 6, 0, 255)
    inds = rng.choice(grain.size, 800, replace=False)
    grain.ravel()[inds] = 50
    grain[640, 1232:1234] = 30
    return {'strokes_on_fixed_dirt': strokes, 'sample15_roi_border_contract': contract, 'gray_gradient_grain': grain, 'blank': np.full((720, 1280), 220, np.uint8)}
