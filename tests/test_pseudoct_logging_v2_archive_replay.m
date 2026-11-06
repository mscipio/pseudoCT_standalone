function test_pseudoct_logging_v2_archive_replay()
%TEST_PSEUDOCT_LOGGING_V2_ARCHIVE_REPLAY Exercise production logging on archives.
%   Requires the retained log-corpus-reconciled-20261104-093540 and
%   launchpad-pbs-recovered-20261104 directories. Set
%   PSEUDOCT_LOGGING_ARCHIVE_ROOT to their common runs/ directory if it is not
%   the sibling tests-datasets tree.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'io'));
old_format = getenv('PSEUDOCT_OUTPUT_FORMAT');
cleanup = onCleanup(@() local_restore_state(old_format)); %#ok<NASGU>
archive_root = getenv('PSEUDOCT_LOGGING_ARCHIVE_ROOT');
if isempty(archive_root)
    archive_root = fullfile(fileparts(root_dir), 'tests-datasets', ...
        'pseudoCT', '3.2.0-refactored', 'pseudoCT_validation', 'runs');
end
corpus = fullfile(archive_root, ...
    'log-corpus-reconciled-20261104-093540');
launchpad = fullfile(archive_root, 'launchpad-pbs-recovered-20261104');
assert(exist(corpus, 'dir') == 7 && exist(launchpad, 'dir') == 7, ...
    ['Archived logging corpus is unavailable. Set ', ...
     'PSEUDOCT_LOGGING_ARCHIVE_ROOT to the common runs/ directory.']);

profiles = {'local-current'; 'local-mprage-only'; 'local-legacy'; ...
    'mlsc-current'; 'mlsc-mprage-only'; 'mlsc-legacy'; 'launchpad-legacy'};
configs = { ...
    struct('mode','local','implementation','current', ...
        'output_policy','nifti-and-dicom','reference_policy','umap-required'); ...
    struct('mode','local','implementation','current', ...
        'output_policy','nifti-only','reference_policy','none'); ...
    struct('mode','local','implementation','legacy-v2', ...
        'output_policy','nifti-and-dicom','reference_policy','umap-required'); ...
    struct('mode','mlsc','implementation','current', ...
        'output_policy','nifti-and-dicom','reference_policy','umap-required'); ...
    struct('mode','mlsc','implementation','current', ...
        'output_policy','nifti-only','reference_policy','none'); ...
    struct('mode','mlsc','implementation','legacy-v2', ...
        'output_policy','nifti-and-dicom','reference_policy','umap-required'); ...
    struct('mode','launchpad','implementation','legacy-v2', ...
        'output_policy','nifti-and-dicom','reference_policy','umap-required')};
% V4: allowlisted parent transitions, INFO children, source-position warning
% groups, explicit preparation skips, and two numbered legacy delegations.
% These are streaming corpus counts (including retained secondary sources),
% not the separately reconciled offline-reference replay counts.
% Repeated warning occurrences are not confirmed duplicate-source messages.
expected_counts = [39 36 120 97 98 126 102];
stage_ids = {'workflow.input_prepare'; 'workflow.recenter'; ...
    'workflow.alias_correct'; 'workflow.normalize'; ...
    'workflow.align_mask'; 'workflow.segment'; 'workflow.dartel'; ...
    'workflow.attenuation_qc'; 'workflow.dicom_output'; ...
    'workflow.full_output_finalize'};

fprintf('PROFILE                 EXPECTED ACTUAL NUMBERED SKIPS DELEGATION RESULT\n');
warning_events = [];
terminal_sample = struct('line', '', 'context', struct(), ...
    'preceding_line', '', 'preceding_context', struct(), ...
    'preceding_event', struct());
