function [visible, console_line, event_record] = pseudo_CT_output_console_visible(level, message, varargin)
%PSEUDO_CT_OUTPUT_CONSOLE_VISIBLE Format concise fixed-width live progress.
%   The detailed run-log record is written unchanged by PSEUDO_CT_OUTPUT.
%   DRAIN_EVENTS returns structured records for rows already presented;
%   fields are level, subject, stage, status, job, message, and timestamp.
%   Missing values use the internal 'unavailable' marker; JSONL omits unknown
%   optional context fields. Minimum MATLAB: R2010b.

persistent state;
event_record = local_unavailable_event();
if nargin > 0 && ischar(level) && ...
        any(strcmpi(level, {'DRAIN_EVENTS'; 'EVENTS'}))
    if isempty(state)
        state = local_initial_state();
    end
    visible = state.event_records;
    state.event_records = local_empty_events();
    console_line = '';
    return;
end
if nargin > 0 && ischar(level) && strcmpi(level, 'RESET')
    state = [];
    visible = false;
    console_line = '';
    return;
end
if nargin > 0 && ischar(level) && strcmpi(level, 'FLUSH')
    if isempty(state)
        state = local_initial_state();
    end
    if local_is_presenter_profile(state.active_profile)
        state = local_flush_pending_warnings(state, -1, -1);
        state = local_flush_all_warnings(state);
    end
    state.truncated_warning = struct('subject', {}, 'stage', {});
    visible = false;
    console_line = '';
    return;
end
if isempty(state)
    state = local_initial_state();
end

visible = false;
console_line = '';
level = upper(strtrim(level));
context = struct();
source_line = '';
if nargin >= 3 && isstruct(varargin{1})
    context = varargin{1};
end
if nargin >= 4 && ischar(varargin{2})
    source_line = varargin{2};
end
if isempty(source_line) && ischar(message)
    source_line = message;
end
if ~ischar(message)
    return;
end

[record_prefix, body, record_level] = local_split_record(source_line);
if ~isempty(record_level)
    level = record_level;
elseif isempty(record_prefix)
    body = message;
end
body = local_clean_line(body);
source_line = local_clean_line(source_line);
source_time = local_record_time(source_line);
[explicit_stage, explicit_stage_total] = ...
    local_stage_marker(source_line, context);
body = local_strip_context_tags(body);

% Canonical Local Current events (emitted by the orchestrator/adapter) carry
% their own public stage (stage_index/stage_count) and a semantic status
% (stage_status: START, DONE, SKIPPED, INFO, WARN, ERROR, LOG) and an
% optional display text (stage_message). The presenter only formats them.
canonical_status = '';
canonical_message = '';
if isfield(context, 'stage_status') && ischar(context.stage_status)
    canonical_status = upper(strtrim(context.stage_status));
end
if isfield(context, 'stage_message') && ischar(context.stage_message)
    canonical_message = context.stage_message;
end
if strcmp(canonical_status, 'LOG')
    return;  % detail belongs to the run log only
end

% Recover stable subject identity from either the explicit MATLAB context or
% the tagged orchestration record. Compiled output inherits the caller's
% subject context from the local backend monitor.
subject_index = [];
subject_count = [];
run_scope = false;
if isfield(context, 'scope') && ischar(context.scope) && ...
        strcmp(context.scope, 'run')
    run_scope = true;
elseif ~isempty(strfind(source_line, '[run]'))
    run_scope = true;
end
if isfield(context, 'subject_index') && ~isempty(context.subject_index)
    subject_index = context.subject_index;
end
if isfield(context, 'subject_count') && ~isempty(context.subject_count)
    subject_count = context.subject_count;
end
[tag_index, tag_count] = local_subject_tag(source_line);
if isempty(subject_index)
    subject_index = tag_index;
end
if isempty(subject_count)
    subject_count = tag_count;
end
if ~isempty(subject_index)
    state.current_subject = subject_index;
elseif ~isempty(tag_index)
    state.current_subject = tag_index;
elseif isempty(state.current_subject)
    state.current_subject = [];
end
if isempty(subject_index)
    subject_index = state.current_subject;
end
if run_scope
    subject_index = [];
end

% Set the active profile at its existing orchestration emission point. The
% run context supplies header metadata without adding any log text.
profile_match = regexp(lower(strtrim(body)), ...
    '^profile:[ \t]*([^;, \t]+)', 'tokens', 'once');
if isfield(context, 'console_profile') && ischar(context.console_profile)
    profile_name = context.console_profile;
elseif ~isempty(profile_match)
    profile_name = profile_match{1};
else
    profile_name = '';
end
run_id = '';
if isfield(context, 'console_run_id') && ischar(context.console_run_id)
    run_id = context.console_run_id;
end
new_run = ~isempty(profile_name) && ~strcmp(profile_name, state.active_profile);
if ~isempty(run_id)
    if isempty(state.active_run_id)
        % Subject-scoped output can establish the profile before run metadata
        % arrives. Adopt the first run ID without resetting the printed header.
        state.active_run_id = run_id;
    elseif ~strcmp(run_id, state.active_run_id)
        new_run = true;
    end
end
if new_run
    if local_is_presenter_profile(state.active_profile)
        state = local_flush_pending_warnings(state, -1, -1);
        state = local_flush_all_warnings(state);
    end
    state = local_reset_run_state(state, profile_name, run_id);
end
if ~isempty(profile_match) && isempty(state.active_profile)
    state = local_reset_run_state(state, profile_match{1}, run_id);
end
% Local Current: a raw [stage N/M] whose total is not an orchestration total
% (9 or 10) is a compiled-child counter (for example the stage 6/8 of a child
% WARN). It never becomes a public stage; the event keeps the active
% canonical stage carried by its context, or no stage.
if strcmp(state.active_profile, 'local-current') && explicit_stage > 0 && ...
        ~any(explicit_stage_total == [9 10])
    [explicit_stage, explicit_stage_total] = local_stage_marker('', context);
    if ~any(explicit_stage_total == [9 10])
        explicit_stage = 0;
        explicit_stage_total = 0;
    end
end

warning_start = ~isempty(regexp(lower(strtrim(body)), ...
    '^[{ \t]*warning[ \t]*:', 'once'));
severity_probe = lower(strtrim(body));
if warning_start || ~isempty(regexp(severity_probe, ...
        '^[^a-z]*(warning|error)[ \t]*:', 'once')) || ...
        strncmp(severity_probe, '??? error', 9)
    if warning_start || ~isempty(strfind(severity_probe, 'warning'))
        level = 'WARN';
    else
        level = 'ERROR';
    end
end

% Multiline warning continuations have no event prefix. Keep each warning
% isolated by subject and active stage; any typed/timestamped or otherwise
% recognizable event closes pending warning text before it is processed.
event_subject = subject_index;
if isempty(event_subject)
    event_subject = state.current_subject;
end
if run_scope || isempty(event_subject)
    event_subject = 0;
end
% Do not inherit the previous stage into an untagged event's output record.
event_stage = 0;
event_stage_total = 0;
if explicit_stage > 0
    event_stage = explicit_stage;
    event_stage_total = explicit_stage_total;
    if event_subject > 0
        [state, event_slot] = local_subject_slot(state, event_subject);
        state.subject_stages(event_slot) = explicit_stage;
        state.subject_stage_totals(event_slot) = explicit_stage_total;
    else
        state.run_stage = explicit_stage;
        state.run_stage_total = explicit_stage_total;
    end
end
truncated_slot = local_truncated_warning_slot(state, event_subject, event_stage);
if ~isempty(truncated_slot)
    is_continuation = local_is_warning_continuation(state.active_profile, ...
        level, body, record_prefix, record_level, source_time);
    if is_continuation
        if ~isempty(strfind(body, '}'))
            state = local_remove_truncated_warning(state, truncated_slot);
        end
        return;
    end
    state = local_remove_truncated_warning(state, truncated_slot);
