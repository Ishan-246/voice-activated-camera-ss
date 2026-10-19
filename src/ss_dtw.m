function d = ss_dtw(A, B)
%SS_DTW  Dynamic time warping distance between two feature sequences.
%   A is d x n, B is d x m (one column per 10 ms frame).
%   DTW stretches/compresses time so that "shoooot" and "shoot" can still
%   be compared frame by frame. The result is normalised by (n + m) so long
%   and short words are comparable. Lower = more similar.
n = size(A, 2);
m = size(B, 2);

% Local frame-to-frame Euclidean distances C(i,j) = ||A(:,i) - B(:,j)||, n x m.
% Computed from the differences directly, NOT with the shortcut
% ||a||^2 + ||b||^2 - 2*a'*b (ss_sqdist): for identical frames that shortcut
% leaves a rounding residue of ~1e-15 instead of 0, and sqrt magnifies it
% to ~1e-8. Here identical frames give exactly 0, as the definition requires.
C = zeros(n, m);
for k = 1:size(A, 1)
    C = C + (A(k, :)' - B(k, :)).^2;   % n x 1 minus 1 x m -> n x m
end
C = sqrt(C);

D = inf(n + 1, m + 1);
D(1, 1) = 0;
for i = 1:n
    for j = 1:m
        D(i + 1, j + 1) = C(i, j) + min(min(D(i, j + 1), D(i + 1, j)), D(i, j));
    end
end
d = D(n + 1, m + 1) / (n + m);
end
