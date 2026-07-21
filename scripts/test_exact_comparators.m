function test_exact_comparators()
%TEST_EXACT_COMPARATORS Synthetic R2010b-compatible comparator fixtures.

scripts_dir = fileparts(mfilename('fullpath'));
addpath(scripts_dir);
cleanup_path = onCleanup(@() rmpath(scripts_dir)); %#ok<NASGU>

temp_dir = tempname;
mkdir(temp_dir);
cleanup_temp = onCleanup(@() rmdir(temp_dir, 's')); %#ok<NASGU>

left_file = fullfile(temp_dir, 'left.mat');
right_file = fullfile(temp_dir, 'right.mat');
payload = struct('values', single([1 NaN Inf -Inf]), ...
    'nested', {{int16([2 3]), true}}, 'path', '/left/input.nii');
save(left_file, 'payload');
payload.path = '/right/input.nii';
save(right_file, 'payload');

path_map = {'/left/input.nii', 'same-content'; ...
            '/right/input.nii', 'same-content'};
[is_equal, report] = pct_compare_semantic_mat(left_file, right_file, path_map, 5);
assert(is_equal && report.equal);

right = load(right_file);
right.payload.values(1) = single(4);
[is_equal, report] = pct_compare_semantic_mat(load(left_file), right, path_map, 1);
assert(~is_equal && strcmp(report.first_difference.state, 'finite_value'));
assert(report.limit_reached && numel(report.differences) == 1);

header = struct('dim', [2 2 1], 'dt', [4 0], ...
    'pinfo', [1; 0; 0], 'mat', eye(4));
artifact = struct('header', header, 'raw', int16([1 2; 3 4]), ...
    'scaled', single([1 2; 3 4]));
[is_equal, report] = pct_compare_nifti_exact(artifact, artifact);
assert(is_equal && report.equal);

changed = artifact;
changed.scaled(4) = single(5);
[is_equal, report] = pct_compare_nifti_exact(artifact, changed, 2);
assert(~is_equal && ~isempty(report.differences));

missing = artifact;
missing.header = rmfield(missing.header, 'mat');
[is_equal, report] = pct_compare_nifti_exact(artifact, missing);
assert(~is_equal && strcmp(report.first_difference.state, 'required_field'));

fprintf('Exact comparator tests passed.\n');
end
