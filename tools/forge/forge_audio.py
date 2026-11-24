"""forge_audio — synthesizes ALL of LEVERAGE's audio. 100% original.

Output: assets/audio/sfx/*.wav, assets/audio/music/*.wav,
        assets/audio/vox/*.wav
Music is composed here (note data below) — noir trip-hop / industrial /
synthwave beds per district, plus combat/chase/tension layers.
"""
import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from forge_audio_lib import (SR, t, env, sine, saw, square, tri, noise, mix,
                             stereo, reverb_simple, normalize, fade, write_wav,
                             hz, chord_freqs, onepole_lp_fast, onepole_hp_fast,
                             bandpass_fast, delay)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SFX = os.path.join(ROOT, "assets", "audio", "sfx")
MUS = os.path.join(ROOT, "assets", "audio", "music")
VOX = os.path.join(ROOT, "assets", "audio", "vox")
for d in (SFX, MUS, VOX):
    os.makedirs(d, exist_ok=True)

R = np.random.default_rng(4242)


def _sh(x):
    """Stable hash. Python's builtin hash() is salted per process
    (PYTHONHASHSEED), so hash((surface, variant)) gave the footsteps and the
    district music tracks a DIFFERENT seed on every run — this forge claims to
    be the source of truth for assets/audio, and it could not reproduce its own
    output. crc32 is stable across processes and across Python versions."""
    import zlib
    return zlib.crc32(repr(x).encode("utf-8"))


def M(*parts, gains=None):
    """Pad-and-sum signals of differing lengths."""
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for i, p in enumerate(parts):
        g = 1.0 if gains is None else gains[i]
        out[:len(p)] += p * g
    return out


def w(path, x, st=False):
    write_wav(path, x, stereo_=st)


# ================================================================ FOOTSTEPS =
SURFACES = {
    # name: (lowpass, body_freq, crackle, decay)
    "asphalt": (900, 90, 0.25, 0.09),
    "concrete": (1400, 120, 0.35, 0.08),
    "metal": (2600, 240, 0.5, 0.14),
    "gravel": (3200, 150, 0.8, 0.07),
    "water": (1200, 80, 0.9, 0.12),
    "wood": (1100, 180, 0.4, 0.10),
}


def footstep(surface, run=False, variant=0):
    lp, body, crack, dec = SURFACES[surface]
    d = dec * (0.85 if run else 1.0) + variant * 0.008
    nd = max(64, int(SR * d))
    n = noise(nd / SR, np.random.default_rng(_sh((surface, variant)) & 0xFFFF))
    n = onepole_lp_fast(n, lp * (1.2 if run else 1.0))
    amp = 0.5 if run else 0.32
    e = env(nd / SR, a=0.001, d=d * 0.7, s=0.0, r=d * 0.3)
    step = n[:len(e)] * e * amp
    body_s = sine(body * (1 + variant * 0.03), d)[:len(e)] * env(d, 0.001, d * 0.5, 0, d * 0.4)[:len(e)] * 0.35
    cr = noise(d, np.random.default_rng(variant + 7))[:len(e)] * crack * 0.15
    cr = onepole_hp_fast(cr, lp * 0.8)[:len(e)] * e
    if surface == "water":
        spl = bandpass_fast(noise(d + 0.08, np.random.default_rng(variant + 3)), 1500, 6000)
        e2 = env(d + 0.08, 0.002, 0.06, 0, 0.06)
        spl = (spl * e2 * 0.5)[:len(e)]
        step = (step + spl)[:len(e)]
    if surface == "metal":
        ring = sine(body * 3.7, d * 1.6) * env(d * 1.6, 0.001, d, 0, d) * 0.12
        step = (step + ring[:len(step)])
    return fade(normalize(step + body_s + cr, 0.8), 0.002, 0.01)


# =================================================================== MELEE ==
def whoosh(dur=0.22, f0=300, heavy=False):
    n = noise(dur, R)
    sw = bandpass_fast(n, f0, f0 * (2.2 if heavy else 4.0))
    e = env(dur, 0.02, dur * 0.5, 0.1, dur * 0.4)
    return fade(normalize(sw * e * (0.9 if heavy else 0.6), 0.7))


def punch_hit(heavy=False):
    d = 0.16 if heavy else 0.11
    n = noise(d, R)
    body = onepole_lp_fast(n, 500 if heavy else 800)
    slap = bandpass_fast(n, 900, 2400)
    th = sine(70 if heavy else 95, d) * env(d, 0.001, d * 0.6, 0, d * 0.4)
    x = body * env(d, 0.001, d * 0.5, 0, d * 0.4) * 0.8 + slap * env(d, 0.001, 0.02, 0, 0.05) * 0.5 + th * 0.9
    return fade(normalize(reverb_simple(x, 0.12, 0.12), 0.85))


def block_hit():
    d = 0.12
    n = bandpass_fast(noise(d, R), 400, 1400)
    x = n * env(d, 0.001, d * 0.6, 0, d * 0.3) * 0.6 + sine(160, d) * env(d, 0.001, 0.05, 0, 0.06) * 0.7
    return fade(normalize(x, 0.8))


def parry_clang():
    d = 0.5
    f = 1760.0
    x = (sine(f, d) * 0.5 + sine(f * 2.76, d) * 0.3 + sine(f * 5.4, d) * 0.15)
    x *= env(d, 0.001, 0.35, 0.02, 0.14)
    x = M(x, bandpass_fast(noise(0.06, R), 2000, 8000) * 0.5)
    return fade(normalize(reverb_simple(x, 0.4, 0.3), 0.8))


def grunt(pitch=110, dur=0.28, effort=0.7):
    f0 = pitch
    n = int(SR * dur)
    tt = np.arange(n) / SR
    f = f0 * (1 - 0.25 * tt / dur) * (1 + 0.05 * np.sin(2 * np.pi * 6 * tt))
    ph = 2 * np.pi * np.cumsum(f) / SR
    voice = np.sign(np.sin(ph)) * 0.4 + np.sin(ph) * 0.6
    voice = bandpass_fast(voice, f0 * 0.8, f0 * 4.5)
    x = voice * env(dur, 0.01, dur * 0.5, 0.3, dur * 0.4) * effort
    return fade(normalize(x, 0.7))


def body_fall():
    d = 0.3
    n = onepole_lp_fast(noise(d, R), 300)
    x = n * env(d, 0.002, d * 0.7, 0, d * 0.3) * 0.9 + sine(55, d) * env(d, 0.002, d * 0.6, 0, d * 0.4) * 0.8
    return fade(normalize(reverb_simple(x, 0.2, 0.2), 0.85))


def slam():
    d = 0.35
    x = M(body_fall(), whoosh(0.2, 500, True) * 0.6)
    return fade(normalize(x, 0.9))


# ==================================================================== GUNS ==
def gunshot(kind="pistol"):
    cfg = {
        "pistol": (0.18, 900, 140, 0.55),
        "smg": (0.12, 1100, 120, 0.45),
        "shotgun": (0.42, 500, 60, 0.9),
        "rifle": (0.26, 1300, 100, 0.7),
    }[kind]
    d, crack_f, boom_f, lvl = cfg
    n = noise(d + 0.25, R)
    dn = len(n) / SR
    crack = onepole_hp_fast(n, crack_f * 0.8) * env(dn, 0.0005, d * 0.35, 0, d * 0.5)
    boom = onepole_lp_fast(n, boom_f * 3) * env(dn, 0.001, d * 0.8, 0, d * 0.6) * 1.2
    tail = bandpass_fast(n, 300, 2000) * env(dn, 0.01, 0.25, 0, 0.15) * 0.25
    x = M(crack * 0.9, boom, tail) * lvl
    return fade(normalize(reverb_simple(x, 0.35, 0.35), 0.92))


def dry_fire():
    n = bandpass_fast(noise(0.05, R), 1200, 5000)
    return fade(normalize(n * env(0.05, 0.001, 0.02, 0, 0.02) * 0.5, 0.6))


def reload_step(kind):
    if kind == "magout":
        n = bandpass_fast(noise(0.09, R), 800, 3000)
        x = M(n * env(0.09, 0.001, 0.05, 0, 0.03) * 0.5, sine(300, 0.06) * 0.2)
    elif kind == "magin":
        n = bandpass_fast(noise(0.07, R), 1000, 4000)
        x = M(n * env(0.07, 0.001, 0.03, 0, 0.03) * 0.6, sine(420, 0.05) * env(0.05, 0.001, 0.02, 0, 0.02) * 0.4)
    else:  # slide
        n = bandpass_fast(noise(0.12, R), 600, 3500)
        x = M(n * env(0.12, 0.001, 0.08, 0.05, 0.03) * 0.55, sine(240, 0.08) * 0.25)
    return fade(normalize(x, 0.7))


