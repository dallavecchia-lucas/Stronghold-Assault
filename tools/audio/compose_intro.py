"""Original synthesized score for the intro cinematic (212 s).

Not a recording or arrangement of any existing piece: an original temp score in the spirit
of a slow, grieving string adagio that breaks into a driving, triumphant choral ostinato.

  Part A  0.0 - 78.5 s  B-flat minor adagio: low strings, rising violin line, choir joins,
                         builds to a fortissimo climax and cuts to silence.
  (silence 78.5 - 80 s)
  Part B 80.0 - 140 s   120 bpm: impact, spiccato string ostinato, timpani, choir, brass;
                         heroic melody lifting to B-flat major.
  Part C 140 - 212 s    the last stand: war drums and standoff, horn call, the charge, the
                         clash into slow motion, battle fury, a solo-violin breakdown, the
                         final surge, the citadel falls, B-flat major victory and title.

Usage: python3 tools/audio/compose_intro.py out.wav
Then:  ffmpeg -i out.wav -c:a libvorbis -q:a 6 game/assets/audio/intro_theme.ogg
"""
import sys

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, fftconvolve, sosfilt

SR = 44100
DUR = 212.0
N = int(SR * DUR)
rng = np.random.default_rng(1945)

dry = np.zeros((2, N))
send = np.zeros((2, N))  # reverb send bus


def mtof(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def place(sig, t0, pan=0.0, rev=0.4, gain=1.0):
    """Mix a mono signal into the buses at time t0 with constant-power pan (-1..1)."""
    i0 = int(t0 * SR)
    if i0 >= N:
        return
    sig = sig[: N - i0] * gain
    a = (pan + 1.0) * np.pi / 4.0
    l, r = np.cos(a), np.sin(a)
    dry[0, i0:i0 + len(sig)] += sig * l
    dry[1, i0:i0 + len(sig)] += sig * r
    send[0, i0:i0 + len(sig)] += sig * l * rev
    send[1, i0:i0 + len(sig)] += sig * r * rev


def envelope(n, dur, attack, release, curve=1.6):
    t = np.arange(n) / SR
    e = np.clip(t / max(attack, 1e-3), 0, 1) ** curve
    rel = np.clip(1.0 - (t - dur) / max(release, 1e-3), 0, 1)
    return e * np.where(t > dur, rel, 1.0)


def bowed(freq, dur, amp, attack=1.2, release=1.8, vib_depth=0.0045, bright=1.25, voices=4, spread=9.0):
    """Ensemble string tone: detuned band-limited saws with delayed vibrato."""
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    kmax = max(1, min(24, int(9000 / freq)))
    for v in range(voices):
        cents = (v - (voices - 1) / 2) * spread / max(voices - 1, 1) * 2
        f = freq * 2 ** (cents / 1200)
        vib = 1 + vib_depth * np.sin(2 * np.pi * (5.0 + 0.4 * rng.random()) * t + rng.random() * 6.28) * np.clip(t / 1.2, 0, 1)
        ph = 2 * np.pi * np.cumsum(f * vib) / SR + rng.random() * 6.28
        for k in range(1, kmax + 1):
            out += np.sin(k * ph) / k ** bright
    out *= envelope(n, dur, attack, release) * amp / voices
    return out


def choir(freq, dur, amp, attack=1.5, release=2.0):
    src = bowed(freq, dur, 1.0, attack, release, vib_depth=0.003, bright=0.9, voices=5, spread=14)
    out = np.zeros_like(src)
    for lo, hi, g in ((650, 950, 1.0), (1000, 1300, 0.6), (2500, 3100, 0.25)):  # "ah" formants
        out += sosfilt(butter(2, [lo, hi], btype="band", fs=SR, output="sos"), src) * g
    breath = sosfilt(butter(2, [800, 3000], btype="band", fs=SR, output="sos"), rng.standard_normal(len(src))) * 0.02
    return (out + breath * envelope(len(src), dur, attack, release)) * amp


def spiccato(freq, amp):
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    ph = 2 * np.pi * freq * t + rng.random() * 6.28
    kmax = max(1, min(16, int(8000 / freq)))
    s = sum(np.sin(k * ph) / k ** 1.1 for k in range(1, kmax + 1))
    e = np.clip(t / 0.006, 0, 1) * np.exp(-t * 16)
    return s * e * amp


def brass(freq, dur, amp, attack=0.4, release=0.8):
    n = int((dur + release) * SR)
    t = np.arange(n) / SR
    kmax = max(1, min(20, int(7000 / freq)))
    ph = 2 * np.pi * np.cumsum(freq * (1 + 0.002 * np.sin(2 * np.pi * 5.5 * t))) / SR
    env = envelope(n, dur, attack, release, curve=1.2)
    dark = sum(np.sin(k * ph) / k ** 2.2 for k in range(1, kmax + 1))
    bright = sum(np.sin(k * ph) / k ** 1.1 for k in range(1, kmax + 1))
    return (dark * (1 - env * 0.6) + bright * env * 0.6) * env * amp


def timpani(freq, amp, decay=1.6):
    n = int(3.5 * SR)
    t = np.arange(n) / SR
    f = freq * (1 + 0.12 * np.exp(-t * 40))
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t * decay) + 0.35 * np.sin(1.5 * ph) * np.exp(-t * decay * 2.2)
    hit = sosfilt(butter(2, 400, fs=SR, output="sos"), rng.standard_normal(n)) * np.exp(-t * 30) * 0.6
    return (body + hit) * amp


