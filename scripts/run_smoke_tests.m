function run_smoke_tests()
%RUN_SMOKE_TESTS Fast package integrity and policy checks.

root_dir = fileparts(fileparts(mfilename('fullpath')));
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

entry_files = {'run_pseudo_CT.m'};
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


changelog = read_text(fullfile(root_dir, 'CHANGELOG.md'));
first_line = strtrim(strtok(changelog, char(10)));
check('CHANGELOG.md top version is 2.7.0', strcmp(first_line, '2.7.0'), first_line);

try
    test_profile_authority();
    check('simple dynamic profile system', true, '');
catch ME
    check('simple dynamic profile system', false, ME.message);
end

atlas_source = read_text(fullfile(root_dir, 'src', 'core', 'atlas_based_attenuation_map.m'));
check('local final subject mask is policy-gated', ...
    ~isempty(strfind(atlas_source, 'config.zero_background')) && ...
    ~isempty(strfind(atlas_source, 'att_map.*((subj_mask_dil + (orig_mprage > 20)) > 0)')), ...
    'local policy gate not found');
check('bone reduction consumes profile setting', ...
    ~isempty(strfind(atlas_source, 'if config.bone_enabled')) && ...
    ~isempty(strfind(atlas_source, 'reduce_bone_segment(Prc_old)')), 'bone cleanup not found');
entry_source = read_text(fullfile(root_dir, 'run_pseudo_CT.m'));
check('final FWHM consumes profile setting', ...
    ~isempty(strfind(entry_source, 'temp_dir, config.fwhm')), ...
    'config.fwhm is not passed to DICOM output');

launchpad_source = entry_source;
mask_call = strfind(launchpad_source, 'launchpad_apply_background_mask(jobs(jj).temp_dir, context)');
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
