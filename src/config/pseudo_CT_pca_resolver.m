function [pca_fn, backend_name, provenance] = pseudo_CT_pca_resolver(manifest)
%PSEUDO_CT_PCA_RESOLVER Resolve a manifest-owned PCA backend.
%   [PCA_FN, BACKEND_NAME, PROVENANCE] = PSEUDO_CT_PCA_RESOLVER(MANIFEST)
%   selects the first available PCA backend from the manifest's pca_order,
%   returning a function handle PCA_FN with the legacy-compatible signature
%   [COEF, SCORE, LATENT] = PCA_FN(X).
%
%   Profile matrix:
%       local-current              -> callable_pca, then repo_legacy
%       local-near-parity-r2010b   -> repo_legacy, then callable_pca
%       launchpad                  -> remote (no local implementation)
%
%   Native MATLAB princomp is never used as the sole implementation.
%   PSEUDOCT_USE_PRINCOMP is ignored and logged.
%
%   When MANIFEST is omitted, the local-current profile is used so that
%   legacy callers retain deterministic behavior without changing the
%   public entrypoint topology.
%
%   Minimum supported MATLAB: R2010b.

ids = pseudo_CT_error_ids();

provenance = struct();
provenance.ignored_env = '';
provenance.order = {};
provenance.selected = '';

env_val = getenv('PSEUDOCT_USE_PRINCOMP');
if ~isempty(env_val)
    provenance.ignored_env = ids.ENV_IGNORED.USE_PRINCOMP;
    fprintf(1, '[profile-resource-authority] ignored %s=%s\n', provenance.ignored_env, env_val);
end

if nargin < 1 || isempty(manifest)
    manifest = pseudo_CT_profile_registry('local-current');
end

order = manifest.pca_order;
provenance.order = order;

if isempty(order)
    error(ids.PCA.BackendUnavailable, 'PCA backend order is empty.');
end

valid_backends = {'callable_pca', 'repo_legacy', 'remote'};
for ii = 1:length(order)
    if ~ischar(order{ii}) || ~ismember(order{ii}, valid_backends)
        error(ids.PCA.BackendUnavailable, ...
              'Invalid PCA backend: %s', char(order{ii}));
    end
end

for ii = 1:length(order)
    backend = order{ii};
    switch backend
        case 'callable_pca'
            if exist('pca', 'file') == 2
                pca_fn = @pca_svd_wrapper;
                backend_name = 'callable_pca';
                provenance.selected = backend_name;
                return;
            end
        case 'repo_legacy'
            if exist('pseudo_ct_princomp_legacy', 'file') == 2
                pca_fn = @pseudo_ct_princomp_legacy;
                backend_name = 'repo_legacy';
                provenance.selected = backend_name;
                return;
            end
        case 'remote'
            error(ids.PCA.BackendUnavailable, ...
                  'Remote PCA is not available locally.');
    end
end

error(ids.PCA.BackendUnavailable, ...
      'No PCA backend available in order: %s', join_backends(order));

end

%% ------------------------------------------------------------------------
function [coef, score, latent] = pca_svd_wrapper(X)
% Wrapper around modern pca(...) with legacy-compatible signature.
% R2010b does not expose pca(...), so this path is only taken on runtimes
% that have it. The wrapper catches a failing/stub princomp and falls back
% to the repo-local legacy helper.

X = double(X);

if exist('pca', 'file') ~= 2
    [coef, score, latent] = pseudo_ct_princomp_legacy(X);
    return;
end

if size(X, 1) < 2
    [coef, score, latent] = pseudo_ct_princomp_legacy(X);
    return;
end

try
    [coef, score, latent] = pca(X, 'Algorithm', 'svd', 'Economy', false);
catch ME
    fprintf(1, 'callable_pca path failed (%s); falling back to repo_legacy.\n', ME.message);
    [coef, score, latent] = pseudo_ct_princomp_legacy(X);
end

end

%% ------------------------------------------------------------------------
function str = join_backends(order)

str = '';
for ii = 1:length(order)
    if ii > 1
        str = [str, ', '];  %#ok<AGROW>
    end
    str = [str, char(order{ii})];  %#ok<AGROW>
end

end
