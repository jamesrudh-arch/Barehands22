"""forge_world_tex — generates all world/material textures for LEVERAGE.

Output: assets/textures/world/*.png  (albedo, plus *_n.png normal, *_r.png
roughness where the material warrants them). All power-of-two, tileable.

Art direction: CINDER NOIR — wet charcoal streets, sodium-amber light, rust and
ash, restrained neon. See docs/ART_DIRECTION.md.
"""
import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from forge_lib import (fbm, value_noise, white_noise, ridged, brick_pattern,
                       panel_lines, tiles_pattern, normal_from_height,
                       ao_from_height, rough_from_height, to_rgb, colorize,
                       save_png, save_rgba_png, radial_mask, ellipse_mask, RNG_SEED)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "world")
os.makedirs(OUT, exist_ok=True)

# Cinder Noir palette
COL = {
    "charcoal": (23, 20, 26),
    "ash": (138, 131, 120),
    "ash_dark": (74, 70, 66),
    "concrete": (110, 106, 100),
    "concrete_dark": (66, 63, 60),
    "rust": (180, 85, 45),
    "rust_dark": (96, 48, 28),
    "brick_red": (122, 64, 52),
    "brick_dark": (70, 38, 32),
    "brick_grey": (96, 90, 86),
    "amber": (255, 179, 71),
    "magenta": (255, 46, 136),
    "cyan": (46, 230, 255),
    "tar": (34, 32, 36),
    "sand": (146, 126, 96),
    "steel": (128, 132, 140),
}


def rng(seed=RNG_SEED):
    return np.random.default_rng(seed)


def save(name, arr):
    save_png(os.path.join(OUT, name), arr)
    print("  wrote", name, arr.shape)


def save_a(name, arr):
    save_rgba_png(os.path.join(OUT, name), arr)
    print("  wrote", name, arr.shape)


def bake(name, height, dark, light, contrast=1.0, nrm=2.0, rough=(0.85, 0.25),
         stain=None, size=None):
    """Standard material bake: albedo + normal + roughness."""
    albedo = colorize(height, dark, light, contrast)
    if stain is not None:
        albedo *= stain[..., None]
    save(name + ".png", np.clip(albedo, 0, 255).astype(np.uint8))
    save(name + "_n.png", (normal_from_height(height, nrm) * 255).astype(np.uint8))
    if rough:
        r = rough_from_height(height, rough[0], rough[1])
        save(name + "_r.png", to_rgb(r, size))


# ============================================================ asphalt ======
def asphalt():
    S = 512
    r = rng(101)
    base = fbm(S, 6, 8, 0.55, r)
    grain = white_noise(S, r, 0.25)
    h = np.clip(base * 0.7 + grain, 0, 1)
    cracks = ridged(S, 4, 3, rng(102))
    crack_mask = (cracks > 0.93).astype(float) * 0.6
    h = np.clip(h - crack_mask, 0, 1)
    patches = fbm(S, 2, 2, 0.5, rng(103))
    stain = 0.85 + 0.3 * patches
    bake("asphalt", h, (26, 25, 28), (78, 76, 80), 1.15, 1.6, (0.92, 0.12), stain, S)


def asphalt_wet_sheen():
    """Smooth dark wet asphalt variant (rain state) — lower roughness."""
    S = 512
    r = rng(101)  # same seed => same layout, reads as 'the same road, wet'
    base = fbm(S, 6, 8, 0.55, r)
    grain = white_noise(S, r, 0.10)
    h = np.clip(base * 0.4 + grain + 0.35, 0, 1)
    bake("asphalt_wet", h, (18, 18, 22), (52, 52, 60), 0.8, 0.8, (0.15, 0.05), None, S)


# ============================================================ concrete =====
def concrete(variant="concrete", seed=201, dark=(66, 63, 60), light=(128, 124, 118),
               stains=True):
    S = 512
    r = rng(seed)
    base = fbm(S, 5, 6, 0.5, r)
    fine = white_noise(S, r, 0.18)
    h = np.clip(base * 0.6 + fine + 0.15, 0, 1)
    stain = None
    if stains:
        streak = fbm(S, 3, 3, 0.6, rng(seed + 1))
        stain = 0.8 + 0.35 * streak
    bake(variant, h, dark, light, 0.9, 1.2, (0.9, 0.15), stain, S)


