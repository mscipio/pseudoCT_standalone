function config = local_legacy()
%LOCAL_LEGACY Local profile using the legacy v2.0 compiled implementation.
%   Direct-local execution of the legacy v2.0 compiled implementation
%   (Aether lineage) without any remote submission.

% Select the local processing path or the remote MLSC path.
config.mode = 'local';
% Implementation lineage: 'current' is source MATLAB, 'legacy-v2' is the
% compiled Aether backend.
config.implementation = 'legacy-v2';
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
% PCA is performed by the local compiled backend.
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
% Compatibility baseline: empty identifies the standard full-workflow profile.
config.compatibility_profile = '';
% Human-facing selector metadata; runtime identity remains filename-derived.
config.presentation.display_name = 'Aether - Local';
config.presentation.description = ...
    'Run the original v2 pipeline on this computer for comparison with older studies.';
config.presentation.group = 'specialized';
config.presentation.recommended = false;
config.presentation.order = 20;

% FreeSurfer environment used by the isolated local normalization.
config.normalization.source_command = 'source /usr/local/freesurfer/nmr-stable53-env';
% Runtime library directory for the FreeSurfer child process.
config.normalization.child_lib_path = '/autofs/cluster/matlab/current/sys/os/glnxa64';
% Host that runs local processing and FreeSurfer normalization.
config.normalization.host = '127.0.0.1';
% Use Slurm submission for normalization: 'Yes' or 'No'.
config.normalization.cluster = 'No';
% Shared subject temporary directories are used by the MLSC backend.
config.normalization.host_folder = '';

% Immutable legacy compiled facts (neutral contract shared with the MLSC
% legacy profile). Direct-local execution consumes only runner, mcr_root,
% defaults_mat, batch_templates, and att_map alongside the neutral
% top-level atlas/aliasing values and the normalization source command.
% No host, Slurm, partition, nodes, tasks, memory, time, or
% shell-orchestration values are carried here.
% Unchanged compiled runner script.
config.legacy.runner = '/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad/run_Pseudo_CT_launchpad.sh';
% MATLAB Compiler Runtime root used by the compiled backend.
config.legacy.mcr_root = '/usr/pubsw/common/matlab/7.11/';
% Defaults MAT file passed to the compiled backend.
config.legacy.defaults_mat = '/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad/default_pseudo_CT_package_deployed.mat';
% Atlas and SPM batch templates passed to the compiled backend.
config.legacy.batch_templates = '/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad/Batch_atlas';
% Required attenuation-map filename produced by the compiled backend.
config.legacy.att_map = 'att_map.nii';
end
