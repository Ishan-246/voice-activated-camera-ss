function y = ss_preEmphasis(x, a)
%SS_PREEMPHASIS  First-order FIR high-pass (an LTI system).
%   Difference equation : y[n] = x[n] - a*x[n-1]
%   Impulse response    : h[n] = [1, -a]
%   Z-transform         : H(z) = 1 - a z^-1   (zero at z = a, near z = 1)
%   It is computed here as a convolution sum y = x * h (Unit 2).
%   It boosts high frequencies, which are weak in voiced speech.
h = [1; -a];
y = conv(x(:), h);
y = y(1:numel(x));                  % keep same length as the input
end
