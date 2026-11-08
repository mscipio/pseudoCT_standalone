function config = local()
%LOCAL Local profile: this computer, shared compiled current worker.
%   CONFIG = LOCAL() returns the canonical 'local' profile struct. Profiles are
%   discovered from this folder; the selector shows config.presentation fields.
%   Reads dependency paths only; it does not run processing or touch files.
%   Minimum supported MATLAB: R2010b.

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
config.io_policy.reference = 'umap-required';
% Output policy: 'nifti-and-dicom' promotes NIfTI and writes DICOM;
% 'nifti-only' skips DICOM output.
config.io_policy.output = 'nifti-and-dicom';
% GUI policy: 'mMR' uses the MPRAGE+UTE/UMAP UI;
% 'mprage-only' keeps MPRAGE/aliasing controls but bypasses UTE/UMAP controls.
config.io_policy.gui = 'mMR';
% Compatibility baseline: empty disables baseline drift comparison;
% a profile name requires all non-policy settings to match that baseline.
config.compatibility_profile = '';
% Human-facing selector metadata; runtime identity remains filename-derived.
config.presentation.display_name = 'Local MATLAB - This Computer';
config.presentation.description = ...
    'Run the pseudoCT workflow on this computer using the shared compiled worker.';
config.presentation.group = 'recommended';
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

% Current compiled prepare/compute artifact contract shared with MLSC. No compiled
% tree is assumed. The placeholders are never files: installed runtime selection
% replaces the runner and MATLAB Runtime root and clears both manifest paths
% (direct mode). A source checkout refuses application runs unless an explicit
% development artifact root is supplied.
config.current.runner = 'runtime-selection-required';
% MATLAB 7.11 (R2010b) installation root; the MCR runtime release is 7.14.
config.current.mcr_root = '/usr/pubsw/common/matlab/7.11';
config.current.build_manifest = 'runtime-selection-required';
config.current.resource_manifest = 'runtime-selection-required';
config.current.required_outputs = {'att_map.nii'; ...
    'Fusion_MR_Pseudo_CT_validation.tiff'; 'Pseudo_CT_AC_Version.txt'};

end
