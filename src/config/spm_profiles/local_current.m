function config = local_current()
%LOCAL_CURRENT Configuration for the local-current profile.
% Local MATLAB/SPM pipeline using the system-installed MATLAB version and
% compiled MEX dependencies. Recommended default.

%% === Paths ===
config.spm_root = '/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/pseudoCT_devel/pseudoCT_standalone/spm8-r6313';
config.batch_atlas_path = '/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/pseudoCT_devel/pseudoCT_standalone/Batch_atlas';

%% === Pipeline Parameters ===
config.recenter = 'No';
config.zero_background = 'Yes';
config.cleanup_policy = 'remove_on_success';
config.bone_enabled = true;
config.fwhm = 0;
config.aliasing_default = 1;
config.pca_order = {'callable_pca'; 'repo_legacy'};
config.runtime_guard = 'supported_matlab';
config.normalization_child_lib_path = '/autofs/cluster/matlab/current/sys/os/glnxa64';

end
