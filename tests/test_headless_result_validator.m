function test_headless_result_validator()
local_exit_status_checks();
%TEST_HEADLESS_RESULT_VALIDATOR Focused MAT v2 result-contract checks.
%   Synthetic result records follow TMPDIR (tests/README.md);
%   no credentials, network, scheduler, or scientific processing is used.
%   Minimum supported MATLAB: R2010b.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'api'));
scratch_root = getenv('PSEUDOCT_TEST_SCRATCH');
if isempty(scratch_root)
    scratch_root = fullfile(root_dir, '.aria', 'scratch', 'unplanned', ...
        [datestr(now, 'yyyymmdd-HHMMSS') '-pseudoct-tests']);
end
if exist(scratch_root, 'dir') ~= 7
    mkdir(scratch_root);
end
scratch_dir = tempname(scratch_root);
mkdir(scratch_dir);
cleanup = onCleanup(@() local_cleanup(scratch_dir)); %#ok<NASGU>

invocation_id = '6d915c13-2bd1-4db1-a107-b1eab4d34c11';
profile = 'mlsc';
% The development-only artifact-root override is refused for a local profile by the
% headless validate request before any validation runs; the diagnostics name the
% shared identifier.
override_dir = fullfile(scratch_dir, 'artifact-root-local');
mkdir(override_dir);
override_request = local_validate_request('local', local_subject(), invocation_id);
override_request.current_artifact_root = fullfile(override_dir, 'dev-root');
request = override_request; %#ok<NASGU>
override_request_path = fullfile(override_dir, 'request.mat');
save(override_request_path, 'request', '-v6');
override_result = pseudo_CT_headless(override_request_path, ...
    fullfile(override_dir, 'result.mat'));
assert(strcmp(override_result.status, 'failed'), ...
    'A local profile accepted the development-only artifact-root override.');