exit_zero_sample = struct('line', '', 'context', struct());
representative_text = '';
representative_json = '';
for pi = 1:length(profiles)
    profile = profiles{pi};
    stage_map = pseudo_CT_stage_map(configs{pi});
    assert(stage_map.total == 10, ...
        'The public stage total is not ten for %s.', profile);
    [files, sources] = local_profile_files(corpus, launchpad, profile);
    assert(~isempty(files), 'No archived source logs for %s.', profile);
    if strcmp(profile, 'launchpad-legacy')
        source_list = [sources{:}];
        assert(~isempty(strfind(source_list, '19743725')) && ...
            ~isempty(strfind(source_list, '19743726')), ...
            'Recovered Launchpad jobs 19743725 and 19743726 were not replayed.');
    end

    [text_output, text_events, text_samples] = local_replay_profile( ...
        files, sources, profile, stage_map, 'text');
    [json_output, json_events, json_samples] = local_replay_profile( ...
        files, sources, profile, stage_map, 'jsonl');
    assert(length(text_events) == expected_counts(pi) && ...
        length(json_events) == expected_counts(pi), ...
        'Unexpected event count for %s: expected %d, observed text=%d JSONL=%d.', ...
        profile, expected_counts(pi), length(text_events), length(json_events));
    assert(isequal(text_events, json_events), ...
        'Text and JSONL events differ for %s.', profile);
    local_assert_jsonl(json_output, json_events, profile);
    local_assert_event_stages(json_events, stage_ids, profile);

    skips = local_event_count(json_events, 'event_kind', 'stage_skipped');
    delegations = local_event_count(json_events, 'event_kind', 'delegation');
    if pi == 2 || pi == 5
        assert(skips == 3, ...
            'MPRAGE-only logs must show preparation skips plus the stage-9 skip.');
        archived_skip = local_select_events(json_events, ...
            'event_kind', 'stage_skipped');
        assert(isequal(sort(str2double({archived_skip.stage_number})), [2 3 9]));
        archived_skip = archived_skip(strcmp({archived_skip.stage_number}, '9'));
        assert(strcmp(archived_skip.stage_id, 'workflow.dicom_output') && ...
            strcmp(archived_skip.stage_number, '9') && ...
            strcmp(archived_skip.reason, 'profile_policy:mprage_only'));
    elseif pi == 1 || pi == 4
        assert(skips == 2, 'Current full-mode profiles must retain both preparation skips.');
        archived_skip = local_select_events(json_events, 'event_kind', 'stage_skipped');
        assert(isequal(sort(str2double({archived_skip.stage_number})), [2 3]));
    else
        assert(skips == 0, 'Unexpected archived policy skip for %s.', profile);
    end
    assert(delegations == 2 * ~isempty(strfind(profile, 'legacy')), ...
        'Legacy input completion must expose stages 2 and 3 as INFO delegation, not outcomes.');
    if delegations > 0
        delegated = local_select_events(json_events, 'event_kind', 'delegation');
        assert(isequal(str2double({delegated.stage_number}), [2 3]) && ...
            all(strcmp({delegated.status}, 'INFO')));
    end

    profile_warnings = local_select_events(json_events, 'event_kind', 'warning');
    assert(~isempty(profile_warnings), ...
        'Archived warnings were not classified for %s.', profile);
    for wi = 1:length(profile_warnings)
        assert(~isempty(profile_warnings(wi).source_file) && ...
            ~profile_warnings(wi).live, ...
            'Retrospective warning provenance was lost for %s.', profile);
    end
    if isempty(warning_events)
        warning_events = profile_warnings;
    else
        warning_events = [warning_events profile_warnings]; %#ok<AGROW>
    end

    if isempty(terminal_sample.line) && ~isempty(text_samples.terminal_line)
        terminal_sample.line = text_samples.terminal_line;
        terminal_sample.context = text_samples.terminal_context;
        terminal_sample.preceding_line = text_samples.pre_terminal_line;
        terminal_sample.preceding_context = text_samples.pre_terminal_context;
        terminal_sample.preceding_event = text_samples.pre_terminal_event;
    end
    if isempty(exit_zero_sample.line) && ~isempty(text_samples.exit_zero_line)
        exit_zero_sample.line = text_samples.exit_zero_line;
        exit_zero_sample.context = text_samples.exit_zero_context;
    end
    if strcmp(profile, 'local-current')
        representative_text = text_samples.input_prepare_row;
        representative_json = json_samples.input_prepare_json;
        assert(~isempty(representative_text) && ~isempty(representative_json), ...
            'Representative Local Current output was not captured.');
        assert(~isempty(strfind(text_output, representative_text)) && ...
            ~isempty(strfind(json_output, representative_json)), ...
            'Representative output was not part of production replay output.');
    end

    local_assert_ten_stage_fixture(profile, stage_map, stage_ids);
    fprintf('%-22s %8d %6d %8d %5d %10d PASS\n', profile, ...
        expected_counts(pi), length(json_events), ...
        local_numbered_event_count(json_events), skips, delegations);
end

assert(~isempty(warning_events), 'No archived warning events were exercised.');
fprintf('CASE warnings PASS: archive warnings retain source and retrospective provenance.\n');
local_assert_multiline_warning();
fprintf('CASE multiline warning PASS: ANSI opener is emitted immediately, without future-line aggregation.\n');
local_assert_duplicate_terminal(terminal_sample);
fprintf('CASE duplicate output PASS: repeated orphan completion is not emitted.\n');
local_assert_truncated_tail(terminal_sample);
fprintf('CASE truncated logs PASS: preceding observation is retained, orphan completion is not fabricated.\n');
local_assert_missing_outputs(exit_zero_sample);
fprintf('CASE missing outputs PASS: archived scheduler exit 0 alone is not VERIFIED.\n');
local_assert_failure(terminal_sample, stage_ids);
fprintf('CASE failure PASS: finalization failure is ERROR, never completion.\n');
local_assert_cancellation(terminal_sample);
fprintf('CASE cancellation PASS: cancellation is terminal, not a stage completion.\n');
local_assert_policy_fixtures(profiles, configs, stage_ids);
fprintf('CASE delegation PASS: legacy stages 2 and 3 have separate INFO rows with caller-supplied metadata.\n');
fprintf('CASE MPRAGE skip PASS: archived stage 9 and synthetic stage 9-10 JSON fixtures pass.\n');
fprintf('REPRESENTATIVE_TEXT %s\n', representative_text);
fprintf('REPRESENTATIVE_JSONL %s\n', representative_json);
fprintf('ARCHIVED LOGGING V2 REPLAY: PASS (all seven profiles and deterministic cases).\n');
end

function [rendered, events, samples] = local_replay_profile( ...
        files, sources, profile, stage_map, output_format)
