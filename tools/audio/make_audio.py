#!/usr/bin/env python3
"""Generates every sound in the game from code (original, royalty-free).

    python3 tools/audio/make_audio.py   ->  assets/audio/*.ogg

Music: "Golden Hour Line" - 95 BPM laid-back tropical groove (Rhodes-style
electric piano chords, steel-drum lead, round bass, soft kick, rim, shaker),
32 bars, seamless loop. Ambience: ocean swells, light wind (seamless loops).
Effects: line load creak, takeoff twang, landing thud, trick whoosh, combo
chime, super rebound rise, bail.
"""
import os
import subprocess
import numpy as np
from scipy import signal
from scipy.io import wavfile

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")
rng = np.random.default_rng(7)


def write(name, x, quality=5):
    os.makedirs(OUT, exist_ok=True)
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) + 1e-9
    x = x / peak * 0.89
    wav = os.path.join("/tmp", name + ".wav")
    if x.ndim == 2:
        data = (x.T * 32767).astype(np.int16)
    else:
        data = (x * 32767).astype(np.int16)
    wavfile.write(wav, SR, data)
    ogg = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis",
                    "-q:a", str(quality), ogg], check=True)
    print("wrote", os.path.relpath(ogg), "%.1fs" % (data.shape[0] / SR))


def t_(dur):
    return np.arange(int(dur * SR)) / SR


def env_adsr(n, a=0.005, d=0.1, s=0.6, r=0.2):
    e = np.ones(n) * s
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = max(na, 1)
    e[:na] = np.linspace(0, 1, na)
    e[na:na + nd] = np.linspace(1, s, len(e[na:na + nd]))
    if nr > 0 and nr < n:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def lowpass(x, fc, order=2):
    b, a = signal.butter(order, fc / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def highpass(x, fc, order=2):
    b, a = signal.butter(order, fc / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bandpass(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), hi / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def loop_seamless(x, fade=1.0):
    """Crossfade the tail into the head so the file loops without a click."""
    nf = int(fade * SR)
    head, body, tail = x[:nf], x[nf:-nf] if nf else x, x[-nf:]
    w = np.linspace(0, 1, nf)
    mixed = tail * (1 - w) + head * w
    return np.concatenate([mixed, body]) if x.ndim == 1 else None


# ---------------------------------------------------------------- instruments

def epiano(f, dur):
    t = t_(dur)
    mod = np.sin(2 * np.pi * f * 1.0 * t) * 1.2 * np.exp(-t * 3.0)
    x = np.sin(2 * np.pi * f * t + mod)
    x += 0.25 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 4)
    x *= np.exp(-t * 1.1) * env_adsr(len(t), 0.004, 0.05, 1.0, 0.15)
    x *= 1 + 0.15 * np.sin(2 * np.pi * 4.5 * t)   # gentle tremolo
    return x


def steel_drum(f, dur):
    t = t_(dur)
    partials = [(1.0, 1.0), (2.0, 0.5), (2.98, 0.32), (4.05, 0.18), (5.2, 0.08)]
    x = sum(a * np.sin(2 * np.pi * f * k * t) * np.exp(-t * (2.5 + 1.6 * k)) for k, a in partials)
    x *= env_adsr(len(t), 0.002, 0.02, 1.0, 0.05)
    return x


def bass(f, dur):
    t = t_(dur)
    x = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * 2 * f * t)
    x = np.tanh(1.6 * x)
    return lowpass(x, 600) * env_adsr(len(t), 0.006, 0.12, 0.7, 0.06)


def kick(dur=0.35):
    t = t_(dur)
    f = 45 + 90 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 9)


def rim(dur=0.08):
    t = t_(dur)
    x = bandpass(rng.standard_normal(len(t)), 1400, 4200) * np.exp(-t * 70)
    return x + 0.5 * np.sin(2 * np.pi * 1700 * t) * np.exp(-t * 90)


def shaker(dur=0.09):
    t = t_(dur)
    return highpass(rng.standard_normal(len(t)), 6000) * np.exp(-t * 45) * 0.5


def place(buf, x, at, gain=1.0, pan=0.0):
    i = int(at * SR)
    n = min(len(x), buf.shape[1] - i)
    if n <= 0:
        return
    l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    buf[0, i:i + n] += x[:n] * gain * l
    buf[1, i:i + n] += x[:n] * gain * r