# ============================================================== bricks ======
def brick(name, rows, dark, light, seed, variance=0.18):
    S = 512
    r = rng(seed)
    pat = brick_pattern(S, rows, mortar=0.09, jitter=0.05, rng=r)
    n = fbm(S, 5, 12, 0.5, rng(seed + 7))
    coarse = fbm(S, 3, 3, 0.5, rng(seed + 8))
    # per-brick value noise (lattice aligned to the brick rows)
    per_brick = value_noise(S, rows * 2, rng(seed + 9))
    h = np.clip(pat * (0.62 + 0.38 * n) + (per_brick - 0.5) * variance * 2.2, 0, 1)
    h = np.clip(h - (1 - pat) * 0.55, 0, 1)  # deep mortar recess
    ao = ao_from_height(h, 2, 0.55)
    stain = (0.8 + 0.35 * coarse) * (0.55 + 0.45 * ao)
    bake(name, h, dark, light, 1.1, 2.6, (0.88, 0.14), stain, S)


# =============================================================== metals ====
def corrugated():
    S = 512
    r = rng(301)
    y = np.linspace(0, 1, S)
    ribs = (np.sin(y[:, None] * np.pi * 2 * 16) * 0.5 + 0.5)
    n = fbm(S, 4, 24, 0.5, r)
    rust = fbm(S, 4, 4, 0.6, rng(302))
    rust_mask = np.clip((rust - 0.55) * 4, 0, 1)
    h = np.clip(ribs * 0.7 + n * 0.25 - rust_mask * 0.3, 0, 1)
    base = colorize(h, (58, 60, 66), (150, 154, 162), 1.0)
    rust_col = colorize(rust, (96, 48, 28), (180, 85, 45), 1.2)
    albedo = base * (1 - rust_mask[..., None]) + rust_col * rust_mask[..., None]
    save("metal_corrugated.png", np.clip(albedo, 0, 255).astype(np.uint8))
    save("metal_corrugated_n.png", (normal_from_height(h, 2.4) * 255).astype(np.uint8))
    rough = np.clip(0.35 + rust_mask * 0.55 + (n - 0.5) * 0.1, 0, 1)
    save("metal_corrugated_r.png", to_rgb(rough, S))


def metal_panel():
    S = 512
    r = rng(311)
    h = panel_lines(S, 4, 4, width=0.008, depth=0.3)
    n = fbm(S, 4, 32, 0.5, r)
    h = np.clip(h * 0.8 + n * 0.3, 0, 1)
    scratch = ridged(S, 2, 8, rng(312))
    h = np.clip(h - (scratch > 0.96).astype(float) * 0.25, 0, 1)
    bake("metal_panel", h, (72, 74, 80), (148, 152, 160), 1.0, 1.8, (0.4, 0.2), None, S)


def metal_rusted():
    S = 512
    r = rng(321)
    n = fbm(S, 5, 8, 0.55, r)
    pits = ridged(S, 4, 6, rng(322))
    h = np.clip(n * 0.6 + (1 - pits) * 0.5, 0, 1)
    bake("metal_rusted", h, (74, 40, 24), (168, 92, 48), 1.2, 2.0, (0.95, 0.1), None, S)


# ================================================================ wood ======
def wood_planks():
    S = 512
    r = rng(401)
    planks = panel_lines(S, 1, 6, width=0.012, depth=0.25)
    grain = fbm(S, 5, 40, 0.65, r)
    streak = value_noise(S, 90, rng(402))
    h = np.clip(planks * 0.6 + grain * 0.3 + streak * 0.15, 0, 1)
    per_plank = value_noise(S, 6, rng(403))
    albedo = colorize(h, (58, 42, 30), (122, 92, 60), 1.0)
    tint = 0.8 + 0.4 * per_plank[..., None]
    save("wood_planks.png", np.clip(albedo * tint, 0, 255).astype(np.uint8))
    save("wood_planks_n.png", (normal_from_height(h, 2.0) * 255).astype(np.uint8))
    save("wood_planks_r.png", to_rgb(rough_from_height(h, 0.85, 0.1), S))


# =============================================================== floors ====
def tile_floor():
    S = 512
    h = tiles_pattern(S, 4, 4, mortar=0.1)
    n = fbm(S, 4, 24, 0.5, rng(501))
    h = np.clip(h * 0.8 + n * 0.25, 0, 1)
    bake("tile_floor", h, (72, 70, 68), (158, 154, 148), 0.9, 1.6, (0.25, 0.15), None, S)


