"""
concepts_demo.py - One figure that shows every Signals & Systems concept the
project uses, computed on YOUR last recording (or a synthetic vowel).

Run standalone:  py concepts_demo.py            (uses data/test_recordings/latest)
                 py concepts_demo.py file.wav
Or press "S&S Concepts" in the app.
"""

import os
import sys

import numpy as np
import matplotlib
from matplotlib.figure import Figure

import ss_dsp as ss

STYLE = {"axes.facecolor": "white", "figure.facecolor": "white",
         "text.color": "black", "axes.labelcolor": "black",
         "xtick.color": "black", "ytick.color": "black",
         "axes.edgecolor": "black", "font.size": 9}
matplotlib.rcParams.update(STYLE)


def synthetic_vowel(fs, f0=130, dur=0.6):
    """Pulse train (F0) through two formant resonators -> vowel 'aa'."""
    n = np.arange(int(dur * fs))
    x = np.zeros(n.size)
    x[:: int(fs / f0)] = 1.0
    for f, bw in ((730, 90), (1090, 110), (2440, 160)):
        r, w0 = np.exp(-np.pi * bw / fs), 2 * np.pi * f / fs
        a1, a2 = -2 * r * np.cos(w0), r * r
        y = np.zeros_like(x)
        for k in range(x.size):
            y[k] = x[k] - a1 * (y[k - 1] if k else 0) - a2 * (y[k - 2] if k > 1 else 0)
        x = y
    return x / np.max(np.abs(x))


def loudest_frame(y, fs, L):
    """Start index of the 25 ms frame with the most energy (a vowel)."""
    if y.size <= L:
        return 0
    e = np.convolve(y ** 2, np.ones(L), mode="valid")
    return int(np.argmax(e))


