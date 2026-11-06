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
paths.atlas_root = fullfile(install_root, 'external', 'Batch_atlas');
paths.d2n_root = fullfile(install_root, 'external', 'dicom2nifti-1.2.5');
paths.aliasing_root = fullfile(install_root, 'external', ...
    'correct_aliasing-0.4.0');
paths.overrides_root = fullfile(install_root, 'src', 'science', 'overrides');
paths.ssh2_root = fullfile(install_root, 'external', 'ssh2_v2_m1_r5');
paths.current_root = fullfile(install_root, 'compiled', 'current');
end
