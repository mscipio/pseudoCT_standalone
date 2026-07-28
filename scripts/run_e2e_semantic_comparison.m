function summary = run_e2e_semantic_comparison(reference_root, target_roots, out_root)
%RUN_E2E_SEMANTIC_COMPARISON Compare target output trees with one reference.
%   summary = run_e2e_semantic_comparison(reference_root, target_roots)
%   summary = run_e2e_semantic_comparison(reference_root, ...
%       {'/data/target_a', '/data/target_b'}, '/tmp/comparison')
%   TARGET_ROOTS may also be one char path or a char matrix with one path
%   per row.  The output directory defaults to the historical location.

if nargin < 2 || nargin > 3
    error('run_e2e_semantic_comparison:InvalidInputs', ...
        'Expected reference_root, target_roots, and optional out_root.');
end
if ~ischar(reference_root) || size(reference_root, 1) ~= 1 || isempty(strtrim(reference_root))
    error('run_e2e_semantic_comparison:InvalidReference', ...
        'reference_root must be a non-empty char path.');
end
reference_root = strtrim(reference_root);

[target_roots, target_labels] = normalize_target_roots(target_roots);
if nargin < 3 || isempty(out_root)
    out_root = '/home/scratch/opencode/e2e-comparison';
elseif ~ischar(out_root) || size(out_root, 1) ~= 1 || isempty(strtrim(out_root))
    error('run_e2e_semantic_comparison:InvalidOutput', ...
        'out_root must be a non-empty char path.');
else
    out_root = strtrim(out_root);
end

repo = fileparts(fileparts(mfilename('fullpath')));
spm_root = '/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/spm8-r6313';
spm_override_root = fullfile(repo, 'vers');
atlas_root = '/usr/pubsw/packages/mrpet/standalone_apps/PseudoCT/Batch_atlas';
stages = {'MR_PET', 'MR_PET/tmp', 'MR/pseudo_muMAP'};
stage_ids = {'mr_pet', 'tmp', 'dicom'};
tol = 1e-6;

validate_directory(reference_root, 'reference root');
for t = 1:numel(target_roots)
    validate_directory(target_roots{t}, ['target ' target_labels{t} ' root']);
end
validate_directory(spm_root, 'SPM root');
validate_directory(spm_override_root, 'SPM override root');
validate_directory(atlas_root, 'Batch_atlas root');
validate_directory(fullfile(repo, 'scripts'), 'repository scripts root');
if exist(out_root, 'dir') ~= 7
    [created, message] = mkdir(out_root);
    if ~created
        error('run_e2e_semantic_comparison:OutputCreationFailed', ...
            'Cannot create output directory %s: %s', out_root, message);
    end
end

addpath(spm_root);
addpath(spm_override_root);
addpath(fullfile(repo, 'scripts'));
addpath(atlas_root);

summary_path = fullfile(out_root, 'summary.md');
sfid = fopen(summary_path, 'w');
assert(sfid ~= -1, 'Cannot create %s', summary_path);
cleanup_summary = onCleanup(@() fclose(sfid));
fprintf(sfid, '# pseudo-CT E2E semantic comparison\n\n');
fprintf(sfid, '- Reference output tree: `%s`\n', reference_root);
fprintf(sfid, '- Target output trees: %d\n', numel(target_roots));
fprintf(sfid, '- MATLAB: `%s`\n', version);
fprintf(sfid, '- SPM: `%s`\n', spm_root);
fprintf(sfid, '- SPM NIfTI overrides: `%s`\n', spm_override_root);
fprintf(sfid, '- Batch_atlas: `%s`\n', atlas_root);
fprintf(sfid, '- Comparator: `%s`\n', fullfile(repo, 'scripts', 'diff_entrypoint_runs.m'));
fprintf(sfid, '- NIfTI tolerance used by repository comparator: `%.9g`\n\n', tol);

empty_result = struct('label', '', 'target_root', '', 'verdict', '', ...
    'first_divergence', '', 'first_class', '', 'dicom_verdict', '', ...
    'report_path', '', 'comparator_txt', [], 'comparator_csv', [], ...
    'coverage_complete', false, 'coverage_status', '', 'coverage', []);
target_results = repmat(empty_result, 1, numel(target_roots));
artifact_paths = {summary_path};

