function D = ss_sqdist(A, B)
%SS_SQDIST  Squared Euclidean distances between the columns of A and B.
%   A is d x n, B is d x m, D is n x m.
D = sum(A.^2, 1)' + sum(B.^2, 1) - 2 * (A' * B);
D = max(D, 0);
end
