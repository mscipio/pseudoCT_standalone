function line = pseudo_CT_output(level, context, format_string, varargin)
%PSEUDO_CT_OUTPUT Write one standardized event to the console and the run log.
%   LINE = PSEUDO_CT_OUTPUT(LEVEL, CONTEXT, FORMAT_STRING, ARG1, ...)
%   LEVEL is 'INFO', 'WARN', 'ERROR' or 'SUCCESS' (case-insensitive). CONTEXT
%   is a logging struct: log_file or log_files name the run log, and console_*
%   fields control the console view. FORMAT_STRING and ARG1, ... are passed to
%   sprintf. LINE is the formatted text, with a second-resolution timestamp.
%   The console receives the line when the console view shows it. The run log
%   receives it whenever a log file is set.
%   Side effects: prints to the console and appends to the run log file(s). If
%   a log cannot be written, one warning is emitted per MATLAB session.
%   Minimum supported MATLAB: R2010b.

persistent log_warning_emitted;
if isempty(log_warning_emitted)
    log_warning_emitted = false;
end

if nargin < 2 || ~isstruct(context)
    context = struct();
end
if nargin < 3
    format_string = '';
end
context = local_public_stage_context(context);

level = upper(strtrim(level));
valid_levels = {'INFO', 'WARN', 'ERROR', 'SUCCESS'};
if ~any(strcmp(level, valid_levels))
    error('pseudo_CT:InvalidOutputLevel', 'Unknown output level: %s', level);
end

message = sprintf(format_string, varargin{:});
message = regexprep(message, '[\r\n]+', ' | ');
timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
% Optional original event time for replayed external diagnostics (for example
% buffered dcm2nii lines); invalid values fall back to the current time.
if isfield(context, 'record_timestamp') && ischar(context.record_timestamp) && ...
        ~isempty(regexp(context.record_timestamp, ...
        '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$', 'once'))
    timestamp = context.record_timestamp;
end
tags = '';
if isfield(context, 'subject_index') && isfield(context, 'subject_count') && ...
        ~isempty(context.subject_index) && ~isempty(context.subject_count)
    tags = [tags sprintf('[subject %d/%d] ', ...
        context.subject_index, context.subject_count)]; %#ok<AGROW>
end
% The stage number is printed once per run log and subject: on that stage's
% first row (its START row, or its SKIPPED row when no START exists). Later rows
% of the same stage carry the status and message without the number.
if isfield(context, 'stage_index') && isfield(context, 'stage_count') && ...
        ~isempty(context.stage_index) && ~isempty(context.stage_count) && ...
        local_claim_stage_number(context)
    tags = [tags sprintf('[stage %d/%d] ', ...
        context.stage_index, context.stage_count)]; %#ok<AGROW>
end
if isfield(context, 'job_number') && ~isempty(context.job_number)
    tags = [tags sprintf('[job %s] ', local_to_char(context.job_number))]; %#ok<AGROW>
end
if isempty(tags) && isfield(context, 'scope') && ~isempty(context.scope)
    tags = sprintf('[%s] ', context.scope);
end

line = sprintf('[%s] %-7s %s%s', timestamp, level, tags, message);
cli_output = strcmp(getenv('PSEUDOCT_CLI_OUTPUT'), '1');
detail_only = isfield(context, 'console_detail_only') && ...
    isequal(context.console_detail_only, true);
remote_detail = isfield(context, 'console_detail_remote') && ...
    isequal(context.console_detail_remote, true);
if detail_only && (cli_output || remote_detail)
    % Detailed diagnostics are written to the protected run log only. Local
    % detail rows keep the HEAD behaviour: suppressed in CLI mode, printed to the
    % MATLAB command window otherwise. Remote (PBS/SSH response) detail rows are
    % suppressed in every console mode; the presenter never sees them.
elseif cli_output
    console_source_line = line;
    if isfield(context, 'console_timestamp') && ...
            ischar(context.console_timestamp) && ...
            ~isempty(regexp(context.console_timestamp, ...
            '^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$', 'once'))
        console_source_line = sprintf('[%s] %-7s %s%s', ...
            context.console_timestamp, level, tags, message);
    end
    [console_visible, console_line] = pseudo_CT_output_console_visible( ...
        level, message, context, console_source_line);
    if console_visible
        if strcmp(getenv('PSEUDOCT_OUTPUT_FORMAT'), 'jsonl')
            % The CLI formatter emits JSONL directly, including delayed warnings.
        else
            fprintf(1, '%s\n', console_line);
        end
    end
