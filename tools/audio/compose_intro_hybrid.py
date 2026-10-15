"""Original hybrid electronic-orchestral score for the intro cinematic (212 s).

Original material in the general style of dark synth-orchestral film scores (analog synth
bass and pads, pumping four-on-the-floor drums, risers, brass, strings and choir). It does
not quote or arrange any existing piece.

Timeline (matches scripts/intro/intro.gd):
  0 - 78.5    despair: cold synth pads + grieving strings, a ticking low pulse whose filter
              slowly opens, heartbeat kick, a noise riser into the climax
  78.5 - 80   silence
  80 - 140    the drop / hope: sub impact, pumping 16th synth bass, kick + snare, arps,
              brass stabs, choir; heroic theme from 112; B-flat major arrival at 136
  140 - 212   the last stand: half-time standoff, horn call and charge, clash into slow
              motion, battle fury, solo-violin breakdown, final surge, the citadel falls,
              B-flat major victory and title

Usage: python3 tools/audio/compose_intro_hybrid.py out.wav   (then master + encode, see
compose_intro.py)
"""
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, fftconvolve, sosfilt

SR = 44100
DUR = 212.0
N = int(SR * DUR)
BEAT = 0.5  # 120 bpm
rng = np.random.default_rng(1982)

orch = np.zeros((2, N))      # strings / brass / choir
synth = np.zeros((2, N))     # synth bass, pads, arps (sidechained to the kick)
drums = np.zeros((2, N))
send = np.zeros((2, N))      # reverb send
duck = np.ones(N)            # sidechain gain