def shell_drop():
    d = 0.25
    x = M(sine(2600, d) * env(d, 0.001, 0.09, 0, 0.15) * 0.25,
          sine(3900, d * 0.7) * env(d * 0.7, 0.001, 0.06, 0, 0.1) * 0.15)
    return fade(normalize(reverb_simple(x, 0.3, 0.3), 0.5))


def bullet_impact(kind):
    d = {"concrete": 0.2, "metal": 0.3, "glass": 0.4, "wood": 0.18}[kind]
    n = noise(d, R)
    if kind == "concrete":
        x = bandpass_fast(n, 700, 4000) * env(d, 0.001, d * 0.4, 0, d * 0.5) * 0.6
    elif kind == "metal":
        f = 2100
        x = M((sine(f, d) + sine(f * 1.7, d) * 0.5) * env(d, 0.001, d * 0.5, 0, d * 0.4) * 0.4,
              bandpass_fast(noise(0.05, R), 2000, 7000) * env(0.05, 0.001, 0.03, 0, 0.02) * 0.5)
    elif kind == "glass":
        shards = np.zeros(int(SR * d))
        for k in range(6):
            f = R.uniform(1800, 5200)
            dd = R.uniform(0.1, 0.35)
            st = int(R.uniform(0, 0.08) * SR)
            sg = sine(f, dd) * env(dd, 0.001, dd * 0.4, 0, dd * 0.5) * 0.15
            en = min(len(shards), st + len(sg))
            shards[st:en] += sg[:en - st]
        x = M(bandpass_fast(noise(0.08, R), 2500, 9000) * env(0.08, 0.001, 0.05, 0, 0.03) * 0.5, shards)
    else:
        x = bandpass_fast(n, 400, 1800) * env(d, 0.001, d * 0.5, 0, d * 0.4) * 0.5
    return fade(normalize(reverb_simple(x, 0.2, 0.25), 0.8))


def glass_break():
    d = 0.7
    n = bandpass_fast(noise(d, R), 2000, 9000)
    x = n * env(d, 0.001, d * 0.5, 0.02, d * 0.45) * 0.5
    for k in range(10):
        f = R.uniform(1500, 6000)
        dd = R.uniform(0.08, 0.4)
        st = int(R.uniform(0, 0.25) * SR)
        s = sine(f, dd) * env(dd, 0.001, dd * 0.4, 0, dd * 0.5) * 0.12
        en = min(len(x), st + len(s))
        x[st:en] += s[:en - st]
    return fade(normalize(reverb_simple(x, 0.4, 0.35), 0.8))


# ================================================================ VEHICLES ==
def engine_loop(kind="sedan", dur=2.0):
    cfg = {"sedan": (55, 0.35), "muscle": (42, 0.5), "van": (48, 0.4), "bike": (75, 0.3)}[kind]
    base, rough = cfg
    tt = t(dur)
    wobble = 1 + 0.02 * np.sin(2 * np.pi * 1.7 * tt) + 0.01 * np.sin(2 * np.pi * 3.1 * tt)
    f = base * wobble
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = saw_arr(ph) * 0.5 + np.sin(ph) * 0.5 + np.sin(ph * 2) * 0.25 * rough
    x = onepole_lp_fast(x, 900)
    x += noise(dur, np.random.default_rng(5)) * 0.12 * rough
    x += bandpass_fast(noise(dur, np.random.default_rng(6)), 100, 400) * 0.2
    x *= 0.5 + 0.08 * np.sin(2 * np.pi * 8 * tt)  # idle flutter
    return fade(normalize(x, 0.7), 0.05, 0.05)


def saw_arr(ph):
    x = (ph / (2 * np.pi)) % 1.0
    return 2 * x - 1


def skid_loop(dur=1.5):
    n = noise(dur, R)
    x = bandpass_fast(n, 800, 2600)
    x *= 0.7 + 0.3 * np.sin(2 * np.pi * 11 * t(dur))
    return fade(normalize(x, 0.6), 0.05, 0.1)


def crash(level="light"):
    d = 0.5 if level == "light" else 0.9
    n = noise(d, R)
    parts = [onepole_lp_fast(n, 800) * env(d, 0.002, d * 0.6, 0, d * 0.4),
             bandpass_fast(noise(0.12, R), 1500, 6000) * env(0.12, 0.001, 0.08, 0, 0.04) * (0.5 if level == "light" else 0.9),
             sine(60, d) * env(d, 0.002, d * 0.5, 0, d * 0.4) * 0.7]
    if level == "heavy":
        parts.append(glass_break() * 0.4)
    x = M(*parts)
    return fade(normalize(reverb_simple(x, 0.3, 0.3), 0.9))


def horn(dur=0.6):
    x = (saw_arr(2 * np.pi * 392 * t(dur)) * 0.4 + saw_arr(2 * np.pi * 466 * t(dur)) * 0.4)
    x = onepole_lp_fast(x, 1800)
    x *= env(dur, 0.01, 0.05, 0.9, 0.08)
    return fade(normalize(x, 0.7))


def siren_loop(dur=3.0):
    tt = t(dur)
    f = 660 + 260 * (np.sign(np.sin(2 * np.pi * 0.55 * tt)) * 0.5 + 0.5)
    f = f * (1 + 0.01 * np.sin(2 * np.pi * 5 * tt))
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph) * 0.5 + np.sin(ph * 2) * 0.2
    x = reverb_simple(x, 0.3, 0.2)
    return fade(normalize(x, 0.6), 0.05, 0.05)


def door_sound(kind="wood", opening=True):
    d = 0.4
    n = bandpass_fast(noise(d, R), 200, 900)
    creak = saw_arr(2 * np.pi * (90 + 40 * t(d) / d) * t(d)) * 0.1
    creak = bandpass_fast(creak, 300, 1200) * env(d, 0.05, d * 0.6, 0.2, d * 0.3)
    x = n * env(d, 0.01, d * 0.5, 0.1, d * 0.4) * 0.4 + creak
    if not opening:
        x = M(x, onepole_lp_fast(noise(0.08, R), 400) * env(0.08, 0.001, 0.05, 0, 0.03) * 0.8)  # latch clunk
    if kind == "metal":
        x = M(x, sine(240, 0.3) * env(0.3, 0.005, 0.2, 0, 0.1) * 0.2)
    return fade(normalize(x, 0.7))


def engine_start():
    d = 1.1
    tt = t(d)
    rev = np.interp(tt, [0, 0.35, 0.55, 1.1], [30, 90, 60, 55])
    ph = 2 * np.pi * np.cumsum(rev) / SR
    x = saw_arr(ph) * 0.6 + np.sin(ph) * 0.4
    x = onepole_lp_fast(x, 700) * env(d, 0.02, 0.4, 0.5, 0.3)
    x = M(x, noise(0.3, R) * onepole_lp_fast(np.ones(int(SR * 0.3)), 500) * env(0.3, 0.005, 0.2, 0, 0.1) * 0.4)
    return fade(normalize(x, 0.75))


# ==================================================================== UI ====
def ui_click():
    d = 0.05
    x = M(bandpass_fast(noise(d, R), 1500, 6000) * env(d, 0.001, 0.02, 0, 0.02) * 0.4,
          sine(1400, 0.04) * env(0.04, 0.001, 0.02, 0, 0.015) * 0.3)
    return fade(normalize(x, 0.6))


def ui_back():
    d = 0.07
    x = sine(600, d) * env(d, 0.001, 0.04, 0, 0.02) * 0.35
    x += sine(420, d) * env(d, 0.005, 0.04, 0, 0.02) * 0.25
    return fade(normalize(x, 0.6))


def ui_confirm():
    d = 0.14
    x = M(sine(880, d) * env(d, 0.002, 0.06, 0.2, 0.06) * 0.3,
          sine(1320, d * 0.8) * env(d * 0.8, 0.004, 0.05, 0.2, 0.05) * 0.25)
    return fade(normalize(reverb_simple(x, 0.15, 0.2), 0.6))


def ui_error():
    d = 0.18
    x = square(220, d) * env(d, 0.002, 0.08, 0.3, 0.06) * 0.25
    x += square(180, d) * env(d, 0.01, 0.08, 0.3, 0.06) * 0.2
    return fade(normalize(x, 0.6))


def ui_notify():
    d = 0.25
    x = M(sine(1046, d) * env(d, 0.002, 0.1, 0.3, 0.1) * 0.3,
          sine(1568, d * 0.7) * env(d * 0.7, 0.01, 0.08, 0.3, 0.08) * 0.2)
    return fade(normalize(reverb_simple(x, 0.2, 0.25), 0.6))


def phone_ring():
    d = 1.6
    x = np.zeros(int(SR * d))
    for k in range(2):
        st = int(k * 0.8 * SR)
        seg = (sine(1200, 0.4) * 0.3 + sine(1500, 0.4) * 0.2)
        seg *= (np.sin(2 * np.pi * 20 * t(0.4)) > 0).astype(float)
        x[st:st + len(seg)] += seg
    return fade(normalize(x, 0.6), 0.005, 0.01)


