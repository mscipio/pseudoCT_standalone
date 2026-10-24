function result = mlsc_lifecycle(subject, config, runtime, transport)
%MLSC_LIFECYCLE Submit, monitor, and finalize one MLSC Slurm subject record.
%   RESULT = MLSC_LIFECYCLE(SUBJECT, CONFIG, RUNTIME, TRANSPORT) reuses the
%   T003 mlsc_backend submission seam, then uses injected query/cancel seams:
%       TRANSPORT.query_squeue(JOB_ID)
%       TRANSPORT.query_sacct(JOB_ID)
%       TRANSPORT.cancel_job(JOB_ID)
%       TRANSPORT.query_squeue_by_name(JOB_NAME)
%       TRANSPORT.query_sacct_by_name(JOB_NAME)
%   The callbacks return stable command output, never credentials or SSH
%   internals.  TRANSPORT.sleep and TRANSPORT.clock are optional test seams;
%   defaults are pause and now.  No real scheduler operation is performed by
%   this function unless a caller supplies those runtime callbacks.
%   query_squeue must use squeue --noheader --format=%T and query_sacct must
%   use sacct --allocations --parsable2 with JobIDRaw, State, and
%   ExitCode fields.
%
%   Scheduler-facing user output uses the pseudo_CT_output formatter with a
%   non-secret RUNTIME.output_context (log routing/scope tags only; the
%   numeric job ID is added as the job tag).  After an accepted numeric job
%   ID, the first observed normalized scheduler state is emitted as observed
%   (pending only when first observed pending, running directly when first
%   already running, otherwise the legitimate normalized state), each later
%   actual normalized state change is emitted once, a default 60-second
%   heartbeat (RUNTIME.heartbeat_interval_seconds) reports job ID, state,
%   and elapsed while pending/running from the existing poll loop and
%   TRANSPORT.clock without extra queries or sleeps, and a terminal summary
%   reports job ID, state, exit code (or unavailable marker), and elapsed.
%   Output never changes polling cadence, scheduler queries, cancellation,
%   accounting authority, timeout, or eligibility semantics.
%
%
%   sacct --allocations/primary allocation data is authoritative for terminal
%   state and ExitCode.  A scheduler COMPLETED state is not workflow success
%   until the generated T003 node-local/copy-back contract is represented and
%   shared_subject_temp/att_map.nii is present and non-empty.
%   Terminal Slurm logs are archived to runtime.log_archive_dir before any
%   local finalization can remove the shared subject temp.
%
%   The exact per-submission progress artifact selected by the current
%   submission (shared_subject_temp/.mlsc_progress_<correlation-id>,
%   passed explicitly through the backend artifact) is consumed with its
%   incremental cursor during each existing scheduler poll and once at
%   terminal without adding queries or sleeps and without directory
%   scanning or latest-file inference.  Only that file is ever read; a
%   stale legacy or prior-submission file that remains present or
%   undeletable is never emitted.  A missing, late, partial, or unreadable
%   file never fails the job; only complete enumerated records are emitted
%   once, invalid input stays silent and secret-free.  A bounded
%   secret-free incomplete-trailing indicator (logical flag plus
%   pending-byte count, never the trailing content) is persisted in
%   result.progress and terminal evidence so a terminal partial record
%   remains diagnosable.  Stage-in, preparation, alias-recenter,
%   normalization, alignment-mask, segmentation, bone, DARTEL-warp-reslice,
%   pseudoCT, and attenuation-QC milestones render at stage 3/8, verify
%   and copy-back milestones render only at
%   stage 4/8, and a successful copy-back completion represents the
%   verified return to shared temp.  The durable archive is generated only
%   from the validated recognized milestone sequence (order preserved,
%   at-most-once, from the parser accepted output) and never copies raw
%   source bytes, so malformed, unknown, secret-bearing, or
%   incomplete-trailing input is never archived or echoed; evidence keeps
%   only the incomplete-trailing flag plus pending-byte/ignored counts and
%   never raw rejected content.  Archival is best-effort to the durable
%   per-subject destination under its correlation-preserving name before
%   local cleanup, independent of Slurm log capture with the same
%   non-fatal policy; the raw source itself is left for the existing
%   shared-temp success/failure preservation behavior but is never
%   promoted.
%
%   Minimum supported MATLAB: R2010b.

if nargin < 2 || ~isstruct(subject) || ~isstruct(config)
    error('pseudo_CT:MLSCPreflight', ...
        'An MLSC subject and selected profile config are required.');
end
if nargin < 4 || ~isstruct(transport) || numel(transport) ~= 1
    error('pseudo_CT:MLSCTransportRequired', ...
        'MLSC lifecycle requires a secure runtime transport seam.');
end
if ~isfield(transport, 'query_squeue') || ...
        ~isa(transport.query_squeue, 'function_handle') || ...
        ~isfield(transport, 'query_sacct') || ...
        ~isa(transport.query_sacct, 'function_handle') || ...
        ~isfield(transport, 'cancel_job') || ...
        ~isa(transport.cancel_job, 'function_handle') || ...
        ~isfield(transport, 'query_squeue_by_name') || ...
        ~isa(transport.query_squeue_by_name, 'function_handle') || ...
        ~isfield(transport, 'query_sacct_by_name') || ...
        ~isa(transport.query_sacct_by_name, 'function_handle')
    error('pseudo_CT:MLSCTransportRequired', ...
        ['MLSC lifecycle requires scheduler, cancellation, and bounded ', ...
         'submission-reconciliation callbacks.']);
end

if nargin < 3 || isempty(runtime)
    runtime = struct();
end
if ~isstruct(runtime) || numel(runtime) ~= 1
    error('pseudo_CT:MLSCPreflight', 'Runtime MLSC values must be one struct.');
end
runtime = local_runtime_defaults(runtime);
local_validate_runtime(runtime);

    result = local_initial_result(subject, runtime, transport);
evidence = mlsc_evidence('init', local_evidence_values(result));

try
    backend = mlsc_backend(subject, config, runtime, transport);
catch ME
    result.state = 'failed';
    result.scheduler_state = 'unknown';
    result.workflow_state = 'failed';
    result.terminal = true;
    result.failure_detail = local_backend_failure_detail(ME);
    result.failure = struct('present', true, 'detail', result.failure_detail);
    result.timestamps.finished_at = local_timestamp(transport);
    result = local_finish(result, evidence, runtime, transport);
    return;
end
    result = local_apply_backend_submission(result, backend);
    if ~backend.submission_accepted
        result.state = 'failed';
        result.scheduler_state = 'unknown';
        result.workflow_state = 'failed';
        result.terminal = true;
        result.failure_detail = ...
            ['MLSC submission response was missing or unparseable; no matching ', ...
             'Slurm allocation was recovered and no retry was attempted.'];
        result.failure = struct('present', true, 'detail', result.failure_detail);
        result.timestamps.finished_at = local_timestamp(transport);
        result = local_finish(result, evidence, runtime, transport);
        return;
    end

    result.job_id = backend.job_id;
    if isfield(backend, 'log_paths') && isstruct(backend.log_paths)
    result.log_paths = local_apply_log_paths(result.log_paths, ...
        backend.log_paths, runtime.log_archive_dir);
end
job_id = result.job_id;
result.submitted = true;
result.submission_accepted = true;
result.state = 'pending';
result.scheduler_state = 'pending';
result.workflow_state = 'pending';
result.timestamps.submitted_at = local_timestamp(transport);
result = local_append_state(result, 'pending', transport);
result.contract = local_contract_from_artifact(backend.artifact);
[progress_path, progress_cursor, progress_milestones] = ...
    local_progress_init(backend, result.shared_subject_temp);
result.progress.source_path = progress_path;
result.progress.milestones = progress_milestones;
try
    result.progress.cursor_offset = progress_cursor.offset;
catch %#ok<CTCH>
end
result = local_progress_record_trailing(result, progress_cursor);

output_tracker = local_output_init(runtime, transport);
local_emit_accepted(runtime, job_id);
terminal_observed = false;
accounting_deadline = [];
polling_result = false;
guard_id = local_poll_guard('register', [], struct('result', result, ...
    'evidence', evidence, 'runtime', runtime, 'transport', transport));
polling_guard = onCleanup(@() local_poll_guard('cleanup', guard_id, struct()));
try
    for poll = 1:runtime.max_polls
        result.poll_count = poll;
        local_poll_guard('update', guard_id, struct('result', result, ...
            'evidence', evidence, 'runtime', runtime, 'transport', transport));
        try
            squeue_state = mlsc_parse_squeue_state( ...
                feval(transport.query_squeue, job_id));
        catch ME
            result.squeue_query_failures = result.squeue_query_failures + 1;
            rethrow(ME);
        end
        result = local_append_state(result, squeue_state, transport);
        if strcmp(squeue_state, 'running') && isempty(result.timestamps.started_at)
            result.timestamps.started_at = local_timestamp(transport);
        end
        output_tracker = local_output_note(output_tracker, runtime, ...
            job_id, squeue_state, transport);

        try
            sacct_record = mlsc_parse_sacct_terminal( ...
                feval(transport.query_sacct, job_id), job_id);
        catch ME
            result.sacct_query_failures = result.sacct_query_failures + 1;
            rethrow(ME);
        end
        if sacct_record.found
            result.accounting_record_found = true;
            result = local_append_state(result, sacct_record.state, transport);
            % sacct is authoritative only for terminal states; non-terminal
            % accounting records reflect lag and never drive pending/running
            % display, which follows the live squeue observation.
            if sacct_record.terminal
                output_tracker = local_output_note(output_tracker, runtime, ...
                    job_id, sacct_record.state, transport);
                result = local_apply_accounting(result, sacct_record, subject, transport);
                polling_result = true;
                break;
            end
        end

        if local_is_terminal(squeue_state)
            terminal_observed = true;
            if isempty(accounting_deadline)
                accounting_deadline = local_clock(transport) + ...
                    runtime.accounting_timeout_seconds / 86400;
            end
        end

        elapsed = local_elapsed_seconds(result.clock_started, local_clock(transport));
        result.elapsed_seconds = elapsed;
        if elapsed >= runtime.timeout_seconds
            result = local_request_cancel(result, transport);
            [result, sacct_record, accounting_done, output_tracker, ...
                progress_cursor, progress_milestones] = ...
                local_wait_for_accounting(result, runtime, transport, ...
                output_tracker, progress_path, progress_cursor, ...
                progress_milestones);
            if accounting_done
                result = local_apply_accounting(result, sacct_record, subject, transport);
            else
                result = local_apply_deadline(result, 'timeout', transport, ...
                    'MLSC polling timed out before authoritative terminal accounting was available.');
            end
            polling_result = true;
            break;
        end
        if terminal_observed && local_clock(transport) >= accounting_deadline
            result = local_apply_deadline(result, 'unknown', transport, ...
                'sacct terminal accounting remained unavailable after a bounded wait.');
            polling_result = true;
            break;
        end
        output_tracker = local_output_maybe_heartbeat(output_tracker, ...
            runtime, job_id, result, transport);
        try
            [progress_cursor, progress_milestones] = local_progress_poll( ...
                progress_path, progress_cursor, progress_milestones, ...
                runtime, job_id);
            result.progress.milestones = progress_milestones;
            try
                result.progress.cursor_offset = progress_cursor.offset;
            catch %#ok<CTCH>
            end
            result = local_progress_record_trailing(result, ...
                progress_cursor);
            local_poll_guard('update', guard_id, struct('result', result, ...
                'evidence', evidence, 'runtime', runtime, ...
                'transport', transport));
        catch %#ok<CTCH>
        end
        if poll < runtime.max_polls
            local_sleep(runtime.poll_interval_seconds, transport);
        end
    end

    % A bounded poll count protects injected clocks and failed scheduler seams.
    if ~polling_result
        if terminal_observed
            result = local_apply_deadline(result, 'unknown', transport, ...
                'sacct terminal accounting remained unavailable after a bounded wait.');
        else
            result = local_request_cancel(result, transport);
            [result, sacct_record, accounting_done, output_tracker, ...
                progress_cursor, progress_milestones] = ...
                local_wait_for_accounting(result, runtime, transport, ...
                output_tracker, progress_path, progress_cursor, ...
                progress_milestones);
            if accounting_done
                result = local_apply_accounting(result, sacct_record, subject, transport);
            else
                result = local_apply_deadline(result, 'timeout', transport, ...
                    'MLSC polling reached its bounded poll limit before terminal accounting.');
            end
        end
    end
catch %#ok<CTCH>
    result = local_apply_interrupted(result, transport);
end
try
    [progress_cursor, progress_milestones] = local_progress_poll( ...
        progress_path, progress_cursor, progress_milestones, runtime, ...
        job_id);
    result.progress.milestones = progress_milestones;
    try
        result.progress.cursor_offset = progress_cursor.offset;
    catch %#ok<CTCH>
    end
    result = local_progress_record_trailing(result, progress_cursor);
catch %#ok<CTCH>
end
local_emit_terminal(runtime, result, transport);
local_poll_guard('deactivate', guard_id, struct());
result = local_finish(result, evidence, runtime, transport);
clear polling_guard
end

function guard_id = local_poll_guard(action, guard_id, state)
%LOCAL_POLL_GUARD Keep post-submission unwind state outside the parent stack.
persistent guards next_id
if isempty(next_id)
    next_id = 1;
    guards = struct('id', {}, 'result', {}, 'evidence', {}, ...
        'runtime', {}, 'transport', {});
end
if isempty(guards)
    guards = struct('id', {}, 'result', {}, 'evidence', {}, ...
        'runtime', {}, 'transport', {});
end

if strcmp(action, 'register')
    guard_id = next_id;
    next_id = next_id + 1;
    guards(end + 1) = struct('id', guard_id, 'result', state.result, ...
        'evidence', state.evidence, 'runtime', state.runtime, ...
        'transport', state.transport);
    return;
end

position = 0;
for ii = 1:length(guards)
    if guards(ii).id == guard_id
        position = ii;
        break;
    end
end
if position == 0
    return;
end

if strcmp(action, 'update')
    guards(position).result = state.result;
    guards(position).evidence = state.evidence;
    guards(position).runtime = state.runtime;
    guards(position).transport = state.transport;
