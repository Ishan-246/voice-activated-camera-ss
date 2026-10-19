function lines = ss_evaluate(model, cfg, showFigure)
%SS_EVALUATE  Measure accuracy on recordings that were held out from training.
%   Writes results/evaluation_report.txt and results/evaluation.png.
if nargin < 3, showFigure = true; end
cm = model.command;
nC = numel(cm.labels);
L = {};
L{end+1} = 'VOICE-ACTIVATED CAMERA - EVALUATION REPORT';
L{end+1} = sprintf('Generated: %s   (model trained %s)', ...
    char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), model.created);
L{end+1} = '';

%% Speaker verification
G = model.speaker.genuineScores;
I = model.speaker.impostorScores;
thr = model.speaker.thr;
L{end+1} = '1) SPEAKER VERIFICATION (VQ codebook distance, lower = more similar)';
L{end+1} = sprintf('   Threshold: %.3f', thr);
L{end+1} = sprintf('   Your held-out recordings (leave-one-out): %d, wrongly rejected: %d (%.0f%%)', ...
    numel(G), sum(G > thr), 100 * mean(G > thr));
if isempty(I)
    L{end+1} = '   Other-speaker recordings: none -> threshold is PROVISIONAL and';
    L{end+1} = '   rejection of other people has NOT been measured. Use button 2.';
else
    L{end+1} = sprintf('   Other-speaker recordings: %d, wrongly accepted: %d (%.0f%%)', ...
        numel(I), sum(I <= thr), 100 * mean(I <= thr));
    L{end+1} = '   Note: the other-speaker clips were also used to place the threshold,';
    L{end+1} = '   so the false-acceptance figure is optimistic.';
end
L{end+1} = '';

%% Command recognition, leave-one-out on your templates
labelsX = [upper(cm.labels), {'REJECTED'}];
conf = zeros(nC, nC + 1);
for t = 1:numel(cm.templates)
    r = ss_classifyCommand(cm.templates{t}, cm, t);
    conf(cm.templateClass(t), predIndex(r, cm)) = conf(cm.templateClass(t), predIndex(r, cm)) + 1;
end
L{end+1} = '2) COMMAND RECOGNITION - your recordings, leave-one-out';
L = [L, confusionLines(conf, upper(cm.labels), labelsX)];
L{end+1} = sprintf('   Correct: %d of %d', trace(conf(:, 1:nC)), sum(conf(:)));
L{end+1} = '   (thresholds were calibrated with all templates, so this is approximate)';
L{end+1} = '';

%% Command recognition on the other speaker (never used as templates)
conf2 = zeros(nC, nC + 1);
nO = 0;  nSpkAcc = 0;  nFired = 0;
for k = 1:numel(model.speaker.impostorFiles)
    [~, name] = fileparts(model.speaker.impostorFiles{k});
    trueC = find(strcmpi(strtok(name, '_'), cm.labels), 1);
    if isempty(trueC), continue; end
    [x, fs] = audioread(model.speaker.impostorFiles{k});
    res = ss_recognize(x, fs, model, cfg);
    if ~res.ok, continue; end
    if res.commandAccepted
        p = find(strcmp(res.command, cm.labels), 1);
    else
        p = nC + 1;
    end
    conf2(trueC, p) = conf2(trueC, p) + 1;
    nO = nO + 1;
    nSpkAcc = nSpkAcc + res.speakerAccepted;
    nFired  = nFired + res.trigger;
end
L{end+1} = '3) OTHER SPEAKER saying the commands (fully held-out for command recognition)';
if nO == 0
    L{end+1} = '   No other-speaker recordings yet.';
else
    L = [L, confusionLines(conf2, upper(cm.labels), labelsX)];
    L{end+1} = sprintf('   Other speaker accepted as you: %d of %d;  camera fired: %d of %d', ...
        nSpkAcc, nO, nFired, nO);
end
L{end+1} = '';
L{end+1} = 'LIMITATIONS: small number of recordings, one microphone, one room.';
L{end+1} = 'A replayed recording of your voice WILL be accepted. Academic prototype only.';

lines = L;

%% Save report
fid = fopen(fullfile(cfg.resultsDir, 'evaluation_report.txt'), 'w');
if fid > 0
    fprintf(fid, '%s\r\n', L{:});
    fclose(fid);
end

%% Figure
vis = 'on';
if ~showFigure, vis = 'off'; end
fig = figure('Name', 'Evaluation', 'NumberTitle', 'off', 'Visible', vis, ...
             'Units', 'normalized', 'Position', [0.1 0.15 0.8 0.6]);
ax1 = subplot(1, 2, 1, 'Parent', fig);
h = histogram(ax1, G, 'FaceColor', [0.2 0.6 0.2]);
names = {'You (held out)'};
hold(ax1, 'on');
if ~isempty(I)
    h(2) = histogram(ax1, I, 'FaceColor', [0.8 0.2 0.2]);
    names{2} = 'Other speaker';
end
xline(ax1, thr, 'k--', 'threshold', 'LineWidth', 1.5);
legend(ax1, h, names, 'Location', 'best');
hold(ax1, 'off');
xlabel(ax1, 'Speaker distance score (lower = closer to your voice)');
ylabel(ax1, 'Number of recordings');
title(ax1, 'Speaker verification scores');
grid(ax1, 'on');

ax2 = subplot(1, 2, 2, 'Parent', fig);
imagesc(ax2, conf);
colormap(ax2, flipud(gray));
for i = 1:size(conf, 1)
    for j = 1:size(conf, 2)
        text(ax2, j, i, num2str(conf(i, j)), 'HorizontalAlignment', 'center', ...
             'Color', [0.8 0 0], 'FontWeight', 'bold', 'FontSize', 14);
    end
end
set(ax2, 'XTick', 1:nC+1, 'XTickLabel', labelsX, 'YTick', 1:nC, 'YTickLabel', upper(cm.labels));
xlabel(ax2, 'Recognised as');
ylabel(ax2, 'Actually said');
title(ax2, 'Command recognition (your recordings, leave-one-out)');
try
    exportgraphics(fig, fullfile(cfg.resultsDir, 'evaluation.png'));
catch
    saveas(fig, fullfile(cfg.resultsDir, 'evaluation.png'));
end
if ~showFigure
    close(fig);
end
end

function p = predIndex(r, cm)
if r.accepted
    p = find(strcmp(r.command, cm.labels), 1);
else
    p = numel(cm.labels) + 1;           % REJECTED column
end
end

function L = confusionLines(conf, rowLabels, colLabels)
L = {};
hdr = sprintf('%12s', 'said \ got');
for j = 1:numel(colLabels), hdr = [hdr, sprintf('%10s', colLabels{j})]; end %#ok<AGROW>
L{end+1} = ['   ', hdr];
for i = 1:numel(rowLabels)
    row = sprintf('%12s', rowLabels{i});
    for j = 1:size(conf, 2), row = [row, sprintf('%10d', conf(i, j))]; end %#ok<AGROW>
    L{end+1} = ['   ', row]; %#ok<AGROW>
end
end
