# Viva Guide – Voice-Activated Camera Simulation

---

## PART A – The project

### A1. The 30-second answer ("What is your project?")
> "Our project is a voice-activated camera. You say a command into the laptop microphone. The program checks two things: **who** is speaking (speaker verification) and **what** they said (command recognition). The simulated camera obeys three voice commands, but only from the enrolled user: **ZOOM** zooms in (1×→2×→3×), **STOP** resets it to standby, and **SHOOT** takes the photo. Anyone else's voice, or an unclear word, leaves the camera locked. To do this we treat speech as a discrete-time signal and use Signals & Systems tools on it: sampling, an LTI filter (convolution and z-transform), windowing, the FFT, a filter bank, and the DCT. These give MFCC features, which we match with VQ for the speaker and with DTW for the command."

### A2. The 2-minute answer (walk through the block diagram)

```
 Mic (analog x(t))
   │  sampling, fs = 16 kHz                         ← Unit 1, sampling theorem
   ▼
 x[n] ── DC removal ── trim silence ── normalise    ← signal operations
   │
   ▼
 Pre-emphasis  y[n] = x[n] − 0.97·x[n−1]            ← LTI system, convolution, H(z)
   │
   ▼
 Split into 25 ms frames (10 ms hop) × Hamming window   ← windowing
   │
   ▼
 FFT of each frame → |X(k)|²  (power spectrum)      ← DFT / STFT
   │
   ▼
 26 triangular mel band-pass filters (in parallel)  ← filter bank
   │
   ▼
 log → DCT → 12 MFCC numbers per frame              ← "cepstrum"
   │
   ├──► Speaker check: distance to my VQ codebook (16 "typical sounds" of my voice)
   └──► Command check: DTW distance to my SHOOT/STOP/ZOOM templates
   ▼
 If speaker accepted:  ZOOM → zoom in,  STOP → reset,  SHOOT → photo
 Otherwise (other voice / unknown word) → camera locked
```

Say it like this:
1. **Recording.** The microphone gives a continuous signal. We sample it at 16 kHz, which gives about 16 000 numbers per second. Speech energy is mostly below 8 kHz, and 8 kHz is half of 16 kHz, so by the sampling theorem nothing important is lost.
2. **Cleaning.** We subtract the mean to remove DC offset. We find where the speech is using short-time energy and cut away the silence. Then we scale the signal so its peak is 1, so loudness doesn't matter.
3. **Pre-emphasis.** This is a first-order FIR high-pass filter. Voiced speech has much more energy at low frequencies, so this filter boosts the highs to balance the spectrum.
4. **Framing and windowing.** Speech keeps changing, but over about 25 ms it is roughly stationary. So we cut it into 25 ms frames and multiply each frame by a Hamming window to reduce spectral leakage.
5. **FFT.** We compute the spectrum of every frame. All the frames together form the **spectrogram** (the bottom-left plot).
6. **Mel filter bank.** There are 26 band-pass filters, spaced like human hearing: narrow at low frequencies and wide at high ones. Each filter gives one energy value.
7. **log + DCT → MFCC.** Taking the log makes the values behave like loudness in dB. The DCT then decorrelates the 26 values and compacts them into a few coefficients. We keep c1 to c12. These describe the **shape of the spectrum**, which is set by the vocal tract.
8. **Speaker check (VQ).** At enrollment, all my MFCC frames are grouped into 16 clusters with k-means. That gives my "codebook". For a new voice, we measure the average distance of its frames to the nearest codeword. A small distance means it's me.
9. **Command check (DTW).** Each enrolled word is a sequence of MFCC frames. Dynamic Time Warping lines up two sequences even if one is said faster, then measures the distance. The nearest template wins, but only if it is within that word's threshold.
10. **Thresholds** are not guessed. They come from leave-one-out testing on our own recordings and the other speaker's recordings.

### A3. Why the "unknown" / "uncertain" results?
The system **rejects instead of guessing**. A word is "unknown" if its DTW distance to every command is above that command's calibrated threshold. It is "uncertain" if it is within the threshold of two commands (SHOOT and ZOOM share the vowel "oo"). Like a security system, it prefers a false rejection to a false acceptance.