def boom(amp):
    """The reveal impact: sub drop + noise burst."""
    n = int(6 * SR)
    t = np.arange(n) / SR
    f = 55 * np.exp(-t * 0.25) + 22
    sub = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 0.9)
    noise = sosfilt(butter(2, 900, fs=SR, output="sos"), rng.standard_normal(n)) * np.exp(-t * 5)
    return (sub + noise * 0.7) * amp


def taiko(amp):
    n = int(1.2 * SR)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * np.cumsum(70 * (1 + 0.5 * np.exp(-t * 30))) / SR) * np.exp(-t * 6)
    s += sosfilt(butter(2, 250, fs=SR, output="sos"), rng.standard_normal(n)) * np.exp(-t * 20) * 0.8
    return s * amp


# ------------------------------------------------------------------ Part A: adagio

CHORDS_A = [  # (bass, upper voicing) MIDI, 4 s each starting at 2 s
    (46, [53, 58, 61]),  # Bbm
    (42, [54, 58, 61]),  # Gb
    (39, [54, 58, 63]),  # Ebm
    (41, [53, 57, 60]),  # F
    (46, [53, 58, 61]),  # Bbm
    (42, [54, 58, 63]),  # Ebm/Gb
    (44, [51, 56, 60]),  # Ab
    (37, [53, 56, 61]),  # Db
    (42, [54, 58, 61]),  # Gb
    (39, [54, 58, 63]),  # Ebm
    (41, [53, 58, 61]),  # Bbm/F
    (41, [53, 58, 60]),  # Fsus4
    (41, [53, 57, 60]),  # F
    (46, [53, 58, 61]),  # Bbm
    (42, [54, 58, 61]),  # Gb
    (37, [53, 56, 61]),  # Db
    (44, [51, 56, 60]),  # Ab
    (39, [54, 58, 63]),  # Ebm
    (41, [57, 60, 65]),  # F (climax)
]
# Violin line: two notes per chord from chord 2 (10 s); None = rest.
MELODY_A = [
    [66, 70], [69, 72], [73, 72], [70, 66], [68, 72], [73, 77], [78, 77], [75, 73],
    [73, 77], [77, 82], [81, 77], [77, 78], [78, 82], [80, 85], [84, 80], [82, 85], [84, None],
]

wind = sosfilt(butter(2, [150, 700], btype="band", fs=SR, output="sos"), rng.standard_normal(int(80 * SR)))
wind *= (0.5 + 0.5 * np.sin(np.arange(len(wind)) / SR * 0.4)) * np.clip(np.arange(len(wind)) / SR / 4, 0, 1)
wind *= np.clip((78.5 - np.arange(len(wind)) / SR) / 2, 0, 1)
place(wind * 0.05, 0.0, 0.0, rev=0.2)
place(bowed(mtof(34), 2.5, 0.25, attack=2.0, release=1.0), 0.0, 0.0, rev=0.5)  # opening pedal