def carpet():
    S = 256
    n = fbm(S, 5, 32, 0.5, rng(511))
    h = np.clip(n, 0, 1)
    bake("carpet", h, (48, 26, 30), (92, 56, 58), 0.7, 1.0, (0.98, 0.02), None, S)


def sidewalk():
    S = 512
    h = panel_lines(S, 2, 2, width=0.015, depth=0.2)
    n = fbm(S, 5, 10, 0.5, rng(601))
    fine = white_noise(S, rng(602), 0.15)
    h = np.clip(h * 0.7 + n * 0.35 + fine, 0, 1)
    stain = 0.85 + 0.3 * fbm(S, 2, 2, 0.5, rng(603))
    bake("sidewalk", h, (84, 82, 78), (142, 140, 134), 0.9, 1.8, (0.9, 0.12), stain, S)


def gravel():
    S = 512
    r = rng(701)
    n = fbm(S, 6, 24, 0.5, r)
    peb = white_noise(S, r, 0.4)
    h = np.clip(n * 0.6 + peb, 0, 1)
    stain = 0.8 + 0.4 * fbm(S, 2, 2, 0.5, rng(702))
    bake("gravel", h, (74, 68, 60), (146, 126, 96), 1.1, 2.2, (0.95, 0.1), stain, S)


def roof_tar():
    S = 256
    n = fbm(S, 5, 6, 0.5, rng(711))
    h = np.clip(n * 0.8 + 0.2, 0, 1)
    bake("roof_tar", h, (28, 27, 30), (64, 62, 64), 0.8, 1.0, (0.95, 0.1), None, S)


