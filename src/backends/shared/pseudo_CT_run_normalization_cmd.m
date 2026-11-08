function [sts] = pseudo_CT_run_normalization_cmd(cmd, ssh2_conn, varargin)
%PSEUDO_CT_RUN_NORMALIZATION_CMD Run the FreeSurfer normalization command, locally or over SSH.
%   STS = PSEUDO_CT_RUN_NORMALIZATION_CMD(CMD, SSH2_CONN, CONFIG)
%   STS = PSEUDO_CT_RUN_NORMALIZATION_CMD(CMD, SSH2_CONN, OUTPUT_CONTEXT, CONFIG)
%   CMD is the normalization command. Its last space-separated token is the
%   normalized NIfTI path that the command must create.
%   SSH2_CONN is the connection struct; its hostname selects the path. 127.0.0.1
%   and localhost run CMD on this machine with system(), prefixed by
%   config.normalization.source_command and child_lib_path. Any other host runs
%   the command through pseudo_CT_ssh2_command, then checks the file with ls.
%   CONFIG is the selected profile struct. OUTPUT_CONTEXT is an optional logging
%   struct.
%   STS is 0 when the normalized file exists and -1 when it does not. Failure
%   detail is logged through pseudo_CT_output.
%   Side effects: runs the external FreeSurfer command on the local or remote
%   host. Errors: pseudo_CT:ProfileRequired when CONFIG is missing.
%   Origin: David Izquierdo-Garcia (Athinoula A. Martinos Center, MGH), 2014.
%   Minimum supported MATLAB: R2010b.

sts = 0;
if nargin < 3 || nargin > 4 || ~isstruct(varargin{end})
    error('pseudo_CT:ProfileRequired', ...
        'pseudo_CT_run_normalization_cmd requires the selected profile config.');
end
config = varargin{end};
output_context = struct();
if length(varargin) == 2
    output_context = varargin{1};
end

source_command = config.normalization.source_command;
child_lib_path = config.normalization.child_lib_path;

aa = strfind(cmd, ' ');
norm_fn = strtrim(cmd((aa(end)+1):end));
is_local_host = strcmp(ssh2_conn.hostname, '127.0.0.1') || strcmpi(ssh2_conn.hostname, 'localhost');

if is_local_host
    [status, command_result] = system(local_prepare_source_command(source_command, cmd, child_lib_path));
else
    [ssh2_conn, command_result] = pseudo_CT_ssh2_command(ssh2_conn, sprintf('%s%s', source_command, cmd), 1);
end

if is_local_host
    if exist(norm_fn, 'file') ~= 2
        pseudo_CT_output('ERROR', output_context, 'FreeSurfer did not create the normalized NIfTI file.');
        if ~isempty(command_result)
            pseudo_CT_output('ERROR', output_context, 'FreeSurfer failure detail: %s', strtrim(command_result));
        end
        if exist('status', 'var') && status ~= 0
            pseudo_CT_output('ERROR', output_context, 'FreeSurfer exit status: %d.', status);
        end
        sts = -1;
        return
    end
else
    [ssh2_conn, commando] = pseudo_CT_ssh2_command(ssh2_conn, sprintf('ls %s', norm_fn)); % Added the commando directly here and changed ssh_command by the David function that runs locally too!
    if iscell(commando)
        commando = commando{end};
    end
    commando = strtrim(commando);
    if ~strcmp(norm_fn, commando)
        pseudo_CT_output('ERROR', output_context, 'FreeSurfer did not create the normalized NIfTI file.');
        sts = -1;
        return
    end
end
    

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
