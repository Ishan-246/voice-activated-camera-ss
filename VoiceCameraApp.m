function VoiceCameraApp
%VOICECAMERAAPP  Voice-Activated Camera Simulation (Signals & Systems project).
%
%   HOW TO USE: open this file in MATLAB and press Run (or type
%   VoiceCameraApp in the Command Window). Then follow the on-screen
%   instructions. No code needs to be edited.
%
%   Buttons
%     1. Enroll my voice          - records your voice (first launch)
%     2. Record another speaker   - optional, improves/measures rejection
%     3. TEST - say a command     - the actual voice camera
%     Evaluate accuracy           - report on held-out recordings
%
%   The simulated camera takes a photo only if
%       (speaker is accepted)  AND  (command recognised as "SHOOT").

projectDir = fileparts(mfilename('fullpath'));
addpath(fullfile(projectDir, 'src'));
cfg = ss_config(projectDir);
ss_makeDirs(cfg);

model = [];
busy = false;
recFs = [];          % microphone sampling rate that works (found on first recording)

%% ---------------- Build the window ----------------
fig = figure('Name', 'Voice-Activated Camera Simulation', 'NumberTitle', 'off', ...
    'MenuBar', 'none', 'ToolBar', 'figure', 'Units', 'normalized', ...
    'Position', [0.05 0.06 0.90 0.86], 'Color', [0.95 0.95 0.95]);

uicontrol(fig, 'Style', 'text', 'Units', 'normalized', 'Position', [0.01 0.92 0.24 0.06], ...
    'String', 'Voice Camera', 'FontSize', 18, 'FontWeight', 'bold', ...
    'BackgroundColor', [0.95 0.95 0.95]);

btnEnroll = makeButton([0.02 0.83 0.22 0.07], '1. Enroll my voice', [0.85 0.90 1.00], @onEnroll);
btnOther  = makeButton([0.02 0.75 0.22 0.07], '2. Record another speaker (optional)', [0.95 0.92 0.85], @onOther);
btnTest   = makeButton([0.02 0.62 0.22 0.11], '3. TEST - say a command', [0.70 0.92 0.70], @onTest);
set(btnTest, 'FontSize', 14);
btnEval   = makeButton([0.02 0.54 0.105 0.06], 'Evaluate accuracy', [0.92 0.92 0.92], @onEvaluate);
btnHelp   = makeButton([0.135 0.54 0.105 0.06], 'Help', [0.92 0.92 0.92], @onHelp);
buttons = [btnEnroll, btnOther, btnTest, btnEval, btnHelp];

uicontrol(fig, 'Style', 'text', 'Units', 'normalized', 'Position', [0.02 0.495 0.22 0.03], ...
    'String', 'Messages:', 'HorizontalAlignment', 'left', 'BackgroundColor', [0.95 0.95 0.95]);
statusBox = uicontrol(fig, 'Style', 'listbox', 'Units', 'normalized', ...
    'Position', [0.02 0.02 0.22 0.48], 'Max', 2, 'Min', 0, 'Value', [], ...
    'String', {}, 'FontName', 'Consolas', 'FontSize', 9);

promptBox = uicontrol(fig, 'Style', 'text', 'Units', 'normalized', ...
    'Position', [0.28 0.84 0.70 0.14], 'FontSize', 15, 'FontWeight', 'bold', ...
    'BackgroundColor', [1 1 1], 'String', '');

axWave  = axes(fig, 'Position', [0.31 0.47 0.30 0.30]);
axSpec  = axes(fig, 'Position', [0.67 0.47 0.30 0.30]);
axSgram = axes(fig, 'Position', [0.31 0.06 0.30 0.32]);
axCam   = axes(fig, 'Position', [0.67 0.04 0.30 0.35]);
resetPlots();
showCameraLocked('Camera idle');

%% ---------------- Start-up ----------------
logMsg('Project folder: %s', projectDir);
checkMicrophone();
loadModel();
drawnow;

