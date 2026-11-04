function [ssh2_conn, lines] = launchpad_quiet_command(ssh2_conn, command, output_context)
%LAUNCHPAD_QUIET_COMMAND Run one remote command without echoing its response.
%   SSH2_COMMAND prints the remote response to the screen whenever it is
%   called with a single output.  Requesting the response as a second output
%   suppresses that echo.  Every non-empty response line is recorded, after
%   PSEUDO_CT_SANITIZE_MESSAGE, in the protected subject run log only
%   (console_detail_only); it never reaches the console or JSONL.
%   LINES is the response exactly as SSH2_COMMAND returns it (the same value
%   SSH2_COMMAND_RESPONSE gives for the connection), so callers index it with
%   the orientation they already use.

[ssh2_conn, lines] = ssh2_command(ssh2_conn, command);
text_lines = local_response_lines(lines);

detail_context = struct();
if isstruct(output_context) && isscalar(output_context)
    detail_context = output_context;
end
detail_context.console_detail_only = true;
% Launchpad responses are remote text: suppressed in every console mode.
detail_context.console_detail_remote = true;
for ii = 1:length(text_lines)
    if ~ischar(text_lines{ii})
        continue;
    end
    text = strtrim(text_lines{ii});
    if isempty(text)
        continue;
    end
    pseudo_CT_output('INFO', detail_context, '%s', ...
        pseudo_CT_sanitize_message(text));
end
end

function lines = local_response_lines(response)
lines = {};
if ischar(response)
    lines = regexp(response, '\r?\n', 'split');
elseif iscell(response)
    lines = response(:).';
end
end
