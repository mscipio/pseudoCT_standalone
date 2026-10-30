function test_e2e_partial_artifacts
%TEST_E2E_PARTIAL_ARTIFACTS Focused coverage/verdict tests for the E2E comparator.

spm_root = '/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/spm8-r6313';
tests_dir = fileparts(mfilename('fullpath'));
repo = fileparts(tests_dir);
addpath(spm_root);
addpath(tests_dir);
addpath(fullfile(repo, 'scripts'));

stamp = clock; %#ok<CLOCK> R2010b-compatible unique worktree scratch directory.
date_text = sprintf('%04d-%02d-%02d', stamp(1), stamp(2), stamp(3));
time_text = sprintf('%02d%02d%02d', stamp(4), stamp(5), floor(stamp(6)));
scratch_parent = fullfile(repo, 'scratch', date_text);
if exist(scratch_parent, 'dir') ~= 7
    mkdir(scratch_parent);
end
root = fullfile(scratch_parent, [time_text '-e2e-partial-artifacts']);
suffix = 0;
while exist(root, 'dir') == 7
    suffix = suffix + 1;
    root = fullfile(scratch_parent, sprintf('%s-e2e-partial-artifacts-%d', ...
        time_text, suffix));
end
mkdir(root);
cleanup = onCleanup(@() cleanup_fixture(root));

reference = fullfile(root, 'reference');
create_complete_tree(reference, 1);
targets = {'missing-tmp', 'empty-dicom', 'missing-nifti', ...
    'corrupt-nifti', 'mismatch-partial', 'complete-equal'};
target_paths = cell(size(targets));
for i = 1:numel(targets)
    target_paths{i} = fullfile(root, targets{i});
    copyfile(reference, target_paths{i});
end

rmdir(fullfile(target_paths{1}, 'MR_PET', 'tmp'), 's');
delete(fullfile(target_paths{2}, 'MR', 'pseudo_muMAP', '0001.dcm'));
delete(fullfile(target_paths{3}, 'MR_PET', 'tmp', 'y_mprage_normalized_repos.nii'));
write_bytes(fullfile(target_paths{4}, 'MR_PET', 'tmp', 'mprage.nii'), uint8('not a nifti'));
rmdir(fullfile(target_paths{5}, 'MR_PET', 'tmp'), 's');
write_nifti(fullfile(target_paths{5}, 'MR_PET', 'att_map.nii'), 2);
delete(fullfile(target_paths{6}, 'MR_PET', 'tmp', 'new_segment_01-Jan-2020_batch.mat'));
write_marker_mat(fullfile(target_paths{6}, 'MR_PET', 'tmp', 'new_segment_02-Jan-2020_batch.mat'));

summary = run_e2e_semantic_comparison(reference, target_paths, fullfile(root, 'reports'));
summary_text = fileread(summary.summary_report);
assert(~isempty(strfind(summary_text, ['SPM NIfTI overrides: `' fullfile(repo, 'src', 'science', 'overrides') '`']))); %#ok<STREMP>
assert(isempty(strfind(summary_text, 'pseudoCT_standalone-2.6.4/vers'))); %#ok<STREMP>

missing_tmp = target_result(summary, 'missing-tmp');
assert(strcmp(missing_tmp.verdict, 'INCONCLUSIVE - PARTIAL EVIDENCE'));
assert(strcmp(missing_tmp.coverage(2).status, 'UNAVAILABLE'));
assert(missing_tmp.coverage(1).complete && missing_tmp.coverage(3).complete);

empty_dicom = target_result(summary, 'empty-dicom');
assert(strcmp(empty_dicom.verdict, 'INCONCLUSIVE - PARTIAL EVIDENCE'));
assert(strcmp(empty_dicom.coverage(3).status, 'EMPTY'));

missing_nifti = target_result(summary, 'missing-nifti');
assert(strcmp(missing_nifti.verdict, 'INCONCLUSIVE - PARTIAL EVIDENCE'));
assert(any(strcmp(missing_nifti.coverage(2).required_reference_only, ...
    'y_mprage_normalized_repos.nii')));

corrupt_nifti = target_result(summary, 'corrupt-nifti');
assert(strcmp(corrupt_nifti.verdict, 'INCONCLUSIVE - PARTIAL EVIDENCE'));
assert(strcmp(corrupt_nifti.coverage(2).status, 'READ_ERROR'));
assert(~isempty(corrupt_nifti.coverage(2).read_errors));

mismatch_partial = target_result(summary, 'mismatch-partial');
assert(strcmp(mismatch_partial.verdict, 'BEHAVIORALLY DIVERGENT'));
assert(strcmp(mismatch_partial.first_divergence, 'MR_PET/att_map.nii'));
assert(~mismatch_partial.coverage_complete);

complete_equal = target_result(summary, 'complete-equal');
assert(strcmp(complete_equal.verdict, 'BEHAVIORALLY EQUIVALENT within tolerance'));
assert(complete_equal.coverage_complete);
assert(strcmp(summary.status, 'completed_with_partial_evidence'));

corrupt_report = fileread(corrupt_nifti.report_path);
assert(~isempty(strfind(corrupt_report, 'READ_ERROR'))); %#ok<STREMP>
empty_report = fileread(empty_dicom.report_path);
assert(~isempty(strfind(empty_report, 'no readable common slices'))); %#ok<STREMP>

fprintf('PASS: 6 E2E partial-artifact scenarios\n');
clear cleanup
cleanup_fixture(root);
end

function create_complete_tree(root, value)
mkdir(fullfile(root, 'MR_PET', 'tmp'));
mkdir(fullfile(root, 'MR', 'pseudo_muMAP'));
write_nifti(fullfile(root, 'MR_PET', 'att_map.nii'), value);
write_nifti(fullfile(root, 'MR_PET', 'tmp', 'mprage.nii'), value);
write_nifti(fullfile(root, 'MR_PET', 'tmp', 'y_mprage_normalized_repos.nii'), value);
dicomwrite(uint16([1 2; 3 4]), fullfile(root, 'MR', 'pseudo_muMAP', '0001.dcm'));
write_marker_mat(fullfile(root, 'MR_PET', 'tmp', 'new_segment_01-Jan-2020_batch.mat'));
end

function write_nifti(path, value)
header = struct('fname', path, 'dim', [2 2 2], 'dt', [16 0], ...
    'mat', eye(4), 'pinfo', [1; 0; 0]);
spm_write_vol(header, ones(2, 2, 2) * value);
end

function write_bytes(path, bytes)
fid = fopen(path, 'wb');
assert(fid ~= -1, 'Cannot write %s', path);
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, bytes, 'uint8');
end

function write_marker_mat(path)
marker = 1;
save(path, 'marker');
end

function result = target_result(summary, label)
idx = find(strcmp({summary.targets.label}, label), 1);
assert(~isempty(idx), 'Missing target result: %s', label);
result = summary.targets(idx);
end

function cleanup_fixture(root)
if exist(root, 'dir') == 7
    rmdir(root, 's');
end
end
