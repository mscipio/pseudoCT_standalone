function config = local_near_parity_r2010b()
%LOCAL_NEAR_PARITY_R2010B Local profile for MATLAB R2010b parity work.

% Select the local processing path or the remote Launchpad path.
config.mode = 'local';
% SPM installation used by this profile.
config.spm_root = '/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/spm8-dan';
% Atlas images and SPM batch templates used by the pipeline.
config.atlas_root = '/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/Batch_atlas';
% Recenter the MPRAGE before FreeSurfer normalization: 'Yes' or 'No'.
config.recenter_before_normalization = 'No';
% Set attenuation values outside the subject mask to zero: 'Yes' or 'No'.
config.zero_background = 'No';
% Remove temporary files after successful output promotion.
config.cleanup_on_success = false;
% PCA implementations to try in order.
config.pca_order = {'repo_legacy'; 'callable_pca'};
% Required MATLAB release without the leading R; empty accepts any release.
config.required_matlab_release = '2010b';
% Apply the bone-segmentation cleanup step.
config.bone_enabled = true;
% Final attenuation-map Gaussian smoothing width in millimetres.
config.fwhm = 0;
% Default nose/back aliasing correction for batch and explicit subject lists.
config.aliasing_default = 1;

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
