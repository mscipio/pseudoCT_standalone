function test_pseudoct_multi_subject()
%TEST_PSEUDOCT_MULTI_SUBJECT Stream lifecycle events through the real presenter.
% No workflow/scientific processing is launched by these event-only checks.
root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'io'));
old_format = getenv('PSEUDOCT_OUTPUT_FORMAT');
cleanup = onCleanup(@() local_restore(old_format));
setenv('PSEUDOCT_OUTPUT_FORMAT', 'text');
base = struct('console_profile', 'local-current', 'subject_index', 1, ...
    'subject_count', 2, 'scope', 'subject', 'source', 'orchestrator');
header = [sprintf('%-8s %-7s %-7s %-9s %s', ...
    'TIME', 'SUBJECT', 'STAGE', 'STATUS', 'MESSAGE') char(10) ...
    repmat('-', 1, 123) char(10)];

% A: verified S01 completion; B: S01 failure. Neither stops S02.
for failed = 0:1
    pseudo_CT_output_console_visible('RESET');
    [visible, row] = local_call('INFO', ...
        'Preparing input MPRAGE.', local_stage(base, 1, 'START'));
    assert(visible && strcmp(row, [header local_row('S01', '[1/10]', ...
        'ACTIVE', 'Preparing input MPRAGE')]));
    if ~failed
        [visible, row] = local_call('SUCCESS', ...
            'Input prepared.', local_stage(base, 1, 'DONE'));
        assert(visible && strcmp(row, local_row('S01', '', 'DONE', 'Input MPRAGE prepared')));
        completion = base;
        completion.completion_verified = true;
        [visible, row] = local_call('SUCCESS', ...
            'Subject completed (elapsed 00:00:01).', completion);
        assert(visible && strcmp(row, local_row('S01', '', 'VERIFIED', ...
            'Subject completed (elapsed 00:00:01).')));
    else
        [visible, row] = local_call('ERROR', ...
            'Subject failed before local finalization.', base);
        assert(visible && strcmp(row, local_row('S01', '', 'ERROR', ...
            'Subject failed before local finalization.')));
    end
    second = base;
    second.subject_index = 2;
    [visible, row] = local_call('INFO', ...
        'Preparing input MPRAGE.', local_stage(second, 1, 'START'));
    assert(visible && strcmp(row, local_row('S02', '[1/10]', ...
        'ACTIVE', 'Preparing input MPRAGE')));
    [visible, row] = local_call('SUCCESS', ...
        'Input prepared.', local_stage(second, 1, 'DONE'));
    assert(visible && strcmp(row, local_row('S02', '', 'DONE', 'Input MPRAGE prepared')));
    events = pseudo_CT_output_console_visible('DRAIN_EVENTS');
    if failed
        assert(isequal({events.subject}, {'S01', 'S01', 'S02', 'S02'}) && ...
            isequal({events.status}, {'ACTIVE', 'ERROR', 'ACTIVE', 'DONE'}));
    else
        assert(isequal({events.subject}, {'S01', 'S01', 'S01', 'S02', 'S02'}) && ...
            isequal({events.status}, {'ACTIVE', 'DONE', 'VERIFIED', 'ACTIVE', 'DONE'}));
    end
end

% C: backend prose is not cancellation; an explicit lifecycle cancellation is.
pseudo_CT_output_console_visible('RESET');
pseudo_CT_output_console_visible('INFO', 'Preparing input MPRAGE.', local_stage(base, 1, 'START'));
backend = base;
backend.source = 'backend';
pseudo_CT_output_console_visible('INFO', 'Backend reader interrupted a diagnostic stream.', backend);
[visible, row] = local_call('SUCCESS', ...
    'Input prepared.', local_stage(base, 1, 'DONE'));
cancel = base;
cancel.event_kind = 'cancelled';
[cancel_visible, cancel_row] = local_call('INFO', ...
    'Run cancelled by user.', cancel);
second = base;
second.subject_index = 2;
after = pseudo_CT_output_console_visible('INFO', ...
    'Preparing input MPRAGE.', local_stage(second, 1, 'START'));
events = pseudo_CT_output_console_visible('DRAIN_EVENTS');
assert(visible && strcmp(row, local_row('S01', '', 'DONE', 'Input MPRAGE prepared')) && ...
    cancel_visible && strcmp(cancel_row, local_row('S01', '', 'CANCELLED', 'Run cancelled by user.')) && ...
    ~after && isequal({events.status}, {'ACTIVE', 'DONE', 'CANCELLED'}) && ...
    strcmp(events(3).event_kind, 'cancelled'));
fprintf('MULTI-SUBJECT PRESENTER: PASS (verified, failed, backend prose/cancellation).\n');
end

function [visible, row] = local_call(varargin)
% Live rows without a source time now show the observation time; mask it.
[visible, row] = pseudo_CT_output_console_visible(varargin{:});
row = regexprep(row, '(^|\n)\d\d:\d\d:\d\d ', '$1--:--:-- ');
end

function context = local_stage(context, n, status)
context.workflow_event = true;
context.stage_index = n;
context.stage_count = 10;
context.stage_status = status;
end

function row = local_row(subject, stage, status, message)
row = sprintf('%-8s %-7s %-7s %-9s %s', '--:--:--', subject, stage, status, message);
end

function local_restore(old_format)
setenv('PSEUDOCT_OUTPUT_FORMAT', old_format);
pseudo_CT_output_console_visible('RESET');
end
