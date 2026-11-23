#!/usr/bin/env python3
"""Render docs/gameplay_concept.png — the LEVERAGE gameplay concept frame.

A tiny software 3D renderer: pinhole camera, per-pixel z-buffered quads,
emissive additive glow buffer, painter's-algorithm sprites (humanoids, cars),
screen-space wet-asphalt reflection, rain, film grade — then the touch HUD
laid out per docs/CONTROLS.md §2.

Palette / lighting / mood follow docs/ART_DIRECTION.md: night near-blue blacks
(#0a0c12), wet asphalt, sodium-amber Kiln Row lamps vs teal-white Neon Mile,
emissive window grids, rain streaks, third-person camera at 3.4 m.

HONEST LABEL: this is an ART-DIRECTION TARGET illustration, NOT engine output.
The delivery sandbox is headless with no GPU/rasterizer (docs/KNOWN_DEFECTS.md
K-08); on device the Godot mobile renderer produces the real frame. This
script is the reproducible source of truth for the concept image.

Run:  /tmp/gvenv/bin/python tools/concept/render_concept.py
Deps: numpy, Pillow, system DejaVu fonts.
"""
import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SS = 2
BW, BH = 585, 1266
W, H = BW * SS, BH * SS
FONT_DIR = "/usr/share/fonts/truetype/dejavu"
OUT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "docs", "gameplay_concept.png"))

AMBER = (242, 184, 64)
CRIMSON = (232, 64, 56)
TEAL = (59, 232, 176)
PAPER = (233, 229, 218)
GREY = (154, 163, 178)
FOG = np.array((16, 20, 30), np.float32)

CAM_Y = 3.4
CY = H * 0.40
F = H * 1.02

RNG = np.random.default_rng(20261123)


def fnt(size, bold=False):
    name = "DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"
    return ImageFont.truetype(os.path.join(FONT_DIR, name), int(size * SS))


def proj(x, y, z):
    if z < 0.3:
        return None
    return (W / 2 + F * x / z, CY + F * (CAM_Y - y) / z)


def fogged(col, z, k=1 / 150.0):
    t = 1.0 - math.exp(-z * k)
    c = np.array(col, np.float32) * (1 - t) + FOG * t
    return tuple(int(v) for v in c)


