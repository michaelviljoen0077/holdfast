"""Composes and renders the game's two music loops (calm and battle).

Everything is synthesised with numpy: additive harp, breathy tin whistle,
bowed cello, string pad, war horn and frame/taiko drums, then put through a
convolution reverb. Loops are wrapped so the reverb tail of the end feeds the
start, making them seamless.

    python tools/compose_music.py   ->   assets/audio/music/{calm,battle}.wav
"""
import os

import numpy as np
import soundfile as sf
from scipy.signal import butter, fftconvolve, sosfilt

SR = 32000
RNG = np.random.default_rng(7)
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "audio", "music")


def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


def env_adsr(n, a, d, s, r):
    a, d, r = int(a * SR), int(d * SR), int(r * SR)
    e = np.full(n, s, dtype=np.float64)
    a = min(a, n)
    e[:a] = np.linspace(0, 1, a, endpoint=False)
    d_end = min(a + d, n)
    if d_end > a:
        e[a:d_end] = np.linspace(1, s, d_end - a, endpoint=False)
    if r > 0 and n > r:
        e[-r:] *= np.linspace(1, 0, r)
    return e


def lowpass(x, hz, order=2):
    sos = butter(order, min(hz, SR * 0.45), btype="low", fs=SR, output="sos")
    return sosfilt(sos, x)


def bandpass(x, lo, hi):
    sos = butter(2, [lo, min(hi, SR * 0.45)], btype="band", fs=SR, output="sos")
    return sosfilt(sos, x)


# Instruments ------------------------------------------------------------------

def harp(m, dur):
    f = midi_hz(m)
    n = int((dur + 2.5) * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for h in range(1, 12):
        fh = f * h * (1 + 0.0004 * h * h)          # slight string inharmonicity
        if fh > SR * 0.45:
            break
        amp = (1.0 / h) * (0.6 if h % 2 == 0 else 1.0)
        out += amp * np.sin(2 * np.pi * fh * t) * np.exp(-t * (1.6 + h * 0.9))
    pluck = RNG.standard_normal(n) * np.exp(-t * 90) * 0.15
    return (out + lowpass(pluck, 3000)) * 0.35


def whistle(m, dur):
    f = midi_hz(m)
    n = int((dur + 0.15) * SR)
    t = np.arange(n) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.4 * t) * np.clip((t - 0.25) / 0.3, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * vib) / SR
    tone = np.sin(ph) + 0.18 * np.sin(2 * ph) + 0.05 * np.sin(3 * ph)
    breath = bandpass(RNG.standard_normal(n), f * 0.8, f * 3.5) * 0.12
    e = env_adsr(n, 0.05, 0.1, 0.85, 0.12)
    return (tone + breath) * e * 0.28


def saw(f, t, harmonics=24):
    """Band-limited sawtooth. `f` may be a per-sample frequency array."""
    if np.ndim(f) > 0:
        phase = 2 * np.pi * np.cumsum(f) / SR
        fmax = float(np.max(f))
    else:
        phase = 2 * np.pi * f * t
        fmax = f
    out = np.zeros_like(phase)
    for h in range(1, harmonics + 1):
        if fmax * h > SR * 0.45:
            break
        out += np.sin(h * phase) / h
    return out


def cello(m, dur, attack=0.08, bright=1400):
    f = midi_hz(m)
    n = int((dur + 0.3) * SR)
    t = np.arange(n) / SR
    vib = 0.004 * np.sin(2 * np.pi * 5.0 * t)
    x = saw(f * (1 + vib), t) + 0.6 * saw(f * 1.003, t)
    x = lowpass(x, bright)
    return x * env_adsr(n, attack, 0.2, 0.8, 0.25) * 0.16


def pad(ms, dur):
    n = int((dur + 1.5) * SR)
    t = np.arange(n) / SR
    left = np.zeros(n)
    right = np.zeros(n)
    for m in ms:
        f = midi_hz(m)
        left += saw(f * 0.997, t, 12)
        right += saw(f * 1.003, t, 12)
    e = env_adsr(n, 0.9, 0.5, 0.8, 1.4)
    return lowpass(left, 900) * e * 0.05, lowpass(right, 900) * e * 0.05


