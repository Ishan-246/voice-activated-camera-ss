function ss_makeDirs(cfg)
%SS_MAKEDIRS  Create every data/results folder the project needs (if missing).
dirs = {cfg.dataDir, cfg.phraseDir, cfg.commandDir, cfg.otherDir, ...
        cfg.testDir, cfg.resultsDir, cfg.photoDir};
for k = 1:numel(dirs)
    if ~exist(dirs{k}, 'dir')
        mkdir(dirs{k});
    end
end
end
