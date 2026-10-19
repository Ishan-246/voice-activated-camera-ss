# Voice-Activated Camera Simulation Using Audio Processing and Speaker Recognition

> **Python version (recommended):** see [`python/`](python/README.md). Double-click `python/run_app.bat`.
> **Viva study guide:** [`VIVA_GUIDE.md`](VIVA_GUIDE.md)
> The MATLAB version below is the original.

A Signals & Systems mini-project in **base MATLAB** (no toolboxes needed).
It records your voice from the laptop microphone and analyses it in the time and frequency domains. It "takes a photo" (a simulated one) only when **two checks both pass**:

1. **Speaker check**: the voice matches your enrolled voice.
2. **Command check**: the spoken word is recognised as **SHOOT**. "STOP" and "ZOOM" are non-trigger commands.

---

## Running in MATLAB Online (student account)

1. **Use Google Chrome.** MathWorks documents audio recording in MATLAB Online as supported in Chrome.
2. Go to <https://matlab.mathworks.com> and sign in.
3. **Upload the ZIP:** in the *Current Folder* panel (left), make sure you are in your MATLAB Drive home folder (`/MATLAB Drive`). Then either
   - drag `VoiceCameraProject.zip` from Windows Explorer onto the Current Folder panel, **or**
   - on the **HOME** tab click **Upload** and select the ZIP.
4. **Extract it:** type this in the Command Window and press Enter:
   ```matlab
   unzip('VoiceCameraProject.zip')
   ```
   This creates the folder `VoiceCameraProject` containing `VoiceCameraApp.m`, `src`, `tests` and `README.md`.
5. **Open the project folder:** double-click `VoiceCameraProject` in the Current Folder panel, or type `cd VoiceCameraProject`.
6. **Optional check:** type `addpath tests; run_selftest`. This needs no microphone.
7. **Run the app:** double-click `VoiceCameraApp.m` to open it, then click **Run** on the EDITOR tab. You can also type `VoiceCameraApp` in the Command Window.
8. On the first recording, **Chrome asks for microphone permission: click Allow.**

The `data` and `results` folders are created inside `VoiceCameraProject` on MATLAB Drive. Your enrollment is kept between sessions.

### MATLAB Online limitations (from the MathWorks documentation)
- `audiorecorder` and `sound` are supported in **Google Chrome**. Other browsers may not record or play audio.
- `audiorecorder` **ignores the bit depth** (16 bits) and uses the device default. This does not affect the app, because the samples are returned as doubles.
- **Valid sample rates may differ** from desktop MATLAB. The app first tries 16 kHz. If the browser microphone refuses that rate, it records at 48 kHz or 44.1 kHz instead. It then converts to 16 kHz with an anti-aliasing low-pass filter (windowed-sinc convolution, `src/ss_resample.m`). The Messages panel shows the rate actually used.
- `audiodevinfo` may not list input devices in MATLAB Online. The app only reports this in the Messages panel and still attempts the recording.
- Audio travels from your browser to the MathWorks server, so there may be a short delay at the start of each recording. Wait for the red RECORDING text, then speak.
- The figure window opens inside the MATLAB Online page. If it looks cramped, maximise or undock the figure, or use a larger browser window.
- The shutter click is played with `sound` (Chrome only). If no sound plays, the photo is still taken.

## Running in desktop MATLAB

1. Open this folder in VS Code (to browse the files) and in MATLAB.
2. In MATLAB, open **`VoiceCameraApp.m`** and press **Run**. You can also type `VoiceCameraApp` in the Command Window while this folder is the current folder.
3. **First launch:** a welcome box asks you to enroll. Click **Start enrollment** and follow the big text at the top of the window:
   - read 4 short phrases (3 s each),
   - say each of SHOOT, STOP and ZOOM 4 times (2 s each).
   It takes about 2 minutes. Wait for the red **RECORDING - SPEAK NOW** text before you speak.
4. Press **3. TEST - say a command** and say **"Shoot"**.

Your enrollment is saved in `data/`, so the next launch goes straight to "Ready".

**Recommended:** ask a friend to press **2. Record another speaker** and say the commands. Their recordings are used to calibrate the speaker threshold and to measure how well other voices are rejected. Without them, the speaker threshold is marked *provisional*. Then press **Evaluate accuracy**.

