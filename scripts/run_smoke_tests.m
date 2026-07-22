function run_smoke_tests()
%RUN_SMOKE_TESTS Fast package integrity and policy checks.

root_dir = fileparts(fileparts(mfilename('fullpath')));
fprintf('=== pseudo-CT Smoke Tests ===\n');
fprintf('Root: %s\n\n', root_dir);

num_passed = 0;
num_failed = 0;
num_skipped = 0;

    function check(test_name, ok, detail)
        if ok
            num_passed = num_passed + 1;
            fprintf('  PASS  %s\n', test_name);
        else
            num_failed = num_failed + 1;
            fprintf('  FAIL  %s: %s\n', test_name, detail);
        end
    end

    function skip(test_name, reason)
        num_skipped = num_skipped + 1;
        fprintf('  SKIP  %s - %s\n', test_name, reason);
    end

entry_files = {'run_pseudo_CT_local.m', 'run_pseudo_CT_launchpad.m'};
for i=1:numel(entry_files)
    path = fullfile(root_dir, entry_files{i});
    check([entry_files{i} ' exists'], exist(path, 'file') == 2, 'file not found');
    check_parse(path, entry_files{i}, @check);
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

override_files = {'spm_vol_nifti.m', 'spm_preproc_write8.m', 'spm_dicom_convert.m'};
for i=1:numel(override_files)
    path = fullfile(root_dir, 'vers', override_files{i});
    check(['vers/' override_files{i} ' exists'], exist(path, 'file') == 2, 'file not found');
    check_parse(path, ['vers/' override_files{i}], @check);
end

atlas_path = getenv('PSEUDOCT_BATCH_ATLAS');
if isempty(atlas_path)
    atlas_path = fullfile(root_dir, 'Batch_atlas');
end
if exist(atlas_path, 'dir') ~= 7
    skip('Batch_atlas assets', sprintf('atlas directory not found: %s', atlas_path));
else
    check('Batch_atlas/TPM.nii exists', ...
        exist(fullfile(atlas_path, 'TPM.nii'), 'file') == 2, 'TPM.nii not found');
    check('Batch_atlas/ch2.nii exists', ...
        exist(fullfile(atlas_path, 'ch2.nii'), 'file') == 2, 'ch2.nii not found');
    templates_ok = true;
    for i=0:6
        templates_ok = templates_ok && ...
            exist(fullfile(atlas_path, sprintf('Template_%d.nii', i)), 'file') == 2;
    end
    check('seven DARTEL templates exist', templates_ok, 'Template_0.nii through Template_6.nii are required');
    check('Launchpad SSH JAR exists', ...
        exist(fullfile(atlas_path, 'ganymed-ssh2-build250', ...
        'ganymed-ssh2-build250.jar'), 'file') == 2, 'SSH JAR not found');
end

changelog = read_text(fullfile(root_dir, 'CHANGELOG.md'));
first_line = strtrim(strtok(changelog, char(10)));
check('CHANGELOG.md top version is 2.6.5', strcmp(first_line, '2.6.5'), first_line);

config_dir = fullfile(root_dir, 'src', 'config');
addpath(config_dir);
cleanup_config_path = onCleanup(@() rmpath(config_dir)); %#ok<NASGU>
original_env = getenv('PSEUDOCT_ZERO_BACKGROUND');
cleanup_env = onCleanup(@() setenv('PSEUDOCT_ZERO_BACKGROUND', original_env)); %#ok<NASGU>

setenv('PSEUDOCT_ZERO_BACKGROUND', '');
check('zero-background helper resolves defaults Yes', ...
    strcmp(pseudo_CT_zero_background_enabled(@defaults_yes), 'Yes'), 'expected Yes');
check('zero-background helper resolves defaults No', ...
    strcmp(pseudo_CT_zero_background_enabled(@defaults_no), 'No'), 'expected No');
check('zero-background helper safely handles missing key', ...
    strcmp(pseudo_CT_zero_background_enabled(@defaults_missing), 'No'), 'expected No');
