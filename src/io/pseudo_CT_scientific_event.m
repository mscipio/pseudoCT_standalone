function ok = pseudo_CT_scientific_event(target, rec)
%PSEUDO_CT_SCIENTIFIC_EVENT Append one scientific or run record as one JSONL line.
%   OK = PSEUDO_CT_SCIENTIFIC_EVENT(TARGET, REC) appends exactly one complete,
%   newline-terminated JSON object to TARGET.path (see
%   pseudo_CT_scientific_event_target). REC is a scalar struct whose fields
%   are all optional:
%     event_type       'stage' (default), 'run' or 'diagnostic'
%     level            'INFO', 'WARN' or 'ERROR' (diagnostic records only)
%     kind             'warning', 'error', 'heartbeat' or 'lifecycle'
%                      (diagnostic records only; written by the orchestrator at
%                      phase boundaries only. 'heartbeat' is accepted by this
%                      validator but no writer emits it; never stage rows)
%     stage_id         lowercase identifier, e.g. 'segment' or the canonical
%                      'workflow.recenter' form (stage records)
%     stage_index      canonical ten-stage index 1..10, or [] when none
%     status           'STARTED', 'COMPLETED', 'FAILED', 'SKIPPED' or ''
%                      (stage records). SKIPPED is an observed policy or
%                      not-required outcome and carries its reason in message.
%     outcome          'SUCCEEDED', 'FAILED', 'CANCELLED' (run records only)
%     message          short human text (redacted, truncated to 240 chars)
%     source           'local-orchestrator', 'payload' (the compiled
%                      pseudoct_pipeline, a fixed record-source token) or
%                      'mlsc-lifecycle'
%     job_id           scheduler job number digits, or ''
%     error_identifier, error_message   error details when applicable
%
%   Record fields: schema, schema_version, run_id, subject, profile, seq,
%   timestamp_utc, event_type, stage_id, stage_index, stage_count, status,
%   outcome, message, source, job_id, error_identifier, error_message; diagnostic
%   records add level and kind. Absent optional values are written as JSON null.
%   stage_count is 10 for every stage record. Diagnostic records carry no stage
%   identity: stage_id, stage_index, status and outcome are always null, so the
%   stage reader never presents them. Stage and run records keep their schema.
%
%   seq is one more than the number of line feeds already in the file, so it is
%   strictly increasing and unique for the life of the run file. A partial
%   trailing record (for example after a crash) is closed with a line feed
%   before the new record, so every record starts on its own line; the closed
%   fragment keeps its sequence slot and is skipped by readers.
%
%   Single writer: exactly one process appends to a run file at a time. No
%   lock is taken.
%
%   Advisory I/O: nothing here throws. An invalid request or failed write
%   returns OK=false and warns once per MATLAB session; the scientific caller
%   continues unchanged. No secret-bearing field is recorded: only the fixed
%   fields above exist, and free text is redacted with the run-log pattern.
%   UTC timestamps come from java.util.Date/SimpleDateFormat set to UTC, so
%   they do not depend on the machine time zone. Minimum supported MATLAB: R2010b.

ok = false;
try
    if ~local_valid_target(target) || ~local_valid_record(rec)
        local_warn_once();
        return;
    end
    path = target.path;
    [n_lines, partial_tail] = local_scan(path);
    line = local_record(n_lines + 1, target, rec);
    fid = fopen(path, 'a');
    if fid == -1
        local_warn_once();
        return;
    end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    if partial_tail
        fprintf(fid, '\n');
    end
    fprintf(fid, '%s\n', line);
    ok = true;
catch %#ok<CTCH>
    local_warn_once();
    ok = false;
end
end

function valid = local_valid_target(target)
valid = false;
if ~isstruct(target) || numel(target) ~= 1 || ...
        ~isfield(target, 'path') || ~isfield(target, 'run_id')
    return;
end
valid = ischar(target.path) && size(target.path, 1) == 1 && ...
    ~isempty(target.path) && ischar(target.run_id) && ...
    size(target.run_id, 1) == 1 && ~isempty(target.run_id);
end

function valid = local_valid_record(rec)
valid = false;
if ~isstruct(rec) || numel(rec) ~= 1
    return;
end
text_fields = {'event_type'; 'stage_id'; 'status'; 'outcome'; 'message'; ...
    'source'; 'job_id'; 'error_identifier'; 'error_message'; 'level'; 'kind'};
for ii = 1:length(text_fields)
    if isfield(rec, text_fields{ii}) && ~isempty(rec.(text_fields{ii})) && ...
            ~(ischar(rec.(text_fields{ii})) && size(rec.(text_fields{ii}), 1) == 1)
        return;
    end
end
event_type = local_text(rec, 'event_type', 'stage');
status = local_text(rec, 'status', '');
outcome = local_text(rec, 'outcome', '');
stage_id = local_text(rec, 'stage_id', '');
source = local_text(rec, 'source', '');
job_id = local_text(rec, 'job_id', '');
if ~any(strcmp(event_type, {'stage'; 'run'; 'diagnostic'})) || ...
        ~any(strcmp(status, {''; 'STARTED'; 'COMPLETED'; 'FAILED'; 'SKIPPED'})) || ...
        ~any(strcmp(outcome, {''; 'SUCCEEDED'; 'FAILED'; 'CANCELLED'})) || ...
        ~any(strcmp(source, {'local-orchestrator'; 'payload'; 'mlsc-lifecycle'})) || ...
        (~isempty(job_id) && isempty(regexp(job_id, '^[0-9]+$', 'once')))
    return;
