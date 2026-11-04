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
[explicit_stage, explicit_stage_total, explicit_from_text] = ...
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
if isfield(context, 'stage_map') && local_is_stage_map(context.stage_map)
    state.stage_map = context.stage_map;
end
% Current-lineage local child counters are not public stages. Keep the
% established distinction between their [stage N/8] markers and the fixed
% ten-stage public workflow map.
workflow_direct = isfield(context, 'workflow_event') && ...
    isequal(context.workflow_event, true);
if ~workflow_direct && local_is_current_local_profile(state.active_profile) && explicit_stage > 0 && ...
        ~any(explicit_stage_total == [9 10])
    [explicit_stage, explicit_stage_total] = local_stage_marker('', context);
    explicit_from_text = false;
    if ~any(explicit_stage_total == [9 10])
        explicit_stage = 0;
        explicit_stage_total = 0;
    end
end
% Only context-supplied stage indices are producer numbers that get remapped
% through the policy map. A marker parsed from message text is not a public
% stage under a non-identity map: it keeps its text but gets no stage cell.
stage_cell_blocked = false;
% An MLSC context's [stage] tag is rendered by PSEUDO_CT_OUTPUT from its own
% (already public) stage fields; it is not a producer text marker.
context_tagged = isfield(context, 'stage_index') && ...
    isfield(context, 'stage_count') && local_is_mlsc_profile(state.active_profile);
if ~workflow_direct && explicit_stage > 0 && local_is_stage_map(state.stage_map)
    if explicit_from_text && ~context_tagged && ...
            ~local_is_identity_stage_map(state.stage_map)
        stage_cell_blocked = true;
    else
        [~, mapped_stage, mapped_total] = pseudo_CT_stage_map( ...
            state.stage_map, explicit_stage, explicit_stage_total);
        if mapped_stage > 0
            explicit_stage = mapped_stage;
            explicit_stage_total = mapped_total;
        else
            explicit_stage = 0;
            explicit_stage_total = 0;
            stage_cell_blocked = true;
        end
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
if explicit_stage > 0 && ~stage_cell_blocked
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
    if local_is_remote_profile(state.active_profile)
        % Remote continuation: only an UNTIMED WARN line (forwarded continuation
        % text without its own event timestamp) extends the open warning. A
        % timed row is always its own event: two distinct warnings in the same
        % second stay separate, and scheduler/progress rows never fold into a
        % warning. Identical consecutive rows are grouped later.
        timed_row = isfield(context, 'console_timestamp') && ...
            ~isempty(context.console_timestamp);
        is_continuation = strcmp(level, 'WARN') && ~warning_start && ~timed_row;
    end
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
    if ~isempty(regexp(lower(strtrim(display_body)), ...
            '^(run )?(cancelled|canceled)(\b|[ .,:])|^cancellation requested\b', 'once'))
        kind = 'cancelled';
    end
    if isempty(kind) && explicit_stage > 0 && strcmp(level, 'INFO') && ...
            ~unstructured_child
        kind = 'active';
        display_body = body;
    end
    % A raw [stage N/M] marker inside the message text is never public, for any
    % profile. Only the console and JSONL message are cleaned here; the detailed
    % log is written by PSEUDO_CT_OUTPUT from the original text, unchanged.
    display_body = regexprep(display_body, ...
        '\[stage[ \t]+[0-9]+/[0-9]+\][ \t]*', '', 'ignorecase');

    metadata = local_resolve_event_metadata(state, context, ...
        state.active_profile, kind, display_body, explicit_stage, ...
        explicit_stage_total, source_time);
    if metadata.stage_number > 0
        explicit_stage = metadata.stage_number;
        explicit_stage_total = metadata.stage_total;
        stage_cell_blocked = false;
    elseif workflow_direct
        explicit_stage = 0;
        explicit_stage_total = 0;
        stage_cell_blocked = true;
    end

    if ~workflow_direct && ...
            local_is_legacy_delegated_detail(state.active_profile, display_body) && ...
            ~any(strcmp(kind, {'warn'; 'error'; 'run-failed'; 'cancelled'}))
        % Preserve legacy-child details in the raw log; stages 2-3 have one
        % public delegation event unless authoritative per-operation evidence
        % is provided through structured orchestration metadata.
        state = local_flush_all_warnings(state);
        return;
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
    if local_is_remote_profile(state.active_profile) && strcmp(kind, 'warn') && ...
            ~isempty(source_time)
        % One grouped block per forwarded remote warning, including a timed
        % "{Warning:" block opener (a MATLAB warning wrapped over several lines).
        % Its untimed WARN continuation lines extend it (pending path above); it
        % then joins the repeat path.
        entry = struct('subject', warning_subject, 'stage', event_stage, ...
            'stage_total', event_stage_total, 'job', local_event_job(context), ...
            'text', display_body, 'time', source_time, 'lines', 1, ...
            'source', metadata.source, 'source_file', metadata.source_file, ...
            'event_category', metadata.event_category, ...
            'live', metadata.live, ...
            'original_timestamp', metadata.original_timestamp);
        state.pending_warning(end + 1) = entry;
        return;
    end
    if warning_start || any(strcmp(kind, {'qform'; 'provenance'}))
        [state, repeated_warning] = local_track_repeated_warning(state, ...
            warning_subject, warning_stage, warning_stage_total, kind, ...
            display_body, source_time, local_event_job(context), metadata);
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
    % Remote (MLSC/Launchpad) rows: only public scientific entries carry a stage
    % number. Heartbeats, scheduler/transport/retrieval rows and compiled-child
    % milestones are unnumbered, so no number is reused for another operation.
    remote_unnumbered = local_is_remote_profile(state.active_profile) && ...
        (~any(strcmp(kind, {'active'; 'done'; 'skipped'; 'error'})) || ...
        local_is_remote_child_step(display_body));
    if metadata.stage_number > 0
        if isempty(subject_index)
            row_subject = 0;
        else
            row_subject = subject_index;
        end
        [state, event_stage, record_stage] = local_stage_cells(state, ...
            row_subject, metadata.stage_number, metadata.stage_total);
    elseif stage_cell_blocked || remote_unnumbered
        % Text-parsed producer marker under a non-identity map: no public
        % stage cell in the row or the event record; the message is kept.
        event_stage = '';
        record_stage = '';
    elseif explicit_stage > 0 && local_is_stage_map(state.stage_map)
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
        if unstructured_child
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

    if any(strcmp(kind, {'done'; 'skipped'; 'error'; 'run-failed'; ...
            'cancelled'; 'subject-end'; 'run-end'}))
        if isempty(subject_index)
            completion_subject = 0;
        else
            completion_subject = subject_index;
        end
        % One terminal transition per subject and canonical operation. This
        % also collapses aliases from live polling and buffered backend logs.
        completion_operation = metadata.operation_id;
        if isempty(completion_operation) || ...
                any(strcmp(completion_operation, {'unavailable'; 'event.error'}))
            completion_operation = lower(strtrim(display_body));
        end
        completion_key = sprintf('%d|%s', completion_subject, ...
            lower(strtrim(completion_operation)));
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
    if strcmp(kind, 'cancelled')
        status = 'CANCELLED';
    elseif strcmp(metadata.event_kind, 'output_verified')
        status = 'VERIFIED';
    elseif strcmp(kind, 'subject-end') && ~local_completion_verified(context)
        status = 'INFO';
    elseif strcmp(kind, 'run-end')
        status = 'INFO';
    end
    if isempty(status) && local_is_presenter_profile(state.active_profile)
        status = 'INFO';
    end
    display_body = pseudo_CT_sanitize_message(local_format_duration( ...
        strtrim(display_body)));
    if strcmp(kind, 'run-failed')
        display_body = regexprep(display_body, ...
            '^Run completed:', 'Run failed:');
    end
    [event_date, event_clock] = local_event_clock(source_time, metadata.live);
    state = local_emit_date_separator(state, event_date);
    stage_text = event_stage;
    console_line = local_format_row(event_clock, event_subject, ...
        stage_text, status, display_body);
    visible = true;
    event_record = local_event_record(level, event_subject, record_stage, ...
        status, display_body, source_time, local_event_job(context));
    public_id = metadata.stage_id;
    public_number = metadata.stage_number;
    public_total = metadata.stage_total;
    if isempty(public_id) || strcmp(public_id, 'unavailable')
        [public_id, public_number, public_total] = local_row_public_stage( ...
            state, record_stage, explicit_stage, explicit_stage_total);
    end
    event_record = local_contract_fields(event_record, state, ...
        metadata.event_category, public_id, public_number, public_total, ...
        metadata, context, kind, display_body, source_time);
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
    % No presenter profile is active in this process. The row still goes
    % through the fixed-width table with an explicit STATUS, never as a raw
    % bracket line. SUCCESS is an informational milestone here.
    if strcmp(level, 'WARN')
        event_status = 'WARN';
    elseif strcmp(level, 'ERROR')
        event_status = 'ERROR';
    else
        event_status = 'INFO';
    end
    if event_subject > 0
        fallback_subject = sprintf('S%02d', event_subject);
    else
        fallback_subject = 'RUN';
    end
    [~, fallback_clock] = local_event_clock(source_time);
    console_line = local_format_row(fallback_clock, fallback_subject, '', ...
        event_status, pseudo_CT_sanitize_message(body));
    event_record = local_event_record(level, event_subject, '', ...
        event_status, pseudo_CT_sanitize_message(body), source_time, ...
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
state.stage_map = [];
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
    'stage_total', {}, 'job', {}, 'text', {}, 'time', {}, 'lines', {}, ...
    'source', {}, 'source_file', {}, 'event_category', {}, 'live', {}, ...
    'original_timestamp', {});
