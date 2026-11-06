function test_pseudoct_presenter_legacy_rows()
%TEST_PSEUDOCT_PRESENTER_LEGACY_ROWS Live/replay times, legacy heartbeat,
% legacy stage 2/3 notice ordering and the one-row run summary, through the
% real presenter. Event-only: no workflow or scientific processing is run.
root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'io'));
old_format = getenv('PSEUDOCT_OUTPUT_FORMAT');
cleanup = onCleanup(@() local_restore(old_format));
setenv('PSEUDOCT_OUTPUT_FORMAT', 'text');
live = struct('console_profile', 'local-legacy', 'subject_index', 1, ...
    'subject_count', 2, 'source', 'orchestrator');
replay = live;
replay.live = false;
backend = live;
backend.source = 'backend';
backend_replay = replay;
backend_replay.source = 'backend';

% 1. Time column and JSONL-record timestamps: live = observation time,
%    replay = null (never fabricated).
pseudo_CT_output_console_visible('RESET');
[~, row] = pseudo_CT_output_console_visible('INFO', 'Whole process finished', backend);
lines = local_lines(row);
assert(~isempty(regexp(lines{end}, '^\d\d:\d\d:\d\d S01 ', 'once')));
ev = pseudo_CT_output_console_visible('DRAIN_EVENTS');
assert(isempty(regexp(ev(end).timestamp, '^null$', 'once')) && ...
    strcmp(ev(end).original_timestamp, 'null') && ev(end).live);
pseudo_CT_output_console_visible('RESET');
[~, row] = pseudo_CT_output_console_visible('INFO', 'Whole process finished', backend_replay);
lines = local_lines(row);
assert(strncmp(lines{end}, '--:--:-- S01 ', 13));
ev = pseudo_CT_output_console_visible('DRAIN_EVENTS');
assert(strcmp(ev(end).timestamp, 'null') && ~ev(end).live);

% 2. Legacy heartbeat wording; no heartbeat after the subject is terminal.
pseudo_CT_output_console_visible('RESET');
beat = 'Legacy pseudo-CT still running (elapsed 00:58:44): compiled runner.';
[visible, row] = pseudo_CT_output_console_visible('INFO', beat, live);
lines = local_lines(row);
assert(visible && strcmp(local_msg(lines{end}), ...
    '        INFO      Compiled v2 processing still running (elapsed 58:44)'));
pseudo_CT_output_console_visible('ERROR', 'Subject failed.', live);
visible = pseudo_CT_output_console_visible('INFO', beat, live);
assert(~visible);

% 3. Legacy stage 2/3 notices: held, shown immediately before stage 4,
%    per subject, and emitted before a terminal row on early failure.
for mode = 1:2
    ctx = live;
    if mode == 2
        ctx = replay;
    end
    pseudo_CT_output_console_visible('RESET');
    s2 = ctx;
    s2.subject_index = 2;
    pseudo_CT_output_console_visible('INFO', 'Preparing input MPRAGE.', ctx);
    [~, row] = pseudo_CT_output_console_visible('SUCCESS', 'Input prepared.', ctx);
    lines = local_lines(row);
    assert(length(lines) == 1 && strcmp(local_msg(lines{1}), ...
        '        DONE      Input MPRAGE prepared'));
    % Subject 2 is isolated: its own start does not release S01's notices.
    pseudo_CT_output_console_visible('INFO', 'Preparing input MPRAGE.', s2);
    pseudo_CT_output_console_visible('SUCCESS', 'Input prepared.', s2);
    [~, row] = pseudo_CT_output_console_visible('INFO', ...
        'Normalizing MPRAGE with FreeSurfer.', ctx);
    lines = local_lines(row);
    assert(length(lines) == 3 && ...
        strcmp(local_msg(lines{1}), '[2/10]  INFO      Recentring handled by compiled v2 backend') && ...
        strcmp(local_msg(lines{2}), '[3/10]  INFO      Aliasing correction handled by compiled v2 backend') && ...
        strcmp(local_msg(lines{3}), '[4/10]  ACTIVE    Normalizing MPRAGE with FreeSurfer'));
    if mode == 1
        assert(~isempty(regexp(lines{1}, '^\d\d:\d\d:\d\d S01 ', 'once')));
    else
        assert(strncmp(lines{1}, '--:--:-- S01 ', 13));
    end
    % S02 fails before stage 4: its held notices precede the ERROR row.
    [~, row] = pseudo_CT_output_console_visible('ERROR', 'Subject failed.', s2);
    lines = local_lines(row);
    assert(length(lines) == 3 && ...
        strcmp(local_msg(lines{1}), '[2/10]  INFO      Recentring handled by compiled v2 backend') && ...
        strcmp(local_msg(lines{2}), '[3/10]  INFO      Aliasing correction handled by compiled v2 backend') && ...
        strcmp(local_msg(lines{3}), '        ERROR     Subject failed.'));
    ev = pseudo_CT_output_console_visible('DRAIN_EVENTS');
    notice = ev(strcmp({ev.subject}, 'S01') & strcmp({ev.event_kind}, 'delegation'));
    assert(isequal({notice.stage_number}, {'2', '3'}) && ...
        strcmp(notice(1).operation_id, 'prepare.recenter'));
    if mode == 2
        assert(all(strcmp({notice.timestamp}, 'null')));
    end