def phone_msg():
    d = 0.5
    x = np.zeros(int(SR * d))
    s1 = sine(988, 0.12) * env(0.12, 0.002, 0.06, 0.2, 0.04) * 0.3
    x[:len(s1)] += s1
    s2 = sine(1319, 0.2) * env(0.2, 0.002, 0.1, 0.2, 0.08) * 0.3
    st = 8000
    en = min(len(x), st + len(s2))
    x[st:en] += s2[:en - st]
    return fade(normalize(reverb_simple(x, 0.2, 0.2), 0.6))


# ================================================================== WORLD ===
def rain_loop(dur=4.0):
    n = noise(dur, R)
    x = bandpass_fast(n, 700, 7000) * 0.35
    x += bandpass_fast(n, 2000, 9000) * 0.15
    drops = np.zeros(int(SR * dur))
    for k in range(int(dur * 30)):
        st = int(R.uniform(0, dur - 0.05) * SR)
        dd = R.uniform(0.01, 0.03)
        f = R.uniform(3000, 7000)
        s = sine(f, dd) * env(dd, 0.001, dd * 0.5, 0, dd * 0.5) * R.uniform(0.02, 0.07)
        en = min(len(drops), st + len(s))
        drops[st:en] += s[:en - st]
    x += drops
    return fade(normalize(x, 0.5), 0.2, 0.2)


def thunder(variant=0):
    d = 2.5 + variant * 0.7
    n = noise(d, np.random.default_rng(90 + variant))
    x = onepole_lp_fast(n, 180 + variant * 40)
    x *= env(d, 0.02, d * 0.5, 0.15, d * 0.4)
    x = M(x, onepole_lp_fast(noise(d * 0.5, R), 400) * env(d * 0.5, 0.005, 0.3, 0, 0.2) * 0.4)
    return fade(normalize(x, 0.85), 0.01, 0.3)


def traffic_loop(dur=4.0):
    n = noise(dur, R)
    x = onepole_lp_fast(n, 300) * 0.5
    x += bandpass_fast(n, 500, 1500) * 0.12 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.23 * t(dur)))
    return fade(normalize(x, 0.4), 0.3, 0.3)


def crowd_loop(dur=4.0):
    n = noise(dur, R)
    x = bandpass_fast(n, 250, 1400) * 0.35
    m = 0.5 + 0.5 * bandpass_fast(noise(dur, np.random.default_rng(3)), 0.5, 3.0)
    x *= (0.5 + 0.5 * np.clip(m, 0, 1))
    return fade(normalize(x, 0.4), 0.3, 0.3)


def fire_crackle(dur=2.0):
    x = np.zeros(int(SR * dur))
    base = bandpass_fast(noise(dur, R), 100, 900) * 0.25
    x += base
    for k in range(int(dur * 24)):
        st = int(R.uniform(0, dur - 0.04) * SR)
        dd = R.uniform(0.008, 0.03)
        s = bandpass_fast(noise(dd, R), 1000, 6000) * env(dd, 0.001, dd * 0.5, 0, dd * 0.4) * R.uniform(0.15, 0.5)
        en = min(len(x), st + len(s))
        x[st:en] += s[:en - st]
    return fade(normalize(x, 0.6), 0.2, 0.2)


def steam_hiss(dur=1.2):
    n = noise(dur, R)
    x = bandpass_fast(n, 2500, 9000) * env(dur, 0.05, dur * 0.5, 0.1, dur * 0.4) * 0.5
    return fade(normalize(x, 0.6))


def alarm_loop(dur=2.0):
    tt = t(dur)
    f = 950 + 150 * np.sin(2 * np.pi * 2.2 * tt)
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = (square_arr(ph) * 0.3) * (0.7 + 0.3 * (np.sin(2 * np.pi * 4.4 * tt) > 0))
    return fade(normalize(x, 0.5), 0.02, 0.05)


def square_arr(ph):
    return (((ph / (2 * np.pi)) % 1.0) < 0.5).astype(float) * 2 - 1


def shop_bell():
    d = 0.8
    x = M(sine(1568, d) * env(d, 0.001, 0.3, 0.02, 0.4) * 0.3,
          sine(2093, d * 0.7) * env(d * 0.7, 0.002, 0.2, 0.02, 0.3) * 0.2,
          sine(3136, 0.3) * env(0.3, 0.001, 0.1, 0, 0.15) * 0.1)
    return fade(normalize(reverb_simple(x, 0.4, 0.3), 0.6))


def cash_register():
    d = 0.5
    x = bandpass_fast(noise(0.06, R), 1000, 5000) * 0.4
    s2 = sine(1200, 0.3) * env(0.3, 0.001, 0.1, 0, 0.15) * 0.25
    x = np.concatenate([x, np.zeros(3000), s2])
    return fade(normalize(reverb_simple(x, 0.2, 0.25), 0.6))


def radio_static(dur=1.0):
    n = noise(dur, R)
    x = bandpass_fast(n, 500, 4000) * 0.25 * (0.6 + 0.4 * bandpass_fast(noise(dur, np.random.default_rng(11)), 2, 30))
    return fade(normalize(x, 0.4), 0.05, 0.05)


# ==================================================================== VOX ===
VOICES = [
    # name, f0, brightness, style
    ("eli", 105, 0.5, "tired"), ("marcus", 130, 0.6, "wired"),
    ("roz", 165, 0.7, "smooth"), ("crane", 88, 0.35, "gravel"),
    ("vivian", 190, 0.55, "cold"), ("det_okoro", 150, 0.5, "clipped"),
    ("mama_ruth", 140, 0.6, "warm"), ("bishop", 100, 0.4, "sermon"),
    ("tess", 210, 0.75, "bright"), ("gunnar", 80, 0.3, "slow"),
    ("nia", 200, 0.65, "sharp"), ("padre_sol", 120, 0.45, "soft"),
    ("dex", 145, 0.7, "fast"), ("mags", 175, 0.6, "dry"),
    ("crowe_jr", 115, 0.5, "sneer"), ("halcyon_ai", 240, 0.85, "flat"),
    ("ped_m", 110, 0.5, "plain"), ("ped_f", 185, 0.6, "plain"),
    ("ped_m2", 95, 0.4, "plain"), ("ped_f2", 205, 0.65, "plain"),
]


def vox_blip(name, f0, bright, style, variant=0):
    d = 0.09 + variant * 0.02
    n = int(SR * d)
    tt = np.arange(n) / SR
    drift = {"tired": -0.12, "wired": 0.15, "smooth": -0.05, "gravel": -0.2,
             "cold": -0.08, "clipped": -0.05, "warm": 0.06, "sermon": 0.1,
             "bright": 0.12, "slow": -0.15, "sharp": 0.05, "soft": -0.06,
             "fast": 0.1, "dry": -0.04, "sneer": 0.08, "flat": 0.0,
             "plain": 0.0}[style]
    f = f0 * (1 + drift * tt / d) * (1 + 0.04 * np.sin(2 * np.pi * 5.5 * tt))
    if style == "gravel":
        f *= (1 + 0.08 * noise(d, np.random.default_rng(7)))
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sign(np.sin(ph)) * 0.35 + np.sin(ph) * 0.5 + np.sin(ph * 2) * 0.25
    # vowel formants
    v = variant % 3
    f1, f2 = [(600, 1100), (400, 1900), (350, 800)][v]
    x = bandpass_fast(x, f1 * 0.6, f1 * 1.6) * 0.8 + bandpass_fast(x, f2 * 0.7, f2 * 1.4) * (0.4 * bright)
    if style == "flat":
        x = np.tanh(x * 2.5) * 0.6  # synthetic speaker
    x *= env(d, 0.008, d * 0.4, 0.5, d * 0.4)
    return fade(normalize(x, 0.5), 0.005, 0.01)


# ================================================================== MUSIC ===
def drum_kick(d=0.3, f=52, punch=1.0):
    tt = t(d)
    f_sweep = f * 3 * np.exp(-tt * 22) + f
    ph = 2 * np.pi * np.cumsum(f_sweep) / SR
    x = M(np.sin(ph) * env(d, 0.001, d * 0.5, 0.1, d * 0.4),
          onepole_lp_fast(noise(0.02, R), 900) * 0.3 * punch)
    return x


def drum_snare(d=0.18, tone=180):
    n = bandpass_fast(noise(d, R), tone, tone * 6)
    x = M(n * env(d, 0.001, d * 0.4, 0, d * 0.5),
          sine(tone, d * 0.6) * env(d * 0.6, 0.001, 0.04, 0, 0.08) * 0.5)
    return x


def drum_hat(d=0.06, open_=False):
    dd = d * (4 if open_ else 1)
    n = onepole_hp_fast(noise(dd, R), 6000)
    return n * env(dd, 0.001, dd * 0.5, 0, dd * 0.4) * 0.5


