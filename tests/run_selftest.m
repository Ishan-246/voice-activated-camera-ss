function run_selftest
%RUN_SELFTEST  Check the whole processing chain WITHOUT a microphone.
%   Uses synthetic signals (tones and artificial "voices") written to a
%   temporary folder. Your real recordings are not touched.
%   Run it from MATLAB:  >> run_selftest   (with this folder on the path)
%   or open this file and press Run.

projectDir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectDir, 'src'));
rngState = rng;
rng(7);
cleanup = onCleanup(@() rng(rngState));

nPass = 0;  nFail = 0;
fprintf('\n=== Voice Camera self-test ===\n');

cfg0 = ss_config(projectDir);
fs = cfg0.fs;

%% 1. FFT frequency axis: a 1 kHz tone must peak at 1 kHz
t = (0:round(0.5*fs)-1)' / fs;
tone = [zeros(round(0.3*fs), 1); 0.5 * sin(2*pi*1000*t); zeros(round(0.3*fs), 1)] + 1e-4 * randn(round(1.1*fs), 1);
[y, info] = ss_preprocess(tone, fs, cfg0);
check(info.ok, 'tone accepted as a valid recording');
check(abs(numel(y)/fs - 0.5) < 0.15, sprintf('trimming keeps ~0.5 s (got %.2f s)', numel(y)/fs));
N = numel(y);  Y = abs(fft(y));  [~, k] = max(Y(1:floor(N/2)+1));
fPk = (k - 1) * fs / N;
check(abs(fPk - 1000) <= fs / N + 1, sprintf('FFT peak at %.1f Hz (expected 1000 Hz)', fPk));

%% 2. Silence / noise rejected
[~, info] = ss_preprocess(zeros(2*fs, 1), fs, cfg0);
check(~info.ok, 'all-zero recording rejected');
[~, info] = ss_preprocess(0.01 * randn(2*fs, 1), fs, cfg0);
check(~info.ok, 'pure background noise rejected');
[~, info] = ss_preprocess([], fs, cfg0);
check(~info.ok, 'empty recording rejected');
[~, info] = ss_preprocess([tone tone], 44100, cfg0);
check(info.ok, 'stereo 44.1 kHz input handled (converted to mono 16 kHz)');
t48 = (0:47999)' / 48000;
r16 = ss_resample(sin(2*pi*1000*t48), 48000, fs);
N16 = numel(r16);  [~, k16] = max(abs(fft(r16)));
check(abs(N16 - fs) <= 1 && abs((k16 - 1) * fs / N16 - 1000) <= 2, ...
    '48 kHz -> 16 kHz resampling keeps a 1 kHz tone at 1 kHz');
r16 = ss_resample(sin(2*pi*7000*t48) + sin(2*pi*12000*t48), 48000, fs);
R = abs(fft(r16));  f16 = (0:numel(r16)-1)' * fs / numel(r16);
a7 = max(R(abs(f16 - 7000) < 20));  a4 = max(R(abs(f16 - 4000) < 20));   % 12 kHz would alias to 4 kHz
check(a4 < 0.1 * a7, '12 kHz component removed before resampling (no aliasing to 4 kHz)');

%% 3. Building blocks
F = ss_mfcc(y, fs, cfg0);
check(size(F.C, 1) == cfg0.nCep && size(F.P, 1) == cfg0.nfft/2 + 1, 'MFCC / spectrum dimensions');
check(all(isfinite(F.C(:))), 'MFCCs are finite');
pe = ss_preEmphasis([1; 0; 0; 0], 0.97);
check(max(abs(pe - [1; -0.97; 0; 0])) < 1e-12, 'pre-emphasis impulse response h[n] = [1, -0.97]');
A = randn(12, 30);  B = randn(12, 45);
% Identical frames have local distance exactly 0 (x - x = 0 in IEEE arithmetic),
% so the diagonal warping path costs exactly 0: no tolerance is needed.
check(ss_dtw(A, A) == 0, 'DTW distance of a sequence to itself is 0');
check(ss_dtw(A, A(:, [1 1 2:30 30 30])) == 0, 'DTW ignores repeated frames (time warping)');
check(abs(ss_dtw([0; 0], [3; 4]) - 2.5) < 1e-12, 'DTW hand-computed value: |(3,4)| / (1+1) = 2.5');
check(abs(ss_dtw(A, B) - ss_dtw(B, A)) < 1e-9, 'DTW is symmetric');
[thr, ci] = ss_calibrateThreshold([1 2 3], [5 6 7]);
check(thr == 4 && ci.FAR == 0 && ci.FRR == 0, 'threshold calibration picks the midpoint (4)');
[~, ci] = ss_calibrateThreshold([1 2 3], []);
check(ci.provisional, 'missing impostor data marked provisional');
img = ss_simulatedPhoto();
check(isequal(size(img), [240 320 3]) && all(img(:) >= 0 & img(:) <= 1), 'simulated photo image valid');

%% 4. Full pipeline with synthetic speakers
root = fullfile(tempdir, 'voicecam_selftest');
if exist(root, 'dir'), rmdir(root, 's'); end
cfg = ss_config(root);
ss_makeDirs(cfg);
user  = struct('f0', 115, 'scale', 1.00);
other = struct('f0', 210, 'scale', 1.18);

for p = 1:numel(cfg.phrases)
    audiowrite(fullfile(cfg.phraseDir, sprintf('phrase_%02d.wav', p)), synthPhrase(user, fs, cfg.phraseSec), fs);
end
for r = 1:cfg.repsPerCommand
    for c = 1:numel(cfg.commands)
        audiowrite(fullfile(cfg.commandDir, sprintf('%s_%02d.wav', cfg.commands{c}, r)), ...
            synthCommand(cfg.commands{c}, user, fs, cfg.commandSec), fs);
    end
