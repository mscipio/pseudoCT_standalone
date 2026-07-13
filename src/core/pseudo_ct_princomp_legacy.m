function [coeff, score, latent] = pseudo_ct_princomp_legacy(X)
% Investigation tool — investigation-cleanup-release.
% PSEUDO_CT_PRINCOMP_LEGACY  Legacy-compatible PCA (princomp behavior).
%   [COEFF, SCORE, LATENT] = pseudo_ct_princomp_legacy(X) performs
%   principal components analysis on the N-by-P data matrix X, reproducing
%   the behavior of the old MATLAB princomp function (R2010b-era).
%
%   Rows of X correspond to observations, columns to variables.
%
%   COEFF is a P-by-P matrix of principal component coefficients
%   (loadings), each column in order of decreasing component variance.
%   SCORE is an N-by-P matrix of principal component scores.
%   LATENT is a P-by-1 vector of principal component variances (eigenvalues
%   of the covariance matrix).
%
%   The function:
%     - Centers X by subtracting column means (no rescaling)
%     - Uses SVD (full decomposition, matching old princomp default)
%     - Enforces the old princomp sign convention: the coefficient with the
%       largest absolute value in each column is made positive.
%
%   This helper is zero-dependency: no toolboxes, no Java, no MATLAB
%   version requirements beyond bsxfun.  It is the primary PCA path for
%   the pseudo-CT pipeline and replaces both the old princomp (removed
%   after R2012b) and MATLAB pca(...) when deterministic legacy behavior
%   is required.
%
%   See also: move_image_2_MNI, princomp (legacy), pca.

X = double(X);
[n, p] = size(X);

% Empty input: return identity for coeff, empty score, zero latent
if isempty(X)
    coeff = eye(p);
    score = zeros(n, p);
    latent = zeros(p, 1);
    return;
end

% Center X by subtracting off column means
mu = mean(X, 1);                                                 %#ok<NASGU>
X0 = bsxfun(@minus, X, mu);

% Single observation: no variance to explain
if n < 2
    coeff = eye(p);
    score = X0;
    latent = zeros(p, 1);
    return;
end

% --- SVD decomposition (matching old princomp default: full) ---
% For n > p, svd(X0,'econ') returns the same matrices as svd(X0,0)
% and the decompositions are identical.
% For n <= p, svd(X0,'econ') returns V as p×n (not p×p), which
% breaks the old princomp P×P coeff contract.  Use full svd(X0)
% for wide matrices to get the complete right-singular-vector basis.
if n <= p
    [U, S, coeff] = svd(X0);            % full SVD — V is P×P
    sigma = diag(S);                    % min(n,p)×1 = n×1
    sigma(n+1:p, 1) = 0;               % extend latent to P without overwriting
else
    [U, S, coeff] = svd(X0, 'econ');
    sigma = diag(S);
end

% When observations <= variables, pad score with zero columns and
% set non-signal latent entries to zero, matching old princomp default.
if n <= p
    % Only the first (n-1) columns of U carry signal after centering;
    % the last column corresponds to the zero singular value.
    score = bsxfun(@times, U(:,1:n-1), sigma(1:n-1)');
    score_extra = zeros(n, p - n + 1);
    score = [score, score_extra];                                  %#ok<AGROW>
else
    score = bsxfun(@times, U, sigma');
end

% Eigenvalues of the covariance matrix: sigma^2 / (n-1)
sigma = sigma ./ sqrt(n-1);
latent = sigma.^2;
% Old princomp explicitly zeros non-signal latent for wide matrices
if n <= p
    latent(n:p, 1) = 0;
end

% --- Sign convention from old princomp ---
% The coefficient with the largest absolute value in each column is
% made positive.  If it was negative, flip both coeff(:,j) and score(:,j).
% For wide matrices (n <= p), only the first d = min(n,p) columns carry
% signal; the zero-padded columns (d+1:P) are not sign-flipped.
[~, maxind] = max(abs(coeff), [], 1);
d = size(coeff, 2);
colsign = sign(coeff(maxind + (0:p:(d-1)*p)));
coeff = bsxfun(@times, coeff, colsign);
score(:,1:d) = bsxfun(@times, score(:,1:d), colsign);
