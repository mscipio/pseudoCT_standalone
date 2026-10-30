function setup_pseudo_CT_paths(root_dir, config, purpose, has_inputs, needs_dicom)
%SETUP_PSEUDO_CT_PATHS Add orchestration runtime paths and needed resources.
%   The current scientific implementation is compiled and is deliberately
%   not added to the MATLAB source path. Converter resources are checked/added
%   for runs or when validation includes a resolved input.

if nargin < 2 || ~isstruct(config)
    error('pseudo_CT:InvalidProfile', 'A loaded profile config is required.');
end
if nargin < 3 || isempty(purpose)
    purpose = 'run';
end
if nargin < 4 || isempty(has_inputs)
    has_inputs = true;
end
if nargin < 5 || isempty(needs_dicom)
    needs_dicom = true;
end
if ~ischar(purpose) || ~any(strcmp(purpose, ...
        {'run'; 'validate'; 'preflight'})) || ...
        ~islogical(has_inputs) || ~isscalar(has_inputs) || ...
        ~islogical(needs_dicom) || ~isscalar(needs_dicom)
    error('pseudo_CT:InvalidSetupPurpose', ...
        'Runtime setup purpose and input requirements are invalid.');
end

needs_converter = strcmp(purpose, 'run') || has_inputs;
% Any resolved input can be submitted through the same run setup, which
% conservatively requires SPM even when the input itself is NIfTI.
needs_spm = strcmp(purpose, 'run') || has_inputs || needs_dicom;
needs_science_resources = strcmp(purpose, 'run') || has_inputs;
if needs_science_resources && exist(config.atlas_root, 'dir') ~= 7
    error('pseudo_CT:AtlasRootMissing', ...
        'Configured atlas root not found: %s', config.atlas_root);
end
if needs_converter
    if exist(config.d2n_root, 'dir') ~= 7
        error('pseudo_CT:D2NRootMissing', ...
            'Configured dicom2nifti root not found: %s', config.d2n_root);
    end
    if exist(fullfile(config.d2n_root, 'dcm2nii.m'), 'file') ~= 2 || ...
            exist(fullfile(config.d2n_root, '+dicom2nifti', '+api', 'run.m'), 'file') ~= 2
        error('pseudo_CT:D2NEntrypointMissing', ...
            'Pinned dicom2nifti 1.2.5 entrypoints are missing under: %s', ...
            config.d2n_root);
    end
end
if needs_spm && exist(config.spm_root, 'dir') ~= 7
    error('pseudo_CT:SPMRootMissing', ...
        'Configured SPM root not found: %s', config.spm_root);
end
if isfield(config, 'implementation') && ...
        ischar(config.implementation) && strcmp(config.implementation, 'legacy-v2')
    local_validate_legacy_artifacts(config);
end
if strcmp(config.mode, 'launchpad')
    launchpad_files = {config.launchpad.runner; config.launchpad.defaults_mat};
    for ii = 1:length(launchpad_files)
        if exist(launchpad_files{ii}, 'file') ~= 2
            error('pseudo_CT:MissingResource', ...
                'Configured Launchpad file not found: %s', launchpad_files{ii});
        end
    end
    launchpad_dirs = {config.launchpad.mcr_root; ...
        config.launchpad.batch_templates};
    for ii = 1:length(launchpad_dirs)
        if exist(launchpad_dirs{ii}, 'dir') ~= 7
            error('pseudo_CT:MissingResource', ...
                'Configured Launchpad directory not found: %s', ...
                launchpad_dirs{ii});
        end
    end
elseif strcmp(config.mode, 'mlsc')
    is_current_setup = false;
    try
        is_current_setup = isfield(config, 'implementation') && ...
            ischar(config.implementation) && ...
            strcmp(config.implementation, 'current');
    catch %#ok<CTCH>
        is_current_setup = false;
    end
    if is_current_setup
        local_validate_current_setup(config);
        if strcmp(purpose, 'run')
            mlsc_files = {config.mlsc.shell; config.mlsc.freesurfer_env};
        else
            mlsc_files = {};
        end
    else
        if strcmp(purpose, 'run')
            mlsc_files = {config.mlsc.runner; config.mlsc.defaults_mat; ...
                config.mlsc.shell; config.mlsc.freesurfer_env};
        else
            mlsc_files = {};
        end
    end
    for ii = 1:length(mlsc_files)
        if exist(mlsc_files{ii}, 'file') ~= 2
            error('pseudo_CT:MissingResource', ...
                'Configured MLSC file not found: %s', mlsc_files{ii});
        end
    end
    if is_current_setup
        % Current artifact-file existence and integrity are checked by
        % preflight/validator; setup checks interpreted host dependencies.
    elseif strcmp(purpose, 'run')
        mlsc_dirs = {config.mlsc.mcr_root; config.mlsc.batch_templates};
        for ii = 1:length(mlsc_dirs)
            if exist(mlsc_dirs{ii}, 'dir') ~= 7
                error('pseudo_CT:MissingResource', ...
                    'Configured MLSC directory not found: %s', mlsc_dirs{ii});
            end
        end
    end
else
    % Local mode's external dependencies were validated above.
