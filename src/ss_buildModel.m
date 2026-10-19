function model = ss_buildModel(cfg)
%SS_BUILDMODEL  Train and calibrate both recognisers from the saved WAV files.
%   Reads data/enroll_phrases, data/enroll_commands and (optionally)
%   data/other_speaker, then returns the model struct (saved by the caller).
%
%   Speaker verification
%     model  : VQ codebook of all your recordings.
%     genuine: each of your COMMAND recordings is held out in turn, the
%              model is retrained without it, and the held-out one is scored
%              (leave-one-out, so it is never tested on its own training data).
%     impostor: recordings of the other speaker (if any).
%   Command recognition
%     templates: your command recordings.
%     genuine : each template vs the other templates of the same command.
%     impostor: templates of the other commands and your free phrases.

%% Load your recordings
phraseFiles = ss_listWav(cfg.phraseDir, 'phrase_*.wav');
cmdFiles = {};  cmdClass = [];
for c = 1:numel(cfg.commands)
    f = ss_listWav(cfg.commandDir, [cfg.commands{c} '_*.wav']);
    if numel(f) < 2
        error('ss_buildModel:notEnough', ...
            ['Not enough enrollment recordings for the command "%s" (found %d, need at least 2). ', ...
             'Press "1. Enroll my voice" and complete all recordings.'], upper(cfg.commands{c}), numel(f));
    end
    cmdFiles = [cmdFiles, f];                         %#ok<AGROW>
    cmdClass = [cmdClass, c * ones(1, numel(f))];      %#ok<AGROW>
end

[phraseFeat, okP] = loadFeatures(phraseFiles, cfg);
[cmdFeat, okC]    = loadFeatures(cmdFiles, cfg);
phraseFeat = phraseFeat(okP);
cmdFeat  = cmdFeat(okC);
cmdFiles = cmdFiles(okC);
cmdClass = cmdClass(okC);
for c = 1:numel(cfg.commands)
    if sum(cmdClass == c) < 2
        error('ss_buildModel:badRecordings', ...
            'Too few usable recordings of "%s". Please enroll again and speak clearly.', upper(cfg.commands{c}));
    end
end

%% Other speaker (optional)
otherFiles = ss_listWav(cfg.otherDir, '*.wav');
[otherFeat, okO] = loadFeatures(otherFiles, cfg);
otherFeat  = otherFeat(okO);
otherFiles = otherFiles(okO);

%% ---------------- Speaker model ----------------
userSpk = [cellfun(@(f) f.spk, phraseFeat, 'UniformOutput', false), ...
           cellfun(@(f) f.spk, cmdFeat,    'UniformOutput', false)];
nP = numel(phraseFeat);
sm = ss_trainSpeaker(userSpk, cfg);

G = zeros(numel(cmdFeat), 1);
for i = 1:numel(cmdFeat)
    others = true(1, numel(userSpk));
    others(nP + i) = false;                         % hold out command recording i
    smLoo = ss_trainSpeaker(userSpk(others), cfg);
    G(i) = ss_speakerScore(cmdFeat{i}.spk, smLoo);
end
I = zeros(numel(otherFeat), 1);
for i = 1:numel(otherFeat)
    I(i) = ss_speakerScore(otherFeat{i}.spk, sm);
end
[spkThr, spkInfo] = ss_calibrateThreshold(G, I);

model.speaker.sm = sm;
model.speaker.thr = spkThr;
model.speaker.calib = spkInfo;
model.speaker.genuineScores  = G;
model.speaker.impostorScores = I;
model.speaker.impostorFiles  = otherFiles;

%% ---------------- Command model ----------------
templates = cellfun(@(f) f.cmd, cmdFeat, 'UniformOutput', false);
rows = [templates, cellfun(@(f) f.cmd, phraseFeat, 'UniformOutput', false)];
nT = numel(templates);
Dall = zeros(numel(rows), nT);                      % DTW distance table
for r = 1:numel(rows)
    for t = 1:nT
        if r <= nT && t < r
            Dall(r, t) = Dall(t, r);                % DTW here is symmetric
        elseif r ~= t
            Dall(r, t) = ss_dtw(rows{r}, templates{t});
        end
    end
end

nC = numel(cfg.commands);
thr = zeros(1, nC);
calib = cell(1, nC);
Gc = cell(1, nC);  Ic = cell(1, nC);
rowClass = [cmdClass, zeros(1, numel(phraseFeat))];  % phrases = class 0
for c = 1:nC
    inC = find(cmdClass == c);
    g = zeros(numel(inC), 1);
    for k = 1:numel(inC)
        sameOthers = inC(inC ~= inC(k));
        g(k) = min(Dall(inC(k), sameOthers));
    end
    notC = find(rowClass ~= c);
    imp = zeros(numel(notC), 1);
    for k = 1:numel(notC)
        imp(k) = min(Dall(notC(k), inC));
    end
    [thr(c), calib{c}] = ss_calibrateThreshold(g, imp);
    Gc{c} = g;  Ic{c} = imp;
end

model.command.labels = cfg.commands;
model.command.templates = templates;
model.command.templateClass = cmdClass;
model.command.templateFiles = cmdFiles;
model.command.thr = thr;
model.command.calib = calib;
model.command.genuineScores = Gc;
model.command.impostorScores = Ic;

model.version = cfg.modelVersion;
model.fs = cfg.fs;
model.trigger = cfg.triggerCommand;
model.created = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
model.nPhrases = numel(phraseFeat);
model.nCommands = nT;
model.nOther = numel(otherFeat);
end

function [feats, ok] = loadFeatures(files, cfg)
feats = cell(1, numel(files));
ok = false(1, numel(files));
for k = 1:numel(files)
    try
        [x, fs] = audioread(files{k});
    catch
        warning('ss_buildModel:read', 'Could not read %s - skipped.', files{k});
        continue;
    end
    [y, info] = ss_preprocess(x, fs, cfg);
    if ~info.ok
        warning('ss_buildModel:unusable', 'Skipped %s: %s', files{k}, info.msg);
        continue;
    end
    feats{k} = ss_features(y, cfg.fs, cfg);
    ok(k) = true;
end
end