elseif strcmp(action, 'deactivate')
    guards(position) = [];
elseif strcmp(action, 'cleanup')
    entry = guards(position);
    guards(position) = [];
    try
        interrupted = local_apply_interrupted(entry.result, entry.transport);
        local_finish(interrupted, entry.evidence, entry.runtime, entry.transport);
    catch %#ok<CTCH>
        % Preserve the original interruption while making script cleanup
        % deterministic if evidence or log handling also fails.
        try
            local_cleanup(entry.result.cleanup, entry.runtime, ...
                entry.transport, entry.result.script_materialized);
        catch %#ok<CTCH>
        end
    end
end
end

function runtime = local_runtime_defaults(runtime)
if ~isfield(runtime, 'timeout_seconds')
    runtime.timeout_seconds = 7200;
end
if ~isfield(runtime, 'poll_interval_seconds')
    runtime.poll_interval_seconds = 30;
end
if ~isfield(runtime, 'accounting_timeout_seconds')
    runtime.accounting_timeout_seconds = 120;
end
if ~isfield(runtime, 'max_polls')
    if isnumeric(runtime.timeout_seconds) && isscalar(runtime.timeout_seconds) && ...
            isnumeric(runtime.poll_interval_seconds) && ...
            isscalar(runtime.poll_interval_seconds) && ...
            isfinite(runtime.timeout_seconds) && ...
            isfinite(runtime.poll_interval_seconds) && ...
            runtime.poll_interval_seconds > 0
        runtime.max_polls = max(1, ceil(runtime.timeout_seconds / ...
            runtime.poll_interval_seconds) + 1);
    else
        runtime.max_polls = 1;
    end
end
if ~isfield(runtime, 'max_accounting_polls')
    if isnumeric(runtime.accounting_timeout_seconds) && ...
            isscalar(runtime.accounting_timeout_seconds) && ...
            isnumeric(runtime.poll_interval_seconds) && ...
            isscalar(runtime.poll_interval_seconds) && ...
            isfinite(runtime.accounting_timeout_seconds) && ...
            isfinite(runtime.poll_interval_seconds) && ...
            runtime.poll_interval_seconds > 0
        runtime.max_accounting_polls = max(1, ceil( ...
            runtime.accounting_timeout_seconds / runtime.poll_interval_seconds) + 1);
    else
        runtime.max_accounting_polls = 1;
    end
end
if ~isfield(runtime, 'max_reconciliation_polls')
    runtime.max_reconciliation_polls = 3;
end
if ~isfield(runtime, 'reconciliation_interval_seconds')
    runtime.reconciliation_interval_seconds = runtime.poll_interval_seconds;
end
if ~isfield(runtime, 'cleanup_script')
    runtime.cleanup_script = true;
end
if ~isfield(runtime, 'profile')
    runtime.profile = 'mlsc';
end
if ~isfield(runtime, 'account')
    runtime.account = '';
end
if ~isfield(runtime, 'evidence_dir')
    runtime.evidence_dir = '';
end
if ~isfield(runtime, 'log_archive_dir')
    runtime.log_archive_dir = '';
end
if ~isfield(runtime, 'heartbeat_interval_seconds')
    runtime.heartbeat_interval_seconds = 60;
end
if ~isfield(runtime, 'output_context')
    runtime.output_context = struct();
end
end

function local_validate_runtime(runtime)
positive_fields = {'timeout_seconds'; 'poll_interval_seconds'; ...
    'accounting_timeout_seconds'; 'heartbeat_interval_seconds'; ...
    'max_polls'; 'max_accounting_polls'; ...
    'max_reconciliation_polls'; 'reconciliation_interval_seconds'};
for ii = 1:length(positive_fields)
    value = runtime.(positive_fields{ii});
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value <= 0
        error('pseudo_CT:MLSCPreflight', ...
            'MLSC lifecycle bounds must be positive finite values.');
    end
end
if runtime.max_polls ~= floor(runtime.max_polls) || ...
        runtime.max_accounting_polls ~= floor(runtime.max_accounting_polls) || ...
        runtime.max_reconciliation_polls ~= floor(runtime.max_reconciliation_polls)
    error('pseudo_CT:MLSCPreflight', ...
        'MLSC lifecycle poll bounds must be positive integers.');
end
if ~islogical(runtime.cleanup_script) || ~isscalar(runtime.cleanup_script)
    error('pseudo_CT:MLSCPreflight', 'cleanup_script must be scalar logical.');
end
if ~ischar(runtime.profile) || ~ischar(runtime.account) || ...
        ~ischar(runtime.evidence_dir) || ~ischar(runtime.log_archive_dir) || ...
        (isfield(runtime, 'script_path') && ~ischar(runtime.script_path))
    error('pseudo_CT:MLSCPreflight', ...
        'MLSC runtime profile, account, and evidence directory must be text.');
end
if ~isstruct(runtime.output_context) || numel(runtime.output_context) ~= 1
    error('pseudo_CT:MLSCPreflight', ...
        'MLSC runtime output context must be one struct.');
end
end

function result = local_initial_result(subject, runtime, transport)
result = struct();
result.schema = 'pseudo-CT.mlsc-lifecycle/v1';
result.profile = runtime.profile;
result.subject_id = local_subject_value(subject, {'subject_id'; 'id'; 'name'});
result.runtime_account = runtime.account;
result.job_id = 0;
result.submitted = false;
result.submission_accepted = false;
result.submission_attempted = false;
result.submission_response_lost = false;
result.submission_response_parseable = false;
result.submission_reconciled = false;
result.submission_reconciliation_attempts = 0;
result.submission_outcome = 'not_attempted';
result.submission_callback_failed = false;
result.submission_receipt_path = '';
result.submission_correlation_id = '';
result.job_name = '';
result.squeue_reconciliation_query_contract = ...
    'squeue --noheader --user="$USER" --name=JOB_NAME --format=%A';
result.sacct_reconciliation_query_contract = ...
    'sacct --allocations --noheader --parsable2 --user="$USER" --name=JOB_NAME --format=JobIDRaw,State,ExitCode,Start,End,Elapsed';
result.script_materialized = false;
result.terminal = false;
result.state = 'unknown';
result.scheduler_state = 'unknown';
result.workflow_state = 'unknown';
result.exit_code = [];
result.exit_signal = [];
result.exit_code_text = '';
result.scheduler_start_time = '';
result.scheduler_end_time = '';
result.scheduler_elapsed = '';
result.accounting_source = 'sacct primary allocation';
result.squeue_query_contract = ...
    'squeue --noheader --jobs=JOBID --format=%T';
result.sacct_query_contract = ...
    'sacct --allocations --noheader --parsable2 --jobs=JOBID --format=JobIDRaw,State,ExitCode,Start,End,Elapsed';
result.accounting_record_found = false;
result.primary_allocation = false;
result.poll_count = 0;
result.squeue_query_failures = 0;
result.sacct_query_failures = 0;
result.state_history = {'init'};
result.cancel_requested = false;
result.cancel_succeeded = false;
result.contract = local_empty_contract();
result.shared_subject_temp = local_subject_value(subject, ...
    {'shared_temp'; 'temp_dir'});
result.evidence_dir = runtime.evidence_dir;
result.evidence_path = '';
if ~isempty(runtime.evidence_dir)
    result.evidence_path = fullfile(runtime.evidence_dir, 'mlsc_evidence.mat');
end
result.log_paths = local_empty_log_paths(result.shared_subject_temp, ...
    runtime.log_archive_dir);
result.progress = local_empty_progress();
result.copy_back = struct('contract_represented', false, ...
    'verified', false, 'att_map_path', '', 'att_map_present', false, ...
    'att_map_nonempty', false);
result.scp_used = false;
result.network_payload_staging = false;
result.executor_provenance = local_empty_executor_provenance();
result.cleanup = struct('attempted', false, 'script_removed', false, ...
    'script_preserved', false, ...
    'node_local_tmpdir', 'Slurm-owned cleanup on job exit', ...
    'shared_subject_temp_preserved', true, 'failure_detail', '');
result.failure = struct('present', false, 'detail', '');
result.failure_detail = '';
result.interrupted = false;
result.interruption_detail = '';
result.success = false;
result.eligible_for_finalization = false;
result.evidence_saved = false;
result.evidence_save_failed = false;
result.timestamps = struct('created_at', local_timestamp(transport), ...
    'submitted_at', '', 'started_at', '', 'finished_at', '', 'cleaned_at', '');
result.clock_started = local_clock(transport);
result.elapsed_seconds = 0;
end

function contract = local_empty_contract()
contract = struct('represented', false, 'node_local_processing', false, ...
    'shared_input_staging', false, 'shared_output_staging', false, ...
    'required_output', 'att_map.nii', 'no_scp_network_payload', true, ...
    'heavy_processing_root', '$TMPDIR');
contract.is_current = false;
end

function contract = local_contract_from_artifact(artifact)
%LOCAL_CONTRACT_FROM_ARTIFACT Node-local/copy-back contract from script.
%   T004 current seam (T014 authoritative): legacy checks unchanged. When
%   the artifact selects current (is_current), additionally require the
%   pinned launcher invocation, prepare BEFORE external normalization
%   BEFORE compute, staged job/resource manifests, PREPARE-derived dynamic
%   normalization (corrected selection without sourcing the handoff),
%   three-output plus mandatory-evidence verify and copy-back, current
%   milestones, pinned startup recheck, FreeSurfer isolation, and no
%   global LD_LIBRARY_PATH. The existing heartbeat/progress/cancellation/
%   receipt/timeout/cleanup/finalization model is reused with no second
%   poller.
contract = local_empty_contract();
if ~isstruct(artifact)
    return;
end
script = '';
if isfield(artifact, 'script_text')
    script = artifact.script_text;
end
if isfield(artifact, 'heavy_processing_root')
    contract.heavy_processing_root = artifact.heavy_processing_root;
end
if isfield(artifact, 'is_current') && isequal(artifact.is_current, true)
    contract.is_current = true;
end
contract.node_local_processing = strcmp(contract.heavy_processing_root, '$TMPDIR') && ...
    ~isempty(strfind(script, 'cd "$TMPDIR"')) && ...
    ~isempty(strfind(script, 'att_map.nii'));
contract.shared_input_staging = ~isempty(strfind(script, ...
    'cp -- "$shared_input" "$local_input"'));
contract.shared_output_staging = ~isempty(strfind(script, ...
    'cp -- "$TMPDIR/att_map.nii" "$shared_temp/att_map.nii"')) && ...
    ~isempty(strfind(script, 'Shared att_map.nii copy-back is missing or empty.'));
contract.no_scp_network_payload = contract.no_scp_network_payload && ...
    isempty(strfind(lower(script), 'scp'));
if isfield(artifact, 'network_payload_staging')
    contract.no_scp_network_payload = ~artifact.network_payload_staging;
end
contract.represented = contract.node_local_processing && ...
    contract.shared_input_staging && contract.shared_output_staging && ...
    contract.no_scp_network_payload;
if contract.is_current
    current_ok = ~isempty(strfind(script, '"$current_runner" "$current_mcr_root" prepare')) && ...
        ~isempty(strfind(script, '"$current_runner" "$current_mcr_root" compute')) && ...
        ~isempty(strfind(script, 'cp -- "$shared_job_manifest" "$local_job_manifest"')) && ...
        ~isempty(strfind(script, 'cp -- "$shared_resource_manifest" "$local_resource_manifest"')) && ...
        ~isempty(strfind(script, 'env -u LD_LIBRARY_PATH')) && ...
        ~isempty(strfind(script, 'tcsh -f -c')) && ...
        ~isempty(strfind(script, 'Fusion_MR_Pseudo_CT_validation.tiff')) && ...
        ~isempty(strfind(script, 'Pseudo_CT_AC_Version.txt')) && ...
        ~isempty(strfind(script, 'mlsc_current_output_verification.txt')) && ...
        ~isempty(strfind(script, 'mlsc_current_prepare_evidence.txt')) && ...
        ~isempty(strfind(script, 'mlsc_current_handoff.mat')) && ...
        ~isempty(strfind(script, 'preparation|done')) && ...
        ~isempty(strfind(script, 'alias_recenter|done')) && ...
        ~isempty(strfind(script, 'alignment_mask|done')) && ...
        ~isempty(strfind(script, 'segmentation|done')) && ...
        ~isempty(strfind(script, 'bone|done')) && ...
        ~isempty(strfind(script, 'dartel_warp_reslice|done')) && ...
        ~isempty(strfind(script, 'attenuation_qc|done')) && ...
        ~isempty(strfind(script, 'prepare_selected=')) && ...
        ~isempty(strfind(script, 'prepare_expected=')) && ...
        ~isempty(strfind(script, 'pinned_mcr_root=')) && ...
        isempty(strfind(script, 'export LD_LIBRARY_PATH')) && ...
        isempty(strfind(script, 'source "$shared_temp/mlsc_current_handoff')) && ...
        isempty(strfind(script, 'source $TMPDIR/mlsc_current_handoff')) && ...
        isempty(strfind(script, 'eval '));
    prepare_pos = strfind(script, '"$current_runner" "$current_mcr_root" prepare');
    compute_pos = strfind(script, '"$current_runner" "$current_mcr_root" compute');
    if isempty(prepare_pos) || isempty(compute_pos) || ...
            ~(prepare_pos(1) < compute_pos(1))
        current_ok = false;
    end
    if needs_normalization_in_script(script)
        tcsh_pos = strfind(script, 'tcsh -f -c');
        if isempty(tcsh_pos) || ~(prepare_pos(1) < tcsh_pos(1)) || ...
                ~(tcsh_pos(1) < compute_pos(1))
            current_ok = false;
        end
        % R001: dynamic PREPARE-derived normalization must sit between
        % prepare and compute and must reference the resolved selection.
        if isempty(strfind(script, 'MLSC_INPUT_NAME=$prepare_selected')) || ...
                isempty(strfind(script, 'MLSC_NORMALIZED_NAME=$prepare_expected'))
            current_ok = false;
        end
    end
    % R003: mandatory evidence verify/copy-back (not copy_optional for
    % handoff/evidence) must be present.
    if isempty(strfind(script, 'cp -- "$TMPDIR/mlsc_current_handoff.mat" "$shared_temp/mlsc_current_handoff.mat"')) || ...
            isempty(strfind(script, 'cp -- "$TMPDIR/mlsc_current_output_verification.txt" "$shared_temp/mlsc_current_output_verification.txt"')) || ...
            isempty(strfind(script, 'Shared output verification copy-back is missing or empty.'))
        current_ok = false;
    end
    contract.represented = contract.represented && current_ok;
