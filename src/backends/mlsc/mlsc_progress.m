function [first, second] = mlsc_progress(action, arg1, arg2)
%MLSC_PROGRESS Per-submission progress protocol and incremental reader.
%   Each MLSC submission owns one exact tiny progress artifact derived from
%   its non-secret correlation identity:
%       fullfile(SHARED_TEMP, '.mlsc_progress_<correlation-id>')
%   and contains only tiny deterministic machine-readable records, one per
%   line, each terminated by LF ('\n'):
%   The legacy fixed name fullfile(SHARED_TEMP, '.mlsc_progress') is retained
%   only for harmless best-effort cleanup of preserved-temp prior runs and
%   must never be consumed for the current submission.
%       stage_in|done
%       normalize|start
%       normalize|done
%       pseudoCT|start
%       pseudoCT|done
%       verify|start
%       verify|done
%       copy_back|start
%       copy_back|done
%   A writer appends each reachable milestone at most once in reachable
%   execution order.  The normalize pair is optional and appears only when
%   normalization is actually run.  Records contain no paths, credentials,
%   job metadata, or any other free-form content.  The correlation suffix
%   contains only [A-Za-z0-9_.-] (1-64 chars): no username, account, path,
%   host key, or other secret-bearing content is ever in the filename.
%
%   Usage:
%       NAME = MLSC_PROGRESS('filename')
%       RECORDS = MLSC_PROGRESS('records')
%       PATH = MLSC_PROGRESS('path', SHARED_TEMP)
%       NAME = MLSC_PROGRESS('filename_for', CORRELATION_ID)
%       PATH = MLSC_PROGRESS('path_for', SHARED_TEMP, CORRELATION_ID)
%       CURSOR = MLSC_PROGRESS('init')
%       CURSOR = MLSC_PROGRESS('cursor')
%       [EVENTS, CURSOR] = MLSC_PROGRESS('consume', PROGRESS_PATH, CURSOR)
%       [EVENTS, CURSOR] = MLSC_PROGRESS('read', PROGRESS_PATH, CURSOR)
%
%   T004 current milestones (bounded, same engine, no second poller):
%       preparation|done (bundled prepare wrote handoff)
%       alias_recenter|done (alias/recenter selection resolved)
%       alignment_mask|done, segmentation|done, bone|done,
%       dartel_warp_reslice|done (compute sub-stages, emitted after
%       compute success before pseudoCT|done)
%       attenuation_qc|done (attenuation + QC outputs verified)
%   Legacy emits only the original nine records; current emits the
%   extended set in reachable order. Only exact enumerated records are
%   ever emitted, consumed, archived, or displayed.
%
%   CURSOR is a struct with fields OFFSET (double byte offset already
%   consumed), PENDING (char row of incomplete trailing bytes preserved for
%   the next read), and EMITTED (cell column of already-emitted milestones
%   in emission order).  PENDING is an internal byte fragment and must never
%   be displayed or logged.
%
%   CONSUME reads only bytes after CURSOR.OFFSET, prepends CURSOR.PENDING,
%   splits on LF, and emits only complete recognized records in append
%   order, each once across incremental reads.  A trailing fragment without
%   a terminating LF is preserved as PENDING for the next read.  A missing,
%   delayed, truncated, unreadable, partial, malformed, duplicated, unknown,
%   or secret-bearing input is silently tolerated: CONSUME returns no events
%   for such input and never throws for file conditions.  Only an exact
%   enumerated record is ever emitted; every other line is ignored without
%   echoing its content in outputs or errors.
%
%   Minimum supported MATLAB: R2010b.

if nargin < 1 || isempty(action)
    error('pseudo_CT:MLSCProgressAction', ...
        'An MLSC progress action is required.');
end
if ~ischar(action) || size(action, 1) ~= 1
    error('pseudo_CT:MLSCProgressAction', ...
        'The MLSC progress action must be text.');
end
if nargin < 2
    arg1 = [];
end
if nargin < 3
    arg2 = [];
end

if strcmp(action, 'filename')
    first = '.mlsc_progress';
    second = [];
    return;
end
if strcmp(action, 'records')
    first = local_records();
    second = [];
    return;
end
if strcmp(action, 'path')
    first = local_progress_path(arg1);
    second = [];
    return;
end
if strcmp(action, 'filename_for')
    first = local_filename_for(arg1);
    second = [];
    return;
end
if strcmp(action, 'path_for')
    first = local_progress_path_for(arg1, arg2);
    second = [];
    return;
end
if strcmp(action, 'init') || strcmp(action, 'cursor')
    first = local_init_cursor();
    second = [];
    return;
end
if strcmp(action, 'consume') || strcmp(action, 'read')
    [first, second] = local_consume(arg1, arg2);
    return;
end
error('pseudo_CT:MLSCProgressAction', ...
    'The MLSC progress action is unknown.');
end

function records = local_records()
records = {'stage_in|done'; 'preparation|done'; 'alias_recenter|done'; ...
    'normalize|start'; 'normalize|done'; 'alignment_mask|done'; ...
    'segmentation|done'; 'bone|done'; 'dartel_warp_reslice|done'; ...
    'pseudoCT|start'; 'pseudoCT|done'; 'attenuation_qc|done'; ...
    'verify|start'; 'verify|done'; 'copy_back|start'; 'copy_back|done'};
end

function progress_path = local_progress_path(shared_temp)
if ~ischar(shared_temp) || size(shared_temp, 1) ~= 1 || ...
        isempty(shared_temp) || any(shared_temp == char(0))
    error('pseudo_CT:MLSCProgressPath', ...
        'A shared subject temp is required for the MLSC progress path.');
end
progress_path = fullfile(shared_temp, '.mlsc_progress');
end