### A3b. Why two separate checks?
- The **speaker check ignores the order of frames**. It only asks whether these sounds come from this voice. That's why we use VQ, which treats the frames as a "bag of sounds".
- The **command check depends on order**. "Stop" and "pots" contain the same sounds in a different order. That's why we use DTW, which keeps the time order.

### A4. Things examiners like to hear (limitations)
- A recording of my voice played through a speaker would fool it. There is no liveness detection.
- It is speaker-dependent: it only knows the words as *I* said them at enrollment.
- Noise and a different microphone reduce accuracy.
- The data set is small (16 recordings), so the accuracy numbers are only indicative.
- Possible improvements: more training data, GMM or neural-network models, noise reduction (spectral subtraction), Δ-MFCC features.

### A5. Demo plan in the lab
1. Open the app (already enrolled). Press TEST and say **SHOOT** → photo.
2. Say **ZOOM** twice → the viewfinder zooms to 2× and then 3×. Say **SHOOT** → a zoomed photo. Say **STOP** → back to 1×, standby.
3. Have a friend say **SHOOT** → locked ("voice not recognised").
4. Point to the 4 plots: waveform (time domain), spectrum (frequency domain), spectrogram (time-frequency), camera.
5. Press **S&S Concepts** and go through the 9 plots. This is where you link the project to the syllabus.

---

## PART B – Where each syllabus concept is in the code

| Concept | Where | One-line explanation |
|---|---|---|
| Sampling, x[n] = x(nTs) | `record()`, fs = 16 kHz | Ts = 1/16000 = 62.5 µs |
| Sampling theorem / aliasing | `resample()` | Before going from 48 kHz down to 16 kHz we low-pass filter below 8 kHz; otherwise a 12 kHz tone would show up at 4 kHz |
| Signal operations | `preprocess()` | DC removal = amplitude shift; trimming = time segmentation; normalisation = amplitude scaling |
| Energy of a signal | `preprocess()` | E = Σ x²[n] per frame is used to detect speech |
| LTI system, impulse response | `pre_emphasis()` | h[n] = δ[n] − 0.97 δ[n−1] |
| Convolution sum | `np.convolve`, `convolve_by_hand()` | y[n] = Σ x[k] h[n−k] |
| System properties | pre-emphasis | linear, time-invariant, causal, stable (FIR), has memory |
| Z-transform, pole-zero | concepts plot 5 | H(z) = 1 − 0.97 z⁻¹ → zero at 0.97, pole at 0 |
| Frequency response | concepts plot 4 | H(e^jω) = 1 − 0.97 e^−jω; \|H\| = 0.03 at DC, 1.97 at fs/2 → high-pass |
| Fourier series | concepts plot 7 | Voiced speech is quasi-periodic, so its spectrum has harmonics at k·F0 |
| Correlation | concepts plot 7 | Autocorrelation peak gives the pitch period → F0 |
| DFT / FFT | `mfcc()`, `spectrum_db()` | f_k = k·fs/N, Δf = fs/N |
| Windowing / leakage | `hamming()`, concepts plot 6 | Multiplying in time = convolving in frequency → a smoother window gives lower sidelobes |
| STFT / spectrogram | bottom-left plot | FFT of short overlapping frames |
| Filter bank (parallel systems) | `mel_filterbank()` | 26 band-pass filters on the same input |
| Series (cascade) systems | whole chain | pre-emphasis → window → FFT → mel → log → DCT |
| Frequency-domain filtering | `Hm @ P` | Filtering = multiplying the spectrum by H(f) |
| Source-filter model | `selftest.py` | Pulse train (vocal cords) → IIR resonators (vocal tract) = synthetic speech |
| Laplace transform | (not in code) | The analog mic/amplifier path is continuous-time; Laplace is the continuous-time counterpart of the z-transform (z = e^{sTs}) |

---

## PART C – Syllabus viva questions with short answers

