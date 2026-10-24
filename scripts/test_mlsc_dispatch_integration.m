function test_mlsc_dispatch_integration()
%TEST_MLSC_DISPATCH_INTEGRATION Exercise the real MLSC lifecycle seam.
%   Injected callbacks stand in for transport and scheduler responses.  No
%   SSH, Slurm job, or pseudo-CT processing is started.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'mlsc'), '-begin');
addpath(fullfile(root_dir, 'src', 'io'), '-begin');
addpath(fullfile(root_dir, 'src', 'config', 'profiles'), '-begin');

scratch_root = fullfile(root_dir, 'scratch');
if exist(scratch_root, 'dir') ~= 7
    mkdir(scratch_root);
end
test_root = tempname(scratch_root);
mkdir(test_root);
cleanup = onCleanup(@() local_cleanup(test_root)); %#ok<NASGU>
shared_temp = fullfile(test_root, 'shared subject temp');
durable_success = fullfile(test_root, 'durable success');
durable_failure = fullfile(test_root, 'durable failure');
mkdir(shared_temp);
mkdir(durable_success);
mkdir(durable_failure);

runner = fullfile(test_root, 'runner.sh');
defaults_mat = fullfile(test_root, 'defaults.mat');
freesurfer_env = fullfile(test_root, 'freesurfer-env');
mkdir(fullfile(test_root, 'mcr'));
mkdir(fullfile(test_root, 'Batch_atlas'));
local_touch(runner);
local_touch(defaults_mat);
local_touch(freesurfer_env);
input_path = fullfile(shared_temp, 'mprage.nii');
local_touch(input_path);

subject = struct('subject_id', 'dispatch-subject', ...
    'shared_input', input_path, 'shared_temp', shared_temp);
config = struct();
config.mode = 'mlsc';
config.aliasing_default = 1;
config.mlsc = struct('host', 'mlsc.nmr.mgh.harvard.edu', ...
    'runner', runner, 'mcr_root', fullfile(test_root, 'mcr'), ...
    'defaults_mat', defaults_mat, 'batch_templates', ...
    fullfile(test_root, 'Batch_atlas'), 'shell', '/bin/bash', ...
    'freesurfer_env', freesurfer_env, 'partition', 'basic', ...
    'nodes', 1, 'ntasks', 1, 'cpus_per_task', 1, 'memory', '1G', ...
    'time', '00:01:00');

script_runtime = struct('account', 'fixture-account', ...
    'script_path', fullfile(shared_temp, 'job.sh'));
artifact = mlsc_generate_slurm_script(subject, config, script_runtime);
assert(isempty(strfind(artifact.script_text, '/dev/null')));
assert(~isempty(strfind(artifact.script_text, ...
    'pseudoCT_mlsc_%j.out')));
assert(~isempty(strfind(artifact.script_text, ...
    'pseudoCT_mlsc_%j.err')));
assert(strcmp(artifact.stdout_log_path, ...
    fullfile(shared_temp, 'pseudoCT_mlsc_%j.out')));

mode = 'success';
transport = struct('verify', @local_verify, 'submit_script', @local_submit, ...
    'query_squeue', @local_squeue, 'query_sacct', @local_sacct, ...
    'query_squeue_by_name', @local_squeue_by_name, ...
    'query_sacct_by_name', @local_sacct_by_name, ...
    'cancel_job', @local_cancel, 'sleep', @local_sleep);
runtime = struct('profile', 'mlsc', 'account', 'fixture-account', ...
    'script_path', fullfile(shared_temp, 'job.sh'), ...
    'evidence_dir', durable_success, 'log_archive_dir', durable_success, ...
    'cleanup_script', true, 'timeout_seconds', 10, ...
    'poll_interval_seconds', 1, 'accounting_timeout_seconds', 1, ...
    'max_polls', 2, 'max_accounting_polls', 1);