diag_fid = fopen(fullfile(override_dir, 'pseudoct-headless-diagnostics.txt'), 'r');
assert(diag_fid ~= -1, 'The headless refusal wrote no diagnostics.');
diag_text = char(fread(diag_fid, inf, 'uint8')');
fclose(diag_fid);
assert(~isempty(strfind(diag_text, 'run_pseudo_CT:InvalidMlscCurrentOverride')), ...
    'The local artifact-root refusal did not use the shared identifier.');

% A successful configuration-only validation has no subject records but is
% still bound to the same invocation/profile as its resolved job.
validate_result = local_result('validate', invocation_id, profile);
validate_result.status = 'ready';
validate_result.error_code = '';
validate_result.error_message = '';
validate_result.diagnostics = struct('code', '', 'message', '');
validate_result.backend = 'mlsc';
validate_result.resolved_job = local_resolved_job( ...
    profile, invocation_id, struct([]));
validate_result.evidence = validate_result.resolved_job.validation_evidence;
local_expect_accept(scratch_dir, 'validate-ready', validate_result, ...
    invocation_id, profile);

% A failed local validation remains no-auth/no-submit and may have no job.
validate_failed = local_result('validate', invocation_id, profile);
validate_failed.error_code = 'INVALID_REQUEST';
validate_failed.error_message = 'The request or one-time credential handoff was invalid or consumed.';
validate_failed.diagnostics = struct('code', validate_failed.error_code, ...
    'message', validate_failed.error_message);
local_expect_accept(scratch_dir, 'validate-failed', validate_failed, ...
    invocation_id, profile);

% An accepted MLSC submit must carry the same invocation/profile binding and
% actual positive scheduler evidence before any scientific outcome is claimed.
subject = local_subject();
resolved_job = local_resolved_job(profile, invocation_id, subject);
submitted = local_result('submit', invocation_id, profile);
submitted.status = 'submitted';
submitted.error_code = '';
submitted.error_message = '';
submitted.diagnostics = struct('code', '', 'message', '');
submitted.authentication_status = 'authenticated';
submitted.submission_status = 'accepted';
submitted.group_account = 'synthetic-account';
submitted.job_ids = 31415;
submitted.dispatch_status = 'dispatched';
submitted.resolved_job = resolved_job;
submitted.evidence = struct('validation', resolved_job.validation_evidence, ...
    'warnings', struct([]));
local_expect_accept(scratch_dir, 'submit-accepted', submitted, ...
    invocation_id, profile);

completed = submitted;
completed.scientific_completion = 'completed';
local_expect_accept(scratch_dir, 'submit-completed', completed, ...
    invocation_id, profile);

completed_without_ack = submitted;
completed_without_ack.submission_status = 'unresolved';
completed_without_ack.job_ids = [];
completed_without_ack.scientific_completion = 'completed';
local_expect_reject(scratch_dir, 'completion-without-acknowledgement', ...
    completed_without_ack, invocation_id, profile);

mismatched_job = submitted;
mismatched_job.resolved_job.invocation_id = ...
    '71234567-89ab-cdef-0123-456789abcdef';
local_expect_reject(scratch_dir, 'nested-invocation-mismatch', ...
    mismatched_job, invocation_id, profile);

local_expect_reject(scratch_dir, 'top-level-invocation-mismatch', ...
    submitted, '71234567-89ab-cdef-0123-456789abcdef', profile);

% Validator agreement with the producer: validation never reports a submission
% failure, and submission never reports a validation failure.
validate_submit_code = local_result('validate', invocation_id, profile);
validate_submit_code.error_code = 'SUBMIT_FAILED';
validate_submit_code.error_message = ...
    'The requested operation failed; consult non-secret diagnostics.';
validate_submit_code.diagnostics = struct('code', validate_submit_code.error_code, ...
    'message', validate_submit_code.error_message);
local_expect_reject(scratch_dir, 'validate-submit-code', validate_submit_code, ...
    invocation_id, profile);

submit_validation_code = local_result('submit', invocation_id, profile);
submit_validation_code.resolved_job = resolved_job;
submit_validation_code.error_code = 'VALIDATION_FAILED';
submit_validation_code.error_message = ...
    'Local validation failed; no authentication, submission, or dispatch was attempted.';
submit_validation_code.diagnostics = struct('code', submit_validation_code.error_code, ...
    'message', submit_validation_code.error_message);
local_expect_reject(scratch_dir, 'submit-validation-code', submit_validation_code, ...
    invocation_id, profile);

% Public headless failures through the real entrypoint, each validated by the
% strict result validator. Requests are synthetic and offline: validation never
% authenticates, converts, or runs science.
headless_dir = fullfile(scratch_dir, 'headless');
mkdir(headless_dir);
missing_input = fullfile(headless_dir, 'missing-mprage.nii');
local_profile = 'local-mprage-only';

% Natural unclassified validation failure: this suite runs from a source checkout,
% which is development-only, so an application validation is refused before any
% input check. That refusal is not a named mapping. Confirm the underlying
% identifier directly so the case cannot pass on another failure.
natural = local_headless(headless_dir, 'validate-missing-input', ...
    local_validate_request(local_profile, missing_input, invocation_id), ...
    invocation_id, local_profile);
input_identifier = '';
try
    pseudo_CT_orchestrate('validate', struct('profile', local_profile, ...
        'subjects', missing_input, 'output_config', struct(), ...
        'invocation_id', invocation_id));
catch ME
    input_identifier = ME.identifier;
end
assert(strcmp(input_identifier, 'pseudo_CT:SourceCheckoutDevelopmentOnly'), ...
    'The natural validation case must be refused by the source-checkout guard.');
local_assert_validation_failure(natural);
assert(strcmp(natural.error_code, 'VALIDATION_FAILED'), ...
    'An unclassified validation failure must report VALIDATION_FAILED.');

% Named-mapping and submit-failure cases. A test-only pseudo_CT_orchestrate in
% the current folder shadows the repository function (the current folder takes
% precedence over the path), so no production hook is required.
seam_dir = fullfile(scratch_dir, 'orchestrator-seam');
mkdir(seam_dir);
local_write_text(fullfile(seam_dir, 'pseudo_CT_orchestrate.m'), { ...
    'function value = pseudo_CT_orchestrate(operation, request) %#ok<INUSD>'; ...
    'value = [];'; ...
    'if strcmp(operation, ''validate'')'; ...
    '    error(''pseudo_CT:InvalidProfile'', ''Injected invalid profile.'');'; ...
    'end'; ...
    'error(''pseudo_CT:SyntheticSubmit'', ''Injected unclassified submit failure.'');'});
original_dir = pwd;
restore_dir = onCleanup(@() cd(original_dir)); %#ok<NASGU>
cd(seam_dir);
invalid_profile = local_headless(headless_dir, 'seam-invalid-profile', ...
    local_validate_request(local_profile, missing_input, invocation_id), ...
    invocation_id, local_profile);
submit_failed = local_headless(headless_dir, 'seam-submit', ...
    local_submit_request('local', invocation_id), invocation_id, 'local');
cd(original_dir);

assert(strcmp(invalid_profile.error_code, 'PROFILE_NOT_ALLOWED'), ...
    'A known invalid profile failure must keep the PROFILE_NOT_ALLOWED mapping.');
local_assert_validation_failure(invalid_profile);
assert(strcmp(submit_failed.action, 'submit') && ...
    strcmp(submit_failed.status, 'failed') && ...
    strcmp(submit_failed.error_code, 'SUBMIT_FAILED') && ...
    strcmp(submit_failed.dispatch_status, 'not_dispatched'), ...
    'An unclassified submit failure must keep the SUBMIT_FAILED mapping.');

fprintf('Headless v2 result-contract cases passed; synthetic MATs: %s\n', ...
    scratch_dir);
end

function local_exit_status_checks()
%LOCAL_EXIT_STATUS_CHECKS Raw headless exit status for validated result shapes.
%   A submission returned by the scheduler is not completion: only a verified
%   'completed' scientific result exits 0 (local and remote alike).
addpath(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'src', 'cli'), '-begin');
invocation_id = '6f1f5f0e-2b7a-4c1d-9e3a-0123456789ab';
submitted = local_result('submit', invocation_id, 'mlsc');
submitted.status = 'submitted';
submitted.error_code = '';
submitted.error_message = '';
submitted.dispatch_status = 'dispatched';
submitted.submission_status = 'accepted';
submitted.authentication_status = 'authenticated';
submitted.job_ids = 31415;
submitted.scientific_completion = 'not_observed';
assert(pseudoct_headless_status(submitted) == 3, ...
    'A remote submission without verified completion must exit 3.');