### What you should see after a TEST
| Panel | Content |
|---|---|
| Top-left | Time-domain waveform x[n] against time (s), with the detected speech start and end marked |
| Top-right | FFT magnitude spectrum (dB) against frequency 0 to 8000 Hz (= fs/2) |
| Bottom-left | Spectrogram (short-time FFT) |
| Bottom-right | Simulated camera: a flash, a shutter click and a generated "photo" saved to `results/photos/`, **or** "CAMERA LOCKED" with the reason |
| Top banner | Speaker decision (score vs threshold), command decision, camera result |

### Checking the code without a microphone
In MATLAB, open `tests/run_selftest.m` and press Run. It tests the FFT frequency axis, silence rejection, the DTW, threshold calibration, and the complete enroll → train → recognise pipeline. The pipeline test uses synthetic "voices" in a temporary folder, so your own recordings are never touched.

---

## Folder structure
```
VoiceCameraProject/     (folder created by unzip)
VoiceCameraApp.m        <- the only file you need to run
src/                    helper functions (added to the path automatically)
tests/run_selftest.m    optional microphone-free check
data/                   created automatically: your WAV recordings + voice_model.mat
results/                created automatically: photos, test_log.csv, evaluation report/plot
```
To start completely fresh, close the app and delete the `data` folder.

---

## How it works (processing chain)

```
microphone -> sampling (fs = 16 kHz) -> DC removal -> speech trimming -> normalisation
   -> pre-emphasis FIR  y[n] = x[n] - 0.97 x[n-1]
   -> 25 ms frames x Hamming window -> FFT -> |X|^2 -> 26 mel band-pass filters -> log -> DCT
   -> MFCC c1..c12 per frame
        |-- speaker check: distance to your VQ codebook (16 codewords, k-means)
        |-- command check: DTW distance to your SHOOT/STOP/ZOOM templates
   -> camera fires only if  speaker accepted  AND  command == SHOOT
```

### Speaker verification (who is speaking)
All your recordings are converted to MFCC vectors. k-means groups them into 16 "typical sounds" of your voice, which form a **vector-quantisation codebook**. A new recording's score is the average distance of its frames to the nearest codeword. A lower score means it sounds more like you.

### Command recognition (what was said)
Each of your enrollment commands is stored as an MFCC sequence (a template). A new recording is compared with every template using **Dynamic Time Warping (DTW)**, which lines up the two words in time even if you speak faster or slower. Each command has its own threshold. The result is:
- **recognised** if exactly one command is within its threshold,
- **unknown** if none is,
- **uncertain** if more than one is.

Unknown and uncertain are both rejected.

### How thresholds are calibrated (no made-up numbers)
Thresholds are calculated from your recordings with **leave-one-out** testing: each recording is scored by a model that was trained *without* it.
- *Speaker:* "genuine" scores come from your held-out command recordings, and "impostor" scores from the other speaker's recordings. The threshold is the one that makes the fewest errors on these scores. Without other-speaker data, it is set to the worst genuine score plus one standard deviation and labelled **provisional**.
- *Commands:* "genuine" scores are template vs. same-command templates. "Impostor" scores are other commands and your free phrases.

The app shows raw scores against thresholds. It does **not** show "confidence percentages", because those would not be meaningful.

---

## Mapping to the syllabus