### Unit 1 – Signals and systems basics
1. **What is a signal?** A function of one or more independent variables (usually time) that carries information. Speech is a function of time, x(t).
2. **Continuous-time vs discrete-time?** CT is defined for every t, written x(t). DT is defined only at integer n, written x[n]. Our audio becomes DT after sampling.
3. **Analog vs digital?** Analog has continuous amplitude. Digital is DT *and* has quantised amplitude (16-bit in our WAV files).
4. **Even and odd signals?** Even: x(−t) = x(t), e.g. cos. Odd: x(−t) = −x(t), e.g. sin. Every signal = even part + odd part, where xe = [x(t)+x(−t)]/2 and xo = [x(t)−x(−t)]/2.
5. **Periodic signal?** x(t+T) = x(t) for all t. A DT sinusoid cos(ω₀n) is periodic only if ω₀/2π is a ratio of integers.
6. **Energy vs power signal?** Energy E = Σ\|x[n]\|². An energy signal has finite E (and zero power), e.g. one spoken word. A power signal has finite non-zero average power (and infinite E), e.g. a sinusoid or a periodic signal.
7. **Deterministic vs random?** Deterministic signals are fully predictable, e.g. a sine. Random signals can only be described statistically, e.g. noise. Speech is usually modelled as random.
8. **Standard signals?** Unit impulse δ[n], unit step u[n], ramp r[n], exponential, sinusoid. Note δ[n] = u[n] − u[n−1] and u[n] = Σ δ[n−k].
9. **Signal operations?** Time shifting x(t−t₀), time scaling x(at), time reversal x(−t), amplitude scaling, addition, multiplication. Do shifting before scaling: x(at−b) = x(a(t − b/a)).
10. **System classification?** Linear/non-linear, time-invariant/variant, causal/non-causal, stable/unstable, memory/memoryless, invertible.
11. **How do you test linearity?** Superposition: T{a·x1 + b·x2} = a·T{x1} + b·T{x2}. Example: y = x² is not linear. Also, y = x + 2 is not linear, because zero input gives non-zero output.
12. **How do you test time invariance?** Delay the input by n₀. If the output is just delayed by n₀, the system is TI. Example: y[n] = n·x[n] is time-variant.
13. **Causal?** The output depends only on present and past inputs. Pre-emphasis y[n] = x[n] − 0.97x[n−1] is causal.
14. **BIBO stable?** Every bounded input gives a bounded output. For an LTI system this holds iff Σ\|h[n]\| < ∞ (for CT, ∫\|h(t)\|dt < ∞).
15. **Is our pre-emphasis system stable?** Yes. It is FIR and Σ\|h\| = 1 + 0.97 = 1.97, which is finite.

### Unit 2 – LTI systems, convolution
16. **Why is the impulse response important?** For an LTI system, h[n] tells you everything. Output = input convolved with h: y = x * h.
17. **Convolution sum / integral?** y[n] = Σₖ x[k] h[n−k]; y(t) = ∫ x(τ) h(t−τ) dτ.
18. **Steps of graphical convolution?** Flip h, shift it by n, multiply with x point by point, and sum. Repeat for every n.
19. **Length of a linear convolution?** N + M − 1. Our pre-emphasis output is N+1 samples, and we keep the first N.
20. **Properties of convolution?** Commutative, associative (series systems: h1 * h2), distributive (parallel systems: h1 + h2). Identity: x * δ = x. Shift: x * δ[n−k] = x[n−k].
21. **FIR vs IIR?** FIR has a finite h[n], no feedback, and is always stable (our pre-emphasis). IIR has feedback, an infinite h[n], and may be unstable (the formant resonators in selftest).
22. **Difference equation of an LTI system?** Σ aₖ y[n−k] = Σ bₖ x[n−k]. Ours: y[n] = x[n] − 0.97 x[n−1], so b = [1, −0.97] and a = [1].
23. **Step response from the impulse response?** s[n] = Σ_{k≤n} h[k] (running sum). In CT, s(t) = ∫ h.
24. **Causality / stability from h?** Causal iff h[n] = 0 for n < 0. Stable iff Σ\|h[n]\| < ∞.
25. **Correlation vs convolution?** Correlation is convolution without the flip: r_xy[l] = Σ x[n] y[n−l]. Autocorrelation peaks at lag 0, and also at the pitch period for voiced speech. We use this to find F0.

