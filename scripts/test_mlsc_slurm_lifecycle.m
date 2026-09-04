function test_mlsc_slurm_lifecycle()
%TEST_MLSC_SLURM_LIFECYCLE Focused credential-free MLSC lifecycle checks.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'mlsc'));
addpath(fullfile(root_dir, 'src', 'io'));

assert(mlsc_parse_sbatch_job_id({'sbatch warning'; '31415;mlsc'}) == 31415);
assert_error(@() mlsc_parse_sbatch_job_id('Submitted batch job 31415'));
assert_error(@() mlsc_parse_sbatch_job_id({'31415'; '31416'}));

assert(strcmp(mlsc_parse_squeue_state('PENDING'), 'pending'));
assert(strcmp(mlsc_parse_squeue_state('COMPLETING+'), 'running'));
assert(strcmp(mlsc_parse_squeue_state('OUT_OF_MEMORY'), 'OUT_OF_MEMORY'));
assert(strcmp(mlsc_parse_squeue_state('NODE_FAIL'), 'NODE_FAIL'));
assert(strcmp(mlsc_parse_squeue_state(sprintf('\n')), 'unknown'));
assert(strcmp(mlsc_parse_squeue_state('human output'), 'unknown'));

sacct = {'31415.batch|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60'; ...
    '31415.extern|FAILED|1:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60'; ...
    '31415|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60'};
record = mlsc_parse_sacct_terminal(sacct, 31415);
assert(record.found && record.primary_allocation && record.terminal);
assert(strcmp(record.state, 'completed'));
assert(record.exit_code == 0 && record.exit_signal == 0);
assert(strcmp(record.start_time, '2026-09-02T10:00:00'));

record = mlsc_parse_sacct_terminal( ...
    '31416|OUT_OF_MEMORY|0:9|2026-09-02T10:00:00|2026-09-02T10:01:00|60', 31416);
assert(strcmp(record.state, 'OUT_OF_MEMORY') && record.exit_signal == 9);
record = mlsc_parse_sacct_terminal( ...
    '31417|NODE_FAIL|1:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60', 31417);
assert(strcmp(record.state, 'NODE_FAIL') && record.exit_code == 1);
record = mlsc_parse_sacct_terminal( ...
    '31418|CANCELLED by 42|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60', 31418);
assert(strcmp(record.state, 'cancelled'));
record = mlsc_parse_sacct_terminal( ...
    '31419|MYSTERY_STATE|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60', 31419);
assert(strcmp(record.state, 'unknown') && ~record.terminal);
record = mlsc_parse_sacct_terminal(sacct, 31420);
assert(~record.found && ~record.terminal);

values = struct('profile', 'mlsc', 'runtime_account', 'project', ...
    'job_id', 31415, 'state', 'completed', 'exit_code', 0, ...
    'network_payload_staging', false, 'scp_used', false);
first = mlsc_evidence('init', values);
second = mlsc_evidence('init', values);
assert(isequal(first, second));
next = mlsc_evidence('terminal', first, struct('eligible_for_finalization', false));
next = mlsc_evidence('cleanup', next, struct('cleanup', ...
    struct('attempted', true, 'script_removed', true)));
assert(strcmp(next.schema, 'pseudo-CT.mlsc-evidence/v1'));
assert(strcmp(next.runtime_account, 'project') && next.job_id == 31415);
assert(isequal(next.lifecycle, {'init', 'terminal', 'cleanup'}));

evidence_dir = tempname;
mkdir(evidence_dir);
mlsc_evidence('write', evidence_dir, next);
loaded = load(fullfile(evidence_dir, 'mlsc_evidence.mat'));
assert(strcmp(loaded.snapshot.schema, 'pseudo-CT.mlsc-evidence/v1'));
rmdir(evidence_dir, 's');

assert_error(@() mlsc_evidence('init', struct('password', 'not persisted')));

% The lifecycle seam is exercised with callbacks only; no Slurm command runs.
temp_root = tempname;
mkdir(temp_root);
mkdir(fullfile(temp_root, 'mcr'));
mkdir(fullfile(temp_root, 'Batch_atlas'));
local_touch(fullfile(temp_root, 'runner.sh'));
local_touch(fullfile(temp_root, 'defaults.mat'));
local_touch(fullfile(temp_root, 'freesurfer-env'));
subject = struct('subject_id', 'subject-01', ...
    'shared_input', fullfile(temp_root, 'mprage.nii'), ...
    'shared_temp', temp_root);
local_touch(subject.shared_input);
config = struct();
config.mode = 'mlsc';
config.aliasing_default = 1;
config.mlsc = struct('host', 'mlsc.nmr.mgh.harvard.edu', ...
    'runner', fullfile(temp_root, 'runner.sh'), ...
    'mcr_root', fullfile(temp_root, 'mcr'), ...
    'defaults_mat', fullfile(temp_root, 'defaults.mat'), ...
    'batch_templates', fullfile(temp_root, 'Batch_atlas'), ...
    'shell', '/bin/bash', 'freesurfer_env', ...
    fullfile(temp_root, 'freesurfer-env'), 'partition', 'basic', ...
    'nodes', 1, 'ntasks', 1, 'cpus_per_task', 1, 'memory', '1G', ...
    'time', '00:01:00');
runtime = struct('account', 'project', ...
    'script_path', fullfile(temp_root, 'job.sh'), ...
    'evidence_dir', temp_root, 'timeout_seconds', 10, ...
    'poll_interval_seconds', 1, 'accounting_timeout_seconds', 1, ...
    'max_polls', 3, 'max_accounting_polls', 2, ...
    'max_reconciliation_polls', 2, ...
    'reconciliation_interval_seconds', 1);
mode = 'success';
squeue_calls = 0;
sacct_calls = 0;
cancel_calls = 0;
submit_calls = 0;
reconciliation_squeue_calls = 0;
reconciliation_sacct_calls = 0;
transport = struct('verify', @local_verify, 'submit_script', @local_submit, ...
    'query_squeue', @local_squeue, 'query_sacct', @local_sacct, ...
    'query_squeue_by_name', @local_squeue_by_name, ...
    'query_sacct_by_name', @local_sacct_by_name, ...
    'cancel_job', @local_cancel, 'sleep', @local_sleep);
result = mlsc_lifecycle(subject, config, runtime, transport);
assert(result.terminal && result.success && result.eligible_for_finalization);
assert(strcmp(result.scheduler_state, 'completed') && result.copy_back.verified);
assert(result.primary_allocation && result.evidence_saved);
assert(sacct_calls == 2, 'The first delayed accounting response was not retried.');
assert(length(result.evidence.lifecycle) >= 3);
assert(~exist(runtime.script_path, 'file'));

% sbatch may accept the job while its parsable response is lost.  The unique
% receipt/job name is reconciled without a second submission, and the
% recovered primary allocation follows the ordinary lifecycle path.
mode = 'response_lost_recovered';
squeue_calls = 0;
sacct_calls = 0;
cancel_calls = 0;
reconciliation_squeue_calls = 0;
reconciliation_sacct_calls = 0;
submit_calls_before = submit_calls;
result = mlsc_lifecycle(subject, config, runtime, transport);
assert(result.terminal && result.success && result.job_id == 31416);
assert(result.submission_attempted && result.submission_response_lost && ...
    ~result.submission_response_parseable && result.submission_reconciled);
assert(strcmp(result.submission_outcome, 'recovered'));
assert(result.submission_reconciliation_attempts == 1);
assert(reconciliation_squeue_calls == 1 && reconciliation_sacct_calls == 1);
assert(submit_calls == submit_calls_before + 1, ...
    'Lost sbatch output caused a duplicate submission attempt.');
assert(~isempty(strfind(result.job_name, 'pseudoCT_')));
receipt_data = load(result.submission_receipt_path);
assert(strcmp(receipt_data.receipt.job_name, result.job_name));
assert(receipt_data.receipt.job_id == 31416 && ...
    receipt_data.receipt.reconciled && ...
    strcmp(receipt_data.receipt.submission_outcome, 'recovered'));
persisted = load(fullfile(runtime.evidence_dir, 'mlsc_evidence.mat'));
assert(persisted.snapshot.job_id == 31416 && ...
    persisted.snapshot.submission_response_lost && ...
    persisted.snapshot.submission_reconciled && ...
    strcmp(persisted.snapshot.submission_outcome, 'recovered'));
assert(~exist(runtime.script_path, 'file'));

mode = 'missing_map';
squeue_calls = 0;
sacct_calls = 0;
delete(fullfile(temp_root, 'att_map.nii'));
result = mlsc_lifecycle(subject, config, runtime, transport);
assert(result.terminal && ~result.success && ...
    strcmp(result.scheduler_state, 'completed'));
assert(~result.eligible_for_finalization && ~result.copy_back.verified);

mode = 'timeout';
squeue_calls = 0;
sacct_calls = 0;
cancel_calls = 0;
runtime.timeout_seconds = 1;
runtime.max_polls = 2;
runtime.max_accounting_polls = 1;
result = mlsc_lifecycle(subject, config, runtime, transport);
assert(strcmp(result.state, 'timeout') && result.cancel_requested);
assert(cancel_calls == 1 && result.terminal && ~result.success);
assert(~result.eligible_for_finalization);

% A recovered allocation can still time out.  Cancellation remains bounded to
% one request and generated submission metadata is cleaned up.
mode = 'response_lost_timeout';
squeue_calls = 0;
sacct_calls = 0;
cancel_calls = 0;
reconciliation_squeue_calls = 0;
reconciliation_sacct_calls = 0;
runtime.timeout_seconds = 1;
runtime.max_polls = 2;
runtime.max_accounting_polls = 2;
result = mlsc_lifecycle(subject, config, runtime, transport);
assert(result.terminal && ~result.success && result.job_id == 31417);
assert(result.submission_reconciled && result.cancel_requested && ...
    result.cancel_succeeded && cancel_calls == 1);
assert(reconciliation_squeue_calls <= runtime.max_reconciliation_polls && ...
    reconciliation_sacct_calls <= runtime.max_reconciliation_polls);
assert(result.cleanup.script_removed && ~exist(runtime.script_path, 'file'));
persisted = load(fullfile(runtime.evidence_dir, 'mlsc_evidence.mat'));
assert(persisted.snapshot.terminal && persisted.snapshot.job_id == 31417 && ...
    persisted.snapshot.cancel_requested && persisted.snapshot.cleanup.script_removed);

% A normal rejected sbatch response is not retried.  Reconciliation is still
% bounded, and terminal evidence records that no numeric allocation was found.
mode = 'ordinary_rejected';
squeue_calls = 0;
sacct_calls = 0;
cancel_calls = 0;
reconciliation_squeue_calls = 0;
reconciliation_sacct_calls = 0;
runtime.timeout_seconds = 10;
runtime.max_polls = 3;
runtime.max_accounting_polls = 2;
submit_calls_before = submit_calls;
result = mlsc_lifecycle(subject, config, runtime, transport);
assert(result.terminal && ~result.success && result.job_id == 0);
assert(result.submission_attempted && result.submission_response_lost && ...
    ~result.submission_reconciled && strcmp(result.submission_outcome, 'unresolved'));
assert(submit_calls == submit_calls_before + 1 && cancel_calls == 0);
assert(reconciliation_squeue_calls == runtime.max_reconciliation_polls && ...
    reconciliation_sacct_calls == runtime.max_reconciliation_polls);
assert(result.cleanup.script_removed && ~exist(runtime.script_path, 'file'));
persisted = load(fullfile(runtime.evidence_dir, 'mlsc_evidence.mat'));
assert(persisted.snapshot.terminal && persisted.snapshot.job_id == 0 && ...
    strcmp(persisted.snapshot.state, 'failed') && ...
    strcmp(persisted.snapshot.submission_outcome, 'unresolved') && ...
    persisted.snapshot.submission_attempted && ...
    persisted.snapshot.cleanup.script_removed);