end
if ~isempty(state.pending_warning)
    pending_slot = local_pending_warning_slot(state, event_subject, event_stage);
    is_continuation = local_is_warning_continuation(state.active_profile, ...
        level, body, record_prefix, record_level, source_time);
    if is_continuation && ~isempty(pending_slot)
        state = local_flush_pending_warnings_except(state, pending_slot);
        pending_slot = local_pending_warning_slot(state, ...
            event_subject, event_stage);
        pending_text = state.pending_warning(pending_slot).text;
        line_count = state.pending_warning(pending_slot).lines + 1;
        closes_warning = ~isempty(strfind(body, '}'));
        if line_count > 32
            entry = state.pending_warning(pending_slot);
            state = local_flush_pending_warnings(state, event_subject, event_stage);
                state = local_emit_truncated_warning_notice(state, entry);
                if ~closes_warning
                    state = local_mark_truncated_warning(state, ...
                        entry.subject, entry.stage, entry.stage_total);
            end
            return;
        end
        continuation_text = strtrim(body);
        available_chars = max(0, 4096 - length(pending_text) - 1);
        overflow = length(continuation_text) > available_chars;
        if overflow
            continuation_text = continuation_text(1:available_chars);
        end
        if available_chars == 0
            appended_text = pending_text;
        else
            appended_text = [pending_text ' ' continuation_text];
        end
        state.pending_warning(pending_slot).text = appended_text;
        state.pending_warning(pending_slot).lines = line_count;
        if closes_warning || overflow
            if overflow
                state.pending_warning(pending_slot).text = ...
                    [state.pending_warning(pending_slot).text ...
                     ' [warning text truncated at console buffer limit]'];
            end
            entry = state.pending_warning(pending_slot);
            state = local_flush_pending_warnings(state, event_subject, event_stage);
            if overflow
                state = local_emit_truncated_warning_notice(state, entry);
                if ~closes_warning
                    state = local_mark_truncated_warning(state, ...
                        entry.subject, entry.stage, entry.stage_total);
                end
            end
        end
        return;
    end
    state = local_flush_pending_warnings(state, -1, -1);
end
if state.warning_group_active && strcmp(level, 'WARN') && ~warning_start && ...
        local_is_warning_stack_line(body)
    % Stack frames remain in the scientific log but are not useful as
    % independent routine-console warnings.
    return;
end
if warning_start
    state.warning_group_active = true;
elseif ~strcmp(level, 'WARN')
    state.warning_group_active = false;
end

if local_is_presenter_profile(state.active_profile)
    % Header is emitted once at the Profile event, before any subject starts.
    if ~state.header_printed && (~isempty(profile_match) || ...
            isfield(context, 'console_profile'))
        state = local_print_header(state, context, subject_count, source_time);
    end
    if ~state.header_printed && local_is_presenter_profile(state.active_profile)
        % A replay without a Profile context can still establish count from
        % its first tagged subject event. Production always supplies metadata.
        if ~isempty(subject_count)
            state = local_print_header(state, context, subject_count, source_time);
        end
    end

    if ~state.header_printed
        return;
    end

    if local_is_mlsc_profile(state.active_profile)
        [~, ~, ~, kind, display_body] = ...
            local_classify_mlsc(level, body);
    else
        [~, ~, ~, kind, display_body] = ...
            local_classify_local(state.active_profile, level, body);
    end
    unstructured_child = isfield(context, 'console_unstructured') && ...
        isequal(context.console_unstructured, true);
    [kind, display_body] = local_apply_canonical_status( ...
        canonical_status, canonical_message, kind, display_body);
    if strcmp(state.active_profile, 'local-current')
        % A compiled-child [stage N/8] tag inside the text is never public.
        display_body = regexprep(display_body, ...
            '\[stage[ \t]+[0-9]+/8\][ \t]*', '', 'ignorecase');
    end
    if isempty(kind) && explicit_stage > 0 && strcmp(level, 'INFO') && ...
            ~unstructured_child
        kind = 'active';
        display_body = body;
    end

    if isempty(kind)
        state = local_flush_all_warnings(state);
        return;
    end

    if isempty(subject_index)
        event_subject = 'RUN';
        state_stage = 0;
        subject_slot = [];
    else
        event_subject = sprintf('S%02d', subject_index);
        [state, subject_slot] = local_subject_slot(state, subject_index);
        state_stage = state.subject_stages(subject_slot);
    end

    warning_subject = 0;
    if ~isempty(subject_index)
        warning_subject = subject_index;
    end
    warning_stage = event_stage;
    warning_stage_total = event_stage_total;
    if warning_start || any(strcmp(kind, {'qform'; 'provenance'}))
        [state, repeated_warning] = local_track_repeated_warning(state, ...
            warning_subject, warning_stage, warning_stage_total, kind, ...
            display_body, source_time, local_event_job(context));
        % Defer the concise warning until the warning block ends so repeats
        % are represented by one line and a count. The raw details are still
        % appended to the scientific log by PSEUDO_CT_OUTPUT.
        if repeated_warning || warning_start || ...
                any(strcmp(kind, {'qform'; 'provenance'}))
            return;
        end
    end
    state = local_flush_all_warnings(state);

    if isempty(subject_slot)
        state_stage = state.run_stage;
        state_stage_total = state.run_stage_total;
    else
        state_stage = state.subject_stages(subject_slot);
        state_stage_total = state.subject_stage_totals(subject_slot);
    end

    if local_is_local_profile(state.active_profile) && ...
            ~isempty(subject_slot) && state.subject_failed(subject_slot) && ...
            any(strcmp(kind, {'stage'; 'active'; 'milestone'; 'done'; 'skipped'}))
        return;
    end

    % Compiled-child milestones are subordinate, unnumbered steps; the raw
    % [N/M] tag stays in the detailed log and diagnostics.
    % Local Current orchestration is explicitly [stage N/9]; a line whose own
    % tag carries the compiled internal total (8) is a compiled-child event.
    % Decided by the explicit total and profile, never by message text.
    if strcmp(state.active_profile, 'local-current') && explicit_stage > 0
        % Public stage is carried by the event itself: the console cell is
        % printed on stage entry only; the event record always keeps it.
        if isempty(subject_index)
            row_subject = 0;
        else
            row_subject = subject_index;
        end
        [state, event_stage, record_stage] = local_stage_cells(state, ...
            row_subject, explicit_stage, explicit_stage_total);
    else
        compiled_counter = explicit_stage > 0 && explicit_stage_total == 8 && ...
            strcmp(state.active_profile, 'local-current');
        if unstructured_child || compiled_counter
            event_stage = '';
        else
            event_stage = local_event_stage(explicit_stage, explicit_stage_total);
        end
        record_stage = event_stage;
    end

    if strcmp(kind, 'error') && ~isempty(subject_slot)
        state.subject_failed(subject_slot) = true;
    elseif strcmp(kind, 'run-failed')
        state.subject_failed(:) = true;
    end

    if any(strcmp(kind, {'done'; 'subject-end'; 'run-end'}))
        if isempty(subject_index)
            completion_subject = 0;
        else
            completion_subject = subject_index;
        end
        completion_stage = state_stage;
        % Progress can arrive from both the live milestone reader and a
        % buffered backend log. Those aliases may carry different stage
        % tags even though they report the same completion; de-duplicate by
        % subject and canonical display message, not by transport stage.
        completion_key = sprintf('%d|%s', completion_subject, ...
            lower(strtrim(display_body)));
        if any(strcmp(state.completed_keys, completion_key))
            return;
        end
        state.completed_keys{end + 1} = completion_key;
    end

    if strcmp(kind, 'error')
        level = 'ERROR';
    elseif strcmp(kind, 'warn')
        level = 'WARN';
    end
    status = local_console_status(kind, level);
    if isempty(status) && strcmp(state.active_profile, 'local-current')
        status = 'INFO';
    end
    display_body = local_sanitize_message(local_format_duration( ...
        strtrim(display_body)));
    if strcmp(kind, 'run-failed')
        display_body = regexprep(display_body, ...
            '^Run completed:', 'Run failed:');
    end
    [event_date, event_clock] = local_event_clock(source_time);
    state = local_emit_date_separator(state, event_date);
    stage_text = event_stage;
    console_line = local_format_row(event_clock, event_subject, ...
        stage_text, status, display_body);
    visible = true;
    event_record = local_event_record(level, event_subject, record_stage, ...
        status, display_body, source_time, local_event_job(context));
    state = local_queue_event(state, event_record);
    if strcmp(getenv('PSEUDOCT_OUTPUT_FORMAT'), 'jsonl')
        local_emit_json_event(event_record);
    end
    if strcmp(kind, 'subject-end') || strcmp(kind, 'run-end')
        if ~isempty(subject_index)
            state = local_flush_warnings(state, subject_index, -1);
        else
            state = local_flush_all_warnings(state);
        end
    end
    return;