def bass_note(f, d, wave="saw", cutoff=320, drive=0.0):
    ph = 2 * np.pi * f * t(d)
    x = saw_arr(ph) if wave == "saw" else (np.sin(ph) if wave == "sine" else square_arr(ph))
    if wave == "sub":
        x = np.sin(ph) + 0.3 * np.sin(ph * 2)
    x = onepole_lp_fast(x, cutoff)
    if drive:
        x = np.tanh(x * (1 + drive * 3))
    return x * env(d, 0.005, 0.05, 0.85, min(0.1, d * 0.3))


def pad_chord(freqs, d, detune=0.004, cutoff=1200, atk=0.6):
    n = int(SR * d)
    x = np.zeros(n)
    for f in freqs:
        for dt in (-detune, detune):
            ph = 2 * np.pi * f * (1 + dt) * t(d)
            x += (np.sin(ph) + 0.35 * np.sin(ph * 2) + 0.12 * np.sin(ph * 3))
    x = onepole_lp_fast(x / (len(freqs) * 2), cutoff)
    return x * env(d, atk, d * 0.3, 0.7, d * 0.4)


def tri_arr(ph):
    x = (ph / (2 * np.pi)) % 1.0
    return 4 * np.abs(x - 0.5) - 1


def pluck(f, d, bright=0.6, wave="tri"):
    ph = 2 * np.pi * f * t(d)
    x = tri_arr(ph) if wave == "tri" else saw_arr(ph)
    x = onepole_lp_fast(x, 900 + 3000 * bright)
    return x * env(d, 0.002, d * 0.6, 0.05, d * 0.35)


def muted_lead(f, d, vib=5.5):
    tt = t(d)
    f_v = f * (1 + 0.012 * np.sin(2 * np.pi * vib * tt))
    ph = 2 * np.pi * np.cumsum(f_v) / SR
    x = saw_arr(ph) * 0.6 + np.sin(ph) * 0.4
    x = onepole_lp_fast(x, 1400)
    return x * env(d, 0.03, d * 0.4, 0.5, d * 0.4)


class Track:
    def __init__(self, bpm, bars, seed=1):
        self.bpm = bpm
        self.beat = 60.0 / bpm
        self.bar = self.beat * 4
        self.bars = bars
        self.dur = self.bar * bars
        self.n = int(SR * self.dur)
        self.buf = np.zeros(self.n)
        self.rng = np.random.default_rng(seed)

    def add(self, sig, at_beat, gain=1.0):
        st = int(at_beat * self.beat * SR)
        en = min(self.n, st + len(sig))
        if st < self.n:
            self.buf[st:en] += sig[:en - st] * gain

    def out(self, fx=0.25, stereo_w=0.25):
        x = self.buf
        if fx:
            x = reverb_simple(x, 0.5, fx)
        l = x + np.roll(x, int(0.0012 * SR)) * stereo_w
        r = x + np.roll(x, -int(0.0012 * SR)) * stereo_w
        return fade(normalize(stereo(l, r), 0.85), 0.05, 0.3)


PROG_NOIR = [("F#2", "m7"), ("D2", "M7"), ("B1", "m7"), ("C#2", "dom7")]


def music_menu():
    tr = Track(72, 8, 21)
    for bar in range(8):
        root, q = PROG_NOIR[bar % 4]
        tr.add(pad_chord(chord_freqs(root, q), tr.bar * 1.05, cutoff=900, atk=1.2), bar * 4, 0.5)
        tr.add(bass_note(hz(root), tr.bar * 0.9, "sub", 220), bar * 4, 0.55)
        # brushed hat
        for b in range(4):
            tr.add(drum_hat(0.05), bar * 4 + b + 0.5, 0.12)
        tr.add(drum_kick(0.3, 48, 0.5), bar * 4, 0.5)
        tr.add(drum_snare(0.16, 150), bar * 4 + 2, 0.18)
    # noir lead motif
    motif = [("F#4", 0, 1.5), ("A4", 1.5, 1), ("C#5", 2.5, 1.5), ("B4", 4, 2),
             ("F#4", 8, 1.5), ("E4", 9.5, 1), ("D4", 10.5, 1.5), ("C#4", 12, 4)]
    for name, at, ln in motif:
        tr.add(muted_lead(hz(name), ln * tr.beat), at, 0.32)
    return tr.out(0.35)


def district_track(kind):
    cfg = {
        "kiln": (84, [("A1", "m7"), ("F1", "M7"), ("C2", "M7"), ("G1", "dom7")], "warm"),
        "docks": (70, [("D1", "m"), ("D1", "m"), ("Bb0", "M"), ("C1", "dom7")], "industrial"),
        "furnace": (90, [("E2", "m9"), ("C2", "M7"), ("A1", "m7"), ("B1", "dom7")], "cold"),
        "neon": (100, [("F#1", "m"), ("D2", "M"), ("E2", "M"), ("C#2", "m")], "synth"),
        "slag": (76, [("G1", "m7"), ("Eb1", "M7"), ("Bb1", "dom7"), ("F1", "m7")], "boom"),
        "heights": (60, [("C2", "M7"), ("A1", "m7"), ("F1", "M7"), ("G1", "dom7")], "airy"),
    }[kind]
    bpm, prog, style = cfg
    tr = Track(bpm, 8, 31 + _sh(kind) % 7)
    for bar in range(8):
        root, q = prog[bar % 4]
        bf = hz(root)
        tr.add(pad_chord(chord_freqs(root, q), tr.bar * 1.02,
                         cutoff={"warm": 1100, "industrial": 700, "cold": 1500,
                                 "synth": 1800, "boom": 900, "airy": 2200}[style],
                         atk={"warm": 0.8, "industrial": 1.5, "cold": 1.2,
                              "synth": 0.4, "boom": 0.9, "airy": 2.0}[style]), bar * 4, 0.4)
        # bass pattern
        if style in ("boom", "synth"):
            for b, ln in [(0, 0.9), (1.5, 0.4), (2.5, 0.9), (3.5, 0.4)]:
                tr.add(bass_note(bf, ln * tr.beat, "saw", 300, 0.3), bar * 4 + b, 0.5)
        else:
            tr.add(bass_note(bf, tr.bar * 0.92, "sub", 200), bar * 4, 0.5)
        # drums
        if style in ("boom", "synth", "warm"):
            tr.add(drum_kick(0.3, 50), bar * 4, 0.6)
            tr.add(drum_kick(0.3, 50), bar * 4 + 2.5, 0.4)
            tr.add(drum_snare(0.16, 190), bar * 4 + 1, 0.3)
            tr.add(drum_snare(0.16, 190), bar * 4 + 3, 0.3)
            for b in range(8):
                tr.add(drum_hat(0.04, b % 4 == 3), bar * 4 + b * 0.5, 0.16)
        if style == "industrial":
            tr.add(drum_kick(0.4, 40), bar * 4, 0.7)
            tr.add(drum_kick(0.4, 40), bar * 4 + 2, 0.6)
            # metallic clang
            cl = sine(2100 + (bar % 3) * 300, 0.4) * env(0.4, 0.001, 0.25, 0, 0.14) * 0.12
            tr.add(cl, bar * 4 + 1.5, 0.5)
            tr.add(drum_hat(0.05), bar * 4 + 3.5, 0.2)
        if style in ("cold", "airy"):
            tr.add(drum_kick(0.3, 46, 0.4), bar * 4 + 0.0, 0.35)
            for b in range(4):
                tr.add(drum_hat(0.04), bar * 4 + b + 0.75, 0.1)
        # motif / arp
        if style == "synth":
            seq = [0, 3, 7, 10, 12, 10, 7, 3]
            for i, semi in enumerate(seq):
                tr.add(pluck(bf * 4 * 2 ** (semi / 12), 0.35, 0.8, "saw"),
                       bar * 4 + i * 0.5, 0.18)
        if style == "warm":
            if bar % 2 == 1:
                for i, semi in enumerate([7, 10, 12]):
                    tr.add(pluck(bf * 2 * 2 ** (semi / 12), 0.6, 0.35), bar * 4 + 1 + i * 0.75, 0.2)
        if style == "airy":
            if bar % 4 == 2:
                tr.add(muted_lead(bf * 8, tr.bar * 1.6, 4.5), bar * 4, 0.16)
    return tr.out(0.3 if style != "airy" else 0.45)


def music_tension():
    tr = Track(96, 8, 41)
    for bar in range(8):
        root, q = [("B1", "m"), ("B1", "m"), ("G1", "M"), ("A1", "dom7")][bar % 4]
        bf = hz(root)
        for b in range(4):
            tr.add(bass_note(bf, 0.42 * tr.beat, "saw", 240, 0.2), bar * 4 + b, 0.4)
        tr.add(pad_chord(chord_freqs(root, "m9"), tr.bar, cutoff=800, atk=1.5), bar * 4, 0.3)
        # heartbeat
        tr.add(drum_kick(0.25, 44, 0.3), bar * 4, 0.5)
        tr.add(drum_kick(0.25, 44, 0.3), bar * 4 + 0.75, 0.35)
        if bar % 2:
            tr.add(bandpass_fast(noise(0.3, tr.rng), 3000, 8000) * env(0.3, 0.01, 0.2, 0, 0.1) * 0.1,
                   bar * 4 + 3, 0.4)
    return tr.out(0.3)


