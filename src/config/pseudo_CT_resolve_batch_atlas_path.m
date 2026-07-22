function batch_atlas_path = pseudo_CT_resolve_batch_atlas_path(repo_root, manifest)
%PSEUDO_CT_RESOLVE_BATCH_ATLAS_PATH Resolve the manifest-owned atlas.
%   Environment variables, defaults, and packaged fallbacks cannot replace
%   the selected profile resource.

ids = pseudo_CT_error_ids();
if nargin == 1 && isstruct(repo_root)
    manifest = repo_root;
    repo_root = fileparts(manifest.spm_root);
elseif nargin < 1 || isempty(repo_root)
    config_dir = fileparts(mfilename('fullpath'));
    repo_root = fileparts(fileparts(config_dir));
end
if nargin < 2 || isempty(manifest)
    manifest = pseudo_CT_resolve_profile('local-current', repo_root);
end
if ~isfield(manifest, 'atlas_assets') || ...
        ~isfield(manifest.atlas_assets, 'batch_atlas_path') || ...
        ~isfield(manifest.atlas_assets, 'required_files')
    error(ids.ATLAS.AssetMissing, 'Profile manifest has no Batch_atlas path.');
end

batch_atlas_path = manifest.atlas_assets.batch_atlas_path;
if isempty(batch_atlas_path)
    error(ids.ATLAS.AssetMissing, 'Profile Batch_atlas path is empty.');
end
if ~is_absolute(batch_atlas_path)
    batch_atlas_path = fullfile(repo_root, batch_atlas_path);
end
if exist(batch_atlas_path, 'dir') ~= 7
    error(ids.ATLAS.AssetMissing, 'Batch_atlas not found: %s', batch_atlas_path);
end

required = manifest.atlas_assets.required_files;
for ii = 1:length(required)
    resource = fullfile(batch_atlas_path, required{ii});
    if exist(resource, 'file') ~= 2
        error(ids.ATLAS.AssetMissing, 'Required atlas asset missing: %s', resource);
    end
end
end

function result = is_absolute(path_name)
result = ~isempty(path_name) && (path_name(1) == filesep || ...
    (length(path_name) > 1 && path_name(2) == ':'));
end
