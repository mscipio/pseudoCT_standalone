function config = mlsc()
%MLSC Recommended remote/cluster profile using the legacy compiled backend.

% Select the local processing path or the remote MLSC path.
config.mode = 'mlsc';
% SPM installation used by local finalization support code.
config.spm_root = '/usr/pubsw/packages/mrpet/standalone_apps/shared_libraries_2026/spm8-r6313';
% Atlas images and SPM batch templates used by local finalization.
config.atlas_root = '/usr/pubsw/packages/mrpet/standalone_apps/shared_libraries_2026/Batch_atlas';
% Standalone DICOM-to-NIfTI converter (sibling repository).
config.d2n_root = '/usr/pubsw/packages/mrpet/standalone_apps/dcm2nii/dicom2nifti_standalone-latest';
% Standalone nose/back aliasing correction (external standalone app).
config.aliasing_root = '/usr/pubsw/packages/mrpet/standalone_apps/correct_aliasing/correct_aliasing_standalone-latest';
% Recenter the MPRAGE before FreeSurfer normalization: 'Yes' or 'No'.
config.recenter_before_normalization = 'Yes';
% Set attenuation values outside the subject mask to zero: 'Yes' or 'No'.
config.zero_background = 'No';
% Remove temporary files after successful output promotion.
config.cleanup_on_success = true;
% PCA is performed by the remote compiled backend.
config.pca_order = {'remote'};
% Required local MATLAB release; empty accepts any release.
config.required_matlab_release = '';
% Apply bone cleanup when processing locally; remote processing owns its copy.
config.bone_enabled = true;
% Final attenuation-map Gaussian smoothing width in millimetres.
config.fwhm = 0;
% Default nose/back aliasing correction for batch and explicit subject lists.
config.aliasing_default = 1;
% Standard MPRAGE + UMAP reference collection.
config.io_policy.reference = 'umap-required';
% Standard NIfTI and DICOM output.
config.io_policy.output = 'nifti-and-dicom';
% Standard MPRAGE + UTE/UMAP UI.
config.io_policy.gui = 'mMR';
% Compatibility baseline: empty identifies the standard MLSC profile.
config.compatibility_profile = '';
% Human-facing selector metadata; runtime identity remains filename-derived.
config.presentation.display_name = 'MLSC (Legacy Compiled Backend)';
config.presentation.description = ...
    'Run the full MPRAGE + UMAP workflow on MLSC cluster using the legacy compiled backend.';
config.presentation.group = 'recommended';
config.presentation.recommended = true;
config.presentation.order = 30;

% FreeSurfer environment used inside the remote batch shell.
config.normalization.source_command = 'source /usr/local/freesurfer/nmr-stable53-env';
% Runtime library directory for the FreeSurfer child process.
config.normalization.child_lib_path = '/autofs/cluster/matlab/current/sys/os/glnxa64';
% Host that runs MLSC processing and FreeSurfer normalization.
config.normalization.host = 'mlsc.nmr.mgh.harvard.edu';
% Use Slurm submission for normalization: 'Yes' or 'No'.
config.normalization.cluster = 'Yes';
% Shared subject temporary directories are used by the MLSC backend.
config.normalization.host_folder = '';

% MLSC SSH host.
config.mlsc.host = 'mlsc.nmr.mgh.harvard.edu';
% Unchanged compiled runner script.
config.mlsc.runner = '/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad/run_Pseudo_CT_launchpad.sh';
% MATLAB Compiler Runtime root used by the compiled backend.
config.mlsc.mcr_root = '/usr/pubsw/common/matlab/7.11/';
% Defaults MAT file passed to the compiled backend.
config.mlsc.defaults_mat = '/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad/default_pseudo_CT_package_deployed.mat';
% Atlas and SPM batch templates passed to the compiled backend.
config.mlsc.batch_templates = '/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad/Batch_atlas';
% Explicit shell and FreeSurfer environment used by Slurm jobs.
config.mlsc.shell = '/bin/bash';
config.mlsc.freesurfer_env = '/usr/local/freesurfer/nmr-stable53-env';
% Verified Slurm resource defaults; run-specific selection is external to this profile.
config.mlsc.partition = 'basic';
config.mlsc.nodes = 1;
config.mlsc.ntasks = 1;
config.mlsc.cpus_per_task = 4;
config.mlsc.memory = '8G';
config.mlsc.time = '02:00:00';
end
