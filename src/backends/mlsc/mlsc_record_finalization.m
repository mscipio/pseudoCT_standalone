function result = mlsc_record_finalization(result, runtime, attempted, succeeded, detail)
%MLSC_RECORD_FINALIZATION Persist local-finalization status for one MLSC job.
%   RESULT = MLSC_RECORD_FINALIZATION(RESULT, RUNTIME, ATTEMPTED, SUCCEEDED,
%   DETAIL) appends the local finalization outcome to the already persisted
%   terminal MLSC evidence and writes it back to the durable evidence
%   destination.  This is intentionally separate from scheduler lifecycle
%   success: a completed Slurm job may still fail local finalization.
%
%   The actual shared-temp/progress-source cleanup outcome observed at
%   finalization time is recorded in RESULT.FINALIZATION (and persisted
%   evidence) as shared_temp/shared_temp_exists/source_path/source_exists
%   plus a bounded cleanup_outcome ('removed', 'preserved', or 'unknown')
%   with cleanup_detail, so successful removal after archival versus
%   preservation/failure remains diagnosable.  Observation only: existing
%   success-removes-source-after-archival and failure-preserves semantics
%   are unchanged and nothing is deleted here.
%
%   No credentials, SSH internals, or transport objects are accepted or
%   serialized.  Minimum supported MATLAB: R2010b.

if nargin < 2 || isempty(runtime)
    runtime = struct();
end
if nargin < 3 || isempty(attempted)
    attempted = false;
end
if nargin < 4 || isempty(succeeded)
    succeeded = false;
end
if nargin < 5 || isempty(detail)
    detail = '';
end
if ~isstruct(result) || numel(result) ~= 1 || ...
        ~isstruct(runtime) || numel(runtime) ~= 1
    error('pseudo_CT:MLSCFinalizationEvidence', ...
        'MLSC finalization evidence requires one result and runtime struct.');
end
if ~islogical(attempted) || ~isscalar(attempted) || ...
        ~islogical(succeeded) || ~isscalar(succeeded) || ~ischar(detail)
    error('pseudo_CT:MLSCFinalizationEvidence', ...
        'MLSC finalization status values are invalid.');
end

evidence_dir = '';
if isfield(runtime, 'evidence_dir') && ischar(runtime.evidence_dir)
    evidence_dir = runtime.evidence_dir;
elseif isfield(result, 'evidence_dir') && ischar(result.evidence_dir)
    evidence_dir = result.evidence_dir;
end

if ~attempted
    status = 'not_attempted';
elseif succeeded
    status = 'succeeded';
else
    status = 'failed';
end
evidence_path = '';
if ~isempty(evidence_dir)
    evidence_path = fullfile(evidence_dir, 'mlsc_evidence.mat');
end
cleanup_info = local_cleanup_outcome(result);
finalization = struct('attempted', attempted, 'succeeded', succeeded, ...
    'status', status, 'detail', detail, 'evidence_path', evidence_path, ...
    'shared_temp', cleanup_info.shared_temp, ...
    'shared_temp_exists', cleanup_info.shared_temp_exists, ...
    'source_path', cleanup_info.source_path, ...
    'source_exists', cleanup_info.source_exists, ...
    'cleanup_outcome', cleanup_info.cleanup_outcome, ...
    'cleanup_detail', cleanup_info.cleanup_detail);

if isfield(result, 'evidence') && isstruct(result.evidence)
    evidence = result.evidence;
else
    evidence = mlsc_evidence('init', struct());
end
evidence = mlsc_evidence('finalization', evidence, struct( ...
    'finalization', finalization, 'finalization_status', status, ...
    'finalization_completed_at', local_timestamp(), ...
    'workflow_finalization_succeeded', succeeded));
result.evidence = evidence;
result.finalization = finalization;
result.finalization_status = status;
result.finalization_evidence_path = evidence_path;
result.finalization_evidence_save_failed = false;

if isempty(evidence_dir)
    result.finalization_evidence_save_failed = true;
    return;
end
try
    mlsc_evidence('write', evidence_dir, evidence);
catch %#ok<CTCH>
    result.finalization_evidence_save_failed = true;
end
end

function info = local_cleanup_outcome(result)
info = struct('shared_temp', '', 'shared_temp_exists', false, ...
    'source_path', '', 'source_exists', false, ...
    'cleanup_outcome', 'unknown', ...
    'cleanup_detail', 'No shared temp was recorded.');
shared_temp = '';
source_path = '';
try
    if isstruct(result) && numel(result) == 1
        if isfield(result, 'shared_subject_temp')
            candidate = result.shared_subject_temp;
            if ischar(candidate) && ~isempty(candidate) && ...
                    size(candidate, 1) == 1 && ~any(candidate == char(0))
                info.shared_temp = candidate;
                shared_temp = candidate;
            end
        end
        if isfield(result, 'progress') && isstruct(result.progress) && ...
                numel(result.progress) == 1 && ...
                isfield(result.progress, 'source_path')
            candidate = result.progress.source_path;
            if ischar(candidate) && ~isempty(candidate) && ...
                    size(candidate, 1) == 1 && ~any(candidate == char(0))
                info.source_path = candidate;
                source_path = candidate;
            end
        end
    end
catch %#ok<CTCH>
end
if isempty(source_path) && ~isempty(shared_temp)
    try
        correlation = '';
        try
            if isstruct(result) && numel(result) == 1 && ...
                    isfield(result, 'submission_correlation_id')
                candidate = result.submission_correlation_id;
                if ischar(candidate) && size(candidate, 1) == 1 && ...
                        ~isempty(candidate)
                    correlation = candidate;
                end
            end
        catch %#ok<CTCH>
            correlation = '';
        end
        if ~isempty(correlation)
            try
                derived = mlsc_progress('path_for', shared_temp, ...
                    correlation);
            catch %#ok<CTCH>
                derived = mlsc_progress('path', shared_temp);
            end
        else
            derived = mlsc_progress('path', shared_temp);
        end
        if ischar(derived) && ~isempty(derived) && size(derived, 1) == 1
            info.source_path = derived;
            source_path = derived;
        end
    catch %#ok<CTCH>
    end
end
try
    if ~isempty(shared_temp) && exist(shared_temp, 'dir') == 7
        info.shared_temp_exists = true;
    end
catch %#ok<CTCH>
    info.shared_temp_exists = false;
end
try
    if ~isempty(source_path) && exist(source_path, 'file') == 2
        info.source_exists = true;
    end
catch %#ok<CTCH>
    info.source_exists = false;
end
try
    if isempty(shared_temp) && isempty(source_path)
        info.cleanup_outcome = 'unknown';
        info.cleanup_detail = 'No shared temp was recorded.';
    elseif ~info.shared_temp_exists && ~info.source_exists
        info.cleanup_outcome = 'removed';
        info.cleanup_detail = ...
            'Shared temp source was removed after archival.';
    else
        info.cleanup_outcome = 'preserved';
        info.cleanup_detail = 'Shared temp source was preserved.';
    end
catch %#ok<CTCH>
end
end

function stamp = local_timestamp()
stamp = [datestr(now, 'yyyy-mm-dd') 'T' datestr(now, 'HH:MM:SS')];
end