state.truncated_warning = struct('subject', {}, 'stage', {}, ...
    'stage_total', {});
state.warning_repeats = struct('subject', {}, 'stage', {}, ...
    'stage_total', {}, 'job', {}, 'kind', {}, 'text', {}, ...
    'first_time', {}, 'count', {}, 'source', {}, 'source_file', {}, ...
    'event_category', {}, 'live', {}, 'original_timestamp', {});
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
state.stage_map = [];
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
    'stage_total', {}, 'job', {}, 'text', {}, 'time', {}, 'lines', {}, ...
    'source', {}, 'source_file', {}, 'event_category', {}, 'live', {}, ...
    'original_timestamp', {});
state.truncated_warning = struct('subject', {}, 'stage', {}, ...
    'stage_total', {});
state.warning_repeats = struct('subject', {}, 'stage', {}, ...
    'stage_total', {}, 'job', {}, 'kind', {}, 'text', {}, ...
    'first_time', {}, 'count', {}, 'source', {}, 'source_file', {}, ...
    'event_category', {}, 'live', {}, 'original_timestamp', {});
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
        kind = 'skipped';
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
        % Scheduler exit status only; not scientific completion (no att_map
        % verification or finalization is implied by this event).
        kind = 'remote-terminal';
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
    if local_starts_with(text_lower, 'submitting mlsc job')
        kind = 'scheduler-submit';
    elseif local_starts_with(text_lower, ...
            'aligning mprage and creating subject mask') || ...
            local_starts_with(text_lower, 'running spm new segment') || ...
            local_starts_with(text_lower, 'registering atlases with dartel') || ...
            local_starts_with(text_lower, ...
            'building attenuation map and qc image') || ...
            local_starts_with(text_lower, 'writing dicom output') || ...
            local_starts_with(text_lower, 'promoting final outputs') || ...
            local_starts_with(text_lower, 'cleaning up temporary files')
        kind = 'active';
    elseif local_starts_with(text_lower, 'skipping dicom output by profile policy')
        kind = 'skipped';
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
    elseif ~isempty(regexp(text_lower, ...
            '^mlsc job [0-9]+ completed exit ', 'once'))
        % Scheduler exit status: recognised by text at any producer level.
        kind = 'remote-terminal';
        display_body = regexprep(text, '(?i)^MLSC job ([0-9]+) ', 'Job $1 ');
    elseif local_starts_with(text_lower, 'mlsc verification completed')
        kind = 'remote-verified'; display_body = 'MLSC verification completed.';
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
        kind = 'done'; display_body = 'MLSC stage-in completed.';
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
        subject_index, stage_number, stage_total, kind, text, event_time, job, metadata)