### Unit 3 – Fourier series
26. **What is a Fourier series?** Any periodic signal can be written as a sum of sinusoids at multiples (harmonics) of its fundamental frequency: x(t) = Σ cₖ e^{jkω₀t}.
27. **Trigonometric form?** x(t) = a₀ + Σ [aₙ cos nω₀t + bₙ sin nω₀t].
28. **Coefficient formula?** cₖ = (1/T) ∫_T x(t) e^{−jkω₀t} dt.
29. **Dirichlet conditions?** The signal must be absolutely integrable over one period, with a finite number of maxima/minima and a finite number of discontinuities.
30. **Even/odd symmetry shortcuts?** An even signal has only cosine terms (bₙ = 0). An odd signal has only sine terms (a₀ = aₙ = 0). Half-wave symmetry gives only odd harmonics.
31. **Gibbs phenomenon?** Near a discontinuity, a truncated Fourier series overshoots by about 9%, however many terms you add.
32. **Parseval's theorem (FS)?** Average power = Σ\|cₖ\|².
33. **Where is the Fourier series in your project?** Voiced sounds ("oo" in shoot) are almost periodic, with period = pitch period. So the spectrum shows lines at F0, 2F0, 3F0, … These are the horizontal stripes in the spectrogram and concepts plot 7.
34. **Line spectrum vs continuous spectrum?** Periodic signals have discrete (line) spectra. Aperiodic signals have continuous spectra (the Fourier transform).

### Unit 4 – Fourier transform, sampling, DFT
35. **CTFT definition?** X(jω) = ∫ x(t) e^{−jωt} dt; inverse x(t) = (1/2π) ∫ X(jω) e^{jωt} dω.
36. **FT of standard signals?** δ(t) → 1. 1 → 2πδ(ω). Rectangular pulse → sinc. e^{−at}u(t) → 1/(a + jω). cos ω₀t → π[δ(ω−ω₀) + δ(ω+ω₀)].
37. **Key FT properties?** Linearity; time shift (→ e^{−jωt₀} X); frequency shift (modulation); time scaling (x(at) → (1/\|a\|) X(ω/a)); duality; differentiation (→ jω X); **convolution ↔ multiplication**; Parseval.
38. **Why is "convolution in time = multiplication in frequency" useful?** You can analyse a filter just by multiplying spectra: Y = X·H. That's what the mel filter bank does. The dual also holds: multiplying by a window in time convolves the spectra, which causes leakage.
39. **DTFT vs DFT?** The DTFT X(e^jω) is continuous in ω and periodic with 2π. The DFT is N samples of the DTFT: X[k] = Σ x[n] e^{−j2πkn/N}.
40. **What is the FFT?** A fast algorithm for the DFT. It costs O(N log N) instead of O(N²). For N = 512 that's about 4 600 operations instead of 262 000.
41. **Frequency of DFT bin k?** f_k = k·fs/N. Resolution Δf = fs/N. Ours: 16000/512 = 31.25 Hz per bin for the 512-point frames.
42. **Why plot only 0 to fs/2?** For a real signal the spectrum is conjugate-symmetric, so the upper half mirrors the lower half.
43. **Sampling theorem?** A band-limited signal with highest frequency f_max can be reconstructed exactly if fs > 2·f_max. 2·f_max is the **Nyquist rate**, and fs/2 is the **Nyquist frequency**.
44. **What is aliasing?** If fs is too low, a frequency f > fs/2 appears as fs − f (folding). Example in concepts plot 2: a 6 kHz tone sampled at 8 kHz looks like 2 kHz.
45. **How do you prevent aliasing?** Use an analog anti-aliasing low-pass filter before the ADC, or a digital low-pass filter before downsampling. Our `resample()` does the digital version.
46. **What happens to the spectrum when you sample?** It becomes periodic: copies repeat every fs. If the copies overlap, that overlap is aliasing.
47. **Ideal reconstruction?** Pass the samples through an ideal low-pass filter at fs/2, which means sinc interpolation.
48. **Why 16 kHz for speech?** Intelligible speech sits roughly between 100 Hz and 7 kHz, so 16 kHz covers it. Telephones use 8 kHz (up to 3.4 kHz) and music uses 44.1 kHz.
49. **Spectral leakage? Why use a window?** Cutting a frame is the same as multiplying by a rectangle, whose spectrum (sinc) has high sidelobes. These smear energy into nearby bins. A Hamming window has much lower sidelobes (about −43 dB vs −13 dB) but a wider main lobe.
50. **What is the STFT / spectrogram?** The FFT of short overlapping windowed frames, plotted as frequency against time. It shows how the spectrum changes. There is a trade-off: a longer window gives better frequency resolution but worse time resolution.
51. **Parseval (DFT)?** Σ\|x[n]\|² = (1/N) Σ\|X[k]\|². Energy is the same in both domains.
52. **Magnitude and phase spectrum?** X = \|X\|e^{j∠X}. We use only the magnitude, because the ear is mostly insensitive to phase.

