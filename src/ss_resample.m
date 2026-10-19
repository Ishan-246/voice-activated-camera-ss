function y = ss_resample(x, fsIn, fsOut)
%SS_RESAMPLE  Change the sampling rate of x from fsIn to fsOut (base MATLAB).
%   When reducing the rate, frequencies above the new Nyquist limit fsOut/2
%   would alias, so x is first low-pass filtered by convolving it with a
%   windowed-sinc impulse response (truncated ideal low-pass filter whose
%   frequency response is a rectangle). Then new samples are interpolated.
x = x(:);
if fsIn == fsOut || isempty(x)
    y = x;
    return;
end
if fsOut < fsIn
    fc = 0.45 * fsOut;                          % cut-off just below fsOut/2
    n  = (-50:50)';
    h  = sin(2 * pi * fc * n / fsIn) ./ (pi * n);
    h(n == 0) = 2 * fc / fsIn;
    h  = h .* (0.54 + 0.46 * cos(pi * n / 50)); % Hamming taper
    h  = h / sum(h);                            % unity gain at 0 Hz
    x  = conv(x, h, 'same');
end
tIn  = (0:numel(x)-1)' / fsIn;
tOut = (0:1/fsOut:tIn(end))';
y = interp1(tIn, x, tOut, 'linear');
end
