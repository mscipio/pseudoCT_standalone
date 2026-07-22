function [spm_dir, spm_label] = pseudo_CT_resolve_spm_root(root_dir, manifest)
%PSEUDO_CT_RESOLVE_SPM_ROOT Resolve the SPM tree from a profile manifest.
%   The optional MANIFEST argument is authoritative. With only ROOT_DIR the
%   fixed local-current profile is used for backward-compatible callers.

if nargin == 1 && isstruct(root_dir)
    manifest = root_dir;
    if is_absolute(manifest.spm_root)
        root_dir = fileparts(manifest.spm_root);
    else
        config_dir = fileparts(mfilename('fullpath'));
        root_dir = fileparts(fileparts(config_dir));
    end
elseif nargin < 1 || isempty(root_dir)
    config_dir = fileparts(mfilename('fullpath'));
    root_dir = fileparts(fileparts(config_dir));
end

if nargin < 2 || isempty(manifest)
    manifest = pseudo_CT_resolve_profile('local-current', root_dir);
end

[spm_dir, spm_label] = pseudo_CT_compute_spm_root(manifest, root_dir);
end

function result = is_absolute(path_name)
result = ~isempty(path_name) && (path_name(1) == filesep || ...
    (length(path_name) > 1 && path_name(2) == ':'));
end