end

overrides_path = fullfile(root_dir, 'src', 'science', 'overrides');
overrides = {'spm_vol_nifti.m'; 'spm_preproc_write8.m'; ...
    'spm_dicom_convert.m'};
if needs_spm
    for ii = 1:length(overrides)
        if exist(fullfile(overrides_path, overrides{ii}), 'file') ~= 2
            error('pseudo_CT:MissingResource', ...
                'Required SPM override not found: %s', ...
                fullfile(overrides_path, overrides{ii}));
        end
    end
end

addpath(root_dir, '-begin');
runtime_dirs = {'api'; 'cli'; 'gui'; 'orchestration'; 'backends'; ...
    'config'; 'io'; 'qc'};
for ii = 1:length(runtime_dirs)
    runtime_path = fullfile(root_dir, 'src', runtime_dirs{ii});
    if exist(runtime_path, 'dir') == 7
        addpath(genpath(runtime_path), '-begin');
    end
end

if needs_spm
    addpath(genpath(config.spm_root), '-begin');
    % Keep main SPM matlabbatch/ ahead of toolbox copies.
    addpath(fullfile(config.spm_root, 'matlabbatch'), '-begin');
    % Preserve the historical pre-converter override selection. The pinned
    % DICOM API adds the configured SPM root at path-begin during conversion,
    % so its SPM8 spm_dicom_convert remains the effective converter function.
    addpath(overrides_path, '-begin');
end
if needs_converter
    addpath(config.d2n_root, '-begin');
end
if any(strcmp(config.mode, {'mlsc'; 'launchpad'})) && ...
        ~strcmp(purpose, 'validate')
    ssh2_root = fullfile(root_dir, 'external', 'ssh2_v2_m1_r5');
    if exist(ssh2_root, 'dir') ~= 7
        error('pseudo_CT:SSH2RootMissing', ...
            'Bundled SSH2 client source is missing: %s', ssh2_root);
    end
    addpath(genpath(ssh2_root), '-begin');
end
if needs_spm
    clear spm_vol_nifti spm_preproc_write8 spm_dicom_convert
end
rehash;

if needs_spm
    for ii = 1:length(overrides)
        actual = which(overrides{ii}(1:end-2));
        expected_path = fullfile(overrides_path, overrides{ii});
        if ~strcmp(actual, expected_path)
            error('pseudo_CT:OverrideWrongOrder', ...
                'Override %s is not first on the MATLAB path: %s', ...
                overrides{ii}, actual);
        end
    end
end
end

function local_validate_legacy_artifacts(config)
%LOCAL_VALIDATE_LEGACY_ARTIFACTS Never fall back to a site-installed runner.
if ~isfield(config, 'legacy') || ~isstruct(config.legacy) || ...
        numel(config.legacy) ~= 1
    error('pseudo_CT:LegacyDependencyMissing', ...
        'The legacy profile has no local compiled/legacy-v2.0.0 contract.');
end
required_files = {config.legacy.runner; config.legacy.defaults_mat};
for ii = 1:numel(required_files)
    if exist(required_files{ii}, 'file') ~= 2
        error('pseudo_CT:LegacyDependencyMissing', ...
            'Required local legacy-v2.0.0 file is missing: %s', ...
            required_files{ii});
    end
end
required_dirs = {config.legacy.mcr_root; config.legacy.batch_templates};
for ii = 1:numel(required_dirs)
    if exist(required_dirs{ii}, 'dir') ~= 7
        error('pseudo_CT:LegacyDependencyMissing', ...
            'Required legacy-v2.0.0 directory is missing: %s', ...
            required_dirs{ii});
    end
end
end

function local_validate_current_setup(config)
%LOCAL_VALIDATE_CURRENT_SETUP Validate current artifact strings for setup.
%   Requires the neutral config.current artifact strings and rejects any
%   legacy block/fields. Artifact-file existence is checked by preflight and
%   the execution validator. R2010b only.
if ~isfield(config, 'current') || ~isstruct(config.current) || ...
        numel(config.current) ~= 1
    error('pseudo_CT:InvalidProfile', ...
        'The MLSC current profile has no valid current artifact block.');
end
current_fields = {'runner'; 'mcr_root'; 'build_manifest'; ...
    'resource_manifest'};
for ii = 1:length(current_fields)
    value = config.current.(current_fields{ii});
    if ~ischar(value) || size(value, 1) ~= 1 || ...
            isempty(strtrim(value)) || any(value == char(0))
        error('pseudo_CT:InvalidProfile', ...
            'The MLSC current artifact block is invalid.');
    end
end
if isfield(config, 'legacy')
    error('pseudo_CT:InvalidProfile', ...
        'The MLSC current profile must not carry a legacy block.');
end
legacy_mlsc_fields = {'runner'; 'mcr_root'; 'defaults_mat'; ...
    'batch_templates'};
for ii = 1:length(legacy_mlsc_fields)
    if isfield(config.mlsc, legacy_mlsc_fields{ii})
        error('pseudo_CT:InvalidProfile', ...
            'The MLSC current profile must not carry legacy field %s.', ...
            legacy_mlsc_fields{ii});
    end
end
end
