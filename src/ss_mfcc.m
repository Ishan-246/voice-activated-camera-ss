function F = ss_mfcc(x, fs, cfg)
%SS_MFCC  Short-time Fourier analysis and mel-frequency cepstral coefficients.
%   F = ss_mfcc(x, fs, cfg) returns a struct:
%     F.C    : nCep x nFrames MFCC matrix (row 1 = c0)
%     F.logE : 1 x nFrames frame energy in dB
%     F.P    : (nfft/2+1) x nFrames power spectrum (for the spectrogram)
%     F.f    : frequency axis in Hz  (f_k = k*fs/nfft)
%     F.t    : time of each frame centre in s
%
%   Steps: framing -> Hamming window -> FFT -> |X|^2 -> mel filters
%          -> log -> DCT.  Written in base MATLAB only (no toolboxes).
x = x(:);
L = round(cfg.frameSec * fs);
H = round(cfg.hopSec * fs);
if numel(x) < L
    x = [x; zeros(L - numel(x), 1)];
end
nF  = 1 + floor((numel(x) - L) / H);
idx = (1:L)' + (0:nF-1) * H;        % each column = sample indices of one frame
frames = x(idx);                    % L x nF

% Hamming window w[n] = 0.54 - 0.46 cos(2 pi n/(L-1)): multiplying in time
% smooths the frame edges and reduces spectral leakage in the FFT.
w = 0.54 - 0.46 * cos(2 * pi * (0:L-1)' / (L - 1));
frames = frames .* w;

nfft = max(cfg.nfft, 2^nextpow2(L));
X = fft(frames, nfft, 1);           % DFT of every frame (Unit 4)
P = abs(X(1:nfft/2 + 1, :)).^2 / nfft;

Hm   = ss_melFilterbank(cfg.nMel, nfft, fs, cfg.melLowHz, min(cfg.melHighHz, fs/2));
melE = Hm * P;
logMel = log(melE + 1e-10);

% DCT-II matrix (orthonormal) -> decorrelated cepstral coefficients.
M = cfg.nMel;
k = (0:cfg.nCep-1)';
m = 0:M-1;
D = sqrt(2 / M) * cos(pi * k * (m + 0.5) / M);
D(1, :) = D(1, :) / sqrt(2);

F.C    = D * logMel;
F.logE = 10 * log10(sum(frames.^2, 1) + eps);
F.P    = P;
F.f    = (0:nfft/2)' * fs / nfft;
F.t    = ((0:nF-1) * H + L / 2) / fs;
end
