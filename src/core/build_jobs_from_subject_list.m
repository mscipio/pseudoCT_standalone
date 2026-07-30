function [jobs, stats] = build_jobs_from_subject_list(subject_list, correct_aliasing, io_policy)
%BUILD_JOBS_FROM_SUBJECT_LIST Build job structs from a list of MPRAGE paths.
%   JOBS = BUILD_JOBS_FROM_SUBJECT_LIST(SUBJECT_LIST, CORRECT_ALIASING)
%   creates a struct array from the given MPRAGE file list.
%   A third IO_POLICY argument selects the validated reference policy. When
%   omitted, the historical UMAP-required behavior is retained.
%
%   SUBJECT_LIST is a char matrix with one MPRAGE path per row.
%   CORRECT_ALIASING is a numeric scalar (0 or 1) applied to every job.
%
%   Each subject is checked for a UMAP reference via
%   PSEUDO_CT_AUTO_DISCOVER_UTE_UMAP. Subjects without a detected UMAP are
%   skipped with a console message.
%
%   Returns a struct array with fields: mprage_fn, umap_fn, correct_aliasing.
%   Returns empty when no valid subjects are found.
%
%   This function is extracted from the now-deprecated entrypoints
%   run_pseudo_CT_local.m and run_pseudo_CT_launchpad.m, where it was
%   duplicated as local_build_jobs_from_subject_list and
%   launchpad_build_jobs_from_subject_list respectively.
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

jobs = struct('mprage_fn', {}, 'umap_fn', {}, 'correct_aliasing', {}, ...
    'io_policy', {});
stats = struct('requested', 0, 'skipped', 0, 'skipped_subjects', {{}});

if ischar(subject_list) && isrow(subject_list)
    subject_list = char(subject_list);
end

kk = 0;
for ii = 1:size(subject_list, 1)
    mprage_fn = strtrim(subject_list(ii, :));
    if isempty(mprage_fn)
        continue;
    end
    stats.requested = stats.requested + 1;
    if strcmp(io_policy.reference, 'none')
        if exist(mprage_fn, 'file') ~= 2
            stats.skipped = stats.skipped + 1;
            stats.skipped_subjects{end + 1} = mprage_fn;
            continue;
        end
        umap_fn = '';
    else
        [ute_fn, umap_fn] = pseudo_CT_auto_discover_ute_umap(mprage_fn); %#ok<NASGU>
        if ~ischar(umap_fn) || exist(umap_fn, 'file') ~= 2
            % Legacy output: disp(sprintf('Skipping subject because no UMAP reference was found:\n%s\n', mprage_fn));
            stats.skipped = stats.skipped + 1;
            stats.skipped_subjects{end + 1} = mprage_fn;
            continue;
        end
    end
    kk = kk + 1;
    jobs(kk).mprage_fn = mprage_fn;
    jobs(kk).umap_fn = umap_fn;
    jobs(kk).correct_aliasing = correct_aliasing;
    jobs(kk).io_policy = io_policy;
end

end