def horn(m, dur):
    f = midi_hz(m)
    n = int((dur + 0.25) * SR)
    t = np.arange(n) / SR
    vib = 1 + 0.005 * np.sin(2 * np.pi * 4.8 * t) * np.clip((t - 0.3) / 0.4, 0, 1)
    ph_t = np.cumsum(vib) / SR
    x = saw(f, ph_t, 30)
    # Brassy swell: the filter opens as the note blooms.
    out = np.zeros(n)
    seg = 2048
    for i in range(0, n, seg):
        cut = 500 + 1800 * min(1.0, (i / SR) / 0.25)
        out[i:i + seg] = lowpass(x[max(0, i - 512):i + seg], cut)[-len(out[i:i + seg]):]
    return out * env_adsr(n, 0.09, 0.15, 0.85, 0.18) * 0.2


def frame_drum(strength=1.0):
    n = int(0.6 * SR)
    t = np.arange(n) / SR
    f = 95 * np.exp(-t * 6) + 55
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)
    skin = bandpass(RNG.standard_normal(n), 200, 1800) * np.exp(-t * 40) * 0.5
    return (body + skin) * 0.5 * strength


def taiko(strength=1.0):
    n = int(1.4 * SR)
    t = np.arange(n) / SR
    f = 70 * np.exp(-t * 4) + 38
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 4.5)
    hit = lowpass(RNG.standard_normal(n), 900) * np.exp(-t * 30) * 0.8
    return (body + hit) * 0.9 * strength


# Mixing ------------------------------------------------------------------------

class Track:
    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.L = np.zeros(self.n + 6 * SR)
        self.R = np.zeros(self.n + 6 * SR)

    def add(self, x, at, pan=0.0, right=None):
        i = int(at * SR)
        if right is None:
            right = x
        gl = np.cos((pan + 1) * np.pi / 4)
        gr = np.sin((pan + 1) * np.pi / 4)
        k = min(len(x), len(self.L) - i)
        self.L[i:i + k] += x[:k] * gl * 1.414
        self.R[i:i + k] += right[:k] * gr * 1.414

    def render(self, wet=0.3, decay=2.6):
        ir_n = int(decay * 1.6 * SR)
        t = np.arange(ir_n) / SR
        irs = []
        for _ in range(2):
            ir = RNG.standard_normal(ir_n) * np.exp(-t * 6.9 / decay)
            ir = lowpass(ir, 5000)
            ir[: int(0.012 * SR)] = 0
            irs.append(ir / np.sqrt(np.sum(ir ** 2)))
        Lw = fftconvolve(self.L, irs[0])[: len(self.L)]
        Rw = fftconvolve(self.R, irs[1])[: len(self.R)]
        L = self.L * (1 - wet) + Lw * wet * 2.2
        R = self.R * (1 - wet) + Rw * wet * 2.2
        # Wrap everything past the loop point back onto the start: seamless loop.
        tail = len(L) - self.n
        L[:tail] += L[self.n:]
        R[:tail] += R[self.n:]
        L, R = L[: self.n], R[: self.n]
        peak = max(np.abs(L).max(), np.abs(R).max())
        L, R = np.tanh(L / peak * 1.1) * 0.9, np.tanh(R / peak * 1.1) * 0.9
        return np.stack([L, R], axis=1)


CHORDS = {  # root midi (octave 3), minor?
    "Dm": (50, True), "G": (55, False), "C": (48, False), "F": (53, False),
    "Am": (57, True), "Em": (52, True),
}


def chord_tones(name):
    root, minor = CHORDS[name]
    return root, root + (3 if minor else 4), root + 7


