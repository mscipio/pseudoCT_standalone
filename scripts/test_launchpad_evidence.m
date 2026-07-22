function test_launchpad_evidence()
%TEST_LAUNCHPAD_EVIDENCE RED-first bounded lifecycle non-regression checks.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'launchpad'));
state = struct('profile', 'launchpad', 'subject_count', 1, ...
    'jobname', 'pbsjob_123', 'jobnum', 123, 'exit_status', 0, ...
    'pbs_logs', {{'job.o123', 'job.e123'}}, 'att_map_present', true, ...
    'cleanup', 'remote-scratch-removed');

first = launchpad_evidence('init', state);
second = launchpad_evidence('init', state);
assert(isequal(first, second), 'Identical lifecycle snapshots must be bytewise stable.');
next = launchpad_evidence('polling', first, struct('exit_status', 0));
next = launchpad_evidence('pbs_logs', next, struct('pbs_logs', state.pbs_logs));
next = launchpad_evidence('retrieval', next, struct('att_map_present', true));
next = launchpad_evidence('cleanup', next, struct('cleanup', state.cleanup));
assert(strcmp(next.schema, 'pseudo-CT.launchpad-evidence/v1'));
assert(length(next.lifecycle) == 5);
assert(strcmp(next.lifecycle{1}, 'init') && strcmp(next.lifecycle{end}, 'cleanup'));
assert(next.exit_status == 0 && next.att_map_present);
fprintf('=== Launchpad evidence tests: 7/7 passed ===\n');
end
