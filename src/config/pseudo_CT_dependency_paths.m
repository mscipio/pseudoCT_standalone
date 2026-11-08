function paths = pseudo_CT_dependency_paths()
%PSEUDO_CT_DEPENDENCY_PATHS Resolve versioned local artifacts from install root.
%   Paths mirror dependencies.lock.json and are based on this function's
%   location, never caller pwd or a mutable site-wide "latest" alias.
%   Installed packages ship no external/ or src/ trees: in installed mode the
%   spm_root, d2n_root, aliasing_root and overrides_root strings identify
%   compiled capabilities and are not existence requirements for validation
%   (see setup_pseudo_CT_paths). atlas_root is packaged. No compiled artifact
%   tree is assumed: the runner and manifests of an application run come from the
%   installed Runtime selection (pseudo_CT_runtime_select) or, for development
%   only, from an explicit artifact root.
%   Minimum supported MATLAB: R2010b.

layout = pseudo_CT_package_layout();
install_root = layout.root;
paths = struct();
paths.install_root = install_root;
paths.spm_root = fullfile(install_root, 'external', 'spm8-r6313');
paths.atlas_root = fullfile(install_root, 'external', 'Batch_atlas');
% Installed distribution ships the atlas under <package>/resources. Source mode
% keeps external/Batch_atlas above. The string is absolute with no trailing
% slash.
if strcmp(layout.mode, 'installed')
    paths.atlas_root = fullfile(install_root, 'resources');
end
paths.d2n_root = fullfile(install_root, 'external', 'dicom2nifti-1.2.5');
paths.aliasing_root = fullfile(install_root, 'external', ...
    'correct_aliasing-0.4.0');
paths.overrides_root = fullfile(install_root, 'src', 'science', 'overrides');
paths.ssh2_root = fullfile(install_root, 'external', 'ssh2_v2_m1_r5');
end