for t = 1:numel(target_roots)
    target_root = target_roots{t};
    target_label = target_labels{t};
    report_path = fullfile(out_root, [target_label '_semantic_report.md']);
    txt_paths = cell(1, numel(stages));
    csv_paths = cell(1, numel(stages));
    coverage = inspect_coverage(target_root, reference_root, stages, stage_ids);

    for s = 1:numel(stages)
        left = fullfile(target_root, stages{s}); %#ok<NASGU>
        right = fullfile(reference_root, stages{s}); %#ok<NASGU>
        txt_path = fullfile(out_root, sprintf('%s_%s_comparator.txt', target_label, stage_ids{s}));
        csv_path = fullfile(out_root, sprintf('%s_%s_comparator.csv', target_label, stage_ids{s}));
        if coverage(s).target_available && coverage(s).reference_available
            captured = evalc('diff_entrypoint_runs(left, right, ''Tolerance'', tol, ''OutputCSV'', csv_path, ''Order'', ''timestamp'');');
            write_text(txt_path, genericize_comparator_text(captured));
            genericize_comparator_file(csv_path);
        else
            write_unavailable_comparator(txt_path, csv_path, stages{s}, coverage(s));
        end
        txt_paths{s} = txt_path;
        csv_paths{s} = csv_path;
    end

    fid = fopen(report_path, 'w');
    assert(fid ~= -1, 'Cannot create %s', report_path);
    cleanup_report = onCleanup(@() fclose(fid));
    fprintf(fid, '# Target versus reference: %s\n\n', target_label);
    fprintf(fid, '## Inputs\n\n');
    fprintf(fid, '- Target: `%s`\n', target_root);
    fprintf(fid, '- Reference: `%s`\n', reference_root);
    fprintf(fid, '- SPM: `%s`\n', spm_root);
    fprintf(fid, '- SPM NIfTI overrides: `%s`\n', spm_override_root);
    fprintf(fid, '- Batch_atlas: `%s`\n\n', atlas_root);

    for s = 1:numel(stages)
        write_inventory(fid, coverage(s));
    end

    nifti_rows = compare_all_nifti(fid, target_root, reference_root, stages, coverage, tol);
    dicom_result = compare_dicom_series(fid, fullfile(target_root, stages{3}), fullfile(reference_root, stages{3}), coverage(3));
    coverage = finalize_coverage(coverage, nifti_rows, dicom_result);
    write_coverage(fid, coverage);
    write_expected_differences(fid);
    [first_name, first_class] = first_nifti_divergence(nifti_rows, tol);
    verdict = comparison_verdict(nifti_rows, dicom_result, coverage, tol);
    unavailable = unavailable_evidence(coverage, nifti_rows, dicom_result);

    fprintf(fid, '## Verdict\n\n');
    fprintf(fid, '- Overall: **%s**\n', verdict);
    if isempty(first_name)
        fprintf(fid, '- First significant common NIfTI divergence: none.\n');
    else
        fprintf(fid, '- First significant common NIfTI divergence in canonical generation order: `%s` (%s).\n', first_name, first_class);
    end
    fprintf(fid, '- Earlier unavailable/incomplete checkpoints: %s\n', unavailable);
    fprintf(fid, '- DICOM: %s\n', dicom_result.verdict);
    fprintf(fid, '- Expected-only categories: version text, run-specific summary/evidence artifacts, date-stamped generated batch MAT files, and QC TIFF artifacts.\n');
    fprintf(fid, '- Repository comparator outputs: `%s_%s_comparator.{txt,csv}` for `%s`, `%s`, and `%s`.\n', ...
        target_label, '<stage>', stages{1}, stages{2}, stages{3});

    fprintf(sfid, '## Target: %s\n\n', target_label);
    fprintf(sfid, '- Verdict: **%s**\n', verdict);
    if isempty(first_name)
        fprintf(sfid, '- First significant common NIfTI divergence: none.\n');
    else
        fprintf(sfid, '- First significant common NIfTI divergence: `%s` (%s).\n', first_name, first_class);
    end
    fprintf(sfid, '- Unavailable/incomplete evidence: %s\n', unavailable);
    fprintf(sfid, '- DICOM: %s\n', dicom_result.verdict);
    fprintf(sfid, '- Detailed report: `%s`\n', report_path);
    fprintf(sfid, '- Comparator outputs: `%s`, `%s`, `%s`\n\n', txt_paths{1}, txt_paths{2}, txt_paths{3});
    target_results(t).label = target_label;
    target_results(t).target_root = target_root;
    target_results(t).verdict = verdict;
    target_results(t).first_divergence = first_name;
    target_results(t).first_class = first_class;
    target_results(t).dicom_verdict = dicom_result.verdict;
    target_results(t).report_path = report_path;
    target_results(t).comparator_txt = txt_paths;
    target_results(t).comparator_csv = csv_paths;
    target_results(t).coverage_complete = all([coverage.complete]);
    target_results(t).coverage_status = coverage_status(coverage);
    target_results(t).coverage = coverage;
    artifact_paths = [artifact_paths {report_path} txt_paths csv_paths]; %#ok<AGROW>
    clear cleanup_report
end

fprintf(sfid, '## Overall\n\n');
fprintf(sfid, '- Compared %d target output tree(s) against one reference output tree.\n', numel(target_roots));
fprintf(sfid, '- Detailed reports and comparator outputs are listed in the target sections above.\n');

summary = struct();
if all([target_results.coverage_complete])
    summary.status = 'completed';
else
    summary.status = 'completed_with_partial_evidence';
end
summary.executive_summary = sprintf(...
    'Compared %d target output tree(s) against one reference output tree.', numel(target_roots));