if nargin < 9 || ~isstruct(metadata)
    metadata = struct();
end
source = local_metadata_text(metadata, 'source', 'orchestrator');
source_file = local_metadata_text(metadata, 'source_file', 'unavailable');
event_category = local_metadata_text(metadata, 'event_category', '');
live = local_metadata_live(metadata);
original_timestamp = local_metadata_text(metadata, 'original_timestamp', event_time);
if isempty(original_timestamp)
    original_timestamp = 'null';
end
repeated = false;
% Rows merge only when they are consecutive and share subject, stage, job,
% kind, and identical message text. Only the immediately preceding grouped
% warning can absorb a repeat; any other warning starts its own entry.
if ~isempty(state.warning_repeats)
    last = length(state.warning_repeats);
    entry = state.warning_repeats(last);
    if entry.subject == subject_index && entry.stage == stage_number && ...
            strcmp(entry.job, job) && strcmp(entry.kind, kind) && ...
            strcmp(entry.text, text) && strcmp(entry.source, source) && ...
            strcmp(entry.source_file, source_file) && ...
            strcmp(entry.event_category, event_category) && entry.live == live
        state.warning_repeats(last).count = entry.count + 1;
        repeated = true;
        return;
    end
end
entry = struct('subject', subject_index, 'stage', stage_number, ...
    'stage_total', stage_total, 'job', job, 'kind', kind, 'text', text, ...
    'first_time', event_time, 'count', 0, 'source', source, ...
    'source_file', source_file, 'event_category', event_category, ...
    'live', live, ...
    'original_timestamp', original_timestamp);
state.warning_repeats(end + 1) = entry;
end

function value = local_metadata_text(metadata, field_name, fallback)
value = fallback;
if isstruct(metadata) && isfield(metadata, field_name) && ...
        ischar(metadata.(field_name)) && ~isempty(metadata.(field_name))
    value = metadata.(field_name);
end
end

function live = local_metadata_live(metadata)
live = true;
if isstruct(metadata) && isfield(metadata, 'live') && ...
        (islogical(metadata.live) || isnumeric(metadata.live)) && ...
        isscalar(metadata.live) && isfinite(double(metadata.live))
    live = logical(metadata.live);
end
end

function context = local_warning_context(entry)
context = struct();
context.source = local_metadata_text(entry, 'source', 'orchestrator');
context.source_file = local_metadata_text(entry, 'source_file', 'unavailable');
context.event_category = local_metadata_text(entry, 'event_category', '');
context.live = local_metadata_live(entry);
context.original_timestamp = local_metadata_text(entry, ...
    'original_timestamp', 'null');
end

function event_time = local_warning_time(entry)
event_time = '';
if isstruct(entry) && isfield(entry, 'time')
    event_time = entry.time;
elseif isstruct(entry) && isfield(entry, 'first_time')
    event_time = entry.first_time;
end
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
        if isempty(emission_time) && entry.live
            emission_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
        end
        [event_date, event_clock] = local_event_clock(emission_time, entry.live);
        state = local_emit_date_separator(state, event_date);
        [state, stage_text, record_stage] = local_flush_stage(state, entry);
        event_line = local_format_row(event_clock, subject_name, stage_text, ...
            'WARN', pseudo_CT_sanitize_message(message));
        record = local_event_record('WARN', subject_name, ...
            record_stage, 'WARN', ...
            pseudo_CT_sanitize_message(message), emission_time, entry.job);
        record = local_warning_record(state, record, entry, record_stage);
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
% A completed grouped remote block joins the repeat path, so an identical block
% is counted and printed once when its warning group closes.
message = local_warning_message(entry.text);
[state, ~] = local_track_repeated_warning(state, entry.subject, ...
    entry.stage, entry.stage_total, 'warn', message, entry.time, entry.job, ...
    local_warning_context(entry));
end

function state = local_emit_truncated_warning_notice(state, entry)
subject_name = 'RUN';
if entry.subject > 0
    subject_name = sprintf('S%02d', entry.subject);
end
[event_date, event_clock] = local_event_clock(entry.time, entry.live);
state = local_emit_date_separator(state, event_date);
notice = ['Further continuation text of this warning is truncated on the ' ...
    'console; full text remains in the detailed log.'];
[state, stage_text, record_stage] = local_flush_stage(state, entry);
event_line = local_format_row(event_clock, subject_name, stage_text, 'WARN', ...
    pseudo_CT_sanitize_message(notice));
record = local_event_record('WARN', subject_name, ...
    record_stage, 'WARN', ...
    pseudo_CT_sanitize_message(notice), entry.time, entry.job);
record = local_warning_record(state, record, entry, record_stage);
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
%   No message text is interpreted. Diagnostics keep their level-derived kind
%   (warning grouping and QFORM0 de-duplication stay in the usual path).
if isempty(status) || any(strcmp(kind, ...
        {'warn'; 'provenance'; 'qform'; 'error'; 'run-failed'}))
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
        if strcmp(kind, 'skipped')
            return;  % a policy skip keeps its explicit SKIPPED status
        end
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
if local_is_stage_map(state.stage_map) && entry.stage > 0
    [state, row_stage, record_stage] = local_stage_cells(state, ...
        entry.subject, entry.stage, entry.stage_total);
end
end

function status = local_console_status(kind, level)
status = '';
if strcmp(kind, 'verified') || ...
        any(strcmp(kind, {'subject-end'; 'run-end'}))
    status = 'VERIFIED';
elseif strcmp(kind, 'done')
    status = 'DONE';
elseif strcmp(kind, 'skipped')
    status = 'SKIPPED';
elseif any(strcmp(kind, {'stage'; 'active'}))
    status = 'ACTIVE';
elseif any(strcmp(kind, {'milestone'; 'accepted'; 'state'; 'heartbeat'; ...
        'remote-terminal'; 'retrieved'; 'remote-verified'; 'scheduler-submit'}))
    status = 'INFO';
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

function yes = local_is_remote_profile(profile_name)
yes = ischar(profile_name) && any(strcmp(profile_name, ...
    {'mlsc-current'; 'mlsc-legacy'; 'mlsc-mprage-only'; 'launchpad-legacy'}));
