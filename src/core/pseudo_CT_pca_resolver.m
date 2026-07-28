function [pca_fn, backend_name] = pseudo_CT_pca_resolver(config)
%PSEUDO_CT_PCA_RESOLVER Select the first available configured PCA backend.

if nargin < 1 || ~isstruct(config) || ~isfield(config, 'pca_order')
    error('pseudo_CT:InvalidProfile', 'A profile config with pca_order is required.');
end

for ii = 1:length(config.pca_order)
    backend = config.pca_order{ii};
    switch backend
        case 'callable_pca'
            if exist('pca', 'file') == 2
                pca_fn = @pca_svd_wrapper;
                backend_name = backend;
                return;
            end
        case 'repo_legacy'
            if exist('pseudo_ct_princomp_legacy', 'file') == 2
                pca_fn = @pseudo_ct_princomp_legacy;
                backend_name = backend;
                return;
            end
        case 'remote'
            error('pseudo_CT:PCAUnavailable', ...
                'The selected profile delegates PCA to the remote backend.');
        otherwise
            error('pseudo_CT:InvalidProfile', ...
                'Unknown PCA backend: %s', char(backend));
    end
end

error('pseudo_CT:PCAUnavailable', 'No configured PCA backend is available.');
end

function [coef, score, latent] = pca_svd_wrapper(X)
X = double(X);
if exist('pca', 'file') ~= 2 || size(X, 1) < 2
    [coef, score, latent] = pseudo_ct_princomp_legacy(X);
    return;
end
try
    [coef, score, latent] = pca(X, 'Algorithm', 'svd', 'Economy', false);
catch ME
    fprintf(1, 'callable_pca failed (%s); using repo_legacy.\n', ME.message);
    [coef, score, latent] = pseudo_ct_princomp_legacy(X);
end
end