setenv('PSEUDOCT_OUTPUT_FORMAT', output_format);
pseudo_CT_output_console_visible('RESET');
parts = {};
samples = local_empty_samples();
for fi = 1:length(files)
    context = local_context(profile, stage_map, sources{fi});
    input = fopen(files{fi}, 'r');
    assert(input ~= -1, 'Could not read archived source %s.', sources{fi});
    raw = fread(input, inf, '*char')';
    fclose(input);
    [parts, samples] = local_feed_chunked(raw, context, output_format, ...
        parts, samples, false);
end
flush_output = evalc('pseudo_CT_output_console_visible(''FLUSH'');');
if ~isempty(flush_output)
    parts{end + 1} = flush_output; %#ok<AGROW>
end
events = pseudo_CT_output_console_visible('DRAIN_EVENTS');
if isempty(parts)
    rendered = '';
else
    rendered = [parts{:}];
end
end

function [parts, samples] = local_feed_chunked(raw, context, ...
        output_format, parts, samples, discard_incomplete_tail)
chunks = [1 7 19 4 127 31 53];
chunk_index = 1;
position = 1;
buffer = '';
while position <= length(raw)
    last = min(length(raw), position + chunks(chunk_index) - 1);
    buffer = [buffer raw(position:last)]; %#ok<AGROW>
    position = last + 1;
    chunk_index = mod(chunk_index, length(chunks)) + 1;
    while true
        newline = find(buffer == char(10), 1);
        if isempty(newline)
            break;
        end
        line = buffer(1:newline - 1);
        buffer = buffer(newline + 1:end);
        if ~isempty(line) && line(end) == char(13)
            line(end) = [];
        end
        [parts, samples] = local_feed_line(line, context, ...
            output_format, parts, samples);
    end
end
if ~isempty(buffer) && ~discard_incomplete_tail
    [parts, samples] = local_feed_line(buffer, context, ...
        output_format, parts, samples);
end
end

function [parts, samples] = local_feed_line(line, context, ...
        output_format, parts, samples)
if isempty(strtrim(line))
    return;
end
capture = evalc(['[visible, row, event] = ', ...
    'pseudo_CT_output_console_visible(''INFO'', line, context, line);']); %#ok<NASGU>
if ~isempty(capture)
    parts{end + 1} = capture; %#ok<AGROW>
end
if visible && strcmp(output_format, 'text') && ~isempty(row)
    parts{end + 1} = [row char(10)]; %#ok<AGROW>
end
if visible && isfield(event, 'event_kind')
    if isempty(samples.terminal_line) && ...
            strcmp(event.event_kind, 'stage_completed') && ...
            strcmp(event.status, 'DONE')
        samples.terminal_line = line;
        samples.terminal_context = context;
        samples.pre_terminal_line = samples.last_visible_line;
        samples.pre_terminal_context = samples.last_visible_context;
        samples.pre_terminal_event = samples.last_visible_event;
    end
    if isempty(samples.exit_zero_line) && ...
            strcmp(event.event_category, 'scheduler') && ...
            ~isempty(strfind(lower(event.message), 'exit 0'))
        samples.exit_zero_line = line;
        samples.exit_zero_context = context;
    end
    if strcmp(output_format, 'text') && ...
            isempty(samples.input_prepare_row) && ...
            strcmp(event.stage_id, 'workflow.input_prepare') && ...
            strcmp(event.stage_number, '1') && ...
            ~isempty(strfind(row, '[1/10]'))
        samples.input_prepare_row = row;
    elseif strcmp(output_format, 'jsonl') && ...
            isempty(samples.input_prepare_json) && ...
            strcmp(event.stage_id, 'workflow.input_prepare') && ...
            strcmp(event.stage_number, '1') && ~isempty(capture)
        samples.input_prepare_json = strtrim(capture);
    end
    if ~isempty(event.event_kind) && ...
            ~any(strcmp(event.event_kind, {'unavailable'; 'warning'}))
        samples.last_visible_line = line;
        samples.last_visible_context = context;
        samples.last_visible_event = event;
    end
end
end

function [files, sources] = local_profile_files(corpus, launchpad, profile)
files = {};
sources = {};
directories = {'permanent'; 'backend'};
for di = 1:length(directories)
    directory = fullfile(corpus, profile, directories{di});
    entries = dir(directory);
    [~, order] = sort({entries.name});
    entries = entries(order);
    for ei = 1:length(entries)
        if entries(ei).isdir || entries(ei).bytes == 0 || ...
                any(strcmp(entries(ei).name, {'.'; '..'}))
            continue;
        end
        [~, ~, extension] = fileparts(entries(ei).name);
        if ~any(strcmpi(extension, {'.log'; '.out'; '.err'}))
            continue;
        end
        files{end + 1} = fullfile(directory, entries(ei).name); %#ok<AGROW>
        sources{end + 1} = [profile '/' directories{di} '/' ...
            entries(ei).name]; %#ok<AGROW>
    end
end
if strcmp(profile, 'launchpad-legacy')
    entries = dir(launchpad);
    [~, order] = sort({entries.name});
    entries = entries(order);
    for ei = 1:length(entries)
        if entries(ei).isdir || entries(ei).bytes == 0 || ...
                isempty(regexp(entries(ei).name, ...
                '^pbsjob_[0-9]+\.[oe][0-9]+$', 'once'))
            continue;
        end
        files{end + 1} = fullfile(launchpad, entries(ei).name); %#ok<AGROW>
        sources{end + 1} = ['launchpad-pbs-recovered-20261104/' ...
            entries(ei).name]; %#ok<AGROW>
    end