submitted.scientific_completion = 'completed';
assert(pseudoct_headless_status(submitted) == 0, ...
    'A remote submission with verified completion must exit 0.');
submitted.scientific_completion = 'failed';
assert(pseudoct_headless_status(submitted) == 3, ...
    'A remote submission with a failed scientific result must exit 3.');

local_submitted = submitted;
local_submitted.backend = 'local';
local_submitted.authentication_status = 'not_attempted';
local_submitted.submission_status = 'not_attempted';
local_submitted.job_ids = [];
local_submitted.scientific_completion = 'not_observed';
assert(pseudoct_headless_status(local_submitted) == 3, ...
    'An unverified local submission must keep exit 3.');
local_submitted.scientific_completion = 'completed';
assert(pseudoct_headless_status(local_submitted) == 0, ...
    'A verified local submission must exit 0.');

ready = local_result('validate', invocation_id, 'local');
ready.status = 'ready';
ready.error_code = '';
ready.scientific_completion = 'not_applicable';
ready.dispatch_status = 'not_dispatched';
assert(pseudoct_headless_status(ready) == 0, 'A ready validation must exit 0.');
end

function result = local_result(action, invocation_id, profile)
result = struct('schema', 'pseudoCT.headless-result/v2', ...
    'invocation_id', invocation_id, 'action', action, 'profile', profile, ...
    'status', 'failed', 'error_code', 'INVALID_REQUEST', ...
    'error_message', 'The request or one-time credential handoff was invalid or consumed.', ...
    'authentication_status', 'not_attempted', ...
    'submission_status', 'not_attempted', 'backend', 'mlsc', ...
    'group_account', '', 'job_ids', [], ...
    'scientific_completion', 'not_applicable', ...
    'dispatch_status', 'not_dispatched', 'resolved_job', struct(), ...
    'evidence', struct(), ...
    'diagnostics', struct('code', 'INVALID_REQUEST', ...
    'message', 'The request or one-time credential handoff was invalid or consumed.'));
end

function job = local_resolved_job(profile, invocation_id, subjects)
job = struct('schema', 'pseudoCT.resolved-job/v1', ...
    'profile', profile, 'invocation_id', invocation_id, 'subjects', subjects, ...
    'options', struct('correct_aliasing', true, ...
    'recenter_before_normalization', false), ...
    'output_config', struct('layout', 'profile-default'), ...
    'artifact_identity', struct(), 'current_artifact_root', '', ...
    'validation_evidence', struct('local_only', true, 'checks', {{'inputs'}}, ...
    'validated_at', '2026-10-30T00:00:00'));
end

