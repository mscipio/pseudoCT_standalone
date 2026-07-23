function manifest = pseudo_CT_profile_registry(name, repo_root)
%PSEUDO_CT_PROFILE_REGISTRY Return a validated canonical profile manifest.
%   MANIFEST = PSEUDO_CT_PROFILE_REGISTRY(NAME, REPO_ROOT) builds the
%   deterministic manifest for any profile NAME by loading its configuration
%   from the corresponding file in src/config/spm_profiles/.
%
%   The manifest owns every behavior-changing field: SPM tree/version,
%   exact vers/ override set/order, atlas assets, PCA backend order,
%   runtime guard, normalization resource, recentering, background,
%   bone/FWHM/aliasing policy, cleanup policy, Launchpad identity, and
%   provenance expectations. All pipeline parameters are loaded from the
%   profile config file; structural defaults (vers policy, atlas folder
%   scanning, normalization source command) are set by the registry.
%
%   REPO_ROOT defaults to the repository root inferred from this file's
%   location. An unset deployment root remains unset and is not replaced by
%   a repository-owned SPM tree.
%
%   Minimum supported MATLAB: R2010b.

if nargin < 2 || isempty(repo_root)
    config_dir = fileparts(mfilename('fullpath'));
    repo_root = fileparts(fileparts(config_dir));
end

ids = pseudo_CT_error_ids();

if ~ischar(name) || isempty(strtrim(name))
    error(ids.PROFILE.InvalidName, 'Profile name must be a non-empty string.');
end

name = strtrim(name);

% Load the full profile configuration from the profile config file.
config = pseudo_CT_load_spm_profile_config(name, ...
    fullfile(repo_root, 'src', 'config'));

% Build the manifest from the config plus structural defaults.
manifest = build_from_config(config, repo_root);

% Validate the complete manifest.
manifest = validate_manifest(manifest, ids);

end

%% ------------------------------------------------------------------------
function manifest = build_from_config(config, repo_root)
%BUILD_FROM_CONFIG Build a complete manifest from a profile config struct.

manifest = new_manifest(config.name, repo_root);

% --- Paths from config ---
manifest.spm_root = config.spm_root;
manifest.atlas_assets.batch_atlas_path = config.batch_atlas_path;

% --- Pipeline parameters from config ---
manifest.recenter        = config.recenter;
manifest.zero_background = config.zero_background;
manifest.cleanup_policy  = config.cleanup_policy;
manifest.bone_enabled    = config.bone_enabled;
manifest.fwhm            = config.fwhm;
manifest.aliasing_default = config.aliasing_default;
manifest.pca_order       = config.pca_order;
manifest.runtime_guard   = config.runtime_guard;

% --- Optional normalization child lib path ---
if isfield(config, 'normalization_child_lib_path') && ...
        ischar(config.normalization_child_lib_path)
    manifest.normalization_resource.child_lib_path = ...
        config.normalization_child_lib_path;
end

% --- Launchpad identity (only present in launchpad config) ---
if isfield(config, 'launchpad_host')
    manifest.launchpad_identity.host          = config.launchpad_host;
    manifest.launchpad_identity.runner        = config.launchpad_runner;
    manifest.launchpad_identity.mcr_root      = config.launchpad_mcr_root;
    manifest.launchpad_identity.defaults_mat  = config.launchpad_defaults_mat;
    manifest.launchpad_identity.backend_mat   = config.launchpad_backend_mat;
    manifest.launchpad_identity.batch_templates = config.launchpad_batch_templates;
    manifest.launchpad_identity.queue         = config.launchpad_queue;
    manifest.launchpad_identity.scratch       = config.launchpad_scratch;
    manifest.launchpad_identity.backend_spm_version = config.launchpad_backend_spm_version;
    manifest.launchpad_identity.backend_runtime = config.launchpad_backend_runtime;
    manifest.launchpad_identity.backend_provenance_record_path = '';
end

% --- SPM version is no longer enforced from config; detect from tree ---
% Leave spm_version and spm_expected_revision empty so preflight skips
% revision validation. The SPM tree at spm_root is used as-is.
manifest.spm_version         = '';
manifest.spm_expected_revision = '';

end

%% ------------------------------------------------------------------------
function manifest = new_manifest(name, repo_root)
%NEW_MANIFEST Create a new manifest struct with structural defaults.

manifest = struct();
manifest.name                = name;
manifest.spm_root            = '';
manifest.spm_version         = '';
manifest.vers_path           = fullfile(repo_root, 'vers');
manifest.vers_policy         = struct( ...
    'order', {{'spm_vol_nifti.m'; 'spm_preproc_write8.m'; 'spm_dicom_convert.m'}}, ...
    'required', true);
manifest.atlas_assets        = struct();
manifest.atlas_assets.batch_atlas_path = fullfile(repo_root, 'Batch_atlas');
manifest.pca_order           = {};
manifest.runtime_guard       = '';
manifest.normalization_resource = struct();
manifest.normalization_resource.source_command = sprintf('source %s', ...
    fullfile(repo_root, 'src', 'config', 'fs_setenv_530_from_launchpad.sh'));
