function result = mlsc_backend(subject, config, runtime, transport)
%MLSC_BACKEND Prepare and submit one MLSC subject through an injected seam.
%   RESULT = MLSC_BACKEND(SUBJECT, CONFIG, RUNTIME, TRANSPORT) runs the
%   credential-free preflight and script generator, then requires TRANSPORT
%   to prove that the existing approved MATLAB SSH2/trust mechanism is secure
%   before invoking its submit_script callback.  Authentication stays in the
%   runtime callback closure; it is never accepted in profiles, scripts,
%   command strings, logs, or this result.
%
%   TRANSPORT.verify() must return logical true only after the approved strict
%   host-key/authentication gate has succeeded.  TRANSPORT.submit_script(COMMAND)
%   is the only submission callback.  The generated script is written to the
%   shared filesystem before this callback, so no input/output/script payload
%   is transported over the network.  Missing or rejected transport fails
%   before submission; no null verifier or alternate transport is used.
%
%   A missing or malformed sbatch response is reconciled through optional
%   credential-free query_squeue_by_name/query_sacct_by_name callbacks before
%   submission is declared unresolved.  No submission retry is attempted.
%
%   Each submission owns one exact per-submission progress artifact
%   fullfile(SHARED_TEMP, '.mlsc_progress_<correlation-id>') selected from
%   the non-secret submission correlation identity and passed explicitly
%   through the generated artifact.  A stale legacy shared file left by a
%   preserved-temp prior run is best-effort removed as harmless cleanup
%   only; correctness never depends on that deletion because the current
%   run writes and reads only its own unique file.
%
%   Minimum supported MATLAB: R2010b.
%
%   T004 current gate (T014 authoritative): for MLSC current, unresolved
%   pending native evidence blocks real execution before any submission.
%   Contract validation (preflight/generation) allows the T007-pending
%   marker offline; this gate enforces production proof when a real
%   submission is requested. No catalog/resolver, legacy untouched.

if nargin < 4 || ~isstruct(transport) || numel(transport) ~= 1
    error('pseudo_CT:MLSCTransportRequired', ...
        'A secure runtime MLSC transport seam is required before submission.');
end
if isfield(transport, 'username') || isfield(transport, 'password') || ...
        isfield(transport, 'passphrase') || isfield(transport, 'credentials') || ...
        isfield(transport, 'secret') || isfield(transport, 'token')
    error('pseudo_CT:MLSCTransportRejected', ...
        'MLSC transport authentication material must remain in a runtime closure.');
end
if ~isfield(transport, 'verify') || ~isa(transport.verify, 'function_handle') || ...
        ~isfield(transport, 'submit_script') || ...
        ~isa(transport.submit_script, 'function_handle')
    error('pseudo_CT:MLSCTransportRequired', ...
        'MLSC transport must provide verify and submit_script callbacks.');
end

% Run the side-effect-free preflight first so the receipt identity is only
% created for a submission that can reach the existing script generator.
mlsc_preflight(subject, config, runtime);
is_current = false;
try
    is_current = mlsc_current_validate('is_current', config);
catch %#ok<CTCH>
    is_current = false;
end
if is_current
    try
        mlsc_current_validate('validate_for_execution', config);
    catch ME
        if strncmp(ME.identifier, 'pseudo_CT:MLSC', length('pseudo_CT:MLSC'))
            rethrow(ME);
        end
        error('pseudo_CT:MLSCCurrentNativeEvidence', ...
            'Current production evidence is unresolved; submission blocked.');
    end
end
[receipt_path, correlation_id] = local_submission_identity(subject, runtime);
runtime.job_name = local_job_name(correlation_id);
runtime.submission_correlation_id = correlation_id;
artifact = mlsc_generate_slurm_script(subject, config, runtime);
if isempty(artifact.submission_command)
    error('pseudo_CT:MLSCScriptPathRequired', ...
        'A shared script path and runtime account are required before submission.');
end

try
    secure = feval(transport.verify);
catch %#ok<CTCH>
    error('pseudo_CT:MLSCTransportRejected', ...
        'Secure MLSC transport verification failed; submission was not attempted.');
end
if ~islogical(secure) || ~isscalar(secure) || ~secure
    error('pseudo_CT:MLSCTransportRejected', ...
        'Secure MLSC transport verification was not accepted; submission was not attempted.');
