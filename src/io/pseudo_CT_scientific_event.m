function ok = pseudo_CT_scientific_event(target, stage_id, status, message, job_id)
%PSEUDO_CT_SCIENTIFIC_EVENT Append one scientific boundary record as JSONL.
%   OK = PSEUDO_CT_SCIENTIFIC_EVENT(TARGET, STAGE_ID, STATUS, MESSAGE) appends
%   exactly one complete JSON line to TARGET.path (see
%   pseudo_CT_scientific_event_target). STATUS is STARTED, COMPLETED or FAILED.
%   OK = PSEUDO_CT_SCIENTIFIC_EVENT(..., JOB_ID) also records a scheduler or
%   process id when the caller genuinely has one.
%
%   The file is opened, written and closed per call, so every record is
%   readable as soon as it is emitted and a crash keeps all earlier records.
%   seq is one more than the number of complete lines already in the file;
%   each run has a single writer, so no lock is needed.
%
%   Advisory I/O: nothing here throws. A failed write returns OK=false and
%   warns once per MATLAB session; the scientific call proceeds unchanged.
%
%   Secrets: only the fixed fields below are recorded (no free-form fields), and
%   MESSAGE is redacted with the run-log credential pattern.
%   Minimum supported MATLAB: R2010b.

ok = false;
if nargin < 5 || isempty(job_id)
    job_id = '';
end
try
    if ~local_valid_request(target, stage_id, status, message, job_id)
        return;
    end
    path = target.path;
    seq = local_count_lines(path) + 1;
    line = local_record(seq, target, stage_id, status, message, job_id);
    fid = fopen(path, 'a');
    if fid == -1
        local_warn_once();
        return;
    end
    closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
    fprintf(fid, '%s\n', line);
    ok = true;
catch %#ok<CTCH>
    local_warn_once();
    ok = false;
end
end

function valid = local_valid_request(target, stage_id, status, message, job_id)
valid = false;
if ~isstruct(target) || numel(target) ~= 1 || ~isfield(target, 'path')
    return;
end
if ~ischar(target.path) || size(target.path, 1) ~= 1 || isempty(target.path)
    return;
end
if ~ischar(stage_id) || size(stage_id, 1) ~= 1 || isempty(stage_id)
    return;
end
if ~ischar(status) || ~any(strcmp(status, {'STARTED'; 'COMPLETED'; 'FAILED'}))
    return;
end
valid = ischar(message) && (isempty(message) || size(message, 1) == 1) && ...
    ischar(job_id) && (isempty(job_id) || size(job_id, 1) == 1);
end

function line = local_record(seq, target, stage_id, status, message, job_id)
c = clock;
timestamp = sprintf('%04d-%02d-%02dT%02d:%02d:%06.3f', ...
    c(1), c(2), c(3), c(4), c(5), c(6));
message = local_redact(message);
if length(message) > 240
    message = [message(1:237) '...'];
end
line = sprintf(['{"schema":"pseudoct.scientific_event","schema_version":1,' ...
    '"seq":%d,"timestamp":"%s","run_id":"%s","subject_id":"%s",' ...
    '"profile":"%s","stage_id":"%s","status":"%s","message":"%s",' ...
    '"job_id":"%s"}'], ...
    seq, timestamp, ...
    pseudo_CT_json_escape(local_field(target, 'run_id')), ...
    pseudo_CT_json_escape(local_field(target, 'subject_id')), ...
    pseudo_CT_json_escape(local_field(target, 'profile')), ...
    pseudo_CT_json_escape(stage_id), ...
    pseudo_CT_json_escape(status), ...
    pseudo_CT_json_escape(message), ...
    pseudo_CT_json_escape(job_id));
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

function n = local_count_lines(path)
% Complete records only: each record ends with one line feed.
n = 0;
if exist(path, 'file') ~= 2
    return;
end
fid = fopen(path, 'r');
if fid == -1
    error('pseudo_CT:ScientificEventRead', 'Scientific event file is unreadable.');
end
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes = fread(fid, inf, 'uint8');
n = sum(bytes == 10);
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
