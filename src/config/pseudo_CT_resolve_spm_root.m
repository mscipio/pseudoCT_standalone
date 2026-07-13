function [spm_dir, spm_label] = pseudo_CT_resolve_spm_root(root_dir)
%PSEUDO_CT_RESOLVE_SPM_ROOT Resolve the SPM tree directory from env vars.
%   [SPM_DIR, SPM_LABEL] = PSEUDO_CT_RESOLVE_SPM_ROOT(ROOT_DIR) resolves
%   the SPM tree to use for the pseudo-CT pipeline.
%
%   Resolution order:
%     1. PSEUDOCT_SPM_ROOT env var — absolute or relative path (highest precedence)
%     2. PSEUDOCT_SPM_VARIANT env var — short suffix resolved as spm8-{variant} under ROOT_DIR
%     3. Default: spm8-r6313 under ROOT_DIR
%
%   SPM_LABEL is a human-readable string for diagnostics.
%
%   Example:
%       setenv('PSEUDOCT_SPM_VARIANT', 'dan');
%       [spm_dir, spm_label] = pseudo_CT_resolve_spm_root('/path/to/repo');
%       % spm_dir  = '/path/to/repo/spm8-dan'
%       % spm_label = 'spm8-dan (env:PSEUDOCT_SPM_VARIANT)'
%
%   See also SETUP_PSEUDO_CT_PATHS.

    spm_root_env = getenv('PSEUDOCT_SPM_ROOT');
    spm_variant  = getenv('PSEUDOCT_SPM_VARIANT');

    if ~isempty(spm_root_env)
        spm_dir = spm_root_env;
        spm_label = sprintf('%s (env:PSEUDOCT_SPM_ROOT)', spm_root_env);
    elseif ~isempty(spm_variant)
        spm_dir = fullfile(root_dir, ['spm8-' spm_variant]);
        spm_label = sprintf('spm8-%s (env:PSEUDOCT_SPM_VARIANT)', spm_variant);
    else
        spm_dir = fullfile(root_dir, 'spm8-r6313');
        spm_label = 'spm8-r6313 (default)';
    end
