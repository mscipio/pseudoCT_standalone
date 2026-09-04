function record = mlsc_parse_sacct_terminal(response, job_id)
%MLSC_PARSE_SACCT_TERMINAL Parse the primary sacct allocation record.
%   RECORD = MLSC_PARSE_SACCT_TERMINAL(RESPONSE, JOB_ID) parses stable
%   --parsable2 fields in the order JobIDRaw|State|ExitCode|Start|End|... .
%   Only the exact numeric allocation JOB_ID is accepted; .batch and .extern
%   step records are deliberately ignored.  A terminal scheduler state is
%   authoritative only when this primary allocation record is present.
%
%   Minimum supported MATLAB: R2010b.

if nargin < 2
    job_id = [];
end
wanted_id = local_job_id_text(job_id);
record = local_empty_record(wanted_id);
lines = local_response_lines(response);

for ii = 1:length(lines)
    line = strtrim(lines{ii});
    if isempty(line)
        continue;
    end
    fields = regexp(line, '\|', 'split');
    if length(fields) < 3
        continue;
    end
    candidate_id = strtrim(fields{1});
    if isempty(regexp(candidate_id, '^[0-9]+$', 'once'))
        continue;
    end
    if ~isempty(wanted_id) && ~strcmp(candidate_id, wanted_id)
        continue;
    end

    record.found = true;
    record.job_id = str2double(candidate_id);
    record.raw_state = strtrim(fields{2});
    record.state = local_normalize_state(record.raw_state);
    record.exit_code_text = strtrim(fields{3});
    [record.exit_code, record.exit_signal, record.exit_code_valid] = ...
        local_parse_exit_code(record.exit_code_text);
    if length(fields) >= 4
        record.start_time = strtrim(fields{4});
    end
    if length(fields) >= 5
        record.end_time = strtrim(fields{5});
    end
    if length(fields) >= 6
        record.elapsed = strtrim(fields{6});
    end
    record.primary_allocation = true;
    record.terminal = local_is_terminal(record.state);
    return;
end
end

function record = local_empty_record(wanted_id)
record = struct();
record.found = false;
record.primary_allocation = false;
record.job_id = 0;
record.requested_job_id = wanted_id;
record.raw_state = '';
record.state = 'unknown';
record.exit_code_text = '';
record.exit_code = [];
record.exit_signal = [];
record.exit_code_valid = false;
record.start_time = '';
record.end_time = '';
record.elapsed = '';
record.terminal = false;
end

function wanted_id = local_job_id_text(job_id)
if isempty(job_id)
    wanted_id = '';
elseif isnumeric(job_id) && isscalar(job_id) && isfinite(job_id) && ...
        job_id >= 1 && job_id == floor(job_id)
    wanted_id = num2str(job_id, '%.0f');
elseif ischar(job_id)
    wanted_id = strtrim(job_id);
else
    error('pseudo_CT:MLSCSacctParse', 'The sacct job ID is invalid.');
end
if ~isempty(wanted_id) && isempty(regexp(wanted_id, '^[0-9]+$', 'once'))
    error('pseudo_CT:MLSCSacctParse', ...
        'The sacct job ID must identify a numeric primary allocation.');
end
end

function [code, signal, valid] = local_parse_exit_code(value)
code = [];
signal = [];
valid = false;
tokens = regexp(value, '^([0-9]+):([0-9]+)(\+.*)?$', 'tokens', 'once');
if isempty(tokens)
    return;
end
code = str2double(tokens{1});
signal = str2double(tokens{2});
valid = isfinite(code) && isfinite(signal) && code >= 0 && signal >= 0;
if ~valid
    code = [];
    signal = [];
end
end

function lines = local_response_lines(response)
if ischar(response)
    lines = cellstr(response);
elseif iscell(response)
    lines = {};
    for ii = 1:numel(response)
        if ~ischar(response{ii})
            error('pseudo_CT:MLSCSacctParse', ...
                'The sacct response must contain text lines.');
        end
        lines{end + 1} = response{ii}; %#ok<AGROW>
    end
else
    error('pseudo_CT:MLSCSacctParse', 'The sacct response must be text.');
end
end

function state = local_normalize_state(raw_state)
token = regexp(upper(strtrim(raw_state)), '^([A-Z_]+)', ...
    'tokens', 'once');
if isempty(token)
    state = 'unknown';
    return;
end
switch token{1}
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

function terminal = local_is_terminal(state)
terminal = any(strcmp(state, {'completed'; 'failed'; 'cancelled'; ...
    'timeout'; 'OUT_OF_MEMORY'; 'NODE_FAIL'}));
end