def mtof(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def place(bus, sig, t0, pan=0.0, rev=0.3, gain=1.0):
    i0 = int(t0 * SR)
    if i0 >= N or i0 < 0:
        return
    sig = sig[: N - i0] * gain
    a = (pan + 1.0) * np.pi / 4.0
    l, r = np.cos(a), np.sin(a)
    bus[0, i0:i0 + len(sig)] += sig * l
    bus[1, i0:i0 + len(sig)] += sig * r
    send[0, i0:i0 + len(sig)] += sig * l * rev
    send[1, i0:i0 + len(sig)] += sig * r * rev


def env(n, dur, attack, release, curve=1.5):
    t = np.arange(n) / SR
    e = np.clip(t / max(attack, 1e-3), 0, 1) ** curve
    return e * np.where(t > dur, np.clip(1.0 - (t - dur) / max(release, 1e-3), 0, 1), 1.0)


def lowpass(x, cutoff, order=2):
    return sosfilt(butter(order, min(cutoff, SR * 0.45), fs=SR, output="sos"), x)


def saw(freq, n, detune_cents=0.0, phase=None):
    t = np.arange(n) / SR
    f = freq * 2 ** (detune_cents / 1200)
    ph = (f * t + (rng.random() if phase is None else phase)) % 1.0
    s = 2.0 * ph - 1.0
    return s


# ------------------------------------------------------------------ instruments

def bowed(freq, dur, amp, attack=1.0, release=1.6, vib=0.005, bright=1.25, voices=4, spread=9.0):
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    kmax = max(1, min(24, int(9000 / freq)))
    for v in range(voices):
        cents = (v - (voices - 1) / 2) * spread / max(voices - 1, 1) * 2
        f = freq * 2 ** (cents / 1200)
        mod = 1 + vib * np.sin(2 * np.pi * (5.0 + 0.4 * rng.random()) * t + rng.random() * 6.28) * np.clip(t / 1.2, 0, 1)
        ph = 2 * np.pi * np.cumsum(f * mod) / SR + rng.random() * 6.28
        for k in range(1, kmax + 1):
            out += np.sin(k * ph) / k ** bright
    return out * env(n, dur, attack, release) * amp / voices


def choir(freq, dur, amp, attack=1.2, release=2.0):
    src = bowed(freq, dur, 1.0, attack, release, vib=0.003, bright=0.9, voices=5, spread=14)
    out = np.zeros_like(src)
    for lo, hi, g in ((650, 950, 1.0), (1000, 1300, 0.6), (2500, 3100, 0.25)):
        out += sosfilt(butter(2, [lo, hi], btype="band", fs=SR, output="sos"), src) * g
    return out * amp


def brass(freq, dur, amp, attack=0.15, release=0.6):
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    kmax = max(1, min(20, int(7000 / freq)))
    ph = 2 * np.pi * np.cumsum(freq * (1 + 0.002 * np.sin(2 * np.pi * 5.5 * t))) / SR
    e = env(n, dur, attack, release, curve=1.1)
    dark = sum(np.sin(k * ph) / k ** 2.2 for k in range(1, kmax + 1))
    bright = sum(np.sin(k * ph) / k ** 1.1 for k in range(1, kmax + 1))
    return (dark * (1 - e * 0.6) + bright * e * 0.6) * e * amp


def synth_pad(freq, dur, amp, cutoff=1800, attack=1.5, release=2.0):
    n = int((dur + release) * SR)
    s = sum(saw(freq, n, c) for c in (-11, -4, 3, 10)) / 4
    s = lowpass(lowpass(s, cutoff), cutoff * 1.3)
    return s * env(n, dur, attack, release) * amp


def synth_bass(freq, dur, amp, cutoff=600, accent=1.0):
    """Analog-style bass note: two detuned saws + sub sine, filter envelope."""
    n = int((dur + 0.05) * SR)
    t = np.arange(n) / SR
    s = (saw(freq, n, -6, 0.0) + saw(freq, n, 6, 0.3)) * 0.5
    dark = lowpass(s, cutoff * 0.5, 2)
    bright = lowpass(s, cutoff * (1.5 + accent), 2)
    fenv = np.exp(-t * 18)
    out = dark * (1 - fenv) + bright * fenv
    out += np.sin(2 * np.pi * freq * t) * 0.7  # sub
    a = np.clip(t / 0.004, 0, 1) * np.clip((dur + 0.05 - t) / 0.05, 0, 1)
    return out * a * amp


def arp_note(freq, amp, length=0.2):
    n = int(length * SR)
    t = np.arange(n) / SR
    ph = 2 * np.pi * freq * t
    s = sum(np.sin(k * ph) / k for k in (1, 3, 5, 7, 9))  # square-ish
    s = lowpass(s, 3500)
    return s * np.exp(-t * 14) * np.clip(t / 0.003, 0, 1) * amp


def lead(freq, dur, amp, release=0.8):
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    mod = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t) * np.clip(t / 0.4, 0, 1)
    ph = np.cumsum(freq * mod) / SR
    s = (2 * (ph % 1.0) - 1) * 0.5 + (2 * ((ph * 1.005 + 0.3) % 1.0) - 1) * 0.5
    s = lowpass(s, 4200)
    return s * env(n, dur, 0.05, release, curve=1.0) * amp


def kick(amp):
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    f = 45 + 110 * np.exp(-t * 35)
    s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 6.5)
    click = lowpass(rng.standard_normal(n), 3000) * np.exp(-t * 300) * 0.4
    return np.tanh((s + click) * 1.6) * amp


def snare(amp):
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    noise = sosfilt(butter(2, [1500, 8000], btype="band", fs=SR, output="sos"), rng.standard_normal(n)) * np.exp(-t * 14)
    tone = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 25)
    return (noise * 0.9 + tone * 0.6) * amp


def hat(amp):
    n = int(0.08 * SR)
    t = np.arange(n) / SR
    return sosfilt(butter(2, 7000, btype="high", fs=SR, output="sos"), rng.standard_normal(n)) * np.exp(-t * 60) * amp


def tom(amp, freq=80):
    n = int(1.2 * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * np.cumsum(freq * (1 + 0.6 * np.exp(-t * 25))) / SR) * np.exp(-t * 5)
    s += lowpass(rng.standard_normal(n), 300) * np.exp(-t * 18) * 0.7
    return s * amp