end

% Preserve the prior severity behavior for profiles outside the live-output
% set above.
visible = any(strcmp(level, {'WARN'; 'ERROR'; 'SUCCESS'}));
if ~visible && strcmp(level, 'INFO')
    visible = local_nonlocal_milestone(lower(strtrim(body)));
end
if visible
    console_line = local_sanitize_message(source_line);
    event_status = '';
    if any(strcmp(level, {'WARN'; 'ERROR'; 'SUCCESS'}))
        event_status = level;
    end
    event_record = local_event_record(level, event_subject, '', ...
        event_status, local_sanitize_message(body), source_time, ...
        local_event_job(context));
    state = local_queue_event(state, event_record);
    if strcmp(getenv('PSEUDOCT_OUTPUT_FORMAT'), 'jsonl')
        local_emit_json_event(event_record);
    end
end
end

function state = local_initial_state()
state = struct();
state.active_profile = '';
state.active_run_id = '';
state.current_subject = [];
state.run_stage = 0;
state.run_stage_total = 0;
state.subject_indices = [];
state.subject_stages = [];
state.subject_stage_totals = [];
state.subject_failed = [];
state.completed_keys = {};
state.last_date = '';
state.header_printed = false;
state.pending_warning = struct('subject', {}, 'stage', {}, ...
    'stage_total', {}, 'job', {}, 'text', {}, 'time', {}, 'lines', {});
state.truncated_warning = struct('subject', {}, 'stage', {}, ...
    'stage_total', {});
state.warning_repeats = struct('subject', {}, 'stage', {}, ...
    'stage_total', {}, 'job', {}, 'kind', {}, 'text', {}, ...
    'first_time', {}, 'count', {});
state.warning_group_active = false;
state.last_row_key = [-1 -1];
state.event_records = local_empty_events();
end

function state = local_reset_run_state(state, profile_name, run_id)
event_records = local_empty_events();
if isstruct(state) && isfield(state, 'event_records') && ...
        isstruct(state.event_records)
    event_records = state.event_records;
end
state.active_profile = profile_name;
state.active_run_id = run_id;
state.current_subject = [];
state.run_stage = 0;
state.run_stage_total = 0;
state.subject_indices = [];
state.subject_stages = [];
state.subject_stage_totals = [];
state.subject_failed = [];
state.completed_keys = {};
state.last_date = '';
state.header_printed = false;
state.pending_warning = struct('subject', {}, 'stage', {}, ...
    'stage_total', {}, 'job', {}, 'text', {}, 'time', {}, 'lines', {});
state.truncated_warning = struct('subject', {}, 'stage', {}, ...
    'stage_total', {});
state.warning_repeats = struct('subject', {}, 'stage', {}, ...
    'stage_total', {}, 'job', {}, 'kind', {}, 'text', {}, ...
    'first_time', {}, 'count', {});
state.warning_group_active = false;
state.last_row_key = [-1 -1];
state.event_records = event_records;
end

function [state, slot] = local_subject_slot(state, subject_index)
slot = find(state.subject_indices == subject_index, 1);
if isempty(slot)
    state.subject_indices(end + 1) = subject_index;
    state.subject_stages(end + 1) = 0;
    state.subject_stage_totals(end + 1) = 0;
    state.subject_failed(end + 1) = false;
    slot = length(state.subject_indices);
end
end

function state = local_print_header(state, context, subject_count, source_time)
if state.header_printed || ~local_is_presenter_profile(state.active_profile)
    return;
end
if isfield(context, 'console_subject_count') && ...
        ~isempty(context.console_subject_count)
    subject_count = context.console_subject_count;
end
if isempty(subject_count)
    return;
end
if strcmp(getenv('PSEUDOCT_OUTPUT_FORMAT'), 'jsonl')
    state.header_printed = true;
    return;
end
profile_label = 'Local Current';
if strcmp(state.active_profile, 'local-legacy')
    profile_label = 'Local Legacy';
elseif strcmp(state.active_profile, 'local-mprage-only')
    profile_label = 'Local MPRAGE Only';
elseif local_is_mlsc_profile(state.active_profile)
    profile_label = local_mlsc_profile_label(state.active_profile);
elseif strcmp(state.active_profile, 'launchpad-legacy')
    profile_label = 'Launchpad Legacy';
end
release = ''; %#ok<NASGU>
if isfield(context, 'console_release') && ischar(context.console_release)
    release = context.console_release;
else
    try
        release = version('-release');
    catch %#ok<CTCH>
        release = version;
    end
end
if ~isempty(release) && release(1) ~= 'R'
    release = ['R' release];
end
started = source_time;
if isfield(context, 'console_started_at') && ...
        ischar(context.console_started_at) && ...
        ~isempty(context.console_started_at)
    started = context.console_started_at;
end
if isempty(started)
    started = datestr(now, 'yyyy-mm-dd HH:MM:SS');
end
started = local_normalize_started_at(started);
output_label = ''; %#ok<NASGU>
if isfield(context, 'console_output') && ischar(context.console_output)
    output_label = context.console_output;
elseif strcmp(state.active_profile, 'local-mprage-only')
    output_label = 'NIfTI';
else
    output_label = 'NIfTI+DICOM';
end
header_row = local_format_row('TIME', 'SUBJECT', 'STAGE', 'STATUS', 'MESSAGE');
fprintf(1, 'pseudoCT | %s | MATLAB %s\n', profile_label, release);
fprintf(1, 'Started: %s\n', started);
if local_is_mlsc_profile(state.active_profile)
    fprintf(1, 'Subjects: %d | Backend: MLSC\n', subject_count);
elseif strcmp(state.active_profile, 'launchpad-legacy')
    fprintf(1, 'Subjects: %d | Backend: Launchpad\n', subject_count);
else
    fprintf(1, 'Subjects: %d | Backend: local | Output: %s\n', ...
        subject_count, output_label);
end
fprintf(1, '\n');
fprintf(1, '%s\n', header_row);
fprintf(1, '%s\n', repmat('-', 1, 67));
state.header_printed = true;
if length(started) >= 10
    state.last_date = started(1:10);
end
end

function started = local_normalize_started_at(started)
started = strtrim(started);
if length(started) > 19
    started = started(1:19);
end
end

function [stage_number, stage_total, stage_title, kind, display_body] = ...
        local_classify_local(profile_name, level, body)
text = strtrim(body);
text_lower = lower(text);
stage_number = 0;
stage_total = 0;
stage_title = '';
kind = '';
display_body = text;

if strcmp(level, 'WARN')
    kind = 'warn';
    display_body = local_warning_message(text);
    warning_lower = lower(strtrim(display_body));
    if local_starts_with(warning_lower, ...
            'changelog.md is missing; fallback version provenance was used.')
        kind = 'provenance';
        display_body = 'CHANGELOG.md missing or unavailable; fallback version provenance was used.';
    elseif local_starts_with(warning_lower, ...
            'changelog.md could not be copied; fallback version provenance was used.')
        kind = 'provenance';
        display_body = 'CHANGELOG.md could not be copied; fallback version provenance was used.';
    end
    if local_is_qform_warning(display_body)
        kind = 'qform';
        display_body = 'QFORM0 representation has been rounded.';
    end
    return;
