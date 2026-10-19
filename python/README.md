# Voice-Activated Camera – Python version

Python rewrite of the MATLAB project (same algorithm, same settings). The GUI uses fixed dark-on-light colours, so all text stays readable.

## Run
1. Double-click **`run_app.bat`**. It installs numpy, matplotlib and sounddevice the first time.
   You can also run `py -3 -m pip install -r requirements.txt` and then `py -3 voice_camera_app.py`.
2. First launch: enroll (4 phrases + SHOOT/STOP/ZOOM ×4, about 2 minutes). Wait for the red **RECORDING** text before speaking.
3. Press **3. TEST** and say **SHOOT** → photo. Say STOP or ZOOM → camera stays locked. A friend saying SHOOT → speaker rejected.
4. Optional: a friend uses **2. Record another speaker**. This calibrates the speaker threshold properly; without it the threshold is marked *provisional*.
5. **S&S Concepts** opens 9 plots made from your last recording: sampling, aliasing, convolution, |H(e^jω)|, z-plane, windowing, harmonics, mel filters, MFCC. Use it in the viva.

If the mic isn't working, use **Test using a WAV file**. To check the code with no microphone: `py -3 selftest.py` (13 checks, synthetic voices).

## Files
| File | What it is |
|---|---|
| `ss_dsp.py` | All the DSP: pre-emphasis, resampling, framing, FFT, mel filters, MFCC, DTW, VQ, thresholds |
| `voice_camera_app.py` | The GUI |
| `concepts_demo.py` | The S&S concepts figure |
| `selftest.py` | Tests that need no microphone (source-filter synthetic speech) |
| `data/` | Your recordings and `voice_model.pkl` (created automatically; delete it to start over) |
| `results/` | Photos, `test_log.csv`, evaluation report, concepts.png |

See **`../VIVA_GUIDE.md`** for the explanation of the project and the viva questions.
