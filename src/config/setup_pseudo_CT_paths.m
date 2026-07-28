function setup_pseudo_CT_paths(root_dir, config)
%SETUP_PSEUDO_CT_PATHS Check resources and add pseudo-CT dependencies.

if nargin < 2 || ~isstruct(config)
    error('pseudo_CT:InvalidProfile', 'A loaded profile config is required.');
end
if exist(config.spm_root, 'dir') ~= 7
    error('pseudo_CT:SPMRootMissing', ...
        'Configured SPM root not found: %s', config.spm_root);
end
if exist(config.atlas_root, 'dir') ~= 7
    error('pseudo_CT:AtlasRootMissing', ...
        'Configured atlas root not found: %s', config.atlas_root);
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
end

vers_path = fullfile(root_dir, 'vers');
overrides = {'spm_vol_nifti.m'; 'spm_preproc_write8.m'; ...
    'spm_dicom_convert.m'};
for ii = 1:length(overrides)
    if exist(fullfile(vers_path, overrides{ii}), 'file') ~= 2
        error('pseudo_CT:MissingResource', ...
            'Required SPM override not found: %s', ...
            fullfile(vers_path, overrides{ii}));
    end
end

addpath(root_dir, '-begin');
if exist(fullfile(root_dir, 'src'), 'dir') == 7
    addpath(genpath(fullfile(root_dir, 'src')), '-begin');
end

addpath(genpath(config.spm_root), '-begin');
% Ensure main SPM matlabbatch/ is first on path - prevents WFU toolbox
% (spm8-dan/toolbox/.../matlabbatch/) from shadowing cfg_getfile and
% other core SPM functions with incompatible versions.
addpath(fullfile(config.spm_root, 'matlabbatch'), '-begin');

if exist(fullfile(root_dir, 'imgaussian'), 'dir') == 7
    addpath(genpath(fullfile(root_dir, 'imgaussian')), '-begin');
end
if exist(fullfile(root_dir, 'ssh2_v2_m1_r5'), 'dir') == 7
    addpath(genpath(fullfile(root_dir, 'ssh2_v2_m1_r5')), '-begin');
end
addpath(vers_path, '-begin');
clear spm_vol_nifti spm_preproc_write8 spm_dicom_convert
rehash;

for ii = 1:length(overrides)
    actual = which(overrides{ii}(1:end-2));
    expected_path = fullfile(vers_path, overrides{ii});
    if ~strcmp(actual, expected_path)
        error('VERS:WrongOrder', ...
            'Override %s is not first on the MATLAB path: %s', ...
            overrides{ii}, actual);
    end
end
end