end
end

function context = local_context(profile, stage_map, source_file)
context = struct('console_profile', profile, ...
    'console_run_id', [profile '-archive-replay'], ...
    'console_subject_count', 1, 'subject_index', 1, 'subject_count', 1, ...
    'stage_map', stage_map, 'source', 'permanent', ...
    'source_file', source_file, 'live', false);
if ~isempty(strfind(source_file, '/backend/')) || ...
        ~isempty(strfind(source_file, 'backend/'))
    context.source = 'backend';
elseif ~isempty(strfind(source_file, 'launchpad-pbs-recovered'))
    context.source = 'scheduler';
end
end

function local_assert_jsonl(output, events, profile)
records = local_json_records(output);
assert(length(records) == length(events), ...
    'JSONL row count differs from classifier events for %s.', profile);
blocked = {'MATLAB Version'; 'Stack Trace'; 'Traceback'; ...
    'Environment dump'; 'OPENBLAS_NUM_THREADS'; 'UNCONFIRMED'};
for bi = 1:length(blocked)
    assert(isempty(strfind(output, blocked{bi})), ...
        'Forbidden diagnostic content %s reached JSONL for %s.', ...
        blocked{bi}, profile);
end
for ri = 1:length(records)
    assert(isstruct(records{ri}) && isfield(records{ri}, 'type') && ...
        strcmp(records{ri}.type, 'progress'), ...
        'Invalid production JSONL row for %s.', profile);
end
end

function records = local_json_records(output)
records = {};
lines = regexp(strtrim(output), char(10), 'split');
for li = 1:length(lines)
    if isempty(strtrim(lines{li}))
        continue;
    end
        [value, position] = local_decode_json(lines{li}, 1);
        assert(position == length(lines{li}) + 1, 'Trailing JSON content.');
        records{end + 1} = value; %#ok<AGROW>
end
end

function [value, position] = local_decode_json(text, position)
% R2010b has no jsondecode. Decode the emitted JSON grammar strictly in MATLAB;
% do not involve the Python presentation oracle (or any external process).
while position <= length(text) && isspace(text(position)), position = position + 1; end
assert(position <= length(text), 'Unexpected JSON EOF.');
first = text(position); position = position + 1;
if first == '{'
    value = struct();
    while position <= length(text) && text(position) ~= '}'
        [key, position] = local_decode_json(text, position);
        assert(ischar(key) && text(position) == ':', 'Invalid JSON object key.');
        [item, position] = local_decode_json(text, position + 1);
        value.(key) = item;
        if text(position) ~= ',', break; end
        position = position + 1;
    end
    assert(text(position) == '}', 'Unterminated JSON object.'); position = position + 1;
elseif first == '['
    items = {};
    while position <= length(text) && text(position) ~= ']'
        [item, position] = local_decode_json(text, position);
        items{end + 1} = item; %#ok<AGROW>
        if text(position) ~= ',', break; end
        position = position + 1;
    end
    assert(text(position) == ']', 'Unterminated JSON array.'); position = position + 1;
    value = items;
    if all(cellfun(@isnumeric, items)), value = [items{:}]; end
elseif first == '"'
    value = '';
    while position <= length(text) && text(position) ~= '"'
        code = text(position); position = position + 1;
        if code == char(92)
            assert(position <= length(text));
            escape = text(position); position = position + 1;
            escapes = ['"' char(92) '/bfnrt'];
            decoded = ['"' char(92) '/' char([8 12 10 13 9])];
            slot = find(escapes == escape, 1);
            if escape == 'u'
                assert(position + 3 <= length(text) && ...
                    ~isempty(regexp(text(position:position + 3), '^[0-9a-fA-F]{4}$', 'once')));
                code = char(hex2dec(text(position:position + 3))); position = position + 4;
            else
                assert(~isempty(slot), 'Invalid JSON escape.'); code = decoded(slot);
            end
        else
            assert(double(code) >= 32, 'Unescaped JSON control character.');
        end
        value = [value code]; %#ok<AGROW>
    end
    assert(position <= length(text) && text(position) == '"'); position = position + 1;
else
    position = position - 1;
    token = regexp(text(position:end), ...
        '^(true|false|null|-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?)', 'match', 'once');
    assert(~isempty(token), 'Invalid JSON scalar.');
    if strcmp(token, 'true'), value = true;
    elseif strcmp(token, 'false'), value = false;
    elseif strcmp(token, 'null'), value = [];
    else value = str2double(token);
    end
    position = position + length(token);
end
while position <= length(text) && isspace(text(position)), position = position + 1; end
end

