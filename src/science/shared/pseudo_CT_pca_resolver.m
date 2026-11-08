function [pca_fn, backend_name] = pseudo_CT_pca_resolver(config, varargin)
%PSEUDO_CT_PCA_RESOLVER Select the first available configured PCA backend.
%   [PCA_FN, BACKEND_NAME] = PSEUDO_CT_PCA_RESOLVER(CONFIG) walks
%   CONFIG.pca_order in order and returns the first usable backend:
%     'callable_pca' - MATLAB pca when present (PCA_FN wraps it, falling back
%                      to repo_legacy inside the call if pca fails)
%     'repo_legacy'  - pseudo_CT_princomp_legacy
%   'remote' errors with pseudo_CT:PCAUnavailable, and unknown names error
%   with pseudo_CT:InvalidProfile. If no entry is available, it errors with
%   pseudo_CT:PCAUnavailable.
%   [PCA_FN, BACKEND_NAME] = PSEUDO_CT_PCA_RESOLVER(CONFIG, OUTPUT_CONTEXT)
%   also passes OUTPUT_CONTEXT (optional logging struct) for the fallback
%   warning. Minimum supported MATLAB: R2010b.

if nargin < 1 || ~isstruct(config) || ~isfield(config, 'pca_order')
    error('pseudo_CT:InvalidProfile', 'A profile config with pca_order is required.');
end
output_context = struct();
if ~isempty(varargin) && isstruct(varargin{1})
    output_context = varargin{1};
end

for ii = 1:length(config.pca_order)
    backend = config.pca_order{ii};
    switch backend
        case 'callable_pca'
            if exist('pca', 'file') == 2
                pca_fn = @(X) pca_svd_wrapper(X, output_context);
                backend_name = backend;
                return;
            end
        case 'repo_legacy'
            if exist('pseudo_CT_princomp_legacy', 'file') == 2
                pca_fn = @pseudo_CT_princomp_legacy;
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

function [coef, score, latent] = pca_svd_wrapper(X, output_context)
X = double(X);
if exist('pca', 'file') ~= 2 || size(X, 1) < 2
    [coef, score, latent] = pseudo_CT_princomp_legacy(X);
    return;
end
try
    [coef, score, latent] = pca(X, 'Algorithm', 'svd', 'Economy', false);
catch ME
    % Legacy output: fprintf(1, 'callable_pca failed (%s); using repo_legacy.\n', ME.message);
    pseudo_CT_output('WARN', output_context, ...
        'Configured PCA backend failed; using repo_legacy: %s', ME.message);
    [coef, score, latent] = pseudo_CT_princomp_legacy(X);
end
end
