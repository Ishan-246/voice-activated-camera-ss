function res = ss_recognize(x, fs, model, cfg)
%SS_RECOGNIZE  Speaker check + command check + camera decision for one recording.
%   The two checks are independent; the camera fires only if BOTH pass:
%       trigger = speakerAccepted AND command == 'shoot'
[y, info] = ss_preprocess(x, fs, cfg);
res.info = info;
res.y = y;
res.ok = info.ok;
res.speakerScore = NaN;
res.speakerThr = model.speaker.thr;
res.speakerAccepted = false;
res.command = 'none';
res.commandAccepted = false;
res.commandReason = info.msg;
res.commandNorm = [];
res.trigger = false;
if ~info.ok
    return;
end

feat = ss_features(y, cfg.fs, cfg);

% 1) Speaker verification
res.speakerScore = ss_speakerScore(feat.spk, model.speaker.sm);
res.speakerAccepted = res.speakerScore <= model.speaker.thr;

% 2) Command recognition
r = ss_classifyCommand(feat.cmd, model.command, 0);
res.command = r.command;
res.commandAccepted = r.accepted;
res.commandReason = r.reason;
res.commandNorm = r.norm;

% 3) Decision
res.trigger = res.speakerAccepted && res.commandAccepted && ...
              strcmp(res.command, model.trigger);
end