function local_assert_event_stages(events, stage_ids, profile)
for ei = 1:length(events)
    event = events(ei);
    assert(isempty(event.stage_span) || ...
        (strcmp(event.event_kind, 'delegation') && isequal(event.stage_span, [2 3])), ...
        'Unexpected caller-supplied stage span for %s.', profile);
    assert(~strcmp(event.status, 'UNCONFIRMED'), ...
        'UNCONFIRMED was published for %s.', profile);
    if isempty(event.stage_number) || strcmp(event.stage_number, 'unavailable')
        if strcmp(event.event_kind, 'delegation')
            error('Legacy delegation must identify stage 2 or 3 for %s.', profile);
        end
        continue;
    end
    stage_number = str2double(event.stage_number);
    assert(isfinite(stage_number) && stage_number >= 1 && ...
        stage_number <= 10 && stage_number == floor(stage_number), ...
        'Out-of-range stage for %s.', profile);
    assert(strcmp(event.stage_total, '10') && ...
        strcmp(event.stage_id, stage_ids{stage_number}), ...
        'Invalid ten-stage tag for %s.', profile);
end
end

function local_assert_ten_stage_fixture(profile, stage_map, stage_ids)
% Structured in-memory events exercise all ten production tags per profile.
% Legacy profiles reserve 2-3 for delegation; MPRAGE-only skips 9, promotes at 10.
setenv('PSEUDOCT_OUTPUT_FORMAT', 'text');
pseudo_CT_output_console_visible('RESET');
covered = false(1, 10);
emitted = 0;
is_legacy = ~isempty(strfind(profile, 'legacy'));
is_mprage_only = ~isempty(strfind(profile, 'mprage-only'));
for si = 1:10
    if is_legacy && si == 3
        continue;
    end
    context = local_context(profile, stage_map, ...
        ['synthetic/ten-stage-fixture/' profile '.log']);
    context.workflow_event = true;
    if is_legacy && si == 2
        % SYNTHETIC FIXTURE: archives do not prove separate compiled-v2 outcomes.
        context.stage_id = 'workflow.legacy_preprocess_delegated';
        context.operation_id = 'prepare.compiled_preprocess';
        context.event_kind = 'delegation';
        context.event_category = 'preparation';
        context.stage_span = [2 3];
        context.operation_ids = {'prepare.recenter', 'prepare.alias_correct'};
        context.stage_status = 'INFO';
        line = '[2026-11-04 12:00:02] INFO [subject 1/1] Recentering and aliasing delegated to compiled v2 backend.';
        % Legacy stage 2/3 notices are held until stage 4 starts.
        [visible, ~, ~] = local_emit('INFO', line, context);
        assert(~visible);
        covered(2:3) = true;
        emitted = emitted + 2; % numbered stages 2 and 3, no unnumbered duplicate
        continue;
    end
    context.stage_index = si;
    context.stage_count = 10;
    context.stage_id = stage_ids{si};
    context.operation_id = stage_ids{si};
    context.event_category = local_stage_category(si);
    if is_mprage_only && si == 9
        % SYNTHETIC FIXTURE: explicit DICOM bypass; stage 10 is real promotion.
        context.event_kind = 'stage_skipped';
        context.stage_status = 'SKIPPED';
        context.reason = 'profile_policy:mprage_only';
        line = sprintf('[2026-11-04 12:00:%02d] INFO [subject 1/1] Stage %d skipped by MPRAGE-only policy.', si, si);
    else
        context.event_kind = 'stage_started';
        context.stage_status = 'START';
        line = sprintf('[2026-11-04 12:00:%02d] INFO [subject 1/1] Stage %d started.', si, si);
    end
    [visible, row, event] = local_emit('INFO', line, context);
    if si == 5 && ~visible
        % The accepted bounded stage-5 hold applies while stage 4 is open.
        covered(si) = true;
        emitted = emitted + 1;
        continue;
    end
    released_stage5 = si == 6 && strcmp(event.stage_number, '5');
    released_notices = is_legacy && si == 4 && strcmp(event.stage_number, '2');
    assert(visible && (released_stage5 || released_notices || ...
        (strcmp(event.stage_id, stage_ids{si}) && str2double(event.stage_number) == si)) && ...
        strcmp(event.stage_total, '10') && ...
        ~isempty(strfind(row, sprintf('[%d/10]', si))), ...
        'Production text stage tag %d/10 failed for %s.', si, profile);
    if is_mprage_only && si == 9
        assert(strcmp(event.event_kind, 'stage_skipped') && ...
            strcmp(event.status, 'SKIPPED') && ...
            strcmp(event.reason, 'profile_policy:mprage_only'));
    end
    covered(si) = true;
    emitted = emitted + 1;
    if is_legacy && si == 6
        emitted = emitted + 1;   % legacy: inferred DONE(5) precedes ACTIVE(6)
    end
end
events = pseudo_CT_output_console_visible('DRAIN_EVENTS');
local_assert_event_stages(events, stage_ids, profile);
assert(all(covered) && length(events) == emitted, ...
    'Not all ten logical stages were represented once for %s.', profile);
end

function local_assert_duplicate_terminal(sample)
assert(~isempty(sample.line), 'No archived terminal event was captured.');
setenv('PSEUDOCT_OUTPUT_FORMAT', 'text');
pseudo_CT_output_console_visible('RESET');
[first_visible, ~, first_event] = local_emit('INFO', sample.line, sample.context);
[second_visible, ~, ~] = local_emit('INFO', sample.line, sample.context);
events = pseudo_CT_output_console_visible('DRAIN_EVENTS');
% No ACTIVE was replayed after RESET: neither completion has start evidence.
assert(~first_visible && strcmp(first_event.event_kind, 'unavailable') && ...
    ~second_visible && isempty(events), ...
    'Repeated orphan completion was incorrectly admitted.');
