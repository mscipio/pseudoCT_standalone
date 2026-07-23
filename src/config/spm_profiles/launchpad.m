function config = launchpad()
%LAUNCHPAD Deployment template for Launchpad local support.
% Set spm_root to the local support SPM8 r6313 package. The remote backend
% remains independently identified as SPM8 r4667/MCR7.11.

config.spm_root = '';
config.expected_revision = 'r6313';
end