elseif strcmp(level, 'ERROR')
    display_body = local_error_message(text);
    if local_starts_with(text_lower, 'run completed:')
        kind = 'run-failed';
    else
        kind = 'error';
    end
    return;
end

if strcmp(level, 'INFO')
    if local_starts_with(text_lower, 'preparing input mprage')
        kind = 'active';
    elseif any(strcmp(profile_name, {'local-legacy'; 'launchpad-legacy'}))
        if local_starts_with(text_lower, 'launchpad job ') && ...
                ~isempty(strfind(text_lower, ' still active (elapsed '))
            kind = 'heartbeat';
        elseif local_starts_with(text_lower, 'normalizing mprage with freesurfer')
            kind = 'active';
        elseif local_starts_with(text_lower, 'legacy pseudo-ct started')
            kind = 'active';
        elseif local_starts_with(text_lower, 'verifying attenuation map')
            kind = 'active';
        elseif local_starts_with(text_lower, 'applying local post-processing')
            kind = 'active';
        elseif local_starts_with(text_lower, 'writing dicom output')
            kind = 'active';
        elseif local_starts_with(text_lower, 'promoting final outputs')
            kind = 'active';
        elseif local_starts_with(text_lower, 'cleaning up temporary files')
            kind = 'active';
        end
    else
        if local_starts_with(text_lower, 'running compiled current prepare phase') || ...
                local_starts_with(text_lower, 'normalizing mprage with freesurfer')
            kind = 'active';
        elseif local_starts_with(text_lower, 'normalization input already normalized; skipping')
            kind = 'active';
            display_body = 'Normalization skipped (input already normalized).';
        elseif local_starts_with(text_lower, 'aligning mprage and creating subject mask')
            kind = 'active';
        elseif local_starts_with(text_lower, 'running spm new segment') || ...
                local_starts_with(text_lower, 'starting the new segment process')
            kind = 'active';
        elseif local_starts_with(text_lower, 'registering atlases with dartel') || ...
                local_starts_with(text_lower, 'starting the dartel coregistration process')
            kind = 'active';
        elseif local_starts_with(text_lower, 'building attenuation map and qc image')
            kind = 'active';
        elseif local_starts_with(text_lower, 'writing dicom output')
            kind = 'active';
        elseif local_starts_with(text_lower, 'promoting outputs and cleaning up')
            kind = 'active';
        end
    end
    if strcmp(kind, 'active')
        display_body = text;
        return;
    end

    if local_starts_with(text_lower, '[recentering]') || ...
            local_starts_with(text_lower, '[aliasing correction]')
        kind = 'milestone';
    elseif local_starts_with(text_lower, 'applying inverse warp') || ...
            local_starts_with(text_lower, 'reslicing atlases into mprage space')
        kind = 'milestone';
    elseif local_starts_with(text_lower, 'coregistration and reslicing finished')
        kind = 'milestone';
        display_body = 'Coregistration and reslicing finished.';
    elseif local_starts_with(text_lower, 'skipping dicom output by profile policy')
        kind = 'milestone';
    elseif local_starts_with(text_lower, 'legacy pseudo-ct still running (elapsed ')
        kind = 'milestone';
        display_body = regexprep(text, '^Legacy pseudo-CT still running', ...
            'Legacy backend still running');
    elseif local_starts_with(text_lower, 'current processing still running (elapsed ')
        kind = 'milestone';
    elseif ~isempty(regexp(text_lower, ...
            '^done[ \t]+''create inverse warped''', 'once'))
        kind = 'milestone'; display_body = 'Inverse warping completed.';
    elseif local_starts_with(text_lower, 'starting the inverse warped process')
        kind = 'milestone';
    elseif local_starts_with(text_lower, 'starting the final reslicing')
        kind = 'milestone';
    end
    if strcmp(kind, 'milestone') || strcmp(kind, 'done')
        return;
    end
end

if strcmp(level, 'SUCCESS')
    if local_starts_with(text_lower, 'launchpad job submitted')
        kind = 'accepted';
    elseif local_starts_with(text_lower, 'remote processing wait completed')
        kind = 'remote-terminal';
    elseif local_starts_with(text_lower, 'remote outputs retrieved')
        kind = 'retrieved';
    elseif local_starts_with(text_lower, ...
            'all launchpad jobs completed successfully')
        kind = 'run-end';
    elseif local_starts_with(text_lower, 'input prepared (elapsed ')
        kind = 'done';
    elseif local_starts_with(text_lower, 'mprage normalization completed (elapsed ')
        kind = 'done';
    elseif local_starts_with(text_lower, 'legacy pseudo-ct completed (elapsed ')
        kind = 'done';
    elseif local_starts_with(text_lower, 'attenuation map verified (elapsed ')
        kind = 'verified';
    elseif local_starts_with(text_lower, 'local post-processing completed (elapsed ')
        kind = 'done';
    elseif local_starts_with(text_lower, 'alignment and masking completed (elapsed ')
        kind = 'done';
    elseif local_starts_with(text_lower, 'segmentation completed (elapsed ')
        kind = 'done';
    elseif local_starts_with(text_lower, 'atlas registration completed (elapsed ')
        kind = 'done';
    elseif local_starts_with(text_lower, 'attenuation map and qc completed (elapsed ')
        kind = 'done';
    elseif local_starts_with(text_lower, 'dicom output written (elapsed ')
        kind = 'done';
    elseif local_starts_with(text_lower, 'outputs promoted') && ...
            ~isempty(strfind(text_lower, '(elapsed '))
        kind = 'done';
    elseif local_starts_with(text_lower, 'outputs promoted and cleanup completed (elapsed ')
        kind = 'done';
    elseif local_starts_with(text_lower, 'cleanup completed (elapsed ')
        kind = 'done';
    elseif local_starts_with(text_lower, 'subject completed (elapsed ')
        kind = 'subject-end';
    elseif local_starts_with(text_lower, 'run completed:')
        kind = 'run-end';
    elseif local_starts_with(text_lower, 'compiled current compute phase completed (elapsed ')
        % Emitted by the backend only after the child exit status was 0.
        kind = 'done';
    elseif local_starts_with(text_lower, 'compiled current prepare phase completed') || ...
            local_starts_with(text_lower, 'mlsc current compute completed')
        kind = '';
    end
elseif strcmp(level, 'ERROR')
    if local_starts_with(text_lower, 'run completed:')
        kind = 'run-failed';
    else
        kind = 'error';
    end
elseif strcmp(level, 'WARN')
    kind = 'warn';
end
end

function [stage_number, stage_total, stage_title, kind, display_body] = ...
        local_classify_mlsc(level, body)
%LOCAL_CLASSIFY_MLSC Recognize MLSC events without deriving stage numbers.
%   The stage column is taken only from explicit orchestration [stage N/M]
%   markers; scientific milestones remain progress messages.
text = strtrim(body);
text_lower = lower(text);
stage_number = 0;
stage_total = 0;
stage_title = '';
kind = '';
display_body = text;

if strcmp(level, 'WARN')
    kind = 'warn';
    display_body = local_warning_message(text);
    return;
elseif strcmp(level, 'ERROR')
    kind = 'error';
    display_body = local_error_message(text);
    return;
end

