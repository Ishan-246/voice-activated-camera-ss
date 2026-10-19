function [y, info] = ss_preprocess(x, fs, cfg)
%SS_PREPROCESS  Check a recording and cut out the spoken part.
%   [y, info] = ss_preprocess(x, fs, cfg)
%     x    : recorded samples (any length, mono or stereo)
%     fs   : sampling frequency of x in Hz
%     y    : speech part only, DC removed, amplitude-normalised to peak 1
%     info : .ok (true/false), .msg (reason if not ok), .warning,
%            .xFull (whole recording at cfg.fs), .startIdx, .endIdx
%
%   Signal operations used (Unit 1): DC removal (amplitude shift), time
%   segmentation (windowing a part of the signal), amplitude scaling.

info = struct('ok', false, 'msg', '', 'warning', '', 'xFull', [], ...
              'startIdx', [], 'endIdx', [], 'peak', 0);
y = [];

if isempty(x)
    info.msg = 'The recording is empty.';
    return;
end
if size(x, 1) > 1 && size(x, 2) > 1
    x = mean(x, 2);                 % stereo -> mono
end
x = double(x(:));
x(~isfinite(x)) = 0;

% Bring everything to the project sampling rate (normally already equal).
if fs ~= cfg.fs
    x = ss_resample(x, fs, cfg.fs);
    info.warning = sprintf('Audio was resampled from %d Hz to %d Hz.', fs, cfg.fs);
end
fs = cfg.fs;

if mean(abs(x) >= 0.99) > 0.001
    info.warning = 'Recording is clipped (too loud). Move a little away from the microphone.';
end

x = x - mean(x);                    % remove DC offset
info.xFull = x;
info.peak  = max(abs(x));

if info.peak < cfg.minPeak
    info.msg = ['No speech detected - the recording is almost silent. Speak louder or ', ...
                'closer, and check that Windows allows MATLAB to use the microphone.'];
    return;
end

% Short-time energy in 20 ms frames, 10 ms hop.
L = round(0.020 * fs);
H = round(0.010 * fs);
N = numel(x);
if N < L
    info.msg = 'The recording is too short.';
    return;
end
nF  = floor((N - L) / H) + 1;
idx = (1:L)' + (0:nF-1) * H;        % L x nF sample indices
e   = sum(x(idx).^2, 1);
eDb = 10 * log10(e + eps);

% Noise floor = mean of the quietest 5% of frames.
eSorted = sort(eDb);
nQuiet  = max(1, round(0.05 * nF));
noiseDb = mean(eSorted(1:nQuiet));
if max(eDb) - noiseDb < cfg.minSnrDb
    info.msg = ['No clear speech detected - only background noise was heard. ', ...
                'Speak clearly after the RECORDING prompt appears.'];
    return;
end

active = eDb > max(eDb) - cfg.trimDb;
first  = find(active, 1, 'first');
last   = find(active, 1, 'last');
pad    = round(cfg.padSec * fs);
s = max(1, (first - 1) * H + 1 - pad);
t = min(N, (last - 1) * H + L + pad);

if (t - s + 1) / fs < cfg.minSpeechSec
    info.msg = 'The spoken part was too short. Please say the whole word clearly.';
    return;
end
if last == nF && isempty(info.warning)
    info.warning = 'Speech continued until the end of the recording - it may have been cut off.';
end

y = x(s:t);
y = y / max(abs(y));                % amplitude normalisation
info.startIdx = s;
info.endIdx   = t;
info.ok = true;
end