def boom(amp):
    n = int(6 * SR)
    t = np.arange(n) / SR
    f = 55 * np.exp(-t * 0.25) + 22
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 0.8)
    noise = lowpass(rng.standard_normal(n), 900) * np.exp(-t * 5)
    return (sub + noise * 0.7) * amp


def riser(seconds, amp):
    """Filtered noise sweeping up plus a rising tone."""
    n = int(seconds * SR)
    t = np.arange(n) / SR
    u = t / seconds
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    bands = 12
    for b in range(bands):
        lo = 200 * (40 ** (b / bands))
        band = sosfilt(butter(2, [lo, lo * 1.6], btype="band", fs=SR, output="sos"), noise)
        w = np.exp(-((u * bands - b) ** 2) / 4.0)
        out += band * w
    tone = np.sin(2 * np.pi * np.cumsum(110 * 2 ** (u * 3)) / SR) * 0.25
    return (out + tone) * u ** 2 * amp


def heartbeat(t0, seconds, amp):
    k = 0.0
    while k < seconds:
        place(drums, kick(amp), t0 + k, rev=0.4)
        place(drums, kick(amp * 0.6), t0 + k + 0.26, rev=0.4)
        k += 1.2


# ------------------------------------------------------------------ harmony

TRIADS = {
    "Bbm": [58, 61, 65], "Gb": [54, 58, 61], "Db": [61, 65, 68], "Ab": [56, 60, 63],
    "Bb": [58, 62, 65], "Ebm": [63, 66, 70], "F": [57, 60, 65],
}
BASS = {"Bbm": 34, "Gb": 30, "Db": 37, "Ab": 32, "Bb": 34, "Ebm": 39, "F": 29}

CHORDS_A = [("Bbm", 46), ("Gb", 42), ("Ebm", 39), ("F", 41), ("Bbm", 46), ("Gb", 42), ("Ab", 44), ("Db", 37),
            ("Gb", 42), ("Ebm", 39), ("Bbm", 41), ("F", 41), ("F", 41), ("Bbm", 46), ("Gb", 42), ("Db", 37),
            ("Ab", 44), ("Ebm", 39), ("F", 41)]
MELODY_A = [[66, 70], [69, 72], [73, 72], [70, 66], [68, 72], [73, 77], [78, 77], [75, 73],
            [73, 77], [77, 82], [81, 77], [77, 78], [78, 82], [80, 85], [84, 80], [82, 85], [84, None]]


def bass_line(t0, name, seconds, amp, cutoff, sixteenths=True, pattern=(0, 0, 12, 0, 0, 12, 0, 7)):
    step = BEAT / 4 if sixteenths else BEAT / 2
    root = BASS[name] + 12
    for s in range(int(seconds / step)):
        m = root + pattern[s % len(pattern)]
        place(synth, synth_bass(mtof(m), step * 0.85, amp * (1.0 if s % 4 == 0 else 0.75), cutoff,
                                accent=1.0 if s % 4 == 0 else 0.3), t0 + s * step, 0.0, rev=0.05)


def arp(t0, name, seconds, amp, octave=12):
    tri = TRIADS[name]
    seq = [0, 1, 2, 3, 2, 1, 2, 3]
    step = BEAT / 4
    for s in range(int(seconds / step)):
        idx = seq[s % 8]
        m = tri[idx % 3] + (12 if idx == 3 else 0) + octave
        sig = arp_note(mtof(m), amp)
        place(synth, sig, t0 + s * step, -0.3 if s % 2 else 0.3, rev=0.25)
        place(synth, sig * 0.35, t0 + s * step + BEAT * 0.75, 0.3 if s % 2 else -0.3, rev=0.4)  # dotted-8th echo


