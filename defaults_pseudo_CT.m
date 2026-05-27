% Date: Sept/19/2014;
% Name: defaults_pseudo_CT.m
% Function that defines the default parameters required for several
% options.
% They can be edited if required.
% Inputs: -defstr: One of the definitions: 'HOSTNAME' or 'source_command'
%         for instance;
%
% Outputs: -out: containing the requested values (for HOSTNAME or
%         source_command or whatever is requested);

function out = defaults_pseudo_CT(defstr)

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%   MODIFY THIS SECTION TO MATCH YOUR CONFIGURATION   %%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

HOSTNAME = '127.0.0.1'; %'172.27.25.134'; % Address of Launchpad computer!
source_command = '/usr/local/freesurfer/8.2.0/SetUpFreeSurfer.sh'; %'source /usr/local/freesurfer/nmr-stable53-env; '; % To run FreeSurfer (if no source command is required, then '';
cluster = 'No'; %'Yes'; % If the HOSTNAME is a cluster (then use it to run the FS commands!); otherwise 'No';
host_folder = '/autofs/cluster/catanagp/users/mscipioni/tmp'; % %'/cluster/scratch/monday/'; % Path to folder in HOST computer (HOSTNAME) where temporary images will be created (in a subfolder under the user-name). All temporary images would be deleted when finishing (user folder will stay though!). It should be a folder where the user has access to read and write!! You could specify '~/' or './' for your default home folder

%%%% For deployed applications only:
key_number = '12345678901234'; % For deployed applications only! The number must be written as a string: ' ' 


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%   END OF THE SECTION TO BE MODIFIED, DO NOT CHANGE  %%%%%
%%%%%   ANYTHING ELSE!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!  %%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

out = -1; % Initialize it!

try
    eval(['out = ' defstr ';']);
catch
    disp(sprintf('There is no definition for: \n%s', defstr));
end

return