% The actual lifecycle entrypoint receives only injected transport responses.
result = mlsc_lifecycle(subject, config, runtime, transport);
assert(result.terminal && result.success && result.eligible_for_finalization);
assert(result.log_paths.archive_succeeded);
assert(exist(fullfile(durable_success, 'mlsc_evidence.mat'), 'file') == 2);
assert(exist(fullfile(durable_success, 'pseudoCT_mlsc_31415.out'), 'file') == 2);
assert(exist(fullfile(durable_success, 'pseudoCT_mlsc_31415.err'), 'file') == 2);
persisted = load(fullfile(durable_success, 'mlsc_evidence.mat'));
assert(persisted.snapshot.terminal && ...
    strcmp(persisted.snapshot.log_paths.stdout, ...
    fullfile(shared_temp, 'pseudoCT_mlsc_%j.out')));
assert(strcmp(persisted.snapshot.evidence_path, ...
    fullfile(durable_success, 'mlsc_evidence.mat')));
assert(strcmp(persisted.snapshot.log_paths.stdout_archive, ...
    fullfile(durable_success, 'pseudoCT_mlsc_31415.out')));
assert(persisted.snapshot.copy_back.verified);

% Local finalization may remove the shared subject temp; evidence and copied
% Slurm logs remain in the durable per-subject destination.
rmdir(shared_temp, 's');
result = mlsc_record_finalization(result, runtime, true, true, ...
    'Fixture finalization completed.');
persisted = load(fullfile(durable_success, 'mlsc_evidence.mat'));
assert(strcmp(persisted.snapshot.finalization_status, 'succeeded'));
assert(persisted.snapshot.finalization.succeeded);
assert(exist(fullfile(durable_success, 'pseudoCT_mlsc_31415.out'), 'file') == 2);
assert(exist(fullfile(durable_success, 'pseudoCT_mlsc_31415.err'), 'file') == 2);
summary_config = mlsc_legacy();
summary_options = struct('correct_aliasing', false, ...
    'recenter_before_normalization', true);
pseudo_CT_print_profile_summary('mlsc', summary_config, durable_success, ...
    struct('scope', 'test'), summary_options, result);
summary_text = fileread(fullfile(durable_success, ...
    'pseudo_CT_profile_summary.txt'));
assert(~isempty(strfind(summary_text, ...
    'Requested aliasing correction: No')));
assert(~isempty(strfind(summary_text, ...
    'Confirmed aliasing correction: Not confirmed')));
assert(~isempty(strfind(summary_text, 'Requested recentering: Yes')));
assert(~isempty(strfind(summary_text, ...
    'Confirmed recentering: Not confirmed')));
assert(~isempty(strfind(summary_text, 'Canonical profile ID: mlsc')));
assert(~isempty(strfind(summary_text, ...
    'Configured host: mlsc.nmr.mgh.harvard.edu')));
assert(~isempty(strfind(summary_text, ...
    'Current-run MLSC scheduler state: completed')));
assert(~isempty(strfind(summary_text, ...
    'Current-run local finalization: succeeded')));
assert(~isempty(strfind(summary_text, ...
    'Executor hostname: Not confirmed')));
assert(~isempty(strfind(summary_text, ...
    'Executor CPU: Not confirmed')));
assert(~isempty(strfind(summary_text, ...
    'Executor runtime/build: Not confirmed')));

% A scheduler failure receives terminal evidence and durable logs too, while
% local finalization is explicitly recorded as not attempted.
mkdir(shared_temp);
local_touch(input_path);
mode = 'failed';
runtime.script_path = fullfile(shared_temp, 'job.sh');
runtime.evidence_dir = durable_failure;
runtime.log_archive_dir = durable_failure;
result = mlsc_lifecycle(subject, config, runtime, transport);
assert(result.terminal && ~result.success && strcmp(result.state, 'failed'));
assert(result.log_paths.archive_succeeded);
result = mlsc_record_finalization(result, runtime, false, false, ...
    'Scheduler failure prevented local finalization.');
