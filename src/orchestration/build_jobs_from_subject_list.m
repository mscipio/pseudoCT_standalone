function [jobs, stats] = build_jobs_from_subject_list(subject_list, correct_aliasing, ...
    io_policy, recenter_before_normalization, umap_files)
%BUILD_JOBS_FROM_SUBJECT_LIST Build job structs from a list of MPRAGE paths.
%   JOBS = BUILD_JOBS_FROM_SUBJECT_LIST(SUBJECT_LIST, CORRECT_ALIASING)
%   creates a struct array from the given MPRAGE file list.
%   A third IO_POLICY argument selects the validated reference policy. When
%   omitted, the historical UMAP-required behavior is retained.
%   An optional fourth RECENTER_BEFORE_NORMALIZATION argument is applied to
%   every job. When omitted, the historical disabled behavior is retained.
%
%   SUBJECT_LIST is a char matrix with one MPRAGE path per row.
%   CORRECT_ALIASING and RECENTER_BEFORE_NORMALIZATION are scalar numeric or
%   logical flags applied independently to every job.
%   An optional fifth UMAP_FILES input is paired positionally with subjects;
%   omitted or empty entries use the shared local discovery routine. Explicit
%   non-empty paths are preserved and never replaced by discovery.
%
%   Each subject is checked for a UMAP reference via
%   PSEUDO_CT_DISCOVER_UTE_UMAP. Subjects without a detected UMAP are
%   skipped with a console message.
%
%   Returns a struct array with fields: mprage_fn, umap_fn, correct_aliasing,
%   recenter_before_normalization.
%   Returns empty when no valid subjects are found.
%
%   This function is the single subject-list job construction path.
%
%   Minimum supported MATLAB: R2010b.

if nargin < 3 || isempty(io_policy)
    io_policy.reference = 'umap-required';
    io_policy.output = 'nifti-and-dicom';
    io_policy.gui = 'mMR';
end
if ~isstruct(io_policy) || ~isfield(io_policy, 'reference')
    error('pseudo_CT:InvalidProfile', 'A valid input/output policy is required.');
end
if nargin < 4 || isempty(recenter_before_normalization)
    recenter_before_normalization = false;
end
if nargin < 5
    umap_files = [];
    umap_files_supplied = false;
else
    umap_files_supplied = ~isempty(umap_files);
end
correct_aliasing = validate_aliasing(correct_aliasing);
recenter_before_normalization = validate_recentering( ...
    recenter_before_normalization);

jobs = struct('mprage_fn', {}, 'umap_fn', {}, 'correct_aliasing', {}, ...
    'recenter_before_normalization', {}, 'io_policy', {});
stats = struct('requested', 0, 'skipped', 0, 'skipped_subjects', {{}});

if ischar(subject_list) && isrow(subject_list)
    subject_list = {subject_list};
elseif ischar(subject_list)
    subject_list = cellstr(subject_list);
elseif ~iscell(subject_list)
    error('pseudo_CT:OrchestrationInput', ...
        'Subject inputs must be a path or cell array of paths.');
end

subject_count = 0;
for ii = 1:length(subject_list)
    if ~ischar(subject_list{ii}) || size(subject_list{ii}, 1) ~= 1 || ...
            isempty(strtrim(subject_list{ii}))
        error('pseudo_CT:OrchestrationInput', ...
            'Each subject input must be a non-empty file path.');
    end
    subject_count = subject_count + 1;
end
if umap_files_supplied
    if ischar(umap_files)
        if size(umap_files, 1) == 1
            umap_files = {umap_files};
        else
            umap_files = cellstr(umap_files);
        end
    end
    if ~iscell(umap_files) || length(umap_files) ~= subject_count
        error('pseudo_CT:OrchestrationInput', ...
            'UMAP inputs must match the requested subject list positionally.');
    end
    if strcmp(io_policy.reference, 'none') && ...
            any(~cellfun('isempty', umap_files))
        error('pseudo_CT:OrchestrationInput', ...
            'This MPRAGE-only profile does not accept UMAP inputs.');
    end
end

kk = 0;
for ii = 1:length(subject_list)
    mprage_fn = subject_list{ii};
    stats.requested = stats.requested + 1;
    if strcmp(io_policy.reference, 'none')
        if exist(mprage_fn, 'file') ~= 2
            stats.skipped = stats.skipped + 1;
            stats.skipped_subjects{end + 1} = mprage_fn;
            continue;
        end
        umap_fn = '';
    else
        umap_fn = '';
        if umap_files_supplied && ~isempty(umap_files{stats.requested})
            umap_fn = umap_files{stats.requested};
            if ~ischar(umap_fn) || size(umap_fn, 1) ~= 1 || ...
                    any(umap_fn == char(0)) || exist(umap_fn, 'file') ~= 2
                error('pseudo_CT:OrchestrationInput', ...
                    'An explicit UMAP path is unavailable; no autodiscovery fallback was used.');
            end
        else
            [~, umap_fn] = pseudo_CT_discover_ute_umap(mprage_fn);
        end
        if ~ischar(umap_fn) || exist(umap_fn, 'file') ~= 2
            stats.skipped = stats.skipped + 1;
            stats.skipped_subjects{end + 1} = mprage_fn;
            continue;
        end
    end
    kk = kk + 1;
    jobs(kk).mprage_fn = mprage_fn;
    jobs(kk).umap_fn = umap_fn;
    jobs(kk).correct_aliasing = correct_aliasing;
    jobs(kk).recenter_before_normalization = recenter_before_normalization;
    jobs(kk).io_policy = io_policy;
end

end

function value = validate_aliasing(value)
if ~(isnumeric(value) || islogical(value)) || ~isscalar(value) || ...
        ~ismember(double(value), [0 1])
    error('pseudo_CT:InvalidAliasing', ...
        'Aliasing correction must be a scalar numeric or logical 0 or 1.');
end
value = logical(value);
end

function value = validate_recentering(value)
if ischar(value)
    normalized = lower(strtrim(value));
    if ismember(normalized, {'yes'; 'true'; 'on'; '1'})
        value = true;
    elseif ismember(normalized, {'no'; 'false'; 'off'; '0'})
        value = false;
    else
        error('pseudo_CT:InvalidRecentering', ...
            'Recentering must be Yes/No or a scalar logical 0 or 1.');
    end
elseif ~(isnumeric(value) || islogical(value)) || ~isscalar(value) || ...
        ~ismember(double(value), [0 1])
    error('pseudo_CT:InvalidRecentering', ...
        'Recentering must be Yes/No or a scalar logical 0 or 1.');
else
    value = logical(value);
end
end
