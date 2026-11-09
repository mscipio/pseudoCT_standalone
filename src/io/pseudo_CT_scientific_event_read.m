function [events, state] = pseudo_CT_scientific_event_read(path, state)
%PSEUDO_CT_SCIENTIFIC_EVENT_READ Incremental reader for a run's JSONL event file.
%   [EVENTS, STATE] = PSEUDO_CT_SCIENTIFIC_EVENT_READ(PATH, STATE) returns the
%   stage records appended since STATE, in the struct form consumed by
%   pseudo_CT_present_scientific_events. Start with STATE = [] (or omit it).
%
%   Readers consume only complete newline-terminated lines: bytes after the
%   last line feed are left for the next call, so a trailing partial record
%   (a record still being written) is tolerated and never presented. A complete
%   line that is not a valid record of this schema is skipped and counted in
%   STATE.malformed; it is never presented. Run records (event_type 'run') and
%   stage-less records are read but not presented.
%
%   A missing file yields no events (the run may not have started writing).
%   A file that shrinks below the consumed offset raises
%   pseudo_CT:ScientificEventTruncated; the caller reports it once and stops.
%   Only the fixed schema is parsed (flat object, string/integer/null values);
%   no jsondecode is used. Minimum supported MATLAB: R2010b.

if nargin < 2 || isempty(state)
    state = struct('offset', 0, 'records', 0, 'malformed', 0, 'payload', 0);
end
if ~isfield(state, 'payload')
    state.payload = 0;