for i, (bass, upper) in enumerate(CHORDS_A):
    t0 = 2.0 + i * 4.0
    dur = 4.5 if i == len(CHORDS_A) - 1 else 4.2
    rel = 0.15 if i == len(CHORDS_A) - 1 else 1.8
    grow = i / (len(CHORDS_A) - 1)
    amp = 0.1 + 0.5 * grow ** 1.4
    place(bowed(mtof(bass), dur, amp * 1.1, release=rel, bright=1.5), t0, -0.1, rev=0.5)
    place(bowed(mtof(bass - 12), dur, amp * 0.8, release=rel, bright=1.7), t0, 0.1, rev=0.4)  # basses
    for j, m in enumerate(upper):
        place(bowed(mtof(m), dur, amp * 0.6, release=rel), t0, -0.4 + 0.4 * j, rev=0.55)
        if i >= 4:  # violins double an octave up
            place(bowed(mtof(m + 12), dur, amp * 0.35 * grow, release=rel), t0, 0.5 - 0.3 * j, rev=0.6)
    if i >= 9:  # choir joins
        for j, m in enumerate(upper):
            place(choir(mtof(m + 12), dur, amp * 0.5 * grow, release=rel), t0, -0.3 + 0.3 * j, rev=0.7)

for c, notes in enumerate(MELODY_A):
    for k, m in enumerate(notes):
        if m is None:
            continue
        t0 = 10.0 + c * 4.0 + k * 2.0
        last = c == len(MELODY_A) - 1
        dur = 4.5 if last else 2.1
        grow = c / (len(MELODY_A) - 1)
        amp = 0.12 + 0.35 * grow ** 1.2
        place(bowed(mtof(m), dur, amp, attack=0.5, release=0.12 if last else 1.2, vib_depth=0.006, bright=1.15),
              t0, 0.15, rev=0.65)
        if c >= 8:  # violas double the line an octave below
            place(bowed(mtof(m - 12), dur, amp * 0.5, attack=0.5, release=0.12 if last else 1.2), t0, -0.2, rev=0.6)

place(timpani(mtof(29), 0.5, decay=0.5), 74.0, 0.0, rev=0.5)  # climax roll-in
for k in range(28):
    place(timpani(mtof(29), 0.05 + 0.25 * k / 27, decay=6), 74.5 + k * 0.14, 0.0, rev=0.4)

# ------------------------------------------------------------------ Part B: the reveal

BEAT = 0.5
TRIADS = {  # pitch sets for the ostinato (root, third, fifth) around Bb3
    "Bbm": [58, 61, 65], "Gb": [54, 58, 61], "Db": [61, 65, 68], "Ab": [56, 60, 63],
    "Bb": [58, 62, 65], "Eb": [63, 67, 70],
}
BASS = {"Bbm": 34, "Gb": 30, "Db": 37, "Ab": 32, "Bb": 34, "Eb": 39}
PLAN_B = ["Bbm", "Gb", "Db", "Ab",  # 80-96  ostinato + low strings + timpani
          "Bbm", "Gb", "Db", "Ab",  # 96-112 + choir, brass pads
          "Gb", "Db", "Ab", "Bbm",  # 112-128 heroic melody
          "Gb", "Ab", "Bb"]         # 128-140 lift to B-flat major
PATTERN = [0, 1, 2, 1, 3, 2, 1, 2]

place(boom(0.9), 80.0, 0.0, rev=0.6)
place(timpani(mtof(34), 0.8, decay=0.8), 80.0, 0.0, rev=0.6)