function subject = local_subject()
subject = struct('mprage_fn', '/scratch/subject/MR/MPRAGE/one.dcm', ...
    'umap_fn', '/scratch/subject/MR/UMAP/one.dcm', ...
    'correct_aliasing', true, 'recenter_before_normalization', false, ...
    'io_policy', struct('reference', 'umap-required', ...
    'output', 'nifti-and-dicom', 'gui', 'mMR'), ...
    'processing_dir', '/scratch/subject/MR_PET', ...
    'temp_dir', '/scratch/subject/MR_PET/tmp', ...
    'save_dir', '/scratch/subject/MR/pseudo_muMAP', ...
    'mprage_identity', struct('path', '/scratch/subject/MR/MPRAGE/one.dcm', ...
    'kind', 'file', 'bytes', 1, 'datenum', 1, 'sha256', 'synthetic', ...
    'entries', {{}}), ...
    'umap_identity', struct('path', '/scratch/subject/MR/UMAP/one.dcm', ...
    'kind', 'file', 'bytes', 1, 'datenum', 1, 'sha256', 'synthetic', ...
    'entries', {{}}), 'umap_resolution', 'explicit');
end

function local_expect_accept(directory, name, result, invocation_id, profile)
path_name = fullfile(directory, [name '.mat']);
save(path_name, 'result', '-v6');
validated = pseudo_CT_validate_headless_result(path_name, ...
    invocation_id, profile);
assert(isequal(validated, result), ...
    'Validator changed an accepted synthetic v2 result.');
end

function local_expect_reject(directory, name, result, invocation_id, profile)
path_name = fullfile(directory, [name '.mat']);
save(path_name, 'result', '-v6');
rejected = false;
try
    pseudo_CT_validate_headless_result(path_name, invocation_id, profile);
catch ME
    rejected = any(strcmp(ME.identifier, ...
        {'pseudo_CT:HeadlessResult'; 'pseudo_CT:HeadlessResultBinding'}));
end
assert(rejected, 'Validator accepted an inconsistent synthetic v2 result.');
end

function result = local_headless(directory, name, request, invocation_id, profile)
%LOCAL_HEADLESS Run the public entrypoint and validate its saved result.
request_path = fullfile(directory, [name '-request.mat']);
result_path = fullfile(directory, [name '-result.mat']);
save(request_path, 'request', '-v6');
pseudo_CT_headless(request_path, result_path);
result = pseudo_CT_validate_headless_result(result_path, invocation_id, profile);
end

function request = local_validate_request(profile, subject, invocation_id)
request = struct('schema', 'pseudoCT.headless-request/v2', ...
    'invocation_id', invocation_id, 'action', 'validate', 'profile', profile, ...
    'subjects', subject, 'umap_files', {{}}, 'output_config', struct(), ...
    'options', struct(), 'resolved_job', struct(), 'group_account', '', ...
    'credential_handoff', '', 'host_key_file', '', 'current_artifact_root', '');
end

function request = local_submit_request(profile, invocation_id)
job = local_resolved_job(profile, invocation_id, local_subject());
request = struct('schema', 'pseudoCT.headless-request/v2', ...
    'invocation_id', invocation_id, 'action', 'submit', 'profile', profile, ...
    'subjects', [], 'umap_files', {{}}, 'output_config', struct(), ...
    'options', struct(), 'resolved_job', job, 'group_account', '', ...
    'credential_handoff', '', 'host_key_file', '', 'current_artifact_root', '');
end

function local_assert_validation_failure(result)
%LOCAL_ASSERT_VALIDATION_FAILURE Validation claims no auth, submit, job, or science.
assert(strcmp(result.action, 'validate') && strcmp(result.status, 'failed') && ...
    strcmp(result.authentication_status, 'not_attempted') && ...
    strcmp(result.submission_status, 'not_attempted') && ...
    strcmp(result.dispatch_status, 'not_dispatched') && isempty(result.job_ids) && ...
    strcmp(result.scientific_completion, 'not_applicable') && ...
    isempty(fieldnames(result.resolved_job)), ...
    'A validation failure must not claim authentication, submission, dispatch, or science.');
end

function local_write_text(path_name, lines)
fid = fopen(path_name, 'w');
if fid == -1
    error('test_headless_result_validator:Write', 'Cannot write %s.', path_name);
end
cleanup_fid = onCleanup(@() fclose(fid)); %#ok<NASGU>
for ii = 1:length(lines)
    fprintf(fid, '%s\n', lines{ii});
end
end

function local_cleanup(directory)
if exist(directory, 'dir') == 7
    rmdir(directory, 's');
end
end