if isempty(model)
    setPrompt({'Welcome! You have not enrolled your voice yet.', ...
               'Press "1. Enroll my voice" to begin.'}, [0 0 0.6]);
    choice = questdlg(sprintf(['Welcome to the Voice-Activated Camera Simulation!\n\n', ...
        'Before the camera can recognise you, it needs to learn your voice.\n', ...
        'Enrollment takes about 2 minutes: you will read %d short phrases and say ', ...
        'each command (%s) %d times.\n\nUse a quiet room. Start enrollment now?'], ...
        numel(cfg.phrases), strjoin(upper(cfg.commands), ', '), cfg.repsPerCommand), ...
        'First launch', 'Start enrollment', 'Later', 'Start enrollment');
    if strcmp(choice, 'Start enrollment')
        runSafely(@doEnroll);
    end
else
    setPrompt({'Ready. Press "3. TEST - say a command".', ...
               'Say SHOOT to take a photo.'}, [0 0.45 0]);
end

%% ======================================================================
%%                          Callbacks
%% ======================================================================
    function onEnroll(~, ~)
        runSafely(@doEnroll);
    end

    function onOther(~, ~)
        runSafely(@doOther);
    end

    function onTest(~, ~)
        runSafely(@doTest);
    end

    function onEvaluate(~, ~)
        runSafely(@doEvaluate);
    end

    function onHelp(~, ~)
        msgbox({ ...
            'WORKFLOW', ...
            '1. Enroll my voice: read the phrases and say each command when asked.', ...
            '2. (Optional) Ask a friend to press "Record another speaker" and say', ...
            '   the commands. This calibrates and measures rejection of other people.', ...
            '3. TEST: press the button, wait for "RECORDING", then say a command.', ...
            '', ...
            'The photo is taken only if BOTH checks pass:', ...
            '   - speaker check: the voice matches your enrolled voice', ...
            '   - command check: the word is recognised as SHOOT', ...
            '', ...
            'Recordings: data folder.  Photos, plots, report: results folder.', ...
            'Enrollment is saved, so you only enroll once.', ...
            '', ...
            'This is an academic prototype: a recording of your voice played', ...
            'back through a speaker can fool it.'}, 'Help');
    end

%% ---------------- Enrollment ----------------
    function doEnroll()
        old = [ss_listWav(cfg.phraseDir, '*.wav'), ss_listWav(cfg.commandDir, '*.wav')];
        if ~isempty(old)
            c = questdlg('This will replace your previous enrollment. Continue?', ...
                'Re-enroll', 'Yes, re-enroll', 'Cancel', 'Cancel');
            if ~strcmp(c, 'Yes, re-enroll'), return; end
        end
        uiwait(msgbox({ ...
            'ENROLLMENT', '', ...
            'For each recording:', ...
            '  1. Read the text shown at the top of the window.', ...
            '  2. Wait for the red "RECORDING - SPEAK NOW" message.', ...
            '  3. Speak clearly at your normal volume.', '', ...
            sprintf('Phrases: %.0f s each.  Commands: %.0f s each (say the word once).', ...
                    cfg.phraseSec, cfg.commandSec), '', ...
            'Press OK when you are ready.'}, 'Enrollment'));

        for k = 1:numel(old), delete(old{k}); end
        if exist(cfg.modelFile, 'file'), delete(cfg.modelFile); end
        model = [];

        % Build the list of prompts: phrases first, then commands interleaved.
        items = struct('text', {}, 'sec', {}, 'file', {});
        for p = 1:numel(cfg.phrases)
            items(end+1) = struct('text', ['Read aloud:  "' cfg.phrases{p} '"'], ...
                'sec', cfg.phraseSec, 'file', fullfile(cfg.phraseDir, sprintf('phrase_%02d.wav', p))); %#ok<AGROW>
        end
        for r = 1:cfg.repsPerCommand
            for c = 1:numel(cfg.commands)
                items(end+1) = struct('text', ['Say the command:  ' upper(cfg.commands{c})], ...
                    'sec', cfg.commandSec, ...
                    'file', fullfile(cfg.commandDir, sprintf('%s_%02d.wav', cfg.commands{c}, r))); %#ok<AGROW>
            end
        end

        for k = 1:numel(items)
            label = sprintf('Enrollment %d of %d', k, numel(items));
            if ~recordAndSave(label, items(k).text, items(k).sec, items(k).file)
                setPrompt({'Enrollment cancelled.', 'Press "1. Enroll my voice" to start again.'}, [0.6 0 0]);
                logMsg('Enrollment cancelled.');
                return;
            end
        end
        logMsg('All %d enrollment recordings saved.', numel(items));
        trainModel();
        if ~isempty(model)
            setPrompt({'Enrollment complete!', ...
                'Press "3. TEST - say a command" and say SHOOT.'}, [0 0.45 0]);
            uiwait(msgbox({'Enrollment complete and saved.', '', ...
                'Now press "3. TEST - say a command" and say SHOOT.', '', ...
                'Recommended: ask another person to use button 2, so the', ...
                'system can learn to reject voices that are not yours.'}, 'Done'));
        end
    end