% Polling exceptions after submission request cancellation, persist an
% interrupted terminal result, and remove the generated script metadata.
runtime.timeout_seconds = 10;
runtime.max_polls = 3;
runtime.max_accounting_polls = 2;
mode = 'scheduler_error';
squeue_calls = 0;
sacct_calls = 0;
cancel_calls = 0;
result = mlsc_lifecycle(subject, config, runtime, transport);
assert(result.terminal && result.interrupted && ~result.success);
assert(strcmp(result.state, 'interrupted') && ...
    strcmp(result.workflow_state, 'interrupted'));
assert(result.cancel_requested && result.cancel_succeeded && cancel_calls == 1);
assert(result.cleanup.script_removed && ~exist(runtime.script_path, 'file'));
assert(result.evidence_saved);
persisted = load(fullfile(runtime.evidence_dir, 'mlsc_evidence.mat'));
assert(persisted.snapshot.terminal && persisted.snapshot.interrupted && ...
    strcmp(persisted.snapshot.state, 'interrupted'));
assert(persisted.snapshot.cleanup.script_removed);

mode = 'sleep_error';
squeue_calls = 0;
sacct_calls = 0;
cancel_calls = 0;
result = mlsc_lifecycle(subject, config, runtime, transport);
assert(result.terminal && result.interrupted && result.cancel_requested);
assert(result.cancel_succeeded && cancel_calls == 1);
assert(result.cleanup.script_removed && ~exist(runtime.script_path, 'file'));
persisted = load(fullfile(runtime.evidence_dir, 'mlsc_evidence.mat'));
assert(persisted.snapshot.terminal && persisted.snapshot.interrupted && ...
    strcmp(persisted.snapshot.state, 'interrupted'));

mode = 'failed';
sacct_calls = 0;
result = mlsc_lifecycle(subject, config, runtime, transport);
assert(result.terminal && ~result.success && ~result.eligible_for_finalization);
assert(strcmp(result.state, 'failed') && result.exit_code == 2);
assert(result.accounting_record_found && result.primary_allocation);

% Regression C: a backend exception retains the underlying identifier/message
% in failure_detail, lifecycle evidence, the persisted lifecycle record, and
% the corresponding lifecycle text-log output, without serializing sensitive
% transport/security material.  State, cleanup, and terminal semantics are
% preserved.
sensitive_password = 'S3CR3T-backend-decoy-7f3a';
sensitive_hostkey = 'HOSTKEY-material-decoy-9c2e';
exception_transport = transport;
exception_transport.password = sensitive_password;
exception_transport.host_key = sensitive_hostkey;
result = mlsc_lifecycle(subject, config, runtime, exception_transport);
assert(result.terminal && ~result.success && strcmp(result.state, 'failed'));
assert(strcmp(result.scheduler_state, 'unknown') && ...
    strcmp(result.workflow_state, 'failed'));
assert(~result.submitted && ~result.submission_accepted && result.job_id == 0);
assert(~result.eligible_for_finalization && result.failure.present);
assert(~isempty(strfind(result.failure_detail, ...
    'MLSC submission failed before a numeric Slurm job ID was accepted.')));
assert(~isempty(strfind(result.failure_detail, ...
    'pseudo_CT:MLSCTransportRejected')));
assert(~isempty(strfind(result.failure_detail, 'runtime closure')));
assert(~isempty(strfind(result.failure.detail, ...
    'pseudo_CT:MLSCTransportRejected')));
assert(~isempty(strfind(result.failure.detail, 'runtime closure')));
assert(~isempty(strfind(result.evidence.failure_detail, ...
    'pseudo_CT:MLSCTransportRejected')));
assert(~isempty(strfind(result.evidence.failure.detail, 'runtime closure')));
persisted = load(fullfile(runtime.evidence_dir, 'mlsc_evidence.mat'));
assert(~isempty(strfind(persisted.snapshot.failure_detail, ...
    'pseudo_CT:MLSCTransportRejected')));
assert(~isempty(strfind(persisted.snapshot.failure.detail, ...
    'runtime closure')));
assert(~isempty(strfind(persisted.snapshot.failure_detail, ...
    'MLSC submission failed before a numeric Slurm job ID was accepted.')));
assert(isempty(strfind(result.failure_detail, sensitive_password)));
assert(isempty(strfind(result.failure_detail, sensitive_hostkey)));
assert(isempty(strfind(result.failure.detail, sensitive_password)));
assert(isempty(strfind(result.failure.detail, sensitive_hostkey)));
assert(isempty(strfind(result.evidence.failure_detail, sensitive_password)));
assert(isempty(strfind(result.evidence.failure_detail, sensitive_hostkey)));
assert(isempty(strfind(persisted.snapshot.failure_detail, ...
    sensitive_password)));
assert(isempty(strfind(persisted.snapshot.failure_detail, ...
    sensitive_hostkey)));
assert(isempty(strfind(persisted.snapshot.failure.detail, ...
    sensitive_password)));
assert(isempty(strfind(persisted.snapshot.failure.detail, ...
    sensitive_hostkey)));
assert(~isfield(result.evidence, 'password') && ...
    ~isfield(result.evidence, 'transport') && ...
    ~isfield(result.evidence, 'host_key'));
assert(~isfield(persisted.snapshot, 'password') && ...
    ~isfield(persisted.snapshot, 'transport') && ...
    ~isfield(persisted.snapshot, 'host_key'));
% The production lifecycle log path reports lifecycle.failure_detail with the
% same wrapper (run_pseudo_CT.m:388-396), so the injected identifier/message
% must reach that text-log output while the injected transport
% password/host-key decoys remain absent.  Local/injected seams only.
lifecycle_log = fullfile(temp_root, 'lifecycle-regression-C.log');
lifecycle_context = struct('log_file', lifecycle_log, ...
    'subject_index', 1, 'subject_count', 1, 'scope', 'subject');
lifecycle_failure_detail = result.failure_detail;
if isempty(lifecycle_failure_detail)
    lifecycle_failure_detail = ...
        'MLSC output was not verified in the shared subject temporary directory.';