class Renderer:
    """z-buffered quad rasterizer + additive glow buffer."""

    def __init__(self):
        self.rgb = np.zeros((H, W, 3), np.float32)
        self.zbuf = np.full((H, W), np.inf, np.float32)
        self.glow = np.zeros((H, W, 3), np.float32)

    # ---- primitives ----
    def quad(self, pts, col, z=None, additive=False, glow_amt=0.0):
        pts = [(p[0], p[1]) for p in pts if p is not None]
        if len(pts) < 3:
            return
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        x0, x1 = int(max(0, min(xs))), int(min(W - 1, max(xs)))
        y0, y1 = int(max(0, min(ys))), int(min(H - 1, max(ys)))
        if x1 <= x0 or y1 <= y0:
            return
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        inside = np.ones(gx.shape, bool)
        n = len(pts)
        for i in range(n):
            ax, ay = pts[i]
            bx, by = pts[(i + 1) % n]
            cross = (bx - ax) * (gy - ay) - (by - ay) * (gx - ax)
            inside &= cross >= -1e-6 if cross.mean() >= 0 else cross <= 1e-6
        if not inside.any():
            return
        if z is None:
            z = np.mean([p[2] for p in pts]) if all(len(p) > 2 for p in pts) else 50.0
        if isinstance(z, (int, float)):
            zz = np.full(gx.shape, float(z), np.float32)
        else:
            zz = z
        sel = inside
        if not additive:
            sel = inside & (zz < self.zbuf[y0:y1 + 1, x0:x1 + 1])
            self.zbuf[y0:y1 + 1, x0:x1 + 1][sel] = zz[sel]
        c = np.array(col, np.float32)
        self.rgb[y0:y1 + 1, x0:x1 + 1][sel] = c
        if glow_amt > 0:
            self.glow[y0:y1 + 1, x0:x1 + 1][sel] += c * glow_amt

    def depth_quad(self, x, y0, y1, z0, z1, col, glow_amt=0.0, z_eps=0.0):
        """vertical quad on plane X=x, interpolating depth across pixels."""
        p00, p01 = proj(x, y0, z0), proj(x, y0, z1)
        p10, p11 = proj(x, y1, z0), proj(x, y1, z1)
        if None in (p00, p01, p10, p11):
            return
        xs = [p[0] for p in (p00, p01, p10, p11)]
        ys = [p[1] for p in (p00, p01, p10, p11)]
        x0, x1 = int(max(0, min(xs))), int(min(W - 1, max(xs)))
        y0p, y1p = int(max(0, min(ys))), int(min(H - 1, max(ys)))
        if x1 <= x0 or y1p <= y0p:
            return
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0p, y1p + 1))
        # barycentric in (z, y): solve screen quad as bilinear in (u=z, v=y)
        zz = F * abs(x) / np.maximum(1e-3, np.abs(gx - W / 2)) - z_eps
        pts = [p00, p01, p11, p10]
        inside = np.ones(gx.shape, bool)
        for i in range(4):
            ax, ay = pts[i]
            bx, by = pts[(i + 1) % 4]
            cross = (bx - ax) * (gy - ay) - (by - ay) * (gx - ax)
            inside &= cross >= -1e-6 if cross.mean() >= 0 else cross <= 1e-6
        sel = inside & (zz < self.zbuf[y0p:y1p + 1, x0:x1 + 1])
        if not sel.any():
            return
        self.zbuf[y0p:y1p + 1, x0:x1 + 1][sel] = zz[sel]
        c = np.array(col, np.float32)
        self.rgb[y0p:y1p + 1, x0:x1 + 1][sel] = c
        if glow_amt > 0:
            self.glow[y0p:y1p + 1, x0:x1 + 1][sel] += c * glow_amt

    def ground_quad(self, x0, x1, z0, z1, col, alpha=1.0, z_eps=0.0):
        p00, p01 = proj(x0, 0.02, z0), proj(x1, 0.02, z0)
        p10, p11 = proj(x0, 0.02, z1), proj(x1, 0.02, z1)
        if None in (p00, p01, p10, p11):
            return
        xs = [p[0] for p in (p00, p01, p10, p11)]
        ys = [p[1] for p in (p00, p01, p10, p11)]
        x0p, x1p = int(max(0, min(xs))), int(min(W - 1, max(xs)))
        y0p, y1p = int(max(0, min(ys))), int(min(H - 1, max(ys)))
        if x1p <= x0p or y1p <= y0p:
            return
        gx, gy = np.meshgrid(np.arange(x0p, x1p + 1), np.arange(y0p, y1p + 1))
        pts = [p00, p01, p11, p10]
        inside = np.ones(gx.shape, bool)
        for i in range(4):
            ax, ay = pts[i]
            bx, by = pts[(i + 1) % 4]
            cross = (bx - ax) * (gy - ay) - (by - ay) * (gx - ax)
            inside &= cross >= -1e-6 if cross.mean() >= 0 else cross <= 1e-6
        zz = F * (CAM_Y - 0.02) / np.maximum(1e-3, gy - CY) - z_eps
        sel = inside & (zz < self.zbuf[y0p:y1p + 1, x0p:x1p + 1])
        if not sel.any():
            return
        self.zbuf[y0p:y1p + 1, x0p:x1p + 1][sel] = zz[sel]
        c = np.array(col, np.float32)
        dst = self.rgb[y0p:y1p + 1, x0p:x1p + 1]
        dst[sel] = dst[sel] * (1 - alpha) + c * alpha

    def glow_at(self, px, py, r, color, peak):
        d = max(2, int(r))
        cx, cy = int(px), int(py)
        x0, x1 = max(0, cx - d), min(W, cx + d)
        y0, y1 = max(0, cy - d), min(H, cy + d)
        if x1 <= x0 or y1 <= y0:
            return
        yy, xx = np.mgrid[y0 - cy + d:y1 - cy + d, x0 - cx + d:x1 - cx + d].astype(np.float32)
        dist = np.sqrt((xx - d) ** 2 + (yy - d) ** 2) / d
        a = np.clip(1.0 - dist, 0, 1) ** 2 * (peak / 255.0)
        self.glow[y0:y1, x0:x1] += np.array(color, np.float32) * a[..., None]

    def composite(self):
        out = np.clip(self.rgb + self.glow, 0, 255)
        return Image.fromarray(out.astype(np.uint8)).convert("RGBA")