def music_combat():
    tr = Track(132, 8, 42)
    riff = [0, 0, 3, 0, 5, 3, 0, -2]
    for bar in range(8):
        root = "E1" if bar % 4 < 2 else "D1"
        bf = hz(root)
        for b in range(4):
            tr.add(drum_kick(0.25, 52), bar * 4 + b, 0.7)
            tr.add(drum_snare(0.14, 220), bar * 4 + b + 0.5, 0.35)
            tr.add(drum_hat(0.04), bar * 4 + b + 0.25, 0.2)
            tr.add(drum_hat(0.04), bar * 4 + b + 0.75, 0.14)
        for i, semi in enumerate(riff):
            tr.add(bass_note(bf * 2 * 2 ** (semi / 12), 0.4 * tr.beat, "saw", 500, 0.6),
                   bar * 4 + i * 0.5, 0.45)
        tr.add(pad_chord(chord_freqs(root, "m"), tr.bar * 0.5, cutoff=1000, atk=0.2), bar * 4, 0.22)
    return tr.out(0.2)


def music_chase():
    tr = Track(148, 8, 43)
    for bar in range(8):
        root = ["A1", "A1", "F1", "G1"][bar % 4]
        bf = hz(root)
        for b in range(4):
            tr.add(drum_kick(0.22, 55), bar * 4 + b, 0.75)
            tr.add(drum_hat(0.05, b == 3), bar * 4 + b + 0.5, 0.25)
        tr.add(drum_snare(0.13, 240), bar * 4 + 2, 0.4)
        seq = [0, 7, 12, 7, 0, 7, 10, 12]
        for i, semi in enumerate(seq):
            tr.add(pluck(bf * 4 * 2 ** (semi / 12), 0.25, 0.9, "saw"), bar * 4 + i * 0.5, 0.2)
        tr.add(bass_note(bf, tr.bar * 0.9, "saw", 400, 0.5), bar * 4, 0.5)
    return tr.out(0.18)


def music_ending():
    tr = Track(66, 12, 44)
    for bar in range(12):
        root, q = [("D2", "m7"), ("Bb1", "M7"), ("G1", "m7"), ("A1", "dom7")][bar % 4]
        tr.add(pad_chord(chord_freqs(root, q), tr.bar * 1.1, cutoff=1300, atk=2.2), bar * 4, 0.45)
        tr.add(bass_note(hz(root), tr.bar * 0.95, "sub", 180), bar * 4, 0.5)
    motif = [("D4", 4, 2), ("F4", 6, 2), ("A4", 8, 3), ("G4", 12, 2), ("F4", 14, 2),
             ("D4", 16, 4), ("C4", 24, 2), ("D4", 26, 2), ("A3", 28, 4),
             ("D4", 36, 3), ("E4", 39, 1), ("F4", 40, 6)]
    for name, at, ln in motif:
        tr.add(muted_lead(hz(name), ln * tr.beat, 4.8), at, 0.3)
    return tr.out(0.5)


def sting(kind):
    d = {"success": 1.6, "fail": 1.8, "busted": 2.2, "wasted": 2.6}[kind]
    tr = Track(80, 2, 51)
    if kind == "success":
        for i, nme in enumerate(["F3", "A3", "C4", "F4"]):
            tr.add(pluck(hz(nme), 0.8, 0.5), i * 0.5, 0.4)
        tr.add(pad_chord(chord_freqs("F2", "M7"), 1.4, cutoff=1500, atk=0.1), 1.0, 0.4)
    elif kind == "fail":
        tr.add(muted_lead(hz("D3"), 1.4, 6), 0, 0.4)
        tr.add(muted_lead(hz("Db3"), 1.4, 6), 0.5, 0.35)
        tr.add(bass_note(hz("D1"), 1.6, "sub", 160), 0, 0.5)
    elif kind == "busted":
        tr.add(siren_loop(2.0) * 0.5, 0, 0.6)
        tr.add(drum_kick(0.4, 45), 0, 0.8)
        tr.add(pad_chord(chord_freqs("B1", "m"), 2.0, cutoff=700, atk=0.05), 0.1, 0.5)
    else:
        tr.add(sine(180, 2.4) * env(2.4, 0.01, 1.5, 0.2, 0.8) * 0.5, 0, 0.6)
        tr.add(sine(171, 2.4) * env(2.4, 0.01, 1.5, 0.2, 0.8) * 0.5, 0, 0.5)
        tr.add(onepole_lp_fast(noise(2.0, tr.rng), 300) * env(2.0, 0.01, 1.2, 0.1, 0.7) * 0.5, 0, 0.6)
    return tr.out(0.4)


def studio_sting():
    """D'YOUNGS GAMES logo sting — the sound of the studio card.

    Three movements over ~3.4s: a breath (air + sub drop, felt more than
    heard), a strike (low minor hit under the logo resolving, with a bright
    transient so the card "lands"), and a bell motif that lifts F minor ->
    F major and rings out over a pad into a long room tail. The game itself
    is minor-key; the studio name ends hopeful.
    """
    tr = Track(80, 2, 909)
    keep = int(SR * 3.9)

    # --- movement 1: the breath (0.0 - 0.95s) -----------------------------
    air = bandpass_fast(noise(1.0, tr.rng), 300, 5200)
    air = onepole_lp_fast(air * env(1.0, 0.55, 0.3, 0.5, 0.35) * 0.30, 4200)
    tr.add(air, 0, 0.9)

    # sub drop: 62Hz gliding to 31Hz underneath (body, not pitch)
    tt = t(1.05)
    glide = 62.0 * np.power(0.5, tt / 1.05)
    sub = np.sin(2 * np.pi * np.cumsum(glide) / SR)
    tr.add(sub * env(1.05, 0.30, 0.5, 0.45, 0.4) * 0.85, 0, 0.95)

    # --- movement 2: the strike (0.95s) ----------------------------------
    b = tr.beat
    tr.add(drum_kick(0.55, 44, 1.0), 0.95 / b, 0.95)
    tr.add(pad_chord(chord_freqs("F2", "m"), 1.5, detune=0.006, cutoff=520, atk=0.008),
           0.95 / b, 0.75)
    crack = onepole_hp_fast(noise(0.09, tr.rng), 1800) * env(0.09, 0.001, 0.07, 0.05, 0.02)
    tr.add(crack, 0.95 / b, 0.45)

    # --- movement 3: the bells (1.15s onward, F major lift) ---------------
    for i, nme in enumerate(["F4", "A4", "C5"]):
        tr.add(pluck(hz(nme), 1.5, bright=0.72, wave="tri"), (1.15 + i * 0.19) / b, 0.42)
    tr.add(pluck(hz("F5"), 1.8, bright=0.85, wave="tri"), 1.78 / b, 0.20)
    tr.add(pad_chord(chord_freqs("F2", "M7"), 2.2, detune=0.005, cutoff=1400, atk=0.35),
           1.30 / b, 0.34)

    # mono -> long room tail -> stereo (reverb_simple is mono-only)
    x = reverb_simple(tr.buf[:keep], 1.15, 0.42)
    x = fade(normalize(x, 0.88), 0.02, 0.55)
    return stereo(x, x)


# ================================================================= WILDLIFE =
# Cinder City had 234 sound effects and not one living thing in it. These are
# the creatures: birds on the rooftops, gulls over the harbour, rats in the
# alleys, a dock cat, stray dogs, moths at the neon, and fish breaking the
# water. All synthesized from nothing, like the rest of the score.

def _glide(f0, f1, dur, expo=False):
    """Phase-continuous sine sweeping f0 -> f1. Returns (signal, freq_array)."""
    x = t(dur)
    if expo:
        f = f0 * np.power(max(f1, 1.0) / max(f0, 1.0), x / dur)
    else:
        f = f0 + (f1 - f0) * (x / dur)
    return np.sin(2 * np.pi * np.cumsum(f) / SR), f


def _sawf(f):
    """Sawtooth from an instantaneous-frequency array (phase-continuous)."""
    return 2.0 * ((np.cumsum(f) / SR) % 1.0) - 1.0


