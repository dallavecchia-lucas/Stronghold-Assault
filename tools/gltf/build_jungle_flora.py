"""Builds the jungle's plants as glTF models, procedurally, on numpy and Pillow alone (no Blender):
the Jungle Keep map's trees, palms, understory and ground cover (game/scripts/match/jungle/).

Every plant is one mesh (bark, leaves and so on as its surfaces) at a real size in metres, its origin
at the foot of the trunk (or the middle of the clump) on the ground. Leaves are alpha-cut cards
(alphaMode MASK, double-sided) with textures drawn here: leaf sprays, palm and fern fronds, banana
and elephant-ear leaves, grass blades, bamboo sprays; barks are tileable fractal noise. The leaf
cards' normals lean out from the middle of the crown, so a crown shades like one soft mass; vertex
colours darken the inside and the bottom of it (Godot takes them as albedo).

Trees also come as a `_far` model: the same tree with a quarter of the cards (bigger) and a plain
trunk, for the MultiMesh batches far from the camera.

  python3 tools/gltf/build_jungle_flora.py --out game/assets/environment/jungle [--only palm,fern] [--seed 7]

Models (nominal height; the game scales them to the height it wants, Props.instance):
  kapok          emergent giant, buttress roots, umbrella crown, lianas    48 m
  canopy_a       broadleaf canopy tree, round crown                        30 m
  canopy_b       taller, layered crown, darker leaves                      34 m
  palm           curved trunk, arching fronds, coconuts                    18 m
  banana         clump of pseudostems with big torn paddle leaves           5 m
  tree_fern      slender fibrous trunk, crown of arching fronds             6 m
  bamboo         clump of culms with leaf sprays                           13 m
  fern           ground fern rosette                                      1.3 m
  elephant_ear   big heart-shaped leaves on long stalks                   2.2 m
  grass          tuft of blades                                           0.9 m
"""
import argparse
import io
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gltf_io import write_glb  # noqa: E402

UP = np.array([0.0, 1.0, 0.0])


# ---------------------------------------------------------------- small maths

def norm(v):
    v = np.asarray(v, dtype=float)
    n = np.linalg.norm(v, axis=-1, keepdims=True)
    return v / np.maximum(n, 1e-9)


def rot(axis, ang):
    """Rotation matrix about `axis` by `ang` (radians)."""
    a = norm(axis)
    c, s = math.cos(ang), math.sin(ang)
    x, y, z = a
    return np.array([[c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s],
                     [y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s],
                     [z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c)]])


def perp(v):
    """Some unit vector perpendicular to `v`."""
    v = norm(v)
    a = np.array([1.0, 0.0, 0.0]) if abs(v[0]) < 0.9 else np.array([0.0, 0.0, 1.0])
    return norm(np.cross(v, a))


def bezier(p0, p1, p2, p3, n):
    t = np.linspace(0.0, 1.0, n)[:, None]
    return ((1 - t) ** 3) * p0 + 3 * ((1 - t) ** 2) * t * p1 + 3 * (1 - t) * t * t * p2 + (t ** 3) * p3


# ---------------------------------------------------------------- textures

def periodic_noise(size, cells, rng):
    """Tileable value noise, `cells` lattice cells across, smoothstepped, in 0..1."""
    g = rng.random((cells, cells))
    t = np.arange(size) * cells / size
    i0 = np.floor(t).astype(int)
    f = t - i0
    f = f * f * (3 - 2 * f)
    i1 = (i0 + 1) % cells
    i0 %= cells
    a = g[i0][:, i0] * (1 - f)[None, :] + g[i0][:, i1] * f[None, :]
    b = g[i1][:, i0] * (1 - f)[None, :] + g[i1][:, i1] * f[None, :]
    return a * (1 - f)[:, None] + b * f[:, None]


def fractal(size, base, octaves, rng, stretch=(1, 1)):
    """Tileable fractal noise; `stretch` (cells across x, y multipliers) makes it streaky."""
    out = np.zeros((size, size))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        cx, cy = base * (2 ** o) * stretch[0], base * (2 ** o) * stretch[1]
        n = periodic_noise_xy(size, int(cx), int(cy), rng)
        out += n * amp
        tot += amp
        amp *= 0.5
    return out / tot


def periodic_noise_xy(size, cx, cy, rng):
    cx, cy = max(cx, 1), max(cy, 1)
    g = rng.random((cy, cx))
    tx = np.arange(size) * cx / size
    ty = np.arange(size) * cy / size
    x0 = np.floor(tx).astype(int)
    y0 = np.floor(ty).astype(int)
    fx = tx - x0
    fy = ty - y0
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    x1, y1 = (x0 + 1) % cx, (y0 + 1) % cy
    x0 %= cx
    y0 %= cy
    a = g[y0][:, x0] * (1 - fx)[None, :] + g[y0][:, x1] * fx[None, :]
    b = g[y1][:, x0] * (1 - fx)[None, :] + g[y1][:, x1] * fx[None, :]
    return a * (1 - fy)[:, None] + b * fy[:, None]


def colorize(t, stops):
    """Maps t (0..1 array) through colour stops [(t, (r, g, b)), ...] to an RGB uint8 image."""
    ts = np.array([s[0] for s in stops])
    cs = np.array([s[1] for s in stops], dtype=float)
    out = np.zeros(t.shape + (3,))
    for k in range(3):
        out[..., k] = np.interp(t, ts, cs[:, k])
    return Image.fromarray(np.clip(out, 0, 255).astype(np.uint8), "RGB")


def bark_texture(kind, rng, size=512):
    if kind == "kapok":
        n = fractal(size, 3, 6, rng, (1, 4))
        lich = fractal(size, 4, 4, rng)
        img = colorize(n, [(0.0, (70, 72, 62)), (0.45, (118, 118, 104)), (0.75, (148, 146, 128)), (1.0, (170, 168, 150))])
        a = np.asarray(img).astype(float)
        moss = np.clip((lich - 0.55) * 4.0, 0, 1)[..., None]
        a = a * (1 - moss * 0.6) + np.array([88, 110, 56]) * moss * 0.6
        cracks = fractal(size, 6, 3, rng, (4, 1))
        a *= (0.75 + 0.25 * np.clip((cracks - 0.25) * 3, 0, 1))[..., None]
        return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    if kind == "brown":
        n = fractal(size, 4, 6, rng, (2, 8))
        img = colorize(n, [(0.0, (34, 26, 20)), (0.4, (70, 56, 42)), (0.7, (98, 82, 64)), (1.0, (120, 104, 84))])
        a = np.asarray(img).astype(float)
        moss = np.clip((fractal(size, 3, 4, rng) - 0.6) * 4.0, 0, 1)[..., None]
        a = a * (1 - moss * 0.5) + np.array([70, 92, 44]) * moss * 0.5
        return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
    if kind == "palm":
        n = fractal(size, 4, 5, rng, (1, 2))
        y = np.arange(size)[:, None] / size
        rings = 0.5 + 0.5 * np.cos(y * math.pi * 2 * 14 + n * 2.0)
        t = np.clip(n * 0.75 + rings * 0.22 + 0.1, 0, 1)
        img = colorize(t, [(0.0, (62, 54, 44)), (0.5, (112, 102, 86)), (0.8, (140, 130, 112)), (1.0, (160, 150, 132))])
        return img
    if kind == "bamboo":
        n = fractal(size, 3, 4, rng, (6, 1))
        y = np.arange(size)[:, None] / size
        node = np.exp(-((((y * 3) % 1.0) - 0.5) ** 2) / 0.0015)
        img = np.zeros((size, size, 3))
        base = np.array([96, 128, 46]) * (0.85 + 0.3 * n[..., None])
        nodec = np.array([150, 150, 80])
        img = base * (1 - node[..., None] * np.ones((1, size, 1))) + nodec * node[..., None]
        return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))
    if kind == "fern":
        n = fractal(size, 6, 5, rng, (3, 1))
        img = colorize(n, [(0.0, (26, 18, 12)), (0.5, (60, 42, 28)), (1.0, (96, 72, 46))])
        return img
    if kind == "stem":
        n = fractal(size, 3, 4, rng, (1, 6))
        img = colorize(n, [(0.0, (70, 92, 40)), (0.5, (104, 124, 58)), (1.0, (128, 136, 72))])
        return img
    raise ValueError(kind)


