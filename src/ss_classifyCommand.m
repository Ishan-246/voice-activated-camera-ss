function r = ss_classifyCommand(X, cm, excludeIdx)
%SS_CLASSIFYCOMMAND  Nearest-template command recognition with rejection.
%   X          : feat.cmd of the new recording
%   cm         : model.command (templates, classes, calibrated thresholds)
%   excludeIdx : template index to ignore (for leave-one-out tests), or 0
%
%   For each command c: d(c) = smallest DTW distance to c's templates.
%   Normalised score s(c) = d(c) / threshold(c)  (s <= 1 means "close enough").
%   Accepted only if exactly ONE command has s <= 1; if none -> 'unknown',
%   if several -> 'uncertain'. Both are rejected.
if nargin < 3, excludeIdx = 0; end
nC = numel(cm.labels);
d = inf(1, nC);
for t = 1:numel(cm.templates)
    if t == excludeIdx, continue; end
    c = cm.templateClass(t);
    d(c) = min(d(c), ss_dtw(X, cm.templates{t}));
end
s = d ./ cm.thr;
[sSorted, order] = sort(s);

r.dist = d;
r.norm = s;
r.bestIdx = order(1);
if sSorted(1) <= 1 && (nC == 1 || sSorted(2) > 1)
    r.command  = cm.labels{order(1)};
    r.accepted = true;
    r.reason   = 'matches exactly one enrolled command';
elseif sSorted(1) <= 1
    r.command  = 'uncertain';
    r.accepted = false;
    r.reason   = sprintf('close to both "%s" and "%s"', ...
                         upper(cm.labels{order(1)}), upper(cm.labels{order(2)}));
else
    r.command  = 'unknown';
    r.accepted = false;
    r.reason   = sprintf('not close enough to any command (nearest: "%s")', ...
                         upper(cm.labels{order(1)}));
end
end