end

% 4. The run summary stays on one console row.
pseudo_CT_output_console_visible('RESET');
[~, row] = pseudo_CT_output_console_visible('INFO', ...
    'Run completed: requested 1, started 1, succeeded 1, failed 0, skipped 0 (elapsed 00:58:44).', ...
    struct('console_profile', 'local-legacy', 'source', 'orchestrator'));
lines = local_lines(row);
assert(strcmp(local_msg(lines{end}), ['        INFO      Run completed: 1 requested, 1 started, ' ...
    '1 succeeded, 0 failed, 0 skipped (00:58:44).']));
assert(length(lines{end}) <= 123);

% 5. Legacy stage 5. Lines are copied from captured validation runs
%    (local-legacy / launchpad-legacy / mlsc-legacy run logs, 2026-11-05).
%    ACTIVE on 'Legacy pseudo-CT started'; DONE(5) is inferred only when stage 6
%    starts, immediately before ACTIVE(6), with the stage-6 time.
for mode = 1:2
    ctx = live;
    if mode == 2
        ctx = replay;
    end
    pseudo_CT_output_console_visible('RESET');
    local_feed(ctx, {'Preparing input MPRAGE.', 'Input prepared (elapsed 00:00:43).', ...
        'Normalizing MPRAGE with FreeSurfer.', ...
        'MPRAGE normalization completed (elapsed 00:02:18).'});
    rows = local_feed(ctx, {'Legacy pseudo-CT started.'});
    assert(length(rows) == 1 && strcmp(local_msg(rows{1}), ...
        '[5/10]  ACTIVE    Aligning MPRAGE and generating subject mask'));
    rows = local_feed(backend_ctx(ctx), {'Opening file: /x/tmp/mprage_normalized.nii and calculating the mask ...'});
    assert(isempty(rows));   % no separate INFO row duplicating ACTIVE(5)
    rows = local_feed(backend_ctx(ctx), {'Running ''New Segment'''});
    assert(length(rows) == 2 && ...
        strcmp(local_msg(rows{1}), '        DONE      Alignment and masking completed') && ...
        strcmp(local_msg(rows{2}), '[6/10]  ACTIVE    Running SPM New Segment'));
    assert(strcmp(rows{1}(1:8), rows{2}(1:8)));   % stage-6 transition time
    ev = pseudo_CT_output_console_visible('DRAIN_EVENTS');
    done5 = ev(strcmp({ev.stage_number}, '5') & strcmp({ev.status}, 'DONE'));
    act6 = ev(strcmp({ev.stage_number}, '6') & strcmp({ev.status}, 'ACTIVE'));
    assert(length(done5) == 1 && length(act6) == 1 && ...
        strcmp(done5.event_kind, 'inferred_stage_completion') && ...
        strcmp(done5.reason, 'inferred_from_next_stage_boundary') && ...
        strcmp(done5.operation_id, 'workflow.align_mask') && ...
        strcmp(done5.timestamp, act6.timestamp));
    if mode == 2
        assert(strcmp(done5.timestamp, 'null') && strncmp(rows{1}, '--:--:--', 8));
    end
end
% No fabricated DONE(5) when stage 6 never starts (failure / cancellation).
pseudo_CT_output_console_visible('RESET');
local_feed(live, {'Normalizing MPRAGE with FreeSurfer.', ...
    'MPRAGE normalization completed (elapsed 00:02:18).', 'Legacy pseudo-CT started.', ...
    'Subject failed.'});