### Unit 5 – Laplace transform
53. **Definition?** X(s) = ∫ x(t) e^{−st} dt, with s = σ + jω. The Fourier transform is the Laplace transform on the jω axis (if the ROC includes it).
54. **Why use Laplace instead of Fourier?** It exists for signals that grow, e.g. e^{t}u(t). It handles initial conditions and makes transient and stability analysis easy.
55. **ROC?** The set of s where the integral converges. Right-sided signal → right half-plane. Left-sided signal → left half-plane. The ROC never contains poles.
56. **Standard pairs?** δ(t) → 1. u(t) → 1/s. e^{−at}u(t) → 1/(s+a). t·u(t) → 1/s². sin ω₀t·u(t) → ω₀/(s²+ω₀²). cos ω₀t·u(t) → s/(s²+ω₀²).
57. **Properties?** Linearity; time shift (e^{−st₀}); differentiation (sX(s) − x(0⁻)); integration (X/s); convolution (product); initial value theorem x(0⁺) = lim_{s→∞} sX(s); final value theorem x(∞) = lim_{s→0} sX(s).
58. **Transfer function?** H(s) = Y(s)/X(s), the Laplace transform of h(t) with zero initial conditions.
59. **Stability in the s-plane?** A causal system is stable iff all poles are in the **left half-plane** (equivalently, the ROC includes the jω axis).
60. **Solving a differential equation?** Take the Laplace transform, which turns derivatives into multiplications by s. Solve for Y(s), use partial fractions, then take the inverse transform.
61. **Inverse Laplace?** Partial fractions plus the table of pairs.
62. **Connection to the project?** The microphone and its pre-amp are continuous-time analog systems, which you would analyse with H(s). After sampling, everything is discrete, so we use the z-transform. They are linked by z = e^{sTs}: the left half of the s-plane maps to the inside of the unit circle.

### Unit 6 – Z-transform
63. **Definition?** X(z) = Σ x[n] z^{−n}. On the unit circle z = e^{jω} it becomes the DTFT.
64. **ROC rules?** Right-sided signal → \|z\| > r. Left-sided → \|z\| < r. Two-sided → a ring. FIR → the whole z-plane except possibly 0 or ∞. The ROC contains no poles.
65. **Standard pairs?** δ[n] → 1. u[n] → 1/(1 − z⁻¹) for \|z\| > 1. aⁿu[n] → 1/(1 − a z⁻¹) for \|z\| > \|a\|. −aⁿu[−n−1] → same expression for \|z\| < \|a\|, which is why the ROC must be given.
66. **Properties?** Linearity; time shift x[n−k] ↔ z^{−k}X(z) (so z⁻¹ = one-sample delay); scaling aⁿx[n] ↔ X(z/a); time reversal ↔ X(1/z); convolution ↔ product; differentiation n·x[n] ↔ −z dX/dz; initial value theorem.
67. **Stability in the z-plane?** A causal LTI system is stable iff all poles are **inside the unit circle** (equivalently, the ROC includes \|z\| = 1).
68. **Inverse z-transform methods?** Partial fractions, power series (long division), and the residue (contour integral) method.
69. **Transfer function of our pre-emphasis?** Y(z) = X(z) − 0.97 z⁻¹ X(z), so H(z) = 1 − 0.97 z⁻¹ = (z − 0.97)/z. Zero at z = 0.97, pole at z = 0. The pole is inside the unit circle, so the system is stable.
70. **How do you read the frequency response from pole-zero positions?** \|H(e^jω)\| = (distance to the zeros)/(distance to the poles). The zero at 0.97 is very close to z = 1 (ω = 0, DC), so \|H\| is small at low frequencies. At z = −1 (ω = π, fs/2) the distance is 1.97, so high frequencies are boosted. That makes it a high-pass filter.
71. **Why pre-emphasise speech at all?** The glottal source and lip radiation give voiced speech a spectral tilt of about −6 dB/octave. Pre-emphasis flattens it, so high-frequency formants are not swamped.
72. **FIR vs IIR in the z-domain?** FIR has only zeros (all poles at the origin) and is always stable. IIR has poles that are not at the origin. Our selftest resonator has poles at r·e^{±jω₀}, which produce a peak at ω₀ (a formant).
73. **Relation of z to s?** z = e^{sT}. The jω axis maps to the unit circle, the left half-plane to the inside, and the right half-plane to the outside.