end
if strcmp(event_type, 'stage')
    if ~isempty(outcome) || isempty(regexp(stage_id, '^(workflow\.)?[a-z_]+$', 'once'))
        return;
    end
    if isfield(rec, 'stage_index') && ~isempty(rec.stage_index)
        index = rec.stage_index;
        if ~isnumeric(index) || ~isscalar(index) || ~isfinite(index) || ...
                index ~= fix(index) || index < 1 || index > 10
            return;
        end
    end
elseif strcmp(event_type, 'diagnostic')
    % Typed log row: no stage identity, a level and a kind from the fixed sets.
    level = local_text(rec, 'level', '');
    kind = local_text(rec, 'kind', '');
    if ~any(strcmp(level, {'INFO'; 'WARN'; 'ERROR'})) || ...
            ~any(strcmp(kind, {'warning'; 'error'; 'heartbeat'; 'lifecycle'})) || ...
            ~isempty(status) || ~isempty(outcome) || ~isempty(stage_id) || ...
            (isfield(rec, 'stage_index') && ~isempty(rec.stage_index))
        return;
    end
else
    if isempty(outcome) || ~isempty(status)
        return;
    end
end
valid = true;
end

function value = local_text(rec, name, default)
% Callers validate types first (local_valid_record); empty means absent.
value = default;
if isfield(rec, name) && ~isempty(rec.(name))
    value = rec.(name);
end
end

function line = local_record(seq, target, rec)
line = sprintf(['{"schema":"pseudoct.scientific_event","schema_version":1,' ...
    '"run_id":%s,"subject":%s,"profile":%s,"seq":%d,"timestamp_utc":%s,' ...
    '"event_type":%s,"stage_id":%s,"stage_index":%s,"stage_count":%s,' ...
    '"status":%s,"outcome":%s,"message":%s,"source":%s,"job_id":%s,' ...
    '"error_identifier":%s,"error_message":%s}'], ...
    local_json_string(target.run_id, true), ...
    local_json_string(local_field(target, 'subject_id'), true), ...
    local_json_string(local_field(target, 'profile'), true), ...
    seq, local_json_string(local_utc_timestamp(), true), ...
    local_json_string(local_text(rec, 'event_type', 'stage'), false), ...
    local_json_string(local_text(rec, 'stage_id', ''), true), ...
    local_json_index(rec), ...
    local_json_stage_count(rec), ...
    local_json_string(local_text(rec, 'status', ''), true), ...
    local_json_string(local_text(rec, 'outcome', ''), true), ...
    local_json_string(local_limit(local_redact(local_text(rec, 'message', ''))), false), ...
    local_json_string(local_text(rec, 'source', ''), false), ...
    local_json_string(local_text(rec, 'job_id', ''), true), ...
    local_json_string(local_text(rec, 'error_identifier', ''), true), ...
    local_json_string(local_limit(local_redact(local_text(rec, 'error_message', ''))), true));
if strcmp(local_text(rec, 'event_type', 'stage'), 'diagnostic')
    % Diagnostic rows append their two typed fields; stage and run rows are unchanged.
    line = [line(1:end - 1) sprintf(',"level":%s,"kind":%s}', ...
        local_json_string(local_text(rec, 'level', ''), false), ...
        local_json_string(local_text(rec, 'kind', ''), false))];
end
end

function text = local_limit(text)
if length(text) > 240
    text = [text(1:237) '...'];
end
end

function out = local_json_string(text, nullable)
% Empty optional values are JSON null; required text stays a string.
if isempty(text) && nullable
    out = 'null';
else
    out = ['"' pseudo_CT_json_escape(text) '"'];
end
end

function out = local_json_index(rec)
out = 'null';
if isfield(rec, 'stage_index') && ~isempty(rec.stage_index) && ...
        strcmp(local_text(rec, 'event_type', 'stage'), 'stage')
    out = sprintf('%d', rec.stage_index);
end
end

function out = local_json_stage_count(rec)
out = 'null';
if strcmp(local_text(rec, 'event_type', 'stage'), 'stage') && ...
        isfield(rec, 'stage_index') && ~isempty(rec.stage_index)
    out = '10';
end
end

function value = local_field(target, name)
value = '';
if isfield(target, name) && ischar(target.(name)) && ...
        (isempty(target.(name)) || size(target.(name), 1) == 1)
    value = target.(name);
end
end

function text = local_redact(text)
% Same credential pattern as the run-log filter, plus "credential".
text = regexprep(text, ...
    ['(?i)(username|user|password|passphrase|account|token|secret|credential)' ...
    '([ \t]*[:=][ \t]*|[ \t]+)[^ \t,;]+'], '$1$2<redacted>');
end

function timestamp = local_utc_timestamp()
% UTC independent of the machine time zone (Java is available in R2010b).
timestamp = '';
try
    formatter = java.text.SimpleDateFormat( ...
        'yyyy-MM-dd''T''HH:mm:ss.SSS''Z''');
    formatter.setTimeZone(java.util.TimeZone.getTimeZone('UTC'));
    timestamp = char(formatter.format(java.util.Date()));
catch %#ok<CTCH>
    timestamp = '';
end
end

function [n_lines, partial_tail] = local_scan(path)
% Complete records only: each record ends with one line feed.
n_lines = 0;
partial_tail = false;
if exist(path, 'file') ~= 2
    return;
end
fid = fopen(path, 'r');
if fid == -1
    error('pseudo_CT:ScientificEventRead', 'Scientific event file is unreadable.');
end
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, inf, 'uint8');
n_lines = sum(bytes == 10);
partial_tail = ~isempty(bytes) && bytes(end) ~= 10;
end

function local_warn_once()
persistent warned;
if ~isempty(warned)
    return;
end
warned = true;
try
    warning('pseudo_CT:ScientificEventWrite', ...
        'Scientific event record could not be written; processing continues unchanged.');
catch %#ok<CTCH>
end
end
