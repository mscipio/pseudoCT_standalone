function config = mlsc()
%MLSC MLSC profile: Slurm submission to MLSC by pseudoct_job_manager, which runs pseudoct_pipeline once per subject.
%   CONFIG = MLSC() returns the canonical 'mlsc' profile struct. Its science
%   settings match LOCAL (alias 1, recenter 'Yes', zero background 'No', bone
%   on, fwhm 0, PCA callable_pca then repo_legacy, mMR policy, NIfTI and DICOM
%   output). config.mlsc holds the host, shell, FreeSurfer and Slurm fields
%   (partition basic, 1 node, 1 task, 4 CPUs, 8G memory, 02:00:00 time limit).
%   config.current holds the compiled artifact contract: runner, mcr_root (the
%   MATLAB 7.11 installation root), build_manifest, resource_manifest and
%   required_outputs. The required MCR release is 7.14; it is not inferred
%   from mcr_root.
%
%   Artifact fields are placeholders here; the installed Runtime selection
%   supplies them. A source checkout has no installed artifact and fails closed
%   before any application run unless an explicit development artifact root is
%   given. There is no mutable alias or current-label lookup, and no submitting-
%   MATLAB substitute. config.mlsc contains no artifact fields.
%   Minimum supported MATLAB: R2010b (MATLAB 7.11). This file only declares
%   values; mlsc_preflight and the MLSC backend perform validation and submission.

dependency_paths = pseudo_CT_dependency_paths();

% Select the local processing path or the remote MLSC path.
config.mode = 'mlsc';
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
% PCA implementations to try in order (matches local).
config.pca_order = {'callable_pca'; 'repo_legacy'};
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
config.presentation.display_name = 'MLSC';
config.presentation.description = ...
    'Run the pseudoCT pipeline on MLSC using the same compiled pseudoct_pipeline.';
config.presentation.group = 'specialized';
config.presentation.recommended = true;
config.presentation.order = 15;

% FreeSurfer environment used inside the remote batch shell.
config.normalization.source_command = 'source /usr/local/freesurfer/nmr-stable53-env';
% Runtime library directory for the FreeSurfer child process; empty means no prepend.
config.normalization.child_lib_path = '';
% Host that runs MLSC processing and FreeSurfer normalization.
config.normalization.host = 'mlsc.nmr.mgh.harvard.edu';
% Use Slurm submission for normalization: 'Yes' or 'No'.
config.normalization.cluster = 'Yes';
% Shared subject temporary directories are used by the MLSC backend.
config.normalization.host_folder = '';

% MLSC scheduler/host/shell/FreeSurfer fields only. Artifact fields
% (runner/mcr_root/build_manifest/...) live in config.current, never here.
% MLSC SSH host.
config.mlsc.host = 'mlsc.nmr.mgh.harvard.edu';
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

% Neutral current artifact contract: the referenced immutable artifact and its
% machine-readable manifests. No compiled tree is assumed. The placeholders below
% are not files. Installed runtime selection replaces the runner and MATLAB
% Runtime root and clears build_manifest and resource_manifest (direct mode),
% identifying the runner by SHA-256 instead. A source checkout refuses application
% runs unless an explicit development artifact root is supplied
% (mlsc_current_artifact_root). There is no absolute pin and no silent fallback.
% MATLAB_ROOT stays pinned below; the required MCR release stays separately
% pinned at 7.14. The resolved shared Runtime path belongs only to transient
% execution context, never to this profile (no runtime_root field).
% Launcher of the referenced artifact (placeholder until runtime selection).
config.current.runner = 'runtime-selection-required';
% MATLAB R2010b/compiler installation root (never infer MCR from this path).
config.current.mcr_root = '/usr/pubsw/common/matlab/7.11';
% Immutable build manifest (placeholder until runtime selection clears it).
config.current.build_manifest = 'runtime-selection-required';
% Resource manifest (placeholder until runtime selection clears it).
config.current.resource_manifest = 'runtime-selection-required';
% Required outputs described by the referenced artifact contract.
config.current.required_outputs = {'att_map.nii'; ...
    'Fusion_MR_Pseudo_CT_validation.tiff'; 'Pseudo_CT_AC_Version.txt'};
end
