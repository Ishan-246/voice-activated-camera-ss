function s = ss_speakerScore(X, sm)
%SS_SPEAKERSCORE  Average distance of each frame to its nearest codeword.
%   Lower score = the recording sounds more like the enrolled speaker.
Z = (X - sm.mu) ./ sm.sd;
s = mean(sqrt(min(ss_sqdist(Z, sm.CB), [], 2)));
end
