function feat = ss_features(y, fs, cfg)
%SS_FEATURES  Features for the two separate recognisers.
%   feat.spk : MFCC c1..c12 of the louder frames  -> speaker verification
%              (order of frames ignored: describes HOW the voice sounds)
%   feat.cmd : MFCC c1..c12 of all frames, cepstral mean removed
%              -> command recognition (order of frames matters: WHAT is said)
%   c0 (overall loudness) is dropped so that speaking volume does not matter.
F = ss_mfcc(ss_preEmphasis(y, cfg.preEmph), fs, cfg);
C = F.C(2:cfg.nCep, :);

keep = F.logE > max(F.logE) - cfg.speechFrameDb;
feat.spk = C(:, keep);
feat.cmd = C - mean(C, 2);   % cepstral mean normalisation (removes mic colour)
end
