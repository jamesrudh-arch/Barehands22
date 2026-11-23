"""forge_ui_tex — LEVERAGE branding, UI kit and character face bank.

Produces:
  assets/textures/ui/   icon, logo, studio splash, advisory, menu art,
                        hud/phone icons, 9-patch panels, crosshair, prompts
  assets/textures/faces/ 24 stylized face albedo variants (procedural)
All original.
"""
import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from forge_lib import (fbm, value_noise, white_noise, radial_mask, save_png,
                       save_rgba_png, normal_from_height, to_rgb, colorize)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
UI = os.path.join(ROOT, "assets", "textures", "ui")
FA = os.path.join(ROOT, "assets", "textures", "faces")
os.makedirs(UI, exist_ok=True)
os.makedirs(FA, exist_ok=True)

FONT_B = os.path.join(ROOT, "assets", "fonts", "DejaVuSans-Bold.ttf")
FONT_R = os.path.join(ROOT, "assets", "fonts", "DejaVuSans.ttf")

EMBER = (255, 122, 40)
AMBER = (255, 179, 71)
MAGENTA = (255, 46, 136)
CYAN = (46, 230, 255)
CHARCOAL = (17, 15, 20)
BONE = (232, 226, 214)


def P():
    from PIL import Image, ImageDraw, ImageFont
    return Image, ImageDraw, ImageFont


# ------------------------------------------------------------------ icon ---
def app_icon():
    Image, ImageDraw, ImageFont = P()
    S = 512
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # rounded charcoal plate
    d.rounded_rectangle([8, 8, S - 8, S - 8], radius=96, fill=(20, 17, 23, 255))
    # ember gradient sweep
    for y in range(S):
        t_ = y / S
        c = (int(20 + 60 * t_), int(14 + 18 * t_), int(18 + 8 * t_))
        d.line([(16, y), (S - 16, y)], fill=c + (255,))
    # crowbar silhouette ("leverage")
    d.line([(120, 380), (330, 150)], fill=(232, 226, 214, 255), width=34)
    d.arc([300, 96, 400, 196], 180, 340, fill=(232, 226, 214, 255), width=34)
    d.line([(96, 356), (150, 410)], fill=(232, 226, 214, 255), width=30)
    # ember spark
    d.ellipse([352, 320, 432, 400], fill=EMBER + (255,))
    d.ellipse([368, 336, 416, 384], fill=(255, 210, 120, 255))
    img.save(os.path.join(UI, "icon.png"))


def logo():
    Image, ImageDraw, ImageFont = P()
    W, H = 1600, 420
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONT_B, 210)
    # distressed wordmark
    d.text((40, 40), "LEVERAGE", font=f, fill=BONE + (255,))
    # ember underline slash
    d.polygon([(48, 320), (1560, 300), (1560, 336), (48, 362)], fill=EMBER + (255,))
    # crack through the E
    d.line([(620, 40), (600, 120), (640, 200), (610, 300)], fill=(20, 17, 23, 255), width=10)
    # tagline
    f2 = ImageFont.truetype(FONT_R, 44)
    d.text((52, 356), "EVERYONE HAS LEVERAGE ON YOU", font=f2, fill=(180, 168, 152, 255))
    img.save(os.path.join(UI, "logo_leverage.png"))


