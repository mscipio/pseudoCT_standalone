function manifest = pseudo_CT_profile_registry(name, repo_root)
%PSEUDO_CT_PROFILE_REGISTRY Return a validated canonical profile manifest.
%   MANIFEST = PSEUDO_CT_PROFILE_REGISTRY(NAME, REPO_ROOT) builds the
%   deterministic manifest for one of the three canonical profiles:
%       'local-current'              - r6313 + vers/, Yes/Yes
%       'local-near-parity-r2010b'   - r4667/R2010b, No/No (internal)
%       'launchpad'                  - remote r4667/MCR7.11, No/No
%
%   The manifest owns every behavior-changing field: SPM tree/version,
%   exact vers/ override set/order, atlas assets, PCA backend order,
%   runtime guard, normalization resource, recentering, background,
%   bone/FWHM/aliasing policy, cleanup policy, Launchpad identity, and
%   provenance expectations. The SPM root and expected revision are loaded
%   from the fixed deployment template for the selected profile. Environment
%   variables are not consulted.
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

switch lower(name)
    case 'local-current'
        manifest = build_local_current(repo_root);
    case 'local-near-parity-r2010b'
        manifest = build_near_parity(repo_root);
    case 'launchpad'
        manifest = build_launchpad(repo_root);
    otherwise
        error(ids.PROFILE.InvalidName, 'Unknown profile name: %s', name);
end

manifest = attach_spm_config(manifest, name, repo_root);
manifest = validate_manifest(manifest, ids);

end

%% ------------------------------------------------------------------------
function manifest = attach_spm_config(manifest, profile_name, repo_root)

config = pseudo_CT_load_spm_profile_config(profile_name, ...
    fullfile(repo_root, 'src', 'config'));
manifest.spm_root = config.spm_root;
manifest.spm_version = config.expected_revision;
manifest.spm_expected_revision = config.expected_revision;
manifest.spm_config_path = config.config_path;
manifest.spm_config_dir = config.config_dir;
manifest.spm_root_base = config.spm_root_base;
end

%% ------------------------------------------------------------------------
function manifest = build_local_current(repo_root)

manifest = new_manifest('local-current', repo_root);
manifest.vers_policy.order = {'spm_vol_nifti.m'; 'spm_preproc_write8.m'; 'spm_dicom_convert.m'};
manifest.pca_order         = {'callable_pca'; 'repo_legacy'};
manifest.runtime_guard     = 'supported_matlab';
manifest.recenter          = 'No';
manifest.zero_background   = 'Yes';
manifest.cleanup_policy    = 'remove_on_success';
manifest.normalization_resource.child_lib_path = '/autofs/cluster/matlab/current/sys/os/glnxa64';
manifest.provenance.expected_spm_version = 'r6313';
manifest.provenance.record_path = fullfile(repo_root, 'spm8-r6313', 'INVENTORY.json');

end

%% ------------------------------------------------------------------------
function manifest = build_near_parity(repo_root)

manifest = new_manifest('local-near-parity-r2010b', repo_root);
manifest.vers_policy.order = {'spm_vol_nifti.m'; 'spm_preproc_write8.m'; 'spm_dicom_convert.m'};
manifest.pca_order         = {'repo_legacy'; 'callable_pca'};
manifest.runtime_guard     = 'r2010b_only';
manifest.recenter          = 'No';
manifest.zero_background   = 'No';
manifest.cleanup_policy    = 'remove_on_success';
manifest.provenance.expected_spm_version = 'r4667';
manifest.provenance.record_path = fullfile(repo_root, 'spm8-r4667', 'INVENTORY.json');

end

%% ------------------------------------------------------------------------
function manifest = build_launchpad(repo_root)

manifest = new_manifest('launchpad', repo_root);
manifest.vers_policy.order = {'spm_vol_nifti.m'; 'spm_preproc_write8.m'; 'spm_dicom_convert.m'};
manifest.pca_order         = {'remote'};
manifest.runtime_guard     = 'launchpad_opaque';
manifest.recenter          = 'No';
manifest.zero_background   = 'No';
manifest.cleanup_policy    = 'remove_on_success';
manifest.provenance.expected_spm_version = 'r6313';
manifest.provenance.record_path = fullfile(repo_root, 'spm8-r6313', 'INVENTORY.json');

manifest.launchpad_identity.host          = '172.27.25.134';
manifest.launchpad_identity.runner        = fullfile('/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad', 'run_Pseudo_CT_launchpad.sh');
manifest.launchpad_identity.mcr_root      = '/usr/pubsw/common/matlab/7.11/';
manifest.launchpad_identity.batch_templates = fullfile('/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad', 'Batch_atlas');
manifest.launchpad_identity.defaults_mat  = fullfile('/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad', 'default_pseudo_CT_package_deployed.mat');
manifest.launchpad_identity.backend_mat   = fullfile('/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad', 'Pseudo_CT_launchpad');
manifest.launchpad_identity.queue         = 'p60';
manifest.launchpad_identity.scratch       = '/cluster/scratch/monday/';
manifest.launchpad_identity.backend_spm_version = 'r4667';
manifest.launchpad_identity.backend_runtime = 'MCR7.11';
manifest.launchpad_identity.backend_provenance_record_path = fullfile(repo_root, 'spm8-r4667', 'INVENTORY.json');

end

%% ------------------------------------------------------------------------
function manifest = new_manifest(name, repo_root)

manifest = struct();
manifest.name                = name;
manifest.spm_root            = '';
manifest.spm_version         = '';
manifest.vers_path           = fullfile(repo_root, 'vers');
manifest.vers_policy         = struct('order', {{}}, 'required', true);
manifest.atlas_assets        = struct();
manifest.atlas_assets.batch_atlas_path = fullfile(repo_root, 'Batch_atlas');
manifest.atlas_assets.required_files = { ...
    'TPM.nii'; ...
    'ch2.nii'; ...
    'Template_0.nii'; 'Template_1.nii'; 'Template_2.nii'; ...
    'Template_3.nii'; 'Template_4.nii'; 'Template_5.nii'; 'Template_6.nii'; ...
    fullfile('ganymed-ssh2-build250', 'ganymed-ssh2-build250.jar') ...
    };
manifest.pca_order           = {};
manifest.runtime_guard       = '';
manifest.normalization_resource = struct();
manifest.normalization_resource.source_command = sprintf('source %s', fullfile(repo_root, 'src', 'config', 'fs_setenv_530_from_launchpad.sh'));
manifest.normalization_resource.child_lib_path = '';
manifest.recenter            = 'No';
manifest.zero_background       = 'No';
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