if strcmp(level, 'INFO')
    if local_starts_with(text_lower, 'submitting mlsc job') || ...
            local_starts_with(text_lower, ...
            'aligning mprage and creating subject mask') || ...
            local_starts_with(text_lower, 'running spm new segment') || ...
            local_starts_with(text_lower, 'registering atlases with dartel') || ...
            local_starts_with(text_lower, ...
            'building attenuation map and qc image') || ...
            local_starts_with(text_lower, 'writing dicom output') || ...
            local_starts_with(text_lower, 'promoting final outputs') || ...
            local_starts_with(text_lower, 'cleaning up temporary files')
        kind = 'active';
    elseif local_starts_with(text_lower, 'mlsc normalization started') || ...
            local_starts_with(text_lower, 'mlsc copy-back started') || ...
            local_starts_with(text_lower, 'applying inverse warp') || ...
            local_starts_with(text_lower, ...
            'reslicing atlases into mprage space')
        kind = 'milestone';
    elseif ~isempty(regexp(text_lower, ...
            '^mlsc job [0-9]+ accepted\.?$', 'once'))
        kind = 'accepted';
        display_body = regexprep(text, ...
            '(?i)^MLSC job ([0-9]+) accepted\.?$', 'Job $1 accepted.');
    elseif ~isempty(regexp(text_lower, ...
            '^mlsc job [0-9]+ state [a-z_]+\.?$', 'once'))
        kind = 'state';
        display_body = regexprep(text, ...
            '(?i)^MLSC job ([0-9]+) state ([a-z_]+)\.?$', ...
            'Job $1 state: $2.');
    elseif ~isempty(regexp(text_lower, ...
            '^mlsc job [0-9]+ still (running|pending) \(elapsed [0-9:]+\)\.?$', ...
            'once'))
        kind = 'heartbeat';
        display_body = regexprep(text, ...
            '(?i)^MLSC job ([0-9]+) still (running|pending)', ...
            'Job $1 still $2');
    elseif local_starts_with(text_lower, 'mlsc job ')
        kind = 'milestone';
        display_body = regexprep(text, '(?i)^MLSC job ([0-9]+) ', 'Job $1 ');
    end
    return;
elseif strcmp(level, 'SUCCESS')
    if local_starts_with(text_lower, ...
            'mlsc connection and authentication succeeded')
        kind = 'milestone';
    elseif local_starts_with(text_lower, 'mlsc stage-in completed')
        kind = 'milestone'; display_body = 'MLSC stage-in completed.';
    elseif local_starts_with(text_lower, 'mlsc preparation completed')
        kind = 'done'; display_body = 'MLSC preparation completed.';
    elseif local_starts_with(text_lower, 'mlsc alias-recenter completed')
        kind = 'done'; display_body = 'MLSC alias and recenter completed.';
    elseif local_starts_with(text_lower, 'mlsc normalization completed')
        kind = 'done'; display_body = 'MLSC normalization completed.';
    elseif local_starts_with(text_lower, 'alignment and masking completed') || ...
            local_starts_with(text_lower, 'mlsc alignment-mask completed')
        kind = 'done'; display_body = 'Alignment and masking completed.';
    elseif local_starts_with(text_lower, 'segmentation completed') || ...
            local_starts_with(text_lower, 'mlsc segmentation completed')
        kind = 'done'; display_body = 'Segmentation completed.';
    elseif local_starts_with(text_lower, 'mlsc bone completed')
        kind = 'done'; display_body = 'Bone processing completed.';
    elseif local_starts_with(text_lower, 'atlas registration completed') || ...
            local_starts_with(text_lower, ...
            'mlsc dartel-warp-reslice completed')
        kind = 'done'; display_body = 'Atlas registration completed.';
    elseif local_starts_with(text_lower, 'mlsc pseudo-ct completed')
        kind = 'done'; display_body = 'PseudoCT computation completed.';
    elseif local_starts_with(text_lower, ...
            'attenuation map and qc completed') || ...
            local_starts_with(text_lower, 'mlsc attenuation-qc completed')
        kind = 'done'; display_body = 'Attenuation map and QC completed.';
    elseif local_starts_with(text_lower, 'mlsc verification completed')
        kind = 'remote-verified'; display_body = 'MLSC verification completed.';
    elseif local_starts_with(text_lower, ...
            'mlsc verified return to shared temp completed') || ...
            local_starts_with(text_lower, ...
            'mlsc verified return to shared temp for job ')
        kind = 'retrieved'; display_body = 'Verified return to shared temp completed.';
    elseif local_starts_with(text_lower, 'local post-processing completed')
        kind = 'done'; display_body = 'Local post-processing completed.';
    elseif local_starts_with(text_lower, 'dicom output written (elapsed ')
        kind = 'done'; display_body = 'DICOM output written.';
    elseif local_starts_with(text_lower, 'outputs promoted') || ...
            local_starts_with(text_lower, 'cleanup completed (elapsed ')
        kind = 'done'; display_body = text;
    elseif local_starts_with(text_lower, 'mlsc job ')
        if ~isempty(regexp(text_lower, ...
                '^mlsc job [0-9]+ completed exit ', 'once'))
            kind = 'remote-terminal';
        else
            kind = 'done';
        end
        display_body = regexprep(text, '(?i)^MLSC job ([0-9]+) ', 'Job $1 ');
    elseif local_starts_with(text_lower, 'subject completed')
        kind = 'subject-end';
    elseif local_starts_with(text_lower, 'run completed:')
        kind = 'run-end';
    end
elseif strcmp(level, 'ERROR')
    if local_starts_with(text_lower, 'run completed:')
        kind = 'run-failed';
    else
        kind = 'error';
        display_body = local_error_message(text);
    end
end
end

function body = local_warning_message(body)
body = strtrim(body);
body = regexprep(body, ...
    '^[{ \t?]*[Ww][Aa][Rr][Nn][Ii][Nn][Gg][ \t]*:[ \t]*', '');
body = regexprep(body, '[}\t ]+$', '');
if local_starts_with(lower(body), 'version log fallback used: changelog.md not found')
    body = 'CHANGELOG.md is missing; fallback version provenance was used.';
elseif local_starts_with(lower(body), ...
        'version log used fallback content because changelog.md could not be copied')
    body = 'CHANGELOG.md could not be copied; fallback version provenance was used.';
end
end

function body = local_error_message(body)
text_lower = lower(strtrim(body));
if ~isempty(regexp(text_lower, '^[{ \t?]*error[ \t]*:', 'once'))
    body = regexprep(body, '^[{ \t?]*[Ee][Rr][Rr][Oo][Rr]:[ \t]*', '');
elseif local_starts_with(text_lower, '??? error')
    body = strtrim(body(5:end));
end
end

function yes = local_is_qform_warning(body)
yes = ~isempty(regexp(lower(strtrim(body)), ...
    '^qform0 representation has been rounded\.?$', 'once'));
end

function [state, repeated] = local_track_repeated_warning(state, ...
        subject_index, stage_number, stage_total, kind, text, event_time, job)
repeated = false;
for ii = 1:length(state.warning_repeats)
    entry = state.warning_repeats(ii);
    % Per-subject grouping: the stage is not part of the key; the row keeps
    % the stage of the first occurrence.
    if entry.subject == subject_index && ...
            strcmp(entry.job, job) && ...
            strcmp(entry.kind, kind) && strcmp(entry.text, text)
        state.warning_repeats(ii).count = entry.count + 1;
        repeated = true;
        return;
    end
end
entry = struct('subject', subject_index, 'stage', stage_number, ...
    'stage_total', stage_total, 'job', job, 'kind', kind, 'text', text, ...
    'first_time', event_time, 'count', 0);
state.warning_repeats(end + 1) = entry;
end

function state = local_flush_warnings(state, subject_index, stage_number)
if isempty(state.warning_repeats)
    return;
end
keep = true(1, length(state.warning_repeats));
for ii = 1:length(state.warning_repeats)
    entry = state.warning_repeats(ii);
    subject_match = subject_index < 0 || entry.subject == subject_index;
    stage_match = stage_number < 0 || entry.stage == stage_number;
    if subject_match && stage_match
        subject_name = 'RUN';
        if entry.subject > 0
            subject_name = sprintf('S%02d', entry.subject);
        end
        message = entry.text;
        total_occurrences = entry.count + 1;
        if total_occurrences > 1
            message = sprintf('%s (%d occurrences)', ...
                message, total_occurrences);
        end
        emission_time = entry.first_time;
        if isempty(emission_time)
            emission_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
        end
        [event_date, event_clock] = local_event_clock(emission_time);
        state = local_emit_date_separator(state, event_date);
        [state, stage_text, record_stage] = local_flush_stage(state, entry);
        event_line = local_format_row(event_clock, subject_name, stage_text, ...
            'WARN', local_sanitize_message(message));
        record = local_event_record('WARN', subject_name, ...
            record_stage, 'WARN', ...
            local_sanitize_message(message), emission_time, entry.job);
        local_emit_console_event(event_line, record);
        state = local_queue_event(state, record);
        keep(ii) = false;
    end
