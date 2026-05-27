% Date: Sept/19/2014;
% Name: run_normalization_cmd.m;
% Function to run the normalization command in an external machine (not cluster) using the ssh commands
% from matlab;
% Inputs: - cmd: the command to run on the external machine;
%         - ssh2_conn: (optional) if available, the ssh connection to a
%         host;
%
% Output: - sts: the exit status of the command (from the external machine). If 0 then
%           command finshed properly, otherwise there was some problem.
%
% To use: [sts] = run_normalization_cmd(cmd, ssh2_conn, pause_time, init_pause)
%
% By David Izquierdo-Garcia.
% Athinoula A. Martinos Center.
% Harvard University / Mass. General Hospital. Boston.

function [sts] = run_normalization_cmd(cmd, varargin)

sts = 0;

if nargin > 1
    ssh2_conn = varargin{1};
else
%     [PASSWORD, USERNAME] = passwordEntryDialog('enterUserName', true, 'ValidatePassword', true, 'PasswordLengthMax', 50, ...
%         'WindowName', 'Enter your Martinos Login and Password to connect to the external machine and use FreeSurfer!');
%     HOSTNAME = defaults_pseudo_CT('HOSTNAME'); % Address of Launchpad computer!
% 
%     ssh_log = {USERNAME, PASSWORD, HOSTNAME};
% 
%     disp('Starting the ssh connection to run the Normalization process  ... (be patient!)');
%     ssh2_conn = ssh2_config(HOSTNAME,USERNAME,PASSWORD);
    ssh2_conn = ssh_login_pseudo_CT();
end
if nargin > 2 & isdeployed
    defaults = varargin{2};
end 

%source_command = 'source /usr/local/freesurfer/nmr-stable53-env'; % To run FreeSurfer!
source_command = defaults_pseudo_CT('source_command'); % To run FreeSurfer!
if isdeployed
    source_command = defaults.source_command;
end
disp('Starting FS command (be patient) ...');
ssh2_conn = ssh2_command_david(ssh2_conn, sprintf('%s%s', source_command, cmd), 1);
aa = strfind(cmd, ' ');
% Check the status:
norm_fn = cmd((aa(end)+1):end);
[ssh2_conn, commando] = ssh2_command_david(ssh2_conn, sprintf('ls %s', norm_fn)); % Added the commando directly here and changed ssh_command by the David function that runs locally too!
%commando = ssh2_command_response(ssh2_conn);
if ~strcmp(norm_fn, commando)
    disp(sprintf('Something has gone wrong and the normalized file was not creatd!!'));
    sts = -1;
    return
end
    
disp('Good News Everyone!! The command ran properly!');

return