end

function yes = local_is_remote_child_step(text)
%LOCAL_IS_REMOTE_CHILD_STEP Compiled-child progress forwarded from a remote run.
%   These steps are scientific but not public stages: they never carry a
%   public stage number, so their producer tags cannot collide with one.
text_lower = lower(strtrim(text));
prefixes = {'running spm new segment'; ...
    'aligning mprage and creating subject mask'; ...
    'registering atlases with dartel'; ...
    'building attenuation map and qc image'; ...
    'segmentation completed'; 'mlsc segmentation completed'; ...
    'alignment and masking completed'; 'mlsc alignment-mask completed'; ...
    'mlsc normalization'; 'mlsc alias-recenter'; 'mlsc preparation completed'; ...
    'mlsc stage-in completed'; 'atlas registration completed'; ...
    'mlsc dartel-warp-reslice'; 'attenuation map and qc completed'; ...
    'mlsc attenuation-qc'; 'mlsc bone'; 'mlsc pseudo-ct completed'; ...
    'applying inverse warp'; 'reslicing atlases into mprage space'; ...
    'mlsc copy-back started'};
yes = false;
for ii = 1:length(prefixes)
    if local_starts_with(text_lower, prefixes{ii})
        yes = true;
        return;
    end
end
end

function backend = local_backend_of(profile_name)
backend = 'unavailable';
if ~ischar(profile_name) || isempty(profile_name)
    return;
end
if strncmp(profile_name, 'local-', 6)
    backend = 'local';
elseif strncmp(profile_name, 'mlsc-', 5)
    backend = 'mlsc';
elseif strncmp(profile_name, 'launchpad-', 10)
    backend = 'launchpad';
end
end

function yes = local_contract_applies(profile_name)
%LOCAL_CONTRACT_APPLIES The additive event contract applies to every known
%   profile, including Local Current. The existing JSONL keys are unchanged.
yes = ischar(profile_name) && ~isempty(profile_name) && ...
    ~strcmp(profile_name, 'unavailable');
end

function yes = local_completion_verified(context)
%LOCAL_COMPLETION_VERIFIED True only on the single subject-completion context
%   that the orchestration sets after att_map verification, output promotion,
%   and finalization have all succeeded (never on failed or skipped paths).
yes = isstruct(context) && isscalar(context) && ...
    isfield(context, 'completion_verified') && ...
    isequal(context.completion_verified, true);
end

function metadata = local_resolve_event_metadata(state, context, profile_name, ...
        kind, text, producer_stage, producer_total, source_time)
% Resolve the additive event contract from explicit orchestration metadata or
% recognized production messages. Unknown diagnostic lines never become events.
metadata = struct('event_kind', '', 'operation_id', '', 'stage_id', '', ...
    'stage_number', 0, 'stage_total', 0, 'event_category', '', 'reason', '', ...
    'source', '', 'source_file', '', 'live', true, 'original_timestamp', '', ...
    'stage_span', [], 'operation_ids', {{}});
direct = isstruct(context) && isscalar(context) && ...
    isfield(context, 'workflow_event') && isequal(context.workflow_event, true);

if direct
    if isfield(context, 'stage_index') && isnumeric(context.stage_index) && ...
            isscalar(context.stage_index) && isfinite(context.stage_index) && ...
            context.stage_index >= 1 && context.stage_index <= 10 && ...
            context.stage_index == floor(context.stage_index) && ...
            isfield(context, 'stage_count') && isnumeric(context.stage_count) && ...
            isscalar(context.stage_count) && context.stage_count == 10
        metadata.stage_number = context.stage_index;
        metadata.stage_total = context.stage_count;
    end
    if isfield(context, 'stage_id') && ischar(context.stage_id)
        metadata.stage_id = context.stage_id;
    end
else
    non_workflow_event = any(strcmp(kind, ...
        {'accepted'; 'state'; 'heartbeat'; 'remote-terminal'; 'retrieved'; ...
         'remote-verified'; 'scheduler-submit'}));
    if non_workflow_event
        workflow_number = 0;
        workflow_id = '';
    else
        [workflow_number, workflow_id] = local_workflow_stage_from_text( ...
            profile_name, kind, text);
    end
    if workflow_number > 0
        metadata.stage_number = workflow_number;
        metadata.stage_total = 10;
        metadata.stage_id = workflow_id;
    elseif ~non_workflow_event && ...
            ~local_is_legacy_delegated_detail(profile_name, text) && ...
            producer_stage > 0 && local_is_stage_map(state.stage_map)
        metadata.stage_id = local_public_stage_id(state.stage_map, ...
            producer_stage, producer_total);
        if ~isempty(metadata.stage_id)
            metadata.stage_number = producer_stage;
            metadata.stage_total = producer_total;
        end
    end
end

if isstruct(context) && isscalar(context)
    if isfield(context, 'event_kind') && ischar(context.event_kind)
        metadata.event_kind = context.event_kind;
    end
    if isfield(context, 'event_category') && ischar(context.event_category)
        metadata.event_category = context.event_category;
    end
    if isfield(context, 'operation_id') && ischar(context.operation_id)
        metadata.operation_id = context.operation_id;
    end
    if isfield(context, 'source') && ischar(context.source)
        metadata.source = context.source;
    end
    if isfield(context, 'source_file') && ischar(context.source_file)
        metadata.source_file = context.source_file;
    end
    if isfield(context, 'reason') && ischar(context.reason)
        metadata.reason = context.reason;
    end
    if isfield(context, 'live') && (islogical(context.live) || isnumeric(context.live)) && ...
            isscalar(context.live) && isfinite(double(context.live))
        metadata.live = logical(context.live);
    end
    if isfield(context, 'original_timestamp') && ischar(context.original_timestamp)
        metadata.original_timestamp = context.original_timestamp;
    end
    if isfield(context, 'stage_span') && isnumeric(context.stage_span) && ...
            numel(context.stage_span) == 2 && ...
            all(isfinite(context.stage_span(:))) && ...
            all(context.stage_span(:) == floor(context.stage_span(:)))
        metadata.stage_span = reshape(context.stage_span, 1, 2);
    end
    if isfield(context, 'operation_ids') && iscell(context.operation_ids)
        metadata.operation_ids = context.operation_ids;
    end