%% ---------------- Other speaker ----------------
    function doOther()
        if isempty(model)
            msgbox('Please enroll your own voice first (button 1).', 'Not enrolled');
            return;
        end
        c = questdlg(sprintf(['Hand the laptop to ANOTHER person.\n\n', ...
            'They will say each command (%s) %d times.\n', ...
            'These recordings teach the system what a different voice looks like ', ...
            'and are used to calibrate the speaker threshold.\n\nReady?'], ...
            strjoin(upper(cfg.commands), ', '), cfg.otherReps), ...
            'Other speaker', 'Start', 'Cancel', 'Start');
        if ~strcmp(c, 'Start'), return; end

        n = 0;  total = cfg.otherReps * numel(cfg.commands);
        for r = 1:cfg.otherReps
            for c = 1:numel(cfg.commands)
                n = n + 1;
                file = nextFreeName(cfg.otherDir, cfg.commands{c});
                if ~recordAndSave(sprintf('Other speaker %d of %d', n, total), ...
                        ['OTHER PERSON - say:  ' upper(cfg.commands{c})], cfg.commandSec, file)
                    logMsg('Other-speaker recording stopped early.');
                    break;
                end
            end
        end
        trainModel();
        if ~isempty(model)
            setPrompt({'Other-speaker samples saved and threshold recalibrated.', ...
                'Press "Evaluate accuracy" to see the results.'}, [0 0.45 0]);
        end
    end

%% ---------------- Test ----------------
    function doTest()
        if isempty(model)
            c = questdlg('You have not enrolled yet. Enroll now?', 'Not enrolled', ...
                'Enroll now', 'Cancel', 'Enroll now');
            if strcmp(c, 'Enroll now'), doEnroll(); end
            return;
        end
        x = recordClip('TEST', ['Say a command:  ' strjoin(upper(cfg.commands), '  /  ')], cfg.commandSec);
        if isempty(x), return; end

        stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
        testFile = fullfile(cfg.testDir, ['test_' stamp '.wav']);
        audiowrite(testFile, max(min(x, 1), -1), cfg.fs);

        res = ss_recognize(x, cfg.fs, model, cfg);
        plotWave(x, res.info);
        if ~res.ok
            resetPlots(true);
            setPrompt({'No usable speech - camera NOT triggered.', res.info.msg}, [0.7 0 0]);
            showCameraLocked('No speech');
            logMsg('Test: %s', res.info.msg);
            writeLog(testFile, res);
            return;
        end
        if ~isempty(res.info.warning), logMsg('Note: %s', res.info.warning); end
        plotSpectrum(res.y);
        plotSpectrogram(res.y);

        if res.speakerAccepted
            spkLine = sprintf('Speaker: ACCEPTED  (score %.2f <= threshold %.2f)', res.speakerScore, res.speakerThr);
        else
            spkLine = sprintf('Speaker: REJECTED  (score %.2f > threshold %.2f)', res.speakerScore, res.speakerThr);
        end
        if model.speaker.calib.provisional
            spkLine = [spkLine '  [provisional]'];
        end
        if res.commandAccepted
            cmdLine = sprintf('Command: %s  (%s)', upper(res.command), res.commandReason);
        else
            cmdLine = sprintf('Command: REJECTED - %s', res.commandReason);
        end

        if res.trigger
            camLine = 'Camera: PHOTO CAPTURED';
            setPrompt({spkLine, cmdLine, camLine}, [0 0.5 0]);
            takePhoto();
        else
            if ~res.speakerAccepted && res.commandAccepted && strcmp(res.command, model.trigger)
                why = 'voice not recognised';
            elseif ~res.speakerAccepted
                why = 'voice not recognised and command is not SHOOT';
            elseif res.commandAccepted
                why = sprintf('"%s" is not the trigger command', upper(res.command));
            else
                why = 'command not recognised';
            end
            camLine = ['Camera: NOT triggered (' why ')'];
            setPrompt({spkLine, cmdLine, camLine}, [0.7 0 0]);
            showCameraLocked(why);
        end
        logMsg('%s | %s', spkLine, cmdLine);
        logMsg('%s', camLine);
        writeLog(testFile, res);
    end