end
for r = 1:cfg.otherReps
    for c = 1:numel(cfg.commands)
        audiowrite(fullfile(cfg.otherDir, sprintf('%s_%02d.wav', cfg.commands{c}, r)), ...
            synthCommand(cfg.commands{c}, other, fs, cfg.commandSec), fs);
    end
end

tic;
model = ss_buildModel(cfg);
fprintf('   (model built in %.1f s)\n', toc);
check(model.nCommands == cfg.repsPerCommand * numel(cfg.commands), 'all command templates loaded');
check(~model.speaker.calib.provisional, 'speaker threshold calibrated with other-speaker data');
save(cfg.modelFile, 'model');
S = load(cfg.modelFile, 'model');
check(isfield(S, 'model') && S.model.version == cfg.modelVersion, 'model saves and reloads');

res = ss_recognize(synthCommand('shoot', user, fs, cfg.commandSec), fs, model, cfg);
check(res.ok && res.trigger, sprintf('enrolled speaker + SHOOT -> photo (speaker %d, command %s)', ...
    res.speakerAccepted, res.command));
res = ss_recognize(synthCommand('stop', user, fs, cfg.commandSec), fs, model, cfg);
check(res.ok && ~res.trigger, sprintf('enrolled speaker + STOP -> no photo (command %s)', res.command));
res = ss_recognize(synthCommand('shoot', other, fs, cfg.commandSec), fs, model, cfg);
check(res.ok && ~res.trigger, sprintf('other speaker + SHOOT -> no photo (speaker accepted = %d)', res.speakerAccepted));
res = ss_recognize(zeros(2*fs, 1), fs, model, cfg);
check(~res.ok && ~res.trigger, 'silence -> no photo');

lines = ss_evaluate(model, cfg, false);
check(~isempty(lines) && exist(fullfile(cfg.resultsDir, 'evaluation_report.txt'), 'file') == 2, ...
    'evaluation report written');

fprintf('\n%d passed, %d failed.\n', nPass, nFail);
if nFail == 0
    fprintf('All checks passed. Now run VoiceCameraApp and enroll with your microphone.\n\n');
else
    fprintf(['Some checks failed. Synthetic voices are only an approximation of real speech;\n', ...
             'failures in section 4 do not necessarily mean the app fails with real voices.\n\n']);
end

    function check(cond, name)
        if cond
            nPass = nPass + 1;
            fprintf('  PASS  %s\n', name);
        else
            nFail = nFail + 1;
            fprintf('  FAIL  %s\n', name);
        end
    end
end

%% ---------- synthetic speech (harmonics shaped by formants) ----------
function x = synthCommand(cmd, spk, fs, dur)
switch cmd
    case 'shoot'
        segs = {'n', 0.13, 0, 0; 'v', 0.25, 300, 870; 's', 0.05, 0, 0; 'n', 0.03, 0, 0};
    case 'stop'
        segs = {'n', 0.12, 0, 0; 's', 0.05, 0, 0; 'v', 0.20, 730, 1090; 's', 0.06, 0, 0; 'n', 0.02, 0, 0};
    case 'zoom'
        segs = {'v', 0.10, 250, 2200; 'v', 0.25, 350, 1000; 'v', 0.12, 250, 1200};
    otherwise
        error('unknown command');
end
x = synthUtterance(segs, spk, fs, dur);
end

function x = synthPhrase(spk, fs, dur)
vowels = [730 1090; 270 2290; 300 870; 530 1840; 660 1720; 490 1350];
segs = cell(0, 4);
for k = 1:10
    if rand < 0.25
        segs(end+1, :) = {'n', 0.08, 0, 0}; %#ok<AGROW>
    else
        v = vowels(randi(size(vowels, 1)), :);
        segs(end+1, :) = {'v', 0.15 + 0.1 * rand, v(1), v(2)}; %#ok<AGROW>
    end
end
x = synthUtterance(segs, spk, fs, dur);
end

function x = synthUtterance(segs, spk, fs, dur)
x = zeros(round(0.3 * fs), 1);                % leading silence
for k = 1:size(segs, 1)
    n = max(1, round(segs{k, 2} * (1 + 0.08 * randn) * fs));
    t = (0:n-1)' / fs;
    switch segs{k, 1}
        case 'v'
            f0 = spk.f0 * (1 + 0.03 * randn);
            s = zeros(n, 1);
            F1 = segs{k, 3} * spk.scale;  F2 = segs{k, 4} * spk.scale;  F3 = 2500 * spk.scale;
            for h = 1:floor(4000 / f0)
                fh = h * f0;
                a = exp(-((fh - F1) / 120)^2) + 0.7 * exp(-((fh - F2) / 160)^2) + ...
                    0.3 * exp(-((fh - F3) / 200)^2) + 0.02;
                s = s + a * sin(2 * pi * fh * t + 2 * pi * rand);
            end
        case 'n'
            s = 0.3 * conv(randn(n, 1), [1; -1], 'same');
        otherwise
            s = zeros(n, 1);
    end
    r = min(round(0.005 * fs), floor(n / 2));
    if r > 0
        ramp = (0:r-1)' / r;
        s(1:r) = s(1:r) .* ramp;
        s(end-r+1:end) = s(end-r+1:end) .* flipud(ramp);
    end
    x = [x; s]; %#ok<AGROW>
end
total = round(dur * fs);
x = [x; zeros(max(0, total - numel(x)), 1)];
x = x(1:total);
x = 0.5 * x / max(abs(x)) + 0.002 * randn(total, 1);
x = max(min(x, 1), -1);
end