def beat(t0, seconds, amp, snares=True, hats=True, half_time=False):
    for b in range(int(seconds / BEAT)):
        tb = t0 + b * BEAT
        if not half_time or b % 2 == 0:
            place(drums, kick(amp), tb, rev=0.08)
            i0 = int(tb * SR)
            n = int(0.42 * SR)
            if i0 + n < N:  # sidechain pump on the synth bus
                duck[i0:i0 + n] = np.minimum(duck[i0:i0 + n], 1 - 0.65 * np.exp(-np.arange(n) / SR * 9))
        if snares and b % 4 in ((2,) if half_time else (1, 3)):
            place(drums, snare(amp * 0.8), tb, rev=0.35)
        if hats:
            for h in range(2):
                place(drums, hat(amp * (0.35 if h else 0.2)), tb + h * BEAT / 2, 0.4, rev=0.1)


def chords_pad(t0, name, seconds, amp, cutoff=1800, strings=0.0, choir_amp=0.0, brass_amp=0.0, release=1.5):
    tri = TRIADS[name]
    for j, m in enumerate(tri):
        place(synth, synth_pad(mtof(m), seconds, amp, cutoff, attack=0.4, release=release), t0, -0.5 + 0.5 * j, rev=0.5)
        if strings:
            place(orch, bowed(mtof(m + 12), seconds, strings, attack=0.4, release=release), t0, 0.4 - 0.4 * j, rev=0.55)
        if choir_amp:
            place(orch, choir(mtof(m + 12), seconds, choir_amp, attack=0.5, release=release + 1.0), t0, -0.4 + 0.4 * j, rev=0.75)
        if brass_amp:
            place(orch, brass(mtof(m - 12 + (12 if j else 0)), seconds, brass_amp, release=release), t0, -0.2 + 0.2 * j, rev=0.45)
    place(orch, bowed(mtof(BASS[name]), seconds, amp * 1.2, attack=0.3, release=release, bright=1.6), t0, 0.0, rev=0.35)


def stabs(t0, name, times, amp):
    for b in times:
        for m in TRIADS[name]:
            place(orch, brass(mtof(m), 0.22, amp, attack=0.02, release=0.25), t0 + b, 0.0, rev=0.45)


def roll(t0, seconds, amp):
    k = 0.0
    step = 0.125
    while k < seconds:
        u = k / seconds
        place(drums, snare(amp * (0.15 + 0.85 * u)), t0 + k, rev=0.3)
        k += step if u < 0.5 else step / 2


# ================================================================== Part A: despair (0 - 78.5)

place(synth, synth_pad(mtof(34), 2.5, 0.25, 400, attack=2.0, release=1.0), 0.0, 0.0, rev=0.5)
for i, (name, bass_m) in enumerate(CHORDS_A):
    t0 = 2.0 + i * 4.0
    last = i == len(CHORDS_A) - 1
    dur = 4.5 if last else 4.2
    rel = 0.15 if last else 1.8
    grow = i / (len(CHORDS_A) - 1)
    tri = TRIADS[name]
    # cold synth pad, filter opening as hope drains away and tension rises
    for j, m in enumerate(tri):
        place(synth, synth_pad(mtof(m), dur, 0.16 + 0.12 * grow, 700 + 2500 * grow ** 1.5, attack=1.6, release=rel),
              t0, -0.5 + 0.5 * j, rev=0.6)
    place(orch, bowed(mtof(bass_m), dur, 0.14 + 0.4 * grow ** 1.4, release=rel, bright=1.6), t0, 0.0, rev=0.5)
    if i >= 6:
        for j, m in enumerate(tri):
            place(orch, bowed(mtof(m + 12), dur, (0.1 + 0.3 * grow) * grow, release=rel), t0, 0.4 - 0.3 * j, rev=0.6)
    if i >= 11:
        for j, m in enumerate(tri):
            place(orch, choir(mtof(m + 12), dur, 0.28 * grow, release=rel), t0, -0.3 + 0.3 * j, rev=0.75)

# grieving violin line (original), from 10 s
for c, notes in enumerate(MELODY_A):
    for k, m in enumerate(notes):
        if m is None:
            continue
        t0 = 10.0 + c * 4.0 + k * 2.0
        last = c == len(MELODY_A) - 1
        grow = c / (len(MELODY_A) - 1)
        place(orch, bowed(mtof(m), 4.5 if last else 2.1, 0.12 + 0.3 * grow, attack=0.5, release=0.12 if last else 1.2,
                          vib=0.006, bright=1.15), t0, 0.15, rev=0.65)

