function line = pseudo_CT_output(level, context, format_string, varargin)
%PSEUDO_CT_OUTPUT Write one standardized event to console and run logs.
%   Both console and log lines use second-resolution timestamps.
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

level = upper(strtrim(level));
valid_levels = {'INFO', 'WARN', 'ERROR', 'SUCCESS'};
if ~any(strcmp(level, valid_levels))
    error('pseudo_CT:InvalidOutputLevel', 'Unknown output level: %s', level);
end

message = sprintf(format_string, varargin{:});
message = regexprep(message, '[\r\n]+', ' | ');
timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
tags = '';
if isfield(context, 'subject_index') && isfield(context, 'subject_count') && ...
        ~isempty(context.subject_index) && ~isempty(context.subject_count)
    tags = [tags sprintf('[subject %d/%d] ', ...
        context.subject_index, context.subject_count)]; %#ok<AGROW>
end
if isfield(context, 'stage_index') && isfield(context, 'stage_count') && ...
        ~isempty(context.stage_index) && ~isempty(context.stage_count)
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
if strcmp(getenv('PSEUDOCT_CLI_OUTPUT'), '1')
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