end

function local_assert_multiline_warning()
policy = struct('mode','local','implementation','current', ...
    'output_policy','nifti-and-dicom','reference_policy','umap-required');
context = local_context('local-current', pseudo_CT_stage_map(policy), ...
    'synthetic/ansi-multiline-warning.log');
long_token = repmat('x', 1, 180);
opener = ['[2026-11-04 12:00:00] INFO [subject 1/1] ' ...
    char(27) '[31m{Warning: first warning line'];
continuation = '    second line from warning';
% Do not label this fixture "token": credential redaction intentionally hides it.
ending = ['    third line with long value ' long_token '}'];

setenv('PSEUDOCT_OUTPUT_FORMAT', 'text');
pseudo_CT_output_console_visible('RESET');
evalc(['[opener_visible, opener_row] = pseudo_CT_output_console_visible(''INFO'', opener, ', ...
    'context, opener); pseudo_CT_output_console_visible(''INFO'', ', ...
    'continuation, context, continuation); pseudo_CT_output_console_visible(', ...
    '''INFO'', ending, context, ending); ', ...
    'pseudo_CT_output_console_visible(''FLUSH'');']);
events = pseudo_CT_output_console_visible('DRAIN_EVENTS');
assert(length(events) == 1 && strcmp(events(1).event_kind, 'warning') && ...
    strcmp(events(1).timestamp, '2026-11-04 12:00:00') && ...
    strcmp(events(1).original_timestamp, '2026-11-04 12:00:00') && ...
    strcmp(events(1).source_file, 'synthetic/ansi-multiline-warning.log') && ...
    strcmp(events(1).message, 'first warning line') && ...
    opener_visible && ~isempty(strfind(opener_row, 'first warning line')));
% The accepted incremental architecture cannot append future continuation
% lines to an event that has already been emitted (only stage 5 may be held).

setenv('PSEUDOCT_OUTPUT_FORMAT', 'jsonl');
pseudo_CT_output_console_visible('RESET');
json_output = evalc(['pseudo_CT_output_console_visible(''INFO'', opener, ', ...
    'context, opener); pseudo_CT_output_console_visible(''INFO'', ', ...
    'continuation, context, continuation); pseudo_CT_output_console_visible(', ...
    '''INFO'', ending, context, ending); ', ...
    'pseudo_CT_output_console_visible(''FLUSH'');']);
records = local_json_records(json_output);
assert(length(records) == 1 && strcmp(records{1}.message, events(1).message) && ...
    strcmp(records{1}.original_timestamp, '2026-11-04 12:00:00'));
end

function local_assert_truncated_tail(sample)
assert(length(sample.line) > 8, 'Archived terminal fixture is too short.');
assert(~isempty(sample.preceding_line) && ...
    ~isempty(sample.preceding_event.event_kind), ...
    'No complete archived event before the terminal row was captured.');
setenv('PSEUDOCT_OUTPUT_FORMAT', 'text');
pseudo_CT_output_console_visible('RESET');
truncated = sample.line(1:end - 8);
last_tag = find(truncated == ']', 1, 'last');
[preceding_visible, ~, preceding_event] = local_emit('INFO', ...
    sample.preceding_line, sample.preceding_context);
[partial_visible, partial_row, partial_event] = local_emit('INFO', ...
    truncated, sample.context);
% FLUSH closes production warning groups; DRAIN_EVENTS returns records already
% rendered by the production presenter. The presenter receives individual
% lines, so an EOF fragment passed to it is classified/rendered as given.
evalc('pseudo_CT_output_console_visible(''FLUSH'');');
events = pseudo_CT_output_console_visible('DRAIN_EVENTS');
assert(preceding_visible && ...
    strcmp(preceding_event.event_kind, sample.preceding_event.event_kind) && ...
    strcmp(preceding_event.message, sample.preceding_event.message) && ...
    ~partial_visible && strcmp(partial_event.event_kind, 'unavailable') && ...
    isempty(partial_row) && ~isempty(last_tag) && length(events) == 1 && ...
    strcmp(events(1).event_kind, sample.preceding_event.event_kind) && ...
    strcmp(events(1).message, sample.preceding_event.message), ...
    'Production flush lost the preceding event or fabricated an orphan DONE.');
end

function local_assert_missing_outputs(sample)
assert(~isempty(sample.line), ...
    'No archived scheduler exit-0 row was captured for the missing-output case.');
setenv('PSEUDOCT_OUTPUT_FORMAT', 'text');
pseudo_CT_output_console_visible('RESET');
[visible, ~, event] = local_emit('INFO', sample.line, sample.context);
events = pseudo_CT_output_console_visible('DRAIN_EVENTS');
assert(visible && strcmp(event.event_category, 'scheduler') && ...
    ~strcmp(event.status, 'VERIFIED') && length(events) == 1 && ...
    ~strcmp(events(1).event_kind, 'output_verified'), ...
    'Archived scheduler exit 0 was incorrectly treated as output verification.');
end

function local_assert_failure(sample, stage_ids)
assert(~isempty(sample.line), 'No archived line was captured for failure variant.');
policy = struct('mode','local','implementation','current', ...
    'output_policy','nifti-and-dicom','reference_policy','umap-required');