end
state.warning_repeats = state.warning_repeats(keep);
end

function state = local_flush_all_warnings(state)
state = local_flush_warnings(state, -1, -1);
end

function slot = local_pending_warning_slot(state, subject_index, stage_number)
slot = [];
for ii = 1:length(state.pending_warning)
    if state.pending_warning(ii).subject == subject_index && ...
            state.pending_warning(ii).stage == stage_number
        slot = ii;
        return;
    end
end
end

function slot = local_truncated_warning_slot(state, subject_index, stage_number)
slot = [];
for ii = 1:length(state.truncated_warning)
    if state.truncated_warning(ii).subject == subject_index && ...
            state.truncated_warning(ii).stage == stage_number
        slot = ii;
        return;
    end
end
end

function state = local_mark_truncated_warning(state, subject_index, ...
        stage_number, stage_total)
if isempty(local_truncated_warning_slot(state, subject_index, stage_number))
    entry = struct('subject', subject_index, 'stage', stage_number, ...
        'stage_total', stage_total);
    state.truncated_warning(end + 1) = entry;
end
end

function state = local_remove_truncated_warning(state, slot)
if isempty(slot)
    return;
end
keep = true(1, length(state.truncated_warning));
keep(slot) = false;
state.truncated_warning = state.truncated_warning(keep);
end

function yes = local_is_warning_continuation(profile_name, level, body, ...
        record_prefix, record_level, source_time)
yes = strcmp(level, 'INFO');
if ~yes
    return;
end
text_lower = lower(strtrim(body));
if ~isempty(regexp(text_lower, ...
        '^[{ \t]*(warning|error|success)[ \t]*:', 'once')) || ...
        local_starts_with(text_lower, '??? error') || ...
        local_starts_with(text_lower, 'success ') || ...
        local_starts_with(text_lower, 'done ') || ...
        ~isempty(regexp(text_lower, ...
        '^(run completed|run failed|subject completed|subject failed|run summary|requested [0-9]+, started)', 'once'))
    yes = false;
    return;
end
[~, ~, ~, event_kind, ~] = local_classify_local( ...
    profile_name, 'INFO', body);
if any(strcmp(event_kind, {'stage'; 'active'; 'heartbeat'; ...
        'milestone'; 'done'; ...
        'subject-end'; 'run-end'}))
    yes = false;
end
end

function state = local_flush_pending_warnings(state, subject_index, stage_number)
if isempty(state.pending_warning)
    return;
end
keep = true(1, length(state.pending_warning));
for ii = 1:length(state.pending_warning)
    entry = state.pending_warning(ii);
    subject_match = subject_index < 0 || entry.subject == subject_index;
    stage_match = stage_number < 0 || entry.stage == stage_number;
    if subject_match && stage_match
        state = local_emit_pending_warning(state, entry);
        keep(ii) = false;
    end
end
state.pending_warning = state.pending_warning(keep);
end

function state = local_flush_pending_warnings_except(state, keep_slot)
if isempty(state.pending_warning)
    return;
end
keep = true(1, length(state.pending_warning));
for ii = 1:length(state.pending_warning)
    if ii ~= keep_slot
        state = local_emit_pending_warning(state, state.pending_warning(ii));
        keep(ii) = false;
    end
end
state.pending_warning = state.pending_warning(keep);
end

function state = local_emit_pending_warning(state, entry)
subject_name = 'RUN';
if entry.subject > 0
    subject_name = sprintf('S%02d', entry.subject);
end
[event_date, event_clock] = local_event_clock(entry.time);
state = local_emit_date_separator(state, event_date);
message = local_warning_message(entry.text);
[state, stage_text, record_stage] = local_flush_stage(state, entry);
event_line = local_format_row(event_clock, subject_name, stage_text, 'WARN', ...
    local_sanitize_message(message));
record = local_event_record('WARN', subject_name, ...
    record_stage, 'WARN', ...
    local_sanitize_message(message), entry.time, entry.job);
local_emit_console_event(event_line, record);
state = local_queue_event(state, record);
end

function state = local_emit_truncated_warning_notice(state, entry)
subject_name = 'RUN';
if entry.subject > 0
    subject_name = sprintf('S%02d', entry.subject);
end
[event_date, event_clock] = local_event_clock(entry.time);
state = local_emit_date_separator(state, event_date);
notice = ['Further continuation text of this warning is truncated on the ' ...
    'console; full text remains in the detailed log.'];
[state, stage_text, record_stage] = local_flush_stage(state, entry);
event_line = local_format_row(event_clock, subject_name, stage_text, 'WARN', ...
    local_sanitize_message(notice));
record = local_event_record('WARN', subject_name, ...
    record_stage, 'WARN', ...
    local_sanitize_message(notice), entry.time, entry.job);
local_emit_console_event(event_line, record);
state = local_queue_event(state, record);
end

function state = local_emit_date_separator(state, event_date)
if isempty(event_date)
    return;
end
if ~isempty(state.last_date) && ~strcmp(state.last_date, event_date)
    if ~strcmp(getenv('PSEUDOCT_OUTPUT_FORMAT'), 'jsonl')
        fprintf(1, '--- %s ---\n', event_date);
    end
end
state.last_date = event_date;
end

function [kind, display_body] = local_apply_canonical_status(status, message, kind, display_body)
%LOCAL_APPLY_CANONICAL_STATUS Map an explicit event status to a row kind.
%   No message text is interpreted. WARN/ERROR keep their level-derived kind
%   (warning grouping and QFORM0 de-duplication stay in the usual path).
if isempty(status)
    return;
end
switch status
    case {'START', 'ACTIVE'}
        kind = 'active';
    case 'DONE'
        kind = 'done';
    case 'SKIPPED'
        kind = 'skipped';
    case 'INFO'
        kind = 'milestone';
    otherwise
        return;
end
if ~isempty(message)
    display_body = message;
end
end

function [state, row_stage, record_stage] = local_stage_cells(state, subject, stage_number, stage_total)
%LOCAL_STAGE_CELLS Row cell is non-blank only when the active (subject,
%   stage) differs from the previously presented row; the record is full.
record_stage = local_event_stage(stage_number, stage_total);
key = [subject stage_number];
if isequal(key, state.last_row_key)
    row_stage = '';
else
    row_stage = record_stage;
    state.last_row_key = key;
end
end

function [state, row_stage, record_stage] = local_flush_stage(state, entry)
record_stage = local_event_stage(entry.stage, entry.stage_total);
row_stage = record_stage;
if strcmp(state.active_profile, 'local-current') && entry.stage > 0
    [state, row_stage, record_stage] = local_stage_cells(state, ...
        entry.subject, entry.stage, entry.stage_total);
end
end

function status = local_console_status(kind, level)
status = '';
if strcmp(kind, 'remote-terminal')
    status = 'REMOTE';
elseif strcmp(kind, 'retrieved')
    status = 'RETRIEVED';
elseif strcmp(kind, 'remote-verified')
    status = 'REMOTE_CHECK';
elseif strcmp(kind, 'verified') || ...
        any(strcmp(kind, {'subject-end'; 'run-end'}))
    status = 'VERIFIED';
elseif strcmp(kind, 'done')
    status = 'DONE';
elseif strcmp(kind, 'skipped')
    status = 'SKIPPED';
elseif any(strcmp(kind, {'stage'; 'active'}))
    status = 'ACTIVE';
elseif strcmp(kind, 'accepted')
    status = 'ACCEPT';
elseif strcmp(kind, 'state')
    status = 'STATE';