else
    % Preserve the established MATLAB console contract outside the CLI.
    fprintf(1, '%s\n', line);
end

log_files = {};
if isfield(context, 'log_files') && ~isempty(context.log_files)
    log_files = context.log_files;
elseif isfield(context, 'log_file') && ~isempty(context.log_file)
    log_files = {context.log_file};
end
if ischar(log_files)
    log_files = {log_files};
end

for ii = 1:length(log_files)
    fid = fopen(log_files{ii}, 'a');
    if fid == -1
        if ~log_warning_emitted
            warning_line = sprintf('[%s] WARN    Run log could not be written; processing will continue.', timestamp);
            if strcmp(getenv('PSEUDOCT_CLI_OUTPUT'), '1') && ...
                    strcmp(getenv('PSEUDOCT_OUTPUT_FORMAT'), 'jsonl')
                fprintf(2, '%s\n', warning_line);
            else
                fprintf(1, '%s\n', warning_line);
            end
            log_warning_emitted = true;
        end
        continue;
    end
    write_failed = false;
    try
        fprintf(fid, '%s\n', line);
    catch
        write_failed = true;
    end
    try
        fclose(fid);
    catch
        write_failed = true;
    end
    if write_failed
        if ~log_warning_emitted
            warning_line = sprintf('[%s] WARN    Run log could not be written; processing will continue.', timestamp);
            if strcmp(getenv('PSEUDOCT_CLI_OUTPUT'), '1') && ...
                    strcmp(getenv('PSEUDOCT_OUTPUT_FORMAT'), 'jsonl')
                fprintf(2, '%s\n', warning_line);
            else
                fprintf(1, '%s\n', warning_line);
            end
            log_warning_emitted = true;
        end
    end
end
end

function value = local_to_char(value)
if isnumeric(value)
    value = num2str(value);
else
    value = char(value);
end
end

function context = local_public_stage_context(context)
% Apply the shared policy map to context tags only. MESSAGE remains the
% original detailed-log record; console sanitization is a separate view.
if ~isstruct(context) || ~isscalar(context) || ...
        (isfield(context, 'workflow_event') && ...
        isequal(context.workflow_event, true)) || ...
        ~isfield(context, 'stage_map') || ...
        ~isfield(context, 'stage_index') || ...
        ~isfield(context, 'stage_count')
    return;
end
if ~isstruct(context.stage_map) || ...
        ~isnumeric(context.stage_index) || ~isscalar(context.stage_index) || ...
        ~isnumeric(context.stage_count) || ~isscalar(context.stage_count)
    return;
end
[~, stage_number, stage_total] = pseudo_CT_stage_map( ...
    context.stage_map, context.stage_index, context.stage_count);
if stage_number > 0
    context.stage_index = stage_number;
    context.stage_count = stage_total;
end
end

function first = local_claim_stage_number(context)
% True on the first row of this stage for this run log and subject. Called once
% per row, after the public stage mapping, so local and MLSC rows share one rule.
% A context without a run log has no run identity: its rows keep their number.
persistent numbered;
first = true;
key = local_run_key(context);
if isempty(key)
    return;
end
if ~isa(numbered, 'containers.Map')
    numbered = containers.Map();
end
key = sprintf('%s|stage%d', key, context.stage_index);
if isKey(numbered, key)
    first = false;
else
    numbered(key) = true;
end
end

function key = local_run_key(context)
% Run log identity plus subject index; '' when the context names no run log.
key = '';
if isfield(context, 'log_files') && ~isempty(context.log_files)
    files = context.log_files;
    if ischar(files)
        files = {files};
    end
    if iscellstr(files)
        key = sprintf('%s;', files{:});
    end
elseif isfield(context, 'log_file') && ischar(context.log_file)
    key = context.log_file;
end
if isempty(key)
    return;
end
subject = '';
if isfield(context, 'subject_index') && ~isempty(context.subject_index)
    subject = local_to_char(context.subject_index);
end
key = [key '|subject' subject];
end