function filename = local_filename_for(correlation_id)
if ~local_is_correlation_id(correlation_id)
    error('pseudo_CT:MLSCProgressCorrelation', ...
        'A non-secret MLSC correlation identity is required.');
end
filename = ['.mlsc_progress_' correlation_id(:)'];
filename = reshape(filename, 1, numel(filename));
end

function progress_path = local_progress_path_for(shared_temp, correlation_id)
if ~ischar(shared_temp) || size(shared_temp, 1) ~= 1 || ...
        isempty(shared_temp) || any(shared_temp == char(0))
    error('pseudo_CT:MLSCProgressPath', ...
        'A shared subject temp is required for the MLSC progress path.');
end
filename = local_filename_for(correlation_id);
progress_path = fullfile(shared_temp, filename);
end

function valid = local_is_correlation_id(value)
valid = false;
try
    if ~ischar(value) || size(value, 1) ~= 1 || isempty(value)
        return;
    end
    if any(value == char(0))
        return;
    end
    if length(value) < 1 || length(value) > 64
        return;
    end
    if isempty(regexp(value, '^[A-Za-z0-9_.-]+$', 'once'))
        return;
    end
    valid = true;
catch %#ok<CTCH>
    valid = false;
end
end

function cursor = local_init_cursor()
cursor = struct();
cursor.offset = 0;
cursor.pending = '';
cursor.emitted = cell(0, 1);
end

function cursor = local_normalize_cursor(candidate)
cursor = local_init_cursor();
if ~isstruct(candidate) || numel(candidate) ~= 1
    return;
end
if isfield(candidate, 'offset')
    value = candidate.offset;
    if isnumeric(value) && isscalar(value) && isfinite(value) && ...
            value >= 0 && value == floor(value)
        cursor.offset = double(value);
    end
end
if isfield(candidate, 'pending')
    value = candidate.pending;
    if ischar(value) && (isempty(value) || size(value, 1) == 1)
        cursor.pending = reshape(value, 1, numel(value));
    end
end
if isfield(candidate, 'emitted')
    value = candidate.emitted;
    if iscell(value)
        keep = cell(0, 1);
        for ii = 1:numel(value)
            if ischar(value{ii}) && local_is_record(value{ii}) && ...
                    ~local_contains(keep, value{ii})
                keep{end + 1, 1} = value{ii}; %#ok<AGROW>
            end
        end
        cursor.emitted = keep;
    end
end
end

function [events, cursor] = local_consume(progress_path, candidate)
cursor = local_normalize_cursor(candidate);
events = cell(0, 1);
if ~ischar(progress_path) || size(progress_path, 1) ~= 1 || ...
        isempty(progress_path) || any(progress_path == char(0))
    return;
end
if exist(progress_path, 'file') ~= 2
    return;
end
fid = fopen(progress_path, 'rb');
if fid == -1
    return;
end
new_bytes = uint8([]);
try
    if fseek(fid, 0, 'eof') ~= 0
        fclose(fid);
        return;
    end
    file_size = ftell(fid);
    if file_size < 0
        fclose(fid);
        return;
    end
    start_offset = cursor.offset;
    if start_offset > double(file_size)
        start_offset = 0;
    end
    if fseek(fid, start_offset, 'bof') ~= 0
        fclose(fid);
        return;
    end
    if double(file_size) > start_offset
        raw = fread(fid, Inf, '*uint8');
        if ~isempty(raw)
            new_bytes = uint8(raw(:)');
        end
    end
    fclose(fid);
catch %#ok<CTCH>
    try
        fclose(fid);
    catch %#ok<CTCH>
    end
    return;
end
new_text = '';
if ~isempty(new_bytes)
    new_text = char(new_bytes(:)');
    new_text = reshape(new_text, 1, numel(new_text));
end
combined = [cursor.pending new_text];
lines = cell(0, 1);
start = 1;
for ii = 1:length(combined)
    if combined(ii) == char(10)
        if ii > start
            lines{end + 1, 1} = combined(start:(ii - 1)); %#ok<AGROW>
        else
            lines{end + 1, 1} = ''; %#ok<AGROW>
        end
        start = ii + 1;
    end
end
pending = '';
if start <= length(combined)
    pending = combined(start:end);
end
cursor.pending = reshape(pending, 1, numel(pending));
cursor.offset = double(file_size);
for ii = 1:size(lines, 1)
    line = lines{ii, 1};
    if ~isempty(line) && line(end) == char(13)
        line(end) = '';
    end
    if local_is_record(line) && ~local_contains(cursor.emitted, line)
        events{end + 1, 1} = line; %#ok<AGROW>
        cursor.emitted{end + 1, 1} = line;
    end
end
end

function recognized = local_is_record(line)
recognized = strcmp(line, 'stage_in|done') || ...
    strcmp(line, 'preparation|done') || ...
    strcmp(line, 'alias_recenter|done') || ...
    strcmp(line, 'normalize|start') || ...
    strcmp(line, 'normalize|done') || ...
    strcmp(line, 'alignment_mask|done') || ...
    strcmp(line, 'segmentation|done') || ...
    strcmp(line, 'bone|done') || ...
    strcmp(line, 'dartel_warp_reslice|done') || ...
    strcmp(line, 'pseudoCT|start') || ...
    strcmp(line, 'pseudoCT|done') || ...
    strcmp(line, 'attenuation_qc|done') || ...
    strcmp(line, 'verify|start') || ...
    strcmp(line, 'verify|done') || ...
    strcmp(line, 'copy_back|start') || ...
    strcmp(line, 'copy_back|done');
end

function found = local_contains(list, value)
found = false;
for ii = 1:numel(list)
    if strcmp(list{ii}, value)
        found = true;
        return;
    end
end
end