summary.reference_root = reference_root;
summary.targets = target_results;
summary.summary_report = summary_path;
summary.artifacts = artifact_paths;
summary.next_recommended = 'Review target reports for the first significant divergence.';
summary.risks = 'Semantic comparisons require the configured SPM, DICOM, and repository comparator dependencies.';
summary.skill_resolution = 'wiki-search loaded; relevant pseudo-CT comparator guidance reviewed.';
fprintf('Reports written under %s\n', out_root);
end

function [roots, labels] = normalize_target_roots(target_roots)
if ischar(target_roots)
    if size(target_roots, 1) == 1
        roots = {strtrim(target_roots)};
    else
        roots = cell(size(target_roots, 1), 1);
        for i = 1:size(target_roots, 1)
            roots{i} = strtrim(target_roots(i, :));
        end
    end
elseif iscell(target_roots)
    roots = cell(numel(target_roots), 1);
    for i = 1:numel(target_roots)
        if ~ischar(target_roots{i}) || size(target_roots{i}, 1) ~= 1
            error('run_e2e_semantic_comparison:InvalidTargets', ...
                'Each target root must be a char path.');
        end
        roots{i} = strtrim(target_roots{i});
    end
else
    error('run_e2e_semantic_comparison:InvalidTargets', ...
        'target_roots must be a char path, char matrix, or cell array of char paths.');
end
if isempty(roots)
    error('run_e2e_semantic_comparison:EmptyTargets', ...
        'At least one target root is required.');
end

labels = cell(size(roots));
for i = 1:numel(roots)
    if isempty(roots{i})
        error('run_e2e_semantic_comparison:InvalidTargets', ...
            'Target root %d is empty.', i);
    end
    labels{i} = sanitize_label(folder_basename(roots{i}));
    for j = 1:i-1
        if strcmpi(labels{i}, labels{j})
            error('run_e2e_semantic_comparison:DuplicateTargetLabels', ...
                'Target roots %s and %s share output label "%s".', ...
                roots{j}, roots{i}, labels{i});
        end
    end
end
end