def compose_calm():
    bpm = 76
    beat = 60 / bpm
    bar = beat * 4
    prog = ["Dm", "G", "Dm", "C", "F", "C", "G", "Am"] * 3
    tr = Track(len(prog) * bar)
    mel_a = [(81, 1.5), (79, .5), (77, 1), (76, 1), (74, 1.5), (76, .5), (79, 2), (81, 1), (86, 1), (84, 1), (81, 1),
             (79, 1.5), (81, .5), (79, 1), (76, 1), (77, 1), (81, 1), (84, 1.5), (81, .5), (79, 2), (76, 2),
             (74, 1), (76, 1), (79, 1), (83, 1), (81, 4)]
    mel_b = [(86, 1.5), (84, .5), (81, 2), (83, 1), (79, 1), (81, 1), (83, 1), (84, 1.5), (81, .5), (77, 1), (81, 1),
             (79, 3), (76, 1), (77, 1.5), (79, .5), (81, 1), (84, 1), (79, 1), (84, 1), (76, 2),
             (74, 1.5), (76, .5), (79, 1), (81, 1), (76, 2), (74, 2)]
    # Drone under everything.
    drone = cello(38, len(prog) * bar, attack=1.5, bright=600) * 0.9
    tr.add(drone, 0.0, 0.0)
    tr.add(cello(45, len(prog) * bar, attack=2.0, bright=500) * 0.5, 0.0, 0.1)
    for b, ch in enumerate(prog):
        t0 = b * bar
        r, third, fifth = chord_tones(ch)
        pl, pr = pad([r + 12, third + 12, fifth + 12], bar)
        tr.add(pl, t0, -0.6, pr)
        arp = [r, fifth, r + 12, third + 12, fifth + 12, r + 24, fifth + 12, r + 12]
        for k, m in enumerate(arp):
            vel = 0.8 + 0.2 * (k % 2 == 0)
            tr.add(harp(m, beat / 2) * vel, t0 + k * beat / 2 + RNG.uniform(0, 0.008), -0.35 + 0.1 * (k % 3))
        if b >= 16 and b % 2 == 0:
            tr.add(frame_drum(0.5), t0)
            tr.add(frame_drum(0.3), t0 + 2 * beat)
    for section, mel in ((8, mel_a), (16, mel_b)):
        t = section * bar
        for m, d in mel:
            tr.add(whistle(m, d * beat * 0.95), t, 0.25)
            t += d * beat
    return tr.render(wet=0.32, decay=3.0)


def compose_battle():
    bpm = 112
    beat = 60 / bpm
    bar = beat * 4
    prog = ["Dm", "Dm", "F", "C", "Dm", "Dm", "G", "Am"] * 3
    tr = Track(len(prog) * bar)
    horn_a = [(62, 2), (69, 2), (67, 1), (65, 1), (64, 1), (62, 1), (65, 2), (72, 2), (67, 3), (64, 1),
              (62, 1.5), (64, .5), (65, 1), (69, 1), (74, 4), (71, 2), (67, 2), (69, 4)]
    for b, ch in enumerate(prog):
        t0 = b * bar
        r, third, fifth = chord_tones(ch)
        # Driving cello ostinato in eighths.
        pattern = [r - 12, r - 12, fifth - 12, r - 12, r, r - 12, fifth - 12, r - 12]
        for k, m in enumerate(pattern):
            acc = 1.0 if k % 4 == 0 else 0.7
            tr.add(cello(m, beat / 2 * 0.9, attack=0.01, bright=1100) * acc, t0 + k * beat / 2, -0.1)
        tr.add(taiko(1.0), t0)
        tr.add(taiko(0.7), t0 + 2.5 * beat)
        for k in range(8):
            if k in (1, 3, 5, 6, 7) or b >= 16:
                tr.add(frame_drum(0.35 + 0.15 * (k % 2)), t0 + k * beat / 2, 0.3 * (1 if k % 2 else -1))
        if b >= 8:
            pl, pr = pad([r + 12, third + 12, fifth + 12], bar)
            tr.add(pl * 1.4, t0, -0.5, pr * 1.4)
    for section, shift in ((8, 0), (16, 12)):
        t = section * bar
        for m, d in horn_a:
            tr.add(horn(m + shift, d * beat * 0.95) * (0.8 if shift else 1.0), t, 0.15)
            if shift:
                tr.add(horn(m, d * beat * 0.95) * 0.6, t, -0.15)
            t += d * beat
    return tr.render(wet=0.22, decay=2.2)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    for name, fn in (("calm", compose_calm), ("battle", compose_battle)):
        audio = fn()
        path = os.path.join(OUT, f"{name}.wav")
        sf.write(path, audio.astype(np.float32), SR, subtype="PCM_16")
        print(name, f"{len(audio) / SR:.1f}s", path)