# ============================================================== fabrics ====
def fabric(name, seed, weave=64):
    S = 256
    r = rng(seed)
    y, x = np.mgrid[0:S, 0:S]
    w = (np.sin(x / S * np.pi * 2 * weave) * np.sin(y / S * np.pi * 2 * weave)) * 0.5 + 0.5
    n = fbm(S, 3, weave // 4, 0.5, r)
    fuzz = white_noise(S, r, 0.12)
    h = np.clip(w * 0.4 + n * 0.4 + fuzz + 0.2, 0, 1)
    save(name + ".png", to_rgb(h * 0.5 + 0.35, S))  # mid-grey, tinted per material
    save(name + "_n.png", (normal_from_height(h, 0.8) * 255).astype(np.uint8))
    print("  wrote", name)


# =========================================================== road marks ====
def road_marks():
    """Atlas 1024x1024, quadrants: 00 center dashes, 01 crosswalk,
    10 stop line + arrows, 11 lane edge solid. White on transparent —
    laid as decal meshes over asphalt."""
    S = 1024
    H = S // 2
    img = np.zeros((S, S, 4), dtype=np.uint8)

    def quad(qx, qy):
        return img[qy * H:(qy + 1) * H, qx * H:(qx + 1) * H]

    # dashes
    q = quad(0, 0)
    for i in range(4):
        y0 = int(i * H / 4 + H / 16)
        q[y0:y0 + int(H / 8), int(H * 0.46):int(H * 0.54), :] = (226, 222, 208, 255)
    # crosswalk
    q = quad(1, 0)
    for i in range(6):
        x0 = int(i * H / 6 + H / 24)
        q[int(H * 0.1):int(H * 0.9), x0:x0 + int(H / 12), :] = (226, 222, 208, 255)
    # stop line + arrow
    q = quad(0, 1)
    q[int(H * 0.12):int(H * 0.2), int(H * 0.1):int(H * 0.9), :] = (226, 222, 208, 255)
    # straight arrow
    cx = H // 2
    q[int(H * 0.35):int(H * 0.8), cx - 8:cx + 8, :] = (226, 222, 208, 255)
    for sgn in (-1, 1):
        for k in range(40):
            yy = int(H * 0.35) + k
            w = int(28 - k * 0.7)
            q[yy, max(0, cx - w):cx + w, :] = (226, 222, 208, 255)
    # edge line
    q = quad(1, 1)
    q[:, int(H * 0.45):int(H * 0.55), :] = (226, 222, 208, 255)
    save_a("road_marks.png", img)


# ===================================================== window emissive ======
def windows_atlas():
    """8x4 atlas of window quads; interior warm glow variants + dark.
    Emissive mask for building facades at night."""
    S = 1024
    cw, ch = S // 8, S // 4
    r = rng(801)
    img = np.zeros((S, S, 3), dtype=np.uint8)
    for j in range(4):
        for i in range(8):
            cell = np.zeros((ch, cw, 3))
            kind = r.integers(0, 5)
            gy, gx = np.mgrid[0:ch, 0:cw]
            y = gy / ch
            x = gx / cw
            if kind == 0:  # dark
                cell[:] = (6, 7, 10)
            elif kind == 1:  # warm lamp
                g = np.clip(1.2 - np.abs(y - 0.6) * 1.6, 0, 1) * np.clip(1.2 - np.abs(x - 0.5) * 1.4, 0, 1)
                cell = (np.stack([g * 255, g * 196, g * 120], -1))
            elif kind == 2:  # cool TV flicker
                g = np.clip(1.1 - np.abs(y - 0.5) * 1.8, 0, 1)
                cell = np.stack([g * 90, g * 140, g * 210], -1)
            elif kind == 3:  # silhouette (someone home)
                g = np.ones((ch, cw)) * 0.9
                head = np.clip(1.0 - np.sqrt(((x - 0.5) / 0.12) ** 2 + ((y - 0.35) / 0.09) ** 2), 0, 1)
                body = np.clip((y - 0.45) * 2.2, 0, 1) * (np.abs(x - 0.5) < 0.22)
                mask = np.clip(head + body, 0, 1)
                cell = np.stack([(g * (1 - mask * 0.92)) * 240, (g * (1 - mask * 0.92)) * 180,
                                 (g * (1 - mask * 0.92)) * 110], -1)
            else:  # blinds half-closed
                g = np.clip(1.2 - np.abs(y - 0.35) * 2.2, 0, 1)
                lines = (np.sin(y * np.pi * 2 * 14) > 0.4).astype(float) * 0.5
                g *= (1 - lines)
                cell = np.stack([g * 250, g * 200, g * 130], -1)
            img[j * ch:(j + 1) * ch, i * cw:(i + 1) * cw] = np.clip(cell, 0, 255).astype(np.uint8)
    save_png(os.path.join(OUT, "windows_atlas.png"), img)
    print("  wrote windows_atlas.png")


# ============================================================== signage =====
def _draw_text(img, xy, text, scale=2, color=(255, 255, 255), font=None):
    from PIL import Image, ImageDraw
    pil = Image.fromarray(img)
    d = ImageDraw.Draw(pil)
    if font is None:
        fpath = os.path.join(ROOT, "assets", "fonts", "DejaVuSans-Bold.ttf")
        from PIL import ImageFont
        font = ImageFont.truetype(fpath, 14 * scale)
    d.text(xy, text, fill=tuple(int(c) for c in color), font=font)
    return np.array(pil)


def signs_atlas():
    """16 cells (4x4) of 512px signage: shopfront boards + neon words.
    In-world brands of Cinder City. Alpha channel for neon cutouts."""
    from PIL import Image, ImageDraw, ImageFont
    S = 2048
    C = S // 4
    fdir = os.path.join(ROOT, "assets", "fonts")
    fonts = {
        "bold": ImageFont.truetype(os.path.join(fdir, "DejaVuSans-Bold.ttf"), 64),
        "reg": ImageFont.truetype(os.path.join(fdir, "DejaVuSans.ttf"), 48),
        "mono": ImageFont.truetype(os.path.join(fdir, "DejaVuSansMono-Bold.ttf"), 52),
        "big": ImageFont.truetype(os.path.join(fdir, "DejaVuSans-Bold.ttf"), 96),
    }
    img = np.zeros((S, S, 4), dtype=np.uint8)
    signs = [
        # (text, sub, bg, fg, glow, font)
        ("NOIR LOUNGE", "cocktails · vinyl", (18, 10, 24), COL["magenta"], True, "bold"),
        ("HALCYON", "DYNAMICS GROUP", (10, 14, 22), (140, 200, 255), True, "bold"),
        ("ASHFALL DOCKS", "berth 7 · cargo", (24, 20, 16), COL["amber"], False, "mono"),
        ("KILN ROW MARKET", "fresh · daily", (30, 16, 14), (240, 210, 160), False, "bold"),
        ("THE SLAG HEAP", "bar & grill", (20, 14, 12), (255, 120, 60), True, "bold"),
        ("CINDER MOTORS", "sales · repairs", (14, 16, 20), (120, 220, 255), False, "mono"),
        ("PAWN · 24H", "cash for gold", (22, 18, 10), COL["amber"], True, "big"),
        ("VOSS & SONS", "haulage est. 1961", (16, 14, 18), (200, 190, 180), False, "reg"),
        ("CLUB BRAVADO", "open late", (24, 8, 20), COL["cyan"], True, "bold"),
        ("DR. M. OKONKWO", "clinic · walk-in", (12, 20, 18), (140, 255, 200), False, "reg"),
        ("SLAGWORKS YARD 4", "authorized only", (20, 16, 10), (255, 170, 40), False, "mono"),
        ("LUCKY SEVEN", "casino", (26, 10, 14), (255, 215, 90), True, "big"),
        ("MAMA RUTH'S", "soul food", (28, 14, 10), (255, 150, 90), False, "bold"),
        ("CROWN HEIGHTS", "private road", (14, 14, 18), (210, 210, 225), False, "reg"),
        ("GUNSMITH", "licensed firearms", (18, 16, 14), (230, 90, 60), False, "mono"),
        ("RADIO STATIC 88", "the sound of cinder", (10, 10, 14), COL["magenta"], True, "bold"),
    ]
    pil = Image.fromarray(img, "RGBA")
    d = ImageDraw.Draw(pil)
    for idx, (text, sub, bg, fg, glow, fk) in enumerate(signs):
        j, i = idx // 4, idx % 4
        x0, y0 = i * C, j * C
        # board background
        d.rectangle([x0 + 8, y0 + 8, x0 + C - 8, y0 + C - 8], fill=tuple(bg) + (255,),
                    outline=(0, 0, 0, 255), width=4)
        # auto-fit: shrink font until the text fits the cell with margins
        from PIL import ImageFont as _IF
        f = fonts[fk]
        for size in range(f.size, 14, -4):
            f = f.font_variant(size=size)
            bbox = d.textbbox((0, 0), text, font=f)
            tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
            if tw <= C - 72:
                break
        tx, ty = x0 + (C - tw) // 2, y0 + C // 2 - th
        if glow:
            for r_ in (10, 6, 3):
                gc = tuple(int(c * 0.5) for c in fg) + (60,)
                d.text((tx, ty), text, font=f, fill=gc, stroke_width=r_, stroke_fill=gc)
        d.text((tx, ty), text, font=f, fill=tuple(fg) + (255,))
        f2 = fonts["reg"]
        bbox2 = d.textbbox((0, 0), sub, font=f2)
        sw = bbox2[2] - bbox2[0]
        d.text((x0 + (C - sw) // 2, y0 + C // 2 + th // 2 + 24), sub, font=f2,
               fill=tuple(int(c * 0.8) for c in fg) + (230,))
    img = np.array(pil)
    save_a("signs_atlas.png", img)


def posters_atlas():
    """4x4 atlas of 512px posters/graffiti with alpha — environmental story."""
    from PIL import Image, ImageDraw, ImageFont
    S = 2048
    C = S // 4
    fdir = os.path.join(ROOT, "assets", "fonts")
    fb = ImageFont.truetype(os.path.join(fdir, "DejaVuSans-Bold.ttf"), 56)
    fr = ImageFont.truetype(os.path.join(fdir, "DejaVuSans.ttf"), 34)
    img = np.zeros((S, S, 4), dtype=np.uint8)
    pil = Image.fromarray(img, "RGBA")
    d = ImageDraw.Draw(pil)
    posters = [
        ("FIND HIM", "MISSING: MARCUS VANE, 28", (40, 30, 24), (230, 200, 150)),
        ("HALCYON IS\nLISTENING", "report dissent · earn credit", (16, 20, 30), (130, 190, 255)),
        ("PAY YOUR\nDEBTS", "the crow remembers", (30, 16, 16), (240, 120, 80)),
        ("NOIR LOUNGE", "FRIDAY · ROZ MAKU LIVE", (20, 10, 26), (255, 70, 150)),
        ("KILN ROW\nUNITY FIGHT", "SAT · YARD 4 · PURSE 500", (26, 20, 14), (255, 180, 60)),
        ("KEEP CINDER\nCLEAN", "fine 250cr for litter", (18, 24, 20), (160, 220, 180)),
        ("STATIC 88", "CALL IN: 555-0188", (12, 12, 18), (255, 60, 200)),
        ("VOSS HAULAGE\nIS HIRING", "ask for the foreman", (22, 20, 24), (220, 210, 200)),
    ]
    for idx, (title, sub, bg, fg) in enumerate(posters):
        j, i = idx // 4, idx % 4
        x0, y0 = i * C, j * C
        d.rectangle([x0 + 16, y0 + 16, x0 + C - 16, y0 + C - 16], fill=tuple(bg) + (245,))
        # torn corner
        d.polygon([(x0 + C - 16, y0 + 16), (x0 + C - 90, y0 + 16), (x0 + C - 16, y0 + 90)],
                  fill=(0, 0, 0, 0))
        lines = title.split("\n")
        yy = y0 + 90
        for ln in lines:
            d.text((x0 + 48, yy), ln, font=fb, fill=tuple(fg) + (255,))
            yy += 70
        d.text((x0 + 48, y0 + C - 130), sub, font=fr, fill=tuple(int(c * 0.75) for c in fg) + (255,))
    # graffiti tags (cells 8..15): stylized strokes
    r = np.random.default_rng(901)
    for idx in range(8, 16):
        j, i = idx // 4, idx % 4
        x0, y0 = i * C, j * C
        col = [COL["magenta"], COL["cyan"], COL["amber"], (240, 240, 240)][idx % 4]
        pts = []
        px, py = x0 + 80, y0 + C // 2
        for k in range(9):
            pts.append((px, py))
            px += C / 10 + r.normal(0, 8)
            py += r.normal(0, C / 7)
            py = min(max(py, y0 + 60), y0 + C - 60)
        d.line(pts, fill=tuple(col) + (230,), width=26, joint="curve")
        d.line(pts, fill=(255, 255, 255, 90), width=8, joint="curve")
    img = np.array(pil)
    save_a("posters_atlas.png", img)


# ============================================================== decals ======
def decals():
    S = 512
    # puddle
    r = rng(1001)
    shape = fbm(S, 4, 3, 0.6, r)
    mask = np.clip((shape - 0.45) * 3.0, 0, 1) * radial_mask(S, 0.6)
    rgba = np.zeros((S, S, 4), dtype=np.uint8)
    rgba[..., 0:3] = 12
    rgba[..., 3] = (mask * 200).astype(np.uint8)
    save_a("decal_puddle.png", rgba)
    # scorch
    shape = fbm(S, 4, 5, 0.6, rng(1002))
    mask = np.clip((shape - 0.5) * 3.0, 0, 1) * radial_mask(S, 1.2)
    rgba = np.zeros((S, S, 4), dtype=np.uint8)
    rgba[..., 0:3] = 16
    rgba[..., 3] = (mask * 220).astype(np.uint8)
    save_a("decal_scorch.png", rgba)
    # blood
    shape = fbm(S, 4, 6, 0.6, rng(1003))
    mask = np.clip((shape - 0.52) * 4.0, 0, 1) * radial_mask(S, 1.0)
    splats = white_noise(S, rng(1004))
    mask = np.clip(mask + (splats > 0.997).astype(float) * radial_mask(S, 2.0), 0, 1)
    rgba = np.zeros((S, S, 4), dtype=np.uint8)
    rgba[..., 0] = 92
    rgba[..., 1] = 14
    rgba[..., 2] = 18
    rgba[..., 3] = (mask * 235).astype(np.uint8)
    save_a("decal_blood.png", rgba)
    # oil stain
    shape = fbm(S, 4, 4, 0.6, rng(1005))
    mask = np.clip((shape - 0.5) * 3.5, 0, 1) * radial_mask(S, 1.1)
    rgba = np.zeros((S, S, 4), dtype=np.uint8)
    rgba[..., 0:3] = (10, 10, 14)
    rgba[..., 3] = (mask * 180).astype(np.uint8)
    save_a("decal_oil.png", rgba)
    # manhole cover (opaque round)
    y, x = np.mgrid[0:S, 0:S] / S
    d = np.sqrt((x - 0.5) ** 2 + (y - 0.5) ** 2)
    disc = np.clip((0.42 - d) * 40, 0, 1)
    n = fbm(S, 5, 24, 0.5, rng(1006))
    ribs = np.clip(np.sin(np.arctan2(y - 0.5, x - 0.5) * 24) * 0.5 + 0.5, 0, 1) * (d < 0.35)
    h = np.clip(disc * (0.6 + 0.25 * n + 0.25 * ribs), 0, 1)
    albedo = colorize(h, (40, 42, 46), (96, 100, 106), 1.0)
    alpha = (disc * 255).astype(np.uint8)
    rgba = np.zeros((S, S, 4), dtype=np.uint8)
    rgba[..., :3] = np.clip(albedo, 0, 255).astype(np.uint8)
    rgba[..., 3] = alpha
    save_a("decal_manhole.png", rgba)


# ============================================================ particles ====
def particles():
    S = 128
    # smoke puff
    r = rng(1101)
    n = fbm(S, 5, 4, 0.6, r)
    mask = np.clip((n - 0.35) * 2.2, 0, 1) * radial_mask(S, 1.4)
    rgba = np.zeros((S, S, 4), dtype=np.uint8)
    rgba[..., 0:3] = 200
    rgba[..., 3] = (mask * 140).astype(np.uint8)
    save_a("particle_smoke.png", rgba)
    # spark
    rgba = np.zeros((S, S, 4), dtype=np.uint8)
    g = radial_mask(S, 3.0)
    rgba[..., 0] = 255
    rgba[..., 1] = (g * 220).astype(np.uint8)
    rgba[..., 2] = (g ** 2 * 140).astype(np.uint8)
    rgba[..., 3] = (g * 255).astype(np.uint8)
    save_a("particle_spark.png", rgba)
    # rain streak (tall thin)
    S2 = 64
    rgba = np.zeros((S2, S2, 4), dtype=np.uint8)
    y = np.linspace(0, 1, S2)
    grad = np.clip(1 - np.abs(y - 0.5) * 2.4, 0, 1)
    xband = np.clip(1 - np.abs(np.arange(S2) / S2 - 0.5) * 14, 0, 1)
    a = (grad[:, None] * xband[None, :] * 160)
    rgba[..., 0:3] = (170, 190, 220)
    rgba[..., 3] = a.astype(np.uint8)
    save_a("particle_rain.png", rgba)
    # debris chunk
    rgba = np.zeros((S, S, 4), dtype=np.uint8)
    n = fbm(S, 3, 6, 0.5, rng(1102))
    mask = np.clip((n - 0.4) * 3, 0, 1) * radial_mask(S, 1.6)
    rgba[..., 0:3] = 130
    rgba[..., 3] = (mask * 255).astype(np.uint8)
    save_a("particle_debris.png", rgba)
    # muzzle flash
    rgba = np.zeros((S, S, 4), dtype=np.uint8)
    g = radial_mask(S, 2.2)
    star = np.clip(np.abs(np.sin(np.arctan2(np.mgrid[0:S, 0:S][0] / S - .5, np.mgrid[0:S, 0:S][1] / S - .5) * 2)) ** 8, 0, 1) * radial_mask(S, 0.8)
    m = np.clip(g + star * 0.8, 0, 1)
    rgba[..., 0] = 255
    rgba[..., 1] = (m * 235).astype(np.uint8)
    rgba[..., 2] = (m ** 2 * 160).astype(np.uint8)
    rgba[..., 3] = (m * 255).astype(np.uint8)
    save_a("particle_muzzle.png", rgba)
    # blood droplet
    rgba = np.zeros((S, S, 4), dtype=np.uint8)
    g = radial_mask(S, 2.5)
    rgba[..., 0] = (g * 150).astype(np.uint8)
    rgba[..., 1] = (g * 18).astype(np.uint8)
    rgba[..., 2] = (g * 22).astype(np.uint8)
    rgba[..., 3] = (np.clip(g * 1.4, 0, 1) * 255).astype(np.uint8)
    save_a("particle_blood.png", rgba)


# ============================================================== glass ======
def glass():
    S = 256
    n = fbm(S, 3, 8, 0.5, rng(1201))
    h = np.clip(0.5 + n * 0.15, 0, 1)
    img = colorize(h, (14, 18, 24), (40, 52, 64), 0.6)
    save("glass_dark.png", np.clip(img, 0, 255).astype(np.uint8))


# ================================================================= water ====
def water():
    S = 512
    n = fbm(S, 5, 6, 0.55, rng(1301))
    h = np.clip(n, 0, 1)
    save("water_n.png", (normal_from_height(h, 1.2) * 255).astype(np.uint8))
    img = colorize(h, (10, 16, 22), (30, 44, 56), 0.8)
    save("water.png", np.clip(img, 0, 255).astype(np.uint8))


def main():
    print("== LEVERAGE world texture forge ==")
    asphalt()
    asphalt_wet_sheen()
    concrete("concrete", 201, COL["concrete_dark"], COL["concrete"])
    concrete("concrete_stained", 211, (56, 52, 50), (104, 98, 92))
    concrete("stucco", 221, (128, 112, 92), (196, 178, 148), stains=True)
    brick("brick_red", 8, COL["brick_dark"], COL["brick_red"], 231)
    brick("brick_grey", 9, (58, 54, 52), COL["brick_grey"], 241)
    brick("brick_dark", 7, (38, 30, 30), (84, 56, 48), 251)
    corrugated()
    metal_panel()
    metal_rusted()
    wood_planks()
    tile_floor()
    carpet()
    sidewalk()
    gravel()
    roof_tar()
    fabric("fabric_canvas", 901, 48)
    fabric("fabric_denim", 902, 96)
    fabric("fabric_leather", 903, 24)
    fabric("fabric_wool", 904, 32)
    road_marks()
    windows_atlas()
    signs_atlas()
    posters_atlas()
    decals()
    particles()
    glass()
    water()
    print("done:", len(os.listdir(OUT)), "files")


if __name__ == "__main__":
    main()


# ============================================================ facades ======
def facade(base_name, wall, seed, window_cols=4, window_rows=5, glassy=False,
           sill=True):
    """Albedo with window holes + emissive mask with lit/unlit variety."""
    S = 512
    r = rng(seed)
    src = os.path.join(OUT, wall + ".png")
    from PIL import Image
    wallimg = np.array(Image.open(src).convert("RGB").resize((S, S)))
    alb = wallimg.astype(float)
    emi = np.zeros((S, S, 3))
    cw, ch = S // window_cols, S // window_rows
    lit_kind = [[(255, 196, 120), (250, 210, 150)], [(90, 140, 210), (120, 170, 230)],
                [(240, 240, 235), (200, 200, 210)], [(0, 0, 0), (0, 0, 0)]]
    for j in range(window_rows):
        for i in range(window_cols):
            x0, y0 = i * cw + int(cw * 0.22), j * ch + int(ch * 0.2)
            x1, y1 = (i + 1) * cw - int(cw * 0.22), (j + 1) * ch - int(ch * 0.28)
            # glass
            g = 18 + int(r.random() * 20)
            alb[y0:y1, x0:x1] = (g, g + 4, g + 10)
            # frame
            fr = (max(0, wallimg[y0, x0][0] - 30),) * 3
            alb[y0 - 3:y0, x0:x1] = fr
            alb[y1:y1 + 3, x0:x1] = fr
            alb[y0:y1, x0 - 3:x0] = fr
            alb[y0:y1, x1:x1 + 3] = fr
            # emissive: some windows lit
            roll = r.random()
            kind = lit_kind[3] if roll < (0.55 if not glassy else 0.75) else lit_kind[int(r.integers(0, 3))]
            c = kind[int(r.integers(0, 2))]
            flick = 0.85 + r.random() * 0.15
            emi[y0:y1, x0:x1] = (np.array(c) * flick)
            if sill:
                alb[y1 + 3:y1 + 7, x0 - 3:x1 + 3] = (np.array(wallimg[y1 + 4, x0]) * 0.7)
    save(base_name + ".png", np.clip(alb, 0, 255).astype(np.uint8))
    save(base_name + "_e.png", np.clip(emi, 0, 255).astype(np.uint8))


def grass():
    S = 256
    n = fbm(S, 5, 24, 0.55, rng(1401))
    blades = white_noise(S, rng(1402), 0.5)
    h = np.clip(n * 0.6 + blades * 0.5, 0, 1)
    stain = 0.8 + 0.4 * fbm(S, 2, 2, 0.5, rng(1403))
    bake("grass", h, (34, 52, 26), (86, 108, 52), 1.0, 1.4, (0.95, 0.05), stain, S)


def facades():
    facade("facade_brick_red", "brick_red", 2001, 4, 5)
    facade("facade_brick_dark", "brick_dark", 2002, 4, 5)
    facade("facade_brick_grey", "brick_grey", 2003, 5, 6)
    facade("facade_concrete", "concrete", 2004, 5, 6)
    facade("facade_stucco", "stucco", 2005, 4, 5)
    facade("facade_glass", "glass_dark", 2006, 6, 8, glassy=True, sill=False)
    facade("facade_metal", "metal_panel", 2007, 4, 4, sill=False)
    facade("facade_corrugated", "metal_corrugated", 2008, 3, 3, sill=False)
    grass()