end

if isempty(metadata.stage_id) && metadata.stage_number > 0
    metadata.stage_id = local_workflow_stage_id(metadata.stage_number);
end
if isempty(metadata.operation_id)
    if ~isempty(metadata.stage_id)
        metadata.operation_id = metadata.stage_id;
    else
        metadata.operation_id = local_operation_id(kind, text);
    end
end
if isempty(metadata.event_kind)
    metadata.event_kind = local_event_kind(kind, metadata.stage_number);
end
% The observed severity is authoritative over a caller's start/status hint.
% A failure during a started stage must not be serialized as stage_started.
if any(strcmp(kind, {'error'; 'run-failed'}))
    metadata.event_kind = 'failure';
elseif strcmp(kind, 'cancelled')
    metadata.event_kind = 'cancelled';
elseif strcmp(kind, 'warn') && ~strcmp(metadata.event_kind, 'delegation')
    metadata.event_kind = 'warning';
end
if isempty(metadata.event_category)
    if metadata.stage_number > 0
        metadata.event_category = local_workflow_category(metadata.stage_number);
    elseif strcmp(metadata.event_kind, 'delegation')
        metadata.event_category = 'preparation';
    elseif strcmp(metadata.operation_id, 'output.verify')
        metadata.event_category = 'verified_completion';
    elseif strncmp(metadata.operation_id, 'output.', 7)
        metadata.event_category = 'finalization';
    elseif strcmp(metadata.operation_id, 'scheduler.job')
        metadata.event_category = 'scheduler';
    else
        has_subject = isstruct(context) && isfield(context, 'subject_index') && ...
            ~isempty(context.subject_index);
        metadata.event_category = local_event_category(kind, profile_name, ...
            text, metadata.stage_id, has_subject, ...
            local_completion_verified(context));
    end
end
if strcmp(metadata.event_category, 'remote_processing')
    metadata.event_category = 'remote_execution';
elseif strcmp(metadata.event_category, 'retrieval')
    metadata.event_category = 'transfer';
end
if strcmp(metadata.event_kind, 'delegation')
    if isempty(metadata.stage_span)
        metadata.stage_span = [2 3];
    end
    if isempty(metadata.operation_ids)
        metadata.operation_ids = {'prepare.recenter', 'prepare.alias_correct'};
    end
end
if strcmp(metadata.event_kind, 'stage_skipped') && isempty(metadata.reason) && ...
        any(strcmp(metadata.stage_id, ...
        {'workflow.dicom_output'; 'workflow.full_output_finalize'})) && ...
        (strcmp(profile_name, 'local-mprage-only') || ...
         strcmp(profile_name, 'mlsc-mprage-only'))
    metadata.reason = 'profile_policy:mprage_only';
end
if isempty(metadata.source)
    metadata.source = 'orchestrator';
end
if isempty(metadata.source_file)
    metadata.source_file = 'unavailable';
end
if isempty(metadata.original_timestamp)
    metadata.original_timestamp = source_time;
end
if isempty(metadata.original_timestamp)
    metadata.original_timestamp = 'null';
end
end

function [stage_number, stage_id] = local_workflow_stage_from_text(profile_name, kind, text)
stage_number = 0;
stage_id = '';
text_lower = lower(strtrim(text));
if local_is_legacy_profile(profile_name) && ...
        (~isempty(strfind(text_lower, 'recentering')) || ...
         ~isempty(strfind(text_lower, 'aliasing correction')) || ...
         ~isempty(strfind(text_lower, 'alias-recenter')))
    return; % compiled v2 is represented by one delegated event, not stage outcomes
end
if local_starts_with(text_lower, 'recentering') || ...
        local_starts_with(text_lower, '[recentering]')
    stage_number = 2;
elseif local_starts_with(text_lower, 'aliasing correction') || ...
        local_starts_with(text_lower, '[aliasing correction]')
    stage_number = 3;
elseif local_starts_with(text_lower, 'input prepared') || ...
        local_starts_with(text_lower, 'preparing input mprage') || ...
        local_starts_with(text_lower, 'input preparation')
    stage_number = 1;
elseif ~isempty(strfind(text_lower, 'normaliz'))
    stage_number = 4;
elseif ~isempty(strfind(text_lower, 'aligning mprage')) || ...
        ~isempty(strfind(text_lower, 'alignment and masking')) || ...
        ~isempty(strfind(text_lower, 'creating subject mask'))
    stage_number = 5;
elseif ~isempty(strfind(text_lower, 'new segment')) || ...
        ~isempty(strfind(text_lower, 'segmentation completed'))
    stage_number = 6;
elseif ~isempty(strfind(text_lower, 'dartel')) || ...
        ~isempty(strfind(text_lower, 'inverse warp')) || ...
        ~isempty(strfind(text_lower, 'reslicing atlases')) || ...
        ~isempty(strfind(text_lower, 'atlas registration completed'))
    stage_number = 7;
elseif ~isempty(strfind(text_lower, 'attenuation map')) || ...
        ~isempty(strfind(text_lower, 'attenuation-map')) || ...
        ~isempty(strfind(text_lower, 'att_map verified'))
    stage_number = 8;
elseif ~isempty(strfind(text_lower, 'dicom output')) || ...
        ~isempty(strfind(text_lower, 'writing dicom'))
    stage_number = 9;
elseif ~isempty(strfind(text_lower, 'full-output promotion')) || ...
        ~isempty(strfind(text_lower, 'promoting final outputs')) || ...
        ~isempty(strfind(text_lower, 'outputs promoted'))
    if ~any(strcmp(profile_name, {'local-mprage-only'; 'mlsc-mprage-only'}))
        stage_number = 10;
    end
end
if stage_number > 0 && any(strcmp(kind, ...
        {'warn'; 'error'; 'run-failed'; 'cancelled'}))
    % Diagnostics are source-qualified events, not transitions of the workflow stage.
    stage_number = 0;
end
if stage_number > 0
    stage_id = local_workflow_stage_id(stage_number);
end
end

