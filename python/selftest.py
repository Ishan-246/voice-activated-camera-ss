"""
selftest.py - checks the signal processing WITHOUT a microphone.

Run:  py selftest.py

Synthetic "voices" are made with the source-filter model of speech:
a periodic pulse train (vocal cords, pitch F0) is passed through IIR
resonators (vocal tract formants). Different F0 / formant scaling = a
different speaker; different formant movement = a different word.
Everything is written to a temporary folder, your real data is untouched.
"""

import os
import shutil
import tempfile

import numpy as np

import ss_dsp as ss

PASS, FAIL = 0, 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        print(f"  FAIL  {name}  {detail}")


def resonator(x, f, bw, fs):
    """2nd-order IIR all-pole resonator: poles at r e^{+-j w0}."""
    r = np.exp(-np.pi * bw / fs)
    w0 = 2 * np.pi * f / fs
    a1, a2 = -2 * r * np.cos(w0), r * r
    y = np.zeros_like(x)
    for n in range(len(x)):
        y[n] = x[n] - a1 * (y[n - 1] if n >= 1 else 0) - a2 * (y[n - 2] if n >= 2 else 0)
    return y


# formant trajectories (start -> end, Hz) for three "words"
WORDS = {
    "shoot": [(300, 350), (2300, 900), (3000, 2400)],   # 'sh' noise + 'oo'
    "stop":  [(700, 600), (1300, 1100), (2600, 2500)],
    "zoom":  [(320, 300), (1600, 800), (2500, 2200)],
}


def synth_word(word, f0, scale, fs, rng, dur=0.45):
    n = int(dur * fs)
    t = np.arange(n) / fs
    f0t = f0 * (1 + 0.05 * np.sin(2 * np.pi * 3 * t)) * (1 + 0.02 * rng.standard_normal())
    phase = np.cumsum(f0t / fs)
    src = (np.diff(np.floor(phase), prepend=0) > 0).astype(float)      # pulse train
    if word in ("shoot", "stop"):
        src[: int(0.12 * fs)] = 0.3 * rng.standard_normal(int(0.12 * fs))  # fricative
    if word == "zoom":
        src[: int(0.08 * fs)] += 0.2 * rng.standard_normal(int(0.08 * fs))
    y = np.zeros(n)
    seg = 4
    for k in range(seg):                         # piecewise-stationary formants
        a, b = k * n // seg, (k + 1) * n // seg
        frac = (k + 0.5) / seg
        part = src[a:b]
        for (fs_, fe) in WORDS[word]:
            fc = scale * (fs_ + (fe - fs_) * frac) * (1 + 0.03 * rng.standard_normal())
            part = resonator(part, fc, 90, fs)
        y[a:b] = part
    y *= np.hanning(n)
    y /= np.max(np.abs(y)) + 1e-12
    full = np.concatenate([np.zeros(int(0.4 * fs)), 0.6 * y, np.zeros(int(0.5 * fs))])
    return full + 0.002 * rng.standard_normal(full.size)


def synth_phrase(f0, scale, fs, rng):
    parts = [synth_word(w, f0, scale, fs, rng, 0.3)[int(0.3 * fs):-int(0.4 * fs)]
             for w in ("stop", "zoom", "shoot", "zoom", "stop")]
    full = np.concatenate([np.zeros(int(0.3 * fs))] + parts + [np.zeros(int(0.3 * fs))])
    return full + 0.002 * rng.standard_normal(full.size)


