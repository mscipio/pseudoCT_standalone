function config = launchpad()
%LAUNCHPAD Remote profile using the legacy compiled Launchpad backend.

% Select the local processing path or the remote Launchpad path.
config.mode = 'launchpad';
% SPM installation used by the local input/output support code.
config.spm_root = '/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/spm8-r6313';
% Atlas images and SPM batch templates used by local support code.
config.atlas_root = '/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/Batch_atlas';
% Recenter the MPRAGE before FreeSurfer normalization: 'Yes' or 'No'.
config.recenter_before_normalization = 'No';
% Set attenuation values outside the subject mask to zero: 'Yes' or 'No'.
config.zero_background = 'No';
% Remove temporary files after successful output promotion.
config.cleanup_on_success = false;
% PCA implementations to try in order; remote means the backend owns PCA.
config.pca_order = {'remote'};
% Required local MATLAB release; empty accepts any release.
config.required_matlab_release = '';
% Apply bone cleanup when processing locally; remote processing owns its copy.
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
config.normalization.host = '172.27.25.134';
% Use cluster submission for normalization: 'Yes' or 'No'.
config.normalization.cluster = 'Yes';
% Remote normalization scratch root.
config.normalization.host_folder = '/cluster/scratch/monday/';

% Launchpad SSH host.
config.launchpad.host = '172.27.25.134';
% Compiled Launchpad runner script.
config.launchpad.runner = '/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad/run_Pseudo_CT_launchpad.sh';
% MATLAB Compiler Runtime root used by the compiled backend.
config.launchpad.mcr_root = '/usr/pubsw/common/matlab/7.11/';
% Defaults MAT file passed to the compiled backend.
config.launchpad.defaults_mat = '/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad/default_pseudo_CT_package_deployed.mat';
% Atlas and SPM batch templates passed to the compiled backend.
config.launchpad.batch_templates = '/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad/Batch_atlas';
% PBS queue override; empty uses the subject-count heuristic.
config.launchpad.queue = '';
% Remote scratch root for staged subjects.
config.launchpad.scratch = '/cluster/scratch/monday/';
end
