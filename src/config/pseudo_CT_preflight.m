function manifest = pseudo_CT_preflight(manifest, repo_root)
%PSEUDO_CT_PREFLIGHT Validate manifest, resources, and runtime before mutation.
%   MANIFEST = PSEUDO_CT_PREFLIGHT(MANIFEST, REPO_ROOT) enforces the
%   ordering contract: profile/alias/manifest/runtime/resource/provenance
%   validation completes before any filesystem, DICOM, network, subprocess,
%   or output mutation. Raises deterministic PROFILE/SPM_ROOT/VERS/ATLAS/
%   PCA/NORMALIZATION/PROVENANCE/ALIAS error IDs.
%
%   REPO_ROOT is used to anchor relative atlas/vers paths when the manifest
%   does not already contain absolute paths. It defaults to the repository
%   root inferred from this file's location.
%
%   This PR1 foundation validates structure and presence. Full provenance
%   checksum enforcement is wired in pseudo_CT_provenance_record and will
%   become hard once r6313/r4667 records land in the vendor phase.
%
%   Minimum supported MATLAB: R2010b.

ids = pseudo_CT_error_ids();

if nargin < 2 || isempty(repo_root)
    config_dir = fileparts(mfilename('fullpath'));
    repo_root = fileparts(fileparts(config_dir));
end

if exist(repo_root, 'dir') ~= 7
    error(ids.PROFILE.InvalidValue, 'repo_root does not exist: %s', repo_root);
end

validate_manifest_structure(manifest, ids);
validate_alias(manifest, ids);
validate_runtime(manifest, ids);
validate_spm_root(manifest, ids);
validate_vers(manifest, ids);
validate_atlas(manifest, ids);
validate_normalization(manifest, ids);
validate_pca(manifest, ids);
validate_provenance(manifest, ids);

end

%% ------------------------------------------------------------------------
function validate_alias(manifest, ids)

if ~isfield(manifest, 'aliasing_default') || ~isfield(manifest, 'aliasing_override')
    error(ids.ALIAS.InvalidOverride, 'Alias policy missing from manifest.');
end

if ~isnumeric(manifest.aliasing_default) || ~isscalar(manifest.aliasing_default) || ...
   ~ismember(manifest.aliasing_default, [0 1])
    error(ids.ALIAS.InvalidOverride, 'aliasing_default must be 0 or 1.');
end

if ~isnumeric(manifest.aliasing_override) || isempty(manifest.aliasing_override) || ...
   ~all(ismember(manifest.aliasing_override, [0 1]))
    error(ids.ALIAS.InvalidOverride, 'aliasing_override must be a non-empty subset of [0 1].');
end

end

%% ------------------------------------------------------------------------
function validate_runtime(manifest, ids)

if strcmpi(manifest.runtime_guard, 'r2010b_only')
    rel = version('-release');
    if ~strcmp(rel, '2010b')
        error(ids.PROFILE.R2010bOnly, ...
              'Profile %s requires MATLAB R2010b (7.11); running %s.', ...
              manifest.name, rel);
    end
end

end

%% ------------------------------------------------------------------------
function validate_spm_root(manifest, ids)

if isempty(manifest.spm_root)
    error(ids.SPM_ROOT.NotFound, 'SPM root is empty in profile %s.', manifest.name);
end

if exist(manifest.spm_root, 'dir') ~= 7
    error(ids.SPM_ROOT.NotFound, 'SPM root not found: %s', manifest.spm_root);
end

end

%% ------------------------------------------------------------------------
function validate_vers(manifest, ids)

if ~manifest.vers_policy.required
    return;
end

expected = {'spm_vol_nifti.m'; 'spm_preproc_write8.m'; 'spm_dicom_convert.m'};
if length(manifest.vers_policy.order) ~= length(expected)
    error(ids.VERS.Incomplete, 'vers_policy.order length mismatch.');
end

for ii = 1:length(expected)
    if ~ischar(manifest.vers_policy.order{ii}) || ...
       ~strcmp(manifest.vers_policy.order{ii}, expected{ii})
        error(ids.VERS.WrongOrder, ...
              'vers_policy.order(%d) expected %s, got %s', ...
              ii, expected{ii}, char(manifest.vers_policy.order{ii}));
    end
end

if ~isfield(manifest, 'vers_path') || isempty(manifest.vers_path)
    error(ids.VERS.Incomplete, 'vers_path missing from manifest.');
end

vers_dir = manifest.vers_path;
for ii = 1:length(expected)
    f = fullfile(vers_dir, expected{ii});
    if exist(f, 'file') ~= 2
        error(ids.VERS.Incomplete, 'vers override missing: %s', f);
    end
end

end

%% ------------------------------------------------------------------------
function validate_atlas(manifest, ids)

