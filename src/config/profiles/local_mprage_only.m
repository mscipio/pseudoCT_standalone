function config = local_mprage_only()
%LOCAL_MPRAGE_ONLY Local MPRAGE-only profile matching LOCAL_CURRENT.

% Select the local processing path or the remote Launchpad path.
config.mode = 'local';
% SPM installation used by this profile.
config.spm_root = '/usr/pubsw/packages/mrpet/standalone_apps/shared_libraries_2026/spm8-r6313';
% Atlas images and SPM batch templates used by the pipeline.
config.atlas_root = '/usr/pubsw/packages/mrpet/standalone_apps/shared_libraries_2026/Batch_atlas';
% Standalone DICOM-to-NIfTI converter (sibling repository).
config.d2n_root = '/usr/pubsw/packages/mrpet/standalone_apps/dcm2nii/dicom2nifti_standalone-latest';
% Recenter the MPRAGE before FreeSurfer normalization: 'Yes' or 'No'.
config.recenter_before_normalization = 'No';
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
config.compatibility_profile = 'local-current';
% Human-facing selector metadata; runtime identity remains filename-derived.
config.presentation.display_name = '[Bay8] Local MATLAB - MPRAGE Only';
config.presentation.description = ...
    'Generate NIfTI-only pseudoCT locally from MPRAGE without requiring a UMAP reference.';
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

% Launchpad SSH host; empty for local use.
config.launchpad.host = '';
% Compiled Launchpad runner; empty for local use.
config.launchpad.runner = '';
% MATLAB Compiler Runtime root; empty for local use.
config.launchpad.mcr_root = '';
% Compiled backend defaults MAT file; empty for local use.
config.launchpad.defaults_mat = '';
% Remote batch-template directory; empty for local use.
config.launchpad.batch_templates = '';
% PBS queue override; empty for local use.
config.launchpad.queue = '';
% Remote scratch root; empty for local use.
config.launchpad.scratch = '';
end
