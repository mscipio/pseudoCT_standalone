function config = local_near_parity_r2010b()
%LOCAL_NEAR_PARITY_R2010B Configuration for the near-parity profile.
% Local pipeline pinned to near-R2010b (7.11) numerical parity for
% consistent optimizer results across MATLAB versions. Intended for
% internal validation use.

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
config.pca_order = {'repo_legacy'; 'callable_pca'};
config.runtime_guard = 'r2010b_only';

end