if ~isfield(manifest, 'atlas_assets') || ~isfield(manifest.atlas_assets, 'batch_atlas_path')
    error(ids.ATLAS.AssetMissing, 'Atlas assets missing from manifest.');
end

atlas_dir = manifest.atlas_assets.batch_atlas_path;
if isempty(atlas_dir)
    error(ids.ATLAS.AssetMissing, 'Atlas directory is empty.');
end

if exist(atlas_dir, 'dir') ~= 7
    error(ids.ATLAS.AssetMissing, 'Atlas directory not found: %s', atlas_dir);
end

required = manifest.atlas_assets.required_files;
for ii = 1:length(required)
    f = fullfile(atlas_dir, required{ii});
    if exist(f, 'file') ~= 2
        error(ids.ATLAS.AssetMissing, 'Required atlas asset missing: %s', f);
    end
end

end

%% ------------------------------------------------------------------------
function validate_normalization(manifest, ids)

if ~isfield(manifest, 'normalization_resource') || ...
   ~isfield(manifest.normalization_resource, 'source_command')
    error(ids.NORMALIZATION.SourceCommandMissing, ...
          'normalization_resource.source_command missing.');
end

cmd = manifest.normalization_resource.source_command;
if ~ischar(cmd) || isempty(cmd)
    error(ids.NORMALIZATION.SourceCommandMissing, ...
          'normalization_resource.source_command is empty.');
end

bad_chars = sprintf(';|&$`<>*?[]{}\\()\r\n\t');
for ii = 1:length(bad_chars)
    if ~isempty(strfind(cmd, bad_chars(ii)))
        error(ids.NORMALIZATION.ShellMetachar, ...
              'normalization source_command contains shell metacharacter: %c', bad_chars(ii));
    end
end

end

%% ------------------------------------------------------------------------
function validate_pca(manifest, ids)

if ~isfield(manifest, 'pca_order') || isempty(manifest.pca_order)
    error(ids.PCA.BackendUnavailable, 'PCA backend order missing from manifest.');
end

valid_backends = {'callable_pca', 'repo_legacy', 'remote'};
for ii = 1:length(manifest.pca_order)
    if ~ischar(manifest.pca_order{ii}) || ...
       ~ismember(manifest.pca_order{ii}, valid_backends)
        error(ids.PCA.BackendUnavailable, ...
              'Invalid PCA backend: %s', char(manifest.pca_order{ii}));
    end
end

end

%% ------------------------------------------------------------------------
function validate_provenance(manifest, ids)

if ~isfield(manifest, 'provenance') || ~isfield(manifest.provenance, 'record_path')
    error(ids.PROFILE.MissingManifestField, 'provenance.record_path missing.');
end

if ~isfield(manifest.provenance, 'expected_spm_version') || ...
   isempty(manifest.provenance.expected_spm_version)
    error(ids.PROVENANCE.RecordMissing, 'provenance.expected_spm_version missing.');
end

if ~strcmpi(manifest.provenance.expected_spm_version, manifest.spm_version)
    error(ids.PROVENANCE.ChecksumMismatch, ...
          'Provenance expected_spm_version %s does not match manifest spm_version %s.', ...
          manifest.provenance.expected_spm_version, manifest.spm_version);
end

% PR1 foundation: do not require the physical record file to exist for
% local-current or launchpad. The helper pseudo_CT_provenance_record is
% fail-closed when called directly; full enforcement arrives with r6313/r4667
% records in the vendor phase.

end

%% ------------------------------------------------------------------------
function validate_manifest_structure(manifest, ids)

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
    error(ids.PROFILE.InvalidValue, 'Invalid recenter value: %s', manifest.recenter);
end
if ~ismember(manifest.zero_background, valid_background)
    error(ids.PROFILE.InvalidValue, 'Invalid zero_background value: %s', manifest.zero_background);
end
if ~ismember(manifest.cleanup_policy, valid_cleanup)
    error(ids.PROFILE.InvalidValue, 'Invalid cleanup_policy value: %s', manifest.cleanup_policy);
end
if ~ismember(manifest.runtime_guard, valid_runtime)
    error(ids.PROFILE.InvalidValue, 'Invalid runtime_guard value: %s', manifest.runtime_guard);
end

if ~islogical(manifest.bone_enabled) || ~isscalar(manifest.bone_enabled)
    error(ids.PROFILE.InvalidValue, 'bone_enabled must be a scalar logical.');
end
if ~manifest.bone_enabled
    error(ids.BONE.CleanupFixed, 'Bone reduction must remain enabled; manifest disabled it.');
end
if ~isnumeric(manifest.fwhm) || ~isscalar(manifest.fwhm) || manifest.fwhm < 0
    error(ids.PROFILE.InvalidValue, 'fwhm must be a non-negative scalar.');
end

end