function yes = local_is_legacy_delegated_detail(profile_name, text)
text_lower = lower(strtrim(text));
yes = local_is_legacy_profile(profile_name) && ...
    (~isempty(strfind(text_lower, 'recentering')) || ...
     ~isempty(strfind(text_lower, 'aliasing correction')) || ...
     ~isempty(strfind(text_lower, 'alias-recenter')));
end

function stage_id = local_workflow_stage_id(stage_number)
ids = {'workflow.input_prepare'; 'workflow.recenter'; ...
    'workflow.alias_correct'; 'workflow.normalize'; ...
    'workflow.align_mask'; 'workflow.segment'; 'workflow.dartel'; ...
    'workflow.attenuation_qc'; 'workflow.dicom_output'; ...
    'workflow.full_output_finalize'};
stage_id = '';
if isnumeric(stage_number) && isscalar(stage_number) && ...
        stage_number >= 1 && stage_number <= length(ids) && ...
        stage_number == floor(stage_number)
    stage_id = ids{stage_number};
end
end

function category = local_workflow_category(stage_number)
if stage_number <= 4
    category = 'preparation';
elseif stage_number <= 8
    category = 'scientific';
else
    category = 'finalization';
end
end

function operation_id = local_operation_id(kind, text)
text_lower = lower(strtrim(text));
if strcmp(kind, 'scheduler-submit') || ...
        any(strcmp(kind, {'accepted'; 'state'; 'remote-terminal'; 'heartbeat'}))
    operation_id = 'scheduler.job';
elseif ~isempty(strfind(text_lower, 'delegated to compiled v2'))
    operation_id = 'prepare.compiled_preprocess';
elseif ~isempty(strfind(text_lower, 'promot'))
    operation_id = 'output.promote_nifti';
elseif ~isempty(strfind(text_lower, 'cleanup')) || ...
        ~isempty(strfind(text_lower, 'temporary files removed'))
    operation_id = 'output.cleanup';
elseif ~isempty(strfind(text_lower, 'verified')) || ...
        ~isempty(strfind(text_lower, 'output verification'))
    operation_id = 'output.verify';
else
    operation_id = ['event.' kind];
end
end

function event_kind = local_event_kind(kind, stage_number)
if strcmp(kind, 'cancelled')
    event_kind = 'cancelled';
elseif strcmp(kind, 'delegation')
    event_kind = 'delegation';
elseif strcmp(kind, 'scheduler-submit')
    event_kind = 'scheduler_submission';
elseif strcmp(kind, 'accepted')
    event_kind = 'scheduler_accepted';
elseif strcmp(kind, 'heartbeat')
    event_kind = 'heartbeat';
elseif strcmp(kind, 'skipped')
    event_kind = 'stage_skipped';
elseif strcmp(kind, 'active')
    if stage_number > 0
        event_kind = 'stage_started';
    else
        event_kind = 'operation_started';
    end
elseif strcmp(kind, 'done') || strcmp(kind, 'verified')
    if stage_number > 0
        event_kind = 'stage_completed';
    else
        event_kind = 'operation_completed';
    end
elseif strcmp(kind, 'subject-end')
    event_kind = 'subject_completed';
elseif strcmp(kind, 'run-end')
    event_kind = 'run_completed';
elseif any(strcmp(kind, {'error'; 'run-failed'}))
    event_kind = 'failure';
elseif any(strcmp(kind, {'warn'; 'qform'; 'provenance'}))
    event_kind = 'warning';
elseif strcmp(kind, 'remote-terminal') || strcmp(kind, 'state')
    event_kind = 'scheduler_state';
elseif any(strcmp(kind, {'retrieved'; 'remote-verified'}))
    event_kind = 'transfer';
else
    event_kind = 'info';
end
end

function yes = local_is_legacy_profile(profile_name)
yes = ischar(profile_name) && any(strcmp(profile_name, ...
    {'local-legacy'; 'mlsc-legacy'; 'launchpad-legacy'}));
end

function event_category = local_event_category(kind, profile_name, text, stage_id, has_subject, verified)
%LOCAL_EVENT_CATEGORY Map one presented row to the JSONL event_category set.
%   Scheduler status never implies scientific progress; a scheduler exit or a
%   remote-verified row is retrieval/scheduler, never verified_completion.
%   VERIFIED is true only for the flagged final subject-completion row.
text_lower = lower(strtrim(text));
remote = local_is_remote_profile(profile_name);
if strcmp(kind, 'cancelled')
    if has_subject
        event_category = 'subject';
    else
        event_category = 'run';
    end
elseif strcmp(kind, 'subject-end')
    if verified
        event_category = 'verified_completion';
    else
        event_category = 'subject';
    end
elseif any(strcmp(kind, {'run-end'; 'run-failed'}))
    event_category = 'run';
elseif any(strcmp(kind, {'retrieved'; 'remote-verified'}))
    event_category = 'transfer';
elseif remote && any(strcmp(kind, ...
        {'accepted'; 'state'; 'remote-terminal'; 'scheduler-submit'; 'heartbeat'}))
    event_category = 'scheduler';
elseif remote && ~isempty(regexp(text_lower, 'copy-back', 'once'))
    event_category = 'transfer';
elseif remote && ~isempty(regexp(text_lower, ...
        '(connection and authentication|stage-in)', 'once'))
    event_category = 'remote_execution';
elseif ~isempty(stage_id) && remote
    event_category = local_remote_stage_event_category(stage_id);
elseif ~isempty(stage_id)
    event_category = local_stage_event_category(stage_id);
elseif remote
    event_category = 'remote_execution';
elseif any(strcmp(kind, {'warn'; 'provenance'; 'qform'; 'error'}))
    if has_subject
        event_category = 'subject';
    else
        event_category = 'run';
    end
else
    event_category = 'scientific';
end
end

function event_category = local_remote_stage_event_category(stage_id)
%LOCAL_REMOTE_STAGE_EVENT_CATEGORY Classify scheduler, remote, and transfer rows.
if ~isempty(regexp(stage_id, '\.submit$', 'once'))
    event_category = 'scheduler';
elseif ~isempty(regexp(stage_id, '\.(remote_wait|remote_processing)$', 'once'))
    event_category = 'remote_execution';
