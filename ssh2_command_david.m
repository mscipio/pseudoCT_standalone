% Date: Dec/17/2017;
% Name: ssh2_command_david.m;
% Function to allow calls to the local machine (127.0.0.1) without running
% the ssh itself, since that collapses.

function [ssh2_struct, command_result] = ssh2_command_david(ssh2_struct, command, enableprint)

if nargin < 3
    enableprint = 0;
end

if ~strcmp(ssh2_struct.hostname , '127.0.0.1')
    [ssh2_struct, command_result] = ssh2_command(ssh2_struct, command, enableprint);
else
    [status,command_result] = system(command);
end

return
