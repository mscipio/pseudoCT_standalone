function [ssh2_struct, command_result] = pseudo_CT_ssh2_command(ssh2_struct, command, enableprint)
%PSEUDO_CT_SSH2_COMMAND Run one shell command on the local machine or over SSH.
%   [SSH2_STRUCT, COMMAND_RESULT] = PSEUDO_CT_SSH2_COMMAND(SSH2_STRUCT, COMMAND, ENABLEPRINT)
%   SSH2_STRUCT is the ssh2 connection struct (field hostname). When hostname
%   is 127.0.0.1, COMMAND runs with system() on this machine, avoiding an ssh
%   connection to the same host; the struct is returned unchanged. Any other
%   hostname passes COMMAND to the ssh2_command toolbox function over SSH.
%   ENABLEPRINT is optional (default 0) and is forwarded on the SSH path.
%   COMMAND_RESULT is the command output text. On the local path the exit
%   status is not returned.
%   Side effects: runs COMMAND locally or on the remote host. Errors: none are
%   raised here; ssh2_command errors propagate.
%   Originally dated 12/17/2017. Minimum supported MATLAB: R2010b.

if nargin < 3
    enableprint = 0;
end

if ~strcmp(ssh2_struct.hostname , '127.0.0.1')
    [ssh2_struct, command_result] = ssh2_command(ssh2_struct, command, enableprint);
else
    [status,command_result] = system(command);
end

return