def _sinf(f):
    """Sine from an instantaneous-frequency array (phase-continuous).
    lib.sine() takes a SCALAR freq only; gliding pitches need this."""
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def _place(y, seg, at, gain=1.0):
    """Add a SHORT segment into a longer bed at time `at` (seconds).
    numpy refuses to broadcast mismatched lengths, so layering a 0.1 s bubble
    over a 3 s loop must be a slice-assign, never a multiply-by-gate."""
    i0 = int(round(at * SR))
    i0 = max(0, min(i0, len(y)))
    i1 = min(len(y), i0 + len(seg))
    y[i0:i1] += seg[:i1 - i0] * gain
    return y


def bird_chirp(v=0):
    """Small passerine: 2-4 bright FM syllables with gaps between them."""
    rng = np.random.default_rng(1100 + v)
    n_syl = [3, 4, 2][v % 3]
    base = [2700.0, 3300.0, 2150.0][v % 3]
    parts = []
    for _ in range(n_syl):
        d = float(rng.uniform(0.034, 0.066))
        f0 = base * float(rng.uniform(0.86, 1.20))
        f1 = f0 * float(rng.uniform(1.25, 1.95))
        y, fr = _glide(f0, f1, d)
        harm = np.sin(2 * np.pi * np.cumsum(fr * 2.0) / SR)
        y = (y + 0.30 * harm) * env(d, 0.004, 0.018, 0.55, 0.014)
        parts.append(y)
        parts.append(np.zeros(int(rng.uniform(0.012, 0.038) * SR)))
    x = np.concatenate(parts)
    x = onepole_hp_fast(x, 850)
    return fade(normalize(x, 0.50), 0.003, 0.018)


def gull_cry():
    """Harbour gull: a harsh descending squall with a noisy edge."""
    rng = np.random.default_rng(1201)
    d = 0.66
    x = t(d)
    f = 1550.0 * np.power(0.52, x / d)
    f = f * (1.0 + 0.055 * np.sin(2 * np.pi * 21.0 * x))
    y = _sawf(f) * 0.45 + np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.55
    y = y * env(d, 0.020, 0.20, 0.42, 0.24)
    rasp = bandpass_fast(noise(d, rng), 900, 3400) * env(d, 0.02, 0.22, 0.28, 0.22)
    y = bandpass_fast(y + rasp * 0.40, 480, 4400)
    return fade(normalize(y, 0.68), 0.010, 0.09)


def crow_caw():
    """Low corvid caw — two harsh notes, the sound of a rooftop at dusk."""
    rng = np.random.default_rng(1202)
    out = []
    for k, (f0, f1, d) in enumerate([(620.0, 430.0, 0.20), (560.0, 380.0, 0.24)]):
        x = t(d)
        f = f0 + (f1 - f0) * (x / d)
        y = _sawf(f) * 0.6 + _sawf(f * 1.5) * 0.25
        y = y * env(d, 0.008, 0.06, 0.5, 0.07)
        y += bandpass_fast(noise(d, rng), 500, 2400) * env(d, 0.008, 0.07, 0.35, 0.07) * 0.30
        out.append(bandpass_fast(y, 300, 3000))
        if k == 0:
            out.append(np.zeros(int(0.05 * SR)))
    x = np.concatenate(out)
    return fade(normalize(x, 0.66), 0.006, 0.06)


def wing_flutter():
    """A flock going up off a roof: rapid wingbeats with air behind them."""
    rng = np.random.default_rng(1203)
    d = 0.85
    x = t(d)
    beats = np.abs(np.sin(2 * np.pi * 13.0 * x)) ** 3.0
    flap = bandpass_fast(noise(d, rng), 250, 2600) * beats
    air = onepole_lp_fast(noise(d, rng), 700) * env(d, 0.10, 0.4, 0.5, 0.35) * 0.45
    y = flap * env(d, 0.012, 0.30, 0.55, 0.35) * 0.85 + air
    return fade(normalize(y, 0.62), 0.008, 0.12)


def rat_squeak():
    """Very high, very short — heard more at the edge of the night."""
    d = 0.13
    y, fr = _glide(4200.0, 6800.0, d)
    y = (y + 0.4 * np.sin(2 * np.pi * np.cumsum(fr * 1.5) / SR)) * env(d, 0.003, 0.03, 0.4, 0.05)
    y = onepole_hp_fast(y, 2200)
    return fade(normalize(y, 0.34), 0.002, 0.03)


def rat_scuttle():
    """Tiny rapid claws on grit, decelerating as it reaches cover."""
    rng = np.random.default_rng(777)
    d = 0.55
    out = np.zeros(int(SR * d))
    at = 0.0
    gap = 0.030
    while at < d - 0.05:
        tick = bandpass_fast(noise(0.016, rng), 1800, 7000) * env(0.016, 0.001, 0.008, 0.2, 0.006)
        st = int(at * SR)
        out[st:st + len(tick)] += tick * (1.0 - at / d) * 0.55
        at += gap
        gap *= 1.09
    return fade(normalize(out, 0.42), 0.004, 0.06)


def cat_meow():
    """Dock cat: a rising-then-falling formant glide with a rough edge."""
    rng = np.random.default_rng(1204)
    d = 0.78
    x = t(d)
    k = x / d
    f = 380.0 + 260.0 * np.sin(np.pi * np.clip(k * 1.15, 0, 1))
    f = f * (1.0 + 0.020 * np.sin(2 * np.pi * 5.6 * x))
    y = _sawf(f) * 0.5 + np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.35
    # two fixed formants give it a mouth
    y = bandpass_fast(y, 320, 900) * 0.75 + bandpass_fast(y, 900, 2600) * 0.45
    y = y * env(d, 0.055, 0.18, 0.62, 0.26)
    y += bandpass_fast(noise(d, rng), 1400, 4200) * env(d, 0.05, 0.2, 0.2, 0.25) * 0.16
    return fade(normalize(y, 0.60), 0.012, 0.10)


def dog_bark():
    """Stray bark: a pitched burst that drops, with a noisy attack."""
    rng = np.random.default_rng(31)
    out = []
    for i in range(2):
        d = 0.16 if i == 0 else 0.20
        y, fr = _glide(520.0, 210.0, d, expo=True)
        body = (y * 0.6 + _sawf(fr * 0.5) * 0.4) * env(d, 0.004, 0.05, 0.45, 0.07)
        snap = bandpass_fast(noise(d, rng), 700, 3600) * env(d, 0.002, 0.035, 0.12, 0.05)
        out.append(onepole_lp_fast(body + snap * 0.55, 3200))
        if i == 0:
            out.append(np.zeros(int(0.11 * SR)))
    x = np.concatenate(out)
    return fade(normalize(x, 0.72), 0.004, 0.07)


def insect_buzz():
    """Loopable moth/gnat swarm at a neon sign — 3.0 s, wobbles but never
    resolves, so it can sit under a scene without drawing attention."""
    rng = np.random.default_rng(1205)
    d = 3.0
    x = t(d)
    f = 430.0 + 26.0 * np.sin(2 * np.pi * 0.63 * x) + 11.0 * np.sin(2 * np.pi * 1.9 * x)
    y = _sawf(f) * 0.5 + _sawf(f * 2.02) * 0.22 + _sawf(f * 3.01) * 0.10
    y = bandpass_fast(y, 300, 2200)
    # individual wingbeat amplitude flicker
    y = y * (0.62 + 0.38 * np.abs(np.sin(2 * np.pi * 17.0 * x))) ** 1.5
    y = y * env(d, 0.35, 0.6, 0.9, 0.45)
    y += bandpass_fast(noise(d, rng), 2600, 7000) * 0.045
    return fade(normalize(y, 0.30), 0.25, 0.35)


def fish_splash():
    """A fish breaking the harbour surface: a plop, then a spreading ring."""
    rng = np.random.default_rng(5150)
    d = 0.52
    plop_d = 0.075
    plop, pf = _glide(760.0, 190.0, plop_d, expo=True)
    plop = plop * env(plop_d, 0.001, 0.03, 0.25, 0.03) * 0.85
    wash = bandpass_fast(noise(d, rng), 500, 5200)
    wash = wash * env(d, 0.006, 0.16, 0.18, 0.30) * 0.55
    drops = np.zeros(int(SR * d))
    for k in range(7):
        at = float(rng.uniform(0.05, 0.40))
        dd = 0.028
        y, _f = _glide(float(rng.uniform(1400, 2600)), 500.0, dd)
        y = y * env(dd, 0.001, 0.012, 0.15, 0.012) * float(rng.uniform(0.10, 0.30))
        st = int(at * SR)
        drops[st:st + len(y)] += y
    x = np.zeros(int(SR * d))
    x[:len(plop)] += plop
    x += wash + drops
    x = onepole_lp_fast(x, 5200)
    return fade(normalize(x, 0.60), 0.004, 0.14)


