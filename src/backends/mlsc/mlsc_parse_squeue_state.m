function state = mlsc_parse_squeue_state(response)
%MLSC_PARSE_SQUEUE_STATE Parse one stable squeue %T state.
%   STATE = MLSC_PARSE_SQUEUE_STATE(RESPONSE) returns a normalized state and
%   never treats an empty or human-readable response as successful completion.
%   The returned values are pending, running, completed, failed, cancelled,
%   timeout, OUT_OF_MEMORY, NODE_FAIL, or unknown.
%
%   Minimum supported MATLAB: R2010b.

lines = local_response_lines(response);
nonempty = {};
for ii = 1:length(lines)
    line = strtrim(lines{ii});
    if ~isempty(line)
        nonempty{end + 1} = line; %#ok<AGROW>
    end
end
if length(nonempty) ~= 1
    state = 'unknown';
    return;
end

token = regexp(upper(nonempty{1}), '^([A-Z_]+)', 'tokens', 'once');
if isempty(token)
    state = 'unknown';
    return;
end
state = local_normalize_state(token{1});
end

function lines = local_response_lines(response)
if ischar(response)
    lines = cellstr(response);
elseif iscell(response)
    lines = {};
    for ii = 1:numel(response)
        if ~ischar(response{ii})
            state_error();
        end
        lines{end + 1} = response{ii}; %#ok<AGROW>
    end
else
    state_error();
end
end

function state_error()
error('pseudo_CT:MLSCSqueueParse', 'The squeue response must be text.');
end

function state = local_normalize_state(raw_state)
switch raw_state
    case {'PENDING'; 'PD'; 'CONFIGURING'; 'CF'}
        state = 'pending';
    case {'RUNNING'; 'R'; 'COMPLETING'; 'CG'; 'RESIZING'; 'RS'; ...
            'SUSPENDED'}
        state = 'running';
    case {'COMPLETED'; 'CD'}
        state = 'completed';
    case {'CANCELLED'; 'CA'}
        state = 'cancelled';
    case {'TIMEOUT'; 'TO'}
        state = 'timeout';
    case {'OUT_OF_MEMORY'; 'OOM'}
        state = 'OUT_OF_MEMORY';
    case {'NODE_FAIL'; 'NF'}
        state = 'NODE_FAIL';
    case {'FAILED'; 'F'; 'BOOT_FAIL'; 'BF'; 'DEADLINE'; 'DL'; ...
            'PREEMPTED'; 'PR'}
        state = 'failed';
    otherwise
        state = 'unknown';
end
end