persisted = load(fullfile(durable_failure, 'mlsc_evidence.mat'));
assert(persisted.snapshot.terminal && strcmp(persisted.snapshot.state, 'failed'));
assert(strcmp(persisted.snapshot.finalization_status, 'not_attempted'));
assert(~persisted.snapshot.copy_back.verified);
assert(exist(fullfile(durable_failure, 'pseudoCT_mlsc_31415.out'), 'file') == 2);
assert(exist(fullfile(durable_failure, 'pseudoCT_mlsc_31415.err'), 'file') == 2);

% The production dispatch must pass durable per-subject destinations into the
% lifecycle rather than using the old empty evidence directory.
entry_source = local_read(fullfile(root_dir, 'run_pseudo_CT.m'));
assert(~isempty(strfind(entry_source, ...
    '''evidence_dir'', jobs(ii).processing_dir')));
assert(~isempty(strfind(entry_source, ...
    '''log_archive_dir'', jobs(ii).processing_dir')));
assert(~isempty(strfind(entry_source, 'mlsc_record_finalization')));
% The helper/lifecycle checks above do not execute the user-facing entrypoint.
% Protect its pre-dispatch summary and current-run finalization refresh wiring.
assert(~isempty(strfind(entry_source, ...
    'pseudo_CT_print_profile_summary(profile_name, config, processing_dirs, run_context)')));
assert(~isempty(strfind(entry_source, ...
    'local_mlsc_summary_evidence_ready(lifecycle)')));
assert(~isempty(strfind(entry_source, ...
    'local_job_summary_options(jobs(ii)), lifecycle')));

% T006: all 12 user-facing MLSC event classes with the explicit 1-8
% mapping, retained stages 5-8, secret-free output, and untouched
% local/Launchpad paths. Static dispatch wiring plus injected lifecycle
% evidence; no live SSH, Slurm submission, or pseudoCT/MCR processing.
entry_source = local_read(fullfile(root_dir, 'run_pseudo_CT.m'));
lifecycle_source = local_read(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_lifecycle.m'));
% Events 1-5 wire in the production entrypoint.
assert(~isempty(strfind(entry_source, ...
    'MLSC connection and authentication succeeded.')));
assert(~isempty(strfind(entry_source, 'Discovered %d Slurm account(s).')));
assert(~isempty(strfind(entry_source, 'Selected MLSC account %s.')));
assert(~isempty(strfind(entry_source, 'Preparing input MPRAGE.')));
assert(~isempty(strfind(entry_source, 'Submitting MLSC job.')));
% Events 6-11 render inside the lifecycle seam with job/state/exit/elapsed.
assert(~isempty(strfind(lifecycle_source, 'MLSC job %d accepted.')));
assert(~isempty(strfind(lifecycle_source, 'as observed')));
assert(~isempty(strfind(lifecycle_source, 'MLSC job %d state %s.')));
assert(~isempty(strfind(lifecycle_source, ...
    'MLSC job %d still pending (elapsed %s).')));
assert(~isempty(strfind(lifecycle_source, ...
    'MLSC job %d still running (elapsed %s).')));
assert(isempty(strfind(lifecycle_source, ...
    'MLSC job %d state %s elapsed %s.')));
assert(~isempty(strfind(lifecycle_source, ...
    'MLSC job %d %s exit %s elapsed %s.')));
assert(~isempty(strfind(lifecycle_source, 'MLSC stage-in completed.')));
assert(~isempty(strfind(lifecycle_source, 'MLSC normalization started.')));
assert(~isempty(strfind(lifecycle_source, 'MLSC pseudo-CT started.')));
assert(~isempty(strfind(lifecycle_source, 'MLSC verification started.')));
assert(~isempty(strfind(lifecycle_source, 'MLSC copy-back started.')));
assert(~isempty(strfind(lifecycle_source, ...
    'MLSC verified return to shared temp completed.')));
% Event 12 returns to local finalization before the retained flow.
assert(~isempty(strfind(entry_source, ...
    'returning to local finalization.')));
t006_return_pos = strfind(entry_source, ...
    'returning to local finalization.');
t006_finalize_pos = strfind(entry_source, ...
    'finalization_success = local_finalize_remote_subject');
assert(t006_return_pos(1) < t006_finalize_pos(1));
% Explicit 1-8 mapping: 1 input, 2 submit, 3 Running for
% stage-in/normalize/pseudoCT/running/heartbeat, 4 Retrieving for
% verify/copy-back/verified return, then retained 5-8.
assert(~isempty(strfind(entry_source, ...
    'local_stage_context(context, 1)')));
assert(~isempty(strfind(entry_source, ...
    'local_stage_context(context, 2)')));
assert(~isempty(strfind(entry_source, 'Submitting MLSC job.')));
assert(~isempty(strfind(lifecycle_source, 'stage_index = 3')));
assert(~isempty(strfind(lifecycle_source, 'stage_index = 4')));
assert(~isempty(strfind(lifecycle_source, 'stage_count = 8')));
assert(~isempty(strfind(entry_source, ...
    'Applying local post-processing.')));
assert(~isempty(strfind(entry_source, 'Writing DICOM output.')));
assert(~isempty(strfind(entry_source, 'Promoting final outputs.')));
assert(~isempty(strfind(entry_source, 'Cleaning up temporary files.')));
assert(~isempty(strfind(entry_source, ...
    '''cleanup_script'', true')));
% Accepted numeric job ID propagates through finalization tags.
assert(~isempty(strfind(entry_source, 'local_mlsc_job_id')));
assert(~isempty(strfind(entry_source, 'job_number')));
% Secret denial in user-facing MLSC output wiring.
t006_output_lines = regexp(entry_source, '\r\n|\n|\r', 'split');
for t006_kk = 1:length(t006_output_lines)
    t006_line = t006_output_lines{t006_kk};
    if ~isempty(strfind(t006_line, 'authentication succeeded')) || ...
            ~isempty(strfind(t006_line, 'Slurm account')) || ...
            ~isempty(strfind(t006_line, 'Submitting MLSC job')) || ...
            ~isempty(strfind(t006_line, 'returning to local finalization'))
        assert(isempty(strfind(t006_line, 'PASSWORD')));
        assert(isempty(strfind(t006_line, 'USERNAME')));
    end
end
assert(isempty(strfind(lifecycle_source, 'PASSWORD')));
% Local and Launchpad paths stay behaviorally untouched.
assert(~isempty(strfind(entry_source, 'batch_pseudo_CT_launchpad')));
assert(~isempty(strfind(entry_source, 'local_finalize_remote_subject')));
launchpad_source = local_read(fullfile(root_dir, 'src', 'launchpad', ...
    'batch_pseudo_CT_launchpad.m'));
assert(isempty(strfind(launchpad_source, 'mlsc_progress')));
assert(isempty(strfind(launchpad_source, '.mlsc_progress')));
assert(isempty(strfind(launchpad_source, 'mlsc_lifecycle')));
assert(isempty(strfind(launchpad_source, 'MLSC verified return')));
assert(exist(fullfile(root_dir, 'src', 'config', 'profiles', ...
    'local_current.m'), 'file') == 2);
assert(exist(fullfile(root_dir, 'src', 'config', 'profiles', ...
    'local_mprage_only.m'), 'file') == 2);
% R2010b-era parse compatibility for every touched dispatch seam.
t006_parse_targets = {fullfile(root_dir, 'run_pseudo_CT.m'); ...
    fullfile(root_dir, 'src', 'mlsc', 'mlsc_lifecycle.m'); ...
    fullfile(root_dir, 'src', 'mlsc', 'mlsc_generate_slurm_script.m'); ...
    fullfile(root_dir, 'src', 'mlsc', 'mlsc_progress.m')};
for t006_kk = 1:length(t006_parse_targets)
    try
        mlint(t006_parse_targets{t006_kk});
    catch t006_ME %#ok<NASGU>
        assert(false, 'MLSC dispatch seam failed to parse.');
    end
end

% T003: canonical MLSC observability UX wiring. Static only; no live SSH,
% Slurm submission, processing, MCR, or protocol/profile changes.
% Exactly the three connection/account messages render through the mlsc
% scope tag; the formatter itself stays generic.
t003_entry_lines = regexp(entry_source, '\r\n|\n|\r', 'split');
t003_mlsc_calls = 0;
for t003_kk = 1:length(t003_entry_lines)
    if ~isempty(strfind(t003_entry_lines{t003_kk}, 'pseudo_CT_output')) && ...
            ~isempty(strfind(t003_entry_lines{t003_kk}, 'mlsc_context'))
        t003_mlsc_calls = t003_mlsc_calls + 1;
    end
end
assert(t003_mlsc_calls == 3);
assert(length(strfind(entry_source, '''scope'', ''mlsc''')) == 1);
t003_output_source = local_read(fullfile(root_dir, 'src', 'io', ...
    'pseudo_CT_output.m'));
assert(isempty(strfind(t003_output_source, 'mlsc')));
assert(isempty(strfind(t003_output_source, 'MLSC')));
% Accepted job keeps the numeric tag while explicitly rendering stage 2/8.
assert(~isempty(strfind(lifecycle_source, ...
    'local_stage_output_context(runtime, job_id, 2)')));
assert(~isempty(strfind(lifecycle_source, 'context.job_number = job_id')));
% Canonical heartbeats carry HH:MM:SS with one consistent phrase and no
% redundant state wording; the 30-second poll and 60-second heartbeat
% cadence is unchanged.
assert(~isempty(strfind(lifecycle_source, 'poll_interval_seconds = 30')));
assert(~isempty(strfind(lifecycle_source, ...
    'heartbeat_interval_seconds = 60')));
% Transient unknown is display-only: it returns before the output
% tracker's last displayed state or heartbeat deadline changes, while
% state history, evidence, and terminal output stay untouched.
t003_unknown_pos = strfind(lifecycle_source, ...
    'if strcmp(new_state, ''unknown'')');
t003_tracker_pos = strfind(lifecycle_source, ...
    'tracker.last_state = new_state;');
assert(~isempty(t003_unknown_pos) && ~isempty(t003_tracker_pos));
assert(t003_unknown_pos(1) < t003_tracker_pos(1));

% T009: finalization records the actual source/temp cleanup outcome.
% Local fixtures only; observation never deletes, preserving existing
% success-removes-source-after-archival and failure-preserves semantics.
t009_root = fullfile(test_root, 't009-cleanup');
mkdir(t009_root);
t009_evidence = fullfile(t009_root, 'durable');
mkdir(t009_evidence);
t009_shared = fullfile(t009_root, 'shared-temp');
mkdir(t009_shared);
t009_source = fullfile(t009_shared, '.mlsc_progress');
local_touch(t009_source);
t009_result = struct('shared_subject_temp', t009_shared, ...
    'progress', struct('source_path', t009_source));
t009_runtime = struct('evidence_dir', t009_evidence);
rmdir(t009_shared, 's');
t009_result = mlsc_record_finalization(t009_result, t009_runtime, ...
    true, true, 'Fixture finalization completed.');
assert(strcmp(t009_result.finalization.cleanup_outcome, 'removed'));
assert(~t009_result.finalization.shared_temp_exists);
assert(~t009_result.finalization.source_exists);
assert(strcmp(t009_result.finalization.shared_temp, t009_shared));
assert(strcmp(t009_result.finalization.source_path, t009_source));
assert(~isempty(t009_result.finalization.cleanup_detail));
assert(exist(t009_shared, 'dir') ~= 7);
assert(exist(t009_source, 'file') ~= 2);
t009_persisted = load(fullfile(t009_evidence, 'mlsc_evidence.mat'));
assert(strcmp(t009_persisted.snapshot.finalization.cleanup_outcome, ...
    'removed'));
assert(~t009_persisted.snapshot.finalization.shared_temp_exists);
assert(~t009_persisted.snapshot.finalization.source_exists);
assert(strcmp(t009_persisted.snapshot.finalization_status, 'succeeded'));
mkdir(t009_shared);
local_touch(t009_source);
t009_preserved = struct('shared_subject_temp', t009_shared, ...
    'progress', struct('source_path', t009_source));
t009_preserved = mlsc_record_finalization(t009_preserved, t009_runtime, ...
    true, false, 'Fixture finalization did not complete.');
assert(strcmp(t009_preserved.finalization.cleanup_outcome, 'preserved'));
assert(t009_preserved.finalization.shared_temp_exists);
assert(t009_preserved.finalization.source_exists);
assert(exist(t009_shared, 'dir') == 7);
assert(exist(t009_source, 'file') == 2);
t009_persisted = load(fullfile(t009_evidence, 'mlsc_evidence.mat'));
assert(strcmp(t009_persisted.snapshot.finalization.cleanup_outcome, ...
    'preserved'));
assert(t009_persisted.snapshot.finalization.shared_temp_exists);
assert(t009_persisted.snapshot.finalization.source_exists);
assert(strcmp(t009_persisted.snapshot.finalization_status, 'failed'));
t009_final_source = local_read(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_record_finalization.m'));
assert(~isempty(strfind(t009_final_source, ...
    'Minimum supported MATLAB: R2010b')));
assert(isempty(regexp(t009_final_source, ...
    '(^|[^A-Za-z0-9_])contains\(', 'once')));
assert(isempty(regexp(t009_final_source, ...
    '(^|[^A-Za-z0-9_])startsWith\(', 'once')));
assert(isempty(regexp(t009_final_source, ...
    '(^|[^A-Za-z0-9_])string\(', 'once')));
try
    mlint(fullfile(root_dir, 'src', 'mlsc', ...
        'mlsc_record_finalization.m'));
catch t009_ME %#ok<NASGU>
    assert(false, 'MLSC finalization seam failed to parse.');
end

fprintf('=== MLSC dispatch integration tests passed: durable success/failure evidence and logs ===\n');

    function accepted = local_verify()
        accepted = true;
    end

    function response = local_submit(~)
        local_touch(fullfile(shared_temp, 'pseudoCT_mlsc_31415.out'));
        local_touch(fullfile(shared_temp, 'pseudoCT_mlsc_31415.err'));
        if strcmp(mode, 'success')
            local_touch(fullfile(shared_temp, 'att_map.nii'));
        end
        response = '31415;mlsc';
    end

    function response = local_squeue(~)
        response = 'RUNNING';
    end

    function response = local_sacct(~)
        if strcmp(mode, 'failed')
            response = '31415|FAILED|2:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60';
        else
            response = '31415|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60';
        end
    end

    function response = local_squeue_by_name(~)
        response = '';
    end

    function response = local_sacct_by_name(~)
        response = '';
    end

    function local_cancel(~)
    end

    function local_sleep(~)
    end
end

function local_touch(path_name)
fid = fopen(path_name, 'w');
assert(fid ~= -1, 'The MLSC integration fixture could not be created.');
fwrite(fid, 'fixture');
fclose(fid);
end

function text = local_read(path_name)
fid = fopen(path_name, 'r');
assert(fid ~= -1, 'The MLSC integration source could not be read.');
text = fread(fid, inf, '*char')';
fclose(fid);
end

function local_cleanup(directory)
if exist(directory, 'dir') == 7
    rmdir(directory, 's');
end
end