def human_sprites(img):
    """pedestrians + player drawn in painter order (far first)."""
    d = ImageDraw.Draw(img)

    def person(px, pz, scale_col, rim=None, detail=True):  # rim kept subtle
        bp = proj(px, 0.0, pz)
        if bp is None:
            return
        hp = proj(px, 1.62, pz)
        bw = 0.19 * F / pz
        d.ellipse([bp[0] - bw, hp[1] + 0.10 * F / pz, bp[0] + bw, bp[1]], fill=scale_col)
        hr = 0.14 * F / pz
        d.ellipse([hp[0] - hr, hp[1] - hr, hp[0] + hr, hp[1] + hr], fill=scale_col)
        if rim:
            d.arc([hp[0] - hr, hp[1] - hr, hp[0] + hr, hp[1] + hr], 110, 230,
                  fill=rim + (64,), width=max(1, SS))
        if detail and pz < 6:
            pass
        return bp

    # far pedestrians, left sidewalk
    for (px, pz) in [(-8.3, 44.0), (-7.8, 40.0)]:
        bp = person(px, pz, (9, 10, 13), None)
        rf = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        bw = 0.24 * F / pz
        ImageDraw.Draw(rf).ellipse([bp[0] - bw, bp[1], bp[0] + bw, bp[1] + 0.45 * F / pz],
                                   fill=(9, 10, 13, 46))
        img.alpha_composite(rf)
    return img


def player_sprite(img):
    """Eli from behind at 6.4 m — boxy silhouette + rim light + wet smear."""
    pz = 6.4
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    def q(x0, y0, x1, y1, col, alpha=255):
        p = [proj(x0, y0, pz), proj(x1, y0, pz), proj(x1, y1, pz), proj(x0, y1, pz)]
        d.polygon([(v[0], v[1]) for v in p], fill=col + (alpha,))

    # boots, legs
    q(-0.225, 0.0, -0.02, 0.16, (10, 11, 14))
    q(0.03, 0.0, 0.235, 0.16, (10, 11, 14))
    q(-0.20, 0.0, -0.04, 0.98, (24, 27, 33))
    q(0.04, 0.0, 0.20, 0.98, (20, 23, 28))
    # torso + arms
    q(-0.24, 0.95, 0.24, 1.62, (40, 35, 28))
    q(-0.33, 1.00, -0.215, 1.56, (34, 30, 24))
    q(0.215, 1.00, 0.33, 1.56, (34, 30, 24))
    # jacket hem amber lining + shoulder yoke
    q(-0.24, 0.95, 0.24, 1.01, AMBER, 90)
    q(-0.24, 1.50, 0.24, 1.62, (48, 42, 33))
    q(-0.24, 0.95, -0.15, 1.62, (33, 29, 23))
    q(0.15, 0.95, 0.24, 1.62, (30, 26, 21))
    # seam
    s0, s1 = proj(0.0, 1.03, pz), proj(0.0, 1.60, pz)
    d.line([s0, s1], fill=(22, 19, 15), width=max(1, SS))
    # fists
    for sx in (-0.275, 0.275):
        fp = proj(sx, 0.94, pz)
        r = 0.058 * F / pz
        d.ellipse([fp[0] - r, fp[1] - r, fp[0] + r, fp[1] + r], fill=(110, 74, 48))
    # neck, head, crop hair
    npj = proj(0.0, 1.60, pz)
    hpj = proj(0.0, 1.78, pz)
    hr = 0.145 * F / pz
    d.rectangle([npj[0] - 0.07 * F / pz, npj[1] - 0.12 * F / pz, npj[0] + 0.07 * F / pz, npj[1]],
                fill=(93, 63, 40))
    d.ellipse([hpj[0] - hr, hpj[1] - hr, hpj[0] + hr, hpj[1] + hr], fill=(110, 74, 48))
    d.pieslice([hpj[0] - hr, hpj[1] - hr, hpj[0] + hr, hpj[1] + hr], 168, 372, fill=(18, 14, 10))
    # rim lights: sodium amber (left), Neon Mile teal (right)
    lw = max(2, int(0.022 * F / pz))
    l0, l1 = proj(-0.245, 0.98, pz), proj(-0.245, 1.62, pz)
    d.line([l0, l1], fill=AMBER + (150,), width=lw)
    d.arc([hpj[0] - hr, hpj[1] - hr, hpj[0] + hr, hpj[1] + hr], 128, 205, fill=AMBER + (130,), width=lw)
    r0, r1 = proj(0.245, 0.98, pz), proj(0.245, 1.62, pz)
    d.line([r0, r1], fill=TEAL + (80,), width=max(1, lw - 1))
    d.arc([hpj[0] - hr, hpj[1] - hr, hpj[0] + hr, hpj[1] + hr], -12, 52, fill=TEAL + (80,), width=max(1, lw - 1))
    img.alpha_composite(layer)
    # contact shadow + wet smear below feet
    d2 = ImageDraw.Draw(img)
    bp = proj(0.0, 0.0, pz)
    d2.ellipse([bp[0] - 0.38 * F / pz, bp[1] - 0.08 * F / pz, bp[0] + 0.38 * F / pz, bp[1] + 0.08 * F / pz],
               fill=(0, 0, 0, 150))
    smear = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(smear)
    rw = 0.24 * F / pz
    rh = 1.0 * F / pz
    sd.polygon([(bp[0] - rw, bp[1]), (bp[0] + rw, bp[1]),
                (bp[0] + rw * 0.75, bp[1] + rh), (bp[0] - rw * 0.75, bp[1] + rh)], fill=(28, 24, 19, 70))
    sd.polygon([(bp[0] - rw, bp[1]), (bp[0] + rw, bp[1]),
                (bp[0] + rw, bp[1] + 0.10 * F / pz), (bp[0] - rw, bp[1] + 0.10 * F / pz)], fill=AMBER + (60,))
    img.alpha_composite(smear.filter(ImageFilter.GaussianBlur(SS)))
    return img