def make_concepts_figure(y, fs, cfg, title="your recording"):
    fig = Figure(figsize=(14, 9), dpi=90, facecolor="white")
    fig.suptitle(f"Signals & Systems concepts used in the project  ({title})",
                 fontsize=13, fontweight="bold", color="black")
    ax = [fig.add_subplot(3, 3, i + 1) for i in range(9)]
    L = round(cfg.frame_sec * fs)
    s0 = loudest_frame(y, fs, L)
    frame = y[s0:s0 + L]
    if frame.size < L:
        frame = np.pad(frame, (0, L - frame.size))

    # 1. Sampling: x(t) -> x[n] = x(nTs)
    a = ax[0]
    seg = frame[:80]
    n = np.arange(seg.size)
    tt = np.linspace(0, seg.size - 1, 800)
    a.plot(tt / fs * 1000, np.interp(tt, n, seg), color="0.6", lw=1, label="x(t) (analog idea)")
    a.stem(n / fs * 1000, seg, linefmt="C0-", markerfmt="C0o", basefmt="k-", label="x[n]")
    a.set_title(f"1. Sampling  fs={fs} Hz, Ts={1e6 / fs:.1f} µs")
    a.set_xlabel("time (ms)")
    a.legend(fontsize=7, loc="upper right")

    # 2. Aliasing: why we low-pass before reducing fs
    a = ax[1]
    f_true, fs_low = 6000, 8000
    t = np.arange(0, 0.002, 1 / 200000)
    ts = np.arange(0, 0.002, 1 / fs_low)
    a.plot(t * 1000, np.sin(2 * np.pi * f_true * t), color="0.6", lw=1, label="6 kHz tone")
    a.plot(t * 1000, np.sin(2 * np.pi * (f_true - fs_low) * t), "r--", lw=1.2, label="alias at 2 kHz")
    a.plot(ts * 1000, np.sin(2 * np.pi * f_true * ts), "ko", ms=4, label="samples @ 8 kHz")
    a.set_title("2. Aliasing: f > fs/2 looks like fs - f")
    a.set_xlabel("time (ms)")
    a.legend(fontsize=7, loc="upper right")

    # 3. Convolution: pre-emphasis y = x * h
    a = ax[2]
    yp = ss.pre_emphasis(frame, cfg.pre_emph)
    tm = np.arange(L) / fs * 1000
    a.plot(tm, frame, label="x[n]")
    a.plot(tm, yp, label="y[n] = x[n] - 0.97x[n-1]", alpha=0.8)
    a.set_title("3. Convolution with h[n] = [1, -0.97]")
    a.set_xlabel("time (ms)")
    a.legend(fontsize=7, loc="upper right")

    # 4. Frequency response |H(e^jw)|
    a = ax[3]
    w, H = ss.freq_response([1, -cfg.pre_emph])
    a.plot(w / np.pi * fs / 2, 20 * np.log10(np.abs(H)), "C3")
    a.set_title("4. |H(e^jω)| of pre-emphasis (high-pass)")
    a.set_xlabel("frequency (Hz)")
    a.set_ylabel("dB")
    a.grid(alpha=0.3)

    # 5. Z-plane: pole/zero
    a = ax[4]
    th = np.linspace(0, 2 * np.pi, 300)
    a.plot(np.cos(th), np.sin(th), "k:", lw=1)
    a.plot([cfg.pre_emph], [0], "o", mfc="none", mec="C0", ms=10, mew=2, label=f"zero z={cfg.pre_emph}")
    a.plot([0], [0], "x", color="C3", ms=10, mew=2, label="pole z=0")
    a.axhline(0, color="0.7", lw=0.8)
    a.axvline(0, color="0.7", lw=0.8)
    a.set_aspect("equal")
    a.set_xlim(-1.3, 1.3)
    a.set_ylim(-1.3, 1.3)
    a.set_title("5. Z-plane of H(z) = 1 - 0.97 z⁻¹  (ROC |z|>0, stable)")
    a.legend(fontsize=7, loc="lower left")

    # 6. Windowing & spectral leakage
    a = ax[5]
    nfft = 2048
    f = np.arange(nfft // 2 + 1) * fs / nfft
    Xr = 20 * np.log10(np.abs(np.fft.rfft(frame, nfft)) + 1e-9)
    Xh = 20 * np.log10(np.abs(np.fft.rfft(frame * ss.hamming(L), nfft)) + 1e-9)
    a.plot(f, Xr - Xr.max(), color="0.6", lw=0.8, label="rectangular")
    a.plot(f, Xh - Xh.max(), "C0", lw=1, label="Hamming")
    a.set_xlim(0, 4000)
    a.set_ylim(-80, 5)
    a.set_title("6. Window reduces spectral leakage")
    a.set_xlabel("frequency (Hz)")
    a.legend(fontsize=7)

    # 7. Harmonics (Fourier series) + pitch from autocorrelation
    a = ax[6]
    r = np.correlate(frame, frame, mode="full")[L - 1:]
    lo, hi = int(fs / 400), int(fs / 60)
    lag = lo + int(np.argmax(r[lo:hi])) if hi < r.size else 0
    f0 = fs / lag if lag else 0
    a.plot(f, Xh - Xh.max(), "C0", lw=1)
    if f0:
        for k in range(1, int(3000 // f0) + 1):
            a.axvline(k * f0, color="C3", lw=0.6, alpha=0.6)
    a.set_xlim(0, 3000)
    a.set_ylim(-60, 5)
    a.set_title(f"7. Harmonics at k·F0, F0 ≈ {f0:.0f} Hz (autocorr.)")
    a.set_xlabel("frequency (Hz)")

    # 8. Mel filter bank (parallel band-pass filters)
    a = ax[7]
    Hm = ss.mel_filterbank(cfg.n_mel, cfg.nfft, fs, cfg.mel_low_hz, cfg.mel_high_hz)
    fb = np.arange(cfg.nfft // 2 + 1) * fs / cfg.nfft
    for m in range(cfg.n_mel):
        a.plot(fb, Hm[m], lw=0.8)
    a.set_title(f"8. {cfg.n_mel} mel band-pass filters (parallel)")
    a.set_xlabel("frequency (Hz)")

    # 9. MFCC matrix
    a = ax[8]
    F = ss.mfcc(ss.pre_emphasis(y, cfg.pre_emph), fs, cfg)
    a.imshow(F["C"][1:], aspect="auto", origin="lower", cmap="coolwarm",
             extent=[F["t"][0], F["t"][-1], 1, cfg.n_cep - 1])
    a.set_title("9. MFCC c1..c12 per 10 ms frame (DCT of log-mel)")
    a.set_xlabel("time (s)")
    a.set_ylabel("coefficient")

    fig.tight_layout(rect=[0, 0, 1, 0.96])
    return fig


if __name__ == "__main__":
    cfg = ss.Config()
    path = sys.argv[1] if len(sys.argv) > 1 else None
    if path is None:
        tests = ss.list_wav(cfg.test_dir)
        path = tests[-1] if tests else None
    if path and os.path.exists(path):
        x, fs = ss.read_wav(path)
        y, info = ss.preprocess(x, fs, cfg)
        y = y if info.ok else info.x_full
        name = os.path.basename(path)
    else:
        y, name = synthetic_vowel(cfg.fs), "synthetic vowel 'aa'"
    fig = make_concepts_figure(y, cfg.fs, cfg, name)
    fig.savefig(os.path.join(cfg.root_dir, "concepts.png"))
    print("saved concepts.png")