def studio_splash():
    """D'Youngs Games presentation card."""
    Image, ImageDraw, ImageFont = P()
    W, H = 1600, 900
    img = Image.new("RGB", (W, H), (8, 7, 10))
    d = ImageDraw.Draw(img)
    r = np.random.default_rng(7)
    # faint smoke
    n = fbm(256, 4, 4, 0.6, r)
    n = np.array(Image.fromarray((n * 255).astype(np.uint8)).resize((W, H))) / 255
    base = np.zeros((H, W, 3))
    base[..., 0] = n * 26
    base[..., 1] = n * 18
    base[..., 2] = n * 24
    arr = np.clip(base, 0, 255).astype(np.uint8)
    img = Image.fromarray(arr)
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONT_B, 96)
    f2 = ImageFont.truetype(FONT_R, 40)
    d.text((W // 2, 380), "D'YOUNGS GAMES", font=f, fill=(240, 232, 220), anchor="mm")
    d.text((W // 2, 470), "P R E S E N T S", font=f2, fill=(150, 140, 128), anchor="mm")
    # ember dots
    for i in range(40):
        x, y = r.integers(100, W - 100), r.integers(560, 820)
        d.ellipse([x, y, x + 3, y + 3], fill=(255, 140, 60))
    img.save(os.path.join(UI, "splash_dyoungs.png"))


def advisory():
    Image, ImageDraw, ImageFont = P()
    W, H = 1400, 700
    img = Image.new("RGB", (W, H), (10, 9, 12))
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONT_B, 54)
    f2 = ImageFont.truetype(FONT_R, 30)
    d.rectangle([60, 60, W - 60, H - 60], outline=(120, 110, 100), width=3)
    d.text((W // 2, 140), "CONTENT NOTICE", font=f, fill=(240, 220, 190), anchor="mm")
    lines = [
        "LEVERAGE depicts criminal violence, strong language,",
        "substance references and morally compromised characters.",
        "It is a work of fiction. Cinder City is not a real place.",
        "No real person, organisation or city is portrayed.",
    ]
    y = 240
    for ln in lines:
        d.text((W // 2, y), ln, font=f2, fill=(190, 180, 168), anchor="mm")
        y += 52
    d.text((W // 2, 560), "Play with consideration. Everyone has leverage on you.",
           font=f2, fill=(255, 140, 60), anchor="mm")
    img.save(os.path.join(UI, "advisory.png"))


def menu_art():
    """Main menu backdrop: rain-slick skyline, sodium haze, lone figure."""
    Image, ImageDraw, ImageFont = P()
    W, H = 1920, 1080
    r = np.random.default_rng(31)
    # sky gradient
    y = np.linspace(0, 1, H)[:, None]
    sky = np.zeros((H, W, 3))
    top = np.array([16, 14, 26])
    hor = np.array([120, 62, 34])
    sky[:] = (top[None, None, :] * (1 - y[..., None]) + hor[None, None, :] * (y[..., None] ** 2.2))
    # haze bands
    hz = fbm(256, 4, 3, 0.6, r)
    hz = np.array(Image.fromarray((hz * 255).astype(np.uint8)).resize((W, H // 4))) / 255
    hz = np.repeat(hz, 4, axis=0)
    sky += hz[..., None] * np.array([26, 12, 6])[None, None, :] * (y[..., None] ** 1.5)
    img = Image.fromarray(np.clip(sky, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    # skyline layers (3 depths)
    for depth, col in [(0, (26, 22, 30)), (1, (18, 15, 22)), (2, (10, 9, 14))]:
        x = -50
        base = 620 + depth * 90
        while x < W + 50:
            bw = r.integers(70, 190)
            bh = r.integers(120, 420) - depth * 60
            top_y = base - bh
            d.rectangle([x, top_y, x + bw, H], fill=col)
            # windows
            if depth < 2:
                for wy in range(top_y + 12, base - 10, 26):
                    for wx in range(x + 10, x + bw - 10, 20):
                        if r.random() < 0.16:
                            c = (255, 190, 110) if r.random() < 0.8 else (120, 200, 255)
                            d.rectangle([wx, wy, wx + 7, wy + 10], fill=c)
            # antennae / water tanks
            if r.random() < 0.3:
                d.line([(x + bw // 2, top_y), (x + bw // 2, top_y - r.integers(20, 60))],
                       fill=col, width=4)
            x += bw + r.integers(6, 26)
    # wet street reflection band
    for yy in range(880, H):
        t_ = (yy - 880) / (H - 880)
        d.line([(0, yy), (W, yy)], fill=(int(14 + 20 * t_), int(12 + 12 * t_), int(18 + 10 * t_)))
    # neon reflections
    for i in range(60):
        x = r.integers(0, W)
        yy = r.integers(900, H - 4)
        c = [EMBER, MAGENTA, CYAN, AMBER][i % 4]
        d.line([(x, yy), (x + r.integers(4, 40), yy)], fill=c, width=2)
    # lone figure silhouette
    fx, fy = 1250, 872
    d.ellipse([fx - 10, fy - 96, fx + 10, fy - 76], fill=(6, 6, 8))
    d.polygon([(fx - 16, fy - 78), (fx + 16, fy - 78), (fx + 22, fy), (fx - 22, fy)], fill=(6, 6, 8))
    d.line([(fx + 14, fy - 70), (fx + 30, fy - 34)], fill=(6, 6, 8), width=7)
    # rain streaks
    for i in range(240):
        x = r.integers(0, W)
        yy = r.integers(0, H - 30)
        ln = r.integers(10, 34)
        d.line([(x, yy), (x - 3, yy + ln)], fill=(150, 160, 190, 40), width=1)
    img.save(os.path.join(UI, "menu_bg.png"))


def loading_art():
    Image, ImageDraw, ImageFont = P()
    W, H = 1280, 720
    img = Image.new("RGB", (W, H), (12, 11, 15))
    d = ImageDraw.Draw(img)
    r = np.random.default_rng(9)
    # abstract ember field
    for i in range(300):
        x, y = r.integers(0, W), r.integers(0, H)
        rr = r.integers(1, 4)
        c = (255, r.integers(90, 180), r.integers(30, 80))
        d.ellipse([x, y, x + rr, y + rr], fill=c)
    f = ImageFont.truetype(FONT_B, 60)
    d.text((60, H - 140), "CINDER CITY", font=f, fill=(200, 188, 172))
    img.save(os.path.join(UI, "loading_bg.png"))


# ------------------------------------------------------------------ ui kit -
def ui_kit():
    Image, ImageDraw, ImageFont = P()
    # panel 9-patch (charcoal, amber hairline)
    S = 96
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([2, 2, S - 3, S - 3], radius=14, fill=(16, 14, 19, 235),
                        outline=(255, 179, 71, 150), width=2)
    d.rounded_rectangle([6, 6, S - 7, S - 7], radius=10, outline=(255, 255, 255, 24), width=1)
    img.save(os.path.join(UI, "panel9.png"))
    # button 9-patch
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([2, 2, S - 3, S - 3], radius=12, fill=(34, 29, 36, 240),
                        outline=(232, 226, 214, 120), width=2)
    img.save(os.path.join(UI, "button9.png"))
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([2, 2, S - 3, S - 3], radius=12, fill=(70, 40, 22, 240),
                        outline=(255, 140, 60, 220), width=3)
    img.save(os.path.join(UI, "button9_hot.png"))

    def icon(name, draw_fn, size=96):
        img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        draw_fn(d, size)
        img.save(os.path.join(UI, name + ".png"))

    B = BONE + (255,)
    A = AMBER + (255,)

    def i_health(d, s):
        d.polygon([(s / 2, s * .85), (s * .12, s * .42), (s * .2, s * .2), (s * .38, s * .2),
                   (s / 2, s * .36), (s * .62, s * .2), (s * .8, s * .2), (s * .88, s * .42)], fill=(220, 60, 60, 255))

    def i_armor(d, s):
        d.polygon([(s / 2, s * .1), (s * .85, s * .25), (s * .8, s * .6), (s / 2, s * .9),
                   (s * .2, s * .6), (s * .15, s * .25)], fill=(110, 150, 200, 255))

    def i_stamina(d, s):
        d.polygon([(s * .55, s * .08), (s * .25, s * .55), (s * .45, s * .55), (s * .4, s * .92),
                   (s * .75, s * .42), (s * .53, s * .42)], fill=(240, 200, 80, 255))

    def i_money(d, s):
        d.rounded_rectangle([s * .1, s * .28, s * .9, s * .72], radius=6, outline=A, width=5)
        d.ellipse([s * .38, s * .38, s * .62, s * .62], outline=A, width=4)

    def i_star(d, s):
        pts = []
        for k in range(10):
            ang = -np.pi / 2 + k * np.pi / 5
            rr = s * .42 if k % 2 == 0 else s * .18
            pts.append((s / 2 + rr * np.cos(ang), s / 2 + rr * np.sin(ang)))
        d.polygon(pts, fill=(255, 200, 60, 255))

    def i_ammo(d, s):
        d.rectangle([s * .4, s * .2, s * .6, s * .75], fill=A)
        d.polygon([(s * .4, s * .2), (s * .5, s * .08), (s * .6, s * .2)], fill=A)
        d.rectangle([s * .35, s * .75, s * .65, s * .88], fill=(180, 150, 90, 255))

    def i_phone(d, s):
        d.rounded_rectangle([s * .3, s * .1, s * .7, s * .9], radius=8, outline=B, width=5)
        d.line([(s * .42, s * .8), (s * .58, s * .8)], fill=B, width=4)

    def i_call(d, s):
        d.arc([s * .15, s * .2, s * .85, s * .9], 200, 340, fill=(120, 220, 140, 255), width=10)

    def i_msg(d, s):
        d.rounded_rectangle([s * .12, s * .2, s * .88, s * .7], radius=8, outline=(140, 200, 255, 255), width=5)
        d.polygon([(s * .3, s * .7), (s * .3, s * .88), (s * .48, s * .7)], fill=(140, 200, 255, 255))

    def i_radio(d, s):
        d.ellipse([s * .15, s * .45, s * .45, s * .75], outline=(255, 90, 190, 255), width=5)
        d.line([(s * .3, s * .6), (s * .75, s * .18)], fill=(255, 90, 190, 255), width=5)

    def i_map(d, s):
        d.polygon([(s * .12, s * .2), (s * .38, s * .3), (s * .62, s * .18), (s * .88, s * .28),
                   (s * .88, s * .8), (s * .62, s * .7), (s * .38, s * .82), (s * .12, s * .72)],
                  outline=(200, 190, 170, 255), width=5)
        d.line([(s * .38, s * .3), (s * .38, s * .82)], fill=(200, 190, 170, 255), width=3)
        d.line([(s * .62, s * .18), (s * .62, s * .7)], fill=(200, 190, 170, 255), width=3)

    def i_objective(d, s):
        d.ellipse([s * .2, s * .2, s * .8, s * .8], outline=A, width=5)
        d.ellipse([s * .4, s * .4, s * .6, s * .6], fill=A)

    def i_gun(d, s):
        d.polygon([(s * .12, s * .38), (s * .88, s * .38), (s * .88, s * .5), (s * .5, s * .5),
                   (s * .42, s * .78), (s * .3, s * .78), (s * .34, s * .5), (s * .12, s * .5)], fill=B)

    def i_fist(d, s):
        d.rounded_rectangle([s * .25, s * .3, s * .75, s * .72], radius=10, fill=B)
        d.rectangle([s * .2, s * .55, s * .45, s * .8], fill=B)

    def i_interact(d, s):
        d.ellipse([s * .15, s * .15, s * .85, s * .85], outline=A, width=5)
        d.line([(s / 2, s * .3), (s / 2, s * .7)], fill=A, width=6)
        d.line([(s * .3, s / 2), (s * .7, s / 2)], fill=A, width=6)

    def i_lock(d, s):
        for k in range(4):
            ang = k * np.pi / 2 + np.pi / 4
            x1, y1 = s / 2 + s * .45 * np.cos(ang), s / 2 + s * .45 * np.sin(ang)
            x2, y2 = s / 2 + s * .25 * np.cos(ang), s / 2 + s * .25 * np.sin(ang)
            d.line([(x1, y1), (x2, y2)], fill=(255, 80, 80, 255), width=6)
        d.ellipse([s * .42, s * .42, s * .58, s * .58], fill=(255, 80, 80, 255))

    for nm, fn in [("i_health", i_health), ("i_armor", i_armor), ("i_stamina", i_stamina),
                   ("i_money", i_money), ("i_star", i_star), ("i_ammo", i_ammo),
                   ("i_phone", i_phone), ("i_call", i_call), ("i_msg", i_msg),
                   ("i_radio", i_radio), ("i_map", i_map), ("i_objective", i_objective),
                   ("i_gun", i_gun), ("i_fist", i_fist), ("i_interact", i_interact),
                   ("i_lock", i_lock)]:
        icon(nm, fn)

    # crosshair
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([26, 26, 38, 38], outline=(255, 255, 255, 200), width=2)
    for ang in range(4):
        a = ang * np.pi / 2
        d.line([(32 + 10 * np.cos(a), 32 + 10 * np.sin(a)), (32 + 20 * np.cos(a), 32 + 20 * np.sin(a))],
               fill=(255, 255, 255, 220), width=3)
    img.save(os.path.join(UI, "crosshair.png"))

    # touch dpad-style action button base rings (labels added in-engine)
    for nm, col in [("btn_ring", (232, 226, 214)), ("btn_ring_hot", (255, 140, 60))]:
        img = Image.new("RGBA", (128, 128), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        d.ellipse([6, 6, 122, 122], fill=(20, 18, 24, 150), outline=col + (200,), width=4)
        img.save(os.path.join(UI, nm + ".png"))

    # minimap frame
    img = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.ellipse([4, 4, 252, 252], outline=AMBER + (200,), width=5)
    d.ellipse([12, 12, 244, 244], outline=(255, 255, 255, 60), width=2)
    img.save(os.path.join(UI, "minimap_frame.png"))


# ---------------------------------------------------------------- faces ----
SKINS = [(232, 190, 152), (206, 160, 118), (172, 122, 84), (120, 82, 56),
         (88, 60, 42), (240, 210, 180), (150, 104, 70), (60, 42, 32)]


def face(idx):
    """Stylized face albedo 256px: skin base, brows, eyes, lips, stubble/hairline.
    Mapped onto the procedural head mesh UVs (front face region)."""
    from PIL import Image, ImageDraw
    S = 256
    r = np.random.default_rng(1000 + idx)
    skin = SKINS[idx % len(SKINS)]
    img = Image.new("RGB", (S, S), skin)
    d = ImageDraw.Draw(img)
    # shading: temples/jaw darker
    n = fbm(128, 4, 3, 0.5, r)
    n = np.array(Image.fromarray((n * 255).astype(np.uint8)).resize((S, S))) / 255
    arr = np.array(img).astype(float)
    shade = 0.86 + 0.28 * n
    arr *= shade[..., None]
    img = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(img)
    fem = idx % 2 == 1
    # eyes
    ey = int(S * 0.44)
    for sx in (0.33, 0.67):
        ex = int(S * sx)
        d.ellipse([ex - 20, ey - 9, ex + 20, ey + 9], fill=(238, 234, 228))
        iris = [(70, 50, 34), (52, 74, 60), (60, 64, 88), (40, 40, 44)][idx % 4]
        d.ellipse([ex - 9, ey - 9, ex + 9, ey + 9], fill=iris)
        d.ellipse([ex - 4, ey - 4, ex + 4, ey + 4], fill=(12, 10, 10))
        d.ellipse([ex - 7, ey - 7, ex - 3, ey - 3], fill=(255, 255, 255))
        # lid line
        d.arc([ex - 21, ey - 12, ex + 21, ey + 8], 200, 340, fill=(40, 28, 22), width=3)
        # brow
        bw = 5 if fem else 8
        d.arc([ex - 24, ey - 30, ex + 24, ey - 2], 200, 340,
              fill=(30 + idx * 3 % 60, 22, 16), width=bw)
    # nose shadow
    d.line([(S * 0.5, ey + 12), (S * 0.48, ey + 40), (S * 0.53, ey + 46)],
           fill=tuple(int(c * 0.8) for c in skin), width=4)
    # lips
    ly = int(S * 0.74)
    lipc = (150, 84, 74) if fem else (120, 74, 66)
    d.arc([S * 0.38, ly - 12, S * 0.62, ly + 12], 0, 180, fill=lipc, width=7)
    d.line([(S * 0.4, ly), (S * 0.6, ly)], fill=tuple(int(c * 0.7) for c in lipc), width=3)
    # stubble or hairline
    if not fem and idx % 3 == 0:
        for k in range(140):
            x, y = r.integers(int(S * .3), int(S * .7)), r.integers(int(S * .78), S)
            d.point((x, y), fill=(40, 30, 24))
    d.arc([S * 0.2, -S * 0.35, S * 0.8, S * 0.35], 20, 160,
          fill=(28 + idx * 5 % 70, 20, 14), width=16)
    img.save(os.path.join(FA, f"face_{idx:02d}.png"))


def main():
    print("== LEVERAGE ui/face forge ==")
    app_icon()
    logo()
    studio_splash()
    advisory()
    menu_art()
    loading_art()
    ui_kit()
    for i in range(24):
        face(i)
    print("done")


if __name__ == "__main__":
    main()