pseudo_CT_output_console_visible('FLUSH');
ev = pseudo_CT_output_console_visible('DRAIN_EVENTS');
assert(any(strcmp({ev.stage_number}, '5') & strcmp({ev.status}, 'ACTIVE')) && ...
    ~any(strcmp({ev.stage_number}, '5') & strcmp({ev.status}, 'DONE')));
% Launchpad shares the path: exactly one (inferred) DONE(5), no double DONE.
lp = replay;
lp.console_profile = 'launchpad-legacy';
lp.source = 'scheduler';
pseudo_CT_output_console_visible('RESET');
local_feed(lp, {'Opening file: /x/tmp/mprage_normalized.nii and calculating the mask ...', ...
    'Starting the New Segment process (be patient!!) ...', 'Running ''New Segment'''});
ev = pseudo_CT_output_console_visible('DRAIN_EVENTS');
done5 = ev(strcmp({ev.stage_number}, '5') & strcmp({ev.status}, 'DONE'));
assert(length(done5) == 1 && strcmp(done5.event_kind, 'inferred_stage_completion') && ...
    strcmp(done5.timestamp, 'null') && ~done5.live);

% 6. MLSC Legacy runs its later phases in a new process: the stage 2/3 notices
%    (held in the first process) are regenerated before stage 4, with a null
%    time in replay.
ml = struct('console_profile', 'mlsc-legacy', 'subject_index', 1, ...
    'subject_count', 1, 'source', 'orchestrator');
pseudo_CT_output_console_visible('RESET');
rows = local_feed(ml, {'MLSC job 10594254 accepted.', 'MLSC stage-in completed.', ...
    'MLSC normalization started.'});
assert(length(rows) == 7 && ...   % header, rule, accepted, stage-in, 2, 3, 4
    strcmp(local_msg(rows{5}), '[2/10]  INFO      Recentring handled by compiled v2 backend') && ...
    strcmp(local_msg(rows{6}), '[3/10]  INFO      Aliasing correction handled by compiled v2 backend') && ...
    strcmp(local_msg(rows{7}), '[4/10]  ACTIVE    Normalizing MPRAGE with FreeSurfer'));
rows = local_feed(ml, {'MLSC normalization completed.'});
rows = local_feed(ml, {'MLSC pseudo-CT started.'});
assert(length(rows) == 1 && strcmp(local_msg(rows{1}), ...
    '[5/10]  ACTIVE    Aligning MPRAGE and generating subject mask'));

% 7. MLSC Current: stage 2/3 rows from the captured combined-phase report; held
%    stage-5 start shown with the release time on one row; 60 s heartbeats.
mc = struct('console_profile', 'mlsc-current', 'subject_index', 1, ...
    'subject_count', 1, 'source', 'orchestrator');
mc_replay = mc;
mc_replay.live = false;
for mode = 1:2
    ctx = mc;
    if mode == 2
        ctx = mc_replay;
    end
    pseudo_CT_output_console_visible('RESET');
    rows = local_feed(ctx, {'[2026-11-05 10:27:41] INFO    [subject 1/1] [stage 3/8] [job 10582887] MLSC preparation completed.', ...
        '[2026-11-05 10:27:41] SUCCESS [subject 1/1] [stage 3/8] [job 10582887] MLSC alias-recenter completed.', ...
        '[2026-11-05 10:27:41] INFO    [subject 1/1] [stage 3/8] [job 10582887] MLSC normalization started.'});
    assert(length(rows) >= 6);   % [title,] header, rule, then the four rows
    rows = rows(end - 3:end);
    assert(strcmp(local_msg(rows{2}), ['[2/10]  INFO      MPRAGE recentering handled in compiled phase; ' ...
        'outcome not separately reported']) && ...
        strcmp(local_msg(rows{3}), ['[3/10]  INFO      Aliasing correction handled in compiled phase; ' ...
        'outcome not separately reported']) && ...
        strcmp(local_msg(rows{4}), '[4/10]  ACTIVE    Normalizing MPRAGE with FreeSurfer'));
    assert(all(cellfun(@length, rows) <= 123));
    local_feed(ctx, {'[2026-11-05 10:29:20] INFO    [subject 1/1] [stage 3/8] [job 10582887] Aligning MPRAGE and creating subject mask.'});
    rows = local_feed(ctx, {'[2026-11-05 10:29:22] SUCCESS [subject 1/1] [stage 3/8] [job 10582887] MLSC normalization completed.'});
    assert(length(rows) == 2 && length(rows{2}) <= 123 && ...
        ~isempty(regexp(local_msg(rows{2}), ['^\[5/10\]  ACTIVE    Aligning MPRAGE and generating subject mask ' ...
        '\(start reported before stage 4 ended\)$'], 'once')));
    ev = pseudo_CT_output_console_visible('DRAIN_EVENTS');
    held = ev(strcmp({ev.stage_number}, '5') & strcmp({ev.status}, 'ACTIVE'));
    assert(length(held) == 1 && strcmp(held.original_timestamp, '2026-11-05 10:29:20'));
    if mode == 1
        assert(~isempty(regexp(rows{2}, '^\d\d:\d\d:\d\d S01 ', 'once')) && ...
            ~strcmp(held.timestamp, 'null') && ~strcmp(held.timestamp, held.original_timestamp));
    else
        assert(strncmp(rows{2}, '--:--:-- S01 ', 13) && strcmp(held.timestamp, 'null'));
    end
