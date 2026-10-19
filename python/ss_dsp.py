"""
ss_dsp.py - All signal processing for the Voice-Activated Camera project.

Python rewrite of the MATLAB src/ folder. Only numpy is used for the maths,
and every step is written out by hand so it can be explained in the viva:

    microphone -> sampling (fs = 16 kHz) -> DC removal -> speech trimming
      -> amplitude normalisation
      -> pre-emphasis FIR   y[n] = x[n] - 0.97 x[n-1]     (convolution, Z-transform)
      -> 25 ms frames x Hamming window -> FFT -> |X|^2     (DFT / STFT)
      -> 26 mel band-pass filters -> log -> DCT -> MFCC   (filter bank)
           |-- speaker check : VQ codebook distance  (WHO is speaking)
           |-- command check : DTW template distance (WHAT was said)
      -> camera fires only if  speaker accepted  AND  command == "shoot"
"""

import os
import glob
import wave
import pickle
from dataclasses import dataclass, field
from datetime import datetime

import numpy as np

EPS = np.finfo(float).eps


# =============================================================================
#  Configuration (same values as the MATLAB ss_config.m)
# =============================================================================
@dataclass
class Config:
    root_dir: str = ""

    # Sampling (Unit 1): continuous speech -> discrete-time signal x[n]
    fs: int = 16000                       # speech energy is below 8 kHz = fs/2
    fallback_fs: tuple = (48000, 44100)   # used if the mic refuses 16 kHz

    # Recording lengths (s)
    phrase_sec: float = 3.0
    command_sec: float = 2.0

    # Vocabulary
    commands: tuple = ("shoot", "stop", "zoom")   # only "shoot" triggers
    trigger: str = "shoot"
    reps_per_command: int = 4
    other_reps: int = 2
    phrases: tuple = (
        "The quick brown fox jumps over the lazy dog.",
        "Signals and systems is my favourite subject.",
        "Please take a picture of this beautiful view.",
        "One, two, three, four, five, six, seven, eight.",
    )

    # Recording validity checks (input sanity only, not recognition thresholds)
    min_peak: float = 0.005
    min_snr_db: float = 12.0
    trim_db: float = 30.0
    vad_frac: float = 0.15     # speech threshold: 15% of the way from noise to peak (dB)
    max_gap_sec: float = 0.25  # pauses shorter than this stay inside one word
    vad_min_db: float = 6.0    # ...and always at least 6 dB above the background
    min_speech_sec: float = 0.15
    pad_sec: float = 0.12

    # Feature extraction
    pre_emph: float = 0.97      # H(z) = 1 - 0.97 z^-1
    frame_sec: float = 0.025    # 25 ms frames (speech ~ stationary)
    hop_sec: float = 0.010      # 10 ms hop
    nfft: int = 512
    n_mel: int = 26
    n_cep: int = 13             # c0..c12 (c0 = loudness, dropped)
    mel_low_hz: float = 50.0
    mel_high_hz: float = 7600.0
    speech_frame_db: float = 30.0

    # Speaker model (vector quantisation)
    vq_size: int = 16
    vq_iters: int = 30

    model_version: int = 1

    def __post_init__(self):
        if not self.root_dir:
            self.root_dir = os.path.dirname(os.path.abspath(__file__))
        d = os.path.join(self.root_dir, "data")
        self.data_dir = d
        self.phrase_dir = os.path.join(d, "enroll_phrases")
        self.command_dir = os.path.join(d, "enroll_commands")
        self.other_dir = os.path.join(d, "other_speaker")
        self.test_dir = os.path.join(d, "test_recordings")
        self.model_file = os.path.join(d, "voice_model.pkl")
        r = os.path.join(self.root_dir, "results")
        self.results_dir = r
        self.photo_dir = os.path.join(r, "photos")
        self.log_file = os.path.join(r, "test_log.csv")

    def make_dirs(self):
        for p in (self.phrase_dir, self.command_dir, self.other_dir,
                  self.test_dir, self.photo_dir):
            os.makedirs(p, exist_ok=True)


