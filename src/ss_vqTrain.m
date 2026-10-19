function CB = ss_vqTrain(X, K, nIter)
%SS_VQTRAIN  Vector-quantisation codebook by k-means (base MATLAB only).
%   X is d x N feature vectors, CB is d x K codewords. Each codeword is the
%   average of one "typical sound" of the speaker's voice.
N = size(X, 2);
K = min(K, N);
CB = X(:, round(linspace(1, N, K)));        % deterministic initialisation
for it = 1:nIter
    Dm = ss_sqdist(X, CB);                  % N x K
    [dMin, a] = min(Dm, [], 2);
    for k = 1:K
        members = (a == k);
        if any(members)
            CB(:, k) = mean(X(:, members), 2);
        else
            [~, far] = max(dMin);           % empty cluster: restart it on the
            CB(:, k) = X(:, far);           % worst-represented vector
            dMin(far) = 0;
        end
    end
end
end
