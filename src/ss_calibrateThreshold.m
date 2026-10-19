function [thr, info] = ss_calibrateThreshold(G, I)
%SS_CALIBRATETHRESHOLD  Choose a distance threshold from measured scores.
%   G : distances of GENUINE trials (should be accepted, small values)
%   I : distances of IMPOSTOR trials (should be rejected, large values)
%   A trial is accepted when distance <= thr.
%
%   With impostor data: thr minimises (false rejections + false acceptances).
%   If the two groups are separable this is the midpoint between the largest
%   genuine and the smallest impostor distance.
%   Without impostor data: thr = max(G) + std(G) (accepts all held-out
%   genuine trials plus one standard deviation of margin). This is marked
%   PROVISIONAL because rejection has not been measured.
G = G(:);  I = I(:);
info.provisional = isempty(I);
if isempty(G)
    error('ss_calibrateThreshold:noData', 'No genuine scores for calibration.');
end

if isempty(I)
    thr = max(G) + std(G);
    info.FRR = mean(G > thr);
    info.FAR = NaN;
    return;
end

s = unique([G; I]);
step = max(1e-9, 1e-6 * max(abs(s)));
cands = [s(1) - step; (s(1:end-1) + s(2:end)) / 2; s(end) + step];
errs = zeros(size(cands));
for k = 1:numel(cands)
    errs(k) = mean(G > cands(k)) + mean(I <= cands(k));
end
best = find(errs == min(errs));
thr = cands(best(ceil(numel(best) / 2)));
info.FRR = mean(G > thr);
info.FAR = mean(I <= thr);
end
