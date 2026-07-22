function [spm_dir, spm_label] = pseudo_CT_compute_spm_root(manifest, root_dir)
%PSEUDO_CT_COMPUTE_SPM_ROOT Resolve the SPM root owned by a manifest.
%   Environment variables are intentionally not consulted. A missing
%   profile-owned tree raises SPM_ROOT:NotFound before workflow mutation.

ids = pseudo_CT_error_ids();
if nargin < 2 || isempty(root_dir)
    config_dir = fileparts(mfilename('fullpath'));
    root_dir = fileparts(fileparts(config_dir));
end

if ischar(manifest)
    manifest = pseudo_CT_resolve_profile(manifest, root_dir);
end
if ~isstruct(manifest) || ~isfield(manifest, 'spm_root')
    error(ids.SPM_ROOT.NotFound, 'Profile manifest does not define an SPM root.');
end

spm_dir = manifest.spm_root;
if isempty(spm_dir)
    error(ids.SPM_ROOT.NotFound, 'SPM root is empty in profile %s.', manifest_name(manifest));
end
if ~is_absolute(spm_dir)
    spm_dir = fullfile(root_dir, spm_dir);
end
if exist(spm_dir, 'dir') ~= 7
    error(ids.SPM_ROOT.NotFound, 'SPM root not found: %s', spm_dir);
end

spm_label = sprintf('%s (%s)', spm_dir, manifest_name(manifest));
end

function name = manifest_name(manifest)
if isfield(manifest, 'name') && ischar(manifest.name)
    name = manifest.name;
else
    name = 'profile';
end
end

function result = is_absolute(path_name)
result = ~isempty(path_name) && (path_name(1) == filesep || ...
    (length(path_name) > 1 && path_name(2) == ':'));
end
