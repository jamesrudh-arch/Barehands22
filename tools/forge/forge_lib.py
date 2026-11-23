"""forge_lib — procedural texture synthesis library for LEVERAGE.

Original code, original output. All textures produced here are original works
generated from mathematical noise + hand-authored structure (no external art).

Provides: seeded value-noise FBM, tileable noise, domain warping, brick/panel
structure generators, normal-map derivation (Sobel), PBR-ish map baking,
9-patch helpers, and PNG save utilities.
"""
import numpy as np

RNG_SEED = 2077  # Cinder City's unlucky number


# ---------------------------------------------------------------- noise ----
def _smoothstep(t):
    return t * t * (3.0 - 2.0 * t)


def value_noise(size, freq, rng, tile=True):
    """Tileable value noise: random lattice, bicubic-ish smooth interp."""
    n = int(size)
    f = max(1, int(freq))
    # lattice wraps (tileable)
    lat = rng.random((f, f))
    ys = np.linspace(0, f, n, endpoint=False)
    xs = np.linspace(0, f, n, endpoint=False)
    y0 = np.floor(ys).astype(int) % f
    x0 = np.floor(xs).astype(int) % f
    ty = _smoothstep(ys - np.floor(ys))
    tx = _smoothstep(xs - np.floor(xs))
    y1 = (y0 + 1) % f
    x1 = (x0 + 1) % f
    TL = lat[np.ix_(y0, x0)]
    TR = lat[np.ix_(y0, x1)]
    BL = lat[np.ix_(y1, x0)]
    BR = lat[np.ix_(y1, x1)]
    ty = ty[:, None]
    tx = tx[None, :]
    top = TL + (TR - TL) * tx
    bot = BL + (BR - BL) * tx
    return top + (bot - top) * ty


def fbm(size, octaves=5, base_freq=4, gain=0.5, rng=None, tile=True, warp=0.0):
    """Fractal Brownian motion, normalized to [0,1]. Optional domain warp."""
    if rng is None:
        rng = np.random.default_rng(RNG_SEED)
    out = np.zeros((size, size))
    amp = 1.0
    tot = 0.0
    f = base_freq
    qx = qy = None
    if warp > 0.0:
        qx = value_noise(size, base_freq, np.random.default_rng(rng.integers(1 << 30)), tile) - 0.5
        qy = value_noise(size, base_freq * 2, np.random.default_rng(rng.integers(1 << 30)), tile) - 0.5
    for _ in range(octaves):
        n = value_noise(size, f, np.random.default_rng(rng.integers(1 << 30)), tile)
        if warp > 0.0:
            # cheap domain warp: blend shifted noise
            shift = (qx * warp * size / f).astype(int)
            n = np.roll(np.roll(n, shift, axis=0), (shift.T if warp else shift), axis=1) if False else n
            n = n * (0.7 + 0.6 * (qy + 0.5))
            n = np.clip(n, 0, 1)
        out += amp * n
        tot += amp
        amp *= gain
        f *= 2
    return out / tot


def ridged(size, octaves=4, base_freq=4, rng=None):
    if rng is None:
        rng = np.random.default_rng(RNG_SEED)
    out = np.zeros((size, size))
    amp, tot, f = 1.0, 0.0, base_freq
    for _ in range(octaves):
        n = value_noise(size, f, np.random.default_rng(rng.integers(1 << 30)))
        out += amp * (1.0 - np.abs(n * 2.0 - 1.0))
        tot += amp
        amp *= 0.5
        f *= 2
    return out / tot


def white_noise(size, rng=None, scale=1.0):
    if rng is None:
        rng = np.random.default_rng(RNG_SEED)
    return rng.random((size, size)) * scale