end

% Harmless legacy cleanup only: correctness comes from the unique
% per-submission artifact above, so a stale legacy file that cannot be
% removed never affects the current run.
local_reset_progress(subject);

receipt = local_new_receipt(receipt_path, correlation_id, runtime.job_name);
% The receipt is atomically promoted before the submission callback.  If this
% write fails, do not risk submitting without a durable correlation record.
local_write_receipt(receipt_path, receipt);

receipt.status = 'submission_attempted';
receipt.submission_attempted = true;
receipt.attempted_at = local_timestamp();
local_write_receipt(receipt_path, receipt);

local_write_script(artifact.script_text, runtime.script_path);
script_materialized = true;
artifact.submission_receipt_path = receipt_path;
artifact.submission_correlation_id = correlation_id;
artifact.job_name = runtime.job_name;

submission_callback_failed = false;
try
    submission_response = feval(transport.submit_script, artifact.submission_command);
catch %#ok<CTCH>
    submission_response = '';
    submission_callback_failed = true;
end
receipt.response_received = local_response_received(submission_response);
receipt.response_parseable = false;
local_try_write_receipt(receipt_path, receipt);

try
    job_id = mlsc_parse_sbatch_job_id(submission_response);
    response_parseable = true;
catch %#ok<CTCH>
    response_parseable = false;
end

if response_parseable
    receipt.status = 'accepted';
    receipt.response_parseable = true;
    receipt.submission_outcome = 'accepted';
    receipt.job_id = job_id;
    receipt.completed_at = local_timestamp();
    local_try_write_receipt(receipt_path, receipt);
    result = local_result(artifact, job_id, true, true, false, ...
        response_parseable, false, 0, 'accepted', submission_callback_failed, ...
        receipt_path, correlation_id, runtime.job_name, script_materialized);
    return;
end

receipt.status = 'response_unparseable';
receipt.submission_outcome = 'response_unparseable';
local_try_write_receipt(receipt_path, receipt);
[job_id, reconciled, reconciliation_attempts] = ...
    local_reconcile_submission(runtime.job_name, transport, runtime);

if reconciled
    receipt.status = 'recovered';
    receipt.submission_outcome = 'recovered';
    receipt.job_id = job_id;
    receipt.reconciled = true;
    receipt.reconciliation_attempts = reconciliation_attempts;
    receipt.completed_at = local_timestamp();
    local_try_write_receipt(receipt_path, receipt);
    result = local_result(artifact, job_id, true, true, true, ...
        response_parseable, true, reconciliation_attempts, 'recovered', ...
        submission_callback_failed, receipt_path, correlation_id, ...
        runtime.job_name, script_materialized);
else
    receipt.status = 'unresolved';
    receipt.submission_outcome = 'unresolved';
    receipt.reconciliation_attempts = reconciliation_attempts;
    receipt.completed_at = local_timestamp();
    local_try_write_receipt(receipt_path, receipt);
    result = local_result(artifact, 0, false, true, true, ...
        response_parseable, false, reconciliation_attempts, 'unresolved', ...
        submission_callback_failed, receipt_path, correlation_id, ...
        runtime.job_name, script_materialized);
end
end

function result = local_result(artifact, job_id, accepted, attempted, response_lost, ...
        response_parseable, reconciled, reconciliation_attempts, outcome, ...
        callback_failed, receipt_path, correlation_id, job_name, script_materialized)
result = struct();
result.schema = 'pseudo-CT.mlsc-backend/v1';
if accepted
    result.status = 'submitted';
else
    result.status = 'submission_unresolved';
end
result.artifact = artifact;
result.job_id = job_id;
result.submission_accepted = accepted;
result.submission_attempted = attempted;
result.submission_response_lost = response_lost;
result.submission_response_parseable = response_parseable;
result.submission_reconciled = reconciled;
result.submission_reconciliation_attempts = reconciliation_attempts;
result.submission_outcome = outcome;
result.submission_callback_failed = callback_failed;
result.submission_receipt_path = receipt_path;
result.submission_correlation_id = correlation_id;
result.job_name = job_name;
result.progress_path = '';
result.progress_filename = '';
result.progress_correlation_id = correlation_id;
try
    if isstruct(artifact) && numel(artifact) == 1
        if isfield(artifact, 'progress_path') && ischar(artifact.progress_path)
            result.progress_path = artifact.progress_path;
        end
        if isfield(artifact, 'progress_filename') && ...
                ischar(artifact.progress_filename)
            result.progress_filename = artifact.progress_filename;
        end
        if isfield(artifact, 'progress_correlation_id') && ...
                ischar(artifact.progress_correlation_id)
            result.progress_correlation_id = ...
                artifact.progress_correlation_id;
        end
    end
catch %#ok<CTCH>
end
result.script_materialized = script_materialized;
result.credentials_emitted = false;
result.network_payload_staging = false;
result.secure_transport_verified = true;
result.squeue_reconciliation_query_contract = ...
    'squeue --noheader --user="$USER" --name=JOB_NAME --format=%A';
result.sacct_reconciliation_query_contract = ...
    'sacct --allocations --noheader --parsable2 --user="$USER" --name=JOB_NAME --format=JobIDRaw,State,ExitCode,Start,End,Elapsed';
end

function [receipt_path, correlation_id] = local_submission_identity(subject, runtime)
shared_temp = local_subject_value(subject, {'shared_temp'; 'temp_dir'});
if isempty(shared_temp)
    error('pseudo_CT:MLSCSubmissionReceipt', ...
        'A shared subject temp is required for the MLSC submission receipt.');
end
receipt_dir = shared_temp;
if isfield(runtime, 'evidence_dir') && ischar(runtime.evidence_dir) && ...
        ~isempty(runtime.evidence_dir) && exist(runtime.evidence_dir, 'dir') == 7 && ...
        local_is_writable_directory(runtime.evidence_dir)
    receipt_dir = runtime.evidence_dir;
end
% A caller-provided non-secret correlation (deterministic tests) is reused
% only when it is a valid progress identity and both its receipt and its
% correlation-specific progress artifact are still unused; otherwise a
% fresh unique identity is allocated below.  Production callers never
% provide one, so every live submission creates its own file.  A preserved
% prior-generation progress file whose receipt is missing or was moved
% therefore never reselects that generation: the current run writes and
% reads only its own fresh file and never appends to or consumes the
% preserved file.
try
    if isstruct(runtime) && numel(runtime) == 1 && ...
            isfield(runtime, 'submission_correlation_id')
        candidate_id = runtime.submission_correlation_id;
        if ischar(candidate_id) && size(candidate_id, 1) == 1 && ...
                ~isempty(candidate_id)
            probe_name = mlsc_progress('filename_for', candidate_id);
            if ischar(probe_name) && ~isempty(probe_name)
                candidate_receipt = fullfile(receipt_dir, ...
                    ['.mlsc_submission_' candidate_id(:)' '.mat']);
                if exist(candidate_receipt, 'file') ~= 2
                    candidate_progress = '';
                    try
                        candidate_progress = mlsc_progress('path_for', ...
                            shared_temp, candidate_id);
                    catch %#ok<CTCH>
                        candidate_progress = '';
                    end
                    if ischar(candidate_progress) && ...
                            ~isempty(candidate_progress) && ...
                            exist(candidate_progress, 'file') ~= 2
                        receipt_path = candidate_receipt;
                        correlation_id = candidate_id(:)';
                        correlation_id = reshape(correlation_id, 1, ...
                            numel(correlation_id));
                        return;
                    end
                end
            end
        elseif ~isempty(candidate_id)
            error('pseudo_CT:MLSCProgressCorrelation', ...
                'A non-secret MLSC correlation identity is required.');
        end
    end
catch ME
    if strcmp(ME.identifier, 'pseudo_CT:MLSCProgressCorrelation')
        rethrow(ME);
    end
end
for ii = 1:10
    candidate = tempname(receipt_dir);
    [~, correlation_id, ~] = fileparts(candidate);
    correlation_id = regexprep(correlation_id, '[^A-Za-z0-9_.-]', '_');
    if isempty(correlation_id)
        continue;
    end
    if length(correlation_id) > 64
        correlation_id = correlation_id(1:64);
    end
    try
        mlsc_progress('filename_for', correlation_id);
    catch %#ok<CTCH>
        continue;
    end
    receipt_path = fullfile(receipt_dir, ...
        ['.mlsc_submission_' correlation_id '.mat']);
    if exist(receipt_path, 'file') == 2
        continue;
    end
    try
        fresh_progress = mlsc_progress('path_for', shared_temp, ...
            correlation_id);
    catch %#ok<CTCH>
        continue;
    end
    if exist(fresh_progress, 'file') == 2
        continue;
    end
    return;
end
error('pseudo_CT:MLSCSubmissionReceipt', ...
    'A unique MLSC submission receipt could not be allocated.');
end

function value = local_subject_value(subject, names)
value = '';
for ii = 1:length(names)
    if isfield(subject, names{ii})
        value = subject.(names{ii});
        return;
    end
end
end

function job_name = local_job_name(correlation_id)
job_name = ['pseudoCT_' correlation_id];
if length(job_name) > 128 || ...
        isempty(regexp(job_name, '^[A-Za-z0-9_.-]+$', 'once'))
    error('pseudo_CT:MLSCSubmissionReceipt', ...
        'The generated MLSC correlation job name is unsafe.');
end
end

function receipt = local_new_receipt(receipt_path, correlation_id, job_name)
receipt = struct();
receipt.schema = 'pseudo-CT.mlsc-submission-receipt/v1';
receipt.receipt_path = receipt_path;
receipt.correlation_id = correlation_id;
receipt.job_name = job_name;
receipt.status = 'prepared';
receipt.submission_attempted = false;
receipt.attempted_at = '';
receipt.response_received = false;
receipt.response_parseable = false;
receipt.submission_outcome = 'not_attempted';
receipt.job_id = 0;
receipt.reconciled = false;
receipt.reconciliation_attempts = 0;
receipt.created_at = local_timestamp();
receipt.completed_at = '';
end

function local_reset_progress(subject)
%LOCAL_RESET_PROGRESS Harmless legacy progress cleanup.
%   Best-effort removes a stale legacy .mlsc_progress file left by a
%   preserved-temp prior run.  Correctness never depends on this deletion:
%   the current submission writes and reads only its own unique
%   .mlsc_progress_<correlation-id> artifact.  Never throws and never
%   fails submission.
try
    shared_temp = local_subject_value(subject, {'shared_temp'; 'temp_dir'});
    if ~ischar(shared_temp) || size(shared_temp, 1) ~= 1 || ...
            isempty(shared_temp) || any(shared_temp == char(0))
        return;
    end
    progress_path = '';
    try
        progress_path = mlsc_progress('path', shared_temp);
    catch %#ok<CTCH>
        return;
    end
    if isempty(progress_path) || exist(progress_path, 'file') ~= 2
        return;
    end
    try
        delete(progress_path);
    catch %#ok<CTCH>
    end
catch %#ok<CTCH>
end
end

function local_write_receipt(receipt_path, receipt)
receipt_parent = fileparts(receipt_path);
stage_path = [tempname(receipt_parent) '.mat'];
cleanup = onCleanup(@() local_remove_stage(stage_path)); %#ok<NASGU>
save(stage_path, 'receipt');
[move_success, ~] = movefile(stage_path, receipt_path, 'f');
if ~move_success
    error('pseudo_CT:MLSCSubmissionReceipt', ...
        'The MLSC submission receipt could not be promoted.');
end
end

function local_try_write_receipt(receipt_path, receipt)
try
    local_write_receipt(receipt_path, receipt);
catch %#ok<CTCH>
    % The initial receipt remains the durable no-secret correlation record.
end
end

function [job_id, recovered, attempts] = local_reconcile_submission(job_name, ...
        transport, runtime)
job_id = 0;
recovered = false;
max_attempts = 3;
if isfield(runtime, 'max_reconciliation_polls') && ...
        isnumeric(runtime.max_reconciliation_polls) && ...
        isscalar(runtime.max_reconciliation_polls) && ...
        isfinite(runtime.max_reconciliation_polls) && ...
        runtime.max_reconciliation_polls >= 1 && ...
        runtime.max_reconciliation_polls == floor(runtime.max_reconciliation_polls)
    max_attempts = runtime.max_reconciliation_polls;
end

for ii = 1:max_attempts
    attempts = ii;
    squeue_response = '';
    sacct_response = '';
    if isfield(transport, 'query_squeue_by_name') && ...
            isa(transport.query_squeue_by_name, 'function_handle')
        try
            squeue_response = feval(transport.query_squeue_by_name, job_name);
        catch %#ok<CTCH>
            squeue_response = '';
        end
    end
    if isfield(transport, 'query_sacct_by_name') && ...
            isa(transport.query_sacct_by_name, 'function_handle')
        try
            sacct_response = feval(transport.query_sacct_by_name, job_name);
        catch %#ok<CTCH>
            sacct_response = '';
        end
    end

    squeue_job_id = local_single_reconciliation_id(squeue_response);
    sacct_job_id = local_single_reconciliation_id(sacct_response);
    if squeue_job_id > 0 && sacct_job_id > 0 && ...
            squeue_job_id ~= sacct_job_id
        continue;
    elseif sacct_job_id > 0
        job_id = sacct_job_id;
    elseif squeue_job_id > 0
        job_id = squeue_job_id;
    end
    if job_id > 0
        recovered = true;
        return;
    end

    if ii < max_attempts && isfield(transport, 'sleep') && ...
            isa(transport.sleep, 'function_handle') && ...
            isfield(runtime, 'reconciliation_interval_seconds')
        try
            feval(transport.sleep, runtime.reconciliation_interval_seconds);
        catch %#ok<CTCH>
            % Reconciliation remains bounded and continues without a retry.
        end
    end
end
end

function job_id = local_single_reconciliation_id(response)
job_id = 0;
try
    lines = local_response_lines(response);
catch %#ok<CTCH>
    return;
end
ids = [];
for ii = 1:length(lines)
    fields = regexp(strtrim(lines{ii}), '\|', 'split');
    candidate = strtrim(fields{1});
    if isempty(regexp(candidate, '^[0-9]+$', 'once'))
        continue;
    end
    value = str2double(candidate);
    if isfinite(value) && value >= 1 && value == floor(value) && ...
            isempty(find(ids == value, 1))
        ids(end + 1) = value; %#ok<AGROW>
    end
end
if length(ids) == 1
    job_id = ids(1);
end
end

function lines = local_response_lines(response)
if ischar(response)
    lines = cellstr(response);
elseif iscell(response)
    lines = {};
    for ii = 1:numel(response)
        if ~ischar(response{ii})
            error('pseudo_CT:MLSCSbatchParse', ...
                'The MLSC scheduler response must contain text lines.');
        end
        lines{end + 1} = response{ii}; %#ok<AGROW>
    end
else
    error('pseudo_CT:MLSCSbatchParse', ...
        'The MLSC scheduler response must be text.');
end
end

function received = local_response_received(response)
received = false;
if ischar(response)
    received = ~isempty(strtrim(response));
elseif iscell(response)
    for ii = 1:numel(response)
        if ischar(response{ii}) && ~isempty(strtrim(response{ii}))
            received = true;
            return;
        end
    end
end
end

function stamp = local_timestamp()
stamp = [datestr(now, 'yyyy-mm-dd') 'T' datestr(now, 'HH:MM:SS')];
end

function local_write_script(script_text, script_path)
script_parent = fileparts(script_path);
if isempty(script_parent)
    script_parent = '.';
end
stage_path = tempname(script_parent);
fid = fopen(stage_path, 'w');
if fid == -1
    error('pseudo_CT:MLSCScriptWriteFailed', ...
        'The generated MLSC script could not be written.');
end
cleanup = onCleanup(@() local_remove_stage(stage_path));
count = fwrite(fid, script_text, 'char');
fclose(fid);
if count ~= length(script_text)
    error('pseudo_CT:MLSCScriptWriteFailed', ...
        'The generated MLSC script was written incompletely.');
end
[move_success, ~] = movefile(stage_path, script_path, 'f');
if ~move_success
    error('pseudo_CT:MLSCScriptWriteFailed', ...
        'The generated MLSC script could not be promoted.');
end
end

function local_remove_stage(stage_path)
if exist(stage_path, 'file') == 2
    delete(stage_path);
end
end

function writable = local_is_writable_directory(directory_path)
if exist(directory_path, 'dir') ~= 7
    writable = false;
    return;
end
probe_path = tempname(directory_path);
fid = fopen(probe_path, 'w');
writable = fid ~= -1;
if writable
    fclose(fid);
    if exist(probe_path, 'file') == 2
        delete(probe_path);
    end
end
end