end
end

function flag = needs_normalization_in_script(script)
flag = ~isempty(strfind(script, 'normalize|start')) && ...
    ~isempty(strfind(script, 'mri_normalize'));
end

function record = local_empty_accounting_record(job_id)
record = struct('found', false, 'primary_allocation', false, ...
    'job_id', job_id, 'state', 'unknown', 'exit_code', [], ...
    'exit_signal', [], 'exit_code_text', '', 'terminal', false, ...
    'raw_state', '', 'start_time', '', 'end_time', '', 'elapsed', '');
end

function result = local_append_state(result, state, transport)
if isempty(state)
    state = 'unknown';
end
result.state_history{end + 1} = state;
if strcmp(state, 'running') && isempty(result.timestamps.started_at)
    result.timestamps.started_at = local_timestamp(transport);
end
end

function result = local_apply_accounting(result, record, subject, transport)
result.terminal = true;
result.success = false;
result.eligible_for_finalization = false;
result.failure_detail = '';
result.failure = struct('present', false, 'detail', '');
result.state = record.state;
result.scheduler_state = record.state;
result.workflow_state = record.state;
result.accounting_record_found = record.found;
result.primary_allocation = record.primary_allocation;
result.exit_code = record.exit_code;
result.exit_signal = record.exit_signal;
result.exit_code_text = record.exit_code_text;
result.scheduler_start_time = record.start_time;
result.scheduler_end_time = record.end_time;
result.scheduler_elapsed = record.elapsed;
result.timestamps.finished_at = local_timestamp(transport);
if strcmp(record.state, 'completed')
    result.copy_back = local_verify_copyback(result, subject);
    if ~record.exit_code_valid
        result.workflow_state = 'failed';
        result.failure_detail = ...
            'Scheduler COMPLETED reported an invalid Slurm ExitCode.';
    elseif record.exit_code ~= 0
        result.workflow_state = 'failed';
        result.failure_detail = ...
            'Scheduler COMPLETED reported a non-zero Slurm ExitCode.';
    elseif ~result.contract.represented
        result.workflow_state = 'failed';
        result.failure_detail = ...
            'Scheduler COMPLETED did not prove the node-local processing/copy-back contract.';
    elseif ~result.copy_back.verified
        if isfield(result.contract, 'is_current') && ...
                isequal(result.contract.is_current, true)
            result.failure_detail = ...
                'Scheduler COMPLETED had no complete current outputs in the shared subject temp.';
        else
            result.failure_detail = ...
                'Scheduler COMPLETED had no non-empty att_map.nii in the shared subject temp.';
        end
        result.workflow_state = 'failed';
    else
        result.workflow_state = 'completed';
        result.success = true;
        result.eligible_for_finalization = true;
    end
else
    result.failure_detail = ['Slurm job ended in normalized state ' ...
        record.state '.'];
end
if ~isempty(result.failure_detail)
    result.failure = struct('present', true, 'detail', result.failure_detail);
end
end

function result = local_apply_backend_submission(result, backend)
if ~isstruct(backend)
    return;
end
fields = {'submission_attempted'; 'submission_response_lost'; ...
    'submission_response_parseable'; 'submission_reconciled'; ...
    'submission_reconciliation_attempts'; 'submission_outcome'; ...
    'submission_callback_failed'; 'submission_receipt_path'; ...
    'submission_correlation_id'; 'job_name'; 'script_materialized'; ...
    'squeue_reconciliation_query_contract'; ...
    'sacct_reconciliation_query_contract'};
for ii = 1:length(fields)
    if isfield(backend, fields{ii})
        result.(fields{ii}) = backend.(fields{ii});
    end
end
end

function detail = local_backend_failure_detail(cause)
%LOCAL_BACKEND_FAILURE_DETAIL Keep the backend cause without secrets.
%   Retains only the underlying exception identifier and message strings in
%   the generic submission-failure wrapper.  No exception object, stack,
%   transport closure, credential, or host-key material is serialized.
base = 'MLSC submission failed before a numeric Slurm job ID was accepted.';
identifier = '';
message = '';
try
    if ischar(cause.identifier)
        identifier = strtrim(cause.identifier);
    end
catch %#ok<CTCH>
end
try
    if ischar(cause.message)
        message = strtrim(cause.message);
    end
catch %#ok<CTCH>
end
if isempty(identifier) && isempty(message)
    detail = base;
elseif isempty(identifier)
    detail = sprintf('%s Cause: %s', base, message);
elseif isempty(message)
    detail = sprintf('%s Cause: %s.', base, identifier);
else
    detail = sprintf('%s Cause: %s: %s', base, identifier, message);
end
end

function copy_back = local_verify_copyback(result, subject)
%LOCAL_VERIFY_COPYBACK Exit-0 plus missing output is failure.
%   Legacy requires non-empty att_map.nii. Current requires the complete
%   three-output set (att_map.nii plus validation TIFF plus version TXT)
%   plus mandatory durable evidence (handoff, prepare evidence, output
%   verification); exit 0 with any required output or evidence missing or
%   empty fails. The output-verification evidence attests the verified
%   normalized input and every required output with fingerprints, including
%   the finite float32 attenuation with dimensions/affine provenance
%   recorded by compute; copyback identity (shared bytes equal the
%   verified node-local bytes) is rechecked here before success via the
%   existing verification/failure path. Reuses the existing
%   receipt/timeout/cleanup/finalization model with no second poller.
%   Current participates identically in cancellation/state/receipt
%   handling; validation failures occur before science where possible.
copy_back = struct('contract_represented', result.contract.represented, ...
    'verified', false, 'att_map_path', '', 'att_map_present', false, ...
    'att_map_nonempty', false);
is_current = false;
try
    if isfield(result.contract, 'is_current') && ...
            isequal(result.contract.is_current, true)
        is_current = true;
    end
catch %#ok<CTCH>
end
shared_temp = local_subject_value(subject, {'shared_temp'; 'temp_dir'});
if isempty(shared_temp)
    return;
end
copy_back.att_map_path = fullfile(shared_temp, 'att_map.nii');
copy_back.att_map_present = exist(copy_back.att_map_path, 'file') == 2;
if copy_back.att_map_present
    info = dir(copy_back.att_map_path);
    copy_back.att_map_nonempty = ~isempty(info) && info(1).bytes > 0;
end
if ~is_current
    copy_back.verified = copy_back.contract_represented && ...
        copy_back.att_map_present && copy_back.att_map_nonempty;
    return;
end
% Explicit authoritative key->basename map owned by the current output
% contract: no underscore/dot inference. The validation TIFF is the
% Fusion basename or, as declared, the explicit Composite variant.
output_map = local_current_output_filename_map();
validation_candidates = {output_map.validation_fusion; ...
    output_map.validation_composite};
validation_path = '';
validation_ok = false;
for vv = 1:length(validation_candidates)
    candidate_path = fullfile(shared_temp, validation_candidates{vv});
    if exist(candidate_path, 'file') == 2
        info = dir(candidate_path);
        if ~isempty(info) && info(1).bytes > 0
            validation_path = candidate_path;
            validation_ok = true;
            break;
        end
    end
end
if ~validation_ok
    % Fall back to the Fusion path for evidence reporting when neither
    % variant is present/nonempty (still fails).
    validation_path = fullfile(shared_temp, output_map.validation_fusion);
end
version_path = fullfile(shared_temp, output_map.version);
version_ok = false;
if exist(version_path, 'file') == 2
    info = dir(version_path);
    version_ok = ~isempty(info) && info(1).bytes > 0;
end
copy_back.validation_path = validation_path;
copy_back.version_path = version_path;
copy_back.validation_nonempty = validation_ok;
copy_back.version_nonempty = version_ok;
copy_back.validation_basename = '';
if validation_ok
    [~, v_base, v_ext] = fileparts(validation_path);
    copy_back.validation_basename = [v_base v_ext];
end
% Mandatory durable evidence: handoff + prepare/output verification are
% required for current success, never optional. Nonempty-files-only is
% insufficient without them.
handoff_path = fullfile(shared_temp, 'mlsc_current_handoff.mat');
prepare_evidence_path = fullfile(shared_temp, ...
    'mlsc_current_prepare_evidence.txt');
output_verification_path = fullfile(shared_temp, ...
    'mlsc_current_output_verification.txt');
handoff_ok = local_is_nonempty_file(handoff_path);
prepare_ok = local_is_nonempty_file(prepare_evidence_path);
verification_ok = local_is_nonempty_file(output_verification_path);
copy_back.handoff_path = handoff_path;
copy_back.prepare_evidence_path = prepare_evidence_path;
copy_back.output_verification_path = output_verification_path;
copy_back.handoff_nonempty = handoff_ok;
copy_back.prepare_evidence_nonempty = prepare_ok;
copy_back.output_verification_nonempty = verification_ok;
evidence_content_ok = false;
identity_ok = false;
att_map_content_ok = false;
if verification_ok
    evidence_content_ok = local_verification_evidence_ok( ...
        output_verification_path);
    identity_ok = local_copyback_identity_ok(shared_temp, ...
        output_verification_path);
end
if handoff_ok && prepare_ok && verification_ok
    att_map_content_ok = local_att_map_content_ok( ...
        copy_back.att_map_path, output_verification_path);
end
copy_back.evidence_content_ok = evidence_content_ok;
copy_back.copyback_identity_ok = identity_ok;
copy_back.att_map_content_ok = att_map_content_ok;
copy_back.verified = copy_back.contract_represented && ...
    copy_back.att_map_present && copy_back.att_map_nonempty && ...
    validation_ok && version_ok && handoff_ok && prepare_ok && ...
    verification_ok && evidence_content_ok && identity_ok && ...
    att_map_content_ok;
end

function ok = local_is_nonempty_file(path_name)
ok = false;
try
    if ~ischar(path_name) || size(path_name, 1) ~= 1 || ...
            isempty(path_name) || any(path_name == char(0))
        return;
    end
    if exist(path_name, 'file') ~= 2
        return;
    end
    info = dir(path_name);
    ok = ~isempty(info) && info(1).bytes > 0;
catch %#ok<CTCH>
    ok = false;
end
end

function map = local_current_output_filename_map()
%LOCAL_CURRENT_OUTPUT_FILENAME_MAP Explicit key->basename contract.
%   Owned by the current output contract. Keys are stable logical names;
%   values are exact basenames with no underscore/dot inference. Covers
%   att_map.nii, the Fusion validation TIFF and its explicit Composite
%   variant as declared, plus Pseudo_CT_AC_Version.txt. Any other declared
%   required output is handled as its explicitly declared basename (parsed
%   from the verification evidence, never inferred). R2010b only.
map = struct();
map.att_map = 'att_map.nii';
map.validation_fusion = 'Fusion_MR_Pseudo_CT_validation.tiff';
map.validation_composite = 'Composite_Fusion_MR_Pseudo_CT_validation.tiff';
map.version = 'Pseudo_CT_AC_Version.txt';
end

function ok = local_verification_evidence_ok(verification_path)
%LOCAL_VERIFICATION_EVIDENCE_OK Structured verification content contract.
%   Current-only: the local string/size substring fallback is DISABLED.
%   Requires the compute-written structured schema
%   (pseudo-CT.mlsc-current-output-verification/v1), the verified
%   normalized-input marker, explicit 'output <exact-basename>:' lines with
%   bytes and mandatory SHA-256 for every declared required output
%   (att_map.nii, version TXT, and the Fusion TIFF or its explicit
%   Composite variant as declared), plus the structured att_map semantic
%   block (basename/bytes/sha256/datatype/dim/affine/finite tied to the
%   exact file). Missing/malformed/missing-SHA lines fail. No log-string
%   fallback, no parity, no tolerances, no size-only fallback. R2010b only.
ok = false;
try
    content = local_read_text(verification_path);
    if isempty(content)
        return;
    end
    if isempty(strfind(content, 'pseudo-CT.mlsc-current-output-verification/v1'))
        return;
    end
    if isempty(strfind(content, 'normalized_input_verified'))
        return;
    end
    % NORMALIZED_INPUT SHA STRICT: the 'normalized_input:' fingerprint
    % line must carry exactly ^[0-9A-Fa-f]{64}$ after whitespace
    % normalization (same strict policy as required-output SHA). Missing,
    % empty, 63/65-hex, 64hex+suffix, prefix+64hex, trailing tokens, and
    % non-hex all fail. The verified marker never overrides a malformed
    % SHA; evidence must be internally consistent.
    if ~local_is_valid_normalized_input_sha(content)
        return;
    end
    entries = local_expected_output_entries(verification_path);
    if isempty(entries)
        return;
    end
    basenames = {};
    for ii = 1:length(entries)
        basenames{end + 1, 1} = entries{ii}.basename; %#ok<AGROW>
    end
    output_map = local_current_output_filename_map();
    has_att = local_contains_basename(basenames, output_map.att_map);
    has_ver = local_contains_basename(basenames, output_map.version);
    has_fusion = local_contains_basename(basenames, output_map.validation_fusion);
    has_composite = local_contains_basename(basenames, output_map.validation_composite);
    if ~has_att || ~has_ver || ~(has_fusion || has_composite)
        return;
    end
    % Every declared entry must carry bytes and mandatory SHA-256 (B5A).
    % Missing/empty/malformed/unverifiable SHA fails. No size-only fallback.
    for ii = 1:length(entries)
        if ~(entries{ii}.bytes > 0 && isfinite(entries{ii}.bytes))
            return;
        end
        if ~local_is_valid_sha256(entries{ii}.sha256)
            return;
        end
    end
    % Structured att_map semantic block is mandatory (no fallback).
    if ~local_has_att_map_semantic_block(content)
        return;
    end
    ok = true;
