function run_smoke_tests()

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

%% 1. Entry scripts exist and parse
check('run_pseudo_CT_local.m exists', ...
    exist(fullfile(root_dir, 'run_pseudo_CT_local.m'), 'file') == 2, '');
check('run_pseudo_CT_launchpad.m exists', ...
    exist(fullfile(root_dir, 'run_pseudo_CT_launchpad.m'), 'file') == 2, '');
try
    mlint(fullfile(root_dir, 'run_pseudo_CT_local.m'));
    check('run_pseudo_CT_local.m parses', true, '');
catch ME
    check('run_pseudo_CT_local.m parses', false, ME.message);
end
try
    mlint(fullfile(root_dir, 'run_pseudo_CT_launchpad.m'));
    check('run_pseudo_CT_launchpad.m parses', true, '');
catch ME
    check('run_pseudo_CT_launchpad.m parses', false, ME.message);
end

%% 2. All src/ source files parse
src_files = dir(fullfile(root_dir, 'src', '**', '*.m'));
fprintf('\n  Checking %d source files in src/ ...\n', numel(src_files));
for i = 1:numel(src_files)
    fp = fullfile(src_files(i).folder, src_files(i).name);
    try
        mlint(fp);
        check(sprintf('src/.../%s parses', src_files(i).name), true, '');
    catch ME
        check(sprintf('src/.../%s parses', src_files(i).name), false, ME.message);
    end
end

%% 3. vers/ overrides parse
fprintf('\n  Checking 3 override files in vers/ ...\n');
for name = {'spm_vol_nifti.m', 'spm_preproc_write8.m', 'spm_dicom_convert.m'}
    fp = fullfile(root_dir, 'vers', name{1});
    try
        mlint(fp);
        check(sprintf('vers/%s parses', name{1}), true, '');
    catch ME
        check(sprintf('vers/%s parses', name{1}), false, ME.message);
    end
end

%% 4. Key assets exist
check('Batch_atlas/ directory', ...
    exist(fullfile(root_dir, 'Batch_atlas'), 'dir') == 7, '');
check('TPM.nii exists', ...
    exist(fullfile(root_dir, 'Batch_atlas', 'TPM.nii'), 'file') == 2, '');
check('ch2.nii exists', ...
    exist(fullfile(root_dir, 'Batch_atlas', 'ch2.nii'), 'file') == 2, '');

templates_ok = true;
for i = 0:6
    fn = sprintf('Template_%d.nii', i);
    if exist(fullfile(root_dir, 'Batch_atlas', fn), 'file') ~= 2
        templates_ok = false;
    end
end
check('7 DARTEL templates exist', templates_ok, '');

%% 5. SSH JAR exists
check('ganymed-ssh2-build250.jar', ...
    exist(fullfile(root_dir, 'Batch_atlas', 'ganymed-ssh2-build250', ...
    'ganymed-ssh2-build250.jar'), 'file') == 2, '');

%% Summary
fprintf('\n=== Results: %d passed, %d failed ===\n', num_passed, num_failed);
if num_failed > 0
    error('Smoke tests failed.');
end
end
