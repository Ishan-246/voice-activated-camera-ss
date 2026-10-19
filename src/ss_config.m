function cfg = ss_config(rootDir)
%SS_CONFIG  All settings for the Voice-Activated Camera project in one place.
%   cfg = ss_config()         uses the project folder (parent of /src).
%   cfg = ss_config(rootDir)  uses another folder (used by the self-test).
%
%   Every path is built relative to the project folder, so the project
%   works on any computer without editing anything.

if nargin < 1 || isempty(rootDir)
    rootDir = fileparts(fileparts(mfilename('fullpath')));   % src -> project
end

%% Folders and files (created automatically by ss_makeDirs)
cfg.rootDir     = rootDir;
cfg.dataDir     = fullfile(rootDir, 'data');
cfg.phraseDir   = fullfile(cfg.dataDir, 'enroll_phrases');   % your free phrases
cfg.commandDir  = fullfile(cfg.dataDir, 'enroll_commands');  % your commands
cfg.otherDir    = fullfile(cfg.dataDir, 'other_speaker');    % another person
cfg.testDir     = fullfile(cfg.dataDir, 'test_recordings');  % every TEST press
cfg.modelFile   = fullfile(cfg.dataDir, 'voice_model.mat');
cfg.resultsDir  = fullfile(rootDir, 'results');
cfg.photoDir    = fullfile(cfg.resultsDir, 'photos');
cfg.logFile     = fullfile(cfg.resultsDir, 'test_log.csv');

%% Sampling (Unit 1: continuous speech -> discrete-time signal x[n])
cfg.fs    = 16000;   % sampling frequency in Hz (speech content < 8 kHz = fs/2)
cfg.nBits = 16;      % bits per sample (ignored by MATLAB Online)
% If the microphone does not accept 16 kHz (possible in MATLAB Online),
% these rates are tried instead and the audio is converted to cfg.fs.
cfg.fallbackFs = [48000, 44100];

%% Recording lengths (seconds)
cfg.phraseSec  = 3.0;
cfg.commandSec = 2.0;

%% Vocabulary
cfg.commands       = {'shoot', 'stop', 'zoom'};   % 'shoot' triggers, others do not
cfg.triggerCommand = 'shoot';
cfg.repsPerCommand = 4;      % your repetitions of each command at enrollment
cfg.otherReps      = 2;      % other speaker's repetitions of each command
cfg.phrases = { ...
    'The quick brown fox jumps over the lazy dog.', ...
    'Signals and systems is my favourite subject.', ...
    'Please take a picture of this beautiful view.', ...
    'One, two, three, four, five, six, seven, eight.'};

%% Recording validity checks (input sanity only, not recognition thresholds)
cfg.minPeak      = 0.005;  % peak amplitude below this = practically silent
cfg.minSnrDb     = 12;     % loudest frame must be this far above the noise floor
cfg.trimDb       = 30;     % keep frames within 30 dB of the loudest frame
cfg.minSpeechSec = 0.15;   % shorter than this = no real word spoken
cfg.padSec       = 0.05;   % extra margin kept around detected speech

%% Feature extraction (Units 2, 4, 6)
cfg.preEmph   = 0.97;   % y[n] = x[n] - 0.97 x[n-1]   ->  H(z) = 1 - 0.97 z^-1
cfg.frameSec  = 0.025;  % 25 ms frames (speech is roughly stationary here)
cfg.hopSec    = 0.010;  % 10 ms hop
cfg.nfft      = 512;    % FFT length (>= frame length of 400 samples)
cfg.nMel      = 26;     % number of mel band-pass filters (parallel filter bank)
cfg.nCep      = 13;     % cepstral coefficients c0..c12 (c0 = loudness, dropped)
cfg.melLowHz  = 50;
cfg.melHighHz = 7600;
cfg.speechFrameDb = 30; % speaker model uses frames within 30 dB of the loudest

%% Speaker model (vector-quantisation codebook)
cfg.vqSize  = 16;       % number of codewords
cfg.vqIters = 30;       % k-means iterations

cfg.modelVersion = 1;
end