# the ticking pulse: muted 8th-note synth bass from 18 s, opening up over time
for i in range(4, len(CHORDS_A)):
    t0 = 2.0 + i * 4.0
    grow = (i - 4) / (len(CHORDS_A) - 5)
    name = CHORDS_A[i][0]
    secs = 4.0 if i < len(CHORDS_A) - 1 else 4.5
    bass_line(t0, name, secs, 0.12 + 0.2 * grow, 250 + 1200 * grow ** 1.4, sixteenths=i >= 15,
              pattern=(0, 0, 0, 0, 0, 0, 0, 0))
heartbeat(42.0, 30.0, 0.35)
for b in range(int(16 / (BEAT / 2))):  # ticking hats in the last stretch
    place(drums, hat(0.12 + 0.2 * b / 32), 62.0 + b * BEAT / 2, 0.4, rev=0.15)
place(synth, riser(8.5, 0.35), 70.0, 0.0, rev=0.4)

# ================================================================== Part B: the drop (80 - 140)

PLAN_B = ["Bbm", "Gb", "Db", "Ab", "Bbm", "Gb", "Db", "Ab", "Gb", "Db", "Ab", "Bbm", "Gb", "Ab", "Bb"]
place(drums, boom(1.0), 80.0, rev=0.6)
for i, name in enumerate(PLAN_B):
    t0 = 80.0 + i * 4.0
    section = i // 4
    final = name == "Bb"
    dur = 4.4 if final else 4.1
    chords_pad(t0, name, dur, 0.12 + 0.03 * section, 1500 + 700 * section,
               strings=0.12 + 0.05 * section, choir_amp=0.0 if section == 0 else 0.22 + 0.06 * section,
               brass_amp=0.0 if section == 0 else 0.1 + 0.04 * section)
    if not final:
        bass_line(t0, name, 4.0, 0.3 + 0.04 * section, 700 + 400 * section)
        beat(t0, 4.0, 0.7 + 0.08 * section, snares=i >= 1, hats=True)
        if section >= 1:
            arp(t0, name, 4.0, 0.12 + 0.03 * section)
        stabs(t0, name, (0.0,) if section == 0 else (0.0, 1.75, 2.5), 0.16 + 0.04 * section)
for start in (110.0, 126.0):
    place(synth, riser(2.0, 0.4), start, rev=0.3)
    roll(start, 2.0, 0.5)
place(drums, boom(0.6), 112.0, rev=0.6)
place(drums, boom(0.8), 136.0, rev=0.7)
for j, m in enumerate([46, 53, 58, 62, 65, 70, 74]):
    place(orch, choir(mtof(m + (12 if m < 55 else 0)), 4.0, 0.22, attack=0.8, release=1.5), 136.0, -0.6 + 0.2 * j, rev=0.8)

# heroic theme on synth lead + strings + brass + choir
MELODY_B = [(73, 0, 2), (78, 2, 2), (77, 4, 3), (75, 7, 1), (75, 8, 2), (72, 10, 1), (75, 11, 1), (77, 12, 4),
            (78, 16, 2), (82, 18, 2), (80, 20, 2), (84, 22, 2), (86, 24, 4.3)]
for m, off, d in MELODY_B:
    t0 = 112.0 + off
    place(synth, lead(mtof(m), d, 0.22), t0, 0.1, rev=0.45)
    place(orch, bowed(mtof(m), d, 0.32, attack=0.2, release=1.0, vib=0.006, bright=1.1), t0, -0.1, rev=0.6)
    place(orch, brass(mtof(m - 12), d, 0.2, release=1.0), t0, -0.2, rev=0.5)
    place(orch, choir(mtof(m), d, 0.2, attack=0.3, release=1.0), t0, 0.0, rev=0.75)

