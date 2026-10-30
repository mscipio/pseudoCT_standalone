function snapshot = mlsc_evidence(event, previous, values)
%MLSC_EVIDENCE Capture bounded, credential-free MLSC lifecycle evidence.
%   SNAPSHOT = MLSC_EVIDENCE(EVENT, PREVIOUS, VALUES) mirrors the existing
%   launchpad_evidence state seam without submitting, polling, or transporting
%   anything.  The only persisted artifact is mlsc_evidence.mat when EVENT is
%   write.  Runtime account selection is allowed; credentials and SSH details
%   are rejected, not serialized.
%
%   Minimum supported MATLAB: R2010b.

if nargin < 1 || isempty(event)
    event = 'init';
end
if nargin < 2 || isempty(previous)
    previous = struct();
end
if nargin < 3 || isempty(values)
    values = struct();
end

if strcmp(event, 'write')
    evidence_dir = previous;
    snapshot = values;
    if ~isstruct(snapshot)
        error('pseudo_CT:MLSCEvidence', 'MLSC evidence must be a struct.');
    end
    local_assert_safe_values(snapshot);
    if exist(evidence_dir, 'dir') ~= 7
        error('pseudo_CT:MLSCEvidencePath', ...
            'Evidence directory not found: %s', evidence_dir);
    end
    save(fullfile(evidence_dir, 'mlsc_evidence.mat'), 'snapshot');
    return;
end

if strcmp(event, 'init')
    snapshot = local_new_snapshot(previous);
else
    snapshot = previous;
    if ~isstruct(snapshot) || ~isfield(snapshot, 'schema')
        snapshot = local_new_snapshot(snapshot);
    end
    if ~isfield(snapshot, 'lifecycle') || isempty(snapshot.lifecycle)
        snapshot.lifecycle = {'init'};
    end
    snapshot.lifecycle{end + 1} = event;
    snapshot = local_merge_values(snapshot, values);
end
local_assert_safe_values(snapshot);
end

function snapshot = local_new_snapshot(values)
snapshot = struct();
snapshot.schema = 'pseudo-CT.mlsc-evidence/v1';
snapshot.profile = 'mlsc';
snapshot.lifecycle = {'init'};
snapshot.subject_count = 1;
snapshot.subject_id = '';
snapshot.runtime_account = '';
snapshot.job_id = 0;
snapshot.submission_attempted = false;
snapshot.submission_response_lost = false;
snapshot.submission_response_parseable = false;
snapshot.submission_reconciled = false;
snapshot.submission_reconciliation_attempts = 0;
snapshot.submission_outcome = 'not_attempted';
snapshot.submission_callback_failed = false;
snapshot.submission_receipt_path = '';
snapshot.submission_correlation_id = '';
snapshot.job_name = '';
snapshot.squeue_reconciliation_query_contract = ...
    'squeue --noheader --user="$USER" --name=JOB_NAME --format=%A';
snapshot.sacct_reconciliation_query_contract = ...
    'sacct --allocations --noheader --parsable2 --user="$USER" --name=JOB_NAME --format=JobIDRaw,State,ExitCode,Start,End,Elapsed';
snapshot.state = 'unknown';
snapshot.scheduler_state = 'unknown';
snapshot.exit_code = [];
snapshot.exit_signal = [];
snapshot.exit_code_text = '';
snapshot.scheduler_start_time = '';
snapshot.scheduler_end_time = '';
snapshot.scheduler_elapsed = '';
snapshot.accounting_source = 'sacct primary allocation';
snapshot.accounting_record_found = false;
snapshot.primary_allocation = false;
snapshot.cancel_requested = false;
snapshot.cancel_succeeded = false;
snapshot.squeue_query_contract = ...
    'squeue --noheader --jobs=JOBID --format=%T';
snapshot.sacct_query_contract = ...
    'sacct --allocations --noheader --parsable2 --jobs=JOBID --format=JobIDRaw,State,ExitCode,Start,End,Elapsed';