for i, name in enumerate(PLAN_B):
    t0 = 80.0 + i * 4.0
    section = i // 4
    tri = TRIADS[name]
    final = name == "Bb"
    dur = 4.4 if final else 4.1
    # sustained low strings
    place(bowed(mtof(BASS[name]), dur, 0.35 + 0.1 * section, attack=0.3, release=1.5, bright=1.5), t0, -0.1, rev=0.4)
    place(bowed(mtof(BASS[name] + 12), dur, 0.3, attack=0.3, release=1.5), t0, 0.1, rev=0.4)
    # spiccato ostinato, 16ths
    if not final:
        for s in range(32):
            idx = PATTERN[s % 8]
            m = tri[idx % 3] + (12 if idx == 3 else 0)
            accent = 1.0 if s % 4 == 0 else 0.6
            amp = (0.18 + 0.05 * section) * accent
            place(spiccato(mtof(m), amp), t0 + s * BEAT / 4, -0.35, rev=0.3)
            if section >= 1:
                place(spiccato(mtof(m + 12), amp * 0.6), t0 + s * BEAT / 4 + 0.004, 0.35, rev=0.3)
    # timpani + drums
    beats = 8
    for b in range(beats if not final else 1):
        tb = t0 + b * BEAT
        if b % 4 == 0 or section >= 2:
            place(timpani(mtof(BASS[name] + 12), (0.5 if b % 4 == 0 else 0.22) + 0.08 * section), tb, 0.0, rev=0.45)
        if section >= 1 and b % 4 in (0, 3):
            place(taiko(0.35 + 0.1 * section), tb + (0.25 if b % 4 == 3 else 0.0), 0.2, rev=0.35)
    # choir and brass pads
    if section >= 1:
        for j, m in enumerate(tri):
            place(choir(mtof(m + 12), dur, 0.25 + 0.08 * section, attack=0.6, release=2.5), t0, -0.4 + 0.4 * j, rev=0.75)
    if section >= 1:
        for j, m in enumerate(tri):
            place(brass(mtof(m - 12 + (12 if j else 0)), dur, 0.12 + 0.05 * section, release=1.5), t0, -0.2 + 0.2 * j, rev=0.5)

# drum rolls into the big sections
for start in (110.0, 126.0):
    for k in range(32):
        place(timpani(mtof(46), 0.05 + 0.3 * k / 31, decay=8), start + k * 0.0625, 0.0, rev=0.4)
place(boom(0.6), 112.0, 0.0, rev=0.6)
place(boom(0.8), 136.0, 0.0, rev=0.7)

# heroic melody (violins + horns + choir), 112 s onwards: (midi, start offset, duration)
MELODY_B = [
    (73, 0, 2), (78, 2, 2), (77, 4, 3), (75, 7, 1), (75, 8, 2), (72, 10, 1), (75, 11, 1), (77, 12, 4),
    (78, 16, 2), (82, 18, 2), (80, 20, 2), (84, 22, 2), (86, 24, 4.3),
]
for m, off, dur in MELODY_B:
    t0 = 112.0 + off
    last = off >= 24
    rel = 1.2 if last else 1.0
    place(bowed(mtof(m), dur, 0.42, attack=0.25, release=rel, vib_depth=0.006, bright=1.1), t0, 0.1, rev=0.6)
    place(brass(mtof(m - 12), dur, 0.25, release=rel), t0, -0.15, rev=0.5)
    place(choir(mtof(m), dur, 0.3, attack=0.4, release=rel), t0, 0.0, rev=0.75)

# B-flat major arrival at 136 (the army on the ridge)
for j, m in enumerate([46, 53, 58, 62, 65, 70, 74]):
    place(choir(mtof(m + (12 if m < 55 else 0)), 4.0, 0.22, attack=1.0, release=1.5), 136.0, -0.6 + 0.2 * j, rev=0.8)

# ------------------------------------------------------------------ Part C: the last stand


def ostinato(t0, name, seconds, amp, octave_up=True, sixteenths=True):
    tri = TRIADS[name]
    step = BEAT / 4 if sixteenths else BEAT / 2
    for s_ in range(int(seconds / step)):
        idx = PATTERN[s_ % 8]
        m = tri[idx % 3] + (12 if idx == 3 else 0)
        acc = 1.0 if s_ % 4 == 0 else 0.6
        place(spiccato(mtof(m), amp * acc), t0 + s_ * step, -0.35, rev=0.3)
        if octave_up:
            place(spiccato(mtof(m + 12), amp * acc * 0.6), t0 + s_ * step + 0.004, 0.35, rev=0.3)


def pad(t0, name, seconds, amp, choir_amp=0.0, brass_amp=0.0, release=1.5):
    tri = TRIADS[name]
    place(bowed(mtof(BASS[name]), seconds, amp, attack=0.3, release=release, bright=1.5), t0, -0.1, rev=0.4)
    place(bowed(mtof(BASS[name] + 12), seconds, amp * 0.8, attack=0.3, release=release), t0, 0.1, rev=0.4)
    for j, m in enumerate(tri):
        if choir_amp:
            place(choir(mtof(m + 12), seconds, choir_amp, attack=0.5, release=release + 1.0), t0, -0.4 + 0.4 * j, rev=0.75)
        if brass_amp:
            place(brass(mtof(m - 12 + (12 if j else 0)), seconds, brass_amp, release=release), t0, -0.2 + 0.2 * j, rev=0.5)