end
lifecycle_console = evalc(['pseudo_CT_output(''ERROR'', lifecycle_context, ' ...
    '''Subject failed before local finalization: %s'', lifecycle_failure_detail);']);
lifecycle_fid = fopen(lifecycle_log, 'r');
assert(lifecycle_fid ~= -1, 'The lifecycle text-log output was not written.');
lifecycle_log_text = fread(lifecycle_fid, inf, '*char')';
fclose(lifecycle_fid);
assert(~isempty(strfind(lifecycle_log_text, ...
    'Subject failed before local finalization:')));
assert(~isempty(strfind(lifecycle_log_text, ...
    'MLSC submission failed before a numeric Slurm job ID was accepted.')));
assert(~isempty(strfind(lifecycle_log_text, ...
    'pseudo_CT:MLSCTransportRejected')));
assert(~isempty(strfind(lifecycle_log_text, 'runtime closure')));
assert(~isempty(strfind(lifecycle_console, ...
    'pseudo_CT:MLSCTransportRejected')));
assert(~isempty(strfind(lifecycle_console, 'runtime closure')));
assert(isempty(strfind(lifecycle_log_text, sensitive_password)));
assert(isempty(strfind(lifecycle_log_text, sensitive_hostkey)));
assert(isempty(strfind(lifecycle_console, sensitive_password)));
assert(isempty(strfind(lifecycle_console, sensitive_hostkey)));
assert(result.cleanup.attempted && ~result.cleanup.script_removed);
assert(result.evidence_saved);

% T006: deterministic progress-protocol, output, and retention contract.
% Local fixtures with injected callbacks and fake clocks only; no SSH,
% Slurm submission, or pseudoCT/MCR execution is invoked.
t006_case_root_current = '';
t006_correlation_current = '';
t006_squeue_seq = {'RUNNING'};
t006_squeue_idx = 0;
t006_sacct_seq = {''};
t006_sacct_idx = 0;
t006_clock_base = datenum(2026, 9, 2, 10, 0, 0);
t006_clock_step = 1;
t006_submit_calls = 0;
t006_cancel_calls = 0;
t006_progress_seed = cell(0, 1);
t006_squeue_appends = cell(0, 1);
t006_expected = {'stage_in|done'; 'normalize|start'; 'normalize|done'; ...
    'pseudoCT|start'; 'pseudoCT|done'; 'verify|start'; 'verify|done'; ...
    'copy_back|start'; 'copy_back|done'};

% Protocol unit: bounded set, incremental-once, missing/delayed/partial,
% malformed/unknown/secret tolerance, and duplicate suppression.
t006_prog_root = fullfile(temp_root, 't006-protocol');
mkdir(t006_prog_root);
t006_prog_path = fullfile(t006_prog_root, '.mlsc_progress');
assert(isequal(mlsc_progress('records'), t006_expected));
assert(strcmp(mlsc_progress('filename'), '.mlsc_progress'));
assert(strcmp(mlsc_progress('path', t006_prog_root), t006_prog_path));
t006_cursor = mlsc_progress('init');
assert(t006_cursor.offset == 0 && isempty(t006_cursor.pending) && ...
    isempty(t006_cursor.emitted));
[t006_events, t006_cursor] = mlsc_progress('consume', t006_prog_path, ...
    t006_cursor);
assert(isempty(t006_events));
t006_fid = fopen(t006_prog_path, 'w');
assert(t006_fid ~= -1);
fwrite(t006_fid, ['stage_in|done' char(10) 'normalize|start' char(10)]);
fclose(t006_fid);
[t006_events, t006_cursor] = mlsc_progress('consume', t006_prog_path, ...
    t006_cursor);
assert(isequal(t006_events, {'stage_in|done'; 'normalize|start'}));
[t006_repeat, t006_cursor] = mlsc_progress('consume', t006_prog_path, ...
    t006_cursor);
assert(isempty(t006_repeat));
t006_fid = fopen(t006_prog_path, 'a');
assert(t006_fid ~= -1);
fwrite(t006_fid, 'pseudoCT|sta');
fclose(t006_fid);
[t006_events, t006_cursor] = mlsc_progress('consume', t006_prog_path, ...
    t006_cursor);
assert(isempty(t006_events));
assert(strcmp(t006_cursor.pending, 'pseudoCT|sta'));
t006_fid = fopen(t006_prog_path, 'a');
assert(t006_fid ~= -1);
fwrite(t006_fid, ['rt' char(10)]);
fclose(t006_fid);
[t006_events, t006_cursor] = mlsc_progress('consume', t006_prog_path, ...
    t006_cursor);
assert(isequal(t006_events, {'pseudoCT|start'}));
t006_fid = fopen(t006_prog_path, 'a');
assert(t006_fid ~= -1);
fwrite(t006_fid, ['bogus|line' char(10) 'stage_in|done' char(10) ...
    'password=hunter2-secret' char(10) 'pseudoCT|done' char(10) ...
    'pseudoCT|done' char(10)]);
fclose(t006_fid);
[t006_events, t006_cursor] = mlsc_progress('consume', t006_prog_path, ...
    t006_cursor);
assert(isequal(t006_events, {'pseudoCT|done'}));
[t006_repeat, t006_cursor] = mlsc_progress('consume', t006_prog_path, ...
    t006_cursor);
assert(isempty(t006_repeat));

% S1: pending-first observed-initial state, ordered one-time transitions,
% no per-poll spam, and terminal job/state/exit/elapsed summary.
t006_s1_root = fullfile(temp_root, 't006-s1');
mkdir(t006_s1_root);
mkdir(fullfile(t006_s1_root, 'mcr'));
mkdir(fullfile(t006_s1_root, 'Batch_atlas'));
local_touch(fullfile(t006_s1_root, 'runner.sh'));
local_touch(fullfile(t006_s1_root, 'defaults.mat'));
local_touch(fullfile(t006_s1_root, 'freesurfer-env'));
local_touch(fullfile(t006_s1_root, 'mprage.nii'));
t006_case_root_current = t006_s1_root;
t006_correlation_current = 't006s1';
t006_subject = struct('subject_id', 't006-s1', 'shared_input', ...
    fullfile(t006_s1_root, 'mprage.nii'), 'shared_temp', t006_s1_root);
t006_config = struct();
t006_config.mode = 'mlsc';
t006_config.aliasing_default = 1;
t006_config.mlsc = struct('host', 'mlsc.nmr.mgh.harvard.edu', ...
    'runner', fullfile(t006_s1_root, 'runner.sh'), ...
    'mcr_root', fullfile(t006_s1_root, 'mcr'), ...
    'defaults_mat', fullfile(t006_s1_root, 'defaults.mat'), ...
    'batch_templates', fullfile(t006_s1_root, 'Batch_atlas'), ...
    'shell', '/bin/bash', 'freesurfer_env', ...
    fullfile(t006_s1_root, 'freesurfer-env'), 'partition', 'basic', ...
    'nodes', 1, 'ntasks', 1, 'cpus_per_task', 1, 'memory', '1G', ...
    'time', '00:01:00');
t006_log = fullfile(t006_s1_root, 'output.log');
t006_runtime = struct('account', 'project', ...
    'script_path', fullfile(t006_s1_root, 'job.sh'), ...
    'evidence_dir', t006_s1_root, 'log_archive_dir', t006_s1_root, ...
    'timeout_seconds', 10000, 'poll_interval_seconds', 1, ...
    'accounting_timeout_seconds', 1, 'max_polls', 4, ...
    'max_accounting_polls', 2, 'output_context', struct('log_file', ...
    t006_log, 'subject_index', 1, 'subject_count', 1, 'scope', 'subject'));
t006_runtime.submission_correlation_id = t006_correlation_current;
t006_squeue_seq = {'PENDING'; 'RUNNING'};
t006_squeue_idx = 0;
t006_sacct_seq = {''; ...
    '31415|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60'};
t006_sacct_idx = 0;
t006_clock_step = 1;
t006_submit_calls = 0;
t006_cancel_calls = 0;
t006_progress_seed = cell(0, 1);
t006_squeue_appends = cell(0, 1);
t006_transport = struct('verify', @t006_verify, ...
    'submit_script', @t006_submit, 'query_squeue', @t006_squeue, ...
    'query_sacct', @t006_sacct, ...
    'query_squeue_by_name', @t006_empty_name, ...
    'query_sacct_by_name', @t006_empty_name, ...
    'cancel_job', @t006_cancel, 'sleep', @t006_sleep, ...
    'clock', @t006_clock);
t006_result = mlsc_lifecycle(t006_subject, t006_config, t006_runtime, ...
    t006_transport);
t006_text = t006_read_text(t006_log);
assert(t006_result.terminal && t006_result.success);
assert(~isempty(strfind(t006_text, 'MLSC job 31415 accepted.')));
assert(~isempty(strfind(t006_text, 'state pending.')));
assert(~isempty(strfind(t006_text, 'state running.')));
t006_pending_pos = strfind(t006_text, 'state pending.');
t006_running_pos = strfind(t006_text, 'state running.');
assert(t006_pending_pos(1) < t006_running_pos(1));
assert(t006_count(t006_text, 'state pending.') == 1);
assert(t006_count(t006_text, 'state running.') == 1);
assert(isempty(strfind(t006_text, 'state pending elapsed')));
assert(isempty(strfind(t006_text, 'state running elapsed')));
assert(~isempty(strfind(t006_text, 'exit 0')));
assert(~isempty(strfind(t006_text, 'elapsed')));
assert(~isempty(strfind(t006_text, '[job 31415]')));
t006_accepted_lines = regexp(t006_text, '\r\n|\n|\r', 'split');
t006_accepted_hit = false;
for t006_kk = 1:length(t006_accepted_lines)
    if ~isempty(strfind(t006_accepted_lines{t006_kk}, ...
            'MLSC job 31415 accepted.'))
        t006_accepted_hit = true;
        assert(~isempty(strfind(t006_accepted_lines{t006_kk}, ...
            '[stage 2/8]')));
        assert(~isempty(strfind(t006_accepted_lines{t006_kk}, ...
            '[job 31415]')));
    end
    if ~isempty(strfind(t006_accepted_lines{t006_kk}, ...
            'state pending.')) || ...
            ~isempty(strfind(t006_accepted_lines{t006_kk}, ...
            'state running.'))
        assert(~isempty(strfind(t006_accepted_lines{t006_kk}, ...
            '[stage 3/8]')));
        assert(~isempty(strfind(t006_accepted_lines{t006_kk}, ...
            '[job 31415]')));
    end
end
assert(t006_accepted_hit);
assert(isempty(strfind(t006_text, 'state=')));

% S2: already-running first observation emits running directly with no
% fabricated pending, and duplicate running observations emit once.
t006_s2_root = fullfile(temp_root, 't006-s2');
mkdir(t006_s2_root);
mkdir(fullfile(t006_s2_root, 'mcr'));
mkdir(fullfile(t006_s2_root, 'Batch_atlas'));
local_touch(fullfile(t006_s2_root, 'runner.sh'));
local_touch(fullfile(t006_s2_root, 'defaults.mat'));
local_touch(fullfile(t006_s2_root, 'freesurfer-env'));
local_touch(fullfile(t006_s2_root, 'mprage.nii'));
t006_case_root_current = t006_s2_root;
t006_correlation_current = 't006s2';
t006_subject = struct('subject_id', 't006-s2', 'shared_input', ...
    fullfile(t006_s2_root, 'mprage.nii'), 'shared_temp', t006_s2_root);
t006_config.mlsc.runner = fullfile(t006_s2_root, 'runner.sh');
t006_config.mlsc.mcr_root = fullfile(t006_s2_root, 'mcr');
t006_config.mlsc.defaults_mat = fullfile(t006_s2_root, 'defaults.mat');
t006_config.mlsc.batch_templates = fullfile(t006_s2_root, 'Batch_atlas');
t006_config.mlsc.freesurfer_env = fullfile(t006_s2_root, 'freesurfer-env');
t006_log = fullfile(t006_s2_root, 'output.log');
t006_runtime.script_path = fullfile(t006_s2_root, 'job.sh');
t006_runtime.evidence_dir = t006_s2_root;
t006_runtime.log_archive_dir = t006_s2_root;
t006_runtime.output_context = struct('log_file', t006_log, ...
    'subject_index', 1, 'subject_count', 1, 'scope', 'subject');
t006_runtime.submission_correlation_id = t006_correlation_current;
t006_squeue_seq = {'RUNNING'; 'RUNNING'; 'RUNNING'};
t006_squeue_idx = 0;
t006_sacct_seq = {''; ''; ...
    '31415|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60'};
t006_sacct_idx = 0;
t006_clock_step = 1;
t006_submit_calls = 0;
t006_cancel_calls = 0;
t006_progress_seed = cell(0, 1);
t006_squeue_appends = cell(0, 1);
t006_result = mlsc_lifecycle(t006_subject, t006_config, t006_runtime, ...
    t006_transport);
t006_text = t006_read_text(t006_log);
assert(t006_result.terminal && t006_result.success);
assert(~isempty(strfind(t006_text, 'state running.')));
assert(isempty(strfind(t006_text, 'state pending')));
assert(t006_count(t006_text, 'state running.') == 1);

% S3: bounded 60-second heartbeat carries job ID, state, and elapsed at
% stage 3 while pending persists without extra queries or sleeps.
t006_s3_root = fullfile(temp_root, 't006-s3');
mkdir(t006_s3_root);
mkdir(fullfile(t006_s3_root, 'mcr'));
mkdir(fullfile(t006_s3_root, 'Batch_atlas'));
local_touch(fullfile(t006_s3_root, 'runner.sh'));
local_touch(fullfile(t006_s3_root, 'defaults.mat'));
local_touch(fullfile(t006_s3_root, 'freesurfer-env'));
local_touch(fullfile(t006_s3_root, 'mprage.nii'));
t006_case_root_current = t006_s3_root;
t006_correlation_current = 't006s3';
t006_subject = struct('subject_id', 't006-s3', 'shared_input', ...
    fullfile(t006_s3_root, 'mprage.nii'), 'shared_temp', t006_s3_root);
t006_config.mlsc.runner = fullfile(t006_s3_root, 'runner.sh');
t006_config.mlsc.mcr_root = fullfile(t006_s3_root, 'mcr');
t006_config.mlsc.defaults_mat = fullfile(t006_s3_root, 'defaults.mat');
t006_config.mlsc.batch_templates = fullfile(t006_s3_root, 'Batch_atlas');
t006_config.mlsc.freesurfer_env = fullfile(t006_s3_root, 'freesurfer-env');
t006_log = fullfile(t006_s3_root, 'output.log');
t006_runtime.script_path = fullfile(t006_s3_root, 'job.sh');
t006_runtime.evidence_dir = t006_s3_root;
t006_runtime.log_archive_dir = t006_s3_root;
t006_runtime.submission_correlation_id = t006_correlation_current;
t006_runtime.max_polls = 3;
t006_runtime.max_accounting_polls = 1;
t006_runtime.output_context = struct('log_file', t006_log, ...
    'subject_index', 1, 'subject_count', 1, 'scope', 'subject');
t006_squeue_seq = {'PENDING'; 'PENDING'; 'PENDING'};
t006_squeue_idx = 0;
t006_sacct_seq = {''};
t006_sacct_idx = 0;
t006_clock_step = 35;
t006_submit_calls = 0;
t006_cancel_calls = 0;
t006_progress_seed = cell(0, 1);
t006_squeue_appends = cell(0, 1);
t006_result = mlsc_lifecycle(t006_subject, t006_config, t006_runtime, ...
    t006_transport);
t006_text = t006_read_text(t006_log);
t006_lines = regexp(t006_text, '\r\n|\n|\r', 'split');
t006_heartbeats = 0;
for t006_kk = 1:length(t006_lines)
    if ~isempty(strfind(t006_lines{t006_kk}, 'still pending (elapsed '))
        t006_heartbeats = t006_heartbeats + 1;
        assert(~isempty(strfind(t006_lines{t006_kk}, '31415')));
        assert(~isempty(strfind(t006_lines{t006_kk}, '[stage 3/8]')));
        assert(~isempty(strfind(t006_lines{t006_kk}, '[job 31415]')));
        assert(isempty(strfind(t006_lines{t006_kk}, 'state=')));
    end
end
assert(t006_heartbeats == 1);
assert(~isempty(strfind(t006_text, ...
    'still pending (elapsed 00:01:45).')));
assert(isempty(strfind(t006_text, 'state pending elapsed')));
assert(isempty(strfind(t006_text, 'state running elapsed')));
assert(isempty(strfind(t006_text, 'still running (elapsed ')));
assert(t006_squeue_idx == 3);
assert(~isempty(strfind(t006_text, 'MLSC job 31415 accepted.')));

% S4: a real transition resets the heartbeat deadline, so the same 35s
% cadence that fired above stays silent across a pending-to-running change.
t006_s4_root = fullfile(temp_root, 't006-s4');
mkdir(t006_s4_root);
mkdir(fullfile(t006_s4_root, 'mcr'));
mkdir(fullfile(t006_s4_root, 'Batch_atlas'));
local_touch(fullfile(t006_s4_root, 'runner.sh'));
local_touch(fullfile(t006_s4_root, 'defaults.mat'));
local_touch(fullfile(t006_s4_root, 'freesurfer-env'));
local_touch(fullfile(t006_s4_root, 'mprage.nii'));
t006_case_root_current = t006_s4_root;
t006_correlation_current = 't006s4';
t006_subject = struct('subject_id', 't006-s4', 'shared_input', ...
    fullfile(t006_s4_root, 'mprage.nii'), 'shared_temp', t006_s4_root);
t006_config.mlsc.runner = fullfile(t006_s4_root, 'runner.sh');
t006_config.mlsc.mcr_root = fullfile(t006_s4_root, 'mcr');
t006_config.mlsc.defaults_mat = fullfile(t006_s4_root, 'defaults.mat');
t006_config.mlsc.batch_templates = fullfile(t006_s4_root, 'Batch_atlas');
t006_config.mlsc.freesurfer_env = fullfile(t006_s4_root, 'freesurfer-env');
t006_log = fullfile(t006_s4_root, 'output.log');
t006_runtime.script_path = fullfile(t006_s4_root, 'job.sh');
t006_runtime.evidence_dir = t006_s4_root;
t006_runtime.log_archive_dir = t006_s4_root;
t006_runtime.submission_correlation_id = t006_correlation_current;
t006_runtime.max_polls = 4;
t006_runtime.max_accounting_polls = 2;
t006_runtime.output_context = struct('log_file', t006_log, ...
    'subject_index', 1, 'subject_count', 1, 'scope', 'subject');
t006_squeue_seq = {'PENDING'; 'PENDING'; 'RUNNING'};
t006_squeue_idx = 0;
t006_sacct_seq = {''; ''; ...
    '31415|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60'};
t006_sacct_idx = 0;
t006_clock_step = 35;
t006_submit_calls = 0;
t006_cancel_calls = 0;
t006_progress_seed = cell(0, 1);
t006_squeue_appends = cell(0, 1);
t006_result = mlsc_lifecycle(t006_subject, t006_config, t006_runtime, ...
    t006_transport);
t006_text = t006_read_text(t006_log);
assert(t006_result.terminal && t006_result.success);
assert(isempty(strfind(t006_text, 'state pending elapsed')));
assert(isempty(strfind(t006_text, 'state running elapsed')));
assert(isempty(strfind(t006_text, 'still pending (elapsed ')));
assert(isempty(strfind(t006_text, 'still running (elapsed ')));

% T003: canonical heartbeat, transient-gap, and terminal-unknown contract.
% Injected callbacks/clocks only; the 30-second poll and 60-second
% heartbeat cadence, state history, evidence, and terminal semantics are
% preserved. No live SSH, Slurm submission, processing, or MCR runs.
% Running heartbeat mirrors S3: one deterministic 00:01:45 line at
% stage 3 with job ID and no redundant state wording.
t003_rh_root = fullfile(temp_root, 't003-running-hb');
mkdir(t003_rh_root);
mkdir(fullfile(t003_rh_root, 'mcr'));
mkdir(fullfile(t003_rh_root, 'Batch_atlas'));
local_touch(fullfile(t003_rh_root, 'runner.sh'));
local_touch(fullfile(t003_rh_root, 'defaults.mat'));
local_touch(fullfile(t003_rh_root, 'freesurfer-env'));
local_touch(fullfile(t003_rh_root, 'mprage.nii'));
t006_case_root_current = t003_rh_root;
t006_correlation_current = 't003runhb';
t006_subject = struct('subject_id', 't003-runhb', 'shared_input', ...
    fullfile(t003_rh_root, 'mprage.nii'), 'shared_temp', t003_rh_root);
t006_config.mlsc.runner = fullfile(t003_rh_root, 'runner.sh');
t006_config.mlsc.mcr_root = fullfile(t003_rh_root, 'mcr');
t006_config.mlsc.defaults_mat = fullfile(t003_rh_root, 'defaults.mat');
t006_config.mlsc.batch_templates = fullfile(t003_rh_root, 'Batch_atlas');
t006_config.mlsc.freesurfer_env = fullfile(t003_rh_root, 'freesurfer-env');
t003_log = fullfile(t003_rh_root, 'output.log');
t006_runtime.script_path = fullfile(t003_rh_root, 'job.sh');
t006_runtime.evidence_dir = t003_rh_root;
t006_runtime.log_archive_dir = t003_rh_root;
t006_runtime.submission_correlation_id = t006_correlation_current;
t006_runtime.timeout_seconds = 10000;
t006_runtime.max_polls = 3;
t006_runtime.max_accounting_polls = 1;
t006_runtime.output_context = struct('log_file', t003_log, ...
    'subject_index', 1, 'subject_count', 1, 'scope', 'subject');
t006_squeue_seq = {'RUNNING'; 'RUNNING'; 'RUNNING'};
t006_squeue_idx = 0;
t006_sacct_seq = {''};
t006_sacct_idx = 0;
t006_clock_step = 35;
t006_submit_calls = 0;
t006_cancel_calls = 0;
t006_progress_seed = cell(0, 1);
t006_squeue_appends = cell(0, 1);
t003_result = mlsc_lifecycle(t006_subject, t006_config, t006_runtime, ...
    t006_transport);
t003_text = t006_read_text(t003_log);
t003_lines = regexp(t003_text, '\r\n|\n|\r', 'split');
t003_hb = 0;
for t003_kk = 1:length(t003_lines)
    if ~isempty(strfind(t003_lines{t003_kk}, 'still running (elapsed '))
        t003_hb = t003_hb + 1;
        assert(~isempty(strfind(t003_lines{t003_kk}, '31415')));
        assert(~isempty(strfind(t003_lines{t003_kk}, '[stage 3/8]')));
        assert(~isempty(strfind(t003_lines{t003_kk}, '[job 31415]')));
        assert(isempty(strfind(t003_lines{t003_kk}, 'state=')));
    end
end
assert(t003_hb == 1);
assert(~isempty(strfind(t003_text, ...
    'still running (elapsed 00:01:45).')));
assert(isempty(strfind(t003_text, 'still pending (elapsed ')));
assert(isempty(strfind(t003_text, 'state running elapsed')));
assert(isempty(strfind(t003_text, 'state pending elapsed')));
assert(t006_squeue_idx == 3);
assert(~isempty(strfind(t003_text, 'MLSC job 31415 accepted.')));

% Transient running->unknown-gap->completed: no unknown line, one running
% transition, tracker/cadence undisrupted, history retains the gap.
t003_gap_root = fullfile(temp_root, 't003-gap');
mkdir(t003_gap_root);
mkdir(fullfile(t003_gap_root, 'mcr'));
mkdir(fullfile(t003_gap_root, 'Batch_atlas'));
local_touch(fullfile(t003_gap_root, 'runner.sh'));
local_touch(fullfile(t003_gap_root, 'defaults.mat'));
local_touch(fullfile(t003_gap_root, 'freesurfer-env'));
local_touch(fullfile(t003_gap_root, 'mprage.nii'));
t006_case_root_current = t003_gap_root;
t006_correlation_current = 't003gap';
t006_subject = struct('subject_id', 't003-gap', 'shared_input', ...
    fullfile(t003_gap_root, 'mprage.nii'), 'shared_temp', t003_gap_root);
t006_config.mlsc.runner = fullfile(t003_gap_root, 'runner.sh');
t006_config.mlsc.mcr_root = fullfile(t003_gap_root, 'mcr');
t006_config.mlsc.defaults_mat = fullfile(t003_gap_root, 'defaults.mat');
t006_config.mlsc.batch_templates = fullfile(t003_gap_root, 'Batch_atlas');
t006_config.mlsc.freesurfer_env = fullfile(t003_gap_root, 'freesurfer-env');
t003_log = fullfile(t003_gap_root, 'output.log');
t006_runtime.script_path = fullfile(t003_gap_root, 'job.sh');
t006_runtime.evidence_dir = t003_gap_root;
t006_runtime.log_archive_dir = t003_gap_root;
t006_runtime.submission_correlation_id = t006_correlation_current;
t006_runtime.timeout_seconds = 10000;
t006_runtime.max_polls = 3;
t006_runtime.max_accounting_polls = 1;
t006_runtime.output_context = struct('log_file', t003_log, ...
    'subject_index', 1, 'subject_count', 1, 'scope', 'subject');
t006_squeue_seq = {'RUNNING'; ''; 'RUNNING'};
t006_squeue_idx = 0;
t006_sacct_seq = {''; ''; ...
    '31415|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60'};
t006_sacct_idx = 0;
t006_clock_step = 1;
t006_submit_calls = 0;
t006_cancel_calls = 0;
t006_progress_seed = cell(0, 1);
t006_squeue_appends = cell(0, 1);
t003_result = mlsc_lifecycle(t006_subject, t006_config, t006_runtime, ...
    t006_transport);
t003_text = t006_read_text(t003_log);
assert(t003_result.terminal && t003_result.success);
assert(strcmp(t003_result.state, 'completed'));
assert(t006_count(t003_text, 'state running.') == 1);
assert(isempty(strfind(t003_text, 'unknown')));
assert(~isempty(strfind(t003_text, 'MLSC job 31415 accepted.')));
assert(~isempty(strfind(t003_text, 'completed exit 0 elapsed ')));
assert(isempty(strfind(t003_text, 'still pending (elapsed ')));
assert(isempty(strfind(t003_text, 'still running (elapsed ')));
t003_has_unknown = false;
for t003_kk = 1:length(t003_result.state_history)
    if strcmp(t003_result.state_history{t003_kk}, 'unknown')
        t003_has_unknown = true;
    end
end
assert(t003_has_unknown);
assert(t006_squeue_idx == 3);

% One genuine terminal-unknown is retained when authoritative accounting
% never arrives after a terminal squeue observation.
t003_unk_root = fullfile(temp_root, 't003-unknown');
mkdir(t003_unk_root);
mkdir(fullfile(t003_unk_root, 'mcr'));
mkdir(fullfile(t003_unk_root, 'Batch_atlas'));
local_touch(fullfile(t003_unk_root, 'runner.sh'));
local_touch(fullfile(t003_unk_root, 'defaults.mat'));
local_touch(fullfile(t003_unk_root, 'freesurfer-env'));
local_touch(fullfile(t003_unk_root, 'mprage.nii'));
t006_case_root_current = t003_unk_root;
t006_correlation_current = 't003unk';
t006_subject = struct('subject_id', 't003-unk', 'shared_input', ...
    fullfile(t003_unk_root, 'mprage.nii'), 'shared_temp', t003_unk_root);
t006_config.mlsc.runner = fullfile(t003_unk_root, 'runner.sh');
t006_config.mlsc.mcr_root = fullfile(t003_unk_root, 'mcr');
t006_config.mlsc.defaults_mat = fullfile(t003_unk_root, 'defaults.mat');
t006_config.mlsc.batch_templates = fullfile(t003_unk_root, 'Batch_atlas');
t006_config.mlsc.freesurfer_env = fullfile(t003_unk_root, 'freesurfer-env');
t003_log = fullfile(t003_unk_root, 'output.log');
t006_runtime.script_path = fullfile(t003_unk_root, 'job.sh');
t006_runtime.evidence_dir = t003_unk_root;
t006_runtime.log_archive_dir = t003_unk_root;
t006_runtime.submission_correlation_id = t006_correlation_current;
t006_runtime.timeout_seconds = 10000;
t006_runtime.max_polls = 2;
t006_runtime.max_accounting_polls = 1;
t006_runtime.output_context = struct('log_file', t003_log, ...
    'subject_index', 1, 'subject_count', 1, 'scope', 'subject');
t006_squeue_seq = {'COMPLETED'; 'COMPLETED'};
t006_squeue_idx = 0;
t006_sacct_seq = {''};
t006_sacct_idx = 0;
t006_clock_step = 1;
t006_submit_calls = 0;
t006_cancel_calls = 0;
t006_progress_seed = cell(0, 1);
t006_squeue_appends = cell(0, 1);
t003_result = mlsc_lifecycle(t006_subject, t006_config, t006_runtime, ...
    t006_transport);
t003_text = t006_read_text(t003_log);
assert(t003_result.terminal && ~t003_result.success);
assert(strcmp(t003_result.state, 'unknown'));
assert(t006_count(t003_text, 'unknown') == 1);
assert(~isempty(strfind(t003_text, ...
    'MLSC job 31415 unknown exit unavailable elapsed ')));
assert(~isempty(regexp(t003_text, ...
    'unknown exit unavailable elapsed 00:00:0[0-9]\.', 'once')));
assert(~isempty(strfind(t003_text, '[job 31415]')));
assert(~isempty(strfind(t003_text, 'MLSC job 31415 accepted.')));

% S5: failed-job terminal diagnostics carry job/state/exit/elapsed without
% changing scheduler accounting authority.
t006_s5_root = fullfile(temp_root, 't006-s5');
mkdir(t006_s5_root);
mkdir(fullfile(t006_s5_root, 'mcr'));
mkdir(fullfile(t006_s5_root, 'Batch_atlas'));
local_touch(fullfile(t006_s5_root, 'runner.sh'));
local_touch(fullfile(t006_s5_root, 'defaults.mat'));
local_touch(fullfile(t006_s5_root, 'freesurfer-env'));
local_touch(fullfile(t006_s5_root, 'mprage.nii'));
t006_case_root_current = t006_s5_root;
t006_correlation_current = 't006s5';
t006_subject = struct('subject_id', 't006-s5', 'shared_input', ...
    fullfile(t006_s5_root, 'mprage.nii'), 'shared_temp', t006_s5_root);
t006_config.mlsc.runner = fullfile(t006_s5_root, 'runner.sh');
t006_config.mlsc.mcr_root = fullfile(t006_s5_root, 'mcr');
t006_config.mlsc.defaults_mat = fullfile(t006_s5_root, 'defaults.mat');
t006_config.mlsc.batch_templates = fullfile(t006_s5_root, 'Batch_atlas');
t006_config.mlsc.freesurfer_env = fullfile(t006_s5_root, 'freesurfer-env');
t006_log = fullfile(t006_s5_root, 'output.log');
t006_runtime.script_path = fullfile(t006_s5_root, 'job.sh');
t006_runtime.evidence_dir = t006_s5_root;
t006_runtime.log_archive_dir = t006_s5_root;
t006_runtime.submission_correlation_id = t006_correlation_current;
t006_runtime.max_polls = 4;
t006_runtime.max_accounting_polls = 2;
t006_runtime.output_context = struct('log_file', t006_log, ...
    'subject_index', 1, 'subject_count', 1, 'scope', 'subject');
t006_squeue_seq = {'RUNNING'};
t006_squeue_idx = 0;
t006_sacct_seq = {...
    '31415|FAILED|2:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60'};
t006_sacct_idx = 0;
t006_clock_step = 1;
t006_submit_calls = 0;
t006_cancel_calls = 0;
t006_progress_seed = cell(0, 1);
t006_squeue_appends = cell(0, 1);
t006_result = mlsc_lifecycle(t006_subject, t006_config, t006_runtime, ...
    t006_transport);
t006_text = t006_read_text(t006_log);
assert(t006_result.terminal && ~t006_result.success);
assert(strcmp(t006_result.state, 'failed') && t006_result.exit_code == 2);
assert(t006_result.failure.present && ~isempty(t006_result.failure_detail));
assert(t006_result.accounting_record_found && t006_result.primary_allocation);
assert(~isempty(strfind(t006_text, 'MLSC job 31415 failed exit 2 elapsed')));

% S6: full milestone consumption renders stage 3 versus stage 4 mapping,
% archives the tiny file copy-only, and preserves result semantics.
t006_s6_root = fullfile(temp_root, 't006-s6');
mkdir(t006_s6_root);
mkdir(fullfile(t006_s6_root, 'mcr'));
mkdir(fullfile(t006_s6_root, 'Batch_atlas'));
mkdir(fullfile(t006_s6_root, 'durable'));
local_touch(fullfile(t006_s6_root, 'runner.sh'));
local_touch(fullfile(t006_s6_root, 'defaults.mat'));
local_touch(fullfile(t006_s6_root, 'freesurfer-env'));
local_touch(fullfile(t006_s6_root, 'mprage.nii'));
t006_case_root_current = t006_s6_root;
t006_correlation_current = 't006s6';
t006_subject = struct('subject_id', 't006-s6', 'shared_input', ...
    fullfile(t006_s6_root, 'mprage.nii'), 'shared_temp', t006_s6_root);
t006_config.mlsc.runner = fullfile(t006_s6_root, 'runner.sh');
t006_config.mlsc.mcr_root = fullfile(t006_s6_root, 'mcr');
t006_config.mlsc.defaults_mat = fullfile(t006_s6_root, 'defaults.mat');
t006_config.mlsc.batch_templates = fullfile(t006_s6_root, 'Batch_atlas');
t006_config.mlsc.freesurfer_env = fullfile(t006_s6_root, 'freesurfer-env');
t006_log = fullfile(t006_s6_root, 'output.log');
t006_runtime.script_path = fullfile(t006_s6_root, 'job.sh');
t006_runtime.evidence_dir = fullfile(t006_s6_root, 'durable');
t006_runtime.log_archive_dir = fullfile(t006_s6_root, 'durable');
t006_runtime.submission_correlation_id = t006_correlation_current;
t006_runtime.max_polls = 4;
t006_runtime.max_accounting_polls = 2;
t006_runtime.output_context = struct('log_file', t006_log, ...
    'subject_index', 1, 'subject_count', 1, 'scope', 'subject');
t006_squeue_seq = {'RUNNING'};
t006_squeue_idx = 0;
t006_sacct_seq = {...
    '31415|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60'};
t006_sacct_idx = 0;
t006_clock_step = 1;
t006_submit_calls = 0;
t006_cancel_calls = 0;
t006_progress_seed = t006_expected;
t006_squeue_appends = cell(0, 1);
t006_result = mlsc_lifecycle(t006_subject, t006_config, t006_runtime, ...
    t006_transport);
t006_text = t006_read_text(t006_log);
assert(t006_result.terminal && t006_result.success);
assert(isequal(t006_result.progress.milestones, t006_expected));
assert(t006_count(t006_text, 'MLSC stage-in completed.') == 1);
assert(t006_count(t006_text, 'MLSC normalization started.') == 1);
assert(t006_count(t006_text, 'MLSC normalization completed.') == 1);
assert(t006_count(t006_text, 'MLSC pseudo-CT started.') == 1);
assert(t006_count(t006_text, 'MLSC pseudo-CT completed.') == 1);
assert(t006_count(t006_text, 'MLSC verification started.') == 1);
assert(t006_count(t006_text, 'MLSC verification completed.') == 1);
assert(t006_count(t006_text, 'MLSC copy-back started.') == 1);
assert(t006_count(t006_text, ...
    'MLSC verified return to shared temp completed.') == 1);
t006_map_lines = regexp(t006_text, '\r\n|\n|\r', 'split');
for t006_kk = 1:length(t006_map_lines)
    t006_line = t006_map_lines{t006_kk};
    if ~isempty(strfind(t006_line, 'verification')) || ...
            ~isempty(strfind(t006_line, 'copy-back')) || ...
            ~isempty(strfind(t006_line, 'verified return'))
        assert(~isempty(strfind(t006_line, '[stage 4/8]')));
        assert(isempty(strfind(t006_line, '[stage 3/8]')));
    end
    if ~isempty(strfind(t006_line, 'stage-in')) || ...
            ~isempty(strfind(t006_line, 'normalization')) || ...
            ~isempty(strfind(t006_line, 'pseudo-CT started')) || ...
            ~isempty(strfind(t006_line, 'pseudo-CT completed'))
        assert(~isempty(strfind(t006_line, '[stage 3/8]')));
        assert(isempty(strfind(t006_line, '[stage 4/8]')));
    end
end
assert(t006_result.progress.archive_succeeded);
assert(strcmp(t006_result.progress.source_path, ...
    mlsc_progress('path_for', t006_s6_root, 't006s6')));
assert(strcmp(t006_result.progress.archive_path, ...
    fullfile(t006_s6_root, 'durable', '.mlsc_progress_t006s6')));
assert(t006_result.progress.archive_succeeded);
assert(exist(fullfile(t006_s6_root, 'durable', ...
    '.mlsc_progress_t006s6'), 'file') == 2);
assert(exist(mlsc_progress('path_for', t006_s6_root, 't006s6'), ...
    'file') == 2);
assert(~exist(t006_runtime.script_path, 'file'));
assert(t006_result.evidence_saved);
assert(strcmp(t006_result.state_history{1}, 'init'));
assert(t006_result.copy_back.verified && t006_result.primary_allocation);
assert(strcmp(t006_result.squeue_query_contract, ...
    'squeue --noheader --jobs=JOBID --format=%T'));
assert(isequal(t006_result.evidence.lifecycle{1}, 'init'));
assert(strcmp(t006_result.evidence.lifecycle{end}, 'cleanup'));

% S7: missing progress input never fails the job and stays diagnosable.
t006_s7_root = fullfile(temp_root, 't006-s7');
mkdir(t006_s7_root);
mkdir(fullfile(t006_s7_root, 'mcr'));
mkdir(fullfile(t006_s7_root, 'Batch_atlas'));
local_touch(fullfile(t006_s7_root, 'runner.sh'));
local_touch(fullfile(t006_s7_root, 'defaults.mat'));
local_touch(fullfile(t006_s7_root, 'freesurfer-env'));
local_touch(fullfile(t006_s7_root, 'mprage.nii'));
t006_case_root_current = t006_s7_root;
t006_correlation_current = 't006s7';
t006_subject = struct('subject_id', 't006-s7', 'shared_input', ...
    fullfile(t006_s7_root, 'mprage.nii'), 'shared_temp', t006_s7_root);
t006_config.mlsc.runner = fullfile(t006_s7_root, 'runner.sh');
t006_config.mlsc.mcr_root = fullfile(t006_s7_root, 'mcr');
t006_config.mlsc.defaults_mat = fullfile(t006_s7_root, 'defaults.mat');
t006_config.mlsc.batch_templates = fullfile(t006_s7_root, 'Batch_atlas');
t006_config.mlsc.freesurfer_env = fullfile(t006_s7_root, 'freesurfer-env');
t006_log = fullfile(t006_s7_root, 'output.log');
t006_runtime.script_path = fullfile(t006_s7_root, 'job.sh');
t006_runtime.evidence_dir = t006_s7_root;
t006_runtime.log_archive_dir = t006_s7_root;
t006_runtime.submission_correlation_id = t006_correlation_current;
t006_runtime.output_context = struct('log_file', t006_log, ...
    'subject_index', 1, 'subject_count', 1, 'scope', 'subject');
t006_squeue_seq = {'RUNNING'};
t006_squeue_idx = 0;
t006_sacct_seq = {...
    '31415|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60'};
t006_sacct_idx = 0;
t006_clock_step = 1;
t006_submit_calls = 0;
t006_cancel_calls = 0;
t006_progress_seed = cell(0, 1);
t006_squeue_appends = cell(0, 1);
t006_result = mlsc_lifecycle(t006_subject, t006_config, t006_runtime, ...
    t006_transport);
assert(t006_result.terminal && t006_result.success);
assert(isempty(t006_result.progress.milestones));
assert(~t006_result.progress.archive_succeeded);
assert(~isempty(t006_result.progress.archive_detail));

% S8: delayed and partial lines appended during polling appear exactly once
% on the next existing poll after completion.
t006_s8_root = fullfile(temp_root, 't006-s8');
mkdir(t006_s8_root);
mkdir(fullfile(t006_s8_root, 'mcr'));
mkdir(fullfile(t006_s8_root, 'Batch_atlas'));
local_touch(fullfile(t006_s8_root, 'runner.sh'));
local_touch(fullfile(t006_s8_root, 'defaults.mat'));
local_touch(fullfile(t006_s8_root, 'freesurfer-env'));
local_touch(fullfile(t006_s8_root, 'mprage.nii'));
t006_case_root_current = t006_s8_root;
t006_correlation_current = 't006s8';
t006_subject = struct('subject_id', 't006-s8', 'shared_input', ...
    fullfile(t006_s8_root, 'mprage.nii'), 'shared_temp', t006_s8_root);
t006_config.mlsc.runner = fullfile(t006_s8_root, 'runner.sh');
t006_config.mlsc.mcr_root = fullfile(t006_s8_root, 'mcr');
t006_config.mlsc.defaults_mat = fullfile(t006_s8_root, 'defaults.mat');
t006_config.mlsc.batch_templates = fullfile(t006_s8_root, 'Batch_atlas');
t006_config.mlsc.freesurfer_env = fullfile(t006_s8_root, 'freesurfer-env');
t006_log = fullfile(t006_s8_root, 'output.log');
t006_runtime.script_path = fullfile(t006_s8_root, 'job.sh');
t006_runtime.evidence_dir = t006_s8_root;
t006_runtime.log_archive_dir = t006_s8_root;
t006_runtime.submission_correlation_id = t006_correlation_current;
t006_runtime.output_context = struct('log_file', t006_log, ...
    'subject_index', 1, 'subject_count', 1, 'scope', 'subject');
t006_squeue_seq = {'RUNNING'; 'RUNNING'; 'RUNNING'};
t006_squeue_idx = 0;
t006_sacct_seq = {''; ''; ...
    '31415|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60'};
t006_sacct_idx = 0;
t006_clock_step = 1;
t006_submit_calls = 0;
t006_cancel_calls = 0;
t006_progress_seed = cell(0, 1);
t006_squeue_appends = {['stage_in|done' char(10)]; 'pseudoCT|sta'; ...
    ['rt' char(10)]};
t006_result = mlsc_lifecycle(t006_subject, t006_config, t006_runtime, ...
    t006_transport);
t006_text = t006_read_text(t006_log);
assert(isequal(t006_result.progress.milestones, ...
    {'stage_in|done'; 'pseudoCT|start'}));
assert(t006_count(t006_text, 'MLSC stage-in completed.') == 1);
assert(t006_count(t006_text, 'MLSC pseudo-CT started.') == 1);

% S9: secret-bearing progress content is denied without echo in output,
% logs, milestones, or evidence.
t006_s9_root = fullfile(temp_root, 't006-s9');
mkdir(t006_s9_root);
mkdir(fullfile(t006_s9_root, 'mcr'));
mkdir(fullfile(t006_s9_root, 'Batch_atlas'));
mkdir(fullfile(t006_s9_root, 'durable'));
local_touch(fullfile(t006_s9_root, 'runner.sh'));
local_touch(fullfile(t006_s9_root, 'defaults.mat'));
local_touch(fullfile(t006_s9_root, 'freesurfer-env'));
local_touch(fullfile(t006_s9_root, 'mprage.nii'));
t006_case_root_current = t006_s9_root;
t006_correlation_current = 't006s9';
t006_secret = 'hunter2-t006-secret';
t006_subject = struct('subject_id', 't006-s9', 'shared_input', ...
    fullfile(t006_s9_root, 'mprage.nii'), 'shared_temp', t006_s9_root);
t006_config.mlsc.runner = fullfile(t006_s9_root, 'runner.sh');
t006_config.mlsc.mcr_root = fullfile(t006_s9_root, 'mcr');
t006_config.mlsc.defaults_mat = fullfile(t006_s9_root, 'defaults.mat');
t006_config.mlsc.batch_templates = fullfile(t006_s9_root, 'Batch_atlas');
t006_config.mlsc.freesurfer_env = fullfile(t006_s9_root, 'freesurfer-env');
t006_log = fullfile(t006_s9_root, 'output.log');
t006_runtime.script_path = fullfile(t006_s9_root, 'job.sh');
t006_runtime.evidence_dir = fullfile(t006_s9_root, 'durable');
t006_runtime.log_archive_dir = fullfile(t006_s9_root, 'durable');
t006_runtime.submission_correlation_id = t006_correlation_current;
t006_runtime.output_context = struct('log_file', t006_log, ...
    'subject_index', 1, 'subject_count', 1, 'scope', 'subject');
t006_squeue_seq = {'RUNNING'};
t006_squeue_idx = 0;
t006_sacct_seq = {...
    '31415|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60'};
t006_sacct_idx = 0;
t006_clock_step = 1;
t006_submit_calls = 0;
t006_cancel_calls = 0;
t006_progress_seed = {'stage_in|done'; ['password=' t006_secret]; ...
    'pseudoCT|done'};
t006_squeue_appends = cell(0, 1);
t006_result = mlsc_lifecycle(t006_subject, t006_config, t006_runtime, ...
    t006_transport);
t006_text = t006_read_text(t006_log);
assert(isequal(t006_result.progress.milestones, ...
    {'stage_in|done'; 'pseudoCT|done'}));
assert(~isempty(strfind(t006_text, 'MLSC stage-in completed.')));
assert(isempty(strfind(t006_text, t006_secret)));
assert(isempty(strfind(t006_result.failure_detail, t006_secret)));
for t006_kk = 1:numel(t006_result.progress.milestones)
    assert(isempty(strfind(t006_result.progress.milestones{t006_kk}, ...
        t006_secret)));
end
assert(~isfield(t006_result.evidence, 'password'));
t006_persisted = load(fullfile(t006_s9_root, 'durable', ...
    'mlsc_evidence.mat'));
assert(isempty(strfind(t006_persisted.snapshot.progress_source_path, ...
    t006_secret)));

% T010: terminal incomplete trailing progress is recorded as a bounded
% secret-free indicator (flag plus pending-byte count, never content).
% Local fixtures with injected callbacks only; no live activity.
t010_root = fullfile(temp_root, 't010-partial');
mkdir(t010_root);
mkdir(fullfile(t010_root, 'mcr'));
mkdir(fullfile(t010_root, 'Batch_atlas'));
local_touch(fullfile(t010_root, 'runner.sh'));
local_touch(fullfile(t010_root, 'defaults.mat'));
local_touch(fullfile(t010_root, 'freesurfer-env'));
local_touch(fullfile(t010_root, 'mprage.nii'));
t006_case_root_current = t010_root;
t006_correlation_current = 't010partial';
t010_secret = 'hunter2-t010-secret';
t010_fragment = ['password=' t010_secret];
t010_subject = struct('subject_id', 't010-partial', 'shared_input', ...
    fullfile(t010_root, 'mprage.nii'), 'shared_temp', t010_root);
t006_config.mlsc.runner = fullfile(t010_root, 'runner.sh');
t006_config.mlsc.mcr_root = fullfile(t010_root, 'mcr');
t006_config.mlsc.defaults_mat = fullfile(t010_root, 'defaults.mat');
t006_config.mlsc.batch_templates = fullfile(t010_root, 'Batch_atlas');
t006_config.mlsc.freesurfer_env = fullfile(t010_root, 'freesurfer-env');
t006_log = fullfile(t010_root, 'output.log');
t006_runtime.script_path = fullfile(t010_root, 'job.sh');
t006_runtime.evidence_dir = t010_root;
t006_runtime.log_archive_dir = t010_root;
t006_runtime.submission_correlation_id = t006_correlation_current;
t006_runtime.max_polls = 2;
t006_runtime.max_accounting_polls = 1;
t006_runtime.output_context = struct('log_file', t006_log, ...
    'subject_index', 1, 'subject_count', 1, 'scope', 'subject');
t006_squeue_seq = {'RUNNING'; 'RUNNING'};
t006_squeue_idx = 0;
t006_sacct_seq = {''; ...
    '31415|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60'};
t006_sacct_idx = 0;
t006_clock_step = 1;
t006_submit_calls = 0;
t006_cancel_calls = 0;
t006_progress_seed = {'stage_in|done'};
t006_squeue_appends = {''; t010_fragment};
t010_result = mlsc_lifecycle(t010_subject, t006_config, t006_runtime, ...
    t006_transport);
t010_text = t006_read_text(t006_log);
assert(t010_result.terminal && t010_result.success);
assert(isequal(t010_result.progress.milestones, {'stage_in|done'}));
assert(islogical(t010_result.progress.incomplete_trailing) && ...
    isscalar(t010_result.progress.incomplete_trailing) && ...
    t010_result.progress.incomplete_trailing);
assert(isnumeric(t010_result.progress.pending_bytes) && ...
    isscalar(t010_result.progress.pending_bytes) && ...
    isfinite(t010_result.progress.pending_bytes) && ...
    t010_result.progress.pending_bytes == numel(t010_fragment));
assert(~isfield(t010_result.progress, 'pending'));
assert(isempty(strfind(t010_text, t010_secret)));
assert(isempty(strfind(t010_result.failure_detail, t010_secret)));
for t010_kk = 1:numel(t010_result.progress.milestones)
    assert(isempty(strfind(t010_result.progress.milestones{t010_kk}, ...
        t010_secret)));
end
assert(t010_result.evidence.progress_incomplete_trailing);
assert(t010_result.evidence.progress_pending_bytes == ...
    numel(t010_fragment));
assert(t010_result.evidence.progress.incomplete_trailing);
assert(t010_result.evidence.progress.pending_bytes == ...
    numel(t010_fragment));
assert(~isfield(t010_result.evidence.progress, 'pending'));
assert(isempty(strfind(t010_result.evidence.failure_detail, t010_secret)));
t010_persisted = load(fullfile(t010_root, 'mlsc_evidence.mat'));
assert(t010_persisted.snapshot.progress_incomplete_trailing);
assert(t010_persisted.snapshot.progress_pending_bytes == ...
    numel(t010_fragment));
assert(t010_persisted.snapshot.progress.incomplete_trailing);
assert(t010_persisted.snapshot.progress.pending_bytes == ...
    numel(t010_fragment));
assert(~isfield(t010_persisted.snapshot.progress, 'pending'));
assert(isempty(strfind(t010_persisted.snapshot.failure_detail, ...
    t010_secret)));
assert(isempty(strfind(t010_persisted.snapshot.progress_source_path, ...
    t010_secret)));
assert(isempty(strfind(t010_persisted.snapshot.progress_archive_detail, ...
    t010_secret)));
% A clean terminal records the same indicator as false/zero.
t010_clean_root = fullfile(temp_root, 't010-clean');
mkdir(t010_clean_root);
mkdir(fullfile(t010_clean_root, 'mcr'));
mkdir(fullfile(t010_clean_root, 'Batch_atlas'));
local_touch(fullfile(t010_clean_root, 'runner.sh'));
local_touch(fullfile(t010_clean_root, 'defaults.mat'));
local_touch(fullfile(t010_clean_root, 'freesurfer-env'));
local_touch(fullfile(t010_clean_root, 'mprage.nii'));
t006_case_root_current = t010_clean_root;
t006_correlation_current = 't010clean';
t010_clean_subject = struct('subject_id', 't010-clean', 'shared_input', ...
    fullfile(t010_clean_root, 'mprage.nii'), 'shared_temp', ...
    t010_clean_root);
t006_config.mlsc.runner = fullfile(t010_clean_root, 'runner.sh');
t006_config.mlsc.mcr_root = fullfile(t010_clean_root, 'mcr');
t006_config.mlsc.defaults_mat = fullfile(t010_clean_root, 'defaults.mat');
t006_config.mlsc.batch_templates = fullfile(t010_clean_root, ...
    'Batch_atlas');
t006_config.mlsc.freesurfer_env = fullfile(t010_clean_root, ...
    'freesurfer-env');
t006_log = fullfile(t010_clean_root, 'output.log');
t006_runtime.script_path = fullfile(t010_clean_root, 'job.sh');
t006_runtime.evidence_dir = t010_clean_root;
t006_runtime.log_archive_dir = t010_clean_root;
t006_runtime.submission_correlation_id = t006_correlation_current;
t006_runtime.max_polls = 2;
t006_runtime.max_accounting_polls = 1;
t006_runtime.output_context = struct('log_file', t006_log, ...
    'subject_index', 1, 'subject_count', 1, 'scope', 'subject');
t006_squeue_seq = {'RUNNING'};
t006_squeue_idx = 0;
t006_sacct_seq = {...
    '31415|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60'};
t006_sacct_idx = 0;
t006_clock_step = 1;
t006_submit_calls = 0;
t006_cancel_calls = 0;
t006_progress_seed = {'stage_in|done'};
t006_squeue_appends = cell(0, 1);
t010_clean = mlsc_lifecycle(t010_clean_subject, t006_config, ...
    t006_runtime, t006_transport);
assert(t010_clean.terminal && t010_clean.success);
assert(~t010_clean.progress.incomplete_trailing);
assert(t010_clean.progress.pending_bytes == 0);
assert(~t010_clean.evidence.progress_incomplete_trailing);
assert(t010_clean.evidence.progress_pending_bytes == 0);
t010_clean_persisted = load(fullfile(t010_clean_root, ...
    'mlsc_evidence.mat'));
assert(~t010_clean_persisted.snapshot.progress_incomplete_trailing);
assert(t010_clean_persisted.snapshot.progress_pending_bytes == 0);

% T011: robust per-submission boundary with a stale prior file present.
% The current submission selects one exact unique artifact; Slurm writes
% only that file, lifecycle reads only that file, and a stale legacy
% file that remains present/undeletable is never emitted. Bounded tiny,
% deterministic correlation-preserving cleanup/archive. Local fixtures
% with injected callbacks only; no live activity.
t011_root = fullfile(temp_root, 't011-stale');
mkdir(t011_root);
mkdir(fullfile(t011_root, 'mcr'));
mkdir(fullfile(t011_root, 'Batch_atlas'));
mkdir(fullfile(t011_root, 'durable'));
local_touch(fullfile(t011_root, 'runner.sh'));
local_touch(fullfile(t011_root, 'defaults.mat'));
local_touch(fullfile(t011_root, 'freesurfer-env'));
local_touch(fullfile(t011_root, 'mprage.nii'));
t006_case_root_current = t011_root;
t006_correlation_current = 't011corr01';
t011_legacy_path = fullfile(t011_root, '.mlsc_progress');
t011_legacy_fid = fopen(t011_legacy_path, 'w');
assert(t011_legacy_fid ~= -1);
fwrite(t011_legacy_fid, ['pseudoCT|done' char(10) ...
    'copy_back|done' char(10)]);
fclose(t011_legacy_fid);
assert(exist(t011_legacy_path, 'file') == 2);
t011_subject = struct('subject_id', 't011-stale', 'shared_input', ...
    fullfile(t011_root, 'mprage.nii'), 'shared_temp', t011_root);
t006_config.mlsc.runner = fullfile(t011_root, 'runner.sh');
t006_config.mlsc.mcr_root = fullfile(t011_root, 'mcr');
t006_config.mlsc.defaults_mat = fullfile(t011_root, 'defaults.mat');
t006_config.mlsc.batch_templates = fullfile(t011_root, 'Batch_atlas');
t006_config.mlsc.freesurfer_env = fullfile(t011_root, 'freesurfer-env');
t011_log = fullfile(t011_root, 'output.log');
t006_runtime.script_path = fullfile(t011_root, 'job.sh');
t006_runtime.evidence_dir = fullfile(t011_root, 'durable');
t006_runtime.log_archive_dir = fullfile(t011_root, 'durable');
t006_runtime.max_polls = 3;
t006_runtime.max_accounting_polls = 2;
t006_runtime.output_context = struct('log_file', t011_log, ...
    'subject_index', 1, 'subject_count', 1, 'scope', 'subject');
t006_runtime.submission_correlation_id = t006_correlation_current;
t006_squeue_seq = {'RUNNING'; 'RUNNING'};
t006_squeue_idx = 0;
t006_sacct_seq = {''; ...
    '31415|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60'};
t006_sacct_idx = 0;
t006_clock_step = 1;
t006_submit_calls = 0;
t006_cancel_calls = 0;
t006_progress_seed = {'stage_in|done'};
t006_squeue_appends = {['pseudoCT|start' char(10)]; ''};
t011_result = mlsc_lifecycle(t011_subject, t006_config, t006_runtime, ...
    t006_transport);
t011_text = t006_read_text(t011_log);
t011_expected_new = mlsc_progress('path_for', t011_root, 't011corr01');
assert(strcmp(t011_result.progress.source_path, t011_expected_new));
assert(strcmp(t011_result.submission_correlation_id, 't011corr01'));
assert(isequal(t011_result.progress.milestones, ...
    {'stage_in|done'; 'pseudoCT|start'}));
assert(isempty(strfind(t011_text, 'pseudo-CT completed.')) || ...
    t006_count(t011_text, 'MLSC pseudo-CT started.') == 1);
assert(t006_count(t011_text, 'MLSC stage-in completed.') == 1);
assert(isempty(strfind(t011_text, 'verified return to shared temp completed.')));
for t011_kk = 1:numel(t011_result.progress.milestones)
    assert(~strcmp(t011_result.progress.milestones{t011_kk}, ...
        'pseudoCT|done'));
    assert(~strcmp(t011_result.progress.milestones{t011_kk}, ...
        'copy_back|done'));
end
assert(strcmp(t011_result.progress.archive_path, ...
    fullfile(t011_root, 'durable', '.mlsc_progress_t011corr01')));
assert(t011_result.progress.archive_succeeded);
assert(exist(fullfile(t011_root, 'durable', ...
    '.mlsc_progress_t011corr01'), 'file') == 2);
assert(exist(t011_expected_new, 'file') == 2);
t011_archive_fid = fopen(fullfile(t011_root, 'durable', ...
    '.mlsc_progress_t011corr01'), 'r');
assert(t011_archive_fid ~= -1);
t011_archive_text = fread(t011_archive_fid, inf, '*char')';
fclose(t011_archive_fid);
assert(~isempty(strfind(t011_archive_text, 'stage_in|done')));
assert(~isempty(strfind(t011_archive_text, 'pseudoCT|start')));
assert(isempty(strfind(t011_archive_text, 'copy_back|done')));
t011_archive_info = dir(fullfile(t011_root, 'durable', ...
    '.mlsc_progress_t011corr01'));
assert(numel(t011_archive_info) == 1 && t011_archive_info(1).bytes < 1024);
assert(~isempty(regexp('.mlsc_progress_t011corr01', ...
    '^\.mlsc_progress_[A-Za-z0-9_.-]+$', 'once')));
assert(t011_result.evidence.progress_archive_succeeded);
assert(strcmp(t011_result.evidence.progress_source_path, t011_expected_new));
assert(strcmp(t011_result.evidence.progress_archive_path, ...
    fullfile(t011_root, 'durable', '.mlsc_progress_t011corr01')));
% The stale legacy file may still be present (harmless); it was never
% consumed even though it holds distinct milestones.
t011_stale_fid = fopen(t011_legacy_path, 'w');
assert(t011_stale_fid ~= -1);
fwrite(t011_stale_fid, ['pseudoCT|done' char(10) ...
    'copy_back|done' char(10)]);
fclose(t011_stale_fid);
t011_stale_cursor = mlsc_progress('init');
[t011_stale_events, ~] = mlsc_progress('consume', t011_legacy_path, ...
    t011_stale_cursor);
assert(isequal(t011_stale_events, ...
    {'pseudoCT|done'; 'copy_back|done'}));
assert(~isequal(t011_result.progress.milestones, t011_stale_events));

% T012: durable archive holds only the validated recognized sequence.
% Order preserved, at-most-once, from parser accepted output; malformed,
% unknown, secret-bearing, and incomplete-trailing input is never archived
% or echoed. Evidence keeps only the incomplete flag plus pending-byte
% counts, never raw rejected content; the raw source is left in place but
% never promoted. Local fixtures with injected callbacks only; no live
% activity.
t012_root = fullfile(temp_root, 't012-sanitized');
mkdir(t012_root);
mkdir(fullfile(t012_root, 'mcr'));
mkdir(fullfile(t012_root, 'Batch_atlas'));
mkdir(fullfile(t012_root, 'durable'));
local_touch(fullfile(t012_root, 'runner.sh'));
local_touch(fullfile(t012_root, 'defaults.mat'));
local_touch(fullfile(t012_root, 'freesurfer-env'));
local_touch(fullfile(t012_root, 'mprage.nii'));
t006_case_root_current = t012_root;
t006_correlation_current = 't012san01';
t012_secret = 'hunter2-t012-secret-9f3a';
t012_malformed = 'bogus|line-t012';
t012_unknown = 'mystery|done-t012';
t012_partial = 'verify|sta';
t012_subject = struct('subject_id', 't012-sanitized', 'shared_input', ...
    fullfile(t012_root, 'mprage.nii'), 'shared_temp', t012_root);
t006_config.mlsc.runner = fullfile(t012_root, 'runner.sh');
t006_config.mlsc.mcr_root = fullfile(t012_root, 'mcr');
t006_config.mlsc.defaults_mat = fullfile(t012_root, 'defaults.mat');
t006_config.mlsc.batch_templates = fullfile(t012_root, 'Batch_atlas');
t006_config.mlsc.freesurfer_env = fullfile(t012_root, 'freesurfer-env');
t012_log = fullfile(t012_root, 'output.log');
t006_runtime.script_path = fullfile(t012_root, 'job.sh');
t006_runtime.evidence_dir = fullfile(t012_root, 'durable');
t006_runtime.log_archive_dir = fullfile(t012_root, 'durable');
t006_runtime.max_polls = 3;
t006_runtime.max_accounting_polls = 2;
t006_runtime.output_context = struct('log_file', t012_log, ...
    'subject_index', 1, 'subject_count', 1, 'scope', 'subject');
t006_runtime.submission_correlation_id = t006_correlation_current;
t006_squeue_seq = {'RUNNING'; 'RUNNING'};
t006_squeue_idx = 0;
t006_sacct_seq = {''; ...
    '31415|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60'};
t006_sacct_idx = 0;
t006_clock_step = 1;
t006_submit_calls = 0;
t006_cancel_calls = 0;
t006_progress_seed = {'stage_in|done'; t012_malformed; ...
    ['password=' t012_secret]; 'pseudoCT|start'; t012_unknown; ...
    'pseudoCT|start'; 'pseudoCT|done'};
t006_squeue_appends = {''; t012_partial};
t012_result = mlsc_lifecycle(t012_subject, t006_config, t006_runtime, ...
    t006_transport);
t012_text = t006_read_text(t012_log);
assert(t012_result.terminal && t012_result.success);
assert(isequal(t012_result.progress.milestones, ...
    {'stage_in|done'; 'pseudoCT|start'; 'pseudoCT|done'}));
assert(t012_result.progress.incomplete_trailing);
assert(t012_result.progress.pending_bytes == numel(t012_partial));
assert(~isfield(t012_result.progress, 'pending'));
assert(t012_result.progress.archive_succeeded);
assert(strcmp(t012_result.progress.source_path, ...
    mlsc_progress('path_for', t012_root, 't012san01')));
assert(strcmp(t012_result.progress.archive_path, ...
    fullfile(t012_root, 'durable', '.mlsc_progress_t012san01')));
t012_archive_path = fullfile(t012_root, 'durable', ...
    '.mlsc_progress_t012san01');
assert(exist(t012_archive_path, 'file') == 2);
t012_archive_fid = fopen(t012_archive_path, 'r');
assert(t012_archive_fid ~= -1);
t012_archive_text = fread(t012_archive_fid, inf, '*char')';
fclose(t012_archive_fid);
assert(strcmp(t012_archive_text, ['stage_in|done' char(10) ...
    'pseudoCT|start' char(10) 'pseudoCT|done' char(10)]));
assert(~isempty(strfind(t012_archive_text, 'stage_in|done')));
assert(~isempty(strfind(t012_archive_text, 'pseudoCT|start')));
assert(~isempty(strfind(t012_archive_text, 'pseudoCT|done')));
assert(t006_count(t012_archive_text, 'stage_in|done') == 1);
assert(t006_count(t012_archive_text, 'pseudoCT|start') == 1);
assert(t006_count(t012_archive_text, 'pseudoCT|done') == 1);
assert(isempty(strfind(t012_archive_text, t012_secret)));
assert(isempty(strfind(t012_archive_text, 'password=')));
assert(isempty(strfind(t012_archive_text, t012_malformed)));
assert(isempty(strfind(t012_archive_text, t012_unknown)));
assert(isempty(strfind(t012_archive_text, 'verify|')));
assert(isempty(strfind(t012_archive_text, 'copy_back|')));
t012_archive_info = dir(t012_archive_path);
assert(numel(t012_archive_info) == 1 && t012_archive_info(1).bytes < 1024);
t012_source_text = t006_read_text(t012_result.progress.source_path);
assert(~isempty(strfind(t012_source_text, t012_secret)));
assert(~isempty(strfind(t012_source_text, t012_malformed)));
assert(isempty(strfind(t012_text, t012_secret)));
assert(isempty(strfind(t012_text, t012_malformed)));
assert(isempty(strfind(t012_text, t012_unknown)));
assert(isempty(strfind(t012_text, 'password=')));
for t012_kk = 1:numel(t012_result.progress.milestones)
    assert(isempty(strfind(t012_result.progress.milestones{t012_kk}, ...
        t012_secret)));
    assert(isempty(strfind(t012_result.progress.milestones{t012_kk}, ...
        'password=')));
end
assert(isempty(strfind(t012_result.failure_detail, t012_secret)));
assert(isempty(strfind(t012_result.failure_detail, t012_malformed)));
assert(isempty(strfind(t012_result.progress.source_path, t012_secret)));
assert(isempty(strfind(t012_result.progress.archive_path, t012_secret)));
assert(isempty(strfind(t012_result.progress.archive_detail, t012_secret)));
assert(isempty(strfind(t012_result.progress.archive_detail, ...
    t012_malformed)));
assert(isempty(strfind(t012_result.progress.archive_detail, ...
    t012_unknown)));
assert(t012_result.evidence.progress_incomplete_trailing);
assert(t012_result.evidence.progress_pending_bytes == ...
    numel(t012_partial));
assert(~isfield(t012_result.evidence.progress, 'pending'));
assert(t012_result.evidence.progress_archive_succeeded);
assert(isempty(strfind(t012_result.evidence.failure_detail, t012_secret)));
assert(isempty(strfind(t012_result.evidence.progress_source_path, ...
    t012_secret)));
assert(isempty(strfind(t012_result.evidence.progress_archive_detail, ...
    t012_secret)));
t012_persisted = load(fullfile(t012_root, 'durable', ...
    'mlsc_evidence.mat'));
assert(isempty(strfind(t012_persisted.snapshot.failure_detail, ...
    t012_secret)));
assert(isempty(strfind(t012_persisted.snapshot.progress_source_path, ...
    t012_secret)));
assert(isempty(strfind(t012_persisted.snapshot.progress_archive_detail, ...
    t012_secret)));
assert(isempty(strfind(t012_persisted.snapshot.progress_archive_path, ...
    t012_secret)));
assert(~isfield(t012_persisted.snapshot.progress, 'pending'));
assert(isequal(t012_persisted.snapshot.progress_milestones, ...
    {'stage_in|done'; 'pseudoCT|start'; 'pseudoCT|done'}));

% R2010b/mlint compatibility guard for the lifecycle seams under test.
t006_lifecycle_source = t006_read_text(fullfile(root_dir, 'src', ...
    'mlsc', 'mlsc_lifecycle.m'));
assert(~isempty(strfind(t006_lifecycle_source, ...
    'Minimum supported MATLAB: R2010b')));
assert(isempty(regexp(t006_lifecycle_source, ...
    '(^|[^A-Za-z0-9_])contains\(', 'once')));
assert(isempty(regexp(t006_lifecycle_source, ...
    '(^|[^A-Za-z0-9_])startsWith\(', 'once')));
assert(isempty(regexp(t006_lifecycle_source, ...
    '(^|[^A-Za-z0-9_])string\(', 'once')));
t006_mlint_targets = {fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_lifecycle.m'); fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_progress.m'); fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_evidence.m')};
for t006_kk = 1:length(t006_mlint_targets)
    try
        mlint(t006_mlint_targets{t006_kk});
    catch t006_ME %#ok<NASGU>
        assert(false, 'MLSC source failed to parse.');
    end
end
rmdir(temp_root, 's');

fprintf('=== MLSC Slurm parser/evidence/lifecycle tests passed ===\n');

function assert_error(callback)
failed = false;
try
    feval(callback);
catch %#ok<CTCH>
    failed = true;
end
assert(failed, 'The focused negative test did not fail closed.');
end

function local_touch(path_name)
fid = fopen(path_name, 'w');
assert(fid ~= -1, 'The focused lifecycle fixture could not be created.');
fwrite(fid, 'fixture');
fclose(fid);
end

function accepted = local_verify()
accepted = true;
end

function response = local_submit(~)
submit_calls = submit_calls + 1;
if strcmp(mode, 'success')
    local_touch(fullfile(temp_root, 'att_map.nii'));
elseif strcmp(mode, 'response_lost_recovered')
    local_touch(fullfile(temp_root, 'att_map.nii'));
end
if strcmp(mode, 'response_lost_recovered') || ...
        strcmp(mode, 'response_lost_timeout')
    response = '';
elseif strcmp(mode, 'ordinary_rejected')
    response = 'sbatch: error: rejected';
else
    response = '31415;mlsc';
end
end

function response = local_squeue(~)
squeue_calls = squeue_calls + 1;
if strcmp(mode, 'scheduler_error')
    error('pseudo_CT:TestInjectedScheduler', 'Injected scheduler query failure.');
end
response = 'RUNNING';
end

function response = local_sacct(~)
sacct_calls = sacct_calls + 1;
if strcmp(mode, 'response_lost_timeout')
    if cancel_calls > 0
        response = '31417|CANCELLED|0:15|2026-09-02T10:00:00|2026-09-02T10:01:00|60';
    else
        response = '31417|PENDING|0:0|2026-09-02T10:00:00||';
    end
elseif strcmp(mode, 'response_lost_recovered')
    response = '31416|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60';
elseif strcmp(mode, 'timeout') || strcmp(mode, 'sleep_error')
    response = '31415|PENDING|0:0|2026-09-02T10:00:00||';
elseif strcmp(mode, 'failed')
    response = '31415|FAILED|2:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60';
elseif sacct_calls == 1
    response = '';
else
    response = '31415|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60';
end
end

function response = local_squeue_by_name(job_name)
assert(~isempty(regexp(job_name, '^pseudoCT_[A-Za-z0-9_.-]+$', 'once')));
reconciliation_squeue_calls = reconciliation_squeue_calls + 1;
if strcmp(mode, 'response_lost_recovered')
    response = '31416';
elseif strcmp(mode, 'response_lost_timeout')
    response = '31417';
else
    response = '';
end
end

function response = local_sacct_by_name(job_name)
assert(~isempty(regexp(job_name, '^pseudoCT_[A-Za-z0-9_.-]+$', 'once')));
reconciliation_sacct_calls = reconciliation_sacct_calls + 1;
if strcmp(mode, 'response_lost_recovered')
    response = ['31416.batch|COMPLETED|0:0|2026-09-02T10:00:00|2026-09-02T10:01:00|60' ...
        char(10) '31416|PENDING|0:0|2026-09-02T10:00:00||'];
elseif strcmp(mode, 'response_lost_timeout')
    response = '31417|PENDING|0:0|2026-09-02T10:00:00||';
else
    response = '';
end
end

function local_cancel(~)
cancel_calls = cancel_calls + 1;
end

function local_sleep(~)
if strcmp(mode, 'sleep_error')
    error('pseudo_CT:TestInjectedSleep', 'Injected polling sleep failure.');
end
end

function accepted = t006_verify()
accepted = true;
end

function response = t006_submit(~)
t006_submit_calls = t006_submit_calls + 1;
local_touch(fullfile(t006_case_root_current, 'att_map.nii'));
local_touch(fullfile(t006_case_root_current, 'pseudoCT_mlsc_31415.out'));
local_touch(fullfile(t006_case_root_current, 'pseudoCT_mlsc_31415.err'));
if ~isempty(t006_progress_seed)
    seed_fid = fopen(t006_progress_path_current(), 'w');
    if seed_fid ~= -1
        for seed_kk = 1:numel(t006_progress_seed)
            fwrite(seed_fid, [t006_progress_seed{seed_kk} char(10)]);
        end
        fclose(seed_fid);
    end
end
if strcmp(t006_correlation_current, 't011corr01')
    t011_legacy = fopen(fullfile(t006_case_root_current, ...
        '.mlsc_progress'), 'w');
    if t011_legacy ~= -1
        fwrite(t011_legacy, ['pseudoCT|done' char(10) ...
            'copy_back|done' char(10)]);
        fclose(t011_legacy);
    end
end
response = '31415;mlsc';
end

function response = t006_squeue(~)
t006_squeue_idx = t006_squeue_idx + 1;
if t006_squeue_idx <= numel(t006_squeue_appends) && ...
        ~isempty(t006_squeue_appends{t006_squeue_idx})
    append_fid = fopen(t006_progress_path_current(), 'a');
    if append_fid ~= -1
        fwrite(append_fid, t006_squeue_appends{t006_squeue_idx});
        fclose(append_fid);
    end
end
if strcmp(t006_correlation_current, 't011corr01')
    t011_keep = fopen(fullfile(t006_case_root_current, ...
        '.mlsc_progress'), 'w');
    if t011_keep ~= -1
        fwrite(t011_keep, ['pseudoCT|done' char(10) ...
            'copy_back|done' char(10)]);
        fclose(t011_keep);
    end
end
pick = t006_squeue_idx;
if pick > numel(t006_squeue_seq)
    pick = numel(t006_squeue_seq);
end
response = t006_squeue_seq{pick};
end

function response = t006_sacct(~)
t006_sacct_idx = t006_sacct_idx + 1;
pick = t006_sacct_idx;
if pick > numel(t006_sacct_seq)
    pick = numel(t006_sacct_seq);
end
response = t006_sacct_seq{pick};
end

function response = t006_empty_name(~)
response = '';
end

function t006_cancel(~)
t006_cancel_calls = t006_cancel_calls + 1;
end

function t006_sleep(~)
end

function value = t006_clock()
value = t006_clock_base + (t006_squeue_idx * t006_clock_step) / 86400;
end

function text = t006_read_text(path_name)
fid = fopen(path_name, 'r');
if fid == -1
    text = '';
    return;
end
text = fread(fid, inf, '*char')';
fclose(fid);
end

function n = t006_count(haystack, needle)
n = length(strfind(haystack, needle));
end

function progress_path = t006_progress_path_current()
%T006_PROGRESS_PATH_CURRENT Exact per-submission path for the active case.
%   Mirrors the production explicit passing: the current submission's
%   correlation selects one unique file, never a scanned latest file.
if ~isempty(t006_correlation_current)
    progress_path = mlsc_progress('path_for', ...
        t006_case_root_current, t006_correlation_current);
else
    progress_path = fullfile(t006_case_root_current, '.mlsc_progress');
end
end
end