class Canvas:
    """RGBA drawing surface at `ss` times the final size (downsampled for smooth edges)."""

    def __init__(self, w, h, ss=2):
        self.ss = ss
        self.w, self.h = w * ss, h * ss
        self.img = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    def poly(self, pts, col):
        self.d.polygon([(float(x), float(y)) for x, y in pts], fill=col)

    def line(self, pts, col, width):
        self.d.line([(float(x), float(y)) for x, y in pts], fill=col, width=max(int(width), 1), joint="curve")

    def finish(self, fill_rgb=None):
        img = self.img.resize((self.w // self.ss, self.h // self.ss), Image.LANCZOS)
        a = np.asarray(img).astype(float)
        alpha = a[..., 3:4] / 255.0
        # Fill the see-through texels with the average leaf colour so mipmaps don't fringe dark.
        if fill_rgb is None:
            m = alpha[..., 0] > 0.5
            fill_rgb = a[m][:, :3].mean(0) if m.any() else np.array([60, 90, 40])
        rgb = np.where(alpha > 0.02, a[..., :3] / np.maximum(alpha, 1e-3), fill_rgb)
        rgb = np.clip(rgb, 0, 255)
        # Push the alpha a little so the cut-out holds up in the mips.
        al = np.clip((alpha[..., 0] - 0.5) * 1.6 + 0.5, 0, 1) * 255
        return Image.fromarray(np.dstack([rgb, al]).astype(np.uint8), "RGBA")


def jitter(col, rng, amt):
    r, g, b = col
    k = 1.0 + rng.uniform(-amt, amt)
    h = rng.uniform(-amt, amt) * 40
    return (int(np.clip(r * k + h * 0.5, 0, 255)), int(np.clip(g * k, 0, 255)), int(np.clip(b * k - h * 0.3, 0, 255)), 255)


def leaf_outline(base, tip, width, n=14, shape="ellipse", serr=0.0, rng=None):
    """Points of a leaf from `base` to `tip` (2D), `width` at its widest."""
    base, tip = np.array(base, float), np.array(tip, float)
    ax = tip - base
    L = np.linalg.norm(ax)
    ax /= max(L, 1e-6)
    side = np.array([-ax[1], ax[0]])
    left, right = [], []
    for k in range(n + 1):
        t = k / n
        if shape == "ellipse":
            w = math.sin(math.pi * t) ** 0.75 * (1.0 - 0.25 * t)
        elif shape == "lance":
            w = math.sin(math.pi * t ** 0.7) ** 1.2
        else:  # "heart"
            w = math.sin(math.pi * min(t * 1.2, 1.0)) ** 0.6 * (1.0 - t) ** 0.5 * 1.3
        w *= width * 0.5
        if serr and rng is not None:
            w *= 1.0 + rng.uniform(-serr, serr)
        p = base + ax * L * t
        left.append(p + side * w)
        right.append(p - side * w)
    return left + right[::-1]


def draw_leaf(c, at, tip, width, col, shape="ellipse", rng=None):
    """A leaf with two tones either side of its midrib (lit and shaded halves) and the midrib."""
    pts = leaf_outline(at, tip, width, 16, shape)
    c.poly(pts, col)
    half = len(pts) // 2
    lit = tuple(min(255, int(v * 1.18)) for v in col[:3]) + (255,)
    c.poly(pts[:half + 1], lit)
    mid = tuple(min(255, int(v * 1.35)) for v in col[:3]) + (255,)
    c.line([at, (at[0] + (tip[0] - at[0]) * 0.9, at[1] + (tip[1] - at[1]) * 0.9)], mid, max(c.w * 0.003, 1))


def tex_leaf_spray(rng, size=512, palette=((54, 92, 34), (74, 118, 40), (40, 74, 30)), leaves=24, shape="ellipse", lw=0.36):
    """A dense, ragged-edged mass of leaves on twigs (a crown's leaf card)."""
    c = Canvas(size, size)
    S = c.w
    cx, cy = S * 0.5, S * 0.5
    for k in range(9):
        a = k / 9 * 2 * math.pi + rng.uniform(-0.3, 0.3)
        r = rng.uniform(0.3, 0.4) * S
        c.line([(cx, cy), (cx + math.cos(a) * r, cy + math.sin(a) * r)], (70, 52, 34, 255), S * 0.007)
    order = []
    for k in range(leaves):
        # Scattered over a disc, pointing out from the middle.
        r = math.sqrt(rng.uniform(0.0, 1.0)) * S * 0.3
        a = rng.uniform(0, 2 * math.pi)
        at = (cx + math.cos(a) * r, cy + math.sin(a) * r)
        la = a + rng.uniform(-0.7, 0.7)
        L = rng.uniform(0.13, 0.2) * S
        order.append((rng.random(), at, la, L))
    order.sort()
    for depth, at, a, L in order:
        tip = (at[0] + math.cos(a) * L, at[1] + math.sin(a) * L)
        base_col = palette[rng.integers(len(palette))]
        shade = 0.62 + 0.5 * depth
        col = jitter(tuple(int(v * shade) for v in base_col), rng, 0.1)
        draw_leaf(c, at, tip, L * lw, col, shape)
    return c.finish()


def tex_pinnate(rng, w=256, h=1024, kind="palm"):
    """A frond along v (bottom: base, top: tip), leaflets either side of the rib."""
    c = Canvas(w, h)
    W, H = c.w, c.h
    cx = W * 0.5
    rib = (88, 96, 46, 255) if kind == "palm" else (70, 84, 36, 255)
    n = 40 if kind == "palm" else 34
    for side in (-1, 1):
        for k in range(n):
            t = (k + 0.5) / n
            y = H * (0.97 - t * 0.94)
            env = math.sin(math.pi * (0.08 + 0.92 * t)) ** (0.5 if kind == "palm" else 0.8)
            L = W * 0.5 * env * (0.95 if kind == "palm" else 0.9)
            ang = math.radians(55 if kind == "palm" else 75)
            dx = side * math.sin(ang) * L
            dy = -math.cos(ang) * L
            if kind == "palm":
                col = jitter((70, 112, 38), rng, 0.15)
                tip = (cx + dx * 1.02, y + dy + L * 0.45)
                draw_leaf(c, (cx, y), tip, W * 0.075, col, "lance")
            else:
                col = jitter((58, 104, 36), rng, 0.12)
                # A pinna: lobes along its own little rib.
                lobes = 7
                for j in range(lobes):
                    u = (j + 0.5) / lobes
                    px, py = cx + dx * u, y + dy * u
                    r = W * 0.035 * (1.15 - u * 0.7) * env + W * 0.008
                    c.d.ellipse([px - r, py - r * 1.25, px + r, py + r * 0.6], fill=col)
                c.line([(cx, y), (cx + dx, y + dy)], col, W * 0.012)
    c.line([(cx, H * 0.995), (cx, H * 0.02)], rib, W * 0.02)
    return c.finish()


def tex_banana(rng, w=256, h=1024):
    c = Canvas(w, h)
    W, H = c.w, c.h
    cx = W * 0.5
    pts_l, pts_r = [], []
    for k in range(41):
        t = k / 40
        y = H * (0.99 - t * 0.98)
        hw = W * 0.46 * (min(1.0, t * 6) ** 0.6) * math.sqrt(max(0.0, 1.0 - max(0.0, t - 0.8) ** 2 * 25))
        pts_l.append((cx - hw, y))
        pts_r.append((cx + hw, y))
    outline = pts_l + pts_r[::-1]
    base = np.array([66, 124, 40], float)
    # Lateral veins as stripes of shade, then cut to the outline.
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for k in range(90):
        t = k / 90
        y = H * (1.0 - t * 1.0)
        col = tuple(int(v) for v in np.clip(base * rng.uniform(0.82, 1.14), 0, 255)) + (255,)
        for s in (-1, 1):
            d.line([(cx, y), (cx + s * W * 0.5, y - W * 0.25)], fill=col, width=int(H * 0.013))
    mask = Image.new("L", (W, H), 0)
    md = ImageDraw.Draw(mask)
    md.polygon(outline, fill=255)
    # Tears: slits from the edge in toward the rib, along the veins.
    for k in range(int(rng.integers(6, 11))):
        y = H * rng.uniform(0.12, 0.85)
        s = rng.choice([-1, 1])
        depth = rng.uniform(0.4, 0.95)
        x0 = cx + s * W * 0.52
        x1 = cx + s * W * 0.5 * (1 - depth)
        md.polygon([(x0, y - W * 0.26 - 6), (x1, y - W * 0.25 * (1 - depth)), (x0, y - W * 0.26 + 6)], fill=0)
    layer.putalpha(mask)
    # Browned rim.
    inner = mask.filter(ImageFilter.MinFilter(9))
    rim = (np.asarray(mask).astype(float) - np.asarray(inner).astype(float)) / 255.0
    a = np.asarray(layer).astype(float)
    a[..., :3] = a[..., :3] * (1 - rim[..., None] * 0.6) + np.array([150, 130, 64]) * rim[..., None] * 0.6
    c.img = Image.fromarray(a.astype(np.uint8), "RGBA")
    c.d = ImageDraw.Draw(c.img)
    c.line([(cx, H * 0.995), (cx, H * 0.03)], (150, 172, 92, 255), W * 0.035)
    return c.finish()


def tex_heart(rng, size=512):
    """An elephant-ear blade: pointed tip at the top, two rounded lobes at the bottom."""
    c = Canvas(size, size)
    S = c.w
    cx = S * 0.5
    right = []
    for k in range(33):
        t = k / 32  # 0 at the tip, 1 at the bottom of the lobe
        y = S * (0.03 + 0.9 * t)
        w = S * 0.46 * math.sin(math.pi * min(t / 0.78, 1.0) * 0.5) ** 0.8
        if t > 0.78:
            w = S * 0.46 * math.cos((t - 0.78) / 0.22 * math.pi * 0.5) ** 0.5
            w = max(w, S * 0.06 + (1 - t) * S * 0.5)
        right.append((cx + w, y))
    notch = [(cx + S * 0.02, S * 0.8), (cx, S * 0.74), (cx - S * 0.02, S * 0.8)]
    pts = right + notch + [(2 * cx - x, y) for x, y in right[::-1]]
    c.poly(pts, (36, 82, 36, 255))
    c.poly(right + [(cx, S * 0.74), (cx, S * 0.03)], (46, 98, 42, 255))
    for k in range(7):
        y = S * (0.2 + k * 0.08)
        for s in (-1, 1):
            c.line([(cx, y + S * 0.06), (cx + s * S * 0.3, y - S * 0.02)], (112, 160, 92, 255), S * 0.005)
    c.line([(cx, S * 0.75), (cx, S * 0.05)], (130, 176, 104, 255), S * 0.012)
    return c.finish()


def tex_grass(rng, size=512):
    c = Canvas(size, size)
    S = c.w
    for k in range(70):
        x0 = S * (0.5 + rng.normal(0, 0.09))
        lean = rng.normal(0, 0.22)
        L = S * rng.uniform(0.55, 0.97)
        w = S * rng.uniform(0.008, 0.016)
        pts_l, pts_r = [], []
        for j in range(9):
            t = j / 8
            x = x0 + lean * L * t * t
            y = S - L * t
            ww = w * (1 - t)
            pts_l.append((x - ww, y))
            pts_r.append((x + ww, y))
        dry = rng.random() < 0.15
        col = jitter((150, 140, 70) if dry else (78, 122, 40), rng, 0.18)
        c.poly(pts_l + pts_r[::-1], col)
    return c.finish()


def tex_bamboo_spray(rng, size=512):
    c = Canvas(size, size)
    S = c.w
    cx = S * 0.5
    for k in range(5):
        a = math.radians(-90 + rng.uniform(-60, 60))
        end = (cx + math.cos(a) * S * 0.45, S * 0.95 + math.sin(a) * S * 0.9)
        c.line([(cx, S * 0.98), end], (110, 120, 50, 255), S * 0.006)
        for j in range(7):
            t = rng.uniform(0.3, 1.0)
            at = (cx + (end[0] - cx) * t, S * 0.98 + (end[1] - S * 0.98) * t)
            la = a + rng.uniform(-0.9, 0.9) + 0.35
            L = S * rng.uniform(0.14, 0.22)
            tip = (at[0] + math.cos(la) * L, at[1] + math.sin(la) * L + L * 0.3)
            c.poly(leaf_outline(at, tip, L * 0.16, 10, "lance"), jitter((92, 136, 46), rng, 0.15))
    return c.finish()


def tex_vine(rng, w=128, h=512):
    c = Canvas(w, h)
    W, H = c.w, c.h
    pts = [(W * 0.5 + math.sin(t * 9) * W * 0.12, H * (1 - t)) for t in np.linspace(0, 1, 30)]
    c.line(pts, (70, 60, 36, 255), W * 0.05)
    for k in range(26):
        t = rng.uniform(0.02, 0.98)
        x, y = W * 0.5 + math.sin(t * 9) * W * 0.12, H * (1 - t)
        s = rng.choice([-1, 1])
        L = W * rng.uniform(0.25, 0.42)
        c.poly(leaf_outline((x, y), (x + s * L, y + L * 0.4), L * 0.55, 10, "heart"), jitter((52, 98, 34), rng, 0.15))
    return c.finish()


# ---------------------------------------------------------------- mesh building

class Surface:
    def __init__(self, material):
        self.material = material
        self.pos, self.nrm, self.uv, self.col, self.idx = [], [], [], [], []

    @property
    def n(self):
        return len(self.pos)

    def add(self, p, nr, uv, col=(1, 1, 1, 1)):
        self.pos.append(np.asarray(p, float))
        self.nrm.append(norm(nr))
        self.uv.append(uv)
        self.col.append(col)
        return len(self.pos) - 1

    def tri(self, a, b, c):
        self.idx += [a, b, c]

    def quad(self, a, b, c, d):
        self.idx += [a, b, c, a, c, d]


class Model:
    def __init__(self, name):
        self.name = name
        self.surfaces = {}
        self.materials = {}

    def surface(self, key, image, alpha=False, roughness=0.9, double=False):
        if key not in self.surfaces:
            self.surfaces[key] = Surface(key)
            self.materials[key] = {"image": image, "alpha": alpha, "roughness": roughness, "double": double or not alpha}
        return self.surfaces[key]

    def tris(self):
        return sum(len(s.idx) // 3 for s in self.surfaces.values())


def tube(s, pts, radii, sides=8, v_per_m=0.5, col_fn=None, cap=False, u_tiles=1.0):
    """A tube along `pts` (N x 3) with `radii` (N), parallel-transported frames."""
    pts = np.asarray(pts, float)
    radii = np.asarray(radii, float)
    n = len(pts)
    tang = np.zeros_like(pts)
    tang[1:-1] = pts[2:] - pts[:-2]
    tang[0] = pts[1] - pts[0]
    tang[-1] = pts[-1] - pts[-2]
    tang = norm(tang)
    ref = perp(tang[0])
    rows = []
    v = 0.0
    for i in range(n):
        if i > 0:
            v += np.linalg.norm(pts[i] - pts[i - 1]) * v_per_m
            # Parallel transport the reference.
            ref = norm(ref - tang[i] * np.dot(ref, tang[i]))
        side = np.cross(tang[i], ref)
        row = []
        for k in range(sides + 1):
            a = k / sides * 2 * math.pi
            d = ref * math.cos(a) + side * math.sin(a)
            col = col_fn(i / (n - 1), pts[i]) if col_fn else (1, 1, 1, 1)
            row.append(s.add(pts[i] + d * radii[i], d, (k / sides * u_tiles, v), col))
        rows.append(row)
    for i in range(n - 1):
        for k in range(sides):
            s.quad(rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i + 1][k])
    if cap:
        c = s.add(pts[-1] + tang[-1] * radii[-1] * 0.3, tang[-1], (0.5, v), col_fn(1.0, pts[-1]) if col_fn else (1, 1, 1, 1))
        for k in range(sides):
            s.tri(rows[-1][k], c, rows[-1][k + 1])


def card(s, centre, right, up, w, h, uv_rect, crown=None, bend=0.0, col=(1, 1, 1, 1), lean_out=0.6, segs=1):
    """A quad (or `segs` rows bent by `bend` along `up`), centred on `centre`. Normals lean out from
    `crown` (the middle of the crown) by `lean_out`."""
    right, up = norm(right), norm(up)
    face = norm(np.cross(right, up))
    u0, v0, u1, v1 = uv_rect
    rows = []
    for j in range(segs + 1):
        t = j / segs
        off = up * (t - 0.5) * h
        sag = -face * bend * (t - 0.5) ** 2 * h
        row = []
        for k in range(3):
            x = (k / 2 - 0.5) * w
            p = centre + right * x + off + sag
            nrm = face
            if crown is not None:
                out = norm(p - crown)
                if np.dot(out, face) < 0:
                    nrm = -face
                nrm = norm(nrm * (1 - lean_out) + out * lean_out)
            row.append(s.add(p, nrm, (u0 + (u1 - u0) * k / 2, v1 + (v0 - v1) * t), col))
        rows.append(row)
    for j in range(segs):
        for k in range(2):
            s.quad(rows[j][k], rows[j][k + 1], rows[j + 1][k + 1], rows[j + 1][k])


def ribbon(s, spine, side_dirs, widths, uv_rect, fold=0.35, crown=None, lean_out=0.4, col_fn=None):
    """A leaf or frond along `spine` (N x 3): rows of left / middle / right, the edges folded down by
    `fold` (radians) about the spine (a V-fold), u across, v along (bottom of the texture at the base)."""
    spine = np.asarray(spine, float)
    n = len(spine)
    u0, v0, u1, v1 = uv_rect
    rows = []
    for i in range(n):
        t = i / (n - 1)
        tang = norm(spine[min(i + 1, n - 1)] - spine[max(i - 1, 0)])
        sd = norm(side_dirs[i] - tang * np.dot(side_dirs[i], tang))
        upn = norm(np.cross(sd, tang))
        if upn[1] < 0:
            upn = -upn
        w = widths[i] * 0.5
        left = spine[i] - sd * w * math.cos(fold) - upn * w * math.sin(fold)
        right = spine[i] + sd * w * math.cos(fold) - upn * w * math.sin(fold)
        col = col_fn(t) if col_fn else (1, 1, 1, 1)
        row = []
        for k, p in enumerate((left, spine[i], right)):
            nrm = upn
            if crown is not None:
                nrm = norm(upn * (1 - lean_out) + norm(p - crown) * lean_out)
            row.append(s.add(p, nrm, (u0 + (u1 - u0) * k / 2, v1 + (v0 - v1) * t), col))
        rows.append(row)
    for i in range(n - 1):
        for k in range(2):
            s.quad(rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i + 1][k])


def sphere(s, c, r, col=(1, 1, 1, 1), seg=6):
    rows = []
    for i in range(seg // 2 + 1):
        th = math.pi * i / (seg // 2)
        row = []
        for k in range(seg + 1):
            ph = 2 * math.pi * k / seg
            d = np.array([math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph)])
            row.append(s.add(c + d * r, d, (k / seg, i / (seg // 2)), col))
        rows.append(row)
    for i in range(len(rows) - 1):
        for k in range(seg):
            s.quad(rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i + 1][k])


def shade(y, h, lo=0.55, hi=1.0):
    t = float(np.clip(y / max(h, 1e-6), 0, 1))
    v = lo + (hi - lo) * t
    return (v, v, v, 1.0)


def crown_col(p, centre, radius, rng, lo=0.55):
    """Darker inside the crown and underneath, a little random tint."""
    d = np.linalg.norm((p - centre) / np.array([radius[0], radius[1], radius[0]]))
    under = np.clip(0.5 + (p[1] - centre[1]) / (2 * radius[1]), 0, 1)
    v = lo + (1 - lo) * np.clip(d * 0.6 + under * 0.5, 0, 1)
    tint = rng.uniform(-0.06, 0.06)
    return (float(np.clip(v + tint, 0, 1)), float(np.clip(v, 0, 1)), float(np.clip(v - tint, 0, 1)), 1.0)


# ---------------------------------------------------------------- plants

def branch_path(start, direction, length, droop, rng, n=6):
    d = norm(direction)
    p0 = np.asarray(start, float)
    p3 = p0 + d * length + np.array([0, -droop, 0])
    p1 = p0 + d * length * 0.35 + rng.normal(0, length * 0.05, 3)
    p2 = p0 + d * length * 0.7 + np.array([0, -droop * 0.3, 0]) + rng.normal(0, length * 0.05, 3)
    return bezier(p0, p1, p2, p3, n)


def clump(s_leaf, rng, centre, radius, cards, size, crown_c, crown_r, lean_out=0.7):
    """A clump of foliage: `cards` leaf cards over the shell of the ellipsoid `radius` (rx, ry) round
    `centre`, each facing out of it, so it reads solid from every side and shades like a mass."""
    rx, ry = radius
    for k in range(cards):
        # Even-ish over the shell (Fibonacci sphere), jittered, a bit more on top.
        t = (k + 0.5) / cards
        y = 1.0 - 2.0 * t ** 0.85
        r = math.sqrt(max(0.0, 1.0 - y * y))
        a = k * 2.399963 + rng.uniform(-0.3, 0.3)
        d = np.array([math.cos(a) * r, y, math.sin(a) * r])
        shell = rng.uniform(0.72, 1.0)
        c = centre + d * np.array([rx, ry, rx]) * shell
        out = norm(d * np.array([1.0 / rx, 1.0 / ry, 1.0 / rx]))
        sz = rng.uniform(*size)
        roll = rng.uniform(0, 2 * math.pi)
        right = rot(out, roll) @ perp(out)
        up = norm(np.cross(out, right))
        col = crown_col(c, crown_c, crown_r, rng)
        card(s_leaf, c, right, up, sz, sz, (0, 0, 1, 1), crown=crown_c, col=col, lean_out=lean_out, bend=0.35, segs=1)


def build_kapok(rng, far=False):
    m = Model("kapok_far" if far else "kapok")
    H = 48.0
    bark = m.surface("bark", ("bark_kapok",), roughness=0.95)
    leaves = m.surface("leaves", ("spray_kapok",), alpha=True, roughness=0.75, double=True)
    trunk_top = H * 0.70
    lean = rng.normal(0, 0.6, 3) * np.array([1, 0, 1])
    n = 7 if far else 14
    pts = np.array([[0, 0, 0]] + [list(lean * (t ** 2) + np.array([0, trunk_top * t, 0])) for t in np.linspace(0.08, 1.0, n - 1)])
    radii = [1.55] + [1.25 * (1 - 0.55 * t) + 0.45 * math.exp(-t * 18) for t in np.linspace(0.08, 1.0, n - 1)]
    tube(bark, pts, radii, 6 if far else 14, 0.12, col_fn=lambda t, p: shade(p[1], H * 0.2, 0.5, 1.0), u_tiles=3)
    if not far:
        buttresses(bark, rng, 6, (4.0, 6.5), (5.0, 8.0), 0.9)
    # Branches: an umbrella, a clump of leaves at every branch's end.
    crown_c = pts[-1] + np.array([0, H * 0.12, 0])
    crown_r = (H * 0.36, H * 0.1)
    clumps = []
    nb = 8
    for k in range(nb):
        a = k / nb * 2 * math.pi + rng.uniform(-0.25, 0.25)
        d = np.array([math.cos(a), rng.uniform(0.3, 0.55), math.sin(a)])
        L = rng.uniform(H * 0.22, H * 0.3)
        start = pts[-1] - np.array([0, rng.uniform(0, H * 0.05), 0])
        path = branch_path(start, d, L, -H * 0.02, rng, 4 if far else 7)
        tube(bark, path, np.linspace(0.6, 0.14, len(path)), 4 if far else 7, 0.2)
        clumps.append((path[-1] + UP * 1.5, (rng.uniform(6.5, 8.5), rng.uniform(3.2, 4.2))))
        if not far:
            j = len(path) // 2
            sd = norm(d + rng.normal(0, 0.5, 3) * np.array([1, 0.2, 1]) + UP * 0.4)
            sub = branch_path(path[j], sd, L * 0.45, -0.5, rng, 4)
            tube(bark, sub, np.linspace(0.22, 0.06, len(sub)), 4, 0.3)
            clumps.append((sub[-1] + UP * 1.0, (rng.uniform(4.5, 6.0), rng.uniform(2.6, 3.4))))
    clumps.append((crown_c + UP * 2.0, (8.0, 3.5)))
    for c, r in clumps:
        clump(leaves, rng, c, r, 14 if far else 32, (7.0, 9.5) if far else (3.8, 5.6), crown_c, crown_r)
    if not far:
        vine = m.surface("vine", ("vine",), alpha=True, roughness=0.8, double=True)
        for k in range(9):
            c = clumps[rng.integers(len(clumps))][0]
            top = c - np.array([0, 3.0, 0])
            bottom = np.array([top[0] * rng.uniform(0.2, 0.8), rng.uniform(-0.5, 10.0), top[2] * rng.uniform(0.2, 0.8)])
            sp = bezier(top, top + (bottom - top) * 0.3 + rng.normal(0, 1.5, 3), top + (bottom - top) * 0.7 + rng.normal(0, 1.5, 3), bottom, 10)
            tube(bark, sp, np.full(len(sp), 0.07), 3, 0.5)
            for twist in (0.0, math.pi / 2):
                sd = [rot(UP, twist + c[0]) @ np.array([1.0, 0, 0])] * len(sp)
                ribbon(vine, sp, sd, np.full(len(sp), 1.1), (0, 0, 1, 1), fold=0.0)
    return m


def buttresses(bark, rng, count, reach_r, top_r, at):
    """Buttress roots: thin fins from up the trunk out along the ground."""
    for k in range(count):
        a = k / count * 2 * math.pi + rng.uniform(-0.25, 0.25)
        out = np.array([math.cos(a), 0, math.sin(a)])
        reach = rng.uniform(*reach_r)
        top = rng.uniform(*top_r)
        th = 0.08 + 0.03 * reach
        sidev = np.cross(UP, out)
        rows = []
        for j in range(9):
            t = j / 8
            r = at + reach * t ** 1.4
            y = top * (1 - t) ** 2.2
            base = out * r
            row = []
            for sgn in (-1, 1):
                for yy in (0.0, y):
                    p = base + sidev * sgn * th * (1 - j / 9) + np.array([0, yy - 0.15, 0])
                    row.append(bark.add(p, sidev * sgn + UP * 0.1, (j / 8 * 2, yy * 0.12), shade(yy, 6, 0.45, 0.85)))
            rows.append(row)
        for j in range(len(rows) - 1):
            a0, a1, b0, b1 = rows[j]
            c0, c1, d0, d1 = rows[j + 1]
            bark.quad(a0, c0, c1, a1)
            bark.quad(b1, d1, d0, b0)
            bark.quad(a1, c1, d1, b1)


def build_canopy(rng, variant="a", far=False):
    m = Model("canopy_%s%s" % (variant, "_far" if far else ""))
    H = 30.0 if variant == "a" else 34.0
    bark = m.surface("bark", ("bark_brown",), roughness=0.95)
    leaves = m.surface("leaves", ("spray_canopy_%s" % variant,), alpha=True, roughness=0.7, double=True)
    fork = H * (0.38 if variant == "a" else 0.58)
    lean = rng.normal(0, 0.5, 3) * np.array([1, 0, 1])
    n = 5 if far else 9
    pts = np.array([lean * t ** 2 + np.array([0, fork * t, 0]) for t in np.linspace(0, 1, n)])
    radii = [0.75 * (1 - 0.35 * t) + 0.4 * math.exp(-t * 12) for t in np.linspace(0, 1, n)]
    tube(bark, pts, radii, 5 if far else 10, 0.2, col_fn=lambda t, p: shade(p[1], H * 0.3, 0.55, 1.0), u_tiles=2)
    if variant == "b" and not far:
        buttresses(bark, rng, 5, (1.6, 2.8), (2.0, 3.5), 0.55)
    crown_c = pts[-1] + np.array([0, (H - fork) * 0.5, 0])
    crown_r = (H * (0.36 if variant == "a" else 0.26), (H - fork) * 0.5)
    clumps = []
    limbs = 6 if variant == "a" else 5
    for k in range(limbs):
        a = k / limbs * 2 * math.pi + rng.uniform(-0.35, 0.35)
        spread = 1.1 if variant == "a" else 0.6
        d = np.array([math.cos(a) * spread, 1.0, math.sin(a) * spread])
        L = (H - fork) * rng.uniform(0.55, 0.8)
        path = branch_path(pts[-1], d, L, 0.0, rng, 4 if far else 6)
        tube(bark, path, np.linspace(radii[-1] * 0.75, 0.1, len(path)), 4 if far else 6, 0.25)
        cr = (rng.uniform(4.5, 6.0), rng.uniform(3.0, 4.0)) if variant == "a" else (rng.uniform(3.5, 4.8), rng.uniform(2.4, 3.2))
        clumps.append((path[-1], cr))
        if variant == "b":
            # A lower tier off the trunk.
            j = len(path) // 2
            low = pts[max(1, n - 3)]
            sd = norm(np.array([math.cos(a + 0.5), 0.25, math.sin(a + 0.5)]))
            sub = branch_path(low, sd, H * 0.17, 0.5, rng, 4)
            if not far:
                tube(bark, sub, np.linspace(0.2, 0.06, len(sub)), 4, 0.3)
            clumps.append((sub[-1], (rng.uniform(3.0, 4.0), rng.uniform(1.8, 2.4))))
    clumps.append((crown_c + UP * crown_r[1] * 0.5, (crown_r[0] * 0.45, crown_r[1] * 0.55)))
    # Epiphytes and suckers: smaller clumps hugging the trunk below the crown.
    for k in range(2 if far else 3):
        y = fork * rng.uniform(0.45, 0.9)
        a = rng.uniform(0, 2 * math.pi)
        c = np.array([math.cos(a) * 1.4, y, math.sin(a) * 1.4]) + lean * (y / fork) ** 2
        clumps.append((c, (rng.uniform(2.2, 3.2), rng.uniform(1.6, 2.4))))
    for c, r in clumps:
        clump(leaves, rng, c, r, 14 if far else 30, (5.8, 7.8) if far else (3.0, 4.4), crown_c, crown_r)
    return m


def build_palm(rng, far=False):
    m = Model("palm_far" if far else "palm")
    H = 18.0
    bark = m.surface("bark", ("bark_palm",), roughness=0.9)
    fronds = m.surface("fronds", ("frond_palm",), alpha=True, roughness=0.65, double=True)
    trunk_h = H * 0.86
    bend = rng.uniform(1.2, 2.8)
    a = rng.uniform(0, 2 * math.pi)
    dirv = np.array([math.cos(a), 0, math.sin(a)])
    top = dirv * bend * 1.6 + np.array([0, trunk_h, 0])
    sp = bezier(np.zeros(3), dirv * bend * 0.9 + np.array([0, trunk_h * 0.35, 0]), dirv * bend * 1.5 + np.array([0, trunk_h * 0.7, 0]), top, 6 if far else 14)
    radii = [0.32 + 0.25 * math.exp(-t * 14) - 0.1 * t for t in np.linspace(0, 1, len(sp))]
    tube(bark, sp, radii, 5 if far else 9, 0.5, col_fn=lambda t, p: shade(p[1], H * 0.3, 0.6, 1.0))
    crown = top + np.array([0, 0.3, 0])
    nf = 9 if far else 15
    for k in range(nf):
        az = k / nf * 2 * math.pi + rng.uniform(-0.15, 0.15)
        out = np.array([math.cos(az), 0, math.sin(az)])
        rise = rng.uniform(0.1, 0.9)
        L = rng.uniform(4.6, 6.2)
        droop = rng.uniform(1.8, 3.6) * (1.2 - rise * 0.6)
        p0 = crown
        p1 = crown + out * L * 0.3 + UP * L * (0.25 + rise * 0.35)
        p2 = crown + out * L * 0.7 + UP * L * (0.15 + rise * 0.2)
        p3 = crown + out * L + UP * (L * 0.1 * rise - droop)
        spine = bezier(p0, p1, p2, p3, 5 if far else 10)
        sd = [np.cross(UP, out)] * len(spine)
        wid = [1.9 * math.sin(math.pi * (0.12 + 0.88 * t)) ** 0.6 for t in np.linspace(0, 1, len(spine))]
        ribbon(fronds, spine, sd, wid, (0, 0, 1, 1), fold=0.45, crown=crown - UP * 1.0, lean_out=0.35,
               col_fn=lambda t: (0.75 + 0.25 * t, 0.75 + 0.25 * t, 0.7 + 0.25 * t, 1))
    if not far:
        nut = m.surface("nuts", ("bark_palm",), roughness=0.7)
        for k in range(rng.integers(3, 7)):
            az = rng.uniform(0, 2 * math.pi)
            sphere(nut, crown + np.array([math.cos(az) * 0.4, -0.35 - rng.uniform(0, 0.3), math.sin(az) * 0.4]), 0.17, (0.55, 0.6, 0.3, 1), 6)
    return m


def build_banana(rng):
    m = Model("banana")
    stem = m.surface("stem", ("bark_stem",), roughness=0.8)
    leaves = m.surface("leaves", ("leaf_banana",), alpha=True, roughness=0.55, double=True)
    for s in range(rng.integers(2, 4)):
        base = rng.normal(0, 0.35, 3) * np.array([1, 0, 1])
        hgt = rng.uniform(2.0, 3.1)
        lean = rng.normal(0, 0.15, 3) * np.array([1, 0, 1])
        sp = np.array([base + lean * t + np.array([0, hgt * t, 0]) for t in np.linspace(0, 1, 5)])
        tube(stem, sp, np.linspace(0.17, 0.1, 5), 7, 0.6, col_fn=lambda t, p: shade(t, 1, 0.6, 1.0))
        top = sp[-1]
        nl = rng.integers(6, 9)
        for k in range(nl):
            az = k / nl * 2 * math.pi + rng.uniform(-0.3, 0.3)
            out = np.array([math.cos(az), 0, math.sin(az)])
            L = rng.uniform(1.9, 2.7)
            rise = rng.uniform(0.3, 1.2)
            pet = top + out * 0.35 + UP * 0.35 * rise
            p3 = pet + out * L + UP * (rise * 0.6 - 1.2)
            spine = bezier(pet, pet + out * L * 0.35 + UP * L * 0.4 * rise, pet + out * L * 0.75 + UP * L * 0.15, p3, 8)
            sd = [np.cross(UP, out) + UP * rng.normal(0, 0.2)] * len(spine)
            wid = [0.62 * min(1.0, t * 5 + 0.15) for t in np.linspace(0, 1, len(spine))]
            ribbon(leaves, spine, sd, wid, (0, 0, 1, 1), fold=0.3, crown=top, lean_out=0.25)
            tube(stem, np.array([top, pet]), [0.04, 0.03], 3, 1.0)
    return m


def build_tree_fern(rng):
    m = Model("tree_fern")
    bark = m.surface("bark", ("bark_fern",), roughness=0.95)
    fronds = m.surface("fronds", ("frond_fern",), alpha=True, roughness=0.7, double=True)
    H = 6.0
    a = rng.uniform(0, 2 * math.pi)
    dirv = np.array([math.cos(a), 0, math.sin(a)]) * rng.uniform(0.2, 0.7)
    top = dirv + np.array([0, H * 0.78, 0])
    sp = bezier(np.zeros(3), dirv * 0.2 + UP * H * 0.3, dirv * 0.7 + UP * H * 0.6, top, 8)
    tube(bark, sp, np.linspace(0.2, 0.13, 8), 7, 0.8, col_fn=lambda t, p: shade(t, 1, 0.55, 1.0))
    nf = 13
    for k in range(nf):
        az = k / nf * 2 * math.pi + rng.uniform(-0.2, 0.2)
        out = np.array([math.cos(az), 0, math.sin(az)])
        L = rng.uniform(2.4, 3.2)
        rise = rng.uniform(0.4, 1.0)
        spine = bezier(top, top + out * L * 0.25 + UP * L * 0.45 * rise, top + out * L * 0.7 + UP * L * 0.2 * rise, top + out * L - UP * L * 0.3, 9)
        ribbon(fronds, spine, [np.cross(UP, out)] * 9, [1.15 * math.sin(math.pi * (0.1 + 0.9 * t)) ** 0.7 for t in np.linspace(0, 1, 9)],
               (0, 0, 1, 1), fold=0.25, crown=top, lean_out=0.3)
    return m


def build_fern(rng):
    m = Model("fern")
    fronds = m.surface("fronds", ("frond_fern",), alpha=True, roughness=0.75, double=True)
    nf = rng.integers(10, 15)
    c = np.array([0, 0.05, 0])
    for k in range(nf):
        az = k / nf * 2 * math.pi + rng.uniform(-0.25, 0.25)
        out = np.array([math.cos(az), 0, math.sin(az)])
        L = rng.uniform(1.0, 1.55)
        rise = rng.uniform(0.6, 1.3)
        spine = bezier(c, c + out * L * 0.15 + UP * L * 0.5 * rise, c + out * L * 0.6 + UP * L * 0.5 * rise, c + out * L + UP * L * 0.1, 7)
        ribbon(fronds, spine, [np.cross(UP, out)] * 7, [0.5 * math.sin(math.pi * (0.1 + 0.9 * t)) ** 0.7 for t in np.linspace(0, 1, 7)],
               (0, 0, 1, 1), fold=0.2, crown=c - UP * 0.5, lean_out=0.35, col_fn=lambda t: (0.65 + 0.35 * t, 0.65 + 0.35 * t, 0.65 + 0.35 * t, 1))
    return m


def build_elephant_ear(rng):
    m = Model("elephant_ear")
    stem = m.surface("stem", ("bark_stem",), roughness=0.7)
    leaves = m.surface("leaves", ("leaf_heart",), alpha=True, roughness=0.45, double=True)
    nl = rng.integers(5, 8)
    for k in range(nl):
        az = k / nl * 2 * math.pi + rng.uniform(-0.3, 0.3)
        out = np.array([math.cos(az), 0, math.sin(az)])
        hgt = rng.uniform(0.9, 1.7)
        reach = rng.uniform(0.25, 0.6)
        tip = out * reach + UP * hgt
        tube(stem, bezier(np.zeros(3), UP * hgt * 0.4, out * reach * 0.6 + UP * hgt * 0.9, tip, 5), np.linspace(0.04, 0.02, 5), 4, 1.0)
        L = rng.uniform(0.8, 1.2)
        # The blade hangs off the top of the stalk, tip down and out.
        down = norm(out * 0.9 - UP * 0.6)
        right = np.cross(UP, out)
        centre = tip + down * L * 0.45
        card(leaves, centre, right, -down, L * 0.85, L, (0, 0, 1, 1), crown=np.zeros(3), bend=0.25, lean_out=0.2, segs=3)
    return m


def build_bamboo(rng, far=False):
    m = Model("bamboo_far" if far else "bamboo")
    culm = m.surface("culm", ("bark_bamboo",), roughness=0.5)
    leaves = m.surface("leaves", ("spray_bamboo",), alpha=True, roughness=0.7, double=True)
    nc = 9 if far else 22
    for k in range(nc):
        base = rng.normal(0, 0.7, 3) * np.array([1, 0, 1])
        out = norm(base + rng.normal(0, 0.3, 3) * np.array([1, 0, 1]))
        hgt = rng.uniform(9.0, 13.5)
        bendv = out * rng.uniform(1.5, 3.5)
        sp = bezier(base, base + UP * hgt * 0.4, base + bendv * 0.4 + UP * hgt * 0.75, base + bendv + UP * hgt, 5 if far else 9)
        tube(culm, sp, np.linspace(0.075, 0.035, len(sp)), 3 if far else 6, 0.35)
        for j in list(range(len(sp) // 3, len(sp))) * (1 if far else 2):
            if far and j % 2:
                continue
            sz = rng.uniform(2.2, 3.2) * (1.6 if far else 1.0)
            o = norm(out + rng.normal(0, 0.6, 3))
            right = norm(np.cross(UP, o))
            card(leaves, sp[j] + o * sz * 0.35, right, norm(UP * 0.4 + o), sz, sz, (0, 0, 1, 1), crown=np.array([0, hgt * 0.7, 0]), lean_out=0.4, bend=0.3)
    return m


def build_grass(rng):
    m = Model("grass")
    blades = m.surface("blades", ("grass",), alpha=True, roughness=0.8, double=True)
    for k in range(4):
        a = k / 4 * math.pi + rng.uniform(-0.2, 0.2)
        right = np.array([math.cos(a), 0, math.sin(a)])
        h = rng.uniform(0.75, 0.95)
        card(blades, np.array([0, h * 0.5, 0]) + rng.normal(0, 0.05, 3) * np.array([1, 0, 1]), right, UP, h * 1.1, h, (0, 0, 1, 1),
             crown=np.array([0, -0.3, 0]), lean_out=0.5, col=(1, 1, 1, 1), bend=0.2, segs=2)
    return m


# ---------------------------------------------------------------- textures per model, and writing

def make_textures(rng):
    return {
        "bark_kapok": bark_texture("kapok", rng),
        "bark_brown": bark_texture("brown", rng),
        "bark_palm": bark_texture("palm", rng),
        "bark_bamboo": bark_texture("bamboo", rng),
        "bark_fern": bark_texture("fern", rng),
        "bark_stem": bark_texture("stem", rng),
        "spray_kapok": tex_leaf_spray(rng, 512, ((60, 100, 36), (82, 124, 44), (46, 82, 30)), 110, "ellipse", 0.42),
        "spray_canopy_a": tex_leaf_spray(rng, 512, ((52, 96, 34), (70, 116, 40), (38, 72, 28)), 120, "ellipse", 0.38),
        "spray_canopy_b": tex_leaf_spray(rng, 512, ((34, 70, 30), (46, 86, 34), (28, 58, 26)), 140, "lance", 0.3),
        "frond_palm": tex_pinnate(rng, 256, 1024, "palm"),
        "frond_fern": tex_pinnate(rng, 256, 1024, "fern"),
        "leaf_banana": tex_banana(rng),
        "leaf_heart": tex_heart(rng),
        "grass": tex_grass(rng),
        "spray_bamboo": tex_bamboo_spray(rng),
        "vine": tex_vine(rng),
    }


def encode(img):
    buf = io.BytesIO()
    if img.mode == "RGBA":
        img.save(buf, "PNG", optimize=True)
        return buf.getvalue(), "image/png"
    img.convert("RGB").save(buf, "JPEG", quality=88, optimize=True)
    return buf.getvalue(), "image/jpeg"


def write_model(model, textures, path):
    js = {"asset": {"version": "2.0", "generator": "tools/gltf/build_jungle_flora.py"},
          "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": model.name, "mesh": 0}],
          "meshes": [{"name": model.name, "primitives": []}], "materials": [], "textures": [], "images": [],
          "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
          "bufferViews": [], "accessors": []}
    binary = bytearray()

    def view(data, target=None):
        nonlocal binary
        binary += b"\0" * (-len(binary) % 4)
        v = {"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)}
        if target:
            v["target"] = target
        binary += data
        js["bufferViews"].append(v)
        return len(js["bufferViews"]) - 1

    def acc(arr, kind, comp=5126, bounds=False, target=34962):
        arr = np.ascontiguousarray(arr)
        a = {"bufferView": view(arr.tobytes(), target), "componentType": comp, "count": int(arr.shape[0]), "type": kind}
        if bounds:
            a["min"] = [float(v) for v in arr.min(0)]
            a["max"] = [float(v) for v in arr.max(0)]
        js["accessors"].append(a)
        return len(js["accessors"]) - 1

    image_index = {}
    for key, s in model.surfaces.items():
        if not s.idx:
            continue
        mat = model.materials[key]
        tex_name = mat["image"][0]
        if tex_name not in image_index:
            data, mime = encode(textures[tex_name])
            js["images"].append({"name": tex_name, "bufferView": view(data), "mimeType": mime})
            js["textures"].append({"sampler": 0, "source": len(js["images"]) - 1})
            image_index[tex_name] = len(js["textures"]) - 1
        m = {"name": "%s_%s" % (model.name, key),
             "pbrMetallicRoughness": {"baseColorTexture": {"index": image_index[tex_name]}, "metallicFactor": 0.0,
                                      "roughnessFactor": mat["roughness"]}}
        if mat["alpha"]:
            m["alphaMode"] = "MASK"
            m["alphaCutoff"] = 0.5
        if mat["double"]:
            m["doubleSided"] = True
        js["materials"].append(m)
        pos = np.array(s.pos, np.float32)
        prim = {"attributes": {"POSITION": acc(pos, "VEC3", bounds=True),
                               "NORMAL": acc(np.array(s.nrm, np.float32), "VEC3"),
                               "TEXCOORD_0": acc(np.array(s.uv, np.float32), "VEC2"),
                               "COLOR_0": acc(np.array(s.col, np.float32), "VEC4")},
                "indices": acc(np.array(s.idx, np.uint32), "SCALAR", 5125, target=34963),
                "material": len(js["materials"]) - 1}
        js["meshes"][0]["primitives"].append(prim)
    write_glb(path, js, binary)


BUILDERS = {
    "kapok": lambda r: build_kapok(r),
    "kapok_far": lambda r: build_kapok(r, far=True),
    "canopy_a": lambda r: build_canopy(r, "a"),
    "canopy_a_far": lambda r: build_canopy(r, "a", far=True),
    "canopy_b": lambda r: build_canopy(r, "b"),
    "canopy_b_far": lambda r: build_canopy(r, "b", far=True),
    "palm": lambda r: build_palm(r),
    "palm_far": lambda r: build_palm(r, far=True),
    "bamboo": lambda r: build_bamboo(r),
    "bamboo_far": lambda r: build_bamboo(r, far=True),
    "banana": build_banana,
    "tree_fern": build_tree_fern,
    "fern": build_fern,
    "elephant_ear": build_elephant_ear,
    "grass": build_grass,
}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="game/assets/environment/jungle")
    p.add_argument("--only", default="")
    p.add_argument("--seed", type=int, default=7)
    args = p.parse_args()
    os.makedirs(args.out, exist_ok=True)
    textures = make_textures(np.random.default_rng(args.seed))
    only = [s for s in args.only.split(",") if s]
    for name, build in BUILDERS.items():
        if only and name not in only:
            continue
        # A tree and its far model grow from the same numbers, so they match.
        rng = np.random.default_rng(args.seed * 1000 + sum(ord(ch) for ch in name.replace("_far", "")))
        model = build(rng)
        path = os.path.join(args.out, name + ".glb")
        write_model(model, textures, path)
        print("%-14s %6d tris  %s" % (name, model.tris(), path))


if __name__ == "__main__":
    main()