end
% COVERED(k) is true once any native record carries canonical stage_index k.
% Stage-less records (for example the worker's prepare/compute phase records)
% never set it, so they never establish stage coverage.
if ~isfield(state, 'covered')
    state.covered = false(1, 10);
end
events = local_empty_events();
if exist(path, 'file') ~= 2
    return;
end
fid = fopen(path, 'r');
if fid == -1
    error('pseudo_CT:ScientificEventRead', 'Scientific event file is unreadable.');
end
closer = onCleanup(@() fclose(fid)); %#ok<NASGU>
fseek(fid, 0, 'eof');
total = ftell(fid);
if total < state.offset
    error('pseudo_CT:ScientificEventTruncated', ...
        'Scientific event file shrank during the run.');
end
if total == state.offset
    return;
end
fseek(fid, state.offset, 'bof');
text = char(fread(fid, total - state.offset, 'uint8')');
last_lf = find(text == char(10), 1, 'last');
if isempty(last_lf)
    return;
end
state.offset = state.offset + last_lf;
lines = regexp(text(1:last_lf), char(10), 'split');
for ii = 1:length(lines) - 1
    [rec, ok] = local_parse_object(lines{ii});
    if ~ok
        state.malformed = state.malformed + 1;
        continue;
    end
    state.records = state.records + 1;
    if isfield(rec, 'source') && strcmp(rec.source, 'payload')
        % Worker-written records (stage-less phase records included). Kept as a
        % diagnostic count only: it does NOT establish stage coverage.
        state.payload = state.payload + 1;
    end
    if local_is_canonical_stage(rec)
        state.covered(rec.stage_index) = true;
    end
    event = local_presenter_event(rec, path);
    if ~isempty(event)
        events(end + 1, 1) = event; %#ok<AGROW>
    end
end
end

function events = local_empty_events()
template = local_template('', 0, '', '', '');
events = repmat(template, 0, 1);
end

function template = local_template(subject, index, title, status, message)
template = struct('subject', subject, ...
    'stage', struct('index', index, 'title', title, 'total', 10), ...
    'status', status, 'message', message, ...
    'source', struct('version', 'native', 'file', ''), ...
    'source_timestamp', '', 'observation_timestamp', '', ...
    'transition_kind', 'explicit');
end

function yes = local_is_canonical_stage(rec)
% Stage record with a canonical index 1..10 (any status).
yes = false;
if ~isfield(rec, 'event_type') || ~strcmp(rec.event_type, 'stage')
    return;
end
if ~isfield(rec, 'stage_index') || ~isnumeric(rec.stage_index) || ...
        ~isscalar(rec.stage_index) || ~isfinite(rec.stage_index)
    return;
end
yes = rec.stage_index >= 1 && rec.stage_index <= 10 && ...
    rec.stage_index == fix(rec.stage_index);
end

function event = local_presenter_event(rec, path)
% Stage records with a canonical index and a directly observed status only.
event = [];
if ~local_is_canonical_stage(rec)
    return;
end
if ~isfield(rec, 'status')
    return;
end
index = rec.stage_index;
if isfield(rec, 'stage_id') && strcmp(rec.stage_id, 'dartel') && ...
        strcmp(rec.status, 'COMPLETED')
    % The DARTEL-only completion is detail, not the end of canonical stage 7
    % (DARTEL + inverse warp + reslice). Only inverse_warp COMPLETED presents
    % stage 7 DONE; the record itself stays in the JSONL.
    return;
end
switch rec.status
    case 'STARTED'
        status = 'START';
    case 'COMPLETED'
        status = 'DONE';
    case 'FAILED'
        status = 'ERROR';
    case 'SKIPPED'
        status = 'SKIPPED';
    otherwise
        return;
end
policy = struct('mode', 'local', ...
    'output_policy', 'nifti-and-dicom', 'reference_policy', 'umap-required');
[~, ~, ~, title] = pseudo_CT_stage_map(policy, index, 10);
event = local_template(rec.subject, index, title, status, rec.message);
event.source.file = path;
% Record source ('payload', 'local-orchestrator', 'mlsc-lifecycle') lets a
% caller drop records whose console line it already prints itself.
if isfield(rec, 'source')
    event.source.version = rec.source;
end
event.observation_timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
end

function [obj, ok] = local_parse_object(line)
% Strict flat-object parser for the writer's schema (no nesting, no arrays).
obj = struct();
ok = false;
n = length(line);
pos = local_skip(line, 1);
if pos > n || line(pos) ~= '{'
    return;
end
pos = local_skip(line, pos + 1);
if pos <= n && line(pos) == '}'
    pos = pos + 1;
else
    while true
        [key, pos, good] = local_string(line, pos);
        if ~good || isempty(regexp(key, '^[a-z_][a-z_0-9]*$', 'once'))
            return;
        end
        pos = local_skip(line, pos);
        if pos > n || line(pos) ~= ':'
            return;
        end
        pos = local_skip(line, pos + 1);
        if pos > n
            return;
        end
        if line(pos) == '"'
            [value, pos, good] = local_string(line, pos);
            if ~good
                return;
            end
        elseif pos + 3 <= n && strcmp(line(pos:pos + 3), 'null')
            value = '';
            pos = pos + 4;
        else
            token = regexp(line(pos:end), '^-?[0-9]+', 'match', 'once');
            if isempty(token)
                return;
            end
            value = str2double(token);
            pos = pos + length(token);
        end
        obj.(key) = value;
        pos = local_skip(line, pos);
        if pos > n
            return;
        end
        if line(pos) == ','
            pos = local_skip(line, pos + 1);
        elseif line(pos) == '}'
            pos = pos + 1;
            break;
        else
            return;
        end
    end
end
pos = local_skip(line, pos);
ok = (pos == n + 1);
end

function pos = local_skip(line, pos)
while pos <= length(line) && any(line(pos) == ' ')
    pos = pos + 1;
end
end

function [text, pos, ok] = local_string(line, pos)
% Parses one JSON string starting at LINE(POS) == '"'. Raw control characters
% are invalid JSON; \uXXXX escapes decode to their 16-bit code unit.
text = '';
ok = false;
n = length(line);
if pos > n || line(pos) ~= '"'
    return;
end
pos = pos + 1;
while pos <= n
    c = line(pos);
    if c == '"'
        pos = pos + 1;
        ok = true;
        return;
    elseif c == '\'
        if pos + 1 > n
            return;
        end
        e = line(pos + 1);
        switch e
            case '"'
                text = [text '"']; pos = pos + 2;
            case '\'
                text = [text '\']; pos = pos + 2;
            case '/'
                text = [text '/']; pos = pos + 2;
            case 'n'
                text = [text char(10)]; pos = pos + 2;
            case 'r'
                text = [text char(13)]; pos = pos + 2;
            case 't'
                text = [text char(9)]; pos = pos + 2;
            case 'b'
                text = [text char(8)]; pos = pos + 2;
            case 'f'
                text = [text char(12)]; pos = pos + 2;
            case 'u'
                if pos + 5 > n || isempty(regexp(line(pos + 2:pos + 5), '^[0-9a-fA-F]{4}$', 'once'))
                    return;
                end
                text = [text char(hex2dec(line(pos + 2:pos + 5)))]; %#ok<AGROW>
                pos = pos + 6;
            otherwise
                return;
        end
    elseif double(c) < 32
        return;
    else
        text = [text c]; %#ok<AGROW>
        pos = pos + 1;
    end
end
end