function name = folder_basename(path)
clean = path;
while length(clean) > 1 && (clean(end) == '/' || clean(end) == '\')
    clean = clean(1:end-1);
end
separators = [find(clean == '/') find(clean == '\')];
if isempty(separators)
    name = clean;
else
    name = clean(max(separators) + 1:end);
end
if isempty(name)
    name = 'target';
end
end

function label = sanitize_label(name)
label = regexprep(name, '[^A-Za-z0-9_-]', '_');
if isempty(label)
    label = 'target';
end
end

function validate_directory(path, description)
if exist(path, 'dir') ~= 7
    error('run_e2e_semantic_comparison:MissingDirectory', ...
        'Missing %s directory: %s', description, path);
end
end

function coverage = inspect_coverage(target_root, reference_root, stages, stage_ids)
empty_stage = struct('id', '', 'label', '', 'target_available', false, ...
    'reference_available', false, 'target_count', 0, 'reference_count', 0, ...
    'common_count', 0, 'target_only', {{}}, 'reference_only', {{}}, ...
    'required_target_only', {{}}, 'required_reference_only', {{}}, ...
    'read_errors', {{}}, 'empty', true, 'complete', false, 'status', 'UNAVAILABLE');
coverage = repmat(empty_stage, 1, numel(stages));
for s = 1:numel(stages)
    target_dir = fullfile(target_root, stages{s});
    reference_dir = fullfile(reference_root, stages{s});
    target_available = exist(target_dir, 'dir') == 7;
    reference_available = exist(reference_dir, 'dir') == 7;
    if target_available, target_names = file_names(target_dir); else, target_names = {}; end
    if reference_available, reference_names = file_names(reference_dir); else, reference_names = {}; end
    common = intersect(target_names, reference_names);
    target_only = setdiff(target_names, reference_names);
    reference_only = setdiff(reference_names, target_names);
    if strcmp(stage_ids{s}, 'dicom')
        required_target_only = target_only;
        required_reference_only = reference_only;
        required_common = common;
    else
        required_target_only = required_names(target_only);
        required_reference_only = required_names(reference_only);
        required_common = nifti_names(common);
    end
    coverage(s).id = stage_ids{s};
    coverage(s).label = stages{s};
    coverage(s).target_available = target_available;
    coverage(s).reference_available = reference_available;
    coverage(s).target_count = numel(target_names);
    coverage(s).reference_count = numel(reference_names);
    coverage(s).common_count = numel(common);
    coverage(s).target_only = target_only;
    coverage(s).reference_only = reference_only;
    coverage(s).required_target_only = required_target_only;
    coverage(s).required_reference_only = required_reference_only;
    coverage(s).empty = isempty(target_names) || isempty(reference_names) || isempty(required_common);
    coverage(s).complete = target_available && reference_available && ~coverage(s).empty && ...
        isempty(required_target_only) && isempty(required_reference_only);
    if coverage(s).complete
        coverage(s).status = 'COMPLETE';
    elseif ~target_available || ~reference_available
        coverage(s).status = 'UNAVAILABLE';
    elseif coverage(s).empty
        coverage(s).status = 'EMPTY';
    else
        coverage(s).status = 'PARTIAL';
    end
end
end

function names = required_names(names)
keep = true(size(names));
for i = 1:numel(names)
    keep(i) = ~is_expected_provenance_name(names{i});
end
names = names(keep);
end

function expected = is_expected_provenance_name(name)
expected = strcmp(name, 'Pseudo_CT_AC_Version.txt') || ...
    strcmp(name, 'pseudo_CT_profile_summary.txt') || ...
    strcmp(name, 'pseudo_CT_launchpad_evidence.mat') || ...
    strcmp(name, 'Fusion_MR_Pseudo_CT_validation.tiff') || ...
    ~isempty(regexp(name, '^(new_segment|dartel_existing_template|create_inverse_warped)_.+_batch\.mat$', 'once')) || ...
    ~isempty(regexp(name, '_params\.mat$', 'once'));
end

function names = nifti_names(names)
keep = false(size(names));
for i = 1:numel(names)
    [~, ~, ext] = fileparts(names{i});
    keep(i) = strcmpi(ext, '.nii');
end
names = names(keep);
end

function write_unavailable_comparator(txt_path, csv_path, stage, coverage)
detail = sprintf('%s unavailable: target=%s; reference=%s', stage, ...
    availability_text(coverage.target_available), availability_text(coverage.reference_available));
write_text(txt_path, [detail sprintf('\n')]); %#ok<SPRINTFN>
write_text(csv_path, sprintf('filename,status,detail\n%s,UNAVAILABLE,%s\n', stage, detail));
end

function write_inventory(fid, stage)
fprintf(fid, '## Inventory: %s\n\n', stage.label);
fprintf(fid, '- Target directory: %s\n', availability_text(stage.target_available));
fprintf(fid, '- Reference directory: %s\n', availability_text(stage.reference_available));
fprintf(fid, '- Target files: %d\n', stage.target_count);
fprintf(fid, '- Reference files: %d\n', stage.reference_count);
fprintf(fid, '- Common names: %d\n', stage.common_count);
fprintf(fid, '- Target-only (%d): %s\n', numel(stage.target_only), format_names(stage.target_only));
fprintf(fid, '- Reference-only (%d): %s\n', numel(stage.reference_only), format_names(stage.reference_only));
fprintf(fid, '- Empty evidence: %s\n\n', yesno(stage.empty));
end

function text = availability_text(value)
if value, text = 'available'; else, text = 'unavailable'; end
end

function names = file_names(path)
d = dir(fullfile(path, '*'));
d = d(~[d.isdir]);
names = sort({d.name});
end

function text = format_names(names)
if isempty(names)
    text = 'none';
    return
end
quoted = cell(size(names));
for i = 1:numel(names)
    quoted{i} = ['`' names{i} '`'];
end
text = join_strings(quoted, ', ');
end

function rows = compare_all_nifti(fid, left_root, right_root, stages, coverage, tol)
rows = struct('stage', {}, 'name', {}, 'dim_text', {}, 'dt_text', {}, 'dim_equal', {}, 'dt_equal', {}, ...
    'affine_max', {}, 'pinfo_max', {}, 'max_abs', {}, 'mean_abs', {}, ...
    'nonfinite_mismatch_count', {}, 'different_count', {}, 'different_fraction', {}, 'over_tol_count', {}, ...
    'over_tol_fraction', {}, 'class', {}, 'status', {}, 'read_error', {});
for s = 1:numel(stages)
    if ~coverage(s).target_available || ~coverage(s).reference_available
        continue
    end
    left_dir = fullfile(left_root, stages{s});
    right_dir = fullfile(right_root, stages{s});
    common = intersect(file_names(left_dir), file_names(right_dir));
    for i = 1:numel(common)
        [~, ~, ext] = fileparts(common{i});
        if ~strcmpi(ext, '.nii')
            continue
        end
        try
            row = compare_one_nifti(fullfile(left_dir, common{i}), fullfile(right_dir, common{i}), tol);
        catch ME
            row = unreadable_nifti_row(ME.message);
        end
        row.stage = stages{s};
        row.name = common{i};
        rows(end + 1) = row; %#ok<AGROW>
    end
end

fprintf(fid, '## NIfTI semantic comparison\n\n');
fprintf(fid, 'Exact differing voxels use `abs(target - reference) > 0`; tolerance counts use `> %.9g`. Affine is the SPM-interpreted `mat`; scaling is `pinfo`. Max/mean are over finite comparable pairs; non-finite disagreements are counted separately.\n\n', tol);
fprintf(fid, '| Stage | File | Status | Dimensions | Datatype/endian | Affine max | pinfo max | Max abs | Mean abs | Nonfinite mismatch | Different voxels | Fraction | >tol voxels | >tol fraction | Classification / error |\n');
fprintf(fid, '|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|\n');
for i = 1:numel(rows)
    detail = rows(i).class;
    if strcmp(rows(i).status, 'READ_ERROR'), detail = rows(i).read_error; end
    fprintf(fid, '| %s | `%s` | %s | %s | %s | %.9g | %.9g | %.9g | %.9g | %d | %d | %.9g | %d | %.9g | %s |\n', ...
        rows(i).stage, rows(i).name, rows(i).status, rows(i).dim_text, rows(i).dt_text, ...
        rows(i).affine_max, rows(i).pinfo_max, rows(i).max_abs, rows(i).mean_abs, ...
        rows(i).nonfinite_mismatch_count, rows(i).different_count, rows(i).different_fraction, rows(i).over_tol_count, ...
        rows(i).over_tol_fraction, detail);
end
fprintf(fid, '\n');
end

function row = compare_one_nifti(left_path, right_path, tol)
hl = spm_vol(left_path);
hr = spm_vol(right_path);
vl = spm_read_vols(hl);
vr = spm_read_vols(hr);
dim_equal = isequal(hl.dim, hr.dim);
dt_equal = isequal(hl.dt, hr.dt);
if dim_equal, dim_text = mat2str(hl.dim); else, dim_text = [mat2str(hl.dim) ' vs ' mat2str(hr.dim)]; end
if dt_equal, dt_text = mat2str(hl.dt); else, dt_text = [mat2str(hl.dt) ' vs ' mat2str(hr.dt)]; end
row = struct('stage', '', 'name', '', 'dim_text', dim_text, 'dt_text', dt_text, 'dim_equal', dim_equal, ...
    'dt_equal', dt_equal, 'affine_max', max(abs(double(hl.mat(:)) - double(hr.mat(:)))), ...
    'pinfo_max', NaN, 'max_abs', NaN, 'mean_abs', NaN, 'nonfinite_mismatch_count', 0, 'different_count', 0, ...
    'different_fraction', NaN, 'over_tol_count', 0, 'over_tol_fraction', NaN, 'class', '', ...
    'status', 'COMPARED', 'read_error', '');
if isequal(size(hl.pinfo), size(hr.pinfo))
    row.pinfo_max = max(abs(double(hl.pinfo(:)) - double(hr.pinfo(:))));
end
header_equal = row.dim_equal && row.dt_equal && row.affine_max == 0 && row.pinfo_max == 0;
if ~isequal(size(vl), size(vr))
    row.class = 'DIMENSION_MISMATCH';
    return
end
lv = double(vl(:));
rv = double(vr(:));
finite_pairs = isfinite(lv) & isfinite(rv);
d = abs(lv(finite_pairs) - rv(finite_pairs));
same_nonfinite = (isnan(lv) & isnan(rv)) | (isinf(lv) & isinf(rv) & sign(lv) == sign(rv));
nonfinite_mismatch = ~finite_pairs & ~same_nonfinite;
row.nonfinite_mismatch_count = sum(nonfinite_mismatch);
if ~isempty(d)
    row.max_abs = max(d);
    row.mean_abs = mean(d);
end
row.different_count = sum(d > 0) + row.nonfinite_mismatch_count;
row.different_fraction = row.different_count / numel(lv);
row.over_tol_count = sum(d > tol) + row.nonfinite_mismatch_count;
row.over_tol_fraction = row.over_tol_count / numel(lv);
if row.different_count == 0 && header_equal
    row.class = 'IDENTICAL';
elseif row.different_count == 0
    row.class = 'HEADER_ONLY';
elseif row.dim_equal && row.dt_equal && row.affine_max <= tol && row.pinfo_max <= tol
    row.class = 'VOXEL_LEVEL';
else
    row.class = 'HEADER_AND_VOXEL';
end
end

function row = unreadable_nifti_row(message)
row = struct('stage', '', 'name', '', 'dim_text', 'unavailable', 'dt_text', 'unavailable', ...
    'dim_equal', false, 'dt_equal', false, 'affine_max', NaN, 'pinfo_max', NaN, ...
    'max_abs', NaN, 'mean_abs', NaN, 'nonfinite_mismatch_count', 0, ...
    'different_count', 0, 'different_fraction', NaN, 'over_tol_count', 0, ...
    'over_tol_fraction', NaN, 'class', 'READ_ERROR', 'status', 'READ_ERROR', ...
    'read_error', message);
end

function result = compare_dicom_series(fid, left_dir, right_dir, coverage)
if coverage.target_available, left = file_names(left_dir); else, left = {}; end
if coverage.reference_available, right = file_names(right_dir); else, right = {}; end
common = intersect(left, right);
only_left = setdiff(left, right);
only_right = setdiff(right, left);
geometry_fields = {'Rows', 'Columns', 'PixelSpacing', 'SliceThickness', ...
    'SpacingBetweenSlices', 'ImagePositionPatient', 'ImageOrientationPatient', ...
    'SliceLocation', 'InstanceNumber', 'RescaleSlope', 'RescaleIntercept', ...
    'BitsAllocated', 'BitsStored', 'HighBit', 'PixelRepresentation'};
generated_fields = {'StudyInstanceUID', 'SeriesInstanceUID', 'SOPInstanceUID', ...
    'StudyDate', 'SeriesDate', 'AcquisitionDate', 'ContentDate', ...
    'StudyTime', 'SeriesTime', 'AcquisitionTime', 'ContentTime', ...
    'InstanceCreationDate', 'InstanceCreationTime'};
pixel_total = 0;
pixel_diff_count = 0;
pixel_abs_sum = 0;
pixel_max = 0;
pixel_diff_slices = 0;
geometry_mismatch_slices = 0;
geometry_mismatch_counts = zeros(size(geometry_fields));
generated_mismatch_counts = zeros(size(generated_fields));
read_errors = {};
for i = 1:numel(common)
    lp = fullfile(left_dir, common{i});
    rp = fullfile(right_dir, common{i});
    try
        li = dicominfo(lp);
        ri = dicominfo(rp);
        limg = dicomread(li);
        rimg = dicomread(ri);
        if ~isequal(size(limg), size(rimg))
            pixel_diff_slices = pixel_diff_slices + 1;
            read_errors{end + 1} = [common{i} ': pixel dimensions differ']; %#ok<AGROW>
        else
            d = abs(double(limg(:)) - double(rimg(:)));
            pixel_total = pixel_total + numel(d);
            pixel_diff_count = pixel_diff_count + sum(d > 0);
            pixel_abs_sum = pixel_abs_sum + sum(d);
            pixel_max = max(pixel_max, max(d));
            if any(d > 0), pixel_diff_slices = pixel_diff_slices + 1; end
        end
        slice_geom_bad = false;
        for f = 1:numel(geometry_fields)
            if ~field_equal(li, ri, geometry_fields{f})
                geometry_mismatch_counts(f) = geometry_mismatch_counts(f) + 1;
                slice_geom_bad = true;
            end
        end
        if slice_geom_bad, geometry_mismatch_slices = geometry_mismatch_slices + 1; end
        for f = 1:numel(generated_fields)
            if ~field_equal(li, ri, generated_fields{f})
                generated_mismatch_counts(f) = generated_mismatch_counts(f) + 1;
            end
        end
    catch ME
        read_errors{end + 1} = [common{i} ': ' ME.message]; %#ok<AGROW>
    end
end
if pixel_total > 0
    pixel_mean = pixel_abs_sum / pixel_total;
    pixel_fraction = pixel_diff_count / pixel_total;
else
    pixel_mean = NaN;
    pixel_fraction = NaN;
end
readable_slices = numel(common) - numel(read_errors);
if ~coverage.target_available || ~coverage.reference_available
    verdict = 'DICOM comparison unavailable because a required directory is missing.';
elseif isempty(left) || isempty(right) || isempty(common) || readable_slices == 0
    verdict = 'DICOM comparison incomplete because no readable common slices are available.';
elseif isempty(only_left) && isempty(only_right) && isempty(read_errors) && ...
        pixel_diff_count == 0 && geometry_mismatch_slices == 0
    verdict = 'slice inventory, pixel arrays, and relevant geometry fields match exactly; any listed UID/date/time drift is metadata-only.';
elseif pixel_diff_count > 0
    verdict = 'pixel-divergent DICOM series.';
elseif geometry_mismatch_slices > 0
    verdict = 'pixel arrays match, but relevant DICOM geometry/header fields diverge.';
else
    verdict = 'DICOM comparison incomplete because of inventory or read errors.';
end
result = struct('slice_count_left', numel(left), 'slice_count_right', numel(right), ...
    'pixel_diff_count', pixel_diff_count, 'geometry_mismatch_slices', geometry_mismatch_slices, ...
    'readable_slice_count', readable_slices, 'read_errors', {read_errors}, ...
    'target_only', {only_left}, 'reference_only', {only_right}, 'verdict', verdict);

fprintf(fid, '## DICOM semantic comparison\n\n');
fprintf(fid, '- Target slices: %d\n', numel(left));
fprintf(fid, '- Reference slices: %d\n', numel(right));
fprintf(fid, '- Common filenames: %d\n', numel(common));
fprintf(fid, '- Target-only: %s\n', format_names(only_left));
fprintf(fid, '- Reference-only: %s\n', format_names(only_right));
fprintf(fid, '- Pixel dimensions compared: %d slices\n', readable_slices);
fprintf(fid, '- Pixel-divergent slices: %d\n', pixel_diff_slices);
fprintf(fid, '- Pixel max absolute difference: %.9g\n', pixel_max);
fprintf(fid, '- Pixel mean absolute difference: %.9g\n', pixel_mean);
fprintf(fid, '- Differing pixels: %d / %d (%.9g)\n', pixel_diff_count, pixel_total, pixel_fraction);
fprintf(fid, '- Slices with relevant geometry/header mismatch: %d\n', geometry_mismatch_slices);
fprintf(fid, '- Relevant geometry/header mismatch counts: %s\n', field_counts(geometry_fields, geometry_mismatch_counts));
fprintf(fid, '- Expected generated UID/date/time mismatch counts: %s\n', field_counts(generated_fields, generated_mismatch_counts));
fprintf(fid, '- Read errors: %s\n', format_names(read_errors));
fprintf(fid, '- Verdict: %s\n\n', verdict);
end

function coverage = finalize_coverage(coverage, rows, dicom_result)
for s = 1:numel(coverage)
    read_errors = {};
    if strcmp(coverage(s).id, 'dicom')
        read_errors = dicom_result.read_errors;
        coverage(s).complete = coverage(s).complete && ...
            dicom_result.readable_slice_count > 0 && isempty(read_errors);
    else
        for i = 1:numel(rows)
            if strcmp(rows(i).stage, coverage(s).label) && strcmp(rows(i).status, 'READ_ERROR')
                read_errors{end + 1} = [rows(i).name ': ' rows(i).read_error]; %#ok<AGROW>
            end
        end
        coverage(s).complete = coverage(s).complete && isempty(read_errors);
    end
    coverage(s).read_errors = read_errors;
    if ~isempty(read_errors)
        coverage(s).status = 'READ_ERROR';
    elseif coverage(s).complete
        coverage(s).status = 'COMPLETE';
    end
end
end

function write_coverage(fid, coverage)
fprintf(fid, '## Coverage status\n\n');
fprintf(fid, '| Stage | Status | Required target-only | Required reference-only | Read errors |\n');
fprintf(fid, '|---|---|---:|---:|---:|\n');
for s = 1:numel(coverage)
    fprintf(fid, '| %s | %s | %d | %d | %d |\n', coverage(s).label, coverage(s).status, ...
        numel(coverage(s).required_target_only), numel(coverage(s).required_reference_only), ...
        numel(coverage(s).read_errors));
end
fprintf(fid, '\n');
end

function write_expected_differences(fid)
fprintf(fid, '## Difference classification\n\n');
fprintf(fid, '- Expected metadata/provenance: `Pseudo_CT_AC_Version.txt` (version/date history).\n');
fprintf(fid, '- Expected generated artifacts: date-stamped `new_segment_*_batch.mat`, `dartel_existing_template_*_batch.mat`, and `create_inverse_warped_*_batch.mat`; these differ by run date/name and may leave multiple retained copies.\n');
fprintf(fid, '- Expected run-specific artifacts: summary/evidence text, MAT metadata with job-specific absolute paths, and QC TIFF files.\n');
fprintf(fid, '- Expected retained-intermediate differences may include auxiliary parameter MAT files when one output tree preserves them and the other does not.\n');
fprintf(fid, '- Behaviorally significant: all NIfTI rows with voxel differences above tolerance and all DICOM pixel differences; relevant DICOM geometry fields are reported separately.\n\n');
end

function equal = field_equal(a, b, name)
ha = isfield(a, name);
hb = isfield(b, name);
equal = ha == hb;
if equal && ha
    equal = equal_with_nan(a.(name), b.(name));
end
end

function equal = equal_with_nan(a, b)
equal = isequal(a, b);
if equal || ~isnumeric(a) || ~isnumeric(b) || ~isequal(size(a), size(b))
    return
end
nan_a = isnan(a);
nan_b = isnan(b);
equal = isequal(nan_a, nan_b) && isequal(a(~nan_a), b(~nan_b));
end

function text = field_counts(fields, counts)
parts = {};
for i = 1:numel(fields)
    if counts(i) > 0
        parts{end + 1} = sprintf('%s=%d', fields{i}, counts(i)); %#ok<AGROW>
    end
end
if isempty(parts)
    text = 'none';
else
    text = join_strings(parts, ', ');
end
end

function text = join_strings(parts, separator)
if isempty(parts)
    text = '';
    return
end
text = parts{1};
for i = 2:numel(parts)
    text = [text separator parts{i}]; %#ok<AGROW>
end
end

function text = genericize_comparator_text(text)
text = strrep(text, 'Local:      ', 'Target:    ');
text = strrep(text, 'Launchpad:  ', 'Reference: ');
text = strrep(text, 'local_dir not found', 'target_dir not found');
text = strrep(text, 'launchpad_dir not found', 'reference_dir not found');
text = strrep(text, 'cannot open local:', 'cannot open target:');
text = strrep(text, 'cannot open launchpad:', 'cannot open reference:');
text = strrep(text, 'LOCAL_ONLY', 'TARGET_ONLY');
text = strrep(text, 'LAUNCHPAD_ONLY', 'REFERENCE_ONLY');
end

function genericize_comparator_file(path)
if exist(path, 'file') == 2
    genericized = genericize_comparator_text(fileread(path));
    write_text(path, genericized);
end
end

function [name, class_name] = first_nifti_divergence(rows, tol)
order = {'mprage.nii', 'mprage_normalized.nii', 'mprage_normalized_repos.nii', ...
    'mmprage_normalized_repos.nii', 'smprage_normalized_repos.nii', ...
    'c1mprage_normalized_repos.nii', 'c2mprage_normalized_repos.nii', ...
    'c3mprage_normalized_repos.nii', 'c4mprage_normalized_repos.nii', ...
    'c5mprage_normalized_repos.nii', 'c6mprage_normalized_repos.nii', ...
    'rc1mprage_normalized_repos.nii', 'rc2mprage_normalized_repos.nii', ...
    'rc3mprage_normalized_repos.nii', 'rc4mprage_normalized_repos.nii', ...
    'rc5mprage_normalized_repos.nii', 'rc6mprage_normalized_repos.nii', ...
    'u_rc1mprage_normalized_repos.nii', 'iy_mprage_normalized_repos.nii', ...
    'wAtlas_cp_iso_mprage_normalized_repos_15subj_u_rc1mprage_normalized_repos.nii', ...
    'wAtlas_rcp_ute1_normalized_repos_15subj_u_rc1mprage_normalized_repos.nii', ...
    'wAtlas_rcp_ute2_normalized_repos_15subj_u_rc1mprage_normalized_repos.nii', ...
    'wAtlas_rCT_flipLR_repos_15subj_u_rc1mprage_normalized_repos.nii', ...
    'wAtlas_head_mask_u_rc1mprage_normalized_repos.nii', ...
    'rwAtlas_cp_iso_mprage_normalized_repos_15subj_u_rc1mprage_normalized_repos.nii', ...
    'rwAtlas_rcp_ute1_normalized_repos_15subj_u_rc1mprage_normalized_repos.nii', ...
    'rwAtlas_rcp_ute2_normalized_repos_15subj_u_rc1mprage_normalized_repos.nii', ...
    'rwAtlas_rCT_flipLR_repos_15subj_u_rc1mprage_normalized_repos.nii', ...
    'rwAtlas_head_mask_u_rc1mprage_normalized_repos.nii', 'att_map.nii'};
name = '';
class_name = '';
for o = 1:numel(order)
    candidate_stages = {'MR_PET/tmp', 'MR_PET'};
    for s = 1:numel(candidate_stages)
        idx = find(strcmp({rows.name}, order{o}) & strcmp({rows.stage}, candidate_stages{s}), 1);
        if isempty(idx) || ~strcmp(rows(idx).status, 'COMPARED'), continue; end
        if rows(idx).over_tol_count > 0 || rows(idx).affine_max > tol || ...
                ~rows(idx).dim_equal || ~rows(idx).dt_equal || rows(idx).pinfo_max > tol
            name = [rows(idx).stage '/' rows(idx).name];
            class_name = rows(idx).class;
            return
        end
    end
end
end

function verdict = comparison_verdict(rows, dicom_result, coverage, tol)
significant_nifti = false;
for i = 1:numel(rows)
    if strcmp(rows(i).status, 'COMPARED') && (rows(i).over_tol_count > 0 || rows(i).affine_max > tol || ...
            ~rows(i).dim_equal || ~rows(i).dt_equal || rows(i).pinfo_max > tol)
        significant_nifti = true;
        break
    end
end
if significant_nifti || dicom_result.pixel_diff_count > 0 || dicom_result.geometry_mismatch_slices > 0
    verdict = 'BEHAVIORALLY DIVERGENT';
elseif ~all([coverage.complete])
    verdict = 'INCONCLUSIVE - PARTIAL EVIDENCE';
else
    verdict = 'BEHAVIORALLY EQUIVALENT within tolerance';
end
end

function status = coverage_status(coverage)
if all([coverage.complete])
    status = 'complete';
else
    status = 'partial';
end
end

function text = unavailable_evidence(coverage, rows, dicom_result) %#ok<INUSD>
parts = {};
for s = 1:numel(coverage)
    if coverage(s).complete, continue; end
    detail = coverage(s).status;
    if ~isempty(coverage(s).required_reference_only)
        detail = [detail '; reference-only=' format_names(coverage(s).required_reference_only)]; %#ok<AGROW>
    end
    if ~isempty(coverage(s).required_target_only)
        detail = [detail '; target-only=' format_names(coverage(s).required_target_only)]; %#ok<AGROW>
    end
    if ~isempty(coverage(s).read_errors)
        detail = [detail '; read-errors=' format_names(coverage(s).read_errors)]; %#ok<AGROW>
    end
    parts{end + 1} = [coverage(s).label ' (' detail ')']; %#ok<AGROW>
end
if isempty(parts)
    text = 'none';
else
    text = join_strings(parts, '; ');
end
end

function out = yesno(value)
if value, out = 'yes'; else, out = 'no'; end
end

function write_text(path, content)
fid = fopen(path, 'w');
assert(fid ~= -1, 'Cannot create %s', path);
cleanup = onCleanup(@() fclose(fid));
fprintf(fid, '%s', content);
end
