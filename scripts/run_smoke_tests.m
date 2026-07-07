function run_smoke_tests()

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
    fprintf('  SKIP  %s — %s\n', test_name, reason);
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

%% 4. Key assets exist (with configurable atlas path)
atlas_env = getenv('PSEUDOCT_BATCH_ATLAS');
batch_atlas_path = fullfile(root_dir, 'Batch_atlas');
atlas_configured = false;
if ~isempty(atlas_env)
    batch_atlas_path = atlas_env;
    atlas_configured = true;
    fprintf('\n  Using PSEUDOCT_BATCH_ATLAS: %s\n', batch_atlas_path);
end

atlas_dir_ok = exist(batch_atlas_path, 'dir') == 7;
if ~atlas_dir_ok && ~atlas_configured
    % Batch_atlas absent and no env override: skip atlas-dependent checks.
    % This is expected in environments without the atlas data bundled.
    % Set PSEUDOCT_BATCH_ATLAS to the atlas path to enable these checks.
    skip('Batch_atlas checks', ...
        sprintf('Batch_atlas/ not found at %s; set PSEUDOCT_BATCH_ATLAS to enable', ...
                batch_atlas_path));
else
    if atlas_dir_ok
        check('Batch_atlas/ directory', true, '');
    else
        check('Batch_atlas/ directory', false, ...
            sprintf('PSEUDOCT_BATCH_ATLAS=%s but dir not found', batch_atlas_path));
    end

    if atlas_dir_ok
        check('TPM.nii exists', ...
            exist(fullfile(batch_atlas_path, 'TPM.nii'), 'file') == 2, '');
        check('ch2.nii exists', ...
            exist(fullfile(batch_atlas_path, 'ch2.nii'), 'file') == 2, '');

        templates_ok = true;
        for i = 0:6
            fn = sprintf('Template_%d.nii', i);
            if exist(fullfile(batch_atlas_path, fn), 'file') ~= 2
                templates_ok = false;
            end
        end
        check('7 DARTEL templates exist', templates_ok, '');
    end

    %% 5. SSH JAR exists
    if atlas_dir_ok
        check('ganymed-ssh2-build250.jar', ...
            exist(fullfile(batch_atlas_path, 'ganymed-ssh2-build250', ...
            'ganymed-ssh2-build250.jar'), 'file') == 2, '');
    end
end

%% 6. Changelog contract
check('CHANGELOG.md exists', ...
    exist(fullfile(root_dir, 'CHANGELOG.md'), 'file') == 2);
check('version.txt absent', ...
    exist(fullfile(root_dir, 'version.txt'), 'file') == 0, ...
    'version.txt must be deleted — replaced by CHANGELOG.md');

% 6a. Line-1 version parse — must be non-empty and match semver pattern
try
    fid_v = fopen(fullfile(root_dir, 'CHANGELOG.md'), 'r');
    line1 = strtrim(fgetl(fid_v));
    fclose(fid_v);
    ok_line1 = ~isempty(line1) && ischar(line1) && ...
               ~isempty(regexp(line1, '^\d+\.\d+(\.\d+)?$', 'once'));
    check('CHANGELOG.md line 1 is parseable version (e.g., 2.6.0)', ok_line1, ...
        sprintf('got: ''%s''', line1));
catch ME
    check('CHANGELOG.md line 1 is parseable version (e.g., 2.6.0)', false, ME.message);
end

% 6b. Export helper exists and parses
helper_path = fullfile(root_dir, 'src', 'io', 'pseudo_CT_write_version_log.m');
check('src/io/pseudo_CT_write_version_log.m exists', ...
    exist(helper_path, 'file') == 2);
try
    mlint(helper_path);
    check('src/io/pseudo_CT_write_version_log.m parses', true, '');
catch ME
    check('src/io/pseudo_CT_write_version_log.m parses', false, ME.message);
end

% 6c. Makefile contract — package target structural checks
makefile_path = fullfile(root_dir, 'Makefile');
if exist(makefile_path, 'file') == 2
    fid_m = fopen(makefile_path, 'r');
    mf_content = fread(fid_m, inf, '*char')';
    fclose(fid_m);
    check('Makefile ships CHANGELOG.md (cp CHANGELOG.md)', ...
        ~isempty(strfind(mf_content, 'cp CHANGELOG.md')), ...
        'expected cp CHANGELOG.md in package target');
    check('Makefile: VERSION reads from CHANGELOG.md', ...
        ~isempty(strfind(mf_content, 'head -n 1 CHANGELOG.md')), ...
        'expected VERSION to parse CHANGELOG.md line 1');
    check('Makefile excludes version.txt', ...
        isempty(strfind(mf_content, 'cp version.txt')), ...
        'cp version.txt must not appear');
    check('Makefile excludes dev Makefile (cp Makefile)', ...
        isempty(strfind(mf_content, 'cp Makefile')), ...
        'cp Makefile must not appear');
    check('Makefile excludes scripts/ (cp -r scripts)', ...
        isempty(strfind(mf_content, 'cp -r scripts')), ...
        'cp -r scripts must not appear');
else
    check('Makefile contract (not found)', false, 'Makefile missing');
end

