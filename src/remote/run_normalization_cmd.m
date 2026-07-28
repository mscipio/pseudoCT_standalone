% Date: Sept/19/2014;
% Name: run_normalization_cmd.m;
% Function to run the normalization command in an external machine (not cluster) using the ssh commands
% from matlab;
% Inputs: - cmd: the command to run on the external machine;
%         - ssh2_conn: (optional) if available, the ssh connection to a
%         host;
%         - config: selected profile config;
%
% Output: - sts: the exit status of the command (from the external machine). If 0 then
%           command finshed properly, otherwise there was some problem.
%
% To use: [sts] = run_normalization_cmd(cmd, ssh2_conn, pause_time, init_pause)
%
% By David Izquierdo-Garcia.
% Athinoula A. Martinos Center.
% Harvard University / Mass. General Hospital. Boston.

function [sts] = run_normalization_cmd(cmd, ssh2_conn, config)

sts = 0;
if nargin ~= 3 || ~isstruct(config)
    error('pseudo_CT:ProfileRequired', ...
        'run_normalization_cmd requires the selected profile config.');
end

source_command = config.normalization.source_command;
child_lib_path = config.normalization.child_lib_path;

aa = strfind(cmd, ' ');
norm_fn = strtrim(cmd((aa(end)+1):end));
is_local_host = strcmp(ssh2_conn.hostname, '127.0.0.1') || strcmpi(ssh2_conn.hostname, 'localhost');

disp('Starting FS command (be patient) ...');
if is_local_host
    [status, command_result] = system(local_prepare_source_command(source_command, cmd, child_lib_path));
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

function local_cmd = local_prepare_source_command(source_command, cmd, child_lib_path)

source_command = strtrim(source_command);
if isempty(source_command)
    local_cmd = cmd;
    return;
end

if source_command(end) == ';'
    source_command = strtrim(source_command(1:end-1));
end

if isempty(child_lib_path)
    child_lib_path = '/autofs/cluster/matlab/current/sys/os/glnxa64';
end

% --- Shell-safe input validation for ALL interpolated command strings ---
% child_lib_path, source_command, and cmd are all interpolated into tcsh/sh
% command strings below.  Validate each for shell metacharacters before
% ANY interpolation, not just child_lib_path.  (R1-001 full remediation.)
shell_meta = '[;&|`$(){\}\[\]<>!\\''"]';
if ~isempty(regexp(child_lib_path, shell_meta, 'once'))
    error('pseudo_CT:UnsafeNormalizationCommand', ...
        'Normalization library path contains shell metacharacters: %s', child_lib_path);
end
if ~isempty(regexp(source_command, shell_meta, 'once'))
    error('pseudo_CT:UnsafeNormalizationCommand', ...
        'Normalization source command contains shell metacharacters: %s', source_command);
end
if ~isempty(regexp(cmd, shell_meta, 'once'))
    error('pseudo_CT:UnsafeNormalizationCommand', ...
        'Normalization command contains shell metacharacters: %s', cmd);
end

if length(source_command) >= 6 && strcmpi(source_command(1:6), 'source')
    local_cmd = sprintf('tcsh -f -c "setenv LD_LIBRARY_PATH %s:$LD_LIBRARY_PATH; %s; %s"', child_lib_path, source_command, cmd);
else
    local_cmd = sprintf('/bin/sh -c "LD_LIBRARY_PATH=%s:$LD_LIBRARY_PATH; export LD_LIBRARY_PATH; %s; %s"', child_lib_path, source_command, cmd);
end