catch %#ok<CTCH>
    ok = false;
end
end

function ok = local_copyback_identity_ok(shared_temp, verification_path)
%LOCAL_COPYBACK_IDENTITY_OK Shared bytes equal verified node-local bytes.
%   Uses the EXPLICIT authoritative key->basename map: each verification
%   entry carries its exact declared basename (no fieldname inference), and
%   each shared file fullfile(shared_temp, <exact-basename>) must exist
%   with identical byte size and mandatory identical SHA-256 content hash
%   (independently recomputed, B5A). Missing/malformed SHA, hash mismatch,
%   and same-size different-content fail. Datenum is ignored because
%   copyback creates a new timestamp. R2010b only.
ok = false;
try
    entries = local_expected_output_entries(verification_path);
    if isempty(entries)
        return;
    end
    for ii = 1:length(entries)
        basename = entries{ii}.basename;
        if ~local_is_controlled_basename(basename)
            return;
        end
        shared_path = fullfile(shared_temp, basename);
        if exist(shared_path, 'file') ~= 2
            return;
        end
        info = dir(shared_path);
        if isempty(info) || info(1).bytes ~= entries{ii}.bytes
            return;
        end
        if ~local_is_valid_sha256(entries{ii}.sha256)
            return;
        end
        actual_hash = local_file_sha256_hex(shared_path);
        if isempty(actual_hash) || ~strcmp(lower(strtrim(actual_hash)), ...
                lower(strtrim(entries{ii}.sha256)))
            return;
        end
    end
    ok = true;
catch %#ok<CTCH>
    ok = false;
end
end

function entries = local_expected_output_entries(verification_path)
%LOCAL_EXPECTED_OUTPUT_ENTRIES Parse explicit output identity entries.
%   Each 'output <exact-basename>:' line is parsed with its exact declared
%   basename (no transformation) plus bytes and mandatory strict 64-hex
%   SHA-256 (B5A). Covers the declared required outputs including the
%   Composite variant as declared. Unknown/malformed lines are skipped;
%   empty means fail. R2010b.
entries = {};
try
    content = local_read_text(verification_path);
    if isempty(content)
        entries = {};
        return;
    end
    lines = local_split_lines(content);
    for ii = 1:length(lines)
        line = strtrim(lines{ii});
        prefix = 'output ';
        if ~strncmp(line, prefix, length(prefix))
            continue;
        end
        rest = strtrim(line(length(prefix) + 1:end));
        colon = strfind(rest, ':');
        if isempty(colon)
            continue;
        end
        basename = strtrim(rest(1:colon(1) - 1));
        if ~local_is_controlled_basename(basename)
            continue;
        end
        tail = rest(colon(1) + 1:end);
        bytes_pos = strfind(tail, 'bytes=');
        if isempty(bytes_pos)
            continue;
        end
        number_text = tail(bytes_pos(1) + 6:end);
        bytes_value = sscanf(number_text, '%d', 1);
        if isempty(bytes_value) || ~isfinite(bytes_value) || bytes_value <= 0
            continue;
        end
        sha_text = '';
        fingerprint_text = strtrim(tail);
        sha_pos = strfind(lower(tail), 'sha256=');
        if ~isempty(sha_pos)
            sha_tail = tail(sha_pos(1) + 7:end);
            % B5A: strict 64-hex SHA-256. The ENTIRE normalized value
            % after sha256= must match ^[0-9a-fA-F]{64}$ exactly.
            % Prefix extraction is forbidden: 63/65-hex, 64hex+suffix,
            % prefix+64hex, trailing tokens, non-hex, and missing/empty
            % are not retained; the entry then fails the mandatory check.
            sha_candidate = strtrim(sha_tail);
            if ~isempty(regexp(sha_candidate, '^[0-9a-fA-F]{64}$', 'once'))
                sha_text = lower(sha_candidate);
            end
        end
        entry = struct('basename', basename, 'bytes', double(bytes_value(1)), ...
            'sha256', sha_text, 'fingerprint', fingerprint_text);
        entries{end + 1, 1} = entry; %#ok<AGROW>
    end
catch %#ok<CTCH>
    entries = {};
end
end

function expected = local_expected_output_bytes(verification_path)
%LOCAL_EXPECTED_OUTPUT_BYTES Legacy wrapper (explicit basenames only).
%   Retained for compatibility; new code uses local_expected_output_entries
%   with exact basenames (no underscore/dot inference). Returns a struct
%   keyed by explicit safe keys for the declared basenames. R2010b only.
expected = struct();
try
    entries = local_expected_output_entries(verification_path);
    if isempty(entries)
        expected = struct();
        return;
    end
    output_map = local_current_output_filename_map();
    for ii = 1:length(entries)
        basename = entries{ii}.basename;
        if strcmp(basename, output_map.att_map)
            expected.att_map_nii = entries{ii}.bytes;
        elseif strcmp(basename, output_map.validation_fusion)
            expected.Fusion_MR_Pseudo_CT_validation_tiff = entries{ii}.bytes;
        elseif strcmp(basename, output_map.validation_composite)
            expected.Composite_Fusion_MR_Pseudo_CT_validation_tiff = entries{ii}.bytes;
        elseif strcmp(basename, output_map.version)
            expected.Pseudo_CT_AC_Version_txt = entries{ii}.bytes;
        else
            % Any other declared required output: explicit basename key
            % sanitized without inference collisions (fail closed on clash).
            safe = local_safe_key(basename);
            if isfield(expected, safe)
                expected = struct();
                return;
            end
            expected.(safe) = entries{ii}.bytes;
        end
    end
catch %#ok<CTCH>
    expected = struct();
end
end

function ok = local_att_map_content_ok(att_map_path, verification_path)
%LOCAL_ATT_MAP_CONTENT_OK Structured semantic verification for att_map.nii.
%   No string/size fallback. Requires the narrow structured contract tied
%   to the exact file: exact basename/path identity (att_map.nii),
%   mandatory independently recomputed SHA-256 (B5A/B5B) plus byte size
%   matching the compute-side record, NIfTI datatype 16 (float32), finite
%   dimensions, finite affine/geometry sufficient for wrong-geometry
%   detection (exact match, no tolerance), and finite voxel data. Rejects
%   mismatch/malformed/missing/wrong dims/dtype/affine/nonfinite/missing
%   SHA. No parity, no tolerances. R2010b only.
ok = false;
try
    [~, base_name, ext_name] = fileparts(att_map_path);
    if ~strcmp([base_name ext_name], 'att_map.nii')
        return;
    end
    if exist(att_map_path, 'file') ~= 2
        return;
    end
    content = local_read_text(verification_path);
    if isempty(content)
        return;
    end
    semantic = local_parse_att_map_semantic(content);
    if isempty(semantic)
        return;
    end
    if ~strcmp(strtrim(semantic.basename), 'att_map.nii')
        return;
    end
    info = dir(att_map_path);
    if isempty(info) || info(1).bytes <= 0
        return;
    end
    if info(1).bytes ~= semantic.bytes
        return;
    end
    % B5A/B5B: att_map SHA-256 MANDATORY. Missing/malformed/unverifiable
    % fails closed. No size-only fallback.
    if ~local_is_valid_sha256(semantic.sha256)
        return;
    end
    actual_hash = local_file_sha256_hex(att_map_path);
    if isempty(actual_hash) || ~strcmp(lower(strtrim(actual_hash)), ...
            lower(strtrim(semantic.sha256)))
        return;
    end
    % Independent NIfTI header/geometry/data checks (SPM required for
    % current; no fallback when SPM is unavailable or file is malformed).
    if exist('spm_vol', 'file') ~= 2
        return;
    end
    try
        V = spm_vol(att_map_path);
    catch %#ok<CTCH>
        return;
    end
    if ~isstruct(V) || isempty(V)
        return;
    end
    V = V(1);
    if ~isfield(V, 'dim') || ~isfield(V, 'mat') || ~isfield(V, 'dt')
        return;
    end
    if ~isnumeric(V.dim) || numel(V.dim) < 3 || any(~isfinite(V.dim(:))) || ...
            any(V.dim(:) <= 0)
        return;
    end
    if ~isnumeric(V.mat) || numel(V.mat) ~= 16 || any(~isfinite(V.mat(:))) || ...
            isequal(V.mat, zeros(size(V.mat)))
        return;
    end
    if ~isnumeric(V.dt) || isempty(V.dt) || V.dt(1) ~= 16
        return;
    end
    % Exact structured match (no tolerance): datatype, dimensions, affine.
    if V.dt(1) ~= semantic.datatype
        return;
    end
    if ~local_dims_equal(V.dim, semantic.dim)
        return;
    end
    if ~local_affine_equal(V.mat, semantic.affine)
        return;
    end
    try
        data = spm_read_vols(V);
    catch %#ok<CTCH>
        return;
    end
    if ~isnumeric(data) && ~islogical(data)
        return;
    end
    if isempty(data) || ~all(isfinite(data(:)))
        return;
    end
    if ~isequal(semantic.finite, 1)
        return;
    end
    ok = true;
catch %#ok<CTCH>
    ok = false;
end
end

function semantic = local_parse_att_map_semantic(content)
%LOCAL_PARSE_ATT_MAP_SEMANTIC Parse the structured att_map block.
semantic = [];
try
    if isempty(content) || ~ischar(content)
        return;
    end
    basename = local_field_value(content, 'att_map_basename:');
    bytes_text = local_field_value(content, 'att_map_bytes:');
    sha_text = local_field_value(content, 'att_map_sha256:');
    dtype_text = local_field_value(content, 'att_map_datatype:');
    dim_text = local_field_value(content, 'att_map_dim:');
    affine_text = local_field_value(content, 'att_map_affine:');
    finite_text = local_field_value(content, 'att_map_finite:');
    if isempty(basename) || isempty(bytes_text) || isempty(dtype_text) || ...
            isempty(dim_text) || isempty(affine_text) || isempty(finite_text)
        return;
    end
    % B5A/B5B: att_map SHA-256 structural evidence mandatory.
    if ~local_is_valid_sha256(sha_text)
        return;
    end
    if ~strcmp(strtrim(basename), 'att_map.nii')
        return;
    end
    bytes_value = sscanf(strtrim(bytes_text), '%d', 1);
    dtype_value = sscanf(strtrim(dtype_text), '%d', 1);
    finite_value = sscanf(strtrim(finite_text), '%d', 1);
    if isempty(bytes_value) || ~isfinite(bytes_value) || bytes_value <= 0
        return;
    end
    if isempty(dtype_value) || dtype_value ~= 16
        return;
    end
    if isempty(finite_value) || finite_value ~= 1
        return;
    end
    dim_value = sscanf(strtrim(dim_text), '%f', inf);
    if isempty(dim_value) || any(~isfinite(dim_value)) || any(dim_value <= 0)
        return;
    end
    affine_value = sscanf(strtrim(affine_text), '%f', inf);
    if isempty(affine_value) || numel(affine_value) ~= 16 || ...
            any(~isfinite(affine_value))
        return;
    end
    affine_value = reshape(affine_value, 4, 4);
    semantic = struct('basename', 'att_map.nii', ...
        'bytes', double(bytes_value(1)), ...
        'sha256', lower(strtrim(sha_text)), ...
        'datatype', double(dtype_value(1)), ...
        'dim', dim_value(:)', ...
        'affine', affine_value, ...
        'finite', 1);
catch %#ok<CTCH>
    semantic = [];
end
end

function present = local_has_att_map_semantic_block(content)
present = false;
try
    semantic = local_parse_att_map_semantic(content);
    present = ~isempty(semantic);
catch %#ok<CTCH>
    present = false;
end
end

function value = local_field_value(content, marker)
value = '';
try
    pos = strfind(content, marker);
    if isempty(pos)
        return;
    end
    tail = content(pos(1) + length(marker):end);
    newline = strfind(tail, char(10));
    if ~isempty(newline)
        tail = tail(1:newline(1) - 1);
    end
    carriage = strfind(tail, char(13));
    if ~isempty(carriage)
        tail = tail(1:carriage(1) - 1);
    end
    value = strtrim(tail);
catch %#ok<CTCH>
    value = '';
end
end

function flag = local_contains_basename(list, target)
flag = false;
try
    for ii = 1:length(list)
        if ischar(list{ii}) && strcmp(strtrim(list{ii}), target)
            flag = true;
            return;
        end
    end
catch %#ok<CTCH>
    flag = false;
end
end

function flag = local_is_controlled_basename(name_text)
flag = false;
try
    if ~ischar(name_text) || size(name_text, 1) ~= 1 || ...
            isempty(strtrim(name_text)) || any(name_text == char(0))
        return;
    end
    trimmed = strtrim(name_text);
    if ~isempty(strfind(trimmed, '..')) || ~isempty(strfind(trimmed, '/')) || ...
            ~isempty(strfind(trimmed, char(92)))
        return;
    end
    flag = true;
catch %#ok<CTCH>
    flag = false;
end
end

function flag = local_dims_equal(actual_dim, expected_dim)
flag = false;
try
    a = actual_dim(:)';
    e = expected_dim(:)';
    if length(a) < 3 || length(e) < 3
        return;
    end
    % Compare the first three spatial dimensions exactly (no tolerance).
    % Extra trailing singleton dimensions are ignored only when both sides
    % agree they are singletons; any spatial mismatch fails.
    if length(a) ~= length(e)
        % Allow 3-vs-4 length only when the extra element is 1 on both.
        maxlen = max(length(a), length(e));
        a(end + 1:maxlen) = 1;
        e(end + 1:maxlen) = 1;
    end
    flag = isequal(a, e);
catch %#ok<CTCH>
    flag = false;
end
end

function flag = local_affine_equal(actual_mat, expected_mat)
flag = false;
try
    if ~isequal(size(actual_mat), size(expected_mat))
        return;
    end
    % Exact geometry identity sufficient for wrong-geometry detection.
    % No tolerance: any affine element mismatch fails.
    flag = isequal(actual_mat, expected_mat);
catch %#ok<CTCH>
    flag = false;
end
end

