function sm = ss_trainSpeaker(featCell, cfg)
%SS_TRAINSPEAKER  Build the speaker model from a cell array of feat.spk matrices.
%   sm.mu, sm.sd : per-coefficient mean / std (used to normalise features)
%   sm.CB        : VQ codebook of the normalised features
allX = [featCell{:}];
sm.mu = mean(allX, 2);
sm.sd = std(allX, 0, 2) + eps;
sm.CB = ss_vqTrain((allX - sm.mu) ./ sm.sd, cfg.vqSize, cfg.vqIters);
end