check('zero-background helper safely handles defaults error', ...
    strcmp(pseudo_CT_zero_background_enabled(@defaults_error), 'No'), 'expected No');
setenv('PSEUDOCT_ZERO_BACKGROUND', 'true');
check('zero-background environment opt-in resolves Yes', ...
    strcmp(pseudo_CT_zero_background_enabled(@defaults_no), 'Yes'), 'expected Yes');
setenv('PSEUDOCT_ZERO_BACKGROUND', '');

local_defaults = read_text(fullfile(config_dir, 'defaults_pseudo_CT.m'));
launchpad_defaults = read_text(fullfile(config_dir, 'defaults_pseudo_CT_launchpad.m'));
check('local defaults set zero_background to No', ...
    ~isempty(strfind(local_defaults, 'zero_background = ''No''')), 'default missing');
check('Launchpad defaults set zero_background to No', ...
    ~isempty(strfind(launchpad_defaults, 'zero_background = ''No''')), 'default missing');
check('local defaults set recenter_before_normalization to No', ...
    ~isempty(strfind(local_defaults, 'recenter_before_normalization = ''No''')), 'default missing');
check('Launchpad defaults set recenter_before_normalization to No', ...
    ~isempty(strfind(launchpad_defaults, 'recenter_before_normalization = ''No''')), 'default missing');
check('defaults document normalized Launchpad recenter bypass', ...
    ~isempty(strfind(local_defaults, '_normalized.nii')) && ...
    ~isempty(strfind(launchpad_defaults, '_normalized.nii')), 'bypass explanation missing');

atlas_source = read_text(fullfile(root_dir, 'src', 'core', 'atlas_based_attenuation_map.m'));
check('local final subject mask is policy-gated', ...
    ~isempty(strfind(atlas_source, 'pseudo_CT_zero_background_enabled(zero_background_defaults)')) && ...
    ~isempty(strfind(atlas_source, 'att_map.*((subj_mask_dil + (orig_mprage > 20)) > 0)')), ...
    'local policy gate not found');
check('bone reduction remains enabled', ...
    ~isempty(strfind(atlas_source, 'fixed_bone_cleanup()')) && ...
    ~isempty(strfind(atlas_source, 'reduce_bone_segment(Prc_old)')), 'bone cleanup not found');

launchpad_source = read_text(fullfile(root_dir, 'run_pseudo_CT_launchpad.m'));
mask_call = strfind(launchpad_source, 'launchpad_apply_background_mask(jobs(jj).temp_dir)');
dicom_call = strfind(launchpad_source, 'pseudo_CT_write_mu_map_dicom');
promote_call = strfind(launchpad_source, 'pseudo_CT_promote_final_outputs');
check('Launchpad optional mask precedes DICOM conversion and promotion', ...
    ~isempty(mask_call) && ~isempty(dicom_call) && ~isempty(promote_call) && ...
    mask_call(1) < dicom_call(1) && dicom_call(1) < promote_call(1), ...
    'Launchpad post-fetch order is incorrect');
check('Launchpad missing normalized MPRAGE preserves unmasked map', ...
    ~isempty(strfind(launchpad_source, 'mprage_normalized.nii')) && ...
    ~isempty(strfind(launchpad_source, 'will remain unmasked')), 'fallback warning not found');

comparator_files = {'pct_compare_nifti_exact.m', ...
    'pct_compare_semantic_mat.m', 'test_exact_comparators.m'};
for i=1:numel(comparator_files)
    path = fullfile(root_dir, 'scripts', comparator_files{i});
    check(['scripts/' comparator_files{i} ' exists'], exist(path, 'file') == 2, 'file not found');
    check_parse(path, ['scripts/' comparator_files{i}], @check);
end

fprintf('\n=== Results: %d passed, %d failed, %d skipped ===\n', ...
    num_passed, num_failed, num_skipped);
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

function value = defaults_yes(~)
value = 'Yes';
end

function value = defaults_no(~)
value = 'No';
end

function value = defaults_missing(~)
value = -1;
end

function value = defaults_error(~)
error('test:missingDefault', 'missing default');
value = 'No'; %#ok<UNRCH>
end
