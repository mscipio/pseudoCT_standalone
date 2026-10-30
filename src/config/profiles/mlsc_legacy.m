function config = mlsc_legacy()
%MLSC_LEGACY Historical MLSC profile using the legacy v2.0 compiled implementation.

dependency_paths = pseudo_CT_dependency_paths();

% Select the local processing path or the remote MLSC path.
config.mode = 'mlsc';
% Implementation lineage: 'current' selects the compiled current payload;
% 'legacy-v2' selects the historical compiled Aether backend.
config.implementation = 'legacy-v2';
% SPM installation used by local finalization support code.
config.spm_root = dependency_paths.spm_root;
% Atlas images and SPM batch templates used by local finalization.
config.atlas_root = dependency_paths.atlas_root;
% Standalone DICOM-to-NIfTI converter (sibling repository).
config.d2n_root = dependency_paths.d2n_root;
% Standalone nose/back aliasing correction (external standalone app).
config.aliasing_root = dependency_paths.aliasing_root;
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
config.presentation.display_name = 'Aether - MLSC';
config.presentation.description = ...
    'Run the original v2 pipeline on MLSC for comparison with older studies.';
config.presentation.group = 'specialized';
config.presentation.recommended = false;
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
config.mlsc.runner = dependency_paths.legacy_runner;
% MATLAB Compiler Runtime root used by the compiled backend.
config.mlsc.mcr_root = '/usr/pubsw/common/matlab/7.11/';
% Defaults MAT file passed to the compiled backend.
config.mlsc.defaults_mat = dependency_paths.legacy_defaults;
% Atlas and SPM batch templates passed to the compiled backend.
config.mlsc.batch_templates = dependency_paths.legacy_batch_templates;
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

% Immutable legacy compiled facts (neutral contract shared with the local
% legacy profile). These mirror the orchestration block values above for
% runner, mcr_root, defaults_mat, and batch_templates plus the required
% attenuation-map filename. No host, Slurm, partition, nodes, tasks,
% memory, time, or shell-orchestration values are carried here.
% Unchanged compiled runner script.
config.legacy.runner = dependency_paths.legacy_runner;
% MATLAB Compiler Runtime root used by the compiled backend.
config.legacy.mcr_root = '/usr/pubsw/common/matlab/7.11/';
% Defaults MAT file passed to the compiled backend.
config.legacy.defaults_mat = dependency_paths.legacy_defaults;
% Atlas and SPM batch templates passed to the compiled backend.
config.legacy.batch_templates = dependency_paths.legacy_batch_templates;
% Required attenuation-map filename produced by the compiled backend.
config.legacy.att_map = 'att_map.nii';
end