snapshot.timestamps = local_empty_timestamps();
snapshot.created_at = '';
snapshot.submitted_at = '';
snapshot.started_at = '';
snapshot.finished_at = '';
snapshot.cleaned_at = '';
snapshot.shared_subject_temp = '';
snapshot.evidence_dir = '';
snapshot.evidence_path = '';
snapshot.log_paths = struct('stdout', '', 'stderr', '', ...
    'stdout_resolved', '', 'stderr_resolved', '', ...
    'stdout_archive', '', 'stderr_archive', '', ...
    'archive_attempted', false, 'archive_succeeded', false, ...
    'archive_detail', '');
snapshot.node_local_root = '$TMPDIR';
snapshot.shared_input_staging = 'cp shared subject temp to node-local TMPDIR';
snapshot.node_local_processing = 'heavy processing executes in node-local TMPDIR';
snapshot.shared_output_staging = 'cp node-local TMPDIR outputs to shared subject temp';
snapshot.scp_used = false;
snapshot.network_payload_staging = false;
snapshot.copy_back = struct('contract_represented', false, ...
    'verified', false, 'att_map_path', '', 'att_map_present', false, ...
    'att_map_nonempty', false);
snapshot.progress = local_empty_progress_snapshot();
snapshot.progress_milestones = cell(0, 1);
snapshot.progress_source_path = '';
snapshot.progress_archive_path = '';
snapshot.progress_cursor_offset = 0;
snapshot.progress_incomplete_trailing = false;
snapshot.progress_pending_bytes = 0;
snapshot.progress_archive_attempted = false;
snapshot.progress_archive_succeeded = false;
snapshot.progress_archive_detail = '';
snapshot.cleanup = struct('attempted', false, 'script_removed', false, ...
    'script_preserved', false, ...
    'node_local_tmpdir', 'Slurm-owned cleanup on job exit', ...
    'shared_subject_temp_preserved', true, 'failure_detail', '');
snapshot.failure = struct('present', false, 'detail', '');
snapshot.failure_detail = '';
snapshot.interrupted = false;
snapshot.interruption_detail = '';
snapshot.terminal = false;
snapshot.workflow_success = false;
snapshot.eligible_for_finalization = false;
snapshot.finalization = struct('attempted', false, 'succeeded', false, ...
    'status', 'not_attempted', 'detail', '', 'evidence_path', '');
snapshot.finalization_status = 'not_attempted';
snapshot.finalization_completed_at = '';
snapshot.workflow_finalization_succeeded = false;
snapshot = local_merge_values(snapshot, values);
end

function timestamps = local_empty_timestamps()
timestamps = struct('created_at', '', 'submitted_at', '', 'started_at', '', ...
    'finished_at', '', 'cleaned_at', '');
end

function progress = local_empty_progress_snapshot()
progress = struct();
progress.source_path = '';
progress.archive_path = '';
progress.milestones = cell(0, 1);
progress.cursor_offset = 0;
progress.incomplete_trailing = false;
progress.pending_bytes = 0;
progress.archive_attempted = false;
progress.archive_succeeded = false;
progress.archive_detail = '';
end

function snapshot = local_merge_values(snapshot, values)
if ~isstruct(values)
    return;
end
local_assert_safe_values(values);
names = fieldnames(values);
for ii = 1:length(names)
    snapshot.(names{ii}) = values.(names{ii});
end
end

function local_assert_safe_values(values)
if ~isstruct(values)
    return;
end
for item = 1:numel(values)
    names = fieldnames(values(item));
    for ii = 1:length(names)
        name = lower(names{ii});
        if local_forbidden_field(name)
            error('pseudo_CT:MLSCEvidenceSecret', ...
                'Credential and SSH internals cannot be stored in MLSC evidence.');
        end
        value = values(item).(names{ii});
        if isstruct(value)
            local_assert_safe_values(value);
        elseif iscell(value)
            for jj = 1:numel(value)
                if isstruct(value{jj})
                    local_assert_safe_values(value{jj});
                end
            end
        end
    end
end
end

function forbidden = local_forbidden_field(name)
forbidden_names = {'username'; 'password'; 'passphrase'; 'credentials'; ...
    'credential'; 'token'; 'secret'; 'transport'; 'ssh'; 'ssh2'; ...
    'host_key'; 'authentication'; 'auth'};
forbidden = any(strcmp(name, forbidden_names)) || ...
    ~isempty(regexp(name, '(^|_)(username|password|credential|secret|token|ssh)(_|$)', ...
    'once'));
end
