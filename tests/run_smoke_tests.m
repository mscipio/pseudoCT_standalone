function run_smoke_tests()
%RUN_SMOKE_TESTS Fast package integrity and policy checks.

tests_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(tests_dir);
old_path = path();
addpath(tests_dir, '-begin');
cleanup = onCleanup(@() path(old_path)); %#ok<NASGU>
fprintf('=== pseudo-CT Smoke Tests ===\n');
fprintf('Root: %s\n\n', root_dir);

num_passed = 0;
num_failed = 0;

    function check(test_name, ok, detail)
        if ok
            num_passed = num_passed + 1;
            fprintf('  PASS  %s\n', test_name);
        else
            num_failed = num_failed + 1;
            fprintf('  FAIL  %s: %s\n', test_name, detail);
        end
    end

try
    test_headless_result_validator();
    check('Headless v2 result validation', true, '');
catch ME
    check('Headless v2 result validation', false, ME.message);
end

entry_files = {'run_pseudo_CT.m'};
for i=1:numel(entry_files)
    file_path = fullfile(root_dir, entry_files{i});
    check([entry_files{i} ' exists'], exist(file_path, 'file') == 2, 'file not found');
    check_parse(file_path, entry_files{i}, @check);
end

source_files = collect_m_files(fullfile(root_dir, 'src'));
fprintf('\n  Checking %d source files in src/ ...\n', numel(source_files));
for i=1:numel(source_files)
    check_parse(source_files{i}, source_files{i}, @check);
end

script_files = collect_m_files(fullfile(root_dir, 'scripts'));
fprintf('\n  Checking %d maintainer scripts ...\n', numel(script_files));
for i=1:numel(script_files)
    check_parse(script_files{i}, script_files{i}, @check);
end

test_files = collect_m_files(fullfile(root_dir, 'tests'));
fprintf('\n  Checking %d test files in tests/ ...\n', numel(test_files));
for i=1:numel(test_files)
    check_parse(test_files{i}, test_files{i}, @check);
end

override_files = {'spm_vol_nifti.m', 'spm_preproc_write8.m', 'spm_dicom_convert.m'};
for i=1:numel(override_files)
    file_path = fullfile(root_dir, 'src', 'science', 'overrides', override_files{i});
    check(['src/science/overrides/' override_files{i} ' exists'], exist(file_path, 'file') == 2, 'file not found');
    check_parse(file_path, ['src/science/overrides/' override_files{i}], @check);
end


changelog = read_text(fullfile(root_dir, 'CHANGELOG.md'));
first_line = strtrim(strtok(changelog, char(10)));
check('CHANGELOG.md top version is 3.2.0', strcmp(first_line, '3.2.0'), first_line);

try
    test_profile_authority();
    check('simple dynamic profile system', true, '');
catch ME
    check('simple dynamic profile system', false, ME.message);
end

try
    test_mprage_only_profile();
    check('MPRAGE-only collection and promotion seams', true, '');
catch ME
    check('MPRAGE-only collection and promotion seams', false, ME.message);
end

try
    test_cli_progress_output();
    check('CLI progress and local preprocessing seams', true, '');
catch ME
    check('CLI progress and local preprocessing seams', false, ME.message);
end

try
    test_compressed_nifti_input();
    check('compressed NIfTI input staging', true, '');
catch ME
    check('compressed NIfTI input staging', false, ME.message);
end

try
    test_mlsc_backend();
    check('MLSC account, preflight, script, and transport seams', true, '');
catch ME
    check('MLSC account, preflight, script, and transport seams', false, ME.message);
end

try
    test_mlsc_slurm_lifecycle();
    check('MLSC Slurm lifecycle, accounting, evidence, and cleanup seams', true, '');
catch ME
    check('MLSC Slurm lifecycle, accounting, evidence, and cleanup seams', false, ME.message);
end

try
    test_mlsc_ssh2_compatibility();
    check('MLSC provider-free normal path, optional strict gate, credential-free behavior', true, '');
catch ME
    check('MLSC provider-free normal path, optional strict gate, credential-free behavior', false, ME.message);
end

profile_source = read_text(fullfile(root_dir, 'src', 'config', ...
    'profiles', 'local_mprage_only.m'));
check('MPRAGE-only profile declares explicit policy', ...
    ~isempty(strfind(profile_source, 'config.io_policy.reference = ''none''')) && ...
    ~isempty(strfind(profile_source, 'config.io_policy.output = ''nifti-only''')), ...
    'MPRAGE-only policy fields are missing');

compute_source = read_text(fullfile(root_dir, 'src', 'science', 'current', 'pseudo_CT_current_compute.m'));
check('local final subject mask is policy-gated', ...
    ~isempty(strfind(compute_source, 'config.zero_background')) && ...
    ~isempty(strfind(compute_source, '((subj_mask_dil + (orig_mprage > 20)) > 0)')), ...
    'local policy gate not found');
check('bone reduction consumes profile setting', ...
    ~isempty(strfind(compute_source, 'if config.bone_enabled')) && ...
    ~isempty(strfind(compute_source, 'reduce_bone_segment(Prc_old)')), 'bone cleanup not found');
entry_source = read_text(fullfile(root_dir, 'run_pseudo_CT.m'));
run_lifecycle_source = read_text(fullfile(root_dir, 'src', 'orchestration', ...
    'pseudo_CT_run_lifecycle.m'));
check('public entrypoint delegates to orchestration', ...
    ~isempty(strfind(entry_source, 'pseudo_CT_orchestrate(')), ...
    'run_pseudo_CT no longer dispatches to orchestration');
check('final FWHM consumes profile setting', ...
    ~isempty(strfind(run_lifecycle_source, 'temp_dir, config.fwhm')), ...
    'config.fwhm is not passed to DICOM output');


comparator_files = {'pct_compare_nifti_exact.m', ...
    'pct_compare_semantic_mat.m'};
for i=1:numel(comparator_files)
    file_path = fullfile(root_dir, 'tests', 'manual', comparator_files{i});
    check(['tests/manual/' comparator_files{i} ' exists'], exist(file_path, 'file') == 2, 'file not found');
    check_parse(file_path, ['tests/manual/' comparator_files{i}], @check);
end
file_path = fullfile(root_dir, 'tests', 'test_exact_comparators.m');
check('tests/test_exact_comparators.m exists', exist(file_path, 'file') == 2, 'file not found');
check_parse(file_path, 'tests/test_exact_comparators.m', @check);

fprintf('\n=== Results: %d passed, %d failed ===\n', ...
    num_passed, num_failed);
if num_failed > 0
    error('Smoke tests failed.');
end
end

function check_parse(path, label, check_handle)
try
    mlint(path);
    check_handle([label ' parses'], true, '');
catch ME
    check_handle([label ' parses'], false, ME.message);
end
end

function files = collect_m_files(directory)
files = {};
entries = dir(directory);
for i=1:numel(entries)
    name = entries(i).name;
    if entries(i).isdir
        if ~strcmp(name, '.') && ~strcmp(name, '..')
            nested = collect_m_files(fullfile(directory, name));
            files = [files nested]; %#ok<AGROW>
        end
    elseif numel(name) >= 2 && strcmp(name(end-1:end), '.m')
        files{end+1} = fullfile(directory, name); %#ok<AGROW>
    end
end
end

function text = read_text(path)
fid = fopen(path, 'r');
if fid == -1
    text = '';
    return;
end

text = fread(fid, inf, '*char')';
fclose(fid);
end