context = local_context('local-current', pseudo_CT_stage_map(policy), ...
    'synthetic/missing-output-failure.log');
context.workflow_event = true;
context.stage_index = 10;
context.stage_count = 10;
context.stage_id = stage_ids{10};
context.operation_id = stage_ids{10};
context.event_kind = 'stage_started';
context.event_category = 'finalization';
context.stage_status = 'START';
% SYNTHETIC VARIANT: mutate the archived successful input row into a failure.
line = regexprep(sample.line, 'SUCCESS', 'ERROR', 'once');
line = regexprep(line, '\[stage[ \t]+[0-9]+/[0-9]+\]', '');
line = regexprep(line, 'Input prepared.*$', ...
    'Output promotion failed because a required output is missing.');
assert(~isempty(strfind(line, 'Output promotion failed')));
setenv('PSEUDOCT_OUTPUT_FORMAT', 'text');
pseudo_CT_output_console_visible('RESET');
[visible, ~, event] = local_emit('ERROR', line, context);
assert(visible && strcmp(event.event_kind, 'failure') && ...
    strcmp(event.status, 'ERROR') && ...
    strcmp(event.stage_id, stage_ids{10}) && ...
    strcmp(event.stage_number, '10'));
end

function local_assert_cancellation(sample)
assert(~isempty(sample.line), 'No archived line was captured for cancellation variant.');
policy = struct('mode','local','implementation','current', ...
    'output_policy','nifti-and-dicom','reference_policy','umap-required');
context = local_context('local-current', pseudo_CT_stage_map(policy), ...
    'synthetic/cancellation.log');
context.event_kind = 'cancelled';
% SYNTHETIC VARIANT: preserve the archived record prefix, replace its outcome.
line = regexprep(sample.line, 'SUCCESS', 'INFO', 'once');
line = regexprep(line, '\[stage[ \t]+[0-9]+/[0-9]+\]', '');
line = regexprep(line, 'Input prepared.*$', 'Run cancelled by user.');
assert(~isempty(strfind(line, 'Run cancelled by user.')));
setenv('PSEUDOCT_OUTPUT_FORMAT', 'text');
pseudo_CT_output_console_visible('RESET');
[visible, ~, event] = local_emit('INFO', line, context);
assert(visible && strcmp(event.event_kind, 'cancelled') && ...
    strcmp(event.status, 'CANCELLED'));
end

function local_assert_policy_fixtures(profiles, configs, stage_ids)
for pi = 1:length(profiles)
    profile = profiles{pi};
    if isempty(strfind(profile, 'mprage-only')) && ...
            isempty(strfind(profile, 'legacy'))
        continue;
    end
    stage_map = pseudo_CT_stage_map(configs{pi});
    if ~isempty(strfind(profile, 'mprage-only'))
        % SYNTHETIC FIXTURE: DICOM is skipped; NIfTI promotion really starts.
        setenv('PSEUDOCT_OUTPUT_FORMAT', 'jsonl');
        pseudo_CT_output_console_visible('RESET');
        for si = 9:10
            context = local_context(profile, stage_map, ...
                ['synthetic/mprage-only/' profile '.log']);
            context.workflow_event = true;
            context.stage_index = si;
            context.stage_count = 10;
            context.stage_id = stage_ids{si};
            context.operation_id = stage_ids{si};
            context.event_kind = 'stage_skipped';
            context.event_category = 'finalization';
            context.stage_status = 'SKIPPED';
            context.reason = 'profile_policy:mprage_only';
            line = sprintf('[2026-11-04 12:02:%02d] INFO [subject 1/1] MPRAGE-only stage %d skipped.', si, si);
            expected_kind = 'stage_skipped'; expected_status = 'SKIPPED';
            if si == 10
                context.event_kind = 'stage_started'; context.stage_status = 'START';
                context.reason = ''; expected_kind = 'stage_started'; expected_status = 'ACTIVE';
                line = '[2026-11-04 12:02:10] INFO [subject 1/1] Promoting final outputs.';
            end
            [visible, ~, event, record] = local_emit_json('INFO', line, context);
            assert(visible && strcmp(event.event_kind, expected_kind) && ...
                strcmp(event.status, expected_status) && ...
                strcmp(event.stage_id, stage_ids{si}) && ...
                str2double(event.stage_number) == si && ...
                ((si == 9 && strcmp(event.reason, 'profile_policy:mprage_only')) || ...
                 (si == 10 && strcmp(event.reason, 'unavailable'))));
            assert(strcmp(record.type, 'progress') && ...
                strcmp(record.event_kind, expected_kind) && ...
                strcmp(record.status, expected_status) && ...
                strcmp(record.stage_id, stage_ids{si}) && ...
                record.stage_number == si && record.stage_total == 10 && ...
                ((si == 9 && strcmp(record.reason, 'profile_policy:mprage_only')) || ...
                 (si == 10 && ~isfield(record, 'reason'))));
        end
        events = pseudo_CT_output_console_visible('DRAIN_EVENTS');
        assert(length(events) == 2 && ...
            strcmp(events(1).stage_number, '9') && ...
            strcmp(events(2).stage_number, '10'));
    else
        % SYNTHETIC FIXTURE: legacy logs lack definitive separate stages 2-3 outcomes.
        setenv('PSEUDOCT_OUTPUT_FORMAT', 'jsonl');
        pseudo_CT_output_console_visible('RESET');
        context = local_context(profile, stage_map, ...
            ['synthetic/legacy-delegation/' profile '.log']);
        context.workflow_event = true;
        context.stage_id = 'workflow.legacy_preprocess_delegated';
        context.operation_id = 'prepare.compiled_preprocess';
        context.event_kind = 'delegation';
        context.event_category = 'preparation';
        context.stage_span = [2 3];
        context.operation_ids = {'prepare.recenter', 'prepare.alias_correct'};
        context.stage_status = 'INFO';
        line = ['[2026-11-04 12:03:00] INFO [subject 1/1] ', ...
            'Recentering and aliasing delegated to compiled v2 backend.'];
        % Held until stage 4 / terminal row / FLUSH; FLUSH releases both notices.
        capture = evalc(['[visible, ~, ~] = ', ...
            'pseudo_CT_output_console_visible(''INFO'', line, context, line);', ...
            'pseudo_CT_output_console_visible(''FLUSH'');']);
        records = local_json_records(capture);
        assert(length(records) == 2);
        record = records{1};
        events = pseudo_CT_output_console_visible('DRAIN_EVENTS');
        event = events(1);
        assert(~visible && length(events) == 2 && ...
            strcmp(event.event_kind, 'delegation') && ...
            strcmp(event.stage_number, '2') && ...
            isequal(event.stage_span, [2 3]) && ...
            isequal(event.operation_ids, ...
                {'prepare.recenter', 'prepare.alias_correct'}));
        assert(strcmp(record.type, 'progress') && ...
            strcmp(record.event_kind, 'delegation') && ...
            isequal(record.stage_span, [2 3]) && ...
            record.stage_number == 2 && record.stage_total == 10);
        assert(strcmp(events(1).stage_number, '2') && ...
            strcmp(events(2).stage_number, '3') && ...
            all(strcmp({events(1:2).status}, 'INFO')));
    end