elseif strcmp(kind, 'heartbeat')
    status = 'WAIT';
elseif any(strcmp(kind, {'warn'; 'provenance'})) || strcmp(level, 'WARN')
    status = 'WARN';
elseif strcmp(kind, 'error') || strcmp(kind, 'run-failed') || ...
        strcmp(level, 'ERROR')
    status = 'ERROR';
end
if strcmp(level, 'ERROR') && strcmp(kind, 'run-end')
    status = 'ERROR';
end
if strcmp(kind, 'run-failed')
    status = 'ERROR';
end
end

function row = local_format_row(time_text, subject_text, stage_text, status_text, message)
row = sprintf('%-8s  %-7s %-8s  %-7s  %s', time_text, subject_text, ...
    stage_text, status_text, message);
end

function [event_date, event_clock] = local_event_clock(source_time)
if isempty(source_time)
    source_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
end
source_time = strtrim(source_time);
if length(source_time) >= 19
    event_date = source_time(1:10);
    event_clock = source_time(12:19);
else
    event_date = datestr(now, 'yyyy-mm-dd');
    event_clock = datestr(now, 'HH:MM:SS');
end
end

function source_time = local_record_time(line)
source_time = '';
match = regexp(line, '^\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\]', ...
    'tokens', 'once');
if ~isempty(match)
    source_time = match{1};
end
end

function [prefix, body, level] = local_split_record(line)
prefix = '';
body = line;
level = '';
if ~ischar(line) || isempty(line) || line(1) ~= '['
    return;
end
timestamp_end = find(line == ']', 1);
if isempty(timestamp_end)
    return;
end
cursor = timestamp_end + 1;
while cursor <= length(line) && (line(cursor) == ' ' || line(cursor) == char(9))
    cursor = cursor + 1;
end
level_start = cursor;
while cursor <= length(line) && line(cursor) ~= ' ' && line(cursor) ~= char(9)
    cursor = cursor + 1;
end
candidate_level = line(level_start:cursor - 1);
if ~any(strcmp(candidate_level, {'INFO'; 'WARN'; 'ERROR'; 'SUCCESS'}))
    return;
end
level = candidate_level;
while cursor <= length(line) && (line(cursor) == ' ' || line(cursor) == char(9))
    cursor = cursor + 1;
end
prefix_end = cursor - 1;
while cursor <= length(line) && line(cursor) == '['
    closing = find(line(cursor:end) == ']', 1);
    if isempty(closing)
        break;
    end
    closing = cursor + closing - 1;
    tag = lower(line(cursor + 1:closing - 1));
    is_context_tag = strncmp(tag, 'subject ', 8) || ...
        strncmp(tag, 'stage ', 6) || strncmp(tag, 'job ', 4) || ...
        any(strcmp(tag, {'run', 'subject', 'mlsc'}));
    if ~is_context_tag
        break;
    end
    prefix_end = closing;
    cursor = closing + 1;
    while cursor <= length(line) && (line(cursor) == ' ' || line(cursor) == char(9))
        prefix_end = cursor;
        cursor = cursor + 1;
    end
end
prefix = line(1:prefix_end);
body = line(prefix_end + 1:end);
end

function [subject_index, subject_count] = local_subject_tag(line)
subject_index = [];
subject_count = [];
match = regexp(line, '\[subject[ \t]+([0-9]+)/([0-9]+)\]', 'tokens', 'once');
if ~isempty(match)
    subject_index = str2double(match{1});
    subject_count = str2double(match{2});
end
end

function [stage_number, stage_total] = local_stage_marker(line, context)
stage_number = 0;
stage_total = 0;
match = regexp(line, '\[stage[ \t]+([0-9]+)/([0-9]+)\]', ...
    'tokens', 'once', 'ignorecase');
if isstruct(context) && isfield(context, 'stage_status') && ...
        isfield(context, 'stage_index') && isfield(context, 'stage_count')
    match = [];  % canonical event: its own public stage is authoritative
end
if ~isempty(match)
    candidate = [str2double(match{1}) str2double(match{2})];
elseif isstruct(context) && isfield(context, 'stage_index') && ...
        isfield(context, 'stage_count') && ...
        isnumeric(context.stage_index) && isscalar(context.stage_index) && ...
        isnumeric(context.stage_count) && isscalar(context.stage_count)
    candidate = [double(context.stage_index) double(context.stage_count)];
else
    return;
end
if all(isfinite(candidate)) && candidate(1) >= 1 && ...
        candidate(1) == floor(candidate(1)) && candidate(2) >= candidate(1) && ...
        candidate(2) == floor(candidate(2))
    stage_number = candidate(1);
    stage_total = candidate(2);
end
end

function body = local_strip_context_tags(body)
while true
    if isempty(body) || body(1) ~= '['
        break;
    end
    closing = find(body == ']', 1);
    if isempty(closing)
        break;
    end
    tag = lower(body(2:closing - 1));
    if ~(strcmp(tag, 'run') || strcmp(tag, 'subject') || ...
            local_starts_with(tag, 'subject ') || ...
            local_starts_with(tag, 'stage ') || ...
            local_starts_with(tag, 'job ') || ...
            local_starts_with(tag, 'mlsc'))
        break;
    end
    body = strtrim(body(closing + 1:end));
end
end

function text = local_clean_line(text)
if ~ischar(text)
    text = '';
    return;
end
keep = (text >= char(32) & text ~= char(127));
text = text(keep);
text = strtrim(text);
end

function text = local_sanitize_message(text)
% Replace DICOM names and paths with stable short identifiers for routine
% console output. PSEUDO_CT_OUTPUT still writes the original source line.
dicom_names = regexp(text, ...
    '(?i)(?:[A-Za-z]:\\|/)?[^ \t,;:()]*\.dcm', 'match');
for ii = 1:length(dicom_names)
    identifier = local_short_hash(dicom_names{ii});
    text = strrep(text, dicom_names{ii}, ['DICOM-' identifier]);
end
% Redact path-shaped tokens only: absolute paths, and relative multi-segment
% tokens with a subject-data directory segment (MR_PET, MR, pseudo_muMAP, tmp)
% or a segment ending in a file extension; keep prose such as
% registration/warping and exactly the approved MR_PET/pseudoct-run-*.log
% disclosure. Mirrors bin/pseudoct.
boundary = '(?<![^\s=''"(\[<,;:])';
text = regexprep(text, [boundary '(?:~|\.{1,2})?/[^ \t,;:()]+'], '<path>');
text = regexprep(text, [boundary ...
    '(?!MR_PET/pseudoct-run-[0-9A-Za-z-]+\.log(?![\w.\-/]))' ...
    '(?=[\w.\-/]*?(?:(?<![\w.\-])(?:MR_PET|MR|pseudo_muMAP|tmp)(?![\w.\-])' ...
    '|\.(?=[0-9]*[A-Za-z])[A-Za-z0-9]{1,5}(?![\w.\-])))' ...
    '[\w.\-]+(?:/[\w.\-]+)+'], '<path>');
text = regexprep(text, '[A-Za-z]:\\[^ \t,;:()]+', '<path>');
text = regexprep(text, ...
    '(?i)(username|user|password|passphrase|account|token|secret)([ \t]*[:=][ \t]*|[ \t]+)[^ \t,;]+', ...
    '$1$2<redacted>');
text = regexprep(text, '[\r\n]+', ' | ');
end

function identifier = local_short_hash(value)
% Compact deterministic display identifier; it is not a security primitive.
hash_value = 5381;
for ii = 1:length(value)
    hash_value = mod(hash_value * 33 + double(value(ii)), 4294967296);
end
identifier = lower(dec2hex(hash_value, 8));
end

function text = local_format_duration(text)
% Convert only explicit reported elapsed values; never infer missing durations.
tokens = regexp(text, '\(elapsed ([0-9]+):([0-9]{2}):([0-9]{2})\)', ...
    'tokens', 'once');