%% ---------------- Evaluate ----------------
    function doEvaluate()
        if isempty(model)
            msgbox('Please enroll first (button 1).', 'Not enrolled');
            return;
        end
        setPrompt('Evaluating... please wait.', [0 0 0.6]);
        lines = ss_evaluate(model, cfg, true);
        for k = 1:numel(lines), logMsg('%s', lines{k}); end
        setPrompt({'Evaluation finished.', ...
            'Report: results\evaluation_report.txt   Plot: results\evaluation.png'}, [0 0 0.6]);
    end

%% ======================================================================
%%                          Helpers
%% ======================================================================
    function ok = recordAndSave(label, text, sec, file)
        % Record until a usable clip is obtained (or the user cancels).
        ok = false;
        while true
            x = recordClip(label, text, sec);
            if isempty(x), return; end                % microphone error
            [~, info] = ss_preprocess(x, cfg.fs, cfg);
            plotWave(x, info);
            if info.ok
                audiowrite(file, max(min(x, 1), -1), cfg.fs);
                [~, nm, ext] = fileparts(file);
                logMsg('Saved %s%s', nm, ext);
                if ~isempty(info.warning), logMsg('Note: %s', info.warning); end
                ok = true;
                pause(0.4);
                return;
            end
            c = questdlg(sprintf('%s\n\nRecord this one again?', info.msg), 'Recording problem', ...
                'Try again', 'Cancel', 'Try again');
            if ~strcmp(c, 'Try again'), return; end
        end
    end

    function x = recordClip(label, text, sec)
        % Countdown, then record 'sec' seconds from the default microphone.
        % The returned signal is always at cfg.fs.
        x = [];
        if isempty(recFs)
            setPrompt('Connecting to the microphone (allow access if the browser asks)...', [0 0 0.6]);
            [recFs, errMsg] = findWorkingRate();
            if isempty(recFs)
                setPrompt('Microphone error - see the message box.', [0.7 0 0]);
                logMsg('Microphone error: %s', errMsg);
                errordlg(micHelpText(errMsg), 'Microphone problem');
                return;
            end
            logMsg('Microphone recording at %d Hz.', recFs);
        end
        for n = 3:-1:1
            setPrompt({[label ':  ' text], sprintf('Get ready...  %d', n)}, [0 0 0.6]);
            pause(0.5);
        end
        setPrompt({[label ':  ' text], '>>>  RECORDING - SPEAK NOW  <<<'}, [0.85 0 0]);
        try
            rec = audiorecorder(recFs, cfg.nBits, 1);
            recordblocking(rec, sec);
            x = getaudiodata(rec, 'double');
        catch ME
            x = [];
            recFs = [];                              % re-detect next time
            setPrompt('Microphone error - see the message box.', [0.7 0 0]);
            logMsg('Microphone error: %s', ME.message);
            errordlg(micHelpText(ME.message), 'Microphone problem');
            return;
        end
        if size(x, 2) > 1, x = mean(x, 2); end
        x = ss_resample(x, recFs, cfg.fs);           % e.g. 48 kHz -> 16 kHz
        setPrompt({[label ':  ' text], 'Processing...'}, [0 0 0.6]);
        if isempty(x) || all(x == 0)
            logMsg('The microphone returned only zeros (it may be blocked).');
        end
    end

    function [fsOk, errMsg] = findWorkingRate()
        % Try 16 kHz first, then the fallback rates, with a short test recording.
        fsOk = [];  errMsg = 'No audio input device could be opened.';
        for r = [cfg.fs, cfg.fallbackFs]
            try
                rec = audiorecorder(r, cfg.nBits, 1);
                recordblocking(rec, 0.2);
                getaudiodata(rec);
                fsOk = r;
                return;
            catch ME
                errMsg = ME.message;
            end
        end
    end

    function trainModel()
        setPrompt('Training the voice model... please wait.', [0 0 0.6]);
        drawnow;
        try
            m = ss_buildModel(cfg);
            model = m;
            save(cfg.modelFile, 'model');
            logMsg('Model trained: %d phrases, %d command templates, %d other-speaker clips.', ...
                model.nPhrases, model.nCommands, model.nOther);
            if model.speaker.calib.provisional
                logMsg('Speaker threshold %.3f is PROVISIONAL (no other-speaker data).', model.speaker.thr);
            else
                logMsg('Speaker threshold %.3f (held-out rejections %.0f%%, other speaker accepted %.0f%%).', ...
                    model.speaker.thr, 100 * model.speaker.calib.FRR, 100 * model.speaker.calib.FAR);
            end
            for c = 1:numel(model.command.labels)
                logMsg('Command %s threshold %.3f', upper(model.command.labels{c}), model.command.thr(c));
            end
        catch ME
            model = [];
            logMsg('Training failed: %s', ME.message);
            errordlg(ME.message, 'Training failed');
        end
    end

    function loadModel()
        model = [];
        if exist(cfg.modelFile, 'file')
            try
                S = load(cfg.modelFile, 'model');
                if isfield(S, 'model') && isfield(S.model, 'version') && ...
                        S.model.version == cfg.modelVersion && ...
                        isequal(S.model.command.labels, cfg.commands)
                    model = S.model;
                    logMsg('Loaded saved voice model (trained %s).', model.created);
                    return;
                end
            catch
            end
            logMsg('Saved model is outdated or unreadable - retraining from recordings.');
        end
        if ~isempty(ss_listWav(cfg.commandDir, '*.wav'))
            trainModel();
        else
            logMsg('No enrollment found. Press "1. Enroll my voice".');
        end
    end

    function checkMicrophone()
        try
            info = audiodevinfo;
            if isempty(info.input)
                logMsg(['No microphone listed (normal in MATLAB Online). ', ...
                        'Recording will still be attempted.']);
            else
                logMsg('Microphone: %s', info.input(1).Name);
            end
        catch
            logMsg('Could not list audio devices; will try the default microphone.');
        end
    end

    function takePhoto()
        img = ss_simulatedPhoto();
        image(axCam, ones(size(img)));               % white "flash"
        axis(axCam, 'image', 'off');
        title(axCam, 'FLASH!');
        drawnow;
        playShutter();
        pause(0.15);
        stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
        file = fullfile(cfg.photoDir, ['photo_' stamp '.png']);
        imwrite(img, file);
        image(axCam, img);
        axis(axCam, 'image', 'off');
        text(axCam, 8, 228, ['Simulated photo  ' char(datetime('now', 'Format', 'HH:mm:ss'))], ...
            'Color', 'w', 'FontWeight', 'bold', 'FontSize', 10);
        title(axCam, sprintf('PHOTO CAPTURED - saved as results\\photos\\photo_%s.png', stamp), ...
            'Color', [0 0.5 0], 'Interpreter', 'none');
        logMsg('Photo saved: results\\photos\\photo_%s.png', stamp);
    end

    function playShutter()
        n = round(0.06 * cfg.fs);
        click = randn(n, 1) .* exp(-(0:n-1)' / (0.008 * cfg.fs));
        try
            sound(0.5 * click / max(abs(click)), cfg.fs);
        catch
        end
    end

    function showCameraLocked(reason)
        image(axCam, 0.25 * ones(240, 320, 3));
        axis(axCam, 'image', 'off');
        text(axCam, 160, 105, 'CAMERA LOCKED', 'Color', 'w', 'FontSize', 16, ...
            'FontWeight', 'bold', 'HorizontalAlignment', 'center');
        text(axCam, 160, 140, reason, 'Color', [1 0.8 0.4], 'FontSize', 10, ...
            'HorizontalAlignment', 'center', 'Interpreter', 'none');
        title(axCam, 'Simulated camera', 'Color', 'k');
    end

    function plotWave(x, info)
        x = x(:);
        t = (0:numel(x)-1) / cfg.fs;
        plot(axWave, t, x, 'Color', [0 0.35 0.75]);
        if isfield(info, 'ok') && info.ok
            xline(axWave, t(info.startIdx), 'r--', 'speech start');
            xline(axWave, t(info.endIdx), 'r--', 'speech end');
        end
        xlabel(axWave, 'Time t = n / f_s  (s)');
        ylabel(axWave, 'Amplitude x[n]');
        title(axWave, sprintf('Time-domain waveform  (f_s = %d Hz, %d samples)', cfg.fs, numel(x)));
        xlim(axWave, [0 max(t(end), 1/cfg.fs)]);
        grid(axWave, 'on');
        drawnow;
    end

    function plotSpectrum(y)
        N = numel(y);
        Y = fft(y);
        half = floor(N / 2) + 1;
        A = abs(Y(1:half)) / N;
        A(2:end) = 2 * A(2:end);                     % single-sided amplitude
        f = (0:half-1)' * cfg.fs / N;                % f_k = k fs / N
        plot(axSpec, f, 20 * log10(A + 1e-12), 'Color', [0.75 0.3 0]);
        [~, iPk] = max(A(2:end));
        xlim(axSpec, [0 cfg.fs / 2]);
        xlabel(axSpec, 'Frequency f = k f_s / N  (Hz)');
        ylabel(axSpec, '|X(f)|  (dB)');
        title(axSpec, sprintf('FFT magnitude spectrum  (N = %d, \\Delta f = %.2f Hz, strongest at %.0f Hz)', ...
            N, cfg.fs / N, f(iPk + 1)));
        grid(axSpec, 'on');
    end

    function plotSpectrogram(y)
        F = ss_mfcc(y, cfg.fs, cfg);
        S = 10 * log10(F.P + 1e-12);
        imagesc(axSgram, F.t, F.f, S);
        axis(axSgram, 'xy');
        mx = max(S(:));
        set(axSgram, 'CLim', [mx - 80, mx]);
        colormap(axSgram, parula);
        xlabel(axSgram, 'Time (s)');
        ylabel(axSgram, 'Frequency (Hz)');
        title(axSgram, 'Spectrogram (STFT: 25 ms Hamming frames, 10 ms hop)');
    end

    function resetPlots(keepWave)
        if nargin < 1 || ~keepWave
            cla(axWave);
            title(axWave, 'Time-domain waveform');
            xlabel(axWave, 'Time (s)');  ylabel(axWave, 'Amplitude');
        end
        cla(axSpec);
        title(axSpec, 'FFT magnitude spectrum');
        xlabel(axSpec, 'Frequency (Hz)');  ylabel(axSpec, 'Magnitude (dB)');
        cla(axSgram);
        title(axSgram, 'Spectrogram');
        xlabel(axSgram, 'Time (s)');  ylabel(axSgram, 'Frequency (Hz)');
    end

    function writeLog(testFile, res)
        isNew = ~exist(cfg.logFile, 'file');
        fid = fopen(cfg.logFile, 'a');
        if fid < 0, return; end
        if isNew
            fprintf(fid, 'time,file,speaker_score,speaker_threshold,speaker_accepted,command,command_accepted,camera_triggered\r\n');
        end
        [~, nm, ext] = fileparts(testFile);
        fprintf(fid, '%s,%s,%.4f,%.4f,%d,%s,%d,%d\r\n', ...
            char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), [nm ext], ...
            res.speakerScore, res.speakerThr, res.speakerAccepted, res.command, ...
            res.commandAccepted, res.trigger);
        fclose(fid);
    end

    function file = nextFreeName(folder, cmd)
        k = 1;
        file = fullfile(folder, sprintf('%s_%02d.wav', cmd, k));
        while exist(file, 'file')
            k = k + 1;
            file = fullfile(folder, sprintf('%s_%02d.wav', cmd, k));
        end
    end

    function runSafely(fn)
        % Disable buttons while working, and always re-enable them afterwards.
        if busy || ~ishandle(fig), return; end
        busy = true;
        set(buttons, 'Enable', 'off');
        try
            fn();
        catch ME
            logMsg('Error: %s', ME.message);
            if ishandle(fig)
                errordlg(sprintf('Something went wrong:\n\n%s', ME.message), 'Error');
            end
        end
        busy = false;
        if ishandle(fig)
            set(buttons, 'Enable', 'on');
        end
    end

    function b = makeButton(pos, str, color, cb)
        b = uicontrol(fig, 'Style', 'pushbutton', 'Units', 'normalized', 'Position', pos, ...
            'String', str, 'FontSize', 11, 'FontWeight', 'bold', ...
            'BackgroundColor', color, 'Callback', cb);
    end

    function setPrompt(str, color)
        if nargin < 2, color = [0 0 0]; end
        if ~ishandle(promptBox), return; end
        set(promptBox, 'String', str, 'ForegroundColor', color);
        drawnow;
    end

    function logMsg(varargin)
        msg = sprintf(varargin{:});
        if ~ishandle(statusBox), fprintf('%s\n', msg); return; end
        s = get(statusBox, 'String');
        if ischar(s), s = cellstr(s); end
        s{end+1} = [char(datetime('now', 'Format', 'HH:mm:ss')) '  ' msg];
        set(statusBox, 'String', s, 'Value', [], 'ListboxTop', numel(s));
        drawnow;
    end
end

function txt = micHelpText(err)
txt = sprintf(['MATLAB could not record from the microphone.\n\n', ...
    'MATLAB ONLINE:\n', ...
    '- Use Google Chrome (audio recording in MATLAB Online is supported in Chrome).\n', ...
    '- Click "Allow" when Chrome asks for microphone access. If you blocked it,\n', ...
    '  click the icon left of the address bar > Site settings > Microphone > Allow,\n', ...
    '  then reload MATLAB Online.\n', ...
    '- Windows must also allow Chrome to use the microphone (see below).\n\n', ...
    'DESKTOP MATLAB / WINDOWS - please check:\n', ...
    '1. A microphone is connected / the laptop microphone is enabled.\n', ...
    '2. Windows Settings > Privacy & security > Microphone:\n', ...
    '   "Microphone access" ON and "Let desktop apps access your microphone" ON.\n', ...
    '3. Windows Settings > System > Sound > Input: the correct device is selected\n', ...
    '   and the input volume is not muted.\n', ...
    '4. No other program (Zoom, Teams, ...) is using the microphone exclusively.\n', ...
    '5. Restart MATLAB (or reload the browser tab) after changing these settings.\n\n', ...
    'Technical details: %s'], err);
end
