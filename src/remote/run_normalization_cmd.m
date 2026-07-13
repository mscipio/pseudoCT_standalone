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
aa = strfind(cmd, ' ');
norm_fn = strtrim(cmd((aa(end)+1):end));
is_local_host = strcmp(ssh2_conn.hostname, '127.0.0.1') || strcmpi(ssh2_conn.hostname, 'localhost');

disp('Starting FS command (be patient) ...');
if is_local_host
    [status, command_result] = system(local_prepare_source_command(source_command, cmd));
else
    [ssh2_conn, command_result] = ssh2_command_david(ssh2_conn, sprintf('%s%s', source_command, cmd), 1);
end

if is_local_host
    if exist(norm_fn, 'file') ~= 2
        disp(sprintf('Something has gone wrong and the normalized file was not creatd!!'));
        if ~isempty(command_result)
            disp(command_result);
        end
        if exist('status', 'var') && status ~= 0
            disp(sprintf('Local command exit status: %d', status));
        end
        sts = -1;
        return
    end
else
    [ssh2_conn, commando] = ssh2_command_david(ssh2_conn, sprintf('ls %s', norm_fn)); % Added the commando directly here and changed ssh_command by the David function that runs locally too!
    if iscell(commando)
        commando = commando{end};
    end
    commando = strtrim(commando);
    if ~strcmp(norm_fn, commando)
        disp(sprintf('Something has gone wrong and the normalized file was not creatd!!'));
        sts = -1;
        return
    end
end
    
disp('Good News Everyone!! The command ran properly!');

return

function local_cmd = local_prepare_source_command(source_command, cmd)

source_command = strtrim(source_command);
if isempty(source_command)
    local_cmd = cmd;
    return;
end

if source_command(end) == ';'
    source_command = strtrim(source_command(1:end-1));
end

fs_lib = getenv('PSEUDOCT_FS_LIBSTDCPP_ROOT');
if isempty(fs_lib)
    fs_lib = '/autofs/cluster/matlab/current/sys/os/glnxa64';
end

% --- Shell-safe input validation for ALL interpolated command strings ---
% fs_lib, source_command, and cmd are all interpolated into tcsh/sh
% command strings below.  Validate each for shell metacharacters before
% ANY interpolation, not just fs_lib.  (R1-001 full remediation.)
shell_meta = '[;&|`$(){}\[\]<>!\\''"]';
if ~isempty(regexp(fs_lib, shell_meta, 'once'))
    error('PSEUDOCT_FS_LIBSTDCPP_ROOT contains shell metacharacters: %s', fs_lib);
end
if ~isempty(regexp(source_command, shell_meta, 'once'))
    error('source_command contains shell metacharacters: %s', source_command);
end
if ~isempty(regexp(cmd, shell_meta, 'once'))
    error('Normalization command contains shell metacharacters: %s', cmd);
end

if length(source_command) >= 6 && strcmpi(source_command(1:6), 'source')
    local_cmd = sprintf('tcsh -f -c "setenv LD_LIBRARY_PATH %s:$LD_LIBRARY_PATH; %s; %s"', fs_lib, source_command, cmd);
else
    local_cmd = sprintf('/bin/sh -c "LD_LIBRARY_PATH=%s:$LD_LIBRARY_PATH; export LD_LIBRARY_PATH; %s; %s"', fs_lib, source_command, cmd);
end
