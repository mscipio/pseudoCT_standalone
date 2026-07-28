function line = pseudo_CT_output(level, context, format_string, varargin)
%PSEUDO_CT_OUTPUT Write one standardized event to console and run logs.
%   Console lines are untimestamped. Log lines use second-resolution time.
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
prefix = sprintf('[pseudo-CT] %-7s ', level);
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

line = [prefix tags message];
fprintf(1, '%s\n', line);

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
            fprintf(1, '[pseudo-CT] WARN    Run log could not be written; processing will continue.\n');
            log_warning_emitted = true;
        end
        continue;
    end
    write_failed = false;
    try
        fprintf(fid, '%s %s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'), line);
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
            fprintf(1, '[pseudo-CT] WARN    Run log could not be written; processing will continue.\n');
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