# =============================================================================
#  WAV file helpers (16-bit PCM, mono)
# =============================================================================
def write_wav(path, x, fs):
    x = np.clip(np.asarray(x, dtype=float).ravel(), -1.0, 1.0)
    pcm = (x * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(int(fs))
        w.writeframes(pcm.tobytes())


def read_wav(path):
    with wave.open(path, "rb") as w:
        fs = w.getframerate()
        nch = w.getnchannels()
        sw = w.getsampwidth()
        raw = w.readframes(w.getnframes())
    if sw == 2:
        x = np.frombuffer(raw, dtype="<i2").astype(float) / 32768.0
    elif sw == 1:
        x = (np.frombuffer(raw, dtype=np.uint8).astype(float) - 128) / 128.0
    elif sw == 4:
        x = np.frombuffer(raw, dtype="<i4").astype(float) / 2147483648.0
    else:
        raise ValueError(f"Unsupported sample width {sw} bytes in {path}")
    if nch > 1:
        x = x.reshape(-1, nch).mean(axis=1)       # stereo -> mono
    return x, fs


def list_wav(folder, pattern="*.wav"):
    return sorted(glob.glob(os.path.join(folder, pattern)))


# =============================================================================
#  Unit 1/2/6 - LTI system: pre-emphasis
# =============================================================================
def pre_emphasis(x, a=0.97):
    """First-order FIR high-pass filter (an LTI system).

    Difference equation : y[n] = x[n] - a x[n-1]
    Impulse response    : h[n] = [1, -a]
    Z-transform         : H(z) = 1 - a z^-1  (zero at z = a, close to z = 1)
    Computed as the convolution sum y[n] = sum_k x[k] h[n-k].
    """
    h = np.array([1.0, -a])
    y = np.convolve(np.ravel(x), h)      # full convolution, length N + 1
    return y[:len(x)]                     # keep the causal part, same length


def convolve_by_hand(x, h):
    """The convolution sum written as two loops (for explaining Unit 2).
    Gives exactly the same result as np.convolve."""
    N, M = len(x), len(h)
    y = np.zeros(N + M - 1)
    for n in range(N + M - 1):
        for k in range(M):
            if 0 <= n - k < N:
                y[n] += h[k] * x[n - k]
    return y


def freq_response(b, a=(1.0,), n=512):
    """H(e^jw) = B(e^jw)/A(e^jw) evaluated on 0..pi (DTFT of the system)."""
    w = np.linspace(0, np.pi, n)
    z = np.exp(1j * w)
    B = sum(bk * z ** (-k) for k, bk in enumerate(b))
    A = sum(ak * z ** (-k) for k, ak in enumerate(a))
    return w, B / A


# =============================================================================
#  Unit 1/4 - Sampling theorem: anti-aliased resampling
# =============================================================================
def resample(x, fs_in, fs_out):
    """Change sampling rate. When going down, first low-pass filter below the
    new Nyquist frequency fs_out/2 with a windowed-sinc FIR (truncated ideal
    low-pass) so that higher frequencies cannot alias. Then interpolate."""
    x = np.ravel(x).astype(float)
    if fs_in == fs_out or x.size == 0:
        return x
    if fs_out < fs_in:
        fc = 0.45 * fs_out                         # just below fs_out/2
        n = np.arange(-50, 51)
        h = np.where(n == 0, 2 * fc / fs_in,
                     np.sin(2 * np.pi * fc * n / fs_in) / (np.pi * np.where(n == 0, 1, n)))
        h = h * (0.54 + 0.46 * np.cos(np.pi * n / 50))   # Hamming taper
        h = h / h.sum()                                   # unity DC gain
        x = np.convolve(x, h, mode="same")
    t_in = np.arange(x.size) / fs_in
    t_out = np.arange(0, t_in[-1] + 1e-12, 1.0 / fs_out)
    return np.interp(t_out, t_in, x)


# =============================================================================
#  Unit 1 - Signal operations: DC removal, segmentation, scaling
# =============================================================================
@dataclass
class PreInfo:
    ok: bool = False
    msg: str = ""
    warning: str = ""
    x_full: np.ndarray = field(default_factory=lambda: np.zeros(0))
    start: int = 0
    end: int = 0
    peak: float = 0.0
    snr_db: float = 0.0


def preprocess(x, fs, cfg, single_word=True):
    """Check a recording and cut out the spoken part.
    Returns (y, info): y = speech only, DC removed, peak-normalised to 1.
    single_word=True keeps only the main word (commands); False keeps
    everything from the first to the last speech frame (phrases)."""
    info = PreInfo()
    x = np.asarray(x, dtype=float)
    if x.size == 0:
        info.msg = "The recording is empty."
        return None, info
    if x.ndim > 1:
        x = x.mean(axis=1)                         # stereo -> mono
    x = np.nan_to_num(x.ravel())

    if fs != cfg.fs:
        x = resample(x, fs, cfg.fs)
        info.warning = f"Audio was resampled from {fs} Hz to {cfg.fs} Hz."
    fs = cfg.fs

    if np.mean(np.abs(x) >= 0.99) > 0.001:
        info.warning = "Recording is clipped (too loud). Move a little away from the mic."

    x = x - x.mean()                               # amplitude shift: remove DC
    info.x_full = x
    info.peak = float(np.max(np.abs(x)))
    if info.peak < cfg.min_peak:
        info.msg = ("No speech detected - the recording is almost silent. "
                    "Speak louder/closer and check Windows microphone permission.")
        return None, info

    # Short-time energy: 20 ms frames, 10 ms hop
    L, H, N = round(0.020 * fs), round(0.010 * fs), x.size
    if N < L:
        info.msg = "The recording is too short."
        return None, info
    nF = (N - L) // H + 1
    idx = np.arange(L)[:, None] + H * np.arange(nF)[None, :]
    e_db = 10 * np.log10(np.sum(x[idx] ** 2, axis=0) + EPS)

    # Background level. Frames of near-digital silence (the microphone's
    # start-up, ~0.1 s) are ignored, otherwise the room would look silent.
    peak_db = e_db.max()
    real = e_db[e_db > np.median(e_db) - 40]
    noise_db = float(np.percentile(real, 10))
    info.snr_db = peak_db - noise_db
    if info.snr_db < cfg.min_snr_db:
        info.msg = ("No clear speech detected - your voice is not much louder than the "
                    "background noise. Speak closer/louder or use a quieter room.")
        return None, info

    # Speech = frames clearly above the background (and within trim_db of the peak)
    thr_db = max(peak_db - cfg.trim_db,
                 noise_db + max(cfg.vad_min_db, cfg.vad_frac * (peak_db - noise_db)))
    act = e_db > thr_db
    if single_word:
        # Group active frames into segments (gaps < max_gap are bridged, e.g. the
        # silent closure before the 'p' of STOP) and keep the most energetic one.
        idxs = np.flatnonzero(act)
        max_gap = round(cfg.max_gap_sec * fs / H)
        segs, s0, prev = [], idxs[0], idxs[0]
        for i in idxs[1:]:
            if i - prev > max_gap:
                segs.append((s0, prev))
                s0 = i
            prev = i
        segs.append((s0, prev))
        e_lin = 10 ** (e_db / 10)
        first, last = max(segs, key=lambda ab: e_lin[ab[0]:ab[1] + 1].sum())
    else:
        idxs = np.flatnonzero(act)
        first, last = idxs[0], idxs[-1]
    pad = round(cfg.pad_sec * fs)
    s = max(0, first * H - pad)
    t = min(N, last * H + L + pad)
    if (t - s) / fs < cfg.min_speech_sec:
        info.msg = "The spoken part was too short. Please say the whole word."
        return None, info
    if last == nF - 1 and not info.warning:
        info.warning = "Speech continued to the end of the recording - it may be cut off."
    if info.snr_db < 25 and not info.warning:
        info.warning = (f"Noisy: your voice is only {info.snr_db:.0f} dB above the background "
                        "(aim for 25+). Move closer to the mic / reduce fan or TV noise.")

    y = x[s:t]
    y = y / np.max(np.abs(y))                      # amplitude scaling
    info.start, info.end, info.ok = s, t, True
    return y, info


# =============================================================================
#  Unit 2/4 - Mel filter bank, STFT and MFCC
# =============================================================================
def hz_to_mel(f):
    return 2595.0 * np.log10(1.0 + np.asarray(f) / 700.0)


def mel_to_hz(m):
    return 700.0 * (10.0 ** (np.asarray(m) / 2595.0) - 1.0)


def mel_filterbank(n_mel, nfft, fs, f_low, f_high):
    """n_mel triangular band-pass filters (rows) sampled at FFT bins
    f_k = k fs / nfft. They are applied in PARALLEL to the same spectrum."""
    edges = mel_to_hz(np.linspace(hz_to_mel(f_low), hz_to_mel(f_high), n_mel + 2))
    f = np.arange(nfft // 2 + 1) * fs / nfft
    Hm = np.zeros((n_mel, f.size))
    for m in range(n_mel):
        fl, fc, fr = edges[m], edges[m + 1], edges[m + 2]
        Hm[m] = np.maximum(0, np.minimum((f - fl) / (fc - fl), (fr - f) / (fr - fc)))
    return Hm


def hamming(L):
    """w[n] = 0.54 - 0.46 cos(2 pi n / (L-1))"""
    n = np.arange(L)
    return 0.54 - 0.46 * np.cos(2 * np.pi * n / (L - 1))


def dct_matrix(n_out, n_in):
    """Orthonormal DCT-II matrix."""
    k = np.arange(n_out)[:, None]
    m = np.arange(n_in)[None, :]
    D = np.sqrt(2.0 / n_in) * np.cos(np.pi * k * (m + 0.5) / n_in)
    D[0] /= np.sqrt(2.0)
    return D


def mfcc(x, fs, cfg):
    """Short-time Fourier analysis + MFCC.
    Returns dict: C (n_cep x frames), logE, P (power spectrogram), f, t."""
    x = np.ravel(x)
    L, H = round(cfg.frame_sec * fs), round(cfg.hop_sec * fs)
    if x.size < L:
        x = np.concatenate([x, np.zeros(L - x.size)])
    nF = 1 + (x.size - L) // H
    idx = np.arange(L)[:, None] + H * np.arange(nF)[None, :]
    frames = x[idx] * hamming(L)[:, None]           # windowing (multiplication)

    nfft = max(cfg.nfft, int(2 ** np.ceil(np.log2(L))))
    X = np.fft.rfft(frames, n=nfft, axis=0)         # DFT of each frame
    P = np.abs(X) ** 2 / nfft                       # power spectrum

    Hm = mel_filterbank(cfg.n_mel, nfft, fs, cfg.mel_low_hz, min(cfg.mel_high_hz, fs / 2))
    log_mel = np.log(Hm @ P + 1e-10)                # filter bank energies, log
    C = dct_matrix(cfg.n_cep, cfg.n_mel) @ log_mel  # cepstrum

    return {
        "C": C,
        "logE": 10 * np.log10(np.sum(frames ** 2, axis=0) + EPS),
        "P": P,
        "f": np.arange(nfft // 2 + 1) * fs / nfft,
        "t": (np.arange(nF) * H + L / 2) / fs,
    }


def features(y, fs, cfg):
    """spk: MFCC c1..c12 of loud frames (order ignored -> HOW the voice sounds)
       cmd: MFCC c1..c12 of all frames, mean removed (order kept -> WHAT is said)"""
    F = mfcc(pre_emphasis(y, cfg.pre_emph), fs, cfg)
    C = F["C"][1:cfg.n_cep]                          # drop c0 (loudness)
    keep = F["logE"] > F["logE"].max() - cfg.speech_frame_db
    return {"spk": C[:, keep], "cmd": C - C.mean(axis=1, keepdims=True)}


def spectrum_db(x, fs):
    """Single-sided magnitude spectrum in dB, f_k = k fs / N, 0..fs/2."""
    x = np.ravel(x)
    N = int(2 ** np.ceil(np.log2(max(x.size, 2))))
    X = np.fft.rfft(x * hamming(x.size), n=N)
    mag = np.abs(X) / max(x.size, 1)
    return np.arange(N // 2 + 1) * fs / N, 20 * np.log10(mag + 1e-12)


# =============================================================================
#  Pattern matching: DTW (command) and VQ (speaker)
# =============================================================================
def dtw(A, B):
    """Dynamic time warping distance between A (d x n) and B (d x m),
    normalised by (n + m). Lower = more similar."""
    n, m = A.shape[1], B.shape[1]
    C = np.sqrt(((A.T[:, None, :] - B.T[None, :, :]) ** 2).sum(axis=2))   # n x m
    D = np.full((n + 1, m + 1), np.inf)
    D[0, 0] = 0.0
    for i in range(1, n + 1):
        Ci = C[i - 1]
        prev, cur = D[i - 1], D[i]
        for j in range(1, m + 1):
            cur[j] = Ci[j - 1] + min(prev[j], cur[j - 1], prev[j - 1])
    return D[n, m] / (n + m)


def sqdist(A, B):
    """Squared Euclidean distances between columns of A (d x n) and B (d x m)."""
    D = (A ** 2).sum(0)[:, None] + (B ** 2).sum(0)[None, :] - 2 * A.T @ B
    return np.maximum(D, 0)


def vq_train(X, K, n_iter):
    """k-means codebook (d x K): each codeword = one 'typical sound' of the voice."""
    N = X.shape[1]
    K = min(K, N)
    CB = X[:, np.round(np.linspace(0, N - 1, K)).astype(int)].copy()
    for _ in range(n_iter):
        Dm = sqdist(X, CB)
        a = Dm.argmin(axis=1)
        d_min = Dm.min(axis=1)
        for k in range(K):
            members = a == k
            if members.any():
                CB[:, k] = X[:, members].mean(axis=1)
            else:
                far = d_min.argmax()
                CB[:, k] = X[:, far]
                d_min[far] = 0
    return CB


def train_speaker(feat_list, cfg):
    allX = np.hstack(feat_list)
    mu = allX.mean(axis=1, keepdims=True)
    sd = allX.std(axis=1, ddof=1, keepdims=True) + EPS
    return {"mu": mu, "sd": sd, "CB": vq_train((allX - mu) / sd, cfg.vq_size, cfg.vq_iters)}


def speaker_score(X, sm):
    """Mean distance of each frame to its nearest codeword. Lower = more like you."""
    Z = (X - sm["mu"]) / sm["sd"]
    return float(np.mean(np.sqrt(sqdist(Z, sm["CB"]).min(axis=1))))


def calibrate_threshold(G, I):
    """Pick a distance threshold from measured genuine (G) / impostor (I) scores.
    With impostors: minimise FRR + FAR. Without: max(G) + std(G), PROVISIONAL."""
    G, I = np.ravel(G), np.ravel(I)
    if G.size == 0:
        raise ValueError("No genuine scores for calibration.")
    if I.size == 0:
        thr = float(G.max() + (G.std(ddof=1) if G.size > 1 else 0))
        return thr, {"provisional": True, "FRR": float(np.mean(G > thr)), "FAR": float("nan")}
    s = np.unique(np.concatenate([G, I]))
    step = max(1e-9, 1e-6 * np.abs(s).max())
    cands = np.concatenate([[s[0] - step], (s[:-1] + s[1:]) / 2, [s[-1] + step]])
    errs = np.array([np.mean(G > c) + np.mean(I <= c) for c in cands])
    best = np.flatnonzero(errs == errs.min())
    thr = float(cands[best[(best.size + 1) // 2 - 1]])
    return thr, {"provisional": False, "FRR": float(np.mean(G > thr)),
                 "FAR": float(np.mean(I <= thr))}


def classify_command(X, cm, exclude=-1):
    """Nearest-template recognition with rejection.
    norm score s(c) = d(c)/thr(c); accept only if exactly one s(c) <= 1."""
    labels = cm["labels"]
    d = np.full(len(labels), np.inf)
    for t, T in enumerate(cm["templates"]):
        if t == exclude:
            continue
        c = cm["template_class"][t]
        d[c] = min(d[c], dtw(X, T))
    s = d / cm["thr"]
    order = np.argsort(s)
    r = {"dist": d, "norm": s, "best": int(order[0])}
    if s[order[0]] <= 1 and (len(labels) == 1 or s[order[1]] > 1):
        r.update(command=labels[order[0]], accepted=True,
                 reason="matches exactly one enrolled command")
    elif s[order[0]] <= 1:
        r.update(command="uncertain", accepted=False,
                 reason=f'close to both "{labels[order[0]].upper()}" and "{labels[order[1]].upper()}"')
    else:
        r.update(command="unknown", accepted=False,
                 reason=f'not close enough to any command (nearest: "{labels[order[0]].upper()}")')
    return r


# =============================================================================
#  Training and recognition
# =============================================================================
def _load_features(files, cfg, log=print, single_word=True):
    feats, ok_files = [], []
    for f in files:
        try:
            x, fs = read_wav(f)
        except Exception as e:
            log(f"Could not read {os.path.basename(f)}: {e}")
            continue
        y, info = preprocess(x, fs, cfg, single_word)
        if not info.ok:
            log(f"Skipped {os.path.basename(f)}: {info.msg}")
            continue
        feats.append(features(y, cfg.fs, cfg))
        ok_files.append(f)
    return feats, ok_files


def build_model(cfg, log=print):
    """Train + calibrate both recognisers from the saved WAV files."""
    phrase_feat, _ = _load_features(list_wav(cfg.phrase_dir, "phrase_*.wav"), cfg, log,
                                    single_word=False)
    cmd_feat, cmd_files, cmd_class = [], [], []
    for c, name in enumerate(cfg.commands):
        f, okf = _load_features(list_wav(cfg.command_dir, f"{name}_*.wav"), cfg, log)
        if len(f) < 2:
            raise RuntimeError(f'Too few usable recordings of "{name.upper()}" '
                               f'(found {len(f)}, need 2). Please enroll again.')
        cmd_feat += f
        cmd_files += okf
        cmd_class += [c] * len(f)
    cmd_class = np.array(cmd_class)
    other_feat, other_files = _load_features(list_wav(cfg.other_dir), cfg, log)

    # ---- Speaker model, genuine scores by leave-one-out ----
    user_spk = [f["spk"] for f in phrase_feat] + [f["spk"] for f in cmd_feat]
    nP = len(phrase_feat)
    sm = train_speaker(user_spk, cfg)
    G = np.array([speaker_score(cmd_feat[i]["spk"],
                                train_speaker(user_spk[:nP + i] + user_spk[nP + i + 1:], cfg))
                  for i in range(len(cmd_feat))])
    I = np.array([speaker_score(f["spk"], sm) for f in other_feat])
    spk_thr, spk_info = calibrate_threshold(G, I)

    # ---- Command model (DTW templates) ----
    templates = [f["cmd"] for f in cmd_feat]
    rows = templates + [f["cmd"] for f in phrase_feat]
    nT = len(templates)
    Dall = np.zeros((len(rows), nT))
    for r in range(len(rows)):
        for t in range(nT):
            if r < nT and t < r:
                Dall[r, t] = Dall[t, r]          # DTW is symmetric
            elif r != t:
                Dall[r, t] = dtw(rows[r], templates[t])
    row_class = np.concatenate([cmd_class, -np.ones(len(phrase_feat), int)])
    nC = len(cfg.commands)
    thr = np.zeros(nC)
    calib, Gc, Ic = [], [], []
    for c in range(nC):
        inC = np.flatnonzero(cmd_class == c)
        g = np.array([Dall[k, inC[inC != k]].min() for k in inC])
        imp = np.array([Dall[k, inC].min() for k in np.flatnonzero(row_class != c)])
        thr[c], ci = calibrate_threshold(g, imp)
        calib.append(ci)
        Gc.append(g)
        Ic.append(imp)

    return {
        "speaker": {"sm": sm, "thr": spk_thr, "calib": spk_info,
                    "genuine": G, "impostor": I},
        "command": {"labels": list(cfg.commands), "templates": templates,
                    "template_class": cmd_class, "files": cmd_files,
                    "thr": thr, "calib": calib, "genuine": Gc, "impostor": Ic},
        "trigger": cfg.trigger, "fs": cfg.fs, "version": cfg.model_version,
        "created": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "n_phrases": nP, "n_commands": nT, "n_other": len(other_feat),
    }


def save_model(model, cfg):
    with open(cfg.model_file, "wb") as f:
        pickle.dump(model, f)


def load_model(cfg):
    if not os.path.exists(cfg.model_file):
        return None
    with open(cfg.model_file, "rb") as f:
        m = pickle.load(f)
    return m if m.get("version") == cfg.model_version else None


def recognize(x, fs, model, cfg):
    """Speaker check + command check + camera decision for one recording."""
    y, info = preprocess(x, fs, cfg)
    res = {"info": info, "y": y, "ok": info.ok, "spk_score": float("nan"),
           "spk_thr": model["speaker"]["thr"], "spk_ok": False,
           "command": "none", "cmd_ok": False, "cmd_reason": info.msg,
           "cmd_norm": None, "trigger": False}
    if not info.ok:
        return res
    feat = features(y, cfg.fs, cfg)
    res["spk_score"] = speaker_score(feat["spk"], model["speaker"]["sm"])
    res["spk_ok"] = res["spk_score"] <= model["speaker"]["thr"]
    r = classify_command(feat["cmd"], model["command"])
    res.update(command=r["command"], cmd_ok=r["accepted"],
               cmd_reason=r["reason"], cmd_norm=r["norm"])
    res["trigger"] = res["spk_ok"] and res["cmd_ok"] and res["command"] == model["trigger"]
    return res


def evaluate(model, cfg, log=print):
    """Leave-one-out report on enrollment + other-speaker recordings."""
    cm = model["command"]
    lines = ["EVALUATION REPORT", "=" * 40]
    correct = 0
    for t, T in enumerate(cm["templates"]):
        r = classify_command(T, cm, exclude=t)
        correct += r["command"] == cm["labels"][cm["template_class"][t]]
    n = len(cm["templates"])
    lines.append(f"Command recognition (leave-one-out): {correct}/{n} = {100 * correct / n:.0f}%")
    for c, lab in enumerate(cm["labels"]):
        ci = cm["calib"][c]
        lines.append(f"  {lab.upper():6s} thr={cm['thr'][c]:.3f}  FRR={100 * ci['FRR']:.0f}%  "
                     f"FAR={100 * ci['FAR']:.0f}%")
    sp = model["speaker"]
    G, I = sp["genuine"], sp["impostor"]
    lines.append("")
    lines.append(f"Speaker threshold = {sp['thr']:.3f}"
                 + ("  (PROVISIONAL - no other speaker recorded)" if sp["calib"]["provisional"] else ""))
    lines.append(f"  Your recordings accepted : {np.sum(G <= sp['thr'])}/{G.size}"
                 f"  (FRR = {100 * np.mean(G > sp['thr']):.0f}%)")
    if I.size:
        lines.append(f"  Other speaker accepted   : {np.sum(I <= sp['thr'])}/{I.size}"
                     f"  (FAR = {100 * np.mean(I <= sp['thr']):.0f}%)")
    lines.append(f"  Genuine scores : {np.round(G, 3).tolist()}")
    if I.size:
        lines.append(f"  Impostor scores: {np.round(I, 3).tolist()}")
    return "\n".join(lines)


# =============================================================================
#  Simulated camera photo
# =============================================================================
def simulated_photo(rng=None):
    rng = rng or np.random.default_rng()
    H, W = 240, 320
    Y, X = np.mgrid[0:H, 0:W]
    frac = (Y / H)[..., None]
    img = np.array([0.30, 0.55, 0.95]) * (1 - frac) + np.array([0.85, 0.92, 1.0]) * frac
    cx, cy = 50 + 220 * rng.random(), 45 + 25 * rng.random()
    img[(X - cx) ** 2 + (Y - cy) ** 2 < 22 ** 2] = [1.0, 0.9, 0.3]
    img[Y > 150 + 20 * np.sin(2 * np.pi * X / (180 + 80 * rng.random()) + 2 * np.pi * rng.random())] = [0.35, 0.55, 0.40]
    img[Y > 185 + 12 * np.sin(2 * np.pi * X / (120 + 60 * rng.random()) + 2 * np.pi * rng.random())] = [0.20, 0.62, 0.25]
    return np.clip(img, 0, 1)


def shutter_sound(fs=16000):
    """Short decaying noise burst = 'click'."""
    rng = np.random.default_rng(1)
    n = np.arange(int(0.08 * fs))
    return 0.6 * rng.standard_normal(n.size) * np.exp(-n / (0.012 * fs))
