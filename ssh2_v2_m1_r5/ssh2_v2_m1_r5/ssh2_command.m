function [ssh2_struct, command_result, command_status] = ssh2_command(ssh2_struct, command, enableprint)
% SSH2_COMMAND   Reuses a SSH2 connection and issues the specified command
%
%   [SSH2_CONN, [COMMAND_RESULT], [COMMAND_STATUS]] = SSH2_COMMAND(SSH2_CONN,COMMAND,[ENABLEPRINTTOSCREEN])
%   Connects to the SSH2 host with a configured SSH2_CONN. Once connected 
%   the COMMAND is issues. The output from the remote host is returned.
%   The connection to the remote host is still open the function completes.
%   When finished, close the connection with SSH2_CLOSE(SSH2_CONN)
%
%   OPTIONAL INPUTS:
%   -----------------------------------------------------------------------
%   ENABLEPRINTTOSCREEN  force printing the remote host output on screen.
%
% 
%   SSH2_COMMAND returns the SSH2_CONN for future use and the 
%   cell array containing the host response.
%
%   COMMAND_STATUS  optional THIRD output: the numeric exit status of the
%   command as reported by the remote host.  0 means success, any other
%   number means failure, and empty ([]) means the status was unavailable
%   (the server sent no exit-status packet within the bounded wait, or the
%   channel closed without one); unavailable is an explicit FAILURE.  The
%   status is never inferred from the response text, so empty or
%   success-looking output does not override a non-zero or missing status.
%   The SSH2_CONN also carries .command_exit_status (same numeric value or
%   []) and .command_success (logical true only when the numeric status is
%   0).  Existing one- and two-output callers are unaffected.
%
%see also ssh2, ssh2_config, ssh2_config_publickey, ssh2_simple_command
%
% (c)2011 Boston University - ECE
%    David Scott Freedman (dfreedma@bu.edu)
%    Version 2.0

if nargin < 3
    enableprint = 0;
end

ssh2_struct.command = command;

%% SSH TO HOST
ssh2_struct = ssh2(ssh2_struct);

%% OUTPUT RESPONSE FROM HOST
if (nargout < 2 || enableprint)
    for i = 1:numel(ssh2_struct.command_result)
       fprintf('%s\n', ssh2_struct.command_result{i});
    end
end

if nargout > 1
    command_result = ssh2_struct.command_result;
end
if nargout > 2
    command_status = ssh2_struct.command_exit_status;
end
if nargout == 0
    clear ssh2_struct;
end