def drums(t0, seconds, amp, every_beat=False, root=34):
    for b in range(int(seconds / BEAT)):
        tb = t0 + b * BEAT
        if b % 4 == 0 or every_beat:
            place(timpani(mtof(root + 12), amp * (1.0 if b % 4 == 0 else 0.5)), tb, 0.0, rev=0.45)
        if b % 4 in (0, 3) or (every_beat and b % 2 == 1):
            place(taiko(amp * 0.9), tb + (0.25 if b % 4 == 3 else 0.0), 0.2, rev=0.35)


def roll(t0, seconds, amp, root=46):
    n = int(seconds / 0.0625)
    for k in range(n):
        place(timpani(mtof(root), 0.04 + amp * k / max(n - 1, 1), decay=8), t0 + k * 0.0625, 0.0, rev=0.4)


def heartbeat(t0, seconds, amp):
    k = 0.0
    while k < seconds:
        place(taiko(amp), t0 + k, 0.0, rev=0.5)
        place(taiko(amp * 0.6), t0 + k + 0.28, 0.0, rev=0.5)
        k += 1.2


# 140-152 standoff: drums and a low pulse while the horde marches
for i, name in enumerate(["Bbm", "Gb", "Bbm"]):
    t0 = 140.0 + i * 4.0
    pad(t0, name, 4.1, 0.32, choir_amp=0.12 + 0.05 * i, brass_amp=0.06 * i)
    ostinato(t0, name, 4.0, 0.16 + 0.03 * i, octave_up=i > 0, sixteenths=False)
    drums(t0, 4.0, 0.45 + 0.08 * i)
roll(150.0, 2.0, 0.35)

# 152 horn call, then the charge
for m, off, d in [(58, 0.0, 0.45), (65, 0.5, 0.45), (70, 1.0, 2.6)]:
    place(brass(mtof(m), d, 0.5, attack=0.08, release=0.6), 152.0 + off, 0.0, rev=0.6)
    place(brass(mtof(m - 12), d, 0.35, attack=0.08, release=0.6), 152.0 + off, -0.2, rev=0.6)
for i, name in enumerate(["Gb", "Ab"]):
    t0 = 152.0 + i * 4.0
    pad(t0, name, 4.1, 0.42, choir_amp=0.3, brass_amp=0.16)
    ostinato(t0, name, 4.0, 0.24)
    drums(t0, 4.0, 0.6, every_beat=True)
roll(158.0, 2.0, 0.45)

# 160 the clash: impact, then slow motion (sustain, high choir, heartbeat)
place(boom(1.0), 160.0, 0.0, rev=0.7)
place(timpani(mtof(34), 0.9, decay=0.6), 160.0, 0.0, rev=0.6)
pad(160.0, "Bbm", 6.2, 0.35, choir_amp=0.32, release=1.0)
for j, m in enumerate([70, 73, 77]):
    place(bowed(mtof(m + 12), 6.0, 0.18, attack=1.5, release=1.0), 160.0, -0.3 + 0.3 * j, rev=0.8)
heartbeat(160.6, 5.4, 0.5)

# 166-174 battle fury
for i, name in enumerate(["Bbm", "Gb"]):
    t0 = 166.0 + i * 4.0
    pad(t0, name, 4.1, 0.45, choir_amp=0.34, brass_amp=0.2)
    ostinato(t0, name, 4.0, 0.26)
    drums(t0, 4.0, 0.7, every_beat=True)
    for b in (0.0, 1.25, 2.0, 3.25):  # brass stabs
        for m in TRIADS[name]:
            place(brass(mtof(m), 0.25, 0.22, attack=0.03, release=0.3), t0 + b, 0.0, rev=0.5)
place(boom(0.7), 172.5, 0.0, rev=0.6)  # the eagle strike

