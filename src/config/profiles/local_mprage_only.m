function config = local_mprage_only()
%LOCAL_MPRAGE_ONLY Local MPRAGE-only profile matching LOCAL.

dependency_paths = pseudo_CT_dependency_paths();

% Execution mode: 'local' runs the pipeline on this computer.
config.mode = 'local';
% SPM installation used by this profile.
config.spm_root = dependency_paths.spm_root;
% Atlas images and SPM batch templates used by the pipeline.
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
% PCA implementations to try in order.
config.pca_order = {'callable_pca'; 'repo_legacy'};
% Required MATLAB release without the leading R; empty accepts any release.
config.required_matlab_release = '';
% Apply the bone-segmentation cleanup step.
config.bone_enabled = true;
% Final attenuation-map Gaussian smoothing width in millimetres.
config.fwhm = 0;
% Default nose/back aliasing correction for batch and explicit subject lists.
config.aliasing_default = 1;
% Reference policy: 'umap-required' discovers and validates a UMAP reference;
% 'none' uses MPRAGE-only collection.
config.io_policy.reference = 'none';
% Output policy: 'nifti-and-dicom' promotes NIfTI and writes DICOM;
% 'nifti-only' skips DICOM output.
config.io_policy.output = 'nifti-only';
% GUI policy: 'mMR' uses the MPRAGE+UTE/UMAP UI;
% 'mprage-only' keeps MPRAGE/aliasing controls but bypasses UTE/UMAP controls.
config.io_policy.gui = 'mprage-only';
% Compatibility baseline: empty disables baseline drift comparison;
% a profile name requires all non-policy settings to match that baseline.
config.compatibility_profile = 'local';
% Human-facing selector metadata; runtime identity remains filename-derived.
config.presentation.display_name = 'Local MPRAGE Only';
config.presentation.description = ...
    'Generate a NIfTI-only pseudoCT locally from MPRAGE alone using the shared current-science payload. No UMAP required.';
config.presentation.group = 'specialized';
config.presentation.recommended = false;
config.presentation.order = 10;

% FreeSurfer environment command.
config.normalization.source_command = 'source /usr/local/freesurfer/nmr-stable53-env';
% Runtime library directory prepended for the FreeSurfer child process.
config.normalization.child_lib_path = '/autofs/cluster/matlab/current/sys/os/glnxa64';
% Host that runs FreeSurfer normalization.
config.normalization.host = '127.0.0.1';
% Use cluster submission for normalization: 'Yes' or 'No'.
config.normalization.cluster = 'No';
% Remote normalization scratch root; empty for localhost.
config.normalization.host_folder = '';


% Current compiled prepare/compute artifacts shared with local and MLSC.
% Resolve every artifact from this installation's current root.
artifact_dir_here = dependency_paths.current_root;
config.current.runner = fullfile(artifact_dir_here, 'payload_build', ...
    'run_mlsc_current_payload.sh');
config.current.mcr_root = '/usr/pubsw/common/matlab/7.11';
config.current.build_manifest = fullfile(artifact_dir_here, ...
    'mlsc_current_build.mat');
config.current.resource_manifest = fullfile(artifact_dir_here, ...
    'mlsc_current_resources.mat');
config.current.required_outputs = {'att_map.nii'; ...
    'Fusion_MR_Pseudo_CT_validation.tiff'; 'Pseudo_CT_AC_Version.txt'};
end