end
% Heartbeats are admitted per job when elapsed advanced >= 60 s (captured
% elapsed values 00:02:21, 00:03:28, 00:04:36; 00:04:50 is a derived <60 s case).
pseudo_CT_output_console_visible('RESET');
beats = {'00:02:21', '00:03:28', '00:03:50', '00:04:36', '00:04:50'};
shown = zeros(1, length(beats));
for bi = 1:length(beats)
    rows = local_feed(mc, {sprintf('MLSC job 10582887 still running (elapsed %s).', beats{bi})});
    shown(bi) = ~isempty(rows);
end
assert(isequal(shown, [1 1 0 1 0]));
pseudo_CT_output_console_visible('ERROR', 'Subject failed.', mc);
assert(isempty(local_feed(mc, {'MLSC job 10582887 still running (elapsed 00:09:50).'})));

% 8. Live console time never goes backwards for a subject (captured pair: a
%    10:29:54 warning row followed by the 10:29:44 completion). The admission
%    time is shown; the source time stays in original_timestamp. Replay keeps
%    source times.
for mode = 1:2
    ctx = mc;
    if mode == 2
        ctx = mc_replay;
    end
    pseudo_CT_output_console_visible('RESET');
    local_feed(ctx, {'[2026-11-05 10:29:20] INFO    [subject 1/1] [stage 3/8] [job 10582887] Aligning MPRAGE and creating subject mask.'});
    local_feed(ctx, {'[2026-11-05 10:29:54] WARN    [subject 1/1] [job 10582887] {Warning: QFORM0 representation has been rounded.}'});
    rows = local_feed(ctx, {'[2026-11-05 10:29:44] SUCCESS [subject 1/1] [stage 3/8] [job 10582887] Alignment and masking completed.'});
    ev = pseudo_CT_output_console_visible('DRAIN_EVENTS');
    assert(length(rows) == 1 && strcmp(ev(end).status, 'DONE') && ...
        strcmp(ev(end - 1).timestamp, '2026-11-05 10:29:54'));
    shown_time = rows{1}(1:8);
    if mode == 1
        assert(shown_time(1) ~= '-' && all(strcmp(sort({shown_time, '10:29:54'}), {'10:29:54', shown_time})) && ...
            ~strcmp(shown_time, '10:29:44') && ...
            strcmp(ev(end).original_timestamp, '2026-11-05 10:29:44') && ...
            ~strcmp(ev(end).timestamp, ev(end).original_timestamp));
    else
        assert(strcmp(shown_time, '10:29:44') && ...
            strcmp(ev(end).timestamp, '2026-11-05 10:29:44') && ...
            strcmp(ev(end).original_timestamp, '2026-11-05 10:29:44'));
    end
end
fprintf('PRESENTER LEGACY ROWS: PASS.\n');
end

function ctx = backend_ctx(ctx)
ctx.source = 'backend';
end

function rows = local_feed(ctx, messages)
% Feeds raw lines to the production presenter; returns the printed rows.
rows = {};
for mi = 1:length(messages)
    [visible, text] = pseudo_CT_output_console_visible('INFO', messages{mi}, ctx);
    if visible
        rows = [rows local_lines(text)]; %#ok<AGROW>
    end
end
end

function lines = local_lines(text)
lines = regexp(text, '\n', 'split');
lines = lines(~cellfun('isempty', lines));
end

function msg = local_msg(line)
% Row without TIME and SUBJECT columns.
msg = line(18:end);
end

function local_restore(old_format)
setenv('PSEUDOCT_OUTPUT_FORMAT', old_format);
pseudo_CT_output_console_visible('RESET');
end