elseif ~isempty(regexp(stage_id, '\.(verify|retrieve_verify)$', 'once'))
    event_category = 'transfer';
else
    event_category = local_stage_event_category(stage_id);
end
end

function event_category = local_stage_event_category(stage_id)
% Postprocessing (for example background-mask application) modifies the
% scientific output, so it is 'scientific'. Promotion, cleanup and DICOM output
% writing are 'finalization'. Retrieval and scheduler stages are classified by
% local_remote_stage_event_category before this helper is reached.
if ~isempty(regexp(stage_id, '(dicom_output|promote|cleanup)$', 'once'))
    event_category = 'finalization';
else
    event_category = 'scientific';
end
end

function [stage_id, stage_number, stage_total] = local_row_public_stage( ...
        state, record_stage, producer_stage, producer_total)
%LOCAL_ROW_PUBLIC_STAGE Public stage identity of a row that carries a number.
stage_id = '';
stage_number = 0;
stage_total = 0;
if isempty(record_stage) || ~local_is_stage_map(state.stage_map)
    return;
end
stage_id = local_public_stage_id(state.stage_map, producer_stage, producer_total);
if ~isempty(stage_id)
    stage_number = producer_stage;
    stage_total = producer_total;
end
end

function stage_id = local_public_stage_id(stage_map, stage_number, stage_total)
%LOCAL_PUBLIC_STAGE_ID Stable identifier of a public stage of the active map.
stage_id = '';
if ~local_is_stage_map(stage_map) || ~isfield(stage_map, 'stage_ids') || ...
        ~iscell(stage_map.stage_ids) || ...
        ~isfield(stage_map, 'public_stage_numbers')
    return;
end
if stage_map.total ~= stage_total || ...
        length(stage_map.stage_ids) ~= length(stage_map.public_stage_numbers)
    return;
end
slot = find(stage_map.public_stage_numbers == stage_number, 1);
if ~isempty(slot)
    stage_id = stage_map.stage_ids{slot};
end
end

function record = local_contract_fields(record, state, event_category, ...
        stage_id, stage_number, stage_total, metadata, context, kind, text, source_time)
%LOCAL_CONTRACT_FIELDS Attach the additive progress contract to one event.
if nargin < 7 || ~isstruct(metadata)
    metadata = local_resolve_event_metadata(state, struct(), ...
        state.active_profile, 'info', '', stage_number, stage_total, '');
end
if nargin < 8 || ~isstruct(context)
    context = struct();
end
if nargin < 9
    kind = 'info';
end
if nargin < 10
    text = '';
end
if nargin < 11
    source_time = '';
end
profile = 'unavailable';
if isstruct(state) && isfield(state, 'active_profile') && ...
        ischar(state.active_profile) && ~isempty(state.active_profile)
    profile = state.active_profile;
end
record.profile = profile;
record.backend = local_backend_of(profile);
if isempty(event_category)
    event_category = metadata.event_category;
end
if isempty(event_category)
    event_category = 'unavailable';
end
record.schema_version = '1';
record.event_category = local_event_value(event_category);
record.event_kind = local_event_value(metadata.event_kind);
record.operation_id = local_event_value(metadata.operation_id);
record.source = local_event_value(metadata.source);
record.source_file = local_event_value(metadata.source_file);
record.reason = local_event_value(metadata.reason);
record.live = logical(metadata.live);
record.original_timestamp = metadata.original_timestamp;
record.stage_span = metadata.stage_span;
record.operation_ids = metadata.operation_ids;
record.stage_id = local_event_value(stage_id);
if strcmp(record.stage_id, 'unavailable') && ~isempty(metadata.stage_id)
    record.stage_id = metadata.stage_id;
end
if isempty(stage_id) || stage_number < 1
    record.stage_number = 'unavailable';
    record.stage_total = 'unavailable';
else
    record.stage_number = sprintf('%d', stage_number);
    record.stage_total = sprintf('%d', stage_total);
end
if ~metadata.live && isempty(source_time)
    record.timestamp = 'null';
elseif ~isempty(source_time)
    record.timestamp = source_time;
end
end

function record = local_warning_record(state, record, entry, record_stage)
%LOCAL_WARNING_RECORD Contract fields for a grouped warning row or notice.
[stage_id, stage_number, stage_total] = local_row_public_stage( ...
    state, record_stage, entry.stage, entry.stage_total);
warning_context = local_warning_context(entry);
warning_time = local_warning_time(entry);
metadata = local_resolve_event_metadata(state, warning_context, ...
    state.active_profile, 'warn', record.message, entry.stage, ...
    entry.stage_total, warning_time);
event_category = metadata.event_category;
if isempty(event_category)
    event_category = local_event_category('warn', state.active_profile, '', ...
        stage_id, entry.subject > 0, false);
end
record = local_contract_fields(record, state, event_category, stage_id, ...
    stage_number, stage_total, metadata, warning_context, 'warn', ...
    record.message, warning_time);
end

function [event_date, event_clock] = local_event_clock(source_time, live)
if nargin < 2
    live = true;
end
if isempty(source_time)
    if ~live
        event_date = '';
        event_clock = '—';
        return;
    end
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

function [stage_number, stage_total, from_text] = local_stage_marker(line, context)
stage_number = 0;
stage_total = 0;
from_text = false;
match = regexp(line, '\[stage[ \t]+([0-9]+)/([0-9]+)\]', ...
    'tokens', 'once', 'ignorecase');
if isstruct(context) && isfield(context, 'stage_status') && ...
        isfield(context, 'stage_index') && isfield(context, 'stage_count')
    match = [];  % canonical event: its own public stage is authoritative
end
if ~isempty(match)
    candidate = [str2double(match{1}) str2double(match{2})];
    from_text = true;
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

function yes = local_is_current_local_profile(profile_name)
yes = ischar(profile_name) && any(strcmp(profile_name, ...
    {'local-current'; 'local-mprage-only'}));
end

function yes = local_is_identity_stage_map(stage_map)
yes = local_is_stage_map(stage_map) && ...
    stage_map.producer_total == stage_map.total && ...
    isequal(stage_map.producer_stage_numbers(:), stage_map.public_stage_numbers(:));
