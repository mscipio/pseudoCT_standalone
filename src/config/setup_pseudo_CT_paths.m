function setup_pseudo_CT_paths(root_dir, manifest)
%SETUP_PSEUDO_CT_PATHS Add profile-owned pseudo-CT dependencies to the path.

if nargin < 2 || isempty(manifest)
    manifest = pseudo_CT_resolve_profile('local-current', root_dir);
end

% Validate before addpath or any other workflow mutation.
manifest = pseudo_CT_preflight(manifest, root_dir);
[spm_dir, spm_label] = pseudo_CT_resolve_spm_root(root_dir, manifest);

addpath(root_dir, '-begin');
if exist(fullfile(root_dir, 'src'), 'dir') == 7
    addpath(genpath(fullfile(root_dir, 'src')), '-begin');
end

addpath(genpath(spm_dir), '-begin');
% Ensure main SPM matlabbatch/ is first on path — prevents WFU toolbox
% (spm8-dan/toolbox/.../matlabbatch/) from shadowing cfg_getfile and
% other core SPM functions with incompatible versions.
addpath(fullfile(spm_dir, 'matlabbatch'), '-begin');

if exist(fullfile(root_dir, 'imgaussian'), 'dir') == 7
    addpath(genpath(fullfile(root_dir, 'imgaussian')), '-begin');
end
if exist(fullfile(root_dir, 'ssh2_v2_m1_r5'), 'dir') == 7
    addpath(genpath(fullfile(root_dir, 'ssh2_v2_m1_r5')), '-begin');
end
addpath(manifest.vers_path, '-begin');
clear spm_vol_nifti spm_preproc_write8 spm_dicom_convert
rehash;

expected = manifest.vers_policy.order;
for ii = 1:length(expected)
    actual = which(expected{ii}(1:end-2));
    expected_path = fullfile(manifest.vers_path, expected{ii});
    if ~strcmp(actual, expected_path)
        error('VERS:WrongOrder', ...
            'Override %s is not first on the MATLAB path: %s', expected{ii}, actual);
    end
end
end
