function config = launchpad()
%LAUNCHPAD Configuration for the launchpad profile.
% Legacy compiled Launchpad backend via SSH. Intended for subjects
% requiring the original cluster runtime environment.

%% === Paths ===
config.spm_root = '/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/pseudoCT_devel/pseudoCT_standalone/spm8-dan';
config.batch_atlas_path = '/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/pseudoCT_devel/pseudoCT_standalone/Batch_atlas';

%% === Pipeline Parameters ===
config.recenter = 'No';
config.zero_background = 'No';
config.cleanup_policy = 'remove_on_success';
config.bone_enabled = true;
config.fwhm = 0;
config.aliasing_default = 1;
config.pca_order = {'remote'};
config.runtime_guard = 'launchpad_opaque';

%% === Launchpad Settings ===
config.launchpad_host = '172.27.25.134';
config.launchpad_runner = '/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad/run_Pseudo_CT_launchpad.sh';
config.launchpad_mcr_root = '/usr/pubsw/common/matlab/7.11/';
config.launchpad_defaults_mat = '/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad/default_pseudo_CT_package_deployed.mat';
config.launchpad_backend_mat = '/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad/Pseudo_CT_launchpad';
config.launchpad_batch_templates = '/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad/Batch_atlas';
config.launchpad_queue = 'p60';
config.launchpad_scratch = '/cluster/scratch/monday/';
config.launchpad_backend_spm_version = 'r4667';
config.launchpad_backend_runtime = 'MCR7.11';

end
