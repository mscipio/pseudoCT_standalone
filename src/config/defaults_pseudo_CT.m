% Date: Sept/19/2014;
% Name: defaults_pseudo_CT.m
% Function that defines the default parameters required for performing the pseudo-CT processing locally.
% DO NOT EDIT.

function out = defaults_pseudo_CT(defstr)


config_dir = fileparts(mfilename('fullpath'));

HOSTNAME = '127.0.0.1';
%fshome_command = 'export FREESURFER_HOME=/usr/local/freesurfer/8.2.0';
source_command = sprintf('source %s', fullfile(config_dir, 'fs_setenv_530_from_launchpad.sh')); %'source /usr/local/freesurfer/nmr-stable53-env; '; % To run FreeSurfer 
cluster = 'No'; 
% Launchpad normalizes first and passes an _normalized.nii input to the
% compiled workflow, so its recenter branch is bypassed.
recenter_before_normalization = 'No';
zero_background = 'No'; % 'Yes' applies the optional final subject-mask multiplication.
batch_atlas_path = ''; % Path to Batch_atlas directory; overridden by PSEUDOCT_BATCH_ATLAS env var
keep_temp_files = 'No'; % 'Yes' to preserve MR_PET/tmp/ after successful completion; overridden by PSEUDOCT_KEEP_TMP env var
out = -1; % Initialize it!
try
    eval(['out = ' defstr ';']);
catch
    disp(sprintf('There is no definition for: \n%s', defstr));
end

return