### Questions about the project's own techniques
74. **What are MFCCs?** Mel-frequency cepstral coefficients. They are a compact description of the short-time spectral envelope (the vocal-tract shape) on a perceptual (mel) frequency scale.
75. **Mel scale formula?** mel = 2595·log₁₀(1 + f/700). It is roughly linear below 1 kHz and logarithmic above.
76. **Why take the log?** It gives perceptual loudness (dB-like) and turns the source × filter product into a sum, log(E·H) = log E + log H, so the two can be separated. This is the idea behind the **cepstrum**.
77. **Why the DCT?** The 26 log-mel energies are highly correlated. The DCT decorrelates them and packs most of the information into the first few coefficients, so 12 are enough.
78. **Why drop c0?** c0 is the overall log-energy (loudness). We want the result to be independent of how loudly you speak.
79. **What is cepstral mean normalisation?** Subtracting the average MFCC vector from every frame. A fixed channel (the microphone) multiplies the spectrum, which becomes adding a constant in the log/cepstral domain, so subtracting the mean removes it.
80. **What is DTW?** Dynamic Time Warping. It uses dynamic programming to find the best alignment between two sequences of different lengths: D(i,j) = d(i,j) + min(D(i−1,j), D(i,j−1), D(i−1,j−1)). It handles speaking faster or slower.
81. **What is VQ / k-means?** Vector quantisation: represent many vectors by K codewords (cluster centres). k-means alternates between assigning each vector to its nearest centre and moving each centre to the mean of its vectors.
82. **FAR / FRR / EER?** FAR (false acceptance rate) is how often an impostor gets in. FRR (false rejection rate) is how often the real user gets rejected. Moving the threshold trades one against the other. The EER is the point where they are equal.
83. **What is leave-one-out?** Test each recording with a model trained without it, so you never test on your training data.
84. **Speech is non-stationary, so why does the FFT work?** We use short frames (25 ms), and over that length speech is approximately stationary.
85. **Why a 10 ms hop (overlap)?** Hamming windows taper the frame edges to almost zero. Overlapping frames make sure every part of the signal is analysed, and give smooth time tracking.

---

## PART D – Numbers worth memorising
- fs = **16 kHz**, Ts = **62.5 µs**, Nyquist frequency = **8 kHz**
- Frame = **25 ms = 400 samples**, hop = **10 ms = 160 samples**, FFT N = **512**, Δf = **31.25 Hz**
- Pre-emphasis a = **0.97**: \|H\| = **0.03** (−30 dB) at DC and **1.97** (+5.9 dB) at 8 kHz
- **26** mel filters, **12** MFCCs (c1–c12), **16** VQ codewords
- Enrollment: **4** phrases × 3 s + **3** commands × **4** reps × 2 s
- Hamming: w[n] = 0.54 − 0.46 cos(2πn/(L−1)), first sidelobe about **−43 dB** (rectangular about −13 dB)
- Male F0 is roughly 85–180 Hz, female F0 roughly 165–255 Hz
