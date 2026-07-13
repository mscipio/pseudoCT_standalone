% Date: Sept/19/2014;
% Name: defaults_pseudo_CT_launchpad.m
% Function that defines the default parameters required for the standalone
% Launchpad execution path.
% They can be edited if required.
% Minimum supported local MATLAB: R2010b (matches the cluster's compiled app MCR 7.11).  Modern MATLAB (R2013b+) MAY produce divergent optimizer results.
% Inputs: -defstr: One of the definitions: 'HOSTNAME' or 'source_command'
%         for instance;
%
% Outputs: -out: containing the requested values (for HOSTNAME or
%         source_command or whatever is requested);

function out = defaults_pseudo_CT_launchpad(defstr)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%   MODIFY THIS SECTION TO MATCH YOUR CONFIGURATION   %%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

HOSTNAME = '172.27.25.134'; % Address of Launchpad computer!
source_command = 'source /usr/local/freesurfer/nmr-stable53-env; '; % To run FreeSurfer on launchpad
cluster = 'Yes'; % If the HOSTNAME is a cluster (then use it to run the FS commands!); otherwise 'No';
host_folder = '/cluster/scratch/monday/'; % Used only for non-local hosts. On localhost, normalization staging now happens under the subject MR_PET/tmp folder.
recenter_before_normalization = 'Yes';
keep_temp_files = 'No'; % 'Yes' to preserve MR_PET/tmp/ after successful completion; overridden by PSEUDOCT_KEEP_TMP env var

%%%% For deployed applications only:
launchpad_root = '/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad';
launchpad_runner = fullfile(launchpad_root, 'run_Pseudo_CT_launchpad.sh');
launchpad_batch_templates = fullfile(launchpad_root, 'Batch_atlas');
launchpad_defaults_mat = fullfile(launchpad_root, 'default_pseudo_CT_package_deployed.mat');
launchpad_mcr_root = '/usr/pubsw/common/matlab/7.11/';
key_number = '12345678901234'; % For deployed applications only! The number must be written as a string: ' ' 

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%   END OF THE SECTION TO BE MODIFIED, DO NOT CHANGE  %%%%%
%%%%%   ANYTHING ELSE!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!  %%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

out = -1;

try
    eval(['out = ' defstr ';']);
catch
    disp(sprintf('There is no definition for: \n%s', defstr));
end

return