function text = local_read_text(path_name)
text = '';
try
    fid = fopen(path_name, 'r');
    if fid == -1
        return;
    end
    raw = fread(fid, inf, '*char')';
    fclose(fid);
    if ischar(raw)
        text = raw;
    end
catch %#ok<CTCH>
    try
        fclose(fid);
    catch %#ok<CTCH>
    end
    text = '';
end
end

function lines = local_split_lines(content)
lines = {};
try
    normalized = strrep(content, char(13), char(10));
    parts = regexp(normalized, char(10), 'split');
    for ii = 1:length(parts)
        lines{end + 1, 1} = parts{ii}; %#ok<AGROW>
    end
catch %#ok<CTCH>
    lines = {};
end
end

function safe = local_safe_key(basename)
safe = '';
try
    safe = regexprep(basename, '[^A-Za-z0-9]', '_');
    if isempty(safe) || ~isletter(safe(1))
        safe = ['k_' safe];
    end
catch %#ok<CTCH>
    safe = 'k_unknown';
end
end

function hex = local_file_sha256_hex(path_name)
%LOCAL_FILE_SHA256_HEX SHA-256 content hash, fail-closed (B4B/B5A).
%   Java SHA-256 when available, else the approved deterministic sha256sum
%   mechanism. No FNV/filesize/mtime fallback: when hashing is unavailable
%   the result is '' and callers fail closed. R2010b only.
hex = '';
try
    fid = fopen(path_name, 'r');
    if fid == -1
        return;
    end
    raw = fread(fid, inf, '*uint8')';
    fclose(fid);
    if isempty(raw)
        return;
    end
    try
        digest = java.security.MessageDigest.getInstance('SHA-256');
        digest.update(raw);
        bytes = typecast(digest.digest(), 'uint8');
        candidate = lower(reshape(dec2hex(bytes, 2)', 1, []));
        if local_is_valid_sha256(candidate)
            hex = candidate;
            return;
        end
    catch %#ok<CTCH>
    end
    try
        quoted = local_shell_quote(path_name);
        [status, out] = system(['sha256sum ' quoted ' 2>/dev/null']);
        if status == 0 && ischar(out) && ~isempty(strtrim(out))
            tok = regexp(strtrim(out), '^([0-9a-fA-F]{64})(?![0-9a-fA-F])', ...
                'tokens', 'once');
            if ~isempty(tok)
                candidate = lower(strtrim(tok{1}));
                if local_is_valid_sha256(candidate)
                    hex = candidate;
                    return;
                end
            end
        end
    catch %#ok<CTCH>
    end
    hex = '';
catch %#ok<CTCH>
    try
        fclose(fid);
    catch %#ok<CTCH>
    end
    hex = '';
end
end

function flag = local_is_valid_sha256(value)
%LOCAL_IS_VALID_SHA256 Strict 64-hex SHA-256 shape (B5A). R2010b only.
flag = false;
try
    if ~ischar(value) || size(value, 1) ~= 1
        return;
    end
    trimmed = strtrim(value);
    if length(trimmed) ~= 64
        return;
    end
    if isempty(regexp(trimmed, '^[0-9a-fA-F]{64}$', 'once'))
        return;
    end
    flag = true;
catch %#ok<CTCH>
    flag = false;
end
end

function flag = local_is_valid_normalized_input_sha(content)
%LOCAL_IS_VALID_NORMALIZED_INPUT_SHA Strict normalized-input SHA-256.
%   Parses the 'normalized_input:' fingerprint line (exact prefix, never
%   the 'normalized_input_verified:' marker) and requires the ENTIRE
%   normalized value after sha256= to match ^[0-9a-fA-F]{64}$ exactly
%   (same strict policy as required-output SHA). Prefix extraction is
%   forbidden: missing line, missing sha256=, empty, 63/65-hex,
%   64hex+suffix, prefix+64hex, trailing tokens, and non-hex all fail.
%   R2010b only.
flag = false;
try
    if ~ischar(content) || isempty(content)
        return;
    end
    normalized = strrep(content, char(13), char(10));
    parts = regexp(normalized, char(10), 'split');
    found = false;
    for ii = 1:length(parts)
        line = strtrim(parts{ii});
        if strncmp(line, 'normalized_input:', length('normalized_input:'))
            tail = line(length('normalized_input:') + 1:end);
            sha_pos = strfind(lower(tail), 'sha256=');
            if isempty(sha_pos)
                return;
            end
            sha_tail = tail(sha_pos(1) + 7:end);
            sha_candidate = strtrim(sha_tail);
            if isempty(regexp(sha_candidate, '^[0-9a-fA-F]{64}$', 'once'))
                return;
            end
            if ~local_is_valid_sha256(sha_candidate)
                return;
            end
            found = true;
        end
    end
    if ~found
        return;
    end
    flag = true;
catch %#ok<CTCH>
    flag = false;
end
end

function quoted = local_shell_quote(value)
%LOCAL_SHELL_QUOTE POSIX single-quote for the sha256sum fallback.
quoted = '''''';
try
    if ~ischar(value) || size(value, 1) ~= 1 || isempty(value)
        quoted = '''''';
        return;
    end
    single_quote = char(39);
    double_quote = char(34);
    quoted = single_quote;
    for ii = 1:length(value)
        if value(ii) == char(0)
            error('pseudo_CT:MLSCPreflight', 'NUL in path.');
        elseif value(ii) == single_quote
            quoted = [quoted single_quote double_quote single_quote ...
                double_quote single_quote]; %#ok<AGROW>
        else
            quoted = [quoted value(ii)]; %#ok<AGROW>
        end
    end
    quoted = [quoted single_quote];
catch %#ok<CTCH>
    quoted = '''''';
end
end

function result = local_apply_deadline(result, state, transport, detail)
result.terminal = true;
result.state = state;
result.scheduler_state = state;
result.workflow_state = state;
result.failure_detail = detail;
result.failure = struct('present', true, 'detail', detail);
result.timestamps.finished_at = local_timestamp(transport);
end

function result = local_apply_interrupted(result, transport)
result = local_request_cancel(result, transport);
result.interrupted = true;
result.terminal = true;
result.success = false;
result.eligible_for_finalization = false;
result.state = 'interrupted';
result.scheduler_state = 'interrupted';
result.workflow_state = 'interrupted';
result.state_history{end + 1} = 'interrupted';
result.interruption_detail = ...
    'MLSC polling was interrupted after submission.';
if ~result.cancel_succeeded
    result.interruption_detail = [result.interruption_detail ...
        ' Cancellation could not be confirmed.'];
end
result.failure_detail = result.interruption_detail;
result.failure = struct('present', true, 'detail', result.failure_detail);
result.timestamps.finished_at = local_timestamp(transport);
end

function result = local_request_cancel(result, transport)
if result.cancel_requested
    return;
end
result.cancel_requested = true;
result.state_history{end + 1} = 'cancel_requested';
try
    feval(transport.cancel_job, result.job_id);
    result.cancel_succeeded = true;
 catch %#ok<CTCH>
    result.cancel_succeeded = false;
    result.failure_detail = ...
        'MLSC polling timed out and cancellation could not be confirmed.';
    result.failure = struct('present', true, 'detail', result.failure_detail);
end
end

function [result, record, terminal, tracker, progress_cursor, ...
        progress_milestones] = local_wait_for_accounting( ...
        result, runtime, transport, tracker, progress_path, ...
        progress_cursor, progress_milestones)
record = local_empty_accounting_record(result.job_id);
terminal = false;
if nargin < 4 || ~isstruct(tracker) || numel(tracker) ~= 1
    tracker = local_output_init(runtime, transport);
end
if nargin < 5
    progress_path = '';
end
if nargin < 6 || ~isstruct(progress_cursor) || numel(progress_cursor) ~= 1
    try
        progress_cursor = mlsc_progress('init');
    catch %#ok<CTCH>
        progress_cursor = struct('offset', 0, 'pending', '');
        progress_cursor.emitted = cell(0, 1);
    end
end
if nargin < 7 || ~iscell(progress_milestones)
    progress_milestones = cell(0, 1);
end
job_id = result.job_id;
for ii = 1:runtime.max_accounting_polls
    try
        record = mlsc_parse_sacct_terminal( ...
            feval(transport.query_sacct, result.job_id), result.job_id);
    catch ME
        result.sacct_query_failures = result.sacct_query_failures + 1;
        rethrow(ME);
    end
    if record.found
        result.accounting_record_found = true;
        result = local_append_state(result, record.state, transport);
        % Same authority rule as the main loop: only terminal accounting
        % drives transition output; non-terminal records stay in history.
        if record.terminal
            tracker = local_output_note(tracker, runtime, job_id, ...
                record.state, transport);
            terminal = true;
            try
                [progress_cursor, progress_milestones] = ...
                    local_progress_poll(progress_path, progress_cursor, ...
                    progress_milestones, runtime, job_id);
                result.progress.milestones = progress_milestones;
                try
                    result.progress.cursor_offset = progress_cursor.offset;
                catch %#ok<CTCH>
                end
                result = local_progress_record_trailing(result, ...
                    progress_cursor);
            catch %#ok<CTCH>
            end
            return;
        end
    end
    tracker = local_output_maybe_heartbeat(tracker, runtime, job_id, ...
        result, transport);
    try
        [progress_cursor, progress_milestones] = local_progress_poll( ...
            progress_path, progress_cursor, progress_milestones, ...
            runtime, job_id);
        result.progress.milestones = progress_milestones;
        try
            result.progress.cursor_offset = progress_cursor.offset;
        catch %#ok<CTCH>
        end
        result = local_progress_record_trailing(result, progress_cursor);
    catch %#ok<CTCH>
    end
    if ii < runtime.max_accounting_polls
        local_sleep(runtime.poll_interval_seconds, transport);
    end
end
end

function result = local_finish(result, evidence, runtime, transport)
% Capture the job-ID-specific sidecar before any local cleanup can run.
result.executor_provenance = local_read_executor_provenance( ...
    result.shared_subject_temp, result.job_id);
result.log_paths = local_archive_logs(result.log_paths, result.job_id, runtime);
result = local_archive_progress(result, runtime);
result.cleanup = local_cleanup(result.cleanup, runtime, transport, ...
    result.script_materialized);
if result.cleanup.failed
    result.success = false;
    result.eligible_for_finalization = false;
    result.workflow_state = 'failed';
    result.failure_detail = ...
        'MLSC lifecycle cleanup failed after the scheduler terminal result.';
    result.failure = struct('present', true, 'detail', result.failure_detail);
end
result.timestamps.cleaned_at = result.cleanup.cleaned_at;
evidence = mlsc_evidence('terminal', evidence, local_evidence_values(result));
evidence = mlsc_evidence('cleanup', evidence, local_evidence_values(result));
if ~isempty(runtime.evidence_dir)
    try
        mlsc_evidence('write', runtime.evidence_dir, evidence);
        result.evidence_saved = true;
        result.evidence_path = fullfile(runtime.evidence_dir, ...
            'mlsc_evidence.mat');
    catch %#ok<CTCH>
        result.evidence_save_failed = true;
        result.success = false;
        result.eligible_for_finalization = false;
        result.workflow_state = 'failed';
        result.failure_detail = ...
            'MLSC lifecycle evidence could not be saved.';
        result.failure = struct('present', true, 'detail', result.failure_detail);
    end
end
result.evidence = evidence;
end

function provenance = local_empty_executor_provenance()
provenance = struct('sidecar_path', '', 'sidecar_present', false, ...
    'job_id', 'Not confirmed', 'hostname', 'Not confirmed', ...
    'cpu_model', 'Not confirmed', 'architecture', 'Not confirmed', ...
    'shell_exit_code', 'Not confirmed', ...
    'shell_terminal_outcome', 'Not confirmed', ...
    'selected_mcr_root', 'Not confirmed', ...
    'runtime_library_dir', 'Not confirmed', ...
    'runtime_library_present', 'Not confirmed', ...
    'runtime_release', 'Not confirmed', ...
    'build_manifest_compiler_release', 'Not confirmed', ...
    'build_manifest_mcr_version', 'Not confirmed', ...
    'build_manifest_generation', 'Not confirmed', ...
    'build_manifest_arch', 'Not confirmed', ...
    'build_manifest_mcr_root', 'Not confirmed', ...
    'build_manifest_source_commit', 'Not confirmed', ...
    'build_manifest_runner_checksum', 'Not confirmed');
end

function provenance = local_read_executor_provenance(shared_temp, job_id)
provenance = local_empty_executor_provenance();
try
    if ~ischar(shared_temp) || size(shared_temp, 1) ~= 1 || ...
            isempty(shared_temp) || any(shared_temp == char(0)) || ...
            ~isnumeric(job_id) || ~isscalar(job_id) || ...
            ~isfinite(job_id) || job_id <= 0 || job_id ~= floor(job_id)
        return;
    end
    expected_job_id = sprintf('%.0f', job_id);
    provenance.sidecar_path = fullfile(shared_temp, ...
        ['mlsc_executor_provenance_' expected_job_id '.txt']);
    if exist(provenance.sidecar_path, 'file') ~= 2
        return;
    end
    provenance.sidecar_present = true;
    fid = fopen(provenance.sidecar_path, 'r');
    if fid == -1
        return;
    end
    close_file = onCleanup(@() fclose(fid));
    keys = {'schema'; 'job_id'; 'hostname'; 'cpu_model'; 'architecture'; ...
        'shell_exit_code'; 'shell_terminal_outcome'; 'selected_mcr_root'; ...
        'runtime_library_dir'; 'runtime_library_present'; 'runtime_release'; ...
        'build_manifest_compiler_release'; 'build_manifest_mcr_version'; ...
        'build_manifest_generation'; 'build_manifest_arch'; ...
        'build_manifest_mcr_root'; 'build_manifest_source_commit'; ...
        'build_manifest_runner_checksum'};
    values = repmat({''}, length(keys), 1);
    seen = false(length(keys), 1);
    duplicate = false(length(keys), 1);
    while true
        line = fgetl(fid);
        if ~ischar(line)
            break;
        end
        equals = find(line == '=', 1);
        if isempty(equals)
            continue;
        end
        key = line(1:equals - 1);
        position = find(strcmp(keys, key), 1);
        if isempty(position)
            continue;
        end
        if seen(position)
            duplicate(position) = true;
            values{position} = '';
        else
            seen(position) = true;
            values{position} = strtrim(line(equals + 1:end));
        end
    end
    schema_pos = find(strcmp(keys, 'schema'), 1);
    job_pos = find(strcmp(keys, 'job_id'), 1);
    if duplicate(schema_pos) || duplicate(job_pos) || ...
            ~seen(schema_pos) || ~seen(job_pos) || ...
            ~strcmp(values{schema_pos}, ...
            'pseudo-CT.mlsc-executor-provenance/v1') || ...
            ~strcmp(values{job_pos}, expected_job_id)
        return;
    end
    provenance.job_id = expected_job_id;
    for ii = 1:length(keys)
        if ~seen(ii) || duplicate(ii) || ...
                ~local_executor_provenance_value(values{ii})
            continue;
        end
        value = values{ii};
        switch keys{ii}
            case 'hostname'
                provenance.hostname = value;
            case 'cpu_model'
                provenance.cpu_model = value;
            case 'architecture'
                provenance.architecture = value;
            case 'shell_exit_code'
                if ~isempty(regexp(value, '^[0-9]+$', 'once'))
                    provenance.shell_exit_code = value;
                end
            case 'shell_terminal_outcome'
                if strcmp(value, 'completed') || strcmp(value, 'failed')
                    provenance.shell_terminal_outcome = value;
                end
            case 'selected_mcr_root'
                provenance.selected_mcr_root = value;
            case 'runtime_library_dir'
                provenance.runtime_library_dir = value;
            case 'runtime_library_present'
                if strcmp(value, 'yes') || strcmp(value, 'no')
                    provenance.runtime_library_present = value;
                end
            case 'runtime_release'
                provenance.runtime_release = value;
            case 'build_manifest_compiler_release'
                if ~isempty(regexp(value, '^R[0-9]{4}[ab]$', 'once'))
                    provenance.build_manifest_compiler_release = value;
                end
            case {'build_manifest_mcr_version', 'build_manifest_generation'}
                if ~isempty(regexp(value, '^[0-9]+[.][0-9]+$', 'once'))
                    provenance.(keys{ii}) = value;
                end
            case 'build_manifest_arch'
                provenance.build_manifest_arch = value;
            case 'build_manifest_mcr_root'
                provenance.build_manifest_mcr_root = value;
            case 'build_manifest_source_commit'
                if ~isempty(regexp(value, '^[0-9a-fA-F]{40}$', 'once'))
                    provenance.build_manifest_source_commit = lower(value);
                end
            case 'build_manifest_runner_checksum'
                if ~isempty(regexp(value, '^[0-9a-fA-F]{64}$', 'once'))
                    provenance.build_manifest_runner_checksum = lower(value);
                end
        end
    end
    if ~strcmp(provenance.shell_exit_code, 'Not confirmed')
        if strcmp(provenance.shell_exit_code, '0') && ...
                strcmp(provenance.shell_terminal_outcome, 'completed')
            provenance.shell_terminal_outcome = 'Completed (exit status 0)';
        elseif ~strcmp(provenance.shell_exit_code, '0') && ...
                strcmp(provenance.shell_terminal_outcome, 'failed')
            provenance.shell_terminal_outcome = ...
                ['Failed (exit status ' provenance.shell_exit_code ')'];
        else
            provenance.shell_exit_code = 'Not confirmed';
            provenance.shell_terminal_outcome = 'Not confirmed';
        end
    else
        provenance.shell_terminal_outcome = 'Not confirmed';
    end
catch %#ok<CTCH>
    provenance = local_empty_executor_provenance();
end
end

function valid = local_executor_provenance_value(value)
valid = ischar(value) && size(value, 1) == 1 && ...
    ~isempty(strtrim(value)) && ~any(value == char(0)) && ...
    isempty(regexp(value, '[\r\n]', 'once'));
end

function cleanup = local_cleanup(cleanup, runtime, transport, script_materialized)
cleanup.attempted = true;
cleanup.failed = false;
cleanup.cleaned_at = local_timestamp(transport);
if ~script_materialized
    cleanup.script_preserved = true;
    return;
end
if ~runtime.cleanup_script || ~isfield(runtime, 'script_path') || ...
        isempty(runtime.script_path)
    cleanup.script_preserved = true;
    return;
end
if exist(runtime.script_path, 'file') ~= 2
    cleanup.script_removed = true;
    return;
end
try
    delete(runtime.script_path);
    cleanup.script_removed = exist(runtime.script_path, 'file') ~= 2;
catch %#ok<CTCH>
    cleanup.script_removed = false;
    cleanup.failed = true;
    cleanup.failure_detail = 'Generated MLSC script could not be cleaned up.';
end
end

function values = local_evidence_values(result)
values = struct();
values.profile = result.profile;
values.subject_count = 1;
values.subject_id = result.subject_id;
values.runtime_account = result.runtime_account;
values.job_id = result.job_id;
values.executor_provenance = result.executor_provenance;
values.submission_attempted = result.submission_attempted;
values.submission_response_lost = result.submission_response_lost;
values.submission_response_parseable = result.submission_response_parseable;
values.submission_reconciled = result.submission_reconciled;
values.submission_reconciliation_attempts = ...
    result.submission_reconciliation_attempts;
values.submission_outcome = result.submission_outcome;
values.submission_callback_failed = result.submission_callback_failed;
values.submission_receipt_path = result.submission_receipt_path;
values.submission_correlation_id = result.submission_correlation_id;
values.job_name = result.job_name;
values.squeue_reconciliation_query_contract = ...
    result.squeue_reconciliation_query_contract;
values.sacct_reconciliation_query_contract = ...
    result.sacct_reconciliation_query_contract;
values.state = result.state;
values.scheduler_state = result.scheduler_state;
values.exit_code = result.exit_code;
values.exit_signal = result.exit_signal;
values.exit_code_text = result.exit_code_text;
values.scheduler_start_time = result.scheduler_start_time;
values.scheduler_end_time = result.scheduler_end_time;
values.scheduler_elapsed = result.scheduler_elapsed;
values.accounting_source = result.accounting_source;
values.squeue_query_contract = result.squeue_query_contract;
values.sacct_query_contract = result.sacct_query_contract;
values.accounting_record_found = result.accounting_record_found;
values.primary_allocation = result.primary_allocation;
values.cancel_requested = result.cancel_requested;
values.cancel_succeeded = result.cancel_succeeded;
values.state_history = result.state_history;
values.timestamps = result.timestamps;
values.created_at = result.timestamps.created_at;
values.submitted_at = result.timestamps.submitted_at;
values.started_at = result.timestamps.started_at;
values.finished_at = result.timestamps.finished_at;
values.cleaned_at = result.timestamps.cleaned_at;
values.shared_subject_temp = result.shared_subject_temp;
values.evidence_dir = result.evidence_dir;
values.evidence_path = result.evidence_path;
values.log_paths = result.log_paths;
values.slurm_stdout_log_path = result.log_paths.stdout;
values.slurm_stderr_log_path = result.log_paths.stderr;
values.contract = result.contract;
values.node_local_root = '$TMPDIR';
values.shared_input_staging = ...
    'cp shared subject temp to node-local TMPDIR';
values.node_local_processing = ...
    'heavy processing executes in node-local TMPDIR';
values.shared_output_staging = ...
    'cp node-local TMPDIR outputs to shared subject temp';
values.scp_used = false;
values.network_payload_staging = false;
values.copy_back = result.copy_back;
values.progress = result.progress;
values.progress_milestones = result.progress.milestones;
values.progress_source_path = result.progress.source_path;
values.progress_archive_path = result.progress.archive_path;
values.progress_cursor_offset = result.progress.cursor_offset;
values.progress_incomplete_trailing = local_progress_evidence_flag(result);
values.progress_pending_bytes = local_progress_evidence_bytes(result);
values.progress_archive_attempted = result.progress.archive_attempted;
values.progress_archive_succeeded = result.progress.archive_succeeded;
values.progress_archive_detail = result.progress.archive_detail;
values.cleanup = result.cleanup;
values.failure = result.failure;
values.failure_detail = result.failure_detail;
values.interrupted = result.interrupted;
values.interruption_detail = result.interruption_detail;
values.terminal = result.terminal;
values.workflow_success = result.success;
values.eligible_for_finalization = result.eligible_for_finalization;
end

function paths = local_empty_log_paths(shared_temp, archive_dir)
paths = struct('stdout', '', 'stderr', '', 'stdout_resolved', '', ...
    'stderr_resolved', '', 'stdout_archive', '', 'stderr_archive', '', ...
    'archive_attempted', false, 'archive_succeeded', false, ...
    'archive_detail', '');
if isempty(shared_temp)
    return;
end
paths.stdout = fullfile(shared_temp, 'pseudoCT_mlsc_%j.out');
paths.stderr = fullfile(shared_temp, 'pseudoCT_mlsc_%j.err');
if ~isempty(archive_dir)
    paths.stdout_archive = fullfile(archive_dir, 'pseudoCT_mlsc_%j.out');
    paths.stderr_archive = fullfile(archive_dir, 'pseudoCT_mlsc_%j.err');
end
end

function paths = local_apply_log_paths(paths, artifact_paths, archive_dir)
if isfield(artifact_paths, 'stdout') && ischar(artifact_paths.stdout)
    paths.stdout = artifact_paths.stdout;
end
if isfield(artifact_paths, 'stderr') && ischar(artifact_paths.stderr)
    paths.stderr = artifact_paths.stderr;
end
if ~isempty(archive_dir)
    paths.stdout_archive = local_archive_template(paths.stdout, archive_dir);
    paths.stderr_archive = local_archive_template(paths.stderr, archive_dir);
end
end

function archive_path = local_archive_template(source_path, archive_dir)
archive_path = '';
if isempty(source_path) || isempty(archive_dir)
    return;
end
[~, name, extension] = fileparts(source_path);
archive_path = fullfile(archive_dir, [name extension]);
end

function paths = local_archive_logs(paths, job_id, runtime)
if ~isstruct(paths) || ~isnumeric(job_id) || ~isscalar(job_id) || ...
        ~isfinite(job_id) || job_id < 1 || isempty(runtime.log_archive_dir)
    return;
end
paths.archive_attempted = true;
paths.stdout_resolved = local_expand_job_id(paths.stdout, job_id);
paths.stderr_resolved = local_expand_job_id(paths.stderr, job_id);
paths.stdout_archive = local_expand_job_id(paths.stdout_archive, job_id);
paths.stderr_archive = local_expand_job_id(paths.stderr_archive, job_id);

[stdout_ok, stdout_detail] = local_archive_log(paths.stdout_resolved, ...
    paths.stdout_archive);
[stderr_ok, stderr_detail] = local_archive_log(paths.stderr_resolved, ...
    paths.stderr_archive);
paths.archive_succeeded = stdout_ok && stderr_ok;
paths.archive_detail = local_join_details(stdout_detail, stderr_detail);
end

function path_name = local_expand_job_id(path_name, job_id)
if isempty(path_name)
    return;
end
path_name = strrep(path_name, '%j', num2str(job_id, '%.0f'));
end

function [success, detail] = local_archive_log(source_path, destination_path)
success = false;
detail = '';
if isempty(source_path) || isempty(destination_path)
    detail = 'Slurm log archive path was not configured.';
    return;
end
if exist(source_path, 'file') ~= 2
    detail = ['Slurm log was not found: ' source_path];
    return;
end
if strcmp(source_path, destination_path)
    success = true;
    return;
end
destination_parent = fileparts(destination_path);
if isempty(destination_parent) || exist(destination_parent, 'dir') ~= 7
    detail = ['Slurm log archive directory was not found: ' destination_parent];
    return;
end
stage_path = tempname(destination_parent);
[copy_success, copy_message] = copyfile(source_path, stage_path);
if ~copy_success
    detail = ['Slurm log archive copy failed: ' copy_message];
    return;
end
[move_success, move_message] = movefile(stage_path, destination_path, 'f');
if ~move_success
    if exist(stage_path, 'file') == 2
        delete(stage_path);
    end
    detail = ['Slurm log archive promotion failed: ' move_message];
    return;
end
success = exist(destination_path, 'file') == 2;
if ~success
    detail = ['Slurm log archive was not created: ' destination_path];
end
end

function detail = local_join_details(first, second)
if isempty(first)
    detail = second;
elseif isempty(second)
    detail = first;
else
    detail = [first ' | ' second];
end
end

function local_sleep(seconds, transport)
if isfield(transport, 'sleep') && isa(transport.sleep, 'function_handle')
    feval(transport.sleep, seconds);
else
    pause(seconds);
end
end

function value = local_clock(transport)
value = now;
if isfield(transport, 'clock') && isa(transport.clock, 'function_handle')
    try
        candidate = feval(transport.clock);
        if isnumeric(candidate) && isscalar(candidate) && isfinite(candidate)
            value = candidate;
        end
    catch %#ok<CTCH>
    end
end
end

function stamp = local_timestamp(transport)
clock_value = local_clock(transport);
stamp = [datestr(clock_value, 'yyyy-mm-dd') 'T' ...
    datestr(clock_value, 'HH:MM:SS')];
end

function elapsed = local_elapsed_seconds(start_value, current_value)
elapsed = max(0, (current_value - start_value) * 86400);
end

function context = local_output_context(runtime, job_id)
%LOCAL_OUTPUT_CONTEXT Build a non-secret pseudo_CT_output context.
%   Only log routing and display tags are propagated; the numeric job ID is
%   added as the job tag.  Credentials, transport closures, host keys,
%   paths, accounts, and any other runtime material are never copied.
context = struct();
try
    if isstruct(runtime) && isfield(runtime, 'output_context') && ...
            isstruct(runtime.output_context) && ...
            numel(runtime.output_context) == 1
        source = runtime.output_context;
        if isfield(source, 'log_file')
            try
                value = source.log_file;
                if (ischar(value) && ~isempty(value)) || ...
                        (iscell(value) && ~isempty(value))
                    context.log_file = value;
                end
            catch %#ok<CTCH>
            end
        end
        if isfield(source, 'log_files')
            try
                value = source.log_files;
                if (ischar(value) && ~isempty(value)) || ...
                        (iscell(value) && ~isempty(value))
                    context.log_files = value;
                end
            catch %#ok<CTCH>
            end
        end
        if isfield(source, 'scope')
            try
                value = source.scope;
                if ischar(value) && ~isempty(value)
                    context.scope = value;
                end
            catch %#ok<CTCH>
            end
        end
        if isfield(source, 'subject_index')
            try
                value = source.subject_index;
                if isnumeric(value) && isscalar(value) && isfinite(value)
                    context.subject_index = value;
                end
            catch %#ok<CTCH>
            end
        end
        if isfield(source, 'subject_count')
            try
                value = source.subject_count;
                if isnumeric(value) && isscalar(value) && isfinite(value)
                    context.subject_count = value;
                end
            catch %#ok<CTCH>
            end
        end
        if isfield(source, 'stage_index')
            try
                value = source.stage_index;
                if isnumeric(value) && isscalar(value) && isfinite(value)
                    context.stage_index = value;
                end
            catch %#ok<CTCH>
            end
        end
        if isfield(source, 'stage_count')
            try
                value = source.stage_count;
                if isnumeric(value) && isscalar(value) && isfinite(value)
                    context.stage_count = value;
                end
            catch %#ok<CTCH>
            end
        end
    end
catch %#ok<CTCH>
    context = struct();
end
try
    if isnumeric(job_id) && isscalar(job_id) && isfinite(job_id) && ...
            job_id == floor(job_id) && job_id >= 1
        context.job_number = job_id;
    end
catch %#ok<CTCH>
end
end

function tracker = local_output_init(runtime, transport)
%LOCAL_OUTPUT_INIT Start transition/heartbeat tracking without emitting.
tracker = struct('last_state', '', 'next_heartbeat', [], ...
    'heartbeat_interval', 60);
interval = 60;
try
    if isstruct(runtime) && isfield(runtime, 'heartbeat_interval_seconds')
        candidate = runtime.heartbeat_interval_seconds;
        if isnumeric(candidate) && isscalar(candidate) && ...
                isfinite(candidate) && candidate > 0
            interval = candidate;
        end
    end
catch %#ok<CTCH>
end
tracker.heartbeat_interval = interval;
try
    tracker.next_heartbeat = local_clock(transport) + interval / 86400;
catch %#ok<CTCH>
    tracker.next_heartbeat = [];
end
end

function tracker = local_output_note(tracker, runtime, job_id, new_state, transport)
%LOCAL_OUTPUT_NOTE Emit one transition when the normalized state changes.
%   The initial observation is emitted as observed; duplicates are
%   suppressed; the heartbeat deadline resets on every real transition.
try
    if ~isstruct(tracker) || numel(tracker) ~= 1
        return;
    end
    if ~ischar(new_state) || isempty(new_state)
        new_state = 'unknown';
    end
    if isfield(tracker, 'last_state') && ischar(tracker.last_state) && ...
            strcmp(tracker.last_state, new_state)
        return;
    end
    if strcmp(new_state, 'unknown')
        return;
    end
    tracker.last_state = new_state;
    try
        interval = 60;
        if isfield(tracker, 'heartbeat_interval') && ...
                isnumeric(tracker.heartbeat_interval) && ...
                isscalar(tracker.heartbeat_interval) && ...
                isfinite(tracker.heartbeat_interval) && ...
                tracker.heartbeat_interval > 0
            interval = tracker.heartbeat_interval;
        end
        tracker.next_heartbeat = local_clock(transport) + interval / 86400;
    catch %#ok<CTCH>
    end
    try
        if strcmp(new_state, 'pending') || strcmp(new_state, 'running')
            context = local_stage_output_context(runtime, job_id, 3);
        else
            context = local_output_context(runtime, job_id);
        end
        pseudo_CT_output('INFO', context, 'MLSC job %d state %s.', ...
            job_id, new_state);
    catch %#ok<CTCH>
    end
catch %#ok<CTCH>
end
end

function tracker = local_output_maybe_heartbeat(tracker, runtime, job_id, result, transport)
%LOCAL_OUTPUT_MAYBE_HEARTBEAT Emit a bounded pending/running heartbeat.
%   Uses only TRANSPORT.clock and the existing poll loop; no extra queries
%   or sleeps are performed.  Per-poll output stays suppressed.
try
    if ~isstruct(tracker) || numel(tracker) ~= 1
        return;
    end
    if ~isfield(tracker, 'last_state') || ~ischar(tracker.last_state)
        return;
    end
    if ~strcmp(tracker.last_state, 'pending') && ...
            ~strcmp(tracker.last_state, 'running')
        return;
    end
    if ~isfield(tracker, 'next_heartbeat') || isempty(tracker.next_heartbeat)
        return;
    end
    now_value = local_clock(transport);
    if ~(now_value >= tracker.next_heartbeat)
        return;
    end
    try
        context = local_stage_output_context(runtime, job_id, 3);
        elapsed = 0;
        try
            if isstruct(result) && isfield(result, 'clock_started') && ...
                    isnumeric(result.clock_started) && ...
                    isscalar(result.clock_started) && ...
                    isfinite(result.clock_started)
                elapsed = local_elapsed_seconds(result.clock_started, ...
                    now_value);
            end
        catch %#ok<CTCH>
        end
        if strcmp(tracker.last_state, 'running')
            pseudo_CT_output('INFO', context, ...
                'MLSC job %d still running (elapsed %s).', job_id, ...
                local_elapsed_text(elapsed));
        else
            pseudo_CT_output('INFO', context, ...
                'MLSC job %d still pending (elapsed %s).', job_id, ...
                local_elapsed_text(elapsed));
        end
    catch %#ok<CTCH>
    end
    try
        interval = 60;
        if isfield(tracker, 'heartbeat_interval') && ...
                isnumeric(tracker.heartbeat_interval) && ...
                isscalar(tracker.heartbeat_interval) && ...
                isfinite(tracker.heartbeat_interval) && ...
                tracker.heartbeat_interval > 0
            interval = tracker.heartbeat_interval;
        end
        tracker.next_heartbeat = now_value + interval / 86400;
    catch %#ok<CTCH>
    end
catch %#ok<CTCH>
end
end

function local_emit_accepted(runtime, job_id)
%LOCAL_EMIT_ACCEPTED Report the accepted numeric Slurm job ID once.
try
    if ~isnumeric(job_id) || ~isscalar(job_id) || ~isfinite(job_id) || ...
            job_id ~= floor(job_id) || job_id < 1
        return;
    end
    context = local_stage_output_context(runtime, job_id, 2);
    pseudo_CT_output('INFO', context, 'MLSC job %d accepted.', job_id);
catch %#ok<CTCH>
end
end

function local_emit_terminal(runtime, result, transport)
%LOCAL_EMIT_TERMINAL Report job ID, state, exit, and elapsed once.
%   Skipped when no numeric job was accepted.  Output failures never change
%   the lifecycle result.
try
    if ~isstruct(result) || ~isfield(result, 'job_id')
        return;
    end
    job_id = result.job_id;
    if ~isnumeric(job_id) || ~isscalar(job_id) || ~isfinite(job_id) || ...
            job_id ~= floor(job_id) || job_id < 1
        return;
    end
    state = 'unknown';
    try
        if isfield(result, 'state') && ischar(result.state) && ...
                ~isempty(result.state)
            state = result.state;
        end
    catch %#ok<CTCH>
    end
    exit_text = local_exit_text(result);
    elapsed = 0;
    try
        if isstruct(result) && isfield(result, 'clock_started') && ...
                isnumeric(result.clock_started) && ...
                isscalar(result.clock_started) && ...
                isfinite(result.clock_started)
            elapsed = local_elapsed_seconds(result.clock_started, ...
                local_clock(transport));
        elseif isfield(result, 'elapsed_seconds') && ...
                isnumeric(result.elapsed_seconds) && ...
                isscalar(result.elapsed_seconds) && ...
                isfinite(result.elapsed_seconds) && result.elapsed_seconds >= 0
            elapsed = result.elapsed_seconds;
        end
    catch %#ok<CTCH>
    end
    level = 'ERROR';
    try
        if isfield(result, 'success') && islogical(result.success) && ...
                isscalar(result.success) && result.success
            level = 'SUCCESS';
        end
    catch %#ok<CTCH>
    end
    context = local_output_context(runtime, job_id);
    pseudo_CT_output(level, context, 'MLSC job %d %s exit %s elapsed %s.', ...
        job_id, state, exit_text, local_elapsed_text(elapsed));
catch %#ok<CTCH>
end
end

function text = local_elapsed_text(elapsed)
text = '00:00:00';
try
    if ~isnumeric(elapsed) || ~isscalar(elapsed) || ~isfinite(elapsed) || ...
            elapsed < 0
        elapsed = 0;
    end
    elapsed = max(0, floor(elapsed));
    text = sprintf('%02d:%02d:%02d', floor(elapsed / 3600), ...
        floor(rem(elapsed, 3600) / 60), rem(elapsed, 60));
catch %#ok<CTCH>
    text = '00:00:00';
end
end

function text = local_exit_text(result)
text = 'unavailable';
try
    if isfield(result, 'exit_code') && isnumeric(result.exit_code) && ...
            isscalar(result.exit_code) && isfinite(result.exit_code) && ...
            result.exit_code == floor(result.exit_code) && ...
            result.exit_code >= 0
        text = num2str(result.exit_code, '%.0f');
    end
catch %#ok<CTCH>
end
end

function progress = local_empty_progress()
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

function [progress_path, progress_cursor, progress_milestones] = ...
        local_progress_init(backend, shared_temp)
%LOCAL_PROGRESS_INIT Select the exact current-submission progress artifact.
%   Reads only the backend-selected unique file; never scans a directory
%   and never infers a latest file.  A stale legacy or prior-submission
%   file is therefore never consumed.  R2010b only.
progress_path = '';
try
    progress_cursor = mlsc_progress('init');
catch %#ok<CTCH>
    progress_cursor = struct('offset', 0, 'pending', '');
    progress_cursor.emitted = cell(0, 1);
end
progress_milestones = cell(0, 1);
try
    explicit = local_explicit_progress_path(backend);
    if ischar(explicit) && size(explicit, 1) == 1 && ...
            ~isempty(explicit) && ~any(explicit == char(0))
        progress_path = explicit;
        return;
    end
    if ischar(shared_temp) && size(shared_temp, 1) == 1 && ...
            ~isempty(shared_temp) && ~any(shared_temp == char(0))
        if isstruct(backend) && numel(backend) == 1 && ...
                isfield(backend, 'submission_correlation_id')
            candidate = backend.submission_correlation_id;
            if ischar(candidate) && size(candidate, 1) == 1 && ...
                    ~isempty(candidate)
                try
                    progress_path = mlsc_progress('path_for', ...
                        shared_temp, candidate);
                    return;
                catch %#ok<CTCH>
                end
            end
        end
        progress_path = mlsc_progress('path', shared_temp);
    end
catch %#ok<CTCH>
    if isempty(progress_path)
        progress_path = '';
    end
end
end

function explicit = local_explicit_progress_path(backend)
explicit = '';
try
    if ~isstruct(backend) || numel(backend) ~= 1
        return;
    end
    if isfield(backend, 'artifact') && isstruct(backend.artifact) && ...
            numel(backend.artifact) == 1 && ...
            isfield(backend.artifact, 'progress_path')
        candidate = backend.artifact.progress_path;
        if ischar(candidate) && size(candidate, 1) == 1 && ...
                ~isempty(candidate) && ~any(candidate == char(0))
            explicit = candidate;
            return;
        end
    end
    if isfield(backend, 'progress_path')
        candidate = backend.progress_path;
        if ischar(candidate) && size(candidate, 1) == 1 && ...
                ~isempty(candidate) && ~any(candidate == char(0))
            explicit = candidate;
            return;
        end
    end
catch %#ok<CTCH>
    explicit = '';
end
end

function [progress_cursor, progress_milestones] = local_progress_poll( ...
        progress_path, progress_cursor, progress_milestones, runtime, job_id)
try
    if ~ischar(progress_path) || isempty(progress_path)
        return;
    end
    if ~iscell(progress_milestones)
        progress_milestones = cell(0, 1);
    end
    [events, next_cursor] = mlsc_progress('consume', progress_path, ...
        progress_cursor);
    progress_cursor = next_cursor;
    if isempty(events)
        return;
    end
    for ii = 1:numel(events)
        milestone = events{ii};
        if ~ischar(milestone) || size(milestone, 1) ~= 1 || ...
                isempty(milestone)
            continue;
        end
        if local_progress_contains(progress_milestones, milestone)
            continue;
        end
        progress_milestones{end + 1, 1} = milestone; %#ok<AGROW>
        try
            local_progress_emit(runtime, job_id, milestone);
        catch %#ok<CTCH>
        end
    end
catch %#ok<CTCH>
end
end

function [has_incomplete, pending_bytes] = local_progress_trailing( ...
        progress_cursor)
%LOCAL_PROGRESS_TRAILING Bounded secret-free trailing-progress indicator.
%   Returns a logical flag plus the pending-byte count for CURSOR.PENDING
%   without returning or logging the trailing content itself.  R2010b only.
has_incomplete = false;
pending_bytes = 0;
try
    if isstruct(progress_cursor) && numel(progress_cursor) == 1 && ...
            isfield(progress_cursor, 'pending')
        pending = progress_cursor.pending;
        if ischar(pending) && ~isempty(pending)
            has_incomplete = true;
            pending_bytes = double(numel(pending));
            if ~isfinite(pending_bytes) || pending_bytes < 0
                pending_bytes = 0;
            else
                pending_bytes = floor(pending_bytes);
            end
        end
    end
catch %#ok<CTCH>
    has_incomplete = false;
    pending_bytes = 0;
end
end

function result = local_progress_record_trailing(result, progress_cursor)
%LOCAL_PROGRESS_RECORD_TRAILING Persist the trailing indicator on RESULT.
%   Observation only: never echoes trailing content and never throws.
try
    [has_incomplete, pending_bytes] = local_progress_trailing( ...
        progress_cursor);
    if ~isfield(result, 'progress') || ~isstruct(result.progress) || ...
            numel(result.progress) ~= 1
        result.progress = local_empty_progress();
    end
    result.progress.incomplete_trailing = has_incomplete;
    result.progress.pending_bytes = pending_bytes;
catch %#ok<CTCH>
end
end

function flag = local_progress_evidence_flag(result)
%LOCAL_PROGRESS_EVIDENCE_FLAG Safe flattened trailing flag for evidence.
flag = false;
try
    if isstruct(result) && numel(result) == 1 && ...
            isfield(result, 'progress') && isstruct(result.progress) && ...
            numel(result.progress) == 1 && ...
            isfield(result.progress, 'incomplete_trailing')
        candidate = result.progress.incomplete_trailing;
        if islogical(candidate) && isscalar(candidate)
            flag = candidate;
        end
    end
catch %#ok<CTCH>
    flag = false;
end
end

function count = local_progress_evidence_bytes(result)
%LOCAL_PROGRESS_EVIDENCE_BYTES Safe flattened byte count for evidence.
count = 0;
try
    if isstruct(result) && numel(result) == 1 && ...
            isfield(result, 'progress') && isstruct(result.progress) && ...
            numel(result.progress) == 1 && ...
            isfield(result.progress, 'pending_bytes')
        candidate = result.progress.pending_bytes;
        if isnumeric(candidate) && isscalar(candidate) && ...
                isfinite(candidate) && candidate >= 0 && ...
                candidate == floor(candidate)
            count = double(candidate);
        end
    end
catch %#ok<CTCH>
    count = 0;
end
end

function local_progress_emit(runtime, job_id, milestone)
try
    [level, stage_index, message] = local_progress_display(milestone);
    if isempty(message)
        return;
    end
    context = local_stage_output_context(runtime, job_id, stage_index);
    pseudo_CT_output(level, context, message);
catch %#ok<CTCH>
end
end

function [level, stage_index, message] = local_progress_display(milestone)
level = '';
stage_index = 3;
message = '';
try
    if strcmp(milestone, 'stage_in|done')
        level = 'SUCCESS';
        stage_index = 3;
        message = 'MLSC stage-in completed.';
    elseif strcmp(milestone, 'preparation|done')
        level = 'SUCCESS';
        stage_index = 3;
        message = 'MLSC preparation completed.';
    elseif strcmp(milestone, 'alias_recenter|done')
        level = 'SUCCESS';
        stage_index = 3;
        message = 'MLSC alias-recenter completed.';
    elseif strcmp(milestone, 'normalize|start')
        level = 'INFO';
        stage_index = 3;
        message = 'MLSC normalization started.';
    elseif strcmp(milestone, 'normalize|done')
        level = 'SUCCESS';
        stage_index = 3;
        message = 'MLSC normalization completed.';
    elseif strcmp(milestone, 'alignment_mask|done')
        level = 'SUCCESS';
        stage_index = 3;
        message = 'MLSC alignment-mask completed.';
    elseif strcmp(milestone, 'segmentation|done')
        level = 'SUCCESS';
        stage_index = 3;
        message = 'MLSC segmentation completed.';
    elseif strcmp(milestone, 'bone|done')
        level = 'SUCCESS';
        stage_index = 3;
        message = 'MLSC bone completed.';
    elseif strcmp(milestone, 'dartel_warp_reslice|done')
        level = 'SUCCESS';
        stage_index = 3;
        message = 'MLSC DARTEL-warp-reslice completed.';
    elseif strcmp(milestone, 'pseudoCT|start')
        level = 'INFO';
        stage_index = 3;
        message = 'MLSC pseudo-CT started.';
    elseif strcmp(milestone, 'pseudoCT|done')
        level = 'SUCCESS';
        stage_index = 3;
        message = 'MLSC pseudo-CT completed.';
    elseif strcmp(milestone, 'attenuation_qc|done')
        level = 'SUCCESS';
        stage_index = 3;
        message = 'MLSC attenuation-QC completed.';
    elseif strcmp(milestone, 'verify|start')
        level = 'INFO';
        stage_index = 4;
        message = 'MLSC verification started.';
    elseif strcmp(milestone, 'verify|done')
        level = 'SUCCESS';
        stage_index = 4;
        message = 'MLSC verification completed.';
    elseif strcmp(milestone, 'copy_back|start')
        level = 'INFO';
        stage_index = 4;
        message = 'MLSC copy-back started.';
    elseif strcmp(milestone, 'copy_back|done')
        level = 'SUCCESS';
        stage_index = 4;
        message = 'MLSC verified return to shared temp completed.';
    end
catch %#ok<CTCH>
    level = '';
    message = '';
end
end

function found = local_progress_contains(list, value)
found = false;
try
    for ii = 1:numel(list)
        if ischar(list{ii}) && strcmp(list{ii}, value)
            found = true;
            return;
        end
    end
catch %#ok<CTCH>
end
end

function context = local_stage_output_context(runtime, job_id, stage_index)
context = local_output_context(runtime, job_id);
try
    if isnumeric(stage_index) && isscalar(stage_index) && ...
            isfinite(stage_index) && stage_index == floor(stage_index) && ...
            stage_index >= 1
        context.stage_index = stage_index;
        context.stage_count = 8;
    end
catch %#ok<CTCH>
end
end

function result = local_archive_progress(result, runtime)
try
    if ~isstruct(result) || numel(result) ~= 1
        return;
    end
    if ~isfield(result, 'progress') || ~isstruct(result.progress) || ...
            numel(result.progress) ~= 1
        result.progress = local_empty_progress();
    end
    source_path = '';
    try
        if isfield(result.progress, 'source_path') && ...
                ischar(result.progress.source_path)
            source_path = result.progress.source_path;
        end
    catch %#ok<CTCH>
        source_path = '';
    end
    if isempty(source_path) && isfield(result, 'shared_subject_temp') && ...
            ischar(result.shared_subject_temp) && ...
            ~isempty(result.shared_subject_temp)
        try
            if isfield(result, 'submission_correlation_id') && ...
                    ischar(result.submission_correlation_id) && ...
                    ~isempty(result.submission_correlation_id)
                try
                    source_path = mlsc_progress('path_for', ...
                        result.shared_subject_temp, ...
                        result.submission_correlation_id);
                catch %#ok<CTCH>
                    source_path = mlsc_progress('path', ...
                        result.shared_subject_temp);
                end
            else
                source_path = mlsc_progress('path', ...
                    result.shared_subject_temp);
            end
            result.progress.source_path = source_path;
        catch %#ok<CTCH>
        end
    end
    destination_dir = '';
    try
        if isstruct(runtime) && isfield(runtime, 'log_archive_dir') && ...
                ischar(runtime.log_archive_dir) && ...
                ~isempty(runtime.log_archive_dir)
            destination_dir = runtime.log_archive_dir;
        elseif isstruct(runtime) && isfield(runtime, 'evidence_dir') && ...
                ischar(runtime.evidence_dir) && ...
                ~isempty(runtime.evidence_dir)
            destination_dir = runtime.evidence_dir;
        end
    catch %#ok<CTCH>
        destination_dir = '';
    end
    if isempty(source_path) || isempty(destination_dir)
        return;
    end
    destination_path = fullfile(destination_dir, ...
        local_archive_progress_name(source_path));
    result.progress.archive_path = destination_path;
    result.progress.archive_attempted = true;
    result.progress.archive_succeeded = false;
    result.progress.archive_detail = '';
    if exist(source_path, 'file') ~= 2
        result.progress.archive_detail = ...
            'MLSC progress file was not found; nothing was archived.';
        return;
    end
    if exist(destination_dir, 'dir') ~= 7
        result.progress.archive_detail = ...
            'MLSC progress archive directory was not found.';
        return;
    end
    [copy_ok, copy_detail] = local_archive_progress_file(source_path, ...
        destination_path, result.progress.milestones);
    result.progress.archive_succeeded = copy_ok;
    result.progress.archive_detail = copy_detail;
catch %#ok<CTCH>
    try
        result.progress.archive_attempted = true;
        result.progress.archive_succeeded = false;
        if isempty(result.progress.archive_detail)
            result.progress.archive_detail = ...
                'MLSC progress archive was unavailable.';
        end
    catch %#ok<CTCH>
    end
end
end

function archive_name = local_archive_progress_name(source_path)
%LOCAL_ARCHIVE_PROGRESS_NAME Deterministic correlation-preserving name.
%   Uses the source basename (already .mlsc_progress_<id> for current
%   submissions) so the correlation identity is preserved in the archive.
%   Falls back to the legacy name only for a legacy source.  R2010b only.
archive_name = '.mlsc_progress';
try
    if ~ischar(source_path) || size(source_path, 1) ~= 1 || ...
            isempty(source_path) || any(source_path == char(0))
        return;
    end
    [~, base, extension] = fileparts(source_path);
    candidate = [base extension];
    if isempty(candidate) || any(candidate == char(0)) || ...
            ~isempty(strfind(candidate, filesep))
        return;
    end
    if strcmp(candidate, '.mlsc_progress')
        archive_name = candidate;
        return;
    end
    prefix = '.mlsc_progress_';
    if strncmp(candidate, prefix, length(prefix))
        suffix = candidate((length(prefix) + 1):end);
        if ~isempty(suffix) && length(suffix) <= 64 && ...
                ~isempty(regexp(suffix, '^[A-Za-z0-9_.-]+$', 'once'))
            archive_name = candidate;
            return;
        end
    end
catch %#ok<CTCH>
    archive_name = '.mlsc_progress';
end
end

function [success, detail] = local_archive_progress_file(source_path, ...
        destination_path, milestones)
%LOCAL_ARCHIVE_PROGRESS_FILE Generate a sanitized durable progress archive.
%   Writes only the validated recognized milestone sequence (order
%   preserved, at-most-once, from the parser accepted output) and never
%   copies raw source bytes, so malformed, unknown, secret-bearing, or
%   incomplete-trailing input is never archived or echoed.  The source file
%   is never read for content here beyond the existence check above; even
%   when source and destination coincide the promotion writes only the
%   sanitized sequence.  R2010b only.
success = false;
detail = '';
try
    if isempty(source_path) || isempty(destination_path)
        detail = 'MLSC progress archive path was not configured.';
        return;
    end
    destination_parent = fileparts(destination_path);
    if isempty(destination_parent) || exist(destination_parent, 'dir') ~= 7
        detail = 'MLSC progress archive directory was not found.';
        return;
    end
    sanitized = local_sanitized_milestones(milestones);
    stage_path = tempname(destination_parent);
    fid = fopen(stage_path, 'w');
    if fid == -1
        detail = ...
            'MLSC progress archive copy failed: stage file unavailable.';
        return;
    end
    write_ok = true;
    try
        for ii = 1:numel(sanitized)
            line = sanitized{ii};
            count = fwrite(fid, [line char(10)], 'char');
            if count ~= length(line) + 1
                write_ok = false;
                break;
            end
        end
        fclose(fid);
    catch %#ok<CTCH>
        try
            fclose(fid);
        catch %#ok<CTCH>
        end
        write_ok = false;
    end
    if ~write_ok
        if exist(stage_path, 'file') == 2
            delete(stage_path);
        end
        detail = ...
            'MLSC progress archive copy failed: sanitized write failed.';
        return;
    end
    [move_success, move_message] = movefile(stage_path, destination_path, 'f');
    if ~move_success
        if exist(stage_path, 'file') == 2
            delete(stage_path);
        end
        detail = ['MLSC progress archive promotion failed: ' move_message];
        return;
    end
    success = exist(destination_path, 'file') == 2;
    if ~success
        detail = 'MLSC progress archive was not created.';
    end
catch %#ok<CTCH>
    success = false;
    if isempty(detail)
        detail = 'MLSC progress archive was unavailable.';
    end
end
end

function sanitized = local_sanitized_milestones(milestones)
%LOCAL_SANITIZED_MILESTONES Validated recognized sequence only.
%   Order preserved, at-most-once, from parser accepted output.  R2010b only.
sanitized = cell(0, 1);
try
    if ~iscell(milestones)
        return;
    end
    for ii = 1:numel(milestones)
        candidate = milestones{ii};
        if ~ischar(candidate) || size(candidate, 1) ~= 1 || ...
                isempty(candidate)
            continue;
        end
        if local_is_archivable_record(candidate) && ...
                ~local_progress_contains(sanitized, candidate)
            sanitized{end + 1, 1} = candidate; %#ok<AGROW>
        end
    end
catch %#ok<CTCH>
    sanitized = cell(0, 1);
end
end

function recognized = local_is_archivable_record(line)
%LOCAL_IS_ARCHIVABLE_RECORD Enumerated records only, never free-form.
%   Mirrors mlsc_progress local_is_record (including T004 current
%   milestones) so the durable archive preserves the validated sequence.
recognized = strcmp(line, 'stage_in|done') || ...
    strcmp(line, 'preparation|done') || ...
    strcmp(line, 'alias_recenter|done') || ...
    strcmp(line, 'normalize|start') || ...
    strcmp(line, 'normalize|done') || ...
    strcmp(line, 'alignment_mask|done') || ...
    strcmp(line, 'segmentation|done') || ...
    strcmp(line, 'bone|done') || ...
    strcmp(line, 'dartel_warp_reslice|done') || ...
    strcmp(line, 'pseudoCT|start') || ...
    strcmp(line, 'pseudoCT|done') || ...
    strcmp(line, 'attenuation_qc|done') || ...
    strcmp(line, 'verify|start') || ...
    strcmp(line, 'verify|done') || ...
    strcmp(line, 'copy_back|start') || ...
    strcmp(line, 'copy_back|done');
end

function terminal = local_is_terminal(state)
terminal = any(strcmp(state, {'completed'; 'failed'; 'cancelled'; ...
    'timeout'; 'OUT_OF_MEMORY'; 'NODE_FAIL'}));
end

function value = local_subject_value(subject, names)
value = '';
for ii = 1:length(names)
    if isfield(subject, names{ii})
        value = subject.(names{ii});
        if ~ischar(value)
            value = '';
        end
        return;
    end
end
end