end

function yes = local_is_stage_map(stage_map)
yes = isstruct(stage_map) && isscalar(stage_map) && ...
    isfield(stage_map, 'producer_total') && ...
    isnumeric(stage_map.producer_total) && ...
    isscalar(stage_map.producer_total) && stage_map.producer_total > 0 && ...
    isfield(stage_map, 'total') && isnumeric(stage_map.total) && ...
    isscalar(stage_map.total) && stage_map.total > 0 && ...
    isfield(stage_map, 'producer_stage_numbers') && ...
    isfield(stage_map, 'public_stage_numbers') && isfield(stage_map, 'titles');
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
    'job', {}, 'message', {}, 'timestamp', {}, 'profile', {}, 'backend', {}, ...
    'schema_version', {}, 'event_kind', {}, 'operation_id', {}, ...
    'event_category', {}, 'source', {}, 'source_file', {}, 'reason', {}, ...
    'stage_id', {}, 'stage_number', {}, 'stage_total', {}, 'stage_span', {}, ...
    'operation_ids', {}, 'live', {}, 'original_timestamp', {});
end

function event = local_unavailable_event()
event = struct('level', 'unavailable', 'subject', 'unavailable', ...
    'stage', 'unavailable', 'status', 'unavailable', 'job', 'unavailable', ...
    'message', 'unavailable', 'timestamp', 'unavailable', ...
    'profile', 'unavailable', 'backend', 'unavailable', ...
    'schema_version', '1', 'event_kind', 'unavailable', ...
    'operation_id', 'unavailable', 'event_category', 'unavailable', ...
    'source', 'unavailable', 'source_file', 'unavailable', ...
    'reason', 'unavailable', 'stage_id', 'unavailable', ...
    'stage_number', 'unavailable', 'stage_total', 'unavailable', ...
    'stage_span', [], 'operation_ids', {{}}, 'live', true, ...
    'original_timestamp', 'null');
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
% Existing keys keep their order and meaning. The additive contract keys follow
% them and are emitted only for profiles where local_contract_applies is true.
fields = {'schema_version'; 'timestamp'; 'level'; 'subject'; 'stage'; ...
    'status'; 'job'; 'message'; 'profile'; 'backend'; 'event_kind'; ...
    'operation_id'; 'event_category'; 'source'; 'source_file'; 'reason'; ...
    'stage_id'; 'stage_number'; 'stage_total'; 'stage_span'; 'operation_ids'; ...
    'live'; 'original_timestamp'};
required = {'timestamp'; 'level'; 'message'};
optional_context = {'subject'; 'stage'; 'status'; 'job'};
contract_fields = {'schema_version'; 'profile'; 'backend'; 'event_kind'; ...
    'operation_id'; 'event_category'; 'source'; 'source_file'; 'reason'; ...
    'stage_id'; 'stage_number'; 'stage_total'; 'stage_span'; 'operation_ids'; ...
    'live'; 'original_timestamp'};
numeric_fields = {'schema_version'; 'stage_number'; 'stage_total'};
contract_on = isstruct(event_record) && isfield(event_record, 'profile') && ...
    ischar(event_record.profile) && local_contract_applies(event_record.profile);
for ii = 1:length(fields)
    field_name = fields{ii};
    if any(strcmp(contract_fields, field_name)) && ~contract_on
        continue;
    end
    value = 'unavailable';
    if isstruct(event_record) && isfield(event_record, field_name)
        candidate = event_record.(field_name);
        if ischar(candidate)
            value = candidate;
    elseif strcmp(field_name, 'live') && (islogical(candidate) || isnumeric(candidate))
            value = candidate;
        elseif any(strcmp(field_name, {'stage_span'; 'operation_ids'}))
            value = candidate;
        end
    end
    if strcmp(field_name, 'stage_span') && isempty(value)
        continue;
    elseif strcmp(field_name, 'operation_ids') && isempty(value)
        continue;
    end
    missing_context = any(strcmp(optional_context, field_name)) && ...
        ischar(value) && any(strcmpi(value, {'null'; 'unavailable'}));
    if (ischar(value) && (isempty(value) || strcmp(value, 'unavailable'))) || missing_context || ...
            (strcmp(field_name, 'subject') && strcmp(value, 'RUN'))
        if any(strcmp(required, field_name))
            value = '';
        else
            continue;
        end
    end
    if any(strcmp(numeric_fields, field_name))
        % Integer values are built only from sprintf('%d'); unavailable
        % stage numbers are JSON null, never the invalid bare token.
        if ~ischar(value) || isempty(regexp(value, '^[0-9]+$', 'once'))
            value = 'null';
        end
        record = [record ',"' field_name '":' value]; %#ok<AGROW>
    elseif strcmp(field_name, 'live')
        if (islogical(value) || isnumeric(value)) && isscalar(value) && ...
                isfinite(double(value)) && logical(value)
            encoded = 'true';
        else
            encoded = 'false';
        end
        record = [record ',"' field_name '":' encoded]; %#ok<AGROW>
    elseif strcmp(field_name, 'stage_span')
        if ~isnumeric(value) || numel(value) ~= 2 || ...
                any(~isfinite(value(:))) || any(value(:) ~= floor(value(:)))
            continue;
        end
        record = [record ',"' field_name '":[' ...
            sprintf('%d,%d', value(1), value(2)) ']']; %#ok<AGROW>
    elseif strcmp(field_name, 'operation_ids')
        if ~iscell(value) || ~all(cellfun(@ischar, value))
            continue;
        end
        encoded = '[';
        for jj = 1:length(value)
            if jj > 1
                encoded = [encoded ',']; %#ok<AGROW>
            end
            encoded = [encoded local_json_quote(value{jj})]; %#ok<AGROW>
        end
        encoded = [encoded ']'];
        record = [record ',"' field_name '":' encoded]; %#ok<AGROW>
    elseif any(strcmp(field_name, {'timestamp'; 'original_timestamp'})) && ...
            ischar(value) && strcmp(value, 'null')
        record = [record ',"' field_name '":null']; %#ok<AGROW>
    else
        record = [record ',"' field_name '":' local_json_quote(value)]; %#ok<AGROW>
    end
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
