function setup_pseudo_CT_paths(root_dir, config, purpose, has_inputs, needs_dicom)
%SETUP_PSEUDO_CT_PATHS Add orchestration runtime paths and needed resources.
%   The current scientific implementation is compiled and is deliberately
%   not added to the MATLAB source path. Converter resources are checked/added
%   for runs or when validation includes a resolved input.
%   Source mode checks and adds the physical trees. Installed mode performs no
%   path or rehash operation; it checks packaged resources (atlas) and, for
%   run/preflight only, the compiled capabilities (dicom2nifti, SPM, SPM
%   overrides) by name. Installed validation skips those capabilities.
%   Minimum supported MATLAB: R2010b.

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

layout = pseudo_CT_package_layout();
installed = strcmp(layout.mode, 'installed');
% Installed distributions: the converter, SPM and SPM override code is compiled
% into the science payload (run_mlsc_current_payload), not into the headless
% standalone that runs this setup. Checking those names here fails on the
% standalone's own function table, so installed mode skips them for every
% purpose. The payload's build manifest and runner checksum are validated by
% the artifact check and the payload fails closed if its code is missing.
execution_only = installed;
needs_converter = (strcmp(purpose, 'run') || has_inputs) && ~execution_only;
% Any resolved input can be submitted through the same run setup, which
% conservatively requires SPM even when the input itself is NIfTI.
needs_spm = (strcmp(purpose, 'run') || has_inputs || needs_dicom) && ~execution_only;
needs_science_resources = strcmp(purpose, 'run') || has_inputs;
if needs_science_resources && exist(config.atlas_root, 'dir') ~= 7
    error('pseudo_CT:AtlasRootMissing', ...
        'Configured atlas root not found: %s', config.atlas_root);
end
if needs_converter
    if installed
        % Installed: the converter is a compiled capability. Its top-level
        % entrypoint must be callable; +dicom2nifti/+api/run is proven by the
        % build-time dependency closure, not by a runtime file lookup.
        local_require_capability({'dcm2nii'}, 'pseudo_CT:D2NEntrypointMissing', ...
            'Pinned dicom2nifti 1.2.5 compiled entrypoint is missing');
    else
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
end
if needs_spm
    if installed
        local_require_capability({'spm_vol'}, 'pseudo_CT:SPMRootMissing', ...
            'Compiled SPM capability is missing');
    elseif exist(config.spm_root, 'dir') ~= 7
        error('pseudo_CT:SPMRootMissing', ...
            'Configured SPM root not found: %s', config.spm_root);
    end
end
if strcmp(config.mode, 'mlsc')
    local_validate_current_setup(config);
    if strcmp(purpose, 'run')
        mlsc_files = {config.mlsc.shell; config.mlsc.freesurfer_env};
    else
        mlsc_files = {};
    end
    for ii = 1:length(mlsc_files)
        if exist(mlsc_files{ii}, 'file') ~= 2
            error('pseudo_CT:MissingResource', ...
                'Configured MLSC file not found: %s', mlsc_files{ii});
        end
    end
end

overrides_path = fullfile(root_dir, 'src', 'science', 'overrides');
overrides = {'spm_vol_nifti.m'; 'spm_preproc_write8.m'; ...
    'spm_dicom_convert.m'};
if needs_spm
    if installed
        for ii = 1:length(overrides)
            local_require_capability({overrides{ii}(1:end-2)}, 'pseudo_CT:MissingResource', ...
                'Required compiled SPM override not found');
        end
    else
        for ii = 1:length(overrides)
            if exist(fullfile(overrides_path, overrides{ii}), 'file') ~= 2
                error('pseudo_CT:MissingResource', ...
                    'Required SPM override not found: %s', ...
                    fullfile(overrides_path, overrides{ii}));
            end
        end
    end
end

if ~installed
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
end
if strcmp(config.mode, 'mlsc') && ...
        ~strcmp(purpose, 'validate')
    ssh2_root = fullfile(root_dir, 'external', 'ssh2_v2_m1_r5');
    if exist(ssh2_root, 'dir') ~= 7
        error('pseudo_CT:SSH2RootMissing', ...
            'Bundled SSH2 client source is missing: %s', ssh2_root);
    end
    addpath(genpath(ssh2_root), '-begin');
end
if ~installed
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
end

function local_require_capability(names, identifier, message)
%LOCAL_REQUIRE_CAPABILITY Fail closed unless each compiled name is callable.
for ii = 1:length(names)
    if exist(names{ii}, 'file') ~= 2
        error(identifier, '%s: %s', message, names{ii});
    end
end
end

function local_validate_current_setup(config)
%LOCAL_VALIDATE_CURRENT_SETUP Validate current artifact strings for setup.
%   Requires the neutral config.current artifact strings. Artifact-file
%   existence is checked by preflight and the execution validator. R2010b only.
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
end