def water_lap():
    """Looping harbour wash against stone — 4.0 s of slow surge and hiss."""
    rng = np.random.default_rng(1206)
    d = 4.0
    x = t(d)
    surge = 0.5 + 0.5 * np.sin(2 * np.pi * (1.0 / 3.4) * x - np.pi * 0.5)
    surge = surge ** 1.7
    body = onepole_lp_fast(noise(d, rng), 620) * surge * 0.85
    hiss = bandpass_fast(noise(d, rng), 1400, 6000) * (surge ** 2.2) * 0.30
    y = body + hiss
    y = y * env(d, 0.30, 0.8, 1.0, 0.40)
    return fade(normalize(y, 0.40), 0.30, 0.40)


# ================================================================== TRAINS =
# The Smoke Line: a freight viaduct over the z=-30 arterial. Godot's 3D audio
# handles the Doppler on a moving emitter, so these are written flat and let
# the engine do the pass-by.

def train_horn():
    """Diesel horn: a minor-third pair with a breathy attack and a long
    decay. Two horns slightly detuned is what makes it read as huge."""
    rng = np.random.default_rng(1207)
    d = 2.30
    x = t(d)
    f1, f2 = 233.0, 293.0            # Bb3 / D4 — a minor third apart
    y = np.zeros(int(SR * d))
    for f0, g in ((f1, 0.42), (f2, 0.38), (f1 * 1.005, 0.20), (f2 * 0.996, 0.18)):
        # slight pitch sag as the air pressure drops
        fr = f0 * (1.0 - 0.012 * (x / d))
        osc = _sawf(fr) * 0.45 + np.sin(2 * np.pi * np.cumsum(fr) / SR) * 0.55
        osc = bandpass_fast(osc, f0 * 0.6, f0 * 5.0)
        y += osc * g
    # breath at the attack (short burst laid over the head of the horn)
    bd = 0.22
    breath = bandpass_fast(noise(bd, rng), 200, 1800) * env(bd, 0.01, 0.14, 0.1, 0.06) * 0.30
    y[:len(breath)] += breath
    y = y * env(d, 0.055, 0.30, 0.72, 0.75)
    y = reverb_simple(y, 0.75, 0.22)     # it is coming off a viaduct
    return fade(normalize(y, 0.82), 0.02, 0.30)


def train_rumble():
    """Loopable 4.0 s bed: low rolling rumble + the rhythmic click of wheels
    over rail joints. Kept quiet so it can sit under a scene and swell as the
    train closes."""
    rng = np.random.default_rng(1208)
    d = 4.0
    x = t(d)
    # rolling low end, slowly modulated so it never sounds like a tone
    roll = onepole_lp_fast(noise(d, rng), 150)
    roll = roll * (0.70 + 0.30 * np.sin(2 * np.pi * 0.37 * x))
    # steel resonance riding on top
    steel = bandpass_fast(noise(d, rng), 260, 900) * 0.22
    y = roll * 0.85 + steel
    # rail joints: 8 evenly spaced clicks so the loop point is seamless
    for k in range(8):
        at = k * (d / 8.0)
        cd = 0.055
        clack = bandpass_fast(noise(cd, rng), 900, 4200) * env(cd, 0.001, 0.02, 0.1, 0.03)
        st = int(at * SR)
        y[st:st + len(clack)] += clack * 0.40
    y = y * env(d, 0.10, 0.3, 1.0, 0.10)
    return fade(normalize(y, 0.55), 0.06, 0.06)


def rail_clack():
    """A single wheel over a joint — the sound of a train you cannot see."""
    rng = np.random.default_rng(808)
    d = 0.13
    y = bandpass_fast(noise(d, rng), 700, 5200) * env(d, 0.001, 0.035, 0.12, 0.05)
    y += onepole_lp_fast(noise(d, rng), 220) * env(d, 0.002, 0.06, 0.2, 0.05) * 0.55
    return fade(normalize(y, 0.50), 0.002, 0.03)


def train_brake():
    """Wheel slide / brake squeal on the approach — a long metallic scream."""
    rng = np.random.default_rng(1209)
    d = 1.50
    x = t(d)
    f = 1180.0 + 420.0 * np.sin(2 * np.pi * 3.1 * x) + 260.0 * (x / d)
    y = _sawf(f) * 0.30 + _sawf(f * 1.503) * 0.22 + _sawf(f * 2.011) * 0.14
    y = bandpass_fast(y, 700, 5200)
    y = y * env(d, 0.14, 0.4, 0.5, 0.55)
    y += bandpass_fast(noise(d, rng), 2200, 7000) * env(d, 0.1, 0.5, 0.2, 0.5) * 0.20
    return fade(normalize(y, 0.58), 0.05, 0.25)


# ================================================================== FUEL ===
# Filling stations. A tank filling is the most mundane transaction in the game
# and still has to *sound* like fuel: hose, gurgle, the nozzle's auto-shutoff
# clunk. Written as a seamless loop because the pump runs for as long as the
# player is standing there.

def fuel_pump():
    """Looping fuel flow: a hose bed, a pump motor hum, and rising gurgle."""
    d = 3.0
    x = t(d)
    rng = np.random.default_rng(911)
    # the flow itself: broadband noise shaped into a hollow hose
    flow = bandpass_fast(noise(d, rng), 320, 2600)
    # the motor on top of the pump — a low electrical whine, 50 Hz + 3rd
    hum = sine(50.0, d) * 0.10 + sine(150.0, d) * 0.055 + sine(100.0, d) * 0.04
    hum = onepole_lp_fast(hum, 400)
    # gurgles: air being displaced. Six of them, evenly placed so the loop
    # seam lands between bubbles rather than inside one.
    y = flow * 0.62 + hum
    for k in range(6):
        # evenly spaced so the loop seam falls between bubbles, not in one
        at = (k + 0.5) / 6.0 * d
        gd = 0.11
        gx = t(gd) / gd                      # LOCAL time base, 0..1 over the bubble
        blip = _sinf(np.interp(gx, [0, 1], [240.0, 96.0])) * env(gd, 0.004, 0.05, 0.3, 0.03)
        _place(y, blip, at, 0.34)
        # a little splash of air on each bubble
        splash = bandpass_fast(noise(gd, rng), 1800, 6200) * env(gd, 0.002, 0.04, 0.1, 0.02)
        _place(y, splash, at, 0.20)
    # slow pressure wobble so it never sounds like a tone generator.
    # The periods MUST divide the loop length into whole cycles (3.0/1.5 = 2,
    # 3.0/0.75 = 4) or the modulation itself clicks at every loop point.
    wob = 1.0 + 0.10 * np.sin(2 * np.pi * (1.0 / 1.5) * x) + 0.06 * np.sin(2 * np.pi * (1.0 / 0.75) * x + 1.1)
    y = y * wob
    # a 60 ms fade would duck the loop twice every cycle — keep it minimal so
    # the flow reads as continuous; the bubbles already avoid the seam
    return fade(normalize(y, 0.46), 0.004, 0.004)


def fuel_cap():
    """The cap coming off: a ratchet of thread clicks, then a metal clink."""
    rng = np.random.default_rng(912)
    d = 0.52
    x = t(d)
    y = np.zeros_like(x)
    # three ratchet clicks as the cap unscrews
    for k, at in enumerate([0.00, 0.075, 0.15]):
        cd = 0.030
        click = bandpass_fast(noise(cd, rng), 1400, 6800) * env(cd, 0.001, 0.012, 0.05, 0.008)
        _place(y, click, at, 0.5 - 0.10 * k)
    # the cap dropping clear — a small hollow clink
    cl = 0.20
    _, fcap = _glide(1850.0, 780.0, cl, expo=True)
    clink = _sawf(fcap) * env(cl, 0.001, 0.09, 0.10, 0.05) * 0.42
    clink += bandpass_fast(noise(cl, rng), 2600, 9000) * env(cl, 0.001, 0.03, 0.06, 0.02) * 0.30
    _place(y, clink, 0.22, 1.0)
    return fade(normalize(y, 0.55), 0.003, 0.05)


def nozzle_off():
    """Auto-shutoff clunk: the pump deciding the tank is full before you did."""
    rng = np.random.default_rng(913)
    d = 0.34
    x = t(d)
    # a spring-loaded mechanical thunk — low body + sharp transient
    body = onepole_lp_fast(noise(d, rng), 240) * env(d, 0.002, 0.11, 0.10, 0.10)
    tdrop, _ = _glide(140.0, 62.0, d, expo=True)
    thunk = tdrop * env(d, 0.001, 0.08, 0.06, 0.09) * 0.85
    tick = bandpass_fast(noise(d, rng), 2200, 8000) * env(d, 0.001, 0.014, 0.03, 0.01) * 0.4
    y = body * 0.9 + thunk + tick
    return fade(normalize(y, 0.62), 0.002, 0.07)


