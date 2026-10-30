function paths = pseudo_CT_dependency_paths()
%PSEUDO_CT_DEPENDENCY_PATHS Resolve versioned local artifacts from install root.
%   Paths mirror dependencies.lock.json and are based on this function's
%   location, never caller pwd or a mutable site-wide "latest" alias.
%   Minimum supported MATLAB: R2010b.

config_dir = fileparts(mfilename('fullpath'));
install_root = fileparts(fileparts(config_dir));
paths = struct();
paths.install_root = install_root;
paths.spm_root = fullfile(install_root, 'external', 'spm8-r6313');
paths.spm8_dan_root = fullfile(install_root, 'external', 'spm8-dan');
paths.atlas_root = fullfile(install_root, 'external', 'Batch_atlas');
paths.d2n_root = fullfile(install_root, 'external', 'dicom2nifti-1.2.5');
paths.aliasing_root = fullfile(install_root, 'external', ...
    'correct_aliasing-0.4.0');
paths.overrides_root = fullfile(install_root, 'src', 'science', 'overrides');
paths.ssh2_root = fullfile(install_root, 'external', 'ssh2_v2_m1_r5');
paths.legacy_root = fullfile(install_root, 'compiled', ...
    'legacy-v2.0.0');
paths.legacy_runner = fullfile(paths.legacy_root, ...
    'run_Pseudo_CT_launchpad.sh');
paths.legacy_defaults = fullfile(paths.legacy_root, ...
    'default_pseudo_CT_package_deployed.mat');
paths.legacy_batch_templates = fullfile(paths.legacy_root, 'Batch_atlas');
paths.current_root = fullfile(install_root, 'compiled', 'current');
end
