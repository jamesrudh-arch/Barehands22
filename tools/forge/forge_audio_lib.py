"""forge_audio_lib — tiny DSP toolkit for LEVERAGE's original audio.

Everything is synthesized from oscillators/noise — no sampled material.
44.1 kHz float32 pipelines, WAV16 export.
"""
import numpy as np
import wave
import os

SR = 44100


def t(dur):
    return np.arange(int(SR * dur)) / SR


def env(dur, a=0.005, d=0.05, s=0.7, r=0.1, sustain_dur=None):
    """ADSR-ish envelope; total length = dur."""
    n = int(SR * dur)
    e = np.zeros(n)
    a_n = int(SR * a)
    d_n = int(SR * d)
    r_n = int(SR * r)
    if a_n + d_n + r_n > n:
        a_n, d_n, r_n = n // 6, n // 6, n // 3
    s_n = n - a_n - d_n - r_n
    e[:a_n] = np.linspace(0, 1, a_n)
    e[a_n:a_n + d_n] = np.linspace(1, s, d_n)
    e[a_n + d_n:a_n + d_n + s_n] = s
    tail = np.linspace(s, 0, r_n)
    e[-r_n:] = tail
    return e


def sine(freq, dur, phase=0.0):
    return np.sin(2 * np.pi * freq * t(dur) + phase)


def saw(freq, dur):
    x = (t(dur) * freq) % 1.0
    return 2 * x - 1


def square(freq, dur, duty=0.5):
    return (((t(dur) * freq) % 1.0) < duty).astype(float) * 2 - 1


def tri(freq, dur):
    x = (t(dur) * freq) % 1.0
    return 4 * np.abs(x - 0.5) - 1


def noise(dur, rng=None, color="white"):
    n = rng or np.random.default_rng(0)
    w = n.standard_normal(int(SR * dur))
    if color == "white":
        return w
    if color == "pink":
        # Voss-McCartney-ish: filter white
        b = np.array([0.049922035, -0.095993537, 0.050612699, -0.004408786])
        a = np.array([1, -2.494956002, 2.017265875, -0.522189400])
        return _filter(w, b, a)
    if color == "brown":
        return np.cumsum(w) / (SR * 0.5)
    return w


def _filter(x, b, a):
    from scipy_stub import lfilter  # not used; fallback below
    return x


def onepole_lp(x, cutoff):
    """Simple one-pole lowpass."""
    rc = 1.0 / (2 * np.pi * cutoff)
    dt = 1.0 / SR
    alpha = dt / (rc + dt)
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):  # slow but assets are short
        acc += alpha * (x[i] - acc)
        y[i] = acc
    return y


def onepole_lp_fast(x, cutoff):
    """Vectorized-ish lowpass via FFT (adequate for asset baking)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    H = 1.0 / (1.0 + (f / max(cutoff, 1.0)) ** 2)
    return np.fft.irfft(X * H, len(x))


def onepole_hp_fast(x, cutoff):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    H = (f / max(cutoff, 1.0)) ** 2 / (1.0 + (f / max(cutoff, 1.0)) ** 2)
    return np.fft.irfft(X * H, len(x))


def bandpass_fast(x, lo, hi):
    return onepole_hp_fast(onepole_lp_fast(x, hi), lo)


def mix(*tracks):
    n = max(len(a) for a in tracks)
    out = np.zeros(n)
    for a in tracks:
        out[:len(a)] += a
    return out


def stereo(l, r=None):
    if r is None:
        r = l
    n = max(len(l), len(r))
    s = np.zeros((n, 2))
    s[:len(l), 0] = l
    s[:len(r), 1] = r
    return s


def delay(x, secs, fb=0.3, mixw=0.35):
    d = int(secs * SR)
    y = x.copy()
    buf = np.zeros(len(x) + d * 8)
    buf[:len(x)] = x
    acc = x.copy()
    for k in range(1, 6):
        off = d * k
        g = fb ** k
        seg = np.zeros(len(x))
        end = min(len(x), len(buf) - off)
        if end > 0:
            seg[:end] = buf[off:off + end] * g
        acc += seg * mixw
    return acc


def reverb_simple(x, secs=0.35, mixw=0.25):
    """Cheap comb+allpass-ish: 3 delays, good enough for SFX beds."""
    y = x.copy()
    y += delay(x, secs * 0.37, 0.42, mixw)
    y += delay(x, secs * 0.61, 0.36, mixw * 0.8)
    y += delay(x, secs * 1.0, 0.3, mixw * 0.6)
    return y


def normalize(x, peak=0.9):
    m = np.max(np.abs(x))
    if m < 1e-9:
        return x
    return x * (peak / m)


def fade(x, fi=0.01, fo=0.02):
    y = np.asarray(x).copy()
    a = int(SR * fi)
    b = int(SR * fo)
    nd = y.ndim
    if a and a < len(y):
        ramp = np.linspace(0, 1, a)
        y[:a] *= ramp[:, None] if nd == 2 else ramp
    if b and b < len(y):
        ramp = np.linspace(1, 0, b)
        y[-b:] *= ramp[:, None] if nd == 2 else ramp
    return y


def write_wav(path, x, sr=SR, stereo_=False):
    d = np.asarray(x, dtype=np.float64)
    if stereo_:
        d = np.clip(d, -1, 1)
        pcm = (d * 32767).astype(np.int16)
    else:
        d = np.clip(d, -1, 1)
        pcm = (d * 32767).astype(np.int16)
        pcm = pcm[:, None]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(2 if stereo_ else 1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


# ------------------------------------------------------------- musical ----
NOTE = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5,
        "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}


def hz(name):
    """e.g. 'A2' -> Hz."""
    n = NOTE[name[:-1]]
    octv = int(name[-1])
    midi = (octv + 1) * 12 + n
    return 440.0 * 2 ** ((midi - 69) / 12)


def chord_freqs(root, quality="m7"):
    r = hz(root)
    iv = {"m": [0, 3, 7], "M": [0, 4, 7], "m7": [0, 3, 7, 10], "M7": [0, 4, 7, 11],
          "dom7": [0, 4, 7, 10], "sus": [0, 5, 7], "dim": [0, 3, 6],
          "m9": [0, 3, 7, 10, 14], "m11": [0, 3, 7, 10, 14, 17]}[quality]
    return [r * 2 ** (i / 12) for i in iv]
