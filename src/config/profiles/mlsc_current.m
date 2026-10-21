function config = mlsc_current()
%MLSC_CURRENT Recommended remote/cluster profile using the current implementation.
%   T005 canonical cell (T014 authoritative): mode='mlsc',
%   implementation='current'. Current science settings match local_current
%   (alias=1, recenter='Yes', zero_background='No', bone=true, fwhm=0,
%   PCA callable_pca then repo_legacy, standard mMR/UMAP/NIfTI-and-DICOM
%   policy). config.current carries the neutral pinned artifact contract
%   (runner, pinned MCR_ROOT /usr/pubsw/common/matlab/26.1, build_manifest,
%   resource_manifest, required_outputs); config.mlsc carries
%   scheduler/host/shell/FreeSurfer fields only.
%
%   Artifact references resolve relative to the installed pseudoCT
%   version directory derived from this profile's own location at load
%   time (single coherent installation layout, no second layout).
%   The v3.0.1 distribution includes the previously finalized Gate-A record
%   with its unchanged certified artifact. Source-only checkouts without the
%   packaged artifacts/evidence fail closed at preflight. No catalog, no resolver, no
%   latest/current-label authority, no MCR 7.11 fallback, no
%   submitting-MATLAB substitute. No config.legacy and no legacy payload
%   fields inside config.mlsc.

% Select the local processing path or the remote MLSC path.
config.mode = 'mlsc';
% Implementation lineage: 'current' is source MATLAB, 'legacy-v2' is the
% compiled Aether backend.
config.implementation = 'current';
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
% Current PCA implementations to try in order (matches local-current).
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
config.presentation.display_name = 'MLSC - Current';
config.presentation.description = 'Run the full MPRAGE + UMAP workflow on the MLSC cluster using the current MATLAB source.';
config.presentation.group = 'recommended';
config.presentation.recommended = true;
config.presentation.order = 15;

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

% MLSC scheduler/host/shell/FreeSurfer fields only. No legacy payload
% fields (runner/mcr_root/defaults_mat/batch_templates) are carried here;
% a fake legacy contract must neither satisfy nor be required for current.
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

% Neutral current artifact contract (T004/T014): the referenced immutable
% artifact plus its machine-readable manifests. Defaults resolve relative
% to the installed pseudoCT version directory derived from this profile's
% own location at load time: this file lives in
% <version>/source/src/config/profiles/, so the version directory is four
% levels up and the staged artifact layout keeps the launcher under
% <version>/compiled/payload_build/ with the build/resource manifests at
% <version>/compiled/. There is no absolute deployment pin and no silent
% fallback: absent bundled files fail closed at missing-file validation.
% The explicit mlsc_current_artifact_root / mlsc_current_gate_a_record
% overrides win over these defaults. MCR_ROOT stays pinned below. The
% resolved shared Runtime path belongs only to transient execution
% context, never to this profile (no runtime_root field). Pending Gate A
% the referenced files do not exist and execution fails closed; nothing
% here fabricates Gate-A evidence or weakens validation.
% Installation-relative Gate-A artifact directory (staged layout).
profiles_dir_here = fileparts(mfilename('fullpath'));
version_dir_here = fileparts(fileparts(fileparts(fileparts(profiles_dir_here))));
artifact_dir_here = fullfile(version_dir_here, 'compiled');
% Launcher of the referenced artifact.
config.current.runner = fullfile(artifact_dir_here, 'payload_build', ...
    'run_mlsc_current_payload.sh');
% Pinned version-specific MCR_ROOT (never the current symlink).
config.current.mcr_root = '/usr/pubsw/common/matlab/26.1';
% Immutable build manifest describing the referenced artifact.
config.current.build_manifest = fullfile(artifact_dir_here, ...
    'mlsc_current_build.mat');
% Resource manifest describing the referenced artifact resources.
config.current.resource_manifest = fullfile(artifact_dir_here, ...
    'mlsc_current_resources.mat');
% Required outputs described by the referenced artifact contract.
config.current.required_outputs = {'att_map.nii'; ...
    'Fusion_MR_Pseudo_CT_validation.tiff'; 'Pseudo_CT_AC_Version.txt'};
% Gate-A record: separate immutable file binding this exact candidate
% (minted after a human-authorized Gate-A run; absent until then).
% Pending now, so execution fails closed at validate_for_execution.
% Default path is installation-relative like the manifests above.
config.current.gate_a_record = fullfile(artifact_dir_here, ...
    'mlsc_current_gate_a.mat');
end