# ------------------------------------------------------------ structure ----
def brick_pattern(size, rows, mortar=0.06, jitter=0.02, rng=None):
    """Height mask: 1 = brick face, low = mortar. Offset running bond."""
    if rng is None:
        rng = np.random.default_rng(RNG_SEED)
    h = np.ones((size, size))
    rh = size / rows
    cols = max(2, int(rows * 1.9))
    cw = size / cols
    m = mortar * rh
    for r in range(rows):
        y0 = int(r * rh)
        y1 = int((r + 1) * rh)
        off = (r % 2) * (cw / 2)
        # horizontal mortar
        h[y0:int(y0 + m / 2), :] = 0.15
        h[int(y1 - m / 2):y1, :] = 0.15
        for c in range(-1, cols + 1):
            x = int((c * cw + off) % size)
            j = rng.random() * jitter * cw
            xj = int((x + j) % size)
            w = max(1, int(m * 0.7))
            h[:, xj:xj + w] = 0.15
    return h


def panel_lines(size, nx, ny, width=0.01, depth=0.25):
    """Grid panel seams (metal panels / concrete slabs)."""
    h = np.ones((size, size))
    for i in range(nx):
        x = int(i * size / nx)
        w = max(1, int(width * size))
        h[:, x:x + w] = depth
    for j in range(ny):
        y = int(j * size / ny)
        w = max(1, int(width * size))
        h[y:y + w, :] = depth
    return h


def tiles_pattern(size, nx, ny, mortar=0.08):
    h = np.ones((size, size))
    cw, chh = size / nx, size / ny
    m = mortar * min(cw, chh)
    for i in range(nx + 1):
        x = int(i * cw) % size
        h[:, max(0, x - 1):x + 1] = 0.2
    for j in range(ny + 1):
        y = int(j * chh) % size
        h[max(0, y - 1):y + 1, :] = 0.2
    return h


# ------------------------------------------------------------- utilities ---
def normal_from_height(h, strength=2.0):
    """Sobel-based normal map (RGB, y-up per Godot convention: G flipped)."""
    hl = np.roll(h, 1, axis=1)
    hr = np.roll(h, -1, axis=1)
    hu = np.roll(h, 1, axis=0)
    hd = np.roll(h, -1, axis=0)
    dx = (hl - hr) * strength
    dy = (hd - hu) * strength  # flip for Godot green-up
    n = np.stack([dx, dy, np.ones_like(dx)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return (n * 0.5 + 0.5)


def ao_from_height(h, radius=2, strength=0.5):
    """Cheap cavity AO from height: darker where neighbors are higher."""
    acc = np.zeros_like(h)
    for dx in range(-radius, radius + 1):
        for dy in range(-radius, radius + 1):
            if dx == 0 and dy == 0:
                continue
            acc += np.roll(np.roll(h, dx, 0), dy, 1)
    avg = acc / ((2 * radius + 1) ** 2 - 1)
    ao = np.clip(1.0 - (avg - h) * strength * 4.0, 0, 1)
    return ao


def rough_from_height(h, base=0.8, vary=0.3):
    return np.clip(base + (h - 0.5) * vary * 2.0, 0.05, 1.0)


def to_rgb(arr, size):
    """(size,size) float [0,1] -> (size,size,3) uint8 gray."""
    a = np.clip(arr, 0, 1)
    g = (a * 255).astype(np.uint8)
    return np.stack([g, g, g], axis=-1)


def colorize(height, dark, light, contrast=1.0):
    """Map [0,1] height to gradient between two RGB colors (0-255 tuples)."""
    t = np.clip((height - 0.5) * contrast + 0.5, 0, 1)
    d = np.array(dark, dtype=float)
    l = np.array(light, dtype=float)
    return (d[None, None, :] + t[..., None] * (l - d)[None, None, :])


def save_png(path, arr_rgb_uint8):
    from PIL import Image
    Image.fromarray(arr_rgb_uint8.astype(np.uint8), "RGB").save(path)


def save_rgba_png(path, arr_rgba_uint8):
    from PIL import Image
    Image.fromarray(arr_rgba_uint8.astype(np.uint8), "RGBA").save(path)


def radial_mask(size, power=1.0):
    y, x = np.mgrid[0:size, 0:size] / size
    d = np.sqrt((x - 0.5) ** 2 + (y - 0.5) ** 2) * 2.0
    return np.clip(1.0 - d, 0, 1) ** power


def ellipse_mask(size, cx, cy, rx, ry, soft=0.1):
    y, x = np.mgrid[0:size, 0:size] / size
    d = np.sqrt(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2)
    return np.clip((1.0 - d) / soft, 0, 1)