end

% Synthetic undated warning: never fabricate an original timestamp.
policy = struct('mode','mlsc','implementation','current', ...
    'output_policy','nifti-and-dicom','reference_policy','umap-required');
context = local_context('mlsc-current', pseudo_CT_stage_map(policy), ...
    'synthetic/undated-warning.log');
line = '{Warning: optimizer warning without source time';
setenv('PSEUDOCT_OUTPUT_FORMAT', 'text');
pseudo_CT_output_console_visible('RESET');
evalc('pseudo_CT_output_console_visible(''WARN'', line, context, line);');
evalc('pseudo_CT_output_console_visible(''FLUSH'');');
events = pseudo_CT_output_console_visible('DRAIN_EVENTS');
assert(length(events) == 1 && strcmp(events(1).event_kind, 'warning') && ...
    strcmp(events(1).timestamp, 'null') && ...
    strcmp(events(1).original_timestamp, 'null') && ...
    ~events(1).live && ...
    strcmp(events(1).source_file, 'synthetic/undated-warning.log'));
end

function [visible, row, event, record] = local_emit_json(level, line, context)
capture = evalc('[visible, row, event] = pseudo_CT_output_console_visible(level, line, context, line);'); %#ok<NASGU>
records = local_json_records(capture);
assert(length(records) == 1, 'Structured fixture did not emit exactly one JSONL row.');
record = records{1};
end

function [visible, row, event] = local_emit(level, line, context)
evalc('[visible, row, event] = pseudo_CT_output_console_visible(level, line, context, line);');
end

function category = local_stage_category(stage_number)
if stage_number == 1
    category = 'preparation';
elseif stage_number <= 8
    category = 'scientific';
else
    category = 'finalization';
end
end

function count = local_event_count(events, field_name, value)
count = 0;
for ei = 1:length(events)
    if isfield(events(ei), field_name) && ...
            strcmp(events(ei).(field_name), value)
        count = count + 1;
    end
end
end

function selected = local_select_events(events, field_name, value)
selected = events([]);
for ei = 1:length(events)
    if isfield(events(ei), field_name) && ...
            strcmp(events(ei).(field_name), value)
        selected(end + 1) = events(ei); %#ok<AGROW>
    end
end
end

function count = local_numbered_event_count(events)
count = 0;
for ei = 1:length(events)
    if ~isempty(events(ei).stage_number) && ...
            ~strcmp(events(ei).stage_number, 'unavailable')
        count = count + 1;
    end
end
end

function yes = local_has_public_number(record)
yes = false;
if isfield(record, 'stage_number') && isnumeric(record.stage_number) && ...
        isscalar(record.stage_number) && record.stage_number > 0
    yes = true;
end
end

function samples = local_empty_samples()
samples = struct('terminal_line', '', 'terminal_context', struct(), ...
    'pre_terminal_line', '', 'pre_terminal_context', struct(), ...
    'pre_terminal_event', struct(), 'last_visible_line', '', ...
    'last_visible_context', struct(), 'last_visible_event', struct(), ...
    'exit_zero_line', '', 'exit_zero_context', struct(), ...
    'input_prepare_row', '', 'input_prepare_json', '');
end

function local_restore_state(old_format)
setenv('PSEUDOCT_OUTPUT_FORMAT', old_format);
pseudo_CT_output_console_visible('RESET');
end