def build_world():
    return_img_holder.clear()
    R = Renderer()
    # sky
    rows = np.arange(H)
    t = np.clip(rows / CY, 0, 1)
    sky = np.zeros((H, W, 3), np.float32)
    top = np.array((4, 6, 10), np.float32)
    hor = np.array((20, 26, 38), np.float32)
    sky[:] = (top + (hor - top) * (t ** 1.6)[:, None, None])
    R.rgb[:] = sky
    # distant skyline
    for i in range(30):
        x = RNG.uniform(-45, 45)
        z = RNG.uniform(150, 260)
        h = RNG.uniform(12, 34)
        w = RNG.uniform(4, 10)
        pts = [proj(x, 0, z), proj(x + w, 0, z), proj(x + w, h, z), proj(x, h, z)]
        R.quad(pts, fogged((7, 9, 14), z, 1 / 1200), z=z)
        for _ in range(4):
            wp = proj(x + RNG.uniform(0.8, w - 0.8), RNG.uniform(3, h - 2), z)
            if wp:
                c = TEAL if RNG.random() < 0.7 else AMBER
                R.glow_at(wp[0], wp[1], 2.4 * SS, c, 55)
    # Neon Mile horizon bleed
    R.glow_at(W * 0.5, CY - 10, int(F * 0.5), TEAL, 16)
    R.glow_at(W * 0.32, CY - 6, int(F * 0.2), AMBER, 10)

    # street base
    depth = np.clip((rows - CY) / (H - CY), 0, 1)
    col_far = np.array((11, 12, 16), np.float32)
    col_near = np.array((24, 26, 32), np.float32)
    street = np.zeros((H, W, 3), np.float32)
    street[:] = col_far + (col_near - col_far) * (depth[:, None, None] ** 0.7)
    below = rows > CY
    R.rgb[below] = street[below]
    R.zbuf[below] = 1e6  # ground writes only where nothing else drew? keep inf-safe:
    R.zbuf[below] = np.where(R.zbuf[below] == np.inf, (CAM_Y * F) / np.maximum(1, rows[below][:, None] - CY), R.zbuf[below])

    # sidewalks / curbs / lane dashes
    R.ground_quad(-10.5, -7.0, 6, 240, (21, 21, 25))
    R.ground_quad(7.0, 10.5, 6, 240, (21, 21, 25))
    R.ground_quad(-7.2, -7.0, 6, 240, (40, 41, 48))
    R.ground_quad(7.0, 7.2, 6, 240, (40, 41, 48))
    z = 14.0
    while z < 120:
        a = math.exp(-z / 70)
        R.ground_quad(-0.16, 0.16, z, z + 2.6, (200, 176, 106), alpha=a)
        z += 7.0

    # buildings far -> near, both sides
    segs = [(160, 220, 26), (120, 160, 22), (86, 120, 24), (58, 86, 20), (34, 58, 23), (10, 34, 18)]
    for (z0, z1, hh) in reversed(segs):
        zm = (z0 + z1) / 2
        for side in (-1, 1):
            xf = side * 10.5
            base = fogged((24, 20, 17) if side < 0 else (22, 19, 17), zm, 1 / 260)
            R.depth_quad(xf, 0, hh, z0, z1, base)
            R.depth_quad(xf, hh - 0.7, hh, z0, z1, fogged((13, 11, 9), zm, 1 / 260))
            # window grid
            zc = z0 + 2.0
            while zc < z1 - 1.5:
                y = 3.0
                while y < hh - 2.0:
                    wr = np.random.default_rng(int(zc * 97 + y * 13 + side * 7))
                    lit = wr.random() < 0.42
                    warm = wr.random() < (0.85 if zm < 90 else 0.45)
                    col = AMBER if warm else TEAL
                    dim = math.exp(-zm / 170)
                    if lit:
                        R.depth_quad(xf - side * 0.03, y, y + 1.7, zc - 0.06, zc + 1.64,
                                     tuple(int(c * dim) for c in col), glow_amt=0.55 * dim, z_eps=0.05)
                    else:
                        R.depth_quad(xf - side * 0.03, y, y + 1.7, zc - 0.06, zc + 1.64, (10, 11, 14), z_eps=0.05)
                    y += 3.1
                zc += 3.6
    # shopfront glows
    R.depth_quad(-10.4, 0.2, 3.2, 16, 26, AMBER, glow_amt=0.35, z_eps=0.05)
    R.depth_quad(-10.4, 3.2, 4.0, 16, 26, (60, 34, 14))
    R.depth_quad(10.4, 4.2, 5.6, 44, 50, (150, 30, 27), glow_amt=0.22, z_eps=0.05)
    R.depth_quad(10.4, 6.5, 11.5, 66, 69, TEAL, glow_amt=0.9, z_eps=0.05)
    for (gx, gy, gz, gc, gr, gp) in [(10.2, 9.0, 67, TEAL, 26, 60), (-10.2, 2.0, 21, AMBER, 40, 40),
                                     (10.2, 4.9, 47, CRIMSON, 22, 38)]:
        p = proj(gx, gy, gz)
        R.glow_at(p[0], p[1], gr * F / gz, gc, gp)

    # traffic light
    hb = proj(5.6, 4.3, 58)
    base = proj(5.6, 0, 58)
    hw = 0.5 * F / 58
    R.quad([proj(5.55, 0, 58), proj(5.65, 0, 58), proj(5.65, 5.4, 58), proj(5.55, 5.4, 58)], (10, 11, 14), z=58)
    R.quad([proj(5.35, 4.3, 58), proj(5.85, 4.3, 58), proj(5.85, 5.6, 58), proj(5.35, 5.6, 58)], (14, 16, 20), z=57.9)
    R.glow_at(hb[0], hb[1] + 0.9 * hw, hw * 1.6, CRIMSON, 210)
    R.quad([proj(5.5, 5.25, 57.8), proj(5.7, 5.25, 57.8), proj(5.7, 5.45, 57.8), proj(5.5, 5.45, 57.8)],
           CRIMSON, z=57.8, glow_amt=2.0)
    R.quad([proj(5.5, 4.95, 57.8), proj(5.7, 4.95, 57.8), proj(5.7, 5.12, 57.8), proj(5.5, 5.12, 57.8)],
           (58, 44, 20), z=57.8)
    R.quad([proj(5.5, 4.62, 57.8), proj(5.7, 4.62, 57.8), proj(5.7, 4.79, 57.8), proj(5.5, 4.79, 57.8)],
           (30, 46, 28), z=57.8)

    # parked car, right curb (mid-ground interest)
    pkx, pkz = 6.0, 24.0
    R.quad([proj(pkx - 0.9, 0.28, pkz), proj(pkx + 0.9, 0.28, pkz), proj(pkx + 0.9, 1.2, pkz), proj(pkx - 0.9, 1.2, pkz)],
           fogged((34, 32, 30), pkz), z=pkz)
    R.quad([proj(pkx - 0.75, 1.2, pkz), proj(pkx + 0.75, 1.2, pkz), proj(pkx + 0.65, 1.62, pkz), proj(pkx - 0.65, 1.62, pkz)],
           fogged((26, 24, 22), pkz), z=pkz)
    R.quad([proj(pkx - 0.9, 0.28, pkz), proj(pkx + 0.9, 0.28, pkz), proj(pkx + 0.9, 0.42, pkz), proj(pkx - 0.9, 0.42, pkz)],
           (12, 12, 14), z=pkz - 0.01)
    pp = proj(pkx - 0.5, 1.0, pkz)
    R.glow_at(pp[0], pp[1], 0.3 * F / pkz, AMBER, 40)   # side marker glint

    # traffic car at red
    cx, cz = 2.8, 52.0
    R.quad([proj(cx - 0.95, 0.30, cz), proj(cx + 0.95, 0.30, cz), proj(cx + 0.95, 1.25, cz), proj(cx - 0.95, 1.25, cz)],
           fogged((40, 52, 68), cz), z=cz)
    R.quad([proj(cx - 0.8, 1.25, cz), proj(cx + 0.8, 1.25, cz), proj(cx + 0.7, 1.72, cz), proj(cx - 0.7, 1.72, cz)],
           fogged((30, 40, 52), cz), z=cz)
    R.quad([proj(cx - 0.66, 1.30, cz), proj(cx + 0.66, 1.30, cz), proj(cx + 0.58, 1.68, cz), proj(cx - 0.58, 1.68, cz)],
           (22, 32, 34), z=cz - 0.01, glow_amt=0.03)
    sh0, sh1 = proj(cx - 1.0, 0.02, cz), proj(cx + 1.0, 0.02, cz)
    R.ground_quad(cx - 1.0, cx + 1.0, cz - 0.5, cz + 0.5, (0, 0, 0), alpha=0.5)
    for sx in (-0.72, 0.72):
        tp = proj(cx + sx, 0.95, cz)
        R.glow_at(tp[0], tp[1], 0.55 * F / cz, CRIMSON, 200)
        R.quad([proj(cx + sx - 0.16, 0.88, cz - 0.02), proj(cx + sx + 0.16, 0.88, cz - 0.02),
                proj(cx + sx + 0.16, 1.02, cz - 0.02), proj(cx + sx - 0.16, 1.02, cz - 0.02)],
               (255, 90, 80), z=cz - 0.02, glow_amt=2.2)
        # wet smear
        for i in range(16):
            a = 0.10 * (1 - i / 16)
            yy = tp[1] + i * 0.10 * F / cz
            ww = 0.16 * F / cz * (1 + i * 0.05)
            R.rgb[int(yy):int(yy) + max(1, int(0.06 * F / cz)), int(tp[0] - ww):int(tp[0] + ww)] += \
                np.array(CRIMSON, np.float32) * a

    # lamps far -> near
    lamps = [(-7.6, 90), (7.6, 76), (-7.6, 64), (7.6, 50), (-7.6, 38), (7.6, 26), (-7.6, 16)]
    for (lx, lz) in reversed(lamps):
        head = proj(lx * 0.86, 6.2, lz)
        basep = proj(lx, 0, lz)
        R.quad([proj(lx - 0.06, 0, lz), proj(lx + 0.06, 0, lz), proj(lx + 0.06, 6.2, lz), proj(lx - 0.06, 6.2, lz)],
               (9, 10, 13), z=lz)
        R.quad([proj(min(lx, lx * 0.86) - 0.04, 6.15, lz), proj(max(lx, lx * 0.86) + 0.04, 6.15, lz),
                proj(max(lx, lx * 0.86) + 0.04, 6.28, lz), proj(min(lx, lx * 0.86) - 0.04, 6.28, lz)],
               (9, 10, 13), z=lz)
        R.glow_at(head[0], head[1], 1.15 * F / lz, AMBER, 235)
        R.quad([proj(lx * 0.86 - 0.14, 6.05, lz - 0.01), proj(lx * 0.86 + 0.14, 6.05, lz - 0.01),
                proj(lx * 0.86 + 0.14, 6.18, lz - 0.01), proj(lx * 0.86 - 0.14, 6.18, lz - 0.01)],
               (255, 224, 150), z=lz - 0.01, glow_amt=2.4)
        # light cone + pool
        cone = np.zeros((H, W, 4), np.uint8)
        cimg = Image.fromarray(cone)
        cd = ImageDraw.Draw(cimg)
        w0 = 0.22 * F / lz
        w1 = 2.3 * F / lz
        cd.polygon([(head[0] - w0, head[1]), (head[0] + w0, head[1]),
                    (basep[0] + w1, basep[1]), (basep[0] - w1, basep[1])], fill=AMBER + (22,))
        pw = 2.5 * F / lz
        phh = 0.5 * F / lz
        cd.ellipse([basep[0] - pw, basep[1] - phh, basep[0] + pw, basep[1] + phh], fill=AMBER + (52,))
        cimg = cimg.filter(ImageFilter.GaussianBlur(SS))
        return_img_holder.append(cimg)

    img = R.composite()
    for cimg in return_img_holder:
        img.alpha_composite(cimg)
    img = human_sprites(img)
    img = player_sprite(img)
    return img