# ---------------------------------------------------------------- music

def make_music():
    bpm = 95.0
    beat = 60.0 / bpm
    bars = 32
    total = bars * 4 * beat
    tail = 3.0
    buf = np.zeros((2, int((total + tail) * SR)))
    # Cmaj7 - Am7 - Fmaj7 - G7sus/G   (in D: transpose +2 for a sunnier key)
    tr = 2
    prog = [
        [48, 52, 55, 59], [45, 52, 55, 60], [41, 52, 57, 60], [43, 50, 53, 59],
    ]
    roots = [36, 33, 29, 31]
    # pentatonic steel-drum motifs (scale degrees in semitones over the root key)
    penta = [0, 2, 4, 7, 9, 12, 14, 16]
    motif_a = [(0, 4), (1.0, 7), (1.5, 9), (2.5, 7), (3.0, 4)]
    motif_b = [(0, 12), (0.5, 9), (1.0, 7), (2.0, 9), (2.5, 7), (3.5, 4)]
    motif_c = [(0, 2), (0.75, 4), (1.5, 7), (2.0, 4), (3.0, 2)]
    motifs = [motif_a, motif_b, motif_a, motif_c]
    for bar in range(bars):
        t0 = bar * 4 * beat
        ci = bar % 4
        section = bar // 8      # 0 intro-ish, 1 groove, 2 lead, 3 groove + lead
        # chords: off-beat skank on 2 and 4 plus a held pad on 1
        for b, g in [(0, 0.35), (1.5, 0.22), (3.0, 0.25)]:
            for k, n in enumerate(prog[ci]):
                place(buf, epiano(midi(n + tr + 12), 1.6), t0 + b * beat, g * 0.5, pan=-0.3 + 0.2 * k)
        # bass: root, fifth, octave walk
        if section >= 1 or bar >= 4:
            r = roots[ci] + tr
            for b, n, d in [(0, r, 0.9), (1.5, r, 0.4), (2.0, r + 7, 0.5), (3.0, r + 12, 0.4), (3.5, r + 7, 0.4)]:
                place(buf, bass(midi(n), d * beat * 1.8), t0 + b * beat, 0.55)
        # drums
        if bar >= 2:
            for b in [0, 2.5]:
                place(buf, kick(), t0 + b * beat, 0.8)
            for b in [1, 3]:
                place(buf, rim(), t0 + b * beat, 0.32, pan=0.2)
            for s in range(8):
                g = 0.18 if s % 2 else 0.1
                place(buf, shaker(), t0 + s * beat / 2 + (0.02 if s % 2 else 0), g, pan=0.5)
        # lead
        if section in (2, 3) or (section == 1 and bar % 2 == 1):
            for b, deg in motifs[ci]:
                n = 60 + tr + deg
                place(buf, steel_drum(midi(n), 1.2), t0 + b * beat, 0.42, pan=0.25)
                place(buf, steel_drum(midi(n), 1.2), t0 + b * beat + 0.75 * beat, 0.08, pan=-0.4)  # echo
    # wrap the reverb/decay tail to the start so the loop is seamless
    n_total = int(total * SR)
    wrapped = buf[:, :n_total].copy()
    wrapped[:, :buf.shape[1] - n_total] += buf[:, n_total:]
    # soft warmth: gentle low-pass + light glue compression
    wrapped = np.vstack([lowpass(ch, 9000) for ch in wrapped])
    wrapped = np.tanh(wrapped / (np.max(np.abs(wrapped)) * 0.8)) * 0.9
    write("music_golden_hour_line", wrapped)


# ---------------------------------------------------------------- ambience

def make_ocean():
    dur = 32.0
    t = t_(dur)
    noise = rng.standard_normal(len(t))
    brown = np.cumsum(noise)
    brown = highpass(brown - np.mean(brown), 30)
    brown /= np.max(np.abs(brown))
    hiss = bandpass(rng.standard_normal(len(t)), 800, 6000)
    # waves: swells every ~6-8 s, periodic over the loop length
    swell = np.zeros(len(t))
    for k in [4, 5, 7]:
        swell += np.clip(np.sin(2 * np.pi * k * t / dur + k), 0, 1) ** 3
    swell = swell / swell.max()
    x = brown * (0.35 + 0.65 * swell) + hiss * 0.25 * swell ** 2
    x = lowpass(x, 5000)
    x = loop_seamless(x, 2.0)
    write("ambience_ocean", np.vstack([x, np.roll(x, int(0.013 * SR))]))