# 174-182 breakdown: solo violin over the heartbeat, in slow motion
pad(174.0, "Bbm", 4.2, 0.26, choir_amp=0.12, release=2.0)
pad(178.0, "Gb", 4.2, 0.26, choir_amp=0.14, release=1.5)
heartbeat(174.0, 8.0, 0.42)
for m, off, d in [(77, 0.0, 2.0), (78, 2.0, 1.0), (80, 3.0, 1.0), (82, 4.0, 2.5), (80, 6.5, 1.5)]:
    place(bowed(mtof(m), d, 0.42, attack=0.35, release=1.2, vib_depth=0.008, bright=1.05, voices=2, spread=4.0),
          174.0 + off, 0.15, rev=0.75)
roll(180.0, 2.0, 0.5)

# 182-189 the final surge, lifting key
for i, name in enumerate(["Gb", "Ab"]):
    t0 = 182.0 + i * 4.0
    pad(t0, name, 4.1, 0.5, choir_amp=0.38, brass_amp=0.24)
    ostinato(t0, name, 4.0 if i == 0 else 3.4, 0.28)
    drums(t0, 4.0 if i == 0 else 3.4, 0.75, every_beat=True)
for m, off, d in [(82, 0.0, 2.0), (85, 2.0, 2.0), (84, 4.0, 2.0), (87, 6.0, 1.4)]:
    place(bowed(mtof(m), d, 0.45, attack=0.2, release=0.8, vib_depth=0.006, bright=1.1), 182.0 + off, 0.1, rev=0.6)
    place(brass(mtof(m - 12), d, 0.3, release=0.8), 182.0 + off, -0.15, rev=0.5)
roll(187.6, 1.8, 0.6)

# 189.4 the citadel falls -> B-flat major victory, held through the title
place(boom(1.0), 189.4, 0.0, rev=0.8)
place(timpani(mtof(34), 1.0, decay=0.5), 189.4, 0.0, rev=0.6)
for j, m in enumerate([46, 53, 58, 62, 65, 70, 74]):
    place(choir(mtof(m + (12 if m < 55 else 0)), 20.0, 0.24, attack=0.8, release=4.0), 189.4, -0.6 + 0.2 * j, rev=0.8)
pad(189.4, "Bb", 20.0, 0.4, brass_amp=0.16, release=4.0)
for m, off, d in [(86, 0.0, 4.6), (82, 4.6, 2.0), (86, 6.6, 3.0), (89, 9.6, 8.0)]:
    place(bowed(mtof(m), d, 0.4, attack=0.4, release=2.5, vib_depth=0.006, bright=1.1), 189.4 + off, 0.1, rev=0.7)
    place(choir(mtof(m - 12), d, 0.22, attack=0.5, release=2.5), 189.4 + off, -0.1, rev=0.8)
for k in range(4):
    place(timpani(mtof(34), 0.35, decay=1.0), 198.0 + k * 2.0, 0.0, rev=0.6)
place(boom(0.6), 199.0, 0.0, rev=0.8)  # the title

# ------------------------------------------------------------------ reverb + master

ir_len = int(4.0 * SR)
t = np.arange(ir_len) / SR
ir = rng.standard_normal((2, ir_len)) * np.exp(-6.9 * t / 3.6)
ir = sosfilt(butter(2, 6500, fs=SR, output="sos"), ir, axis=1)
ir[:, : int(0.02 * SR)] *= np.linspace(0, 1, int(0.02 * SR))
wet = np.stack([fftconvolve(send[c], ir[c])[:N] for c in range(2)])
wet /= np.max(np.abs(wet)) + 1e-9
mix = dry / (np.max(np.abs(dry)) + 1e-9) + wet * 0.55

# dramatic silence before the reveal
g = np.ones(N)
tt = np.arange(N) / SR
g = np.where((tt > 78.6) & (tt < 79.98), np.clip(1 - (tt - 78.6) / 0.35, 0, 1), g)
# fade out at the end
g *= np.clip((DUR - tt) / 9.0, 0, 1)
mix *= g

mix = np.tanh(mix * 1.4)
mix /= np.max(np.abs(mix)) / 0.89
wavfile.write(sys.argv[1] if len(sys.argv) > 1 else "intro_theme.wav", SR, (mix.T * 32767).astype(np.int16))
print("wrote", DUR, "s")