manifest.normalization_resource.child_lib_path = '';
manifest.recenter            = 'No';
manifest.zero_background     = 'No';
manifest.bone_enabled        = true;
manifest.fwhm                = 0;
manifest.aliasing_default    = 1;
manifest.aliasing_override   = [0 1];
manifest.cleanup_policy      = 'remove_on_success';
manifest.launchpad_identity  = struct();
manifest.provenance          = struct();
manifest.provenance.source   = '';
manifest.provenance.license  = '';
manifest.provenance.tree_inventory = '';
manifest.provenance.file_count = 0;
manifest.provenance.bytes    = 0;
manifest.provenance.expected_spm_version = '';
manifest.provenance.sha256_map = struct();
manifest.provenance.record_path = '';

end

%% ------------------------------------------------------------------------
function manifest = validate_manifest(manifest, ids)
%VALIDATE_MANIFEST Validate manifest structure and field values.

required_top = { ...
    'name'; 'spm_root'; 'spm_version'; 'vers_path'; 'vers_policy'; ...
    'atlas_assets'; 'pca_order'; 'runtime_guard'; 'normalization_resource'; ...
    'recenter'; 'zero_background'; 'bone_enabled'; 'fwhm'; ...
    'aliasing_default'; 'aliasing_override'; 'cleanup_policy'; ...
    'launchpad_identity'; 'provenance' ...
    };

for ii = 1:length(required_top)
    if ~isfield(manifest, required_top{ii})
        error(ids.PROFILE.MissingManifestField, ...
              'Profile manifest missing required field: %s', required_top{ii});
    end
end

valid_recenter   = {'Yes', 'No'};
valid_background = {'Yes', 'No'};
valid_cleanup    = {'remove_on_success', 'keep_on_success'};
valid_runtime    = {'supported_matlab', 'r2010b_only', 'launchpad_opaque'};

if ~ismember(manifest.recenter, valid_recenter)
    error(ids.PROFILE.InvalidValue, ...
          'Invalid recenter value: %s', manifest.recenter);
end
if ~ismember(manifest.zero_background, valid_background)
    error(ids.PROFILE.InvalidValue, ...
          'Invalid zero_background value: %s', manifest.zero_background);
end
if ~ismember(manifest.cleanup_policy, valid_cleanup)
    error(ids.PROFILE.InvalidValue, ...
          'Invalid cleanup_policy value: %s', manifest.cleanup_policy);
end
if ~ismember(manifest.runtime_guard, valid_runtime)
    error(ids.PROFILE.InvalidValue, ...
          'Invalid runtime_guard value: %s', manifest.runtime_guard);
end

if ~islogical(manifest.bone_enabled) || ~isscalar(manifest.bone_enabled)
    error(ids.PROFILE.InvalidValue, 'bone_enabled must be a scalar logical.');
end
if ~isnumeric(manifest.fwhm) || ~isscalar(manifest.fwhm) || manifest.fwhm < 0
    error(ids.PROFILE.InvalidValue, 'fwhm must be a non-negative scalar.');
end
if ~isnumeric(manifest.aliasing_default) || ~isscalar(manifest.aliasing_default) || ...
   ~ismember(manifest.aliasing_default, [0 1])
    error(ids.PROFILE.InvalidValue, 'aliasing_default must be 0 or 1.');
end
if ~isnumeric(manifest.aliasing_override) || ~all(ismember(manifest.aliasing_override, [0 1]))
    error(ids.PROFILE.InvalidValue, 'aliasing_override must contain only 0 and 1.');
end

if ~isfield(manifest.vers_policy, 'order') || ~isfield(manifest.vers_policy, 'required')
    error(ids.PROFILE.MissingManifestField, ...
          'vers_policy missing order or required field.');
end

expected_vers = {'spm_vol_nifti.m'; 'spm_preproc_write8.m'; 'spm_dicom_convert.m'};
if length(manifest.vers_policy.order) ~= length(expected_vers)
    error(ids.VERS.WrongOrder, 'vers_policy.order has wrong length.');
end
for ii = 1:length(expected_vers)
    if ~ischar(manifest.vers_policy.order{ii}) || ...
       ~strcmp(manifest.vers_policy.order{ii}, expected_vers{ii})
        error(ids.VERS.WrongOrder, ...
              'vers_policy.order(%d) expected %s, got %s', ...
              ii, expected_vers{ii}, char(manifest.vers_policy.order{ii}));
    end
end

if ~isfield(manifest.normalization_resource, 'source_command')
    error(ids.PROFILE.MissingManifestField, ...
          'normalization_resource missing source_command.');
end

if ~isfield(manifest.provenance, 'expected_spm_version') || ...
   ~isfield(manifest.provenance, 'record_path')
    error(ids.PROFILE.MissingManifestField, ...
          'provenance missing expected_spm_version or record_path.');
end

end