# ================================================================== Part C: the last stand (140 - 212)

# 140-152 standoff: half-time pulse, toms, darkness
for i, name in enumerate(["Bbm", "Gb", "Bbm"]):
    t0 = 140.0 + i * 4.0
    chords_pad(t0, name, 4.1, 0.13, 900 + 300 * i, strings=0.1, choir_amp=0.12 + 0.05 * i, brass_amp=0.05 * i)
    bass_line(t0, name, 4.0, 0.3, 500 + 200 * i, sixteenths=False, pattern=(0, 0, 0, 12, 0, 0, 0, 7))
    beat(t0, 4.0, 0.7, snares=True, hats=i > 0, half_time=True)
    for b in (0.0, 1.5, 2.25, 3.0):
        place(drums, tom(0.4 + 0.1 * i), t0 + b, 0.2, rev=0.35)
place(synth, riser(2.0, 0.4), 150.0, rev=0.3)
roll(150.0, 2.0, 0.5)

# 152 horn call, then the charge
for m, off, d in [(58, 0.0, 0.45), (65, 0.5, 0.45), (70, 1.0, 2.6)]:
    place(orch, brass(mtof(m), d, 0.5, attack=0.06, release=0.6), 152.0 + off, 0.0, rev=0.6)
    place(orch, brass(mtof(m - 12), d, 0.35, attack=0.06, release=0.6), 152.0 + off, -0.2, rev=0.6)
for i, name in enumerate(["Gb", "Ab"]):
    t0 = 152.0 + i * 4.0
    chords_pad(t0, name, 4.1, 0.16, 2600, strings=0.2, choir_amp=0.3, brass_amp=0.14)
    bass_line(t0, name, 4.0, 0.4, 1800)
    arp(t0, name, 4.0, 0.16)
    beat(t0, 4.0, 0.9)
place(synth, riser(2.0, 0.5), 158.0, rev=0.3)
roll(158.0, 2.0, 0.6)

# 160 the clash -> slow motion: everything drops to pads and a heartbeat
place(drums, boom(1.0), 160.0, rev=0.7)
chords_pad(160.0, "Bbm", 6.2, 0.16, 1100, strings=0.15, choir_amp=0.3, release=1.0)
for j, m in enumerate([70, 73, 77]):
    place(orch, bowed(mtof(m + 12), 6.0, 0.16, attack=1.5, release=1.0), 160.0, -0.3 + 0.3 * j, rev=0.8)
heartbeat(160.6, 5.4, 0.5)
place(synth, riser(1.6, 0.45), 164.4, rev=0.3)

# 166-174 battle fury
for i, name in enumerate(["Bbm", "Gb"]):
    t0 = 166.0 + i * 4.0
    chords_pad(t0, name, 4.1, 0.17, 3000, strings=0.22, choir_amp=0.32, brass_amp=0.18)
    bass_line(t0, name, 4.0, 0.42, 2200)
    arp(t0, name, 4.0, 0.18)
    arp(t0, name, 4.0, 0.08, octave=24)
    beat(t0, 4.0, 0.95)
    stabs(t0, name, (0.0, 0.75, 1.5, 2.0, 2.75, 3.5), 0.22)
place(drums, boom(0.7), 172.5, rev=0.6)

# 174-182 breakdown: solo violin over a soft pad and the heartbeat, in slow motion
chords_pad(174.0, "Bbm", 4.2, 0.1, 800, choir_amp=0.1, release=2.0)
chords_pad(178.0, "Gb", 4.2, 0.1, 900, choir_amp=0.12, release=1.5)
heartbeat(174.0, 8.0, 0.42)
for m, off, d in [(77, 0.0, 2.0), (78, 2.0, 1.0), (80, 3.0, 1.0), (82, 4.0, 2.5), (80, 6.5, 1.5)]:
    place(orch, bowed(mtof(m), d, 0.42, attack=0.35, release=1.2, vib=0.008, bright=1.05, voices=2, spread=4.0),
          174.0 + off, 0.15, rev=0.75)
