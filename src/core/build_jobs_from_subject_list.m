function jobs = build_jobs_from_subject_list(subject_list, correct_aliasing)
%BUILD_JOBS_FROM_SUBJECT_LIST Build job structs from a list of MPRAGE paths.
%   JOBS = BUILD_JOBS_FROM_SUBJECT_LIST(SUBJECT_LIST, CORRECT_ALIASING)
%   creates a struct array from the given MPRAGE file list.
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

jobs = struct('mprage_fn', {}, 'umap_fn', {}, 'correct_aliasing', {});

if ischar(subject_list) && isrow(subject_list)
    subject_list = char(subject_list);
end

kk = 0;
for ii = 1:size(subject_list, 1)
    mprage_fn = strtrim(subject_list(ii, :));
    if isempty(mprage_fn)
        continue;
    end
    [ute_fn, umap_fn] = pseudo_CT_auto_discover_ute_umap(mprage_fn); %#ok<NASGU>
    if ~ischar(umap_fn) || exist(umap_fn, 'file') ~= 2
        disp(sprintf('Skipping subject because no UMAP reference was found:\n%s\n', mprage_fn));
        continue;
    end
    kk = kk + 1;
    jobs(kk).mprage_fn = mprage_fn;
    jobs(kk).umap_fn = umap_fn;
    jobs(kk).correct_aliasing = correct_aliasing;
end

end
