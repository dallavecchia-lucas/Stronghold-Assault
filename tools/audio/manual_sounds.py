"""The Field Manual's paper sounds, synthesized (no samples): a page turned, the other manual pulled across the
desk and dropped open, and the soft tap of a figure changed.

    python3 tools/audio/manual_sounds.py          # writes game/assets/audio/manual_*.ogg (needs ffmpeg)

A page turn is the sheet's rasp as it lifts (bright, band-passed noise rising), its flutter in the air (the noise
beating a few dozen times a second, dying away) and the slap of it landing (a short crisp burst over a low thud).
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

RATE = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "game", "assets", "audio")


def noise(n, rng):
    return rng.standard_normal(n)


def band(x, lo, hi, order=2):
    return sosfilt(butter(order, [lo, hi], btype="band", fs=RATE, output="sos"), x)


def low(x, hi, order=2):
    return sosfilt(butter(order, hi, btype="low", fs=RATE, output="sos"), x)


def env(n, attack, decay):
    t = np.arange(n) / RATE
    return np.minimum(t / max(attack, 1e-4), 1.0) * np.exp(-np.maximum(t - attack, 0.0) / decay)


def at(sig, start, length):
    out = np.zeros(length)
    i = int(start * RATE)
    end = min(length, i + len(sig))
    out[i:end] = sig[: end - i]
    return out


def page_turn(rng, length=0.62):
    n = int(length * RATE)
    t = np.arange(n) / RATE
    # The lift: a rasp that swells and brightens.
    lift_n = int(0.22 * RATE)
    lift = band(noise(lift_n, rng), 1800, 7500) * np.linspace(0, 1, lift_n) ** 1.6
    # The flutter: the sheet beating the air, slowing as it falls.
    fl_n = int(0.3 * RATE)
    ft = np.arange(fl_n) / RATE
    rate = 42.0 - 30.0 * ft / ft[-1]
    beat = 0.55 + 0.45 * np.sin(2 * np.pi * np.cumsum(rate) / RATE)
    flutter = band(noise(fl_n, rng), 900, 5200) * beat * np.exp(-ft / 0.16)
    # The landing: a crisp slap over a soft thud.
    slap = band(noise(int(0.05 * RATE), rng), 2500, 9000) * env(int(0.05 * RATE), 0.001, 0.012)
    thud = low(noise(int(0.12 * RATE), rng), 220) * env(int(0.12 * RATE), 0.002, 0.03) * 3.0
    sig = at(lift, 0.0, n) * 0.8 + at(flutter, 0.16, n) * 0.6 + at(slap, 0.44, n) * 0.9 + at(thud, 0.44, n) * 0.7
    # A breath of air under it all.
    sig += low(noise(n, rng), 600) * 0.12 * np.exp(-((t - 0.3) / 0.18) ** 2)
    return sig


def book_drop(rng, length=0.9):
    n = int(length * RATE)
    t = np.arange(n) / RATE
    # Pulled across the desk: friction, low and grainy.
    slide_n = int(0.38 * RATE)
    st = np.arange(slide_n) / RATE
    slide = band(noise(slide_n, rng), 250, 2600) * np.sin(np.pi * st / st[-1]) ** 0.7 * (0.7 + 0.3 * np.sin(2 * np.pi * 9 * st))
    # Dropped open: the boards thump, the pages riffle after.
    thump_n = int(0.3 * RATE)
    tt = np.arange(thump_n) / RATE
    thump = (np.sin(2 * np.pi * 78 * tt) * 1.2 + low(noise(thump_n, rng), 400) * 0.9) * env(thump_n, 0.002, 0.07)
    riffle_n = int(0.3 * RATE)
    rt = np.arange(riffle_n) / RATE
    riffle = band(noise(riffle_n, rng), 1500, 7000) * (0.5 + 0.5 * np.sin(2 * np.pi * 34 * rt)) * np.exp(-rt / 0.09)
    sig = at(slide, 0.0, n) * 0.45 + at(thump, 0.36, n) * 0.9 + at(riffle, 0.39, n) * 0.35
    sig += low(noise(n, rng), 180) * 0.05 * np.exp(-((t - 0.4) / 0.1) ** 2)
    return sig


def tap(rng, length=0.16):
    n = int(length * RATE)
    click = band(noise(n, rng), 1200, 6000) * env(n, 0.0008, 0.018)
    knock = low(noise(n, rng), 300) * env(n, 0.001, 0.025) * 1.5
    return click * 0.7 + knock * 0.5


def write(name, sig):
    sig = sig / (np.max(np.abs(sig)) + 1e-9) * 0.7
    fade = int(0.01 * RATE)
    sig[-fade:] *= np.linspace(1, 0, fade)
    path = os.path.join(OUT, name)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wav = f.name
    wavfile.write(wav, RATE, (sig * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-c:a", "libvorbis", "-q:a", "5", path], check=True)
    os.unlink(wav)
    print(f"{path}: {len(sig) / RATE:.2f} s")


def main():
    rng = np.random.default_rng(int(sys.argv[1]) if len(sys.argv) > 1 else 7)
    for k in range(3):
        write(f"manual_page_{k + 1}.ogg", page_turn(rng, 0.58 + 0.04 * k))
    write("manual_book.ogg", book_drop(rng))
    write("manual_tap.ogg", tap(rng))


if __name__ == "__main__":
    main()