place(synth, riser(2.0, 0.5), 180.0, rev=0.3)
roll(180.0, 2.0, 0.6)

# 182-189.4 the final surge
for i, name in enumerate(["Gb", "Ab"]):
    t0 = 182.0 + i * 4.0
    secs = 4.0 if i == 0 else 3.4
    chords_pad(t0, name, secs + 0.1, 0.18, 3200, strings=0.24, choir_amp=0.36, brass_amp=0.22)
    bass_line(t0, name, secs, 0.45, 2600)
    arp(t0, name, secs, 0.18)
    beat(t0, secs, 1.0)
for m, off, d in [(82, 0.0, 2.0), (85, 2.0, 2.0), (84, 4.0, 2.0), (87, 6.0, 1.4)]:
    place(synth, lead(mtof(m), d, 0.24), 182.0 + off, 0.1, rev=0.45)
    place(orch, bowed(mtof(m), d, 0.36, attack=0.15, release=0.8, vib=0.006, bright=1.1), 182.0 + off, -0.1, rev=0.6)
    place(orch, brass(mtof(m - 12), d, 0.26, release=0.8), 182.0 + off, -0.15, rev=0.5)
place(synth, riser(2.0, 0.6), 187.4, rev=0.3)
roll(187.6, 1.8, 0.7)

# 189.4 the citadel falls -> B-flat major victory
place(drums, boom(1.0), 189.4, rev=0.8)
for j, m in enumerate([46, 53, 58, 62, 65, 70, 74]):
    place(orch, choir(mtof(m + (12 if m < 55 else 0)), 20.0, 0.24, attack=0.6, release=4.0), 189.4, -0.6 + 0.2 * j, rev=0.8)
chords_pad(189.4, "Bb", 20.0, 0.16, 2400, strings=0.2, brass_amp=0.14, release=4.0)
bass_line(189.4, "Bb", 8.4, 0.38, 2000)
arp(189.4, "Bb", 8.4, 0.16)
beat(189.4, 8.4, 0.95)
for m, off, d in [(86, 0.0, 4.6), (82, 4.6, 2.0), (86, 6.6, 3.0), (89, 9.6, 8.0)]:
    place(synth, lead(mtof(m), d, 0.2, release=2.0), 189.4 + off, 0.1, rev=0.5)
    place(orch, bowed(mtof(m), d, 0.36, attack=0.3, release=2.5, vib=0.006, bright=1.1), 189.4 + off, -0.1, rev=0.7)
    place(orch, choir(mtof(m - 12), d, 0.2, attack=0.4, release=2.5), 189.4 + off, 0.0, rev=0.8)
place(drums, boom(0.7), 199.0, rev=0.8)  # the title

# ================================================================== mix + master

synth *= duck
ir_len = int(3.6 * SR)
t = np.arange(ir_len) / SR
ir = rng.standard_normal((2, ir_len)) * np.exp(-6.9 * t / 3.2)
ir = sosfilt(butter(2, 6000, fs=SR, output="sos"), ir, axis=1)
ir[:, : int(0.02 * SR)] *= np.linspace(0, 1, int(0.02 * SR))
wet = np.stack([fftconvolve(send[c], ir[c])[:N] for c in range(2)])


def norm(x):
    return x / (np.max(np.abs(x)) + 1e-9)


mix = norm(orch) * 0.9 + norm(synth) * 0.75 + norm(drums) * 0.85 + norm(wet) * 0.45
tt = np.arange(N) / SR
g = np.where((tt > 78.6) & (tt < 79.98), np.clip(1 - (tt - 78.6) / 0.3, 0, 1), 1.0)
g *= np.clip((DUR - tt) / 9.0, 0, 1)
mix *= g
mix = np.tanh(mix * 1.3)
mix /= np.max(np.abs(mix)) / 0.89
wavfile.write(sys.argv[1] if len(sys.argv) > 1 else "intro_theme_hybrid.wav", SR, (mix.T * 32767).astype(np.int16))
print("wrote", DUR, "s")
