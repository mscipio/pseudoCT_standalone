function setup_pseudo_CT_paths(root_dir)
%SETUP_PSEUDO_CT_PATHS Add the pseudo-CT package dependencies to the MATLAB path.
%   SETUP_PSEUDO_CT_PATHS(ROOT_DIR) adds the standard toolboxes and
%   overrides needed by both the local and Launchpad entry points.
%   ROOT_DIR is the absolute path to the package root folder.

    addpath(root_dir, '-begin');
    if exist(fullfile(root_dir, 'src'), 'dir') == 7
        addpath(genpath(fullfile(root_dir, 'src')), '-begin');
    end

    [spm_dir, spm_label] = pseudo_CT_resolve_spm_root(root_dir);
    if exist(spm_dir, 'dir') ~= 7
        error('setup_pseudo_CT_paths:SPMNotFound', ...
              'SPM tree not found: %s\nSet PSEUDOCT_SPM_ROOT or PSEUDOCT_SPM_VARIANT to point to a valid SPM tree.', ...
              spm_dir);
    end
    disp(sprintf('pseudo-CT: SPM tree = %s', spm_label));
    addpath(genpath(spm_dir), '-begin');

    if exist(fullfile(root_dir, 'imgaussian'), 'dir') == 7
        addpath(genpath(fullfile(root_dir, 'imgaussian')), '-begin');
    end
    if exist(fullfile(root_dir, 'ssh2_v2_m1_r5'), 'dir') == 7
        addpath(genpath(fullfile(root_dir, 'ssh2_v2_m1_r5')), '-begin');
    end
    if exist(fullfile(root_dir, 'vers'), 'dir') == 7
        addpath(fullfile(root_dir, 'vers'), '-begin');
    end
    clear spm_vol_nifti spm_preproc_write8
    rehash;
