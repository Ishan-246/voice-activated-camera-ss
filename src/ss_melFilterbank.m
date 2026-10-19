function Hm = ss_melFilterbank(nMel, nfft, fs, fLow, fHigh)
%SS_MELFILTERBANK  Bank of triangular band-pass filters on the mel scale.
%   Hm is nMel x (nfft/2+1). Row m is the magnitude response of filter m
%   sampled at the FFT bin frequencies f_k = k*fs/nfft.
%   The filters work in parallel (Unit 2: parallel interconnection);
%   their centres are spaced like human pitch perception:
%       mel(f) = 2595*log10(1 + f/700)
mel  = @(f) 2595 * log10(1 + f / 700);
imel = @(m) 700 * (10.^(m / 2595) - 1);

edges = imel(linspace(mel(fLow), mel(fHigh), nMel + 2));
f = (0:nfft/2) * fs / nfft;
Hm = zeros(nMel, numel(f));
for m = 1:nMel
    fl = edges(m);  fc = edges(m + 1);  fr = edges(m + 2);
    rising  = (f - fl) / (fc - fl);
    falling = (fr - f) / (fr - fc);
    Hm(m, :) = max(0, min(rising, falling));
end
end
