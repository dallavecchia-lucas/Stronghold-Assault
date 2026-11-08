"""The water's textures (game/assets/textures/water), all tiling: wave normals from an FFT heightfield (a Phillips
wind-wave spectrum, two seas crossing), caustics traced by refracting light through a wavy surface onto the bed,
and a foam pattern.  python3 tools/textures/gen_water.py"""
import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'game', 'assets', 'textures', 'water')
rng = np.random.default_rng(7)


def spectrum_height(n, L, wind, A, small, seed):
    r = np.random.default_rng(seed)
    k1 = np.fft.fftfreq(n, d=L / n) * 2 * np.pi
    kx, ky = np.meshgrid(k1, k1, indexing='xy')
    k = np.sqrt(kx ** 2 + ky ** 2)
    k[0, 0] = 1e-6
    w = np.array(wind, float)
    V = np.linalg.norm(w)
    w /= V
    Lw = V * V / 9.81
    kd = (kx * w[0] + ky * w[1]) / k
    P = A * np.exp(-1 / (k * Lw) ** 2) / k ** 4 * np.abs(kd) ** 3 * np.exp(-(k * small) ** 2)
    P[0, 0] = 0
    h0 = (r.standard_normal((n, n)) + 1j * r.standard_normal((n, n))) * np.sqrt(P / 2)
    return kx, ky, h0


def normal_map(n=1024):
    # Two wind seas crossing: a river's chop rather than one ocean swell.
    out = np.zeros((n, n, 2))
    for wind, A, seed in [((6.0, 2.0), 1.0, 1), ((-3.0, 5.0), 0.6, 2)]:
        kx, ky, h0 = spectrum_height(n, 8.0, wind, A, 0.004, seed)
        gx = np.real(np.fft.ifft2(1j * kx * h0))
        gy = np.real(np.fft.ifft2(1j * ky * h0))
        out[..., 0] += gx
        out[..., 1] += gy
    s = np.percentile(np.abs(out), 99.5)
    g = out / s * 0.9
    nrm = np.dstack([-g[..., 0], g[..., 1], np.ones((n, n))])
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    img = ((nrm * 0.5 + 0.5) * 255 + 0.5).clip(0, 255).astype(np.uint8)
    Image.fromarray(img).save(f'{OUT}/water_normal.png', optimize=True)


def caustics(n=512):
    kx, ky, h0 = spectrum_height(n, 4.0, (4.0, 1.5), 1.0, 0.01, 5)
    gx = np.real(np.fft.ifft2(1j * kx * h0))
    gy = np.real(np.fft.ifft2(1j * ky * h0))
    s = np.percentile(np.abs(np.dstack([gx, gy])), 99)
    gx, gy = gx / s, gy / s
    acc = np.zeros((n, n))
    sub = 3  # rays per texel per axis
    for oy in range(sub):
        for ox in range(sub):
            y, x = np.mgrid[0:n, 0:n].astype(float)
            x += (ox + 0.5) / sub
            y += (oy + 0.5) / sub
            # Light bent by the slope lands this far along the bed (texels).
            tx = (x + gx * 9.0) % n
            ty = (y + gy * 9.0) % n
            np.add.at(acc, (ty.astype(int) % n, tx.astype(int) % n), 1.0)
    acc /= acc.mean()
    k = np.exp(-np.arange(-2, 3) ** 2 / 1.2)
    k /= k.sum()
    for ax in (0, 1):
        acc = sum(np.roll(acc, i - 2, axis=ax) * w for i, w in enumerate(k))
    c = np.clip((acc - 0.6) / 2.4, 0, 1) ** 0.8
    Image.fromarray((c * 255).astype(np.uint8), 'L').save(f'{OUT}/water_caustics.png', optimize=True)


def foam(n=512):
    # Bubbles: inverted cellular noise at two sizes, broken up by fbm.
    def worley(cells, seed):
        r = np.random.default_rng(seed)
        pts = r.random((cells, cells, 2))
        y, x = (np.mgrid[0:n, 0:n] + 0.5) / n * cells
        best = np.full((n, n), 9.0)
        cx, cy = np.floor(x).astype(int), np.floor(y).astype(int)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                ix, iy = cx + dx, cy + dy
                p = pts[iy % cells, ix % cells]
                d = np.hypot(ix + p[..., 0] - x, iy + p[..., 1] - y)
                best = np.minimum(best, d)
        return best
    f = np.fft.fft2(rng.standard_normal((n, n)))
    k = np.sqrt(sum(np.meshgrid(np.fft.fftfreq(n) ** 2, np.fft.fftfreq(n) ** 2)))
    k[0, 0] = 1
    fbm = np.real(np.fft.ifft2(f / k ** 1.4))
    fbm = (fbm - fbm.min()) / (fbm.max() - fbm.min())
    b = (1 - np.clip(worley(24, 1) * 1.6, 0, 1)) * 0.6 + (1 - np.clip(worley(64, 2) * 1.8, 0, 1)) * 0.4
    v = np.clip(b * (0.55 + 0.9 * fbm), 0, 1)
    Image.fromarray((v * 255).astype(np.uint8), 'L').save(f'{OUT}/water_foam.png', optimize=True)


normal_map()
caustics()
foam()
print('done')