def main():
    cfg0 = ss.Config()
    fs = cfg0.fs
    print("\n1. Basic signals & systems checks")

    # FFT frequency axis: a 1 kHz sine must peak at 1000 Hz
    t = np.arange(fs) / fs
    f, X = ss.spectrum_db(np.sin(2 * np.pi * 1000 * t), fs)
    check("FFT peak of 1 kHz sine is at 1000 Hz", abs(f[np.argmax(X)] - 1000) < 2)

    # Convolution by hand == numpy convolution
    x = np.random.default_rng(0).standard_normal(50)
    h = np.array([1, -0.97])
    check("hand-written convolution sum == np.convolve",
          np.allclose(ss.convolve_by_hand(x, h), np.convolve(x, h)))

    # Pre-emphasis frequency response
    w, H = ss.freq_response([1, -0.97])
    check("|H| at 0 Hz = 0.03 and at fs/2 = 1.97",
          abs(abs(H[0]) - 0.03) < 1e-9 and abs(abs(H[-1]) - 1.97) < 1e-9)

    # Linearity of the pre-emphasis system
    x1, x2 = np.random.default_rng(1).standard_normal((2, 100))
    check("pre-emphasis is linear (superposition)",
          np.allclose(ss.pre_emphasis(2 * x1 + 3 * x2), 2 * ss.pre_emphasis(x1) + 3 * ss.pre_emphasis(x2)))

    # Anti-aliasing: a 12 kHz tone at 48 kHz must vanish after resampling to 16 kHz
    t48 = np.arange(48000) / 48000
    y = ss.resample(np.sin(2 * np.pi * 12000 * t48), 48000, 16000)
    check("12 kHz tone removed by anti-alias filter (would alias to 4 kHz)",
          np.max(np.abs(y[200:-200])) < 0.05, f"max={np.max(np.abs(y[200:-200])):.3f}")

    # Silence rejection
    _, info = ss.preprocess(0.0005 * np.random.default_rng(2).standard_normal(fs), fs, cfg0)
    check("silent recording is rejected", not info.ok)

    # DTW
    A = np.random.default_rng(3).standard_normal((12, 40))
    check("DTW(A, A) == 0", ss.dtw(A, A) == 0)
    check("DTW(A, slowed-down A) small",
          ss.dtw(A, np.repeat(A, 2, axis=1)) < 0.5 * ss.dtw(A, np.random.default_rng(4).standard_normal((12, 80))))

    # Threshold calibration
    thr, inf = ss.calibrate_threshold([1, 2, 3], [5, 6, 7])
    check("threshold between separable groups", 3 < thr < 5 and inf["FAR"] == 0 and inf["FRR"] == 0)

    print("\n2. Full pipeline with synthetic voices (enroll -> train -> recognise)")
    tmp = tempfile.mkdtemp(prefix="vcam_test_")
    try:
        cfg = ss.Config(root_dir=tmp)
        cfg.make_dirs()
        rng = np.random.default_rng(42)
        USER = (120, 1.00)     # pitch, formant scale
        OTHER = (210, 1.18)
        for p in range(len(cfg.phrases)):
            ss.write_wav(os.path.join(cfg.phrase_dir, f"phrase_{p + 1:02d}.wav"),
                         synth_phrase(*USER, fs, rng), fs)
        for c in cfg.commands:
            for r in range(cfg.reps_per_command):
                ss.write_wav(os.path.join(cfg.command_dir, f"{c}_{r + 1:02d}.wav"),
                             synth_word(c, *USER, fs, rng), fs)
            for r in range(cfg.other_reps):
                ss.write_wav(os.path.join(cfg.other_dir, f"{c}_{r + 1:02d}.wav"),
                             synth_word(c, *OTHER, fs, rng), fs)
        model = ss.build_model(cfg)
        print(ss.evaluate(model, cfg))

        r = ss.recognize(synth_word("shoot", *USER, fs, rng), fs, model, cfg)
        check("user says SHOOT -> photo taken", r["trigger"],
              f"spk {r['spk_score']:.2f}/{r['spk_thr']:.2f}, cmd {r['command']}")
        r = ss.recognize(synth_word("stop", *USER, fs, rng), fs, model, cfg)
        check("user says STOP -> no photo, command = stop",
              not r["trigger"] and r["command"] == "stop", r["command"])
        r = ss.recognize(synth_word("shoot", *OTHER, fs, rng), fs, model, cfg)
        check("other speaker says SHOOT -> rejected (speaker check)",
              not r["spk_ok"], f"spk {r['spk_score']:.2f}/{r['spk_thr']:.2f}")
        ss.save_model(model, cfg)
        check("model saves and loads", ss.load_model(cfg) is not None)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print(f"\n{PASS} passed, {FAIL} failed")
    return FAIL == 0


if __name__ == "__main__":
    raise SystemExit(0 if main() else 1)