return_img_holder = []


def wet_reflection(img):
    hor = int(CY)
    top = img.crop((0, 0, W, hor)).transpose(Image.FLIP_TOP_BOTTOM)
    refl = top.resize((W, H - hor)).filter(ImageFilter.GaussianBlur(1.1 * SS))
    arr = np.asarray(refl).astype(np.float32)
    lum = arr[..., :3].mean(axis=2) / 255.0
    rows = np.arange(H - hor)[:, None]
    fade = np.clip(1.0 - rows / (H - hor), 0, 1) ** 1.6 * 0.38 + 0.04
    streak = np.random.default_rng(3).uniform(0.5, 1.0, (H - hor, 1))
    a = np.clip(lum * 2.4, 0, 1) * fade * streak
    arr[..., 3] = a * 170
    arr[..., :3] *= 0.75
    out = img.copy()
    out.alpha_composite(Image.fromarray(arr.astype(np.uint8)), (0, hor))
    return out


def rain_and_grade(img):
    rain = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rain)
    rng = np.random.default_rng(7)
    for _ in range(420):
        x, y = rng.uniform(0, W), rng.uniform(0, H)
        ln = rng.uniform(18, 46) * SS
        a = int(rng.uniform(14, 46))
        rd.line([x, y, x - ln * 0.14, y + ln], fill=(185, 200, 218, a), width=max(1, SS))
    img.alpha_composite(rain)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    nd = np.sqrt(((xx - W / 2) / (W * 0.66)) ** 2 + ((yy - H * 0.46) / (H * 0.66)) ** 2)
    va = (np.clip((nd - 0.75) / 0.5, 0, 1) * 120).astype(np.uint8)
    varr = np.zeros((H, W, 4), np.uint8)
    varr[..., 3] = va
    img.alpha_composite(Image.fromarray(varr))
    rgb = np.asarray(img.convert("RGB")).astype(np.int16)
    rgb += np.random.default_rng(9).normal(0, 2.0, rgb.shape).astype(np.int16)
    return Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8))


