"""
voice_camera_app.py - Voice-Activated Camera Simulation (Signals & Systems).

Run:  py voice_camera_app.py      (or double-click run_app.bat)

The simulated camera takes a photo only if BOTH checks pass:
    1. speaker check : the voice matches YOUR enrolled voice
    2. command check : the word is recognised as SHOOT  (STOP / ZOOM do not fire)
"""

import os
import csv
import queue
import threading
import time
import traceback
from datetime import datetime
import tkinter as tk
from tkinter import messagebox, filedialog

import numpy as np
import matplotlib
matplotlib.use("TkAgg")
import matplotlib.image
from matplotlib.figure import Figure
from matplotlib.backends.backend_tkagg import FigureCanvasTkAgg

import ss_dsp as ss
import concepts_demo

try:
    import sounddevice as sd
except Exception:            # app still opens; recording reports the problem
    sd = None

# ---- fixed colours so text is ALWAYS readable (no theme-dependent colours) ----
BG = "#f2f2f2"
PANEL = "#ffffff"
TEXT = "#111111"
BLUE = "#0b3d91"
GREEN = "#0a6b1f"
RED = "#b00020"
ORANGE = "#a85300"

matplotlib.rcParams.update(concepts_demo.STYLE)


class VoiceCameraApp:
    def __init__(self, root):
        self.root = root
        self.cfg = ss.Config()
        self.cfg.make_dirs()
        self.model = None
        self.busy = False
        self.rec_fs = None
        self.last_y = None
        self.zoom = 1                       # ZOOM cycles 1x/2x/3x, STOP resets it
        self.scene = ss.simulated_photo()   # what the camera is "looking at"
        self.q = queue.Queue()

        root.title("Voice-Activated Camera Simulation  -  Signals & Systems")
        root.configure(bg=BG)
        root.geometry("1400x860")
        root.minsize(1100, 700)
        self._build_ui()
        self.root.after(50, self._poll_queue)

        self.log(f"Project folder: {self.cfg.root_dir}")
        self._check_mic()
        self._load_model()
        if self.model is None:
            self.set_prompt("Welcome! You have not enrolled your voice yet.\n"
                            "Press  1. Enroll my voice  to begin.", BLUE)
            self.root.after(300, self._first_launch)
        else:
            self.set_prompt("Ready.  Press  3. TEST  and say  ZOOM (zoom in), STOP (reset)\n"
                            "or  SHOOT  (take the photo).", GREEN)

    # ------------------------------------------------------------------ UI
    def _build_ui(self):
        left = tk.Frame(self.root, bg=BG, width=330)
        left.pack(side=tk.LEFT, fill=tk.Y, padx=10, pady=10)
        left.pack_propagate(False)

        tk.Label(left, text="Voice Camera", font=("Segoe UI", 22, "bold"),
                 bg=BG, fg=TEXT).pack(pady=(0, 10))

        def btn(text, cmd, color, big=False):
            b = tk.Button(left, text=text, command=cmd, bg=color, fg=TEXT,
                          activebackground=color, activeforeground=TEXT,
                          font=("Segoe UI", 15 if big else 11, "bold" if big else "normal"),
                          relief=tk.RAISED, bd=2, height=2 if big else 1, wraplength=290)
            b.pack(fill=tk.X, pady=4)
            return b

        self.buttons = [
            btn("1. Enroll my voice", self.on_enroll, "#d6e4ff"),
            btn("2. Record another speaker (optional)", self.on_other, "#f3ead6"),
            btn("3. TEST - say a command", self.on_test, "#b5e8b5", big=True),
            btn("Test using a WAV file", self.on_test_file, "#e6e6e6"),
            btn("Evaluate accuracy", self.on_evaluate, "#e6e6e6"),
            btn("S&S Concepts (viva plots)", self.on_concepts, "#ffe0f0"),
            btn("Help", self.on_help, "#e6e6e6"),
        ]

        tk.Label(left, text="Messages:", bg=BG, fg=TEXT, anchor="w",
                 font=("Segoe UI", 10, "bold")).pack(fill=tk.X, pady=(10, 0))
        frm = tk.Frame(left, bg=BG)
        frm.pack(fill=tk.BOTH, expand=True)
        sb = tk.Scrollbar(frm)
        sb.pack(side=tk.RIGHT, fill=tk.Y)
        self.msg = tk.Text(frm, bg=PANEL, fg=TEXT, insertbackground=TEXT,
                           font=("Consolas", 9), wrap=tk.WORD, yscrollcommand=sb.set)
        self.msg.pack(fill=tk.BOTH, expand=True)
        sb.config(command=self.msg.yview)

        right = tk.Frame(self.root, bg=BG)
        right.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 10), pady=10)

        self.prompt = tk.Label(right, text="", bg=PANEL, fg=TEXT, font=("Segoe UI", 17, "bold"),
                               height=3, wraplength=1000, justify=tk.CENTER, relief=tk.GROOVE, bd=2)
        self.prompt.pack(fill=tk.X)
        self.result = tk.Label(right, text="", bg=PANEL, fg=TEXT, font=("Consolas", 11),
                               justify=tk.LEFT, anchor="w", relief=tk.GROOVE, bd=1, height=3)
        self.result.pack(fill=tk.X, pady=(6, 6))

        self.fig = Figure(figsize=(10, 6.5), dpi=90, facecolor="white")
        self.ax_wave = self.fig.add_subplot(2, 2, 1)
        self.ax_spec = self.fig.add_subplot(2, 2, 2)
        self.ax_sgram = self.fig.add_subplot(2, 2, 3)
        self.ax_cam = self.fig.add_subplot(2, 2, 4)
        self.canvas = FigureCanvasTkAgg(self.fig, master=right)
        self.canvas.get_tk_widget().pack(fill=tk.BOTH, expand=True)
        self._reset_plots()
        self._camera_locked("Camera idle")

    def _reset_plots(self):
        for a, t, xl, yl in ((self.ax_wave, "Time domain  x[n]", "time (s)", "amplitude"),
                             (self.ax_spec, "Magnitude spectrum |X(f)| (FFT)", "frequency (Hz)", "dB"),
                             (self.ax_sgram, "Spectrogram (short-time FFT)", "time (s)", "frequency (Hz)")):
            a.clear()
            a.set_title(t, color=TEXT)
            a.set_xlabel(xl)
            a.set_ylabel(yl)
        self.fig.tight_layout()
        self.canvas.draw_idle()

    # ----------------------------------------------- thread-safe UI helpers
    def ui(self, fn, *args):
        """Run fn(*args) on the Tk main thread (worker threads call this)."""
        self.q.put((fn, args))

    def _poll_queue(self):
        try:
            while True:
                fn, args = self.q.get_nowait()
                fn(*args)
        except queue.Empty:
            pass
        self.root.after(30, self._poll_queue)

    def log(self, text):
        line = f"[{datetime.now():%H:%M:%S}] {text}\n"
        if threading.current_thread() is threading.main_thread():
            self.msg.insert(tk.END, line)
            self.msg.see(tk.END)
        else:
            self.ui(self.log, text)

    def set_prompt(self, text, color=TEXT):
        if threading.current_thread() is threading.main_thread():
            self.prompt.config(text=text, fg=color)
        else:
            self.ui(self.set_prompt, text, color)

    def set_result(self, text, color=TEXT):
        if threading.current_thread() is threading.main_thread():
            self.result.config(text=text, fg=color)
        else:
            self.ui(self.set_result, text, color)

    def _set_busy(self, b):
        self.busy = b
        for w in self.buttons:
            w.config(state=tk.DISABLED if b else tk.NORMAL)

    def run_worker(self, fn):
        if self.busy:
            return
        self._set_busy(True)

        def wrapper():
            try:
                fn()
            except Exception as e:
                self.log("ERROR: " + str(e))
                self.log(traceback.format_exc())
                self.set_prompt(f"Error: {e}", RED)
            finally:
                self.ui(self._set_busy, False)
        threading.Thread(target=wrapper, daemon=True).start()

    # ------------------------------------------------------------ recording
    def _check_mic(self):
        if sd is None:
            self.log("sounddevice is not installed: run  py -m pip install sounddevice")
            return
        try:
            dev = sd.query_devices(kind="input")
            self.log(f"Microphone: {dev['name']} (default {dev['default_samplerate']:.0f} Hz)")
        except Exception as e:
            self.log(f"No input device found: {e}")

    def record(self, seconds, text):
        """Blocking recording (called from the worker thread). Returns (x, fs)."""
        if sd is None:
            raise RuntimeError("sounddevice not installed (py -m pip install sounddevice)")
        rates = [self.rec_fs] if self.rec_fs else [self.cfg.fs, *self.cfg.fallback_fs]
        for k in (3, 2, 1):
            self.set_prompt(f"{text}\n\nGet ready ... {k}", BLUE)
            time.sleep(0.45)
        last_err = None
        for fs in rates:
            try:
                sd.check_input_settings(samplerate=fs, channels=1)
                self.set_prompt(f"{text}\n\n●  RECORDING - SPEAK NOW  ({seconds:.0f} s)", RED)
                x = sd.rec(int(seconds * fs), samplerate=fs, channels=1, dtype="float32")
                sd.wait()
                if self.rec_fs != fs:
                    self.rec_fs = fs
                    self.log(f"Recording at {fs} Hz" + ("" if fs == self.cfg.fs else
                             f" (converted to {self.cfg.fs} Hz with anti-alias filter)"))
                self.set_prompt(f"{text}\n\nProcessing ...", TEXT)
                return x[:, 0].astype(float), fs
            except Exception as e:
                last_err = e
        raise RuntimeError(f"Microphone problem: {last_err}. Check Windows Settings -> "
                           "Privacy -> Microphone and allow desktop apps.")

    def record_valid(self, seconds, text, path, tries=3, single_word=True):
        """Record until the recording passes the sanity checks, then save it."""
        for _ in range(tries):
            x, fs = self.record(seconds, text)
            y, info = ss.preprocess(x, fs, self.cfg, single_word)
            self.ui(self.show_signal, info.x_full, info, None)
            if info.ok:
                ss.write_wav(path, info.x_full, self.cfg.fs)
                if info.warning:
                    self.log("Note: " + info.warning)
                return True
            self.log("Retry: " + info.msg)
            self.set_prompt(info.msg + "\nLet's try again.", ORANGE)
            time.sleep(1.5)
        return False

    # ------------------------------------------------------------- actions
    def _first_launch(self):
        if messagebox.askyesno(
                "First launch",
                "Welcome to the Voice-Activated Camera Simulation!\n\n"
                "Before the camera can recognise you it needs to learn your voice.\n"
                f"Enrollment takes ~2 minutes: read {len(self.cfg.phrases)} phrases and say each "
                f"command ({', '.join(c.upper() for c in self.cfg.commands)}) "
                f"{self.cfg.reps_per_command} times.\n\nUse a quiet room. Start enrollment now?"):
            self.on_enroll(confirmed=True)

    def on_enroll(self, confirmed=False):
        cfg = self.cfg
        old = ss.list_wav(cfg.phrase_dir) + ss.list_wav(cfg.command_dir)
        if old and not confirmed and not messagebox.askyesno(
                "Re-enroll", "This replaces your previous enrollment. Continue?"):
            return
        messagebox.showinfo("Enrollment",
                            "For each recording:\n"
                            "  1. Read the text shown at the top.\n"
                            "  2. Wait for the red  RECORDING - SPEAK NOW.\n"
                            "  3. Speak clearly at normal volume.\n\n"
                            f"Phrases: {cfg.phrase_sec:.0f} s each.  Commands: {cfg.command_sec:.0f} s "
                            "each (say the word once).")
        for f in old:
            os.remove(f)
        if os.path.exists(cfg.model_file):
            os.remove(cfg.model_file)
        self.model = None

        items = [(f'Read aloud:  "{p}"', cfg.phrase_sec,
                  os.path.join(cfg.phrase_dir, f"phrase_{i + 1:02d}.wav"))
                 for i, p in enumerate(cfg.phrases)]
        for r in range(cfg.reps_per_command):
            for c in cfg.commands:
                items.append((f"Say the command:   {c.upper()}", cfg.command_sec,
                              os.path.join(cfg.command_dir, f"{c}_{r + 1:02d}.wav")))

        def job():
            for k, (text, sec, path) in enumerate(items):
                self.log(f"Enrollment {k + 1}/{len(items)}: {text}")
                if not self.record_valid(sec, f"[{k + 1}/{len(items)}]  {text}", path,
                                         single_word=sec == cfg.command_sec):
                    self.set_prompt("Enrollment stopped: recordings were not usable. "
                                    "Check the microphone and press 1 again.", RED)
                    return
            self._train()
        self.run_worker(job)

    def on_other(self):
        cfg = self.cfg
        if not messagebox.askokcancel(
                "Another speaker",
                "Ask a DIFFERENT person to speak now.\n\nTheir recordings are used to calibrate "
                "the speaker threshold and to measure rejection of other voices."):
            return
        start = len(ss.list_wav(cfg.other_dir)) // len(cfg.commands) + 1
        items = []
        for r in range(cfg.other_reps):
            for c in cfg.commands:
                items.append((f"OTHER SPEAKER - say:   {c.upper()}",
                              os.path.join(cfg.other_dir, f"{c}_{start + r:02d}.wav")))

        def job():
            for k, (text, path) in enumerate(items):
                self.record_valid(cfg.command_sec, f"[{k + 1}/{len(items)}]  {text}", path)
            if ss.list_wav(cfg.phrase_dir):
                self._train()
            else:
                self.set_prompt("Other speaker saved. Now enroll YOUR voice (button 1).", BLUE)
        self.run_worker(job)

    def _train(self):
        self.set_prompt("Training the voice model ... (a few seconds)", BLUE)
        t0 = time.time()
        model = ss.build_model(self.cfg, log=self.log)
        ss.save_model(model, self.cfg)
        self.model = model
        self.log(f"Model trained in {time.time() - t0:.1f} s: {model['n_phrases']} phrases, "
                 f"{model['n_commands']} command templates, {model['n_other']} other-speaker files.")
        self._log_model_summary()
        self.set_prompt("Enrollment complete!  Press  3. TEST  and say  SHOOT.", GREEN)

    def _load_model(self):
        try:
            self.model = ss.load_model(self.cfg)
        except Exception as e:
            self.log(f"Could not load the saved model ({e}); please enroll again.")
            self.model = None
        if self.model:
            self.log(f"Loaded voice model from {self.model['created']}.")
            self._log_model_summary()

    def _log_model_summary(self):
        m = self.model
        sp = m["speaker"]
        self.log(f"Speaker threshold = {sp['thr']:.3f}"
                 + ("  (PROVISIONAL: record another speaker to calibrate)"
                    if sp["calib"]["provisional"] else ""))
        for c, lab in enumerate(m["command"]["labels"]):
            self.log(f"  {lab.upper()} DTW threshold = {m['command']['thr'][c]:.3f}")

    def on_test(self):
        if self.model is None:
            messagebox.showwarning("Not enrolled", "Please enroll your voice first (button 1).")
            return

        def job():
            x, fs = self.record(self.cfg.command_sec, "Say a command:  SHOOT, STOP or ZOOM")
            self._process(x, fs, save=True)
        self.run_worker(job)

    def on_test_file(self):
        if self.model is None:
            messagebox.showwarning("Not enrolled", "Please enroll your voice first (button 1).")
            return
        path = filedialog.askopenfilename(initialdir=self.cfg.data_dir,
                                          filetypes=[("WAV audio", "*.wav")])
        if not path:
            return

        def job():
            x, fs = ss.read_wav(path)
            self.log(f"Testing file {os.path.basename(path)} ({fs} Hz)")
            self._process(x, fs, save=False)
        self.run_worker(job)

    def _process(self, x, fs, save):
        cfg = self.cfg
        res = ss.recognize(x, fs, self.model, cfg)
        info = res["info"]
        self.last_y = res["y"] if info.ok else info.x_full
        if save and info.x_full.size:
            p = os.path.join(cfg.test_dir, f"test_{datetime.now():%Y%m%d_%H%M%S}.wav")
            ss.write_wav(p, info.x_full, cfg.fs)
        self.ui(self.show_signal, info.x_full, info, res)
        if info.warning:
            self.log("Note: " + info.warning)
        if not res["ok"]:
            self.set_prompt(info.msg, ORANGE)
            self.set_result("Recording not usable - nothing was recognised.", ORANGE)
            self.ui(self._camera_locked, "No speech detected")
            return

        spk = "ACCEPTED" if res["spk_ok"] else "REJECTED"
        norms = "  ".join(f"{l.upper()}={v:.2f}" for l, v in
                          zip(self.model["command"]["labels"], res["cmd_norm"]))
        txt = (f"Speaker : score {res['spk_score']:.3f}  vs threshold {res['spk_thr']:.3f}  ->  {spk}\n"
               f"Command : {res['command'].upper()}  ({res['cmd_reason']})\n"
               f"          DTW distance / threshold (<= 1 means match):  {norms}")
        self.log(txt.replace("\n", " | "))
        cmd = res["command"]
        if res["trigger"]:
            self.set_prompt(f"📸  PHOTO TAKEN at {self.zoom}x  -  your voice + SHOOT", GREEN)
            self.set_result(txt, GREEN)
            self.ui(self._take_photo)
        elif res["spk_ok"] and res["cmd_ok"] and cmd == "zoom":
            self.zoom = self.zoom % 3 + 1              # 1x -> 2x -> 3x -> 1x
            self.set_prompt(f"🔍  ZOOM  -  camera now at {self.zoom}x.  Say SHOOT to take the photo.", BLUE)
            self.set_result(txt, BLUE)
            self.ui(self._show_viewfinder, f"VIEWFINDER  {self.zoom}x  (ZOOM)")
        elif res["spk_ok"] and res["cmd_ok"] and cmd == "stop":
            self.zoom = 1
            self.set_prompt("⏹  STOP  -  zoom reset to 1x, camera in standby.", BLUE)
            self.set_result(txt, BLUE)
            self.ui(self._camera_locked, "STANDBY\n(STOP: zoom reset to 1x)")
        else:
            if not res["spk_ok"]:
                why = "voice not recognised as the enrolled speaker"
            else:
                why = f"command {cmd} ({res['cmd_reason']}) - please repeat"
            self.set_prompt(f"CAMERA LOCKED  -  {why}", RED)
            self.set_result(txt, RED)
            self.ui(self._camera_locked, "CAMERA LOCKED\n" + why.split(" (")[0])

        os.makedirs(cfg.results_dir, exist_ok=True)
        new = not os.path.exists(cfg.log_file)
        with open(cfg.log_file, "a", newline="") as f:
            w = csv.writer(f)
            if new:
                w.writerow(["time", "speaker_score", "speaker_thr", "speaker_ok",
                            "command", "command_ok", "photo"])
            w.writerow([datetime.now().isoformat(timespec="seconds"), f"{res['spk_score']:.4f}",
                        f"{res['spk_thr']:.4f}", res["spk_ok"], res["command"],
                        res["cmd_ok"], res["trigger"]])

    def on_evaluate(self):
        if self.model is None:
            messagebox.showwarning("Not enrolled", "Please enroll your voice first.")
            return
        rep = ss.evaluate(self.model, self.cfg)
        with open(os.path.join(self.cfg.results_dir, "evaluation_report.txt"), "w") as f:
            f.write(rep)
        self.log(rep)
        self._show_text_window("Evaluation report", rep)

    def on_concepts(self):
        y = self.last_y
        title = "last recording"
        if y is None or y.size < 400:
            y, title = concepts_demo.synthetic_vowel(self.cfg.fs), "synthetic vowel - record a TEST first"
        win = tk.Toplevel(self.root, bg="white")
        win.title("Signals & Systems concepts")
        win.geometry("1300x850")
        fig = concepts_demo.make_concepts_figure(y, self.cfg.fs, self.cfg, title)
        cv = FigureCanvasTkAgg(fig, master=win)
        cv.get_tk_widget().pack(fill=tk.BOTH, expand=True)
        cv.draw()
        fig.savefig(os.path.join(self.cfg.results_dir, "concepts.png"))
        self.log("Saved results/concepts.png")

    def on_help(self):
        self._show_text_window("Help", (
            "WORKFLOW\n"
            "1. Enroll my voice: read the phrases and say each command when asked.\n"
            "2. (Optional) a friend presses 'Record another speaker' and says the\n"
            "   commands. This calibrates the speaker threshold.\n"
            "3. TEST: press, wait for red RECORDING, say a command.\n\n"
            "The photo is taken only if BOTH checks pass:\n"
            "   - speaker check: the voice matches your enrolled voice (VQ codebook)\n"
            "   - command check: the word is recognised as SHOOT (DTW templates)\n\n"
            "Commands (all need YOUR voice):\n"
            "   ZOOM  : digital zoom 1x -> 2x -> 3x -> 1x (centre crop of the view)\n"
            "   STOP  : reset zoom to 1x, camera to standby\n"
            "   SHOOT : take the photo at the current zoom\n"
            "   unknown / uncertain word, or another voice: camera stays locked\n\n"
            "Plots after a TEST:\n"
            "   top-left : waveform x[n], green/red lines = detected speech start/end\n"
            "   top-right: FFT magnitude spectrum 0..fs/2 = 8 kHz\n"
            "   bottom-left: spectrogram (short-time Fourier transform)\n"
            "   bottom-right: simulated camera\n\n"
            "'S&S Concepts' shows sampling, aliasing, convolution, frequency response,\n"
            "z-plane, windowing, harmonics, mel filters and MFCC on your recording.\n\n"
            "Files: data/ (recordings, model), results/ (photos, log, report).\n"
            "To start fresh delete the data folder.\n\n"
            "Academic prototype: a recording of your voice played back can fool it."))

    def _show_text_window(self, title, text):
        win = tk.Toplevel(self.root, bg=PANEL)
        win.title(title)
        t = tk.Text(win, bg=PANEL, fg=TEXT, font=("Consolas", 11), width=90, height=28, wrap=tk.WORD)
        t.pack(fill=tk.BOTH, expand=True, padx=8, pady=8)
        t.insert("1.0", text)
        t.config(state=tk.DISABLED)

    # ------------------------------------------------------------- plotting
    def show_signal(self, x, info, res):
        fs = self.cfg.fs
        self._reset_plots()
        if x is None or x.size == 0:
            return
        t = np.arange(x.size) / fs
        a = self.ax_wave
        a.plot(t, x, lw=0.6, color="C0")
        if info.ok:
            a.axvline(info.start / fs, color="green", lw=1.5, label="speech start")
            a.axvline(info.end / fs, color="red", lw=1.5, label="speech end")
            a.legend(fontsize=8, loc="upper right")
        a.set_xlim(0, t[-1])

        seg = x[info.start:info.end] if info.ok else x
        f, X = ss.spectrum_db(seg, fs)
        a = self.ax_spec
        a.plot(f, X, lw=0.7, color="C3")
        a.set_xlim(0, fs / 2)
        a.set_ylim(X.max() - 90, X.max() + 5)
        a.grid(alpha=0.3)
        a.text(0.98, 0.95, f"N-point FFT, Δf = {fs / (2 * (f.size - 1)):.2f} Hz",
               transform=a.transAxes, ha="right", va="top", fontsize=8, color=TEXT)

        F = ss.mfcc(x, fs, self.cfg)
        S = 10 * np.log10(F["P"] + 1e-12)
        a = self.ax_sgram
        a.imshow(S, aspect="auto", origin="lower", cmap="magma",
                 extent=[F["t"][0], F["t"][-1], 0, fs / 2], vmin=S.max() - 80, vmax=S.max())
        self.fig.tight_layout()
        self.canvas.draw_idle()

    def _camera_locked(self, text):
        a = self.ax_cam
        a.clear()
        a.set_facecolor("#222222")
        a.set_xticks([])
        a.set_yticks([])
        a.text(0.5, 0.5, text, ha="center", va="center", color="white",
               fontsize=13, fontweight="bold", transform=a.transAxes, wrap=True)
        a.set_title("Simulated camera", color=TEXT)
        self.canvas.draw_idle()

    def _take_photo(self):
        a = self.ax_cam
        a.clear()
        a.set_facecolor("white")
        a.set_xticks([])
        a.set_yticks([])
        a.set_title("FLASH!", color=TEXT)
        self.canvas.draw()
        if sd is not None:
            try:
                sd.play(ss.shutter_sound(16000), 16000)
            except Exception:
                pass
        img = self._zoomed_view()
        path = os.path.join(self.cfg.photo_dir,
                            f"photo_{datetime.now():%Y%m%d_%H%M%S}_{self.zoom}x.png")
        matplotlib.image.imsave(path, img)
        self.log(f"Photo saved ({self.zoom}x): {path}")
        self.scene = ss.simulated_photo()            # new scene for the next photo

        def show():
            a.clear()
            a.imshow(img)
            a.set_xticks([])
            a.set_yticks([])
            a.set_title(f"PHOTO TAKEN at {self.zoom}x  (saved to results/photos)",
                        color=GREEN, fontweight="bold")
            self.canvas.draw_idle()
        self.root.after(250, show)

    def _zoomed_view(self):
        """Centre crop of the scene (1/zoom of the width and height), enlarged
        back to full size by repeating pixels - a digital zoom."""
        H, W, _ = self.scene.shape
        z = self.zoom
        h, w = H // z, W // z
        top, left = (H - h) // 2, (W - w) // 2
        crop = self.scene[top:top + h, left:left + w]
        return np.repeat(np.repeat(crop, z, axis=0), z, axis=1)

    def _show_viewfinder(self, title):
        a = self.ax_cam
        a.clear()
        a.imshow(self._zoomed_view())
        a.set_xticks([])
        a.set_yticks([])
        a.set_title(title, color=BLUE, fontweight="bold")
        self.canvas.draw_idle()


def main():
    root = tk.Tk()
    VoiceCameraApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
