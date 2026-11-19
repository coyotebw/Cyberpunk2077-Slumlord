"""Master a dialogue line for Slumlord: trim, gate, optional holocall effect, loudness, Ogg Vorbis.

Rebuilt 2026-11-19 from the spec in the design doc (4.8): the original was lost with an earlier workspace.

  python holo_fx.py in.wav out.ogg --preset holo        # phone/holocall lines (Oshima's and Finger's calls)
  python holo_fx.py in.wav out.ogg --preset dry          # in-person lines
  python holo_fx.py in.wav out.ogg --preset dry --lufs -21.4   # in-person lines that play positionally (+2.6 dB)
  python holo_fx.py in.wav out.ogg --preset dry --no-gate      # vanilla V lines (decoded from .wem with vgmstream-cli)

Chain:
  1. Trim leading/trailing silence (frames under -38 dBFS RMS: above the ~-46 dB hiss), keeping 0.2 s of padding.
  2. dry preset only: gentle gate, frames under -46 dBFS pulled down by up to 12 dB (10 ms attack, 300 ms
     release), for the hiss floor of Andrew's phone recordings (about -46 dB). The holo preset skips it:
     its band-pass removes most hiss, and a deeper gate ate quiet word endings ("cables"). Check every
     line by transcribing the result back.
  3. holo preset only: 420-3,100 Hz band (4th-order Butterworth), compression (3:1 above -20 dBFS,
     5 ms attack, 80 ms release), 5 ms comb echo (0.35 feedforward) for a metallic edge, 9-bit crusher
     at 50% mix. No static.
  4. Loudness to -24 LUFS (vanilla dialogue level) unless --lufs is given; peaks kept under -1 dBFS.
  5. 48 kHz mono Ogg Vorbis (ffmpeg libvorbis, q 5).
"""
import argparse
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import pyloudnorm as pyln
import soundfile as sf
from scipy.signal import butter, resample_poly, sosfilt

SR = 48000


def load(path):
    x, sr = sf.read(path, dtype="float64", always_2d=True)
    x = x.mean(axis=1)
    if sr != SR:
        x = resample_poly(x, SR, sr)
    return x


def frame_db(x, hop):
    n = max(1, len(x) // hop)
    rms = np.array([np.sqrt(np.mean(x[i * hop:(i + 1) * hop] ** 2) + 1e-12) for i in range(n)])
    return 20 * np.log10(rms)


def trim(x, threshold_db=-38.0, pad=0.2):
    hop = int(0.01 * SR)
    db = frame_db(x, hop)
    loud = np.where(db > threshold_db)[0]
    if len(loud) == 0:
        return x
    start = max(0, loud[0] * hop - int(pad * SR))
    end = min(len(x), (loud[-1] + 1) * hop + int(pad * SR))
    return x[start:end]


def envelope_follow(target, attack, release):
    out = np.empty_like(target)
    g = target[0]
    a = np.exp(-1.0 / (attack * SR))
    r = np.exp(-1.0 / (release * SR))
    for i, t in enumerate(target):
        coef = a if t < g else r
        g = coef * g + (1 - coef) * t
        out[i] = g
    return out


def gate(x, threshold_db=-46.0, floor_db=-12.0):
    hop = int(0.005 * SR)
    db = np.repeat(frame_db(x, hop), hop)
    db = np.pad(db, (0, max(0, len(x) - len(db))), mode="edge")[:len(x)]
    target = np.where(db < threshold_db, 10 ** (floor_db / 20), 1.0)
    return x * envelope_follow(target, attack=0.010, release=0.300)


def compress(x, threshold_db=-20.0, ratio=3.0):
    hop = int(0.002 * SR)
    db = np.repeat(frame_db(x, hop), hop)
    db = np.pad(db, (0, max(0, len(x) - len(db))), mode="edge")[:len(x)]
    over = np.maximum(0.0, db - threshold_db)
    gain_db = -over * (1 - 1 / ratio)
    smoothed = envelope_follow(10 ** (gain_db / 20), attack=0.005, release=0.080)
    return x * smoothed


def holo(x):
    sos = butter(4, [420, 3100], btype="bandpass", fs=SR, output="sos")
    y = sosfilt(sos, x)
    y = compress(y)
    d = int(0.005 * SR)
    comb = y.copy()
    comb[d:] += 0.35 * y[:-d]
    peak = np.max(np.abs(comb)) or 1.0
    norm = comb / peak
    crushed = np.round(norm * 256) / 256          # 9-bit: 2^8 steps per polarity
    return (0.5 * norm + 0.5 * crushed) * peak


def to_lufs(x, lufs):
    meter = pyln.Meter(SR)
    y = pyln.normalize.loudness(x, meter.integrated_loudness(x), lufs)
    peak = np.max(np.abs(y))
    ceiling = 10 ** (-1 / 20)
    if peak > ceiling:                             # soft-limit the few peaks over -1 dBFS
        y = np.tanh(y / ceiling) * ceiling
    return y


def master(src, dst, preset="holo", lufs=-24.0, use_gate=True):
    x = trim(load(src))
    if preset == "holo":
        x = holo(x)        # the 420-3,100 Hz band already removes most hiss; a gate ate word endings
    elif use_gate:
        x = gate(x)
    x = to_lufs(x, lufs)
    dst = Path(dst)
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "m.wav"
        sf.write(wav, x, SR, subtype="PCM_16")
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(wav), "-ac", "1", "-ar", str(SR),
                        "-c:a", "libvorbis", "-q:a", "5", str(dst)], check=True)
    meter = pyln.Meter(SR)
    return len(x) / SR, meter.integrated_loudness(x), 20 * np.log10(np.max(np.abs(x)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--preset", choices=["holo", "dry"], default="holo")
    ap.add_argument("--lufs", type=float, default=-24.0)
    ap.add_argument("--no-gate", action="store_true", help="dry preset without the gate (clean studio audio, e.g. vanilla V lines)")
    a = ap.parse_args()
    secs, lufs, peak = master(a.src, a.dst, a.preset, a.lufs, use_gate=not a.no_gate)
    print(f"{a.dst}: {secs:.2f} s, {lufs:.1f} LUFS, peak {peak:.1f} dBFS")


if __name__ == "__main__":
    main()