def engine_sputter():
    """A dry engine: starter whir, two half-hearted catches, then nothing."""
    rng = np.random.default_rng(914)
    d = 1.40
    x = t(d)
    # starter motor — a whining drill, slightly uneven
    _, fspin = _glide(210.0, 268.0, d)
    _, fspin2 = _glide(420.0, 536.0, d)
    spin = _sawf(fspin) * 0.16 + _sawf(fspin2) * 0.09
    spin = bandpass_fast(spin, 140, 2200)
    # the engine turns over twice and fails to hold either time
    y = np.zeros_like(x)
    for at, lvl in [(0.06, 1.0), (0.62, 0.62)]:
        cd = 0.42
        # 4 firing pulses, the last one dying — that unevenness IS the sound
        for k in range(4):
            pat = at + k * (cd / 5.0)
            pd = 0.075 * (1.0 - 0.16 * k)
            p = onepole_lp_fast(noise(pd, rng), 300) * env(pd, 0.002, 0.05, 0.25, 0.02)
            pdrop, _ = _glide(88.0, 52.0, pd, expo=True)
            p += pdrop * env(pd, 0.002, 0.06, 0.15, 0.02) * 0.8
            _place(y, p, pat, lvl * (1.0 - 0.22 * k))
    # the starter keeps dragging after the engine gives up
    y = y + spin * (0.55 + 0.45 * np.exp(-x / 0.9))
    y = y * env(d, 0.02, 0.9, 1.0, 0.20)
    return fade(normalize(y, 0.60), 0.01, 0.12)


def main():
    print("== LEVERAGE audio forge ==")
    for surf in SURFACES:
        for run in (False, True):
            for v in range(3):
                w(os.path.join(SFX, f"foot_{surf}_{'run' if run else 'walk'}_{v}.wav"),
                  footstep(surf, run, v))
    for name, fn in [
        ("cloth_rustle", lambda: fade(normalize(bandpass_fast(noise(0.15, R), 800, 4000) * env(0.15, 0.01, 0.08, 0.1, 0.06) * 0.3, 0.5))),
        # --- wildlife + water (the living-city layer) ---
        ("bird_chirp_0", lambda: bird_chirp(0)),
        ("bird_chirp_1", lambda: bird_chirp(1)),
        ("bird_chirp_2", lambda: bird_chirp(2)),
        ("gull_cry", gull_cry),
        ("crow_caw", crow_caw),
        ("wing_flutter", wing_flutter),
        ("rat_squeak", rat_squeak),
        ("rat_scuttle", rat_scuttle),
        ("cat_meow", cat_meow),
        ("dog_bark", dog_bark),
        ("insect_buzz", insect_buzz),
        ("fish_splash", fish_splash),
        ("water_lap", water_lap),
        # --- the Smoke Line (freight rail) ---
        ("train_horn", train_horn),
        ("train_rumble", train_rumble),
        ("rail_clack", rail_clack),
        ("train_brake", train_brake),
        # --- filling stations (fuel) ---
        ("fuel_pump", fuel_pump),
        ("fuel_cap", fuel_cap),
        ("nozzle_off", nozzle_off),
        ("engine_sputter", engine_sputter),
        ("dodge_roll", lambda: whoosh(0.3, 400, True)),
        ("jump_effort", lambda: grunt(120, 0.22, 0.5)),
        ("land_thud", lambda: fade(normalize(onepole_lp_fast(noise(0.12, R), 250) * env(0.12, 0.002, 0.08, 0, 0.04) * 0.7 + sine(60, 0.12) * 0.4, 0.8))),
        ("whoosh_light", lambda: whoosh(0.18, 500)),
        ("whoosh_heavy", lambda: whoosh(0.3, 260, True)),
        ("whoosh_kick", lambda: whoosh(0.22, 380, True)),
        ("punch_hit", lambda: punch_hit(False)),
        ("punch_hit_heavy", lambda: punch_hit(True)),
        ("kick_hit", lambda: fade(normalize(M(punch_hit(True) * 0.8, whoosh(0.12, 700) * 0.5), 0.9))),
        ("block_hit", block_hit),
        ("parry_clang", parry_clang),
        ("grunt_m_hit", lambda: grunt(100, 0.3, 0.8)),
        ("grunt_f_hit", lambda: grunt(170, 0.28, 0.8)),
        ("grunt_m_down", lambda: grunt(85, 0.5, 0.9)),
        ("body_fall", body_fall),
        ("slam", slam),
        ("grab_swoosh", lambda: whoosh(0.25, 300, True)),
        ("shot_pistol", lambda: gunshot("pistol")),
        ("shot_smg", lambda: gunshot("smg")),
        ("shot_shotgun", lambda: gunshot("shotgun")),
        ("shot_rifle", lambda: gunshot("rifle")),
        ("dry_fire", dry_fire),
        ("reload_magout", lambda: reload_step("magout")),
        ("reload_magin", lambda: reload_step("magin")),
        ("reload_slide", lambda: reload_step("slide")),
        ("shell_drop", shell_drop),
        ("imp_concrete", lambda: bullet_impact("concrete")),
        ("imp_metal", lambda: bullet_impact("metal")),
        ("imp_glass", lambda: bullet_impact("glass")),
        ("imp_wood", lambda: bullet_impact("wood")),
        ("glass_break", glass_break),
        ("veh_engine_sedan", lambda: engine_loop("sedan")),
        ("veh_engine_muscle", lambda: engine_loop("muscle")),
        ("veh_engine_van", lambda: engine_loop("van")),
        ("veh_engine_bike", lambda: engine_loop("bike")),
        ("veh_skid", skid_loop),
        ("veh_crash_light", lambda: crash("light")),
        ("veh_crash_heavy", lambda: crash("heavy")),
        ("veh_horn", lambda: horn(0.5)),
        ("veh_horn_long", lambda: horn(1.2)),
        ("veh_door_open", lambda: door_sound("wood", True)),
        ("veh_door_close", lambda: door_sound("wood", False)),
        ("veh_start", engine_start),
        ("siren_loop", siren_loop),
        ("police_radio", lambda: fade(normalize(M(radio_static(0.6) * 0.5, bandpass_fast(noise(0.5, R), 900, 2600) * env(0.5, 0.05, 0.3, 0.2, 0.15) * 0.2), 0.5))),
        ("ui_click", ui_click), ("ui_back", ui_back), ("ui_confirm", ui_confirm),
        ("ui_error", ui_error), ("ui_notify", ui_notify),
        ("phone_ring", phone_ring), ("phone_msg", phone_msg),
        ("door_wood_open", lambda: door_sound("wood", True)),
        ("door_wood_close", lambda: door_sound("wood", False)),
        ("door_metal_open", lambda: door_sound("metal", True)),
        ("door_metal_close", lambda: door_sound("metal", False)),
        ("shop_bell", shop_bell), ("cash", cash_register),
        ("rain_loop", lambda: rain_loop(4.0)),
        ("thunder_1", lambda: thunder(0)), ("thunder_2", lambda: thunder(1)), ("thunder_3", lambda: thunder(2)),
        ("traffic_loop", lambda: traffic_loop(4.0)),
        ("crowd_loop", lambda: crowd_loop(4.0)),
        ("fire_crackle", lambda: fire_crackle(2.0)),
        ("steam_hiss", lambda: steam_hiss(1.2)),
        ("alarm_loop", lambda: alarm_loop(2.0)),
        ("radio_static", lambda: radio_static(1.0)),
    ]:
        w(os.path.join(SFX, name + ".wav"), fn())
    for name, f0, br, st in VOICES:
        for v in range(3):
            w(os.path.join(VOX, f"{name}_{v}.wav"), vox_blip(name, f0, br, st, v))
    tracks = {
        "music_menu": music_menu,
        "music_explore_kiln": lambda: district_track("kiln"),
        "music_explore_docks": lambda: district_track("docks"),
        "music_explore_furnace": lambda: district_track("furnace"),
        "music_explore_neon": lambda: district_track("neon"),
        "music_explore_slag": lambda: district_track("slag"),
        "music_explore_heights": lambda: district_track("heights"),
        "music_tension": music_tension,
        "music_combat": music_combat,
        "music_chase": music_chase,
        "music_ending": music_ending,
        "sting_success": lambda: sting("success"),
        "sting_fail": lambda: sting("fail"),
        "sting_busted": lambda: sting("busted"),
        "sting_wasted": lambda: sting("wasted"),
        "studio_sting": studio_sting,
    }
    for name, fn in tracks.items():
        w(os.path.join(MUS, name + ".wav"), fn(), st=True)
        # mobile-friendly delivery format (source-of-truth = this forge script)
        try:
            import soundfile as sf
            data, sr = sf.read(os.path.join(MUS, name + ".wav"))
            sf.write(os.path.join(MUS, name + ".ogg"), data, sr,
                     format="OGG", subtype="VORBIS")
            os.remove(os.path.join(MUS, name + ".wav"))
        except ImportError:
            pass
    n_sfx = len(os.listdir(SFX))
    n_mus = len(os.listdir(MUS))
    n_vox = len(os.listdir(VOX))
    print(f"done: {n_sfx} sfx, {n_mus} music, {n_vox} vox")


if __name__ == "__main__":
    main()
