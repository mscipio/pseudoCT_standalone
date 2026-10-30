function test_headless_result_validator()
%TEST_HEADLESS_RESULT_VALIDATOR Focused MAT v2 result-contract checks.
%   Synthetic result records are confined to unique worktree-local scratch;
%   no credentials, network, scheduler, or scientific processing is used.
%   Minimum supported MATLAB: R2010b.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'api'));
stamp = clock; %#ok<CLOCK> R2010b-compatible scratch timestamp.
date_text = sprintf('%04d-%02d-%02d', stamp(1), stamp(2), stamp(3));
time_text = sprintf('%02d%02d%02d', stamp(4), stamp(5), floor(stamp(6)));
scratch_parent = fullfile(root_dir, 'scratch', date_text);
if exist(scratch_parent, 'dir') ~= 7
    mkdir(scratch_parent);
end
scratch_dir = fullfile(scratch_parent, ...
    [time_text '-headless-result-validator']);
suffix = 0;
while exist(scratch_dir, 'dir') == 7
    suffix = suffix + 1;
    scratch_dir = fullfile(scratch_parent, sprintf( ...
        '%s-headless-result-validator-%d', time_text, suffix));
end
mkdir(scratch_dir);

invocation_id = '6d915c13-2bd1-4db1-a107-b1eab4d34c11';
profile = 'mlsc-legacy';

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

fprintf('Headless v2 result-contract cases passed; synthetic MATs: %s\n', ...
    scratch_dir);
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