def draw_hud(img):
    d = ImageDraw.Draw(img)

    def s(v):
        return v * SS

    def panel(x0, y0, x1, y1, stroke=AMBER + (140,)):
        d.rounded_rectangle([s(x0), s(y0), s(x1), s(y1)], radius=s(4),
                            fill=(13, 15, 20, 184), outline=stroke, width=max(1, SS))

    def btn(x0, y0, x1, y1, label, lsize=9):
        d.rounded_rectangle([s(x0), s(y0), s(x1), s(y1)], radius=s((y1 - y0) / 2),
                            fill=(20, 23, 29, 199), outline=AMBER + (128,), width=max(1, SS))
        d.text((s((x0 + x1) / 2), s((y0 + y1) / 2 + 0.5)), label, font=fnt(lsize, True), fill=PAPER, anchor="mm")

    def circle_btn(cx, cy, r, letter, sub=None, hot=False):
        d.ellipse([s(cx - r), s(cy - r), s(cx + r), s(cy + r)],
                  fill=(26, 21, 16, 217) if hot else (20, 23, 29, 199),
                  outline=AMBER + (190 if hot else 128,), width=max(1, int(SS * (1.4 if hot else 1.1))))
        col = AMBER if hot else PAPER
        d.text((s(cx), s(cy - (3 if sub else 0))), letter, font=fnt(11, True), fill=col, anchor="mm")
        if sub:
            d.text((s(cx), s(cy + 9)), sub, font=fnt(6.5), fill=AMBER if hot else GREY, anchor="mm")

    def star(cx, cy, r, lit):
        pts = []
        for i in range(10):
            ang = -math.pi / 2 + i * math.pi / 5
            rr = r if i % 2 == 0 else r * 0.45
            pts.append((s(cx + rr * math.cos(ang)), s(cy + rr * math.sin(ang))))
        d.polygon(pts, fill=AMBER if lit else (58, 61, 69))

    panel(14, 16, 164, 68)
    for i, (name, frac, col) in enumerate([("HP", 0.78, CRIMSON), ("ARM", 0.46, (143, 163, 184)), ("STA", 0.86, TEAL)]):
        y = 23 + i * 14
        d.text((s(22), s(y + 3.5)), name, font=fnt(7), fill=AMBER, anchor="lm")
        d.rounded_rectangle([s(44), s(y), s(156), s(y + 7)], radius=s(2), fill=(0, 0, 0, 128))
        d.rounded_rectangle([s(44), s(y), s(44 + 112 * frac), s(y + 7)], radius=s(2), fill=col)
    panel(421, 16, 571, 68)
    d.text((s(563), s(31)), "$4,920", font=fnt(11, True), fill=PAPER, anchor="rm")
    for i in range(5):
        star(497 + i * 16, 47, 7, i < 3)
    d.text((s(429), s(60)), "KILN ROW · 23:40 · RAIN", font=fnt(7), fill=AMBER, anchor="lm")
    btn(421, 76, 467, 102, "PHONE", 8)
    btn(473, 76, 515, 102, "MAP", 8)
    btn(521, 76, 571, 102, "II", 9)
    d.ellipse([s(30), s(120), s(142), s(232)], fill=(13, 15, 20, 204), outline=AMBER + (140,), width=max(1, int(SS * 1.4)))
    for x0, y0, x1, y1 in [(40, 150, 132, 150), (46, 176, 126, 176), (52, 202, 120, 202),
                           (66, 128, 66, 224), (106, 128, 106, 224)]:
        d.line([s(x0), s(y0), s(x1), s(y1)], fill=(58, 70, 88), width=s(2))
    d.polygon([(s(86), s(166)), (s(93), s(186)), (s(86), s(181)), (s(79), s(186))], fill=PAPER)
    d.ellipse([s(108), s(146), s(116), s(154)], fill=TEAL)
    d.ellipse([s(56), s(192), s(64), s(200)], fill=CRIMSON)
    d.text((s(86), s(112)), "N", font=fnt(8), fill=AMBER, anchor="mm")
    panel(20, 244, 196, 284)
    d.text((s(30), s(258)), "OBJECTIVE · M01 LAST CALL", font=fnt(7.5), fill=AMBER, anchor="lm")
    d.text((s(30), s(274)), "Get to Ruth's before closing", font=fnt(9), fill=PAPER, anchor="lm")
    panel(120, 112, 465, 136, stroke=TEAL + (128,))
    d.text((s(292), s(124)), "NEWS · Static-88: Rain holds over Kiln Row through the witching hour.",
           font=fnt(8.5), fill=TEAL, anchor="mm")
    d.ellipse([s(30), s(1054), s(162), s(1186)], fill=(16, 19, 26, 140), outline=AMBER + (102,), width=max(1, int(SS * 1.4)))
    d.ellipse([s(86), s(1072), s(138), s(1124)], fill=(27, 32, 41, 230), outline=AMBER + (153,), width=max(1, int(SS * 1.4)))
    btn(20, 1010, 54, 1044, "RUN", 7.5)
    btn(20, 962, 54, 996, "CRCH", 6.5)
    btn(150, 1000, 182, 1032, "JMP", 7.5)
    circle_btn(487, 1064, 23, "Y", "HEAVY")
    circle_btn(443, 1102, 23, "B", "DODGE")
    circle_btn(529, 1102, 23, "X", "PUNCH")
    circle_btn(487, 1146, 26, "A", "KICK", hot=True)
    btn(536, 1006, 574, 1032, "BLK", 7.5)
    btn(536, 970, 574, 996, "LOCK", 7)
    btn(536, 934, 574, 960, "STY", 7.5)
    d.text((s(555), s(926)), "BRAWLER", font=fnt(7), fill=GREY, anchor="mm")
    btn(392, 1052, 432, 1080, "CAR", 8)
    d.rectangle([0, s(1230), W, H], fill=(0, 0, 0, 200))
    d.text((s(292), s(1243)), "LEVERAGE — GAMEPLAY CONCEPT RENDER (ART DIRECTION TARGET)",
           font=fnt(10, True), fill=AMBER, anchor="mm")
    d.text((s(292), s(1257)), "Hand-built from docs/ART_DIRECTION.md + docs/CONTROLS.md — NOT engine output (headless sandbox, see K-08).",
           font=fnt(7.5), fill=GREY, anchor="mm")
    return img


def main():
    img = build_world()
    img = wet_reflection(img)
    img = rain_and_grade(img)
    img = draw_hud(img)
    img.save(OUT)
    print("wrote", OUT, img.size)


if __name__ == "__main__":
    main()