if ~isempty(tokens)
    hours = str2double(tokens{1});
    minutes = str2double(tokens{2});
    seconds = str2double(tokens{3});
    if hours == 0
        total_minutes = minutes;
        text = regexprep(text, '\(elapsed [0-9]+:[0-9]{2}:[0-9]{2}\)', ...
            sprintf('(elapsed %02d:%02d)', total_minutes, seconds), 'once');
    end
end
seconds_tokens = regexp(text, '\(elapsed ([0-9]+(\.[0-9]+)?) s\)', ...
    'tokens', 'once');
if ~isempty(seconds_tokens)
    elapsed_seconds = round(str2double(seconds_tokens{1}));
    hours = floor(elapsed_seconds / 3600);
    minutes = floor(rem(elapsed_seconds, 3600) / 60);
    seconds = rem(elapsed_seconds, 60);
    if hours > 0
        duration = sprintf('%02d:%02d:%02d', hours, minutes, seconds);
    else
        duration = sprintf('%02d:%02d', minutes, seconds);
    end
    text = regexprep(text, '\(elapsed [0-9]+(\.[0-9]+)? s\)', ...
        ['(elapsed ' duration ')'], 'once');
end
end

function yes = local_starts_with(value, prefix)
yes = length(value) >= length(prefix) && ...
    strcmp(value(1:length(prefix)), prefix);
end

function yes = local_is_local_profile(profile_name)
yes = any(strcmp(profile_name, ...
    {'local-current'; 'local-legacy'; 'local-mprage-only'}));
end

function yes = local_is_mlsc_profile(profile_name)
yes = ischar(profile_name) && any(strcmp(profile_name, ...
    {'mlsc-current'; 'mlsc-legacy'; 'mlsc-mprage-only'}));
end

function yes = local_is_presenter_profile(profile_name)
yes = local_is_local_profile(profile_name) || ...
    local_is_mlsc_profile(profile_name) || ...
    (ischar(profile_name) && strcmp(profile_name, 'launchpad-legacy'));
end

function label = local_mlsc_profile_label(profile_name)
if strcmp(profile_name, 'mlsc-legacy')
    label = 'MLSC Legacy';
elseif strcmp(profile_name, 'mlsc-mprage-only')
    label = 'MLSC MPRAGE Only';
else
    label = 'MLSC Current';
end
end

function events = local_empty_events()
events = struct('level', {}, 'subject', {}, 'stage', {}, 'status', {}, ...
    'job', {}, 'message', {}, 'timestamp', {});
end

function event = local_unavailable_event()
event = struct('level', 'unavailable', 'subject', 'unavailable', ...
    'stage', 'unavailable', 'status', 'unavailable', 'job', 'unavailable', ...
    'message', 'unavailable', 'timestamp', 'unavailable');
end

function event = local_event_record(level, subject, stage, status, message, timestamp, job)
if nargin < 7
    job = '';
end
event = local_unavailable_event();
event.level = local_event_value(level);
event.subject = local_event_value(subject);
event.stage = local_event_value(stage);
event.status = local_event_value(status);
event.job = local_event_value(job);
event.message = local_event_value(message);
if ischar(timestamp) && ~isempty(strtrim(timestamp))
    event.timestamp = strtrim(timestamp);
else
    event.timestamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
end
end

function job = local_event_job(context)
job = '';
if ~isstruct(context) || numel(context) ~= 1
    return;
end
if isfield(context, 'job_number')
    candidate = context.job_number;
elseif isfield(context, 'job_id')
    candidate = context.job_id;
else
    return;
end
if isnumeric(candidate) && isscalar(candidate) && isfinite(candidate) && ...
        candidate >= 1 && candidate == floor(candidate)
    job = num2str(candidate, '%.0f');
elseif ischar(candidate) && size(candidate, 1) == 1 && ...
        ~isempty(strtrim(candidate))
    job = strtrim(candidate);
end
end

function value = local_event_value(candidate)
value = 'unavailable';
if ischar(candidate) && size(candidate, 1) == 1 && ...
        ~isempty(strtrim(candidate))
    value = strtrim(candidate);
end
end

function stage = local_event_stage(stage_number, stage_total)
stage = '';
if ~isnumeric(stage_number) || ~isscalar(stage_number) || ...
        ~isfinite(stage_number) || stage_number < 1 || ...
        stage_number ~= floor(stage_number) || ...
        ~isnumeric(stage_total) || ~isscalar(stage_total) || ...
        ~isfinite(stage_total) || stage_total < stage_number || ...
        stage_total ~= floor(stage_total)
    return;
end
stage = sprintf('[%d/%d]', stage_number, stage_total);
end

function state = local_queue_event(state, event)
if ~isstruct(state) || numel(state) ~= 1 || ~isstruct(event) || ...
        numel(event) ~= 1
    return;
end
if ~isfield(state, 'event_records') || ~isstruct(state.event_records)
    state.event_records = local_empty_events();
end
state.event_records(end + 1) = event;
end

function yes = local_nonlocal_milestone(message)
% Narrow legacy recognizers retained for non-local profiles only.
patterns = {'profile:'; 'submitting mlsc'; 'waiting for remote'; ...
    'retrieving remote'; 'launchpad job submitted'; 'all launchpad jobs'; ...
    'run completed:'; 'subject completed'; 'subject failed'};
yes = false;
for ii = 1:length(patterns)
    if local_starts_with(message, patterns{ii})
        yes = true;
        return;
    end
end
end

function yes = local_is_warning_stack_line(text)
text_lower = lower(strtrim(text));
yes = ~isempty(regexp(text_lower, ...
    '^(>+[ \t]*)?in .+ at [0-9]+$', 'once')) || ...
    ~isempty(regexp(text_lower, '^error in .+ at [0-9]+$', 'once'));
end

function local_emit_console_event(line, event_record)
if strcmp(getenv('PSEUDOCT_OUTPUT_FORMAT'), 'jsonl')
    local_emit_json_event(event_record);
else
    fprintf(1, '%s\n', line);
end
end

function local_emit_json_event(event_record)
record = '{"type":"progress"';
fields = {'timestamp'; 'level'; 'subject'; 'stage'; 'status'; 'job'; 'message'};
required = {'timestamp'; 'level'; 'message'};
optional_context = {'subject'; 'stage'; 'status'; 'job'};
for ii = 1:length(fields)
    field_name = fields{ii};
    value = 'unavailable';
    if isstruct(event_record) && isfield(event_record, field_name) && ...
            ischar(event_record.(field_name))
        value = event_record.(field_name);
    end
    missing_context = any(strcmp(optional_context, field_name)) && ...
        any(strcmpi(value, {'null'; 'unavailable'}));
    if isempty(value) || strcmp(value, 'unavailable') || missing_context || ...
            (strcmp(field_name, 'subject') && strcmp(value, 'RUN'))
        if any(strcmp(required, field_name))
            value = '';
        else
            continue;
        end
    end
    record = [record ',"' field_name '":' local_json_quote(value)]; %#ok<AGROW>
end
record = [record '}'];
fprintf(1, '%s\n', record);
end

function encoded = local_json_quote(value)
encoded = '"';
for ii = 1:length(value)
    code = double(value(ii));
    if code == 34
        encoded = [encoded '\"']; %#ok<AGROW>
    elseif code == 92
        encoded = [encoded '\\']; %#ok<AGROW>
    elseif code == 8
        encoded = [encoded '\b']; %#ok<AGROW>
    elseif code == 9
        encoded = [encoded '\t']; %#ok<AGROW>
    elseif code == 10
        encoded = [encoded '\n']; %#ok<AGROW>
    elseif code == 12
        encoded = [encoded '\f']; %#ok<AGROW>
    elseif code == 13
        encoded = [encoded '\r']; %#ok<AGROW>
    elseif code < 32
        encoded = [encoded sprintf('\\u%04x', code)]; %#ok<AGROW>
    else
        encoded = [encoded value(ii)]; %#ok<AGROW>
    end
end
encoded = [encoded '"'];
end
