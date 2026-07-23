function config = local_current()
%LOCAL_CURRENT Deployment template for the local-current profile.
% Set spm_root to the deployed SPM8 r6313 package. Leave it blank only
% while preparing deployment; startup will then fail closed.

config.spm_root = '';
config.expected_revision = 'r6313';
end