def make_wind():
    dur = 24.0
    t = t_(dur)
    x = bandpass(rng.standard_normal(len(t)), 250, 1800)
    gust = 0.4 + 0.6 * (0.5 + 0.5 * np.sin(2 * np.pi * 3 * t / dur)) * (0.5 + 0.5 * np.sin(2 * np.pi * 5 * t / dur + 1))
    x = loop_seamless(x * gust, 2.0)
    write("ambience_wind", np.vstack([x, np.roll(x, int(0.02 * SR))]))


# ---------------------------------------------------------------- effects

def make_effects():
    # line load: low creak of the webbing taking weight
    t = t_(0.35)
    f = 85 - 25 * t / 0.35
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)
    x += 0.3 * bandpass(rng.standard_normal(len(t)), 150, 600) * np.exp(-t * 14)
    write("sfx_line_load", x)
    # takeoff: plucked webbing twang (Karplus-Strong) + short air
    n = int(0.6 * SR)
    period = int(SR / 98)
    ks = rng.uniform(-1, 1, period)
    out = np.zeros(n)
    for i in range(n):
        out[i] = ks[i % period]
        ks[i % period] = 0.996 * 0.5 * (ks[i % period] + ks[(i + 1) % period])
    t = t_(0.6)
    out = out * np.exp(-t * 5) + 0.2 * bandpass(rng.standard_normal(n), 400, 2500) * np.exp(-t * 12)
    write("sfx_takeoff", out)
    # landing: thud + webbing slap
    t = t_(0.4)
    f = 55 + 70 * np.exp(-t * 30)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 10)
    x += 0.45 * bandpass(rng.standard_normal(len(t)), 300, 3000) * np.exp(-t * 40)
    write("sfx_landing", x)
    # trick: air whoosh (band-pass sweep)
    t = t_(0.5)
    noise = rng.standard_normal(len(t))
    x = np.zeros(len(t))
    segs = 20
    for s in range(segs):
        a, b = s * len(t) // segs, (s + 1) * len(t) // segs
        c = 400 + 2600 * np.sin(np.pi * s / segs)
        x[a:b] = bandpass(noise, c * 0.7, c * 1.3)[a:b]
    x *= np.sin(np.pi * t / 0.5) ** 2
    write("sfx_trick", x)
    # combo: bright chime arpeggio (D major add9)
    buf = np.zeros((2, int(1.4 * SR)))
    for k, n in enumerate([74, 78, 81, 86]):
        place(buf, steel_drum(midi(n), 1.2), k * 0.07, 0.6, pan=-0.3 + 0.2 * k)
    write("sfx_combo", buf)
    # super rebound: rising sweep into a chord hit
    t = t_(1.3)
    f = 120 * 2 ** (3.0 * np.clip(t / 0.8, 0, 1))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.clip(t / 0.8, 0, 1) * (t < 0.85)
    x += 0.4 * bandpass(rng.standard_normal(len(t)), 1500, 7000) * np.clip(t / 0.8, 0, 1) ** 2 * (t < 0.85)
    hit = np.zeros(len(t))
    for n in [62, 69, 74, 78]:
        h = steel_drum(midi(n), 0.5)
        hit[int(0.8 * SR):int(0.8 * SR) + len(h)] += h[:len(t) - int(0.8 * SR)]
    write("sfx_super_rebound", x * 0.6 + hit * 0.5)
    # bail: descending wobble + soft crash
    t = t_(0.8)
    f = 520 * 2 ** (-2.0 * t / 0.8) * (1 + 0.05 * np.sin(2 * np.pi * 9 * t))
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 2.5) * 0.5
    x += 0.5 * lowpass(rng.standard_normal(len(t)), 900) * np.exp(-((t - 0.55) * 14) ** 2)
    write("sfx_bail", x)


if __name__ == "__main__":
    make_effects()
    make_ocean()
    make_wind()
    make_music()