%% 6d. BEHAVIORAL: pseudo_CT_write_version_log — normal-copy path
% Execute the real helper from the repo: verifies exact CHANGELOG.md copy.
sandbox_normal = tempname;
mkdir(sandbox_normal);
cleanup_sn = onCleanup(@() rmdir(sandbox_normal, 's'));
addpath(fullfile(root_dir, 'src', 'io'));
cleanup_ap_n = onCleanup(@() rmpath(fullfile(root_dir, 'src', 'io')));
normal_status = pseudo_CT_write_version_log('2.6.0', sandbox_normal);
check('Behavioral: normal path status == 1', ...
    normal_status == 1, sprintf('got %d', normal_status));
out_file = fullfile(sandbox_normal, 'Pseudo_CT_AC_Version.txt');
check('Behavioral: normal output file exists', ...
    exist(out_file, 'file') == 2, 'output file not created');
fid1 = fopen(out_file, 'r');
out_c = fread(fid1, inf, '*char')';
fclose(fid1);
fid2 = fopen(fullfile(root_dir, 'CHANGELOG.md'), 'r');
ch_c = fread(fid2, inf, '*char')';
fclose(fid2);
check('Behavioral: normal path exact CHANGELOG.md copy (isequal)', ...
    isequal(out_c, ch_c), 'output differs from CHANGELOG.md');

%% 6e. BEHAVIORAL: pseudo_CT_write_version_log — fallback path
% Create a phantom directory without CHANGELOG.md.
% The helper resolves root from its own mfilename('fullpath'),
% so a copy in a phantom tree with no CHANGELOG.md will trigger fallback.
% addpath inserts at the front of the path, so the phantom copy is
% found before the real repo copy (still on path from section 6d).
phantom_root = tempname;
mkdir(fullfile(phantom_root, 'src', 'io'));
copyfile(fullfile(root_dir, 'src', 'io', 'pseudo_CT_write_version_log.m'), ...
         fullfile(phantom_root, 'src', 'io', 'pseudo_CT_write_version_log.m'));
sandbox_fb = tempname;
mkdir(sandbox_fb);
cleanup_sf = onCleanup(@() rmdir(sandbox_fb, 's'));
cleanup_pr = onCleanup(@() rmdir(phantom_root, 's'));
addpath(fullfile(phantom_root, 'src', 'io'));
cleanup_ap_f = onCleanup(@() rmpath(fullfile(phantom_root, 'src', 'io')));
fb_status = pseudo_CT_write_version_log('2.6.0', sandbox_fb);
check('Behavioral: fallback status == 0', ...
    fb_status == 0, sprintf('got %d', fb_status));
fb_out = fullfile(sandbox_fb, 'Pseudo_CT_AC_Version.txt');
check('Behavioral: fallback file exists', ...
    exist(fb_out, 'file') == 2, 'fallback file not created');
fid_fb = fopen(fb_out, 'r');
fb_c = fread(fid_fb, inf, '*char')';
fclose(fid_fb);
check('Behavioral: fallback contains code_version', ...
    ~isempty(strfind(fb_c, '2.6.0')), 'version not in fallback output');
check('Behavioral: fallback contains Date: header', ...
    ~isempty(strfind(fb_c, 'Date:')), 'date not in fallback output');

%% 6f. Lightweight package-recipe structural verification
% Parses the Makefile package recipe to verify shipped and excluded files.
% Does NOT execute `make package` — avoids NFS stale-handle issues.
% Literal `make package` verification remains a manual step for release prep.
if exist(makefile_path, 'file') == 2
    pkg_start = strfind(mf_content, 'package:');
    if ~isempty(pkg_start)
        recipe = mf_content(pkg_start:end);
        % Positive: shipped files
        check('Package-recipe: ships run_pseudo_CT_local.m', ...
            ~isempty(strfind(recipe, 'cp run_pseudo_CT_local.m')), '');
        check('Package-recipe: ships run_pseudo_CT_launchpad.m', ...
            ~isempty(strfind(recipe, 'cp run_pseudo_CT_launchpad.m')), '');
        check('Package-recipe: ships CHANGELOG.md (cp CHANGELOG.md)', ...
            ~isempty(strfind(recipe, 'cp CHANGELOG.md')), '');
        check('Package-recipe: ships src/', ...
            ~isempty(strfind(recipe, 'cp -r src')), '');
        check('Package-recipe: ships vers/', ...
            ~isempty(strfind(recipe, 'cp -r vers')), '');
        check('Package-recipe: ships spm8-r6313/', ...
            ~isempty(strfind(recipe, 'cp -r spm8-r6313')), '');
        check('Package-recipe: ships imgaussian/', ...
            ~isempty(strfind(recipe, 'cp -r imgaussian')), '');
        check('Package-recipe: ships ssh2_v2_m1_r5/', ...
            ~isempty(strfind(recipe, 'cp -r ssh2_v2_m1_r5')), '');
        % Negative: excluded dev files
        check('Package-recipe: excludes version.txt', ...
            isempty(strfind(recipe, 'version.txt')), '');
        check('Package-recipe: excludes Makefile (no cp Makefile)', ...
            isempty(strfind(recipe, 'cp Makefile')), '');
        check('Package-recipe: excludes scripts/ (no cp -r scripts)', ...
            isempty(strfind(recipe, 'cp -r scripts')), '');
    else
        check('Package recipe', false, 'Makefile has no package target');
    end
end

%% Summary
fprintf('\n=== Results: %d passed, %d failed, %d skipped ===\n', ...
        num_passed, num_failed, num_skipped);
if num_failed > 0
    error('Smoke tests failed.');
end
end