| Unit | Concept | Where it is used |
|---|---|---|
| 1. Signals | Sampling, discrete-time signal x[n], fs = 16 kHz, t = n/fs | `audiorecorder`, waveform plot (`VoiceCameraApp.m`) |
| 1. Signals | Signal operations: amplitude shift (DC removal), amplitude scaling (normalisation), time segmentation (trimming, framing), multiplication by a window | `ss_preprocess.m`, `ss_mfcc.m` |
| 1. Systems | System classification: pre-emphasis is linear, time-invariant, causal and stable | `ss_preEmphasis.m` |
| 2. LTI systems | **Convolution sum** y[n] = Σ x[k] h[n−k] with h[n] = [1, −0.97] | `ss_preEmphasis.m` uses `conv` |
| 2. LTI systems | **Series** interconnection (pre-emphasis → window → FFT → filter bank) and **parallel** interconnection (26 mel band-pass filters applied to the same spectrum) | `ss_mfcc.m`, `ss_melFilterbank.m` |
| 3. Fourier series | Voiced speech is quasi-periodic, so its spectrum shows harmonics at multiples of the fundamental (pitch) frequency, like Fourier-series lines. Visible in the FFT and spectrogram plots | spectrum and spectrogram plots |
| 3/4. Spectra | Magnitude spectrum \|X(f)\| in dB | top-right plot |
| 4. Fourier transform | DFT/FFT, frequency axis f_k = k·fs/N, resolution Δf = fs/N, single-sided spectrum up to fs/2 (Nyquist) | `plotSpectrum` in `VoiceCameraApp.m` |
| 1/4. Sampling theorem | If the microphone records at 48 kHz, the signal is low-pass filtered below the new Nyquist frequency (8 kHz) before conversion to 16 kHz, to prevent aliasing | `ss_resample.m` |
| 4. Fourier transform | Short-time Fourier transform (spectrogram); windowing reduces spectral leakage | `ss_mfcc.m`, bottom-left plot |
| 4. Frequency-domain LTI analysis | The mel filters act by **multiplying** the spectrum by each filter's response, which is the frequency-domain view of filtering | `ss_mfcc.m` (`Hm * P`) |
| 5. Laplace transform | Not used directly: everything here is discrete-time, so the z-transform is the right tool. The Laplace transform is the continuous-time counterpart, relevant to the analogue microphone path before sampling | (no code) |
| 6. Z-transform | Pre-emphasis H(z) = 1 − 0.97 z⁻¹ has a zero at z = 0.97 (near z = 1, i.e. near 0 Hz), so it attenuates low frequencies and boosts high ones. Its difference equation is solved sample by sample | `ss_preEmphasis.m` |
| Extra | DCT (decorrelates the log filter-bank energies); DTW; vector quantisation | `ss_mfcc.m`, `ss_dtw.m`, `ss_vqTrain.m` |

Frequency response of the pre-emphasis system (Unit 4/6): H(e^{jω}) = 1 − 0.97 e^{−jω}, so |H| ≈ 0.03 at 0 Hz and ≈ 1.97 at fs/2.

Note: no single frequency identifies a person. The speaker check compares the overall *shape* of the short-time spectrum (the MFCC distribution), which depends on the vocal tract and the voice.

---

## Limitations (please read)
- **Academic prototype, not a security system.** A recording of your voice played back through a speaker **will be accepted**. There is no liveness or anti-spoofing check.
- Simple MFCC + VQ speaker verification is **not reliable identity verification**. Accuracy depends on the microphone, room noise, your health and mood, and how similar another voice is. It is trained on only about 16 short recordings.
- Command recognition is **speaker-dependent template matching**. It only knows SHOOT, STOP and ZOOM as *you* said them at enrollment. Other words should be rejected as "unknown", but similar-sounding words may be confused.
- The evaluation set is small. The other-speaker recordings are also used to place the speaker threshold, so the reported false-acceptance rate is optimistic. For a fairer test, record a *second* other person after calibrating with the first, and test them live with the TEST button.
- Background noise reduces accuracy. Enroll and test in the same quiet place.
- The only recording validity checks are a minimum loudness, a minimum speech-to-noise level and a minimum duration. These are input sanity checks, not recognition thresholds.

## Troubleshooting
| Problem | Fix |
|---|---|
| "Microphone problem" box in MATLAB Online | Use Chrome. Click the icon left of the address bar → Site settings → Microphone → Allow, then reload the page. Windows must also allow Chrome to use the microphone (Settings → Privacy & security → Microphone). |
| "Microphone problem" box in desktop MATLAB | Windows Settings → Privacy & security → Microphone: turn on microphone access **and** "Let desktop apps access your microphone". Check Settings → System → Sound → Input. Restart MATLAB. |
| "No speech detected" | Speak after the red RECORDING text, louder or closer to the microphone. |
| Your own voice is rejected often | Re-enroll in the same place where you test, and speak naturally. Adding other-speaker data makes the threshold better calibrated. |
| Need to start over | Close the app and delete the `data` folder. |

All functions used are part of base MATLAB: `audiorecorder`, `recordblocking`, `getaudiodata`, `audiowrite`, `audioread`, `audiodevinfo`, `fft`, `conv`, `interp1`, `uicontrol`, `questdlg`/`msgbox`, `xline`, `histogram`, `exportgraphics`. The project targets R2020a or newer (it was written for R2025b).
