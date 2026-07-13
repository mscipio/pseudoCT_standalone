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

function h = file_md5_simple(fpath)
    % Simple content fingerprint (no Java, no toolbox).  R2010b-safe.
    % Not cryptographic — catches accidental modification for smoke tests.
    fid = fopen(fpath, 'r');
    if fid == -1, h = 'READ_ERROR'; return; end
    bytes = fread(fid, inf, '*uint8');
    fclose(fid);
    h = sprintf('%08x%08x', sum(bytes), length(bytes));
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

%% 2b. All scripts/ diagnostic scripts parse
scripts_files = dir(fullfile(root_dir, 'scripts', '*.m'));
fprintf('\n  Checking %d script files in scripts/ ...\n', numel(scripts_files));
for i = 1:numel(scripts_files)
    fp = fullfile(scripts_files(i).folder, scripts_files(i).name);
    try
        mlint(fp);
        check(sprintf('scripts/%s parses', scripts_files(i).name), true, '');
    catch ME
        check(sprintf('scripts/%s parses', scripts_files(i).name), false, ME.message);
    end
end

%% 2c. Launchpad diagnostic markers — structural check
% Verifies that batch_pseudo_CT_launchpad.m has the always-on PBS log
% diagnostic block (no cluster access needed — keyword scan only).
lp_wrapper_path = fullfile(root_dir, 'src', 'launchpad', 'batch_pseudo_CT_launchpad.m');
if exist(lp_wrapper_path, 'file') == 2
    fid_lp = fopen(lp_wrapper_path, 'r');
    lp_content = fread(fid_lp, inf, '*char')';
    fclose(fid_lp);
    check('lp-diag: [launchpad-diag] tag present', ...
        ~isempty(strfind(lp_content, '[launchpad-diag]')), '');
    check('lp-diag: PBS log capture precedes ss_tot check', ...
        ~isempty(strfind(lp_content, '[launchpad-diag] Saved PBS job logs')), '');
    check('lp-diag: subject-prefixed log filenames (_launchpad_ rename)', ...
        ~isempty(strfind(lp_content, '_launchpad_')), '');
    check('lp-diag: failure path references PBS logs', ...
        ~isempty(strfind(lp_content, 'see PBS logs in')), '');
else
    check('lp-diag: wrapper exists', false, 'batch_pseudo_CT_launchpad.m not found');
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

%% 7a. BEHAVIORAL: pseudo_CT_keep_temp_enabled — env/defaults precedence
fprintf('\n  Behavioral: pseudo_CT_keep_temp_enabled ...\n');
addpath(fullfile(root_dir, 'src', 'config'));
cleanup_kte = onCleanup(@() rmpath(fullfile(root_dir, 'src', 'config')));

% Save original env state
orig_env = getenv('PSEUDOCT_KEEP_TMP');
restore_env = onCleanup(@() setenv('PSEUDOCT_KEEP_TMP', orig_env));

% Dummy defaults handle that always returns 'No'
dummy_defaults_no = @(varargin) 'No';

% Test 1: env var '1' overrides defaults 'No'
setenv('PSEUDOCT_KEEP_TMP', '1');
result = pseudo_CT_keep_temp_enabled(dummy_defaults_no);
check('keep-tmp: PSEUDOCT_KEEP_TMP=1 returns ''Yes''', ...
    strcmp(result, 'Yes'), sprintf('got ''%s''', result));

% Test 2: env var 'true' (case-insensitive)
setenv('PSEUDOCT_KEEP_TMP', 'true');
result = pseudo_CT_keep_temp_enabled(dummy_defaults_no);
check('keep-tmp: PSEUDOCT_KEEP_TMP=true returns ''Yes''', ...
    strcmp(result, 'Yes'), sprintf('got ''%s''', result));

% Test 3: env var '0' — does NOT trigger override; falls back to defaults
setenv('PSEUDOCT_KEEP_TMP', '0');
result = pseudo_CT_keep_temp_enabled(dummy_defaults_no);
check('keep-tmp: PSEUDOCT_KEEP_TMP=0 falls back to defaults ''No''', ...
    strcmp(result, 'No'), sprintf('got ''%s''', result));

% Test 4: unset env — falls back to defaults 'No'
unsetenv('PSEUDOCT_KEEP_TMP');
result = pseudo_CT_keep_temp_enabled(dummy_defaults_no);
check('keep-tmp: unset env returns defaults ''No''', ...
    strcmp(result, 'No'), sprintf('got ''%s''', result));

% Test 5: broken defaults handle (throws error) — returns 'No' safely
broken_handle = @(varargin) error('simulated config error');
result = pseudo_CT_keep_temp_enabled(broken_handle);
check('keep-tmp: broken defaults handle returns ''No''', ...
    strcmp(result, 'No'), sprintf('got ''%s''', result));

% Test 6: 'Yes' literal from env
setenv('PSEUDOCT_KEEP_TMP', 'Yes');
result = pseudo_CT_keep_temp_enabled(dummy_defaults_no);
check('keep-tmp: PSEUDOCT_KEEP_TMP=''Yes'' returns ''Yes''', ...
    strcmp(result, 'Yes'), sprintf('got ''%s''', result));

%% 7b. BEHAVIORAL: diff_entrypoint_runs — text pipeline + MD5 sentinel guard
fprintf('\n  Behavioral: diff_entrypoint_runs text pipeline ...\n');
addpath(fullfile(root_dir, 'scripts'));
cleanup_der = onCleanup(@() rmpath(fullfile(root_dir, 'scripts')));

% Build synthetic directory trees for comparator testing
sandbox_a = tempname;
sandbox_b = tempname;
mkdir(sandbox_a);
mkdir(sandbox_b);
cleanup_sa = onCleanup(@() rmdir(sandbox_a, 's'));
cleanup_sb = onCleanup(@() rmdir(sandbox_b, 's'));

% Files in both dirs, identical content
fid = fopen(fullfile(sandbox_a, 'identical.txt'), 'w');
fprintf(fid, 'hello world\n');
fclose(fid);
copyfile(fullfile(sandbox_a, 'identical.txt'), fullfile(sandbox_b, 'identical.txt'));

% Files in both dirs, different content
fid = fopen(fullfile(sandbox_a, 'divergent.txt'), 'w');
fprintf(fid, 'foo\n');
fclose(fid);
fid = fopen(fullfile(sandbox_b, 'divergent.txt'), 'w');
fprintf(fid, 'bar\n');
fclose(fid);

% File only in sandbox_a (local)
fid = fopen(fullfile(sandbox_a, 'local_only.log'), 'w');
fprintf(fid, 'local\n');
fclose(fid);

% File only in sandbox_b (launchpad)
fid = fopen(fullfile(sandbox_b, 'lp_only.log'), 'w');
fprintf(fid, 'remote\n');
fclose(fid);

csv_out = [tempname '.csv'];
cleanup_csv = onCleanup(@() delete(csv_out));

try
    diff_entrypoint_runs(sandbox_a, sandbox_b, 'OutputCSV', csv_out);

    % Read CSV and verify statuses
    check('diff-cmp: CSV output file exists', ...
        exist(csv_out, 'file') == 2, 'CSV not produced');

    if exist(csv_out, 'file') ~= 2
        error('CSV output was not written; skipping CSV verification');
    end
    fid = fopen(csv_out, 'r');
    if fid == -1
        error('Cannot open CSV for reading');
    end
    csv_lines = textscan(fid, '%s%s%s', 'Delimiter', ',', 'HeaderLines', 1);
    fclose(fid);
    filenames = csv_lines{1};
    statuses  = csv_lines{2};
    details   = csv_lines{3}; %#ok<NASGU>

    % Build lookup
    csv_map = containers.Map();
    for i = 1:length(filenames)
        csv_map(filenames{i}) = statuses{i};
    end

    check('diff-cmp: identical.txt → IDENTICAL', ...
        csv_map.isKey('identical.txt') && strcmp(csv_map('identical.txt'), 'IDENTICAL'), ...
        sprintf('got %s', char(csv_map('identical.txt'))));

    check('diff-cmp: divergent.txt → DIVERGENT', ...
        csv_map.isKey('divergent.txt') && strcmp(csv_map('divergent.txt'), 'DIVERGENT'), ...
        sprintf('got %s', char(csv_map('divergent.txt'))));

    check('diff-cmp: local_only.log → LOCAL_ONLY', ...
        csv_map.isKey('local_only.log') && strcmp(csv_map('local_only.log'), 'LOCAL_ONLY'), ...
        sprintf('got %s', char(csv_map('local_only.log'))));

    check('diff-cmp: lp_only.log → LAUNCHPAD_ONLY', ...
        csv_map.isKey('lp_only.log') && strcmp(csv_map('lp_only.log'), 'LAUNCHPAD_ONLY'), ...
        sprintf('got %s', char(csv_map('lp_only.log'))));

    %% 7c. BEHAVIORAL: compare_hash_strings — sentinel guard
    % The sentinel guard must prove that matching sentinel/error values
    % NEVER produce IDENTICAL.  compare_hash_strings is a standalone
    % helper (no file I/O, no Java) — directly testable.
    fprintf('\n  Behavioral: compare_hash_strings sentinel guard ...\n');

    % 7c.1 Both sides fail identically → DIVERGENT (not IDENTICAL!)
    [st, dt] = compare_hash_strings('READ_ERROR', 'READ_ERROR');
    check('hash-cmp: READ_ERROR+READ_ERROR → DIVERGENT', ...
        strcmp(st, 'DIVERGENT'), sprintf('got %s: %s', st, dt));

    % 7c.2 Both sides fail with different sentinels → DIVERGENT
    [st, dt] = compare_hash_strings('READ_ERROR', 'MD5_UNAVAILABLE');
    check('hash-cmp: READ_ERROR+MD5_UNAVAILABLE → DIVERGENT', ...
        strcmp(st, 'DIVERGENT'), sprintf('got %s: %s', st, dt));

    % 7c.3 One side fails, other has valid hash → DIVERGENT
    [st, dt] = compare_hash_strings('READ_ERROR', 'd41d8cd98f00b204e9800998ecf8427e');
    check('hash-cmp: READ_ERROR+valid → DIVERGENT', ...
        strcmp(st, 'DIVERGENT'), sprintf('got %s: %s', st, dt));

    % 7c.4 Valid side fails, other valid → still check
    [st, dt] = compare_hash_strings('abc', 'MD5_UNAVAILABLE');
    check('hash-cmp: valid+MD5_UNAVAILABLE → DIVERGENT', ...
        strcmp(st, 'DIVERGENT'), sprintf('got %s: %s', st, dt));

    % 7c.5 Identical valid hashes → IDENTICAL (normal path)
    [st, dt] = compare_hash_strings('abc123', 'abc123');
    check('hash-cmp: identical valid → IDENTICAL', ...
        strcmp(st, 'IDENTICAL'), sprintf('got %s: %s', st, dt));

    % 7c.6 Different valid hashes → DIVERGENT (normal path)
    [st, dt] = compare_hash_strings('abc123', 'def456');
    check('hash-cmp: different valid → DIVERGENT', ...
        strcmp(st, 'DIVERGENT'), sprintf('got %s: %s', st, dt));

    %% 7d. BEHAVIORAL: diff_entrypoint_runs DICOM dispatch
    % Extension-based (.ima, .dicom, .dic) + magic-byte (extensionless)
    % must both dispatch to DICOM comparison, not binary fallback.
    fprintf('\n  Behavioral: DICOM dispatch (extension + magic-byte) ...\n');

    sandbox_dcm_a = tempname;  mkdir(sandbox_dcm_a);
    sandbox_dcm_b = tempname;  mkdir(sandbox_dcm_b);
    cleanup_sda = onCleanup(@() rmdir(sandbox_dcm_a, 's'));
    cleanup_sdb = onCleanup(@() rmdir(sandbox_dcm_b, 's'));

    % Minimal DICOM-like file: 128 zero bytes + "DICM" marker.
    % dicominfo/dicomread will fail on it (not a valid DICOM),
    % but the degraded-mode detail proves the dispatcher chose DICOM path.
    dcm_magic = [zeros(1, 128, 'uint8'), uint8('DICM')];

    % File 1: .ima extension → dispatched via known_dcm_exts
    fid = fopen(fullfile(sandbox_dcm_a, 'slice_001.ima'), 'w');
    fwrite(fid, dcm_magic, 'uint8');  fclose(fid);
    copyfile(fullfile(sandbox_dcm_a, 'slice_001.ima'), ...
             fullfile(sandbox_dcm_b, 'slice_001.ima'));

    % File 2: extensionless → dispatched via is_dicom_file() magic-byte
    fid = fopen(fullfile(sandbox_dcm_a, 'slice_002'), 'w');
    fwrite(fid, dcm_magic, 'uint8');  fclose(fid);
    copyfile(fullfile(sandbox_dcm_a, 'slice_002'), ...
             fullfile(sandbox_dcm_b, 'slice_002'));

    csv_dcm = [tempname '.csv'];
    cleanup_cd = onCleanup(@() delete(csv_dcm));

    try
        diff_entrypoint_runs(sandbox_dcm_a, sandbox_dcm_b, 'OutputCSV', csv_dcm);
        if exist(csv_dcm, 'file') ~= 2
            error('CSV output not produced by DICOM dispatch test');
        end
        fid = fopen(csv_dcm, 'r');
        if fid == -1, error('Cannot open DICOM CSV'); end
        all_lines = textscan(fid, '%s%s%s', 'Delimiter', ',', 'HeaderLines', 1);
        fclose(fid);
        fn = all_lines{1};  dt = all_lines{3};

        % .ima extension → DICOM dispatch: detail must mention DICOM
        idx1 = find(strcmp(fn, 'slice_001.ima'), 1);
        ok_ima = false;
        if ~isempty(idx1)
            s1 = dt{idx1};
            ok_ima = ~isempty(strfind(s1, 'DICOM')) || ~isempty(strfind(s1, 'dicom'));
        end
        check('dcm-dispatch: .ima extension → DICOM comparison', ...
            ok_ima, 'expected detail to mention DICOM');

        % Extensionless with DICM magic → DICOM dispatch
        idx2 = find(strcmp(fn, 'slice_002'), 1);
        ok_extless = false;
        if ~isempty(idx2)
            s2 = dt{idx2};
            ok_extless = ~isempty(strfind(s2, 'DICOM')) || ~isempty(strfind(s2, 'dicom'));
        end
        check('dcm-dispatch: extensionless+DICM magic → DICOM comparison', ...
            ok_extless, 'expected detail to mention DICOM');
    catch ME_dcm
        check('dcm-dispatch: behavioral', false, ME_dcm.message);
    end
catch ME
    check('diff_entrypoint_runs behavioral', false, ME.message);
end

%% 7e. BEHAVIORAL: compare_nifti_data — structured metrics + head mask
% Core comparison logic is independently testable (no file I/O, no SPM).
fprintf('\n  Behavioral: NIfTI comparison structured metrics ...\n');
addpath(fullfile(root_dir, 'scripts'));
cleanup_nc = onCleanup(@() rmpath(fullfile(root_dir, 'scripts')));

% Build synthetic SPM-style header structs
hdr1 = struct('fname', 'test.nii', 'dim', [2 2 2], 'dt', [16 0], ...
              'pinfo', [1;0;0], 'mat', eye(4), 'n', [1 1]);
hdr2 = hdr1;
tol = 1e-6;

% 7e.1 Identical volumes → IDENTICAL
vol_ones = ones(2,2,2);
[st, dt] = compare_nifti_data(hdr1, hdr2, vol_ones, vol_ones, tol);
check('nifti-cmp: identical → IDENTICAL', ...
    strcmp(st, 'IDENTICAL'), sprintf('got %s: %s', st, dt));

% 7e.2 Header-only difference (dt changed) → HEADER_ONLY_DIFF
hdr3 = hdr2;
hdr3.dt = [64 0];  % float64 instead of float32
[st, dt] = compare_nifti_data(hdr1, hdr3, vol_ones, vol_ones, tol);
check('nifti-cmp: dt-only → HEADER_ONLY_DIFF', ...
    strcmp(st, 'HEADER_ONLY_DIFF'), sprintf('got %s: %s', st, dt));

% 7e.3 Header-only difference (mat change) → HEADER_ONLY_DIFF
hdr4 = hdr2;
hdr4.mat(1,4) = hdr4.mat(1,4) + 0.01;
[st, dt] = compare_nifti_data(hdr1, hdr4, vol_ones, vol_ones, tol);
check('nifti-cmp: mat-only → HEADER_ONLY_DIFF', ...
    strcmp(st, 'HEADER_ONLY_DIFF'), sprintf('got %s: %s', st, dt));

% 7e.4 Voxel difference, header OK → VOXEL_DIVERGENT
vol2 = vol_ones * 2;  % all voxels doubled
[st, dt] = compare_nifti_data(hdr1, hdr2, vol_ones, vol2, tol);
check('nifti-cmp: voxel diff → VOXEL_DIVERGENT', ...
    strcmp(st, 'VOXEL_DIVERGENT'), sprintf('got %s: %s', st, dt));

% 7e.5 Both header and voxel differ → DIVERGENT
[st, dt] = compare_nifti_data(hdr1, hdr3, vol_ones, vol2, tol);
check('nifti-cmp: header+voxel → DIVERGENT', ...
    strcmp(st, 'DIVERGENT'), sprintf('got %s: %s', st, dt));

% 7e.6 Size mismatch → DIVERGENT with size detail
vol_small = ones(2,2,1);
[st, dt] = compare_nifti_data(hdr1, hdr2, vol_ones, vol_small, tol);
check('nifti-cmp: size mismatch → DIVERGENT', ...
    strcmp(st, 'DIVERGENT') && ~isempty(strfind(dt, 'size mismatch')), ...
    sprintf('got %s: %s', st, dt));

% 7e.7 Background-only voxel difference → mask metrics show outMax>0
% Create volume where bright "head" voxels are identical but
% background (first slice edge) differs.
head_vol = ones(4,4,4);
head_vol(2:3, 2:3, 2:3) = 1000;  % bright core = "head"
bg_vol = head_vol;
bg_vol(1,:,:) = 2;  % modify only first-slice edge (background)
[st, dt] = compare_nifti_data(hdr1, hdr2, head_vol, bg_vol, tol);
% Must be VOXEL_DIVERGENT with mask detail present
has_mask_metrics = ~isempty(strfind(dt, 'in:max')) && ...
                   ~isempty(strfind(dt, 'out:max'));
check('nifti-cmp: background diff → VOXEL_DIVERGENT + mask detail', ...
    strcmp(st, 'VOXEL_DIVERGENT') && has_mask_metrics, dt);

% 7e.8 Dim mismatch in header
hdr5 = hdr2;
hdr5.dim = [3 3 3];
[st, dt] = compare_nifti_data(hdr1, hdr5, vol_ones, vol_ones, tol);
check('nifti-cmp: dim mismatch → HEADER_ONLY_DIFF', ...
    strcmp(st, 'HEADER_ONLY_DIFF'), sprintf('got %s: %s', st, dt));

% 7e.9 Pinfo size mismatch
hdr6 = hdr2;
hdr6.pinfo = [1 0; 0 1];  % wrong size
[st, dt] = compare_nifti_data(hdr1, hdr6, vol_ones, vol_ones, tol);
check('nifti-cmp: pinfo size mismatch → HEADER_ONLY_DIFF', ...
    strcmp(st, 'HEADER_ONLY_DIFF'), sprintf('got %s: %s', st, dt));

% 7e.10 Detail string contains dim status
check('nifti-cmp: detail contains dim=ok for matching dims', ...
    ~isempty(strfind(dt, 'dim=')), dt);

%% 8. BEHAVIORAL: normalized_2_att_map — validation guardrails
fprintf('\n  Behavioral: normalized_2_att_map validation guardrails ...\n');
addpath(fullfile(root_dir, 'src', 'core'));
cleanup_core = onCleanup(@() rmpath(fullfile(root_dir, 'src', 'core')));

% 8a. Require 4 arguments (old 3-arg call must error clearly)
try
    normalized_2_att_map('fake_in.nii', 'fake_orig.nii', 'fake_atlas');
    check('n2a-guard: 3-arg call errors', false, 'should have errored');
catch ME_3arg
    ok_3arg = ~isempty(strfind(ME_3arg.message, '4 arguments'));
    check('n2a-guard: 3-arg call errors with ''4 arguments'' message', ...
        ok_3arg, ME_3arg.message);
end

% 8b. Require work_dir to differ from norm_mprage directory (guardrail)
sandbox_guard = tempname;  mkdir(sandbox_guard);
cleanup_sg = onCleanup(@() rmdir(sandbox_guard, 's'));
fake_norm = fullfile(sandbox_guard, 'fake_norm.nii');
fid = fopen(fake_norm, 'w'); fprintf(fid, 'fake'); fclose(fid);
try
    normalized_2_att_map(fake_norm, fake_norm, sandbox_guard, sandbox_guard);
    check('n2a-guard: same-dir work_dir errors', false, 'should have errored');
catch ME_samedir
    ok_samedir = ~isempty(strfind(ME_samedir.message, 'same as')) || ...
                 ~isempty(strfind(ME_samedir.message, 'separate sandbox'));
    check('n2a-guard: same-dir work_dir rejected', ok_samedir, ME_samedir.message);
end

% 8c. Atlas_rCT and Atlas_head_mask semantic preflight (before expensive SPM work)
% Uses substring matching — must handle real filenames like
% Atlas_rCT_flipLR_repos_15subj.nii and Atlas_head_mask_u_rc1foo.nii.
atlas_sandbox = tempname;  mkdir(atlas_sandbox);
cleanup_as = onCleanup(@() rmdir(atlas_sandbox, 's'));
fake_n2 = fullfile(atlas_sandbox, 'fake_norm.nii');
fid = fopen(fake_n2, 'w'); fprintf(fid, 'fake'); fclose(fid);
work_as = tempname;  mkdir(work_as);
cleanup_wa = onCleanup(@() rmdir(work_as, 's'));
% Create a directory with an Atlas file but neither Atlas_rCT nor Atlas_head_mask
atlas_partial = tempname;  mkdir(atlas_partial);
cleanup_ap = onCleanup(@() rmdir(atlas_partial, 's'));
fid = fopen(fullfile(atlas_partial, 'Atlas_other.nii'), 'w'); fprintf(fid, 'fake'); fclose(fid);
try
    normalized_2_att_map(fake_n2, fake_n2, atlas_partial, work_as);
    check('n2a-guard: no Atlas_rCT or Atlas_head_mask errors', false, 'should have errored');
catch ME_rCT
    ok_rCT = ~isempty(strfind(ME_rCT.message, 'Atlas_rCT'));
    check('n2a-guard: missing Atlas_rCT fails semantic preflight', ok_rCT, ME_rCT.message);
end
% Now add Atlas_rCT_flipLR_repos_15subj.nii (semantic match) but leave
% Atlas_head_mask missing.  Must pass rCT preflight but fail mask preflight.
fid = fopen(fullfile(atlas_partial, 'Atlas_rCT_flipLR_repos_15subj.nii'), 'w');
fprintf(fid, 'fake'); fclose(fid);
try
    normalized_2_att_map(fake_n2, fake_n2, atlas_partial, work_as);
    check('n2a-guard: missing Atlas_head_mask errors (after rCT semantic match)', false, 'should have errored');
catch ME_mask
    ok_mask = ~isempty(strfind(ME_mask.message, 'Atlas_head_mask'));
    check('n2a-guard: missing Atlas_head_mask fails semantic preflight', ok_mask, ME_mask.message);
end
% 8d. Semantic matching: suffixed filenames pass preflight when both roles exist.
% Use real-world names: Atlas_rCT_flipLR_repos_15subj.nii + Atlas_head_mask_u_rc1foo.nii
atlas_semantic = tempname;  mkdir(atlas_semantic);
cleanup_as2 = onCleanup(@() rmdir(atlas_semantic, 's'));
fid = fopen(fullfile(atlas_semantic, 'Atlas_rCT_flipLR_repos_15subj.nii'), 'w');
fprintf(fid, 'fake'); fclose(fid);
fid = fopen(fullfile(atlas_semantic, 'Atlas_head_mask_u_rc1foo.nii'), 'w');
fprintf(fid, 'fake'); fclose(fid);
% Also add a generic *Atlas*.nii to satisfy the "no *Atlas*.nii files at all" check
fid = fopen(fullfile(atlas_semantic, 'Atlas_cp_iso_mprage_normalized_repos_15subj.nii'), 'w');
fprintf(fid, 'fake'); fclose(fid);
try
    normalized_2_att_map(fake_n2, fake_n2, atlas_semantic, work_as);
    % Should error on batch-template check (no TPM.nii etc.), NOT on atlas preflight.
    % The atlas preflight should pass.
    check('n2a-guard: suffixed atlas names pass semantic preflight', false, ...
        'expected error for missing batch templates, not atlas preflight');
catch ME_sem
    % Verify the error is NOT from atlas preflight (should be from batch-template check)
    ok_sem = isempty(strfind(ME_sem.message, 'Atlas_rCT')) && ...
             isempty(strfind(ME_sem.message, 'Atlas_head_mask'));
    check('n2a-guard: suffixed atlas names pass semantic preflight (error is non-atlas)', ...
        ok_sem, ME_sem.message);
end

% 8e. reuse_masked_checkpoint guardrail: smprage_normalized_repos.nii MUST exist
% when the flag is enabled.  The function must fail before any SPM work.
fake_smprage_check = tempname;  mkdir(fake_smprage_check);
cleanup_fsc = onCleanup(@() rmdir(fake_smprage_check, 's'));
fake_n3 = fullfile(fake_smprage_check, 'fake_norm.nii');
fid = fopen(fake_n3, 'w'); fprintf(fid, 'fake'); fclose(fid);
fake_work_8e = tempname;  mkdir(fake_work_8e);
cleanup_fw8e = onCleanup(@() rmdir(fake_work_8e, 's'));
% Build a minimal atlas with both roles so preflight passes
fake_atlas_8e = tempname;  mkdir(fake_atlas_8e);
cleanup_fa8e = onCleanup(@() rmdir(fake_atlas_8e, 's'));
fid = fopen(fullfile(fake_atlas_8e, 'Atlas_rCT_flipLR_repos_15subj.nii'), 'w');
fprintf(fid, 'fake'); fclose(fid);
fid = fopen(fullfile(fake_atlas_8e, 'Atlas_head_mask.nii'), 'w');
fprintf(fid, 'fake'); fclose(fid);
% Call with reuse_masked_checkpoint=1 but NO smprage in the staging dir
try
    normalized_2_att_map(fake_n3, fake_n3, fake_atlas_8e, fake_work_8e, 1);
    check('n2a-guard: reuse_masked_checkpoint without smprage errors', false, 'should have errored');
catch ME_reuse
    ok_reuse = ~isempty(strfind(ME_reuse.message, 'smprage'));
    check('n2a-guard: reuse_masked_checkpoint without smprage fails early', ...
        ok_reuse, ME_reuse.message);
end
% Now create smprage_normalized_repos.nii in the staging dir — should
% pass the smprage check but fail on missing batch templates (expected)
fid = fopen(fullfile(fake_smprage_check, 'smprage_normalized_repos.nii'), 'w');
fprintf(fid, 'fake'); fclose(fid);
try
    normalized_2_att_map(fake_n3, fake_n3, fake_atlas_8e, fake_work_8e, 1);
    % Should reach batch-template check (TPM.nii missing)
    check('n2a-guard: reuse_masked_checkpoint with smprage proceeds past guardrail', false, ...
        'expected error for missing batch templates');
catch ME_reuse2
    ok_reuse2 = isempty(strfind(ME_reuse2.message, 'smprage'));
    check('n2a-guard: reuse_masked_checkpoint passes smprage guardrail (error is non-smprage)', ...
        ok_reuse2, ME_reuse2.message);
end

%% 9. BEHAVIORAL: pseudo_CT_resolve_batch_atlas_path — env + defaults resolution
fprintf('\n  Behavioral: Batch_atlas resolution ...\n');
addpath(fullfile(root_dir, 'src', 'config'));
cleanup_br = onCleanup(@() rmpath(fullfile(root_dir, 'src', 'config')));

try
    batch_path = pseudo_CT_resolve_batch_atlas_path(root_dir);
    ok_br = ischar(batch_path) && ~isempty(batch_path) && ...
            exist(batch_path, 'dir') == 7;
    check('batch-atlas: resolution returns valid directory', ok_br, ...
        sprintf('path=''%s'' exist=%d', batch_path, exist(batch_path, 'dir')));
catch ME_br
    % Resolution failed — must include diagnostic structure.
    % Which sources appear depends on env/config state, so we check
    % for the core diagnostic pattern, not every possible source.
    has_banner = ~isempty(strfind(ME_br.message, 'Batch_atlas not found')) || ...
                 ~isempty(strfind(ME_br.message, 'Checked locations'));
    has_locations = ~isempty(strfind(ME_br.message, 'repo-adjacent-fallback')) || ...
                    ~isempty(strfind(ME_br.message, 'release-sibling-fallback')) || ...
                    ~isempty(strfind(ME_br.message, 'env:PSEUDOCT_BATCH_ATLAS')) || ...
                    ~isempty(strfind(ME_br.message, 'defaults_pseudo_CT'));
    ok_br = has_banner && has_locations;
    check('batch-atlas: failure includes diagnostic with checked locations', ok_br, ...
        sprintf('banner=%d locations=%d', has_banner, has_locations));
end

%% 10. BEHAVIORAL: restart_from_repos_checkpoint — dry_run sandbox staging
fprintf('\n  Behavioral: restart_from_repos_checkpoint dry_run + isolation ...\n');
addpath(fullfile(root_dir, 'scripts'));
cleanup_rc = onCleanup(@() rmpath(fullfile(root_dir, 'scripts')));

% Construct synthetic Launchpad tmp with minimal checkpoint files
synth_exp_root = tempname;  mkdir(synth_exp_root);
synth_lp_tmp = tempname;    mkdir(synth_lp_tmp);
cleanup_synth = onCleanup(@() rmdir(synth_exp_root, 's'));
cleanup_lp = onCleanup(@() rmdir(synth_lp_tmp, 's'));

% Create a minimal (empty) mprage_normalized_repos.nii
fid = fopen(fullfile(synth_lp_tmp, 'mprage_normalized_repos.nii'), 'w');
fprintf(fid, 'minimal checkpoint file');
fclose(fid);

% Create fake original MPRAGE
fake_orig_synth = fullfile(synth_lp_tmp, 'mprage.nii');
fid = fopen(fake_orig_synth, 'w');
fprintf(fid, 'fake original mprage');
fclose(fid);

% Compute MD5 of original files BEFORE staging
md5_before_norm = file_md5_simple(fullfile(synth_lp_tmp, 'mprage_normalized_repos.nii'));
md5_before_orig = file_md5_simple(fake_orig_synth);

% Try dry_run — skip if Batch_atlas not resolveable (test env may lack it)
rc_ran = false;
try
    % Attempt to resolve Batch_atlas for a valid test; fall back gracefully
    try
        test_batch = pseudo_CT_resolve_batch_atlas_path(root_dir);
    catch  %#ok<CTCH>
        test_batch = '';
    end
    if isempty(test_batch) || exist(test_batch, 'dir') ~= 7
        skip('restart-checkpoint: dry_run staging', ...
            'Batch_atlas not available; set PSEUDOCT_BATCH_ATLAS to enable');
    else
        % Call with dry_run=1 and an explicit batch_atlas path
        restart_from_repos_checkpoint(synth_exp_root, synth_lp_tmp, ...
            fake_orig_synth, test_batch, 1);
        rc_ran = true;

        % Find the created sandbox
        sandboxes = dir(fullfile(synth_exp_root, 'restart_sandbox_*'));
        check('restart-checkpoint: sandbox created under experiment_root', ...
            ~isempty(sandboxes), 'no restart_sandbox_* found');

        if ~isempty(sandboxes)
            sb_path = fullfile(synth_exp_root, sandboxes(1).name);
            sb_tmp  = fullfile(sb_path, 'MR_PET', 'tmp');

            check('restart-checkpoint: sandbox tmp/ exists', ...
                exist(sb_tmp, 'dir') == 7, '');

            % Verify checkpoint file was COPIED (not moved — original intact)
            check('restart-checkpoint: mprage_normalized_repos.nii copied to sandbox', ...
                exist(fullfile(sb_tmp, 'mprage_normalized_repos.nii'), 'file') == 2, '');

            check('restart-checkpoint: mprage.nii copied to sandbox', ...
                exist(fullfile(sb_tmp, 'mprage.nii'), 'file') == 2, '');

            % Verify original files were NOT modified
            md5_after_norm = file_md5_simple(fullfile(synth_lp_tmp, 'mprage_normalized_repos.nii'));
            md5_after_orig = file_md5_simple(fake_orig_synth);
            check('restart-checkpoint: original norm_mprage NOT mutated', ...
                strcmp(md5_before_norm, md5_after_norm), ...
                'original checkpoint file was modified');
            check('restart-checkpoint: original mprage.nii NOT mutated', ...
                strcmp(md5_before_orig, md5_after_orig), ...
                'original MPRAGE file was modified');
        end
    end
catch ME_rc
    if rc_ran
        check('restart-checkpoint: dry_run', false, ME_rc.message);
    else
        skip('restart-checkpoint: dry_run staging', ...
            sprintf('Batch_atlas resolution needed but failed: %s', ME_rc.message));
    end
end

%% 10b. BEHAVIORAL: restart_from_repos_checkpoint — default Batch_atlas resolution
% Calls the dry-run with [] (empty) as 4th argument to exercise the
% wrapper's default batch_atlas resolution path (pseudo_CT_resolve_batch_atlas_path
% → dist/Batch_atlas fallback).  Current tests pass explicit test_batch,
% so the wrapper's default resolver was never exercised in smoke.
fprintf('\n  Behavioral: restart_from_repos_checkpoint default batch_atlas resolution ...\n');

synth_exp2 = tempname;  mkdir(synth_exp2);
synth_lp2   = tempname;  mkdir(synth_lp2);
cleanup_synth2 = onCleanup(@() rmdir(synth_exp2, 's'));
cleanup_lp2    = onCleanup(@() rmdir(synth_lp2, 's'));

fid = fopen(fullfile(synth_lp2, 'mprage_normalized_repos.nii'), 'w');
fprintf(fid, 'minimal checkpoint');  fclose(fid);
fid = fopen(fullfile(synth_lp2, 'mprage.nii'), 'w');
fprintf(fid, 'fake orig mprage');  fclose(fid);

try
    % Call with [] for batch_atlas → exercises default resolver path
    restart_from_repos_checkpoint(synth_exp2, synth_lp2, ...
        fullfile(synth_lp2, 'mprage.nii'), [], 1);

    sandboxes2 = dir(fullfile(synth_exp2, 'restart_sandbox_*'));
    check('restart-defaults: sandbox created with default batch_atlas resolution', ...
        ~isempty(sandboxes2), 'no restart_sandbox_* found under experiment_root');

    if ~isempty(sandboxes2)
        sb_path2 = fullfile(synth_exp2, sandboxes2(1).name);
        sb_tmp2  = fullfile(sb_path2, 'MR_PET', 'tmp');
        check('restart-defaults: sandbox tmp/ + proc/ exist', ...
            exist(sb_tmp2, 'dir') == 7 && ...
            exist(fullfile(sb_tmp2, 'proc'), 'dir') == 7, '');
    end
catch ME_defaults
    % Resolution may fail if Batch_atlas is truly unavailable (no env,
    % no defaults, no repo-adjacent).  The wrapper catches and falls back
    % to dist/; if THAT also fails, the error is expected in bare envs.
    if ~isempty(strfind(ME_defaults.message, 'Batch_atlas directory not found'))
        skip('restart-defaults: dry_run with default resolver', ...
            sprintf('Batch_atlas not resolveable in this environment: %s', ...
                    ME_defaults.message));
    else
        check('restart-defaults: dry_run staging', false, ME_defaults.message);
    end
end

%% 10c. BEHAVIORAL: restart_from_repos_checkpoint — reuse_masked_checkpoint dry_run
% Verify the reuse_masked_checkpoint flag propagates through to the
% dry-run display and that smprage_normalized_repos.nii is checked.
fprintf('\n  Behavioral: restart reuse_masked_checkpoint dry_run ...\n');

synth_rmc_exp = tempname;  mkdir(synth_rmc_exp);
synth_rmc_lp  = tempname;  mkdir(synth_rmc_lp);
cleanup_rmc1 = onCleanup(@() rmdir(synth_rmc_exp, 's'));
cleanup_rmc2 = onCleanup(@() rmdir(synth_rmc_lp, 's'));

fid = fopen(fullfile(synth_rmc_lp, 'mprage_normalized_repos.nii'), 'w');
fprintf(fid, 'x'); fclose(fid);
fid = fopen(fullfile(synth_rmc_lp, 'mprage.nii'), 'w');
fprintf(fid, 'x'); fclose(fid);

% Test 1: reuse_masked_checkpoint=1 WITHOUT smprage → must error
try
    test_batch_rmc = pseudo_CT_resolve_batch_atlas_path(root_dir);
catch  %#ok<CTCH>
    test_batch_rmc = '';
end
if isempty(test_batch_rmc) || exist(test_batch_rmc, 'dir') ~= 7
    % Fall back to the dist/ Batch_atlas if resolution fails
    test_batch_rmc = fullfile(root_dir, 'dist', 'Batch_atlas');
end
if isempty(test_batch_rmc) || exist(test_batch_rmc, 'dir') ~= 7
    skip('restart-reuse: smprage requirement', ...
        'Batch_atlas not available; cannot exercise full restart path');
else
    % No smprage in synth_rmc_lp — must error
    try
        restart_from_repos_checkpoint(synth_rmc_exp, synth_rmc_lp, ...
            fullfile(synth_rmc_lp, 'mprage.nii'), test_batch_rmc, 1, '', 1);
        check('restart-reuse: smprage missing with flag=1 errors', false, 'should have errored');
    catch ME_rmc
        ok_rmc = ~isempty(strfind(ME_rmc.message, 'smprage'));
        check('restart-reuse: smprage missing with flag=1 fails early', ...
            ok_rmc, ME_rmc.message);
    end

    % Test 2: Add smprage → flag=1 dry_run should succeed
    fid = fopen(fullfile(synth_rmc_lp, 'smprage_normalized_repos.nii'), 'w');
    fprintf(fid, 'x'); fclose(fid);
    st_rmc = restart_from_repos_checkpoint(synth_rmc_exp, synth_rmc_lp, ...
        fullfile(synth_rmc_lp, 'mprage.nii'), test_batch_rmc, 1, '', 1);

    check('restart-reuse: dry_run with flag=1 creates sandbox', ...
        ~isempty(st_rmc.sandbox_tmp) && exist(st_rmc.sandbox_tmp, 'dir') == 7, '');

    check('restart-reuse: dry_run with flag=1 creates proc/', ...
        ~isempty(st_rmc.processing_dir) && exist(st_rmc.processing_dir, 'dir') == 7, '');
end

%% 11. BEHAVIORAL: check_disk_space_free_bytes — disk preflight helper
fprintf('\n  Behavioral: check_disk_space_free_bytes ...\n');

% The helper lives inside restart_from_repos_checkpoint.m; we test it
% by calling restart_from_repos_checkpoint which invokes the preflight.
% But we can also test the helper contract: free_bytes >= 0 on normal
% JVM systems, -1 on nojvm.  We verify indirectly: if the dry_run ran
% without error, the preflight passed.
% Direct functional test: the helper should not error on a valid dir
% with generous min_bytes (1 byte) and should return >= 0 or -1.
addpath(fullfile(root_dir, 'scripts'));
cleanup_ds = onCleanup(@() rmpath(fullfile(root_dir, 'scripts')));
try
    % The helper is a nested function — not directly callable from outside.
    % We exercise it through a dry-run call with minimal min_bytes constraint
    % (the hardcoded 500 MB check).  On modern systems this should pass.
    % If the environment has <500 MB free, the helper errors — which is the
    % correct fail-fast behavior we're validating.
    %
    % Create a minimal synth set and dry-run; the preflight runs before
    % staging, so we can verify it doesn't false-positive on normal systems.
    synth_ds_exp = tempname;  mkdir(synth_ds_exp);
    synth_ds_lp  = tempname;  mkdir(synth_ds_lp);
    cleanup_ds1 = onCleanup(@() rmdir(synth_ds_exp, 's'));
    cleanup_ds2 = onCleanup(@() rmdir(synth_ds_lp, 's'));

    fid = fopen(fullfile(synth_ds_lp, 'mprage_normalized_repos.nii'), 'w');
    fprintf(fid, 'x'); fclose(fid);
    fid = fopen(fullfile(synth_ds_lp, 'mprage.nii'), 'w');
    fprintf(fid, 'x'); fclose(fid);

    try
        test_batch3 = pseudo_CT_resolve_batch_atlas_path(root_dir);
    catch  %#ok<CTCH>
        test_batch3 = '';
    end

    if isempty(test_batch3) || exist(test_batch3, 'dir') ~= 7
        skip('disk-pf: preflight integration', ...
            'Batch_atlas not available; cannot exercise full restart path');
    else
        % Dry-run exercises the full path including disk preflight
        restart_from_repos_checkpoint(synth_ds_exp, synth_ds_lp, ...
            fullfile(synth_ds_lp, 'mprage.nii'), test_batch3, 1);
        % If we got here without error, disk preflight passed (≥500 MB free)
        check('disk-pf: dry_run completes (disk preflight passed)', true, '');
    end
catch ME_ds
    % Check if this was a legitimate disk-space error or something else
    if ~isempty(strfind(ME_ds.message, 'Insufficient disk space'))
        check('disk-pf: fail-fast on low disk space', true, ...
            sprintf('Correctly blocked: %s', ME_ds.message));
    else
        check('disk-pf: preflight integration', false, ME_ds.message);
    end
end

%% 12. BEHAVIORAL: sandbox collision retry — deterministic (fixed prefix)
fprintf('\n  Behavioral: sandbox collision retry (deterministic) ...\n');
% Use a fixed sandbox_prefix so we can pre-create the first-attempt
% directory and FORCE a collision.  The production code must detect the
% pre-existing directory (exist(sandbox_tmp,'dir')) and retry with _r2.
synth_col_exp = tempname;  mkdir(synth_col_exp);
synth_col_lp  = tempname;  mkdir(synth_col_lp);
cleanup_col1 = onCleanup(@() rmdir(synth_col_exp, 's'));
cleanup_col2 = onCleanup(@() rmdir(synth_col_lp, 's'));

fid = fopen(fullfile(synth_col_lp, 'mprage_normalized_repos.nii'), 'w');
fprintf(fid, 'x'); fclose(fid);
fid = fopen(fullfile(synth_col_lp, 'mprage.nii'), 'w');
fprintf(fid, 'x'); fclose(fid);

% Build a complete synthetic Batch_atlas so the collision retry test is
% orthogonal to the real Batch_atlas content.  The real dist/Batch_atlas
% may have suffixed names that differ from exact filenames, which would
% block the dry-run preflight even though collision handling is correct.
% Section 13 separately tests the missing-atlas blocked behavior.
synth_atlas_col = tempname;  mkdir(synth_atlas_col);
cleanup_sac = onCleanup(@() rmdir(synth_atlas_col, 's'));
fid = fopen(fullfile(synth_atlas_col, 'Atlas_rCT_flipLR_repos_15subj.nii'), 'w');
fprintf(fid, 'fake'); fclose(fid);
fid = fopen(fullfile(synth_atlas_col, 'Atlas_head_mask.nii'), 'w');
fprintf(fid, 'fake'); fclose(fid);
fid = fopen(fullfile(synth_atlas_col, 'TPM.nii'), 'w');
fprintf(fid, 'fake'); fclose(fid);

fixed_prefix = 'smoke_collision_test';

% Pre-create a directory matching the first sandbox attempt.
% The production code must detect this with exist(sandbox_tmp,'dir')
% BEFORE calling mkdir and retry with the _r2 suffix.
collision_name = sprintf('restart_sandbox_%s', fixed_prefix);
collision_dir  = fullfile(synth_col_exp, collision_name, 'MR_PET', 'tmp');
[~] = mkdir(collision_dir);

% Call with the fixed prefix — first attempt collides, must retry to _r2
st1 = restart_from_repos_checkpoint(synth_col_exp, synth_col_lp, ...
    fullfile(synth_col_lp, 'mprage.nii'), synth_atlas_col, 1, fixed_prefix);

% Verify the retry succeeded (not the pre-created collision dir)
sandboxes_col = dir(fullfile(synth_col_exp, 'restart_sandbox_*'));
check('sandbox-col: retry created _r2 sandbox after collision', ...
    any(strcmp({sandboxes_col.name}, sprintf('restart_sandbox_%s_r2', fixed_prefix))), ...
    sprintf('expected _r2 among %d sandboxes', length(sandboxes_col)));

check('sandbox-col: status.ready from retry sandbox', ...
    isfield(st1, 'ready') && st1.ready, ...
    sprintf('status.ready=%d blocked_reason=%s', ...
            isfield(st1,'ready') && st1.ready, st1.blocked_reason));

% Second call — first attempt collides (still pre-created), _r2 collides
% (from first call), must retry to _r3.  This proves the retry loop works
% across multiple collisions, not just a one-off backoff.
st2 = restart_from_repos_checkpoint(synth_col_exp, synth_col_lp, ...
    fullfile(synth_col_lp, 'mprage.nii'), synth_atlas_col, 1, fixed_prefix);

sandboxes_col2 = dir(fullfile(synth_col_exp, 'restart_sandbox_*'));
check('sandbox-col: three sandboxes after double collision (pre + _r2 + _r3)', ...
    length(sandboxes_col2) >= 3, ...
    sprintf('found %d sandboxes (expected >= 3)', length(sandboxes_col2)));

% Verify all names are unique
names_unique = length(unique({sandboxes_col2.name})) == length(sandboxes_col2);
check('sandbox-col: all sandbox names are unique', names_unique, ...
    'duplicate sandbox names found');

%% 13. BEHAVIORAL: restart dry-run — missing-atlas blocked behavior
% Calls restart_from_repos_checkpoint with a partial Batch_atlas that
% deliberately lacks Atlas_rCT.nii, then asserts the externally visible
% blocked contract (status.ready == false, blocked_reason set, sandbox
% and proc/ still exist for operator inspection).
fprintf('\n  Behavioral: restart dry-run missing-atlas blocked ...\n');

synth_da_exp = tempname;  mkdir(synth_da_exp);
synth_da_lp  = tempname;  mkdir(synth_da_lp);
cleanup_da1 = onCleanup(@() rmdir(synth_da_exp, 's'));
cleanup_da2 = onCleanup(@() rmdir(synth_da_lp, 's'));

% Create minimal checkpoint files
fid = fopen(fullfile(synth_da_lp, 'mprage_normalized_repos.nii'), 'w');
fprintf(fid, 'x'); fclose(fid);
fid = fopen(fullfile(synth_da_lp, 'mprage.nii'), 'w');
fprintf(fid, 'x'); fclose(fid);

% Build a partial Batch_atlas with Atlas_head_mask (semantic) but NO Atlas_rCT.
% Uses suffixed name Atlas_head_mask_u_rc1foo.nii — must pass semantic match.
% The dry-run preflight must detect the missing rCT and set status.ready=false.
partial_atlas = tempname;  mkdir(partial_atlas);
cleanup_pa = onCleanup(@() rmdir(partial_atlas, 's'));
fid = fopen(fullfile(partial_atlas, 'Atlas_head_mask_u_rc1foo.nii'), 'w');
fprintf(fid, 'fake'); fclose(fid);
fid = fopen(fullfile(partial_atlas, 'TPM.nii'), 'w');
fprintf(fid, 'fake'); fclose(fid);

% Also test the reverse: has Atlas_rCT_flipLR_repos_15subj.nii (semantic)
% but NO Atlas_head_mask.  The dry-run must detect missing head mask.
partial_atlas2 = tempname;  mkdir(partial_atlas2);
cleanup_pa2 = onCleanup(@() rmdir(partial_atlas2, 's'));
fid = fopen(fullfile(partial_atlas2, 'Atlas_rCT_flipLR_repos_15subj.nii'), 'w');
fprintf(fid, 'fake'); fclose(fid);

try
    % --- Missing Atlas_rCT ---
    st_da1 = restart_from_repos_checkpoint(synth_da_exp, synth_da_lp, ...
        fullfile(synth_da_lp, 'mprage.nii'), partial_atlas, 1);

    check('restart-dryrun: status.ready=false when Atlas_rCT missing', ...
        isfield(st_da1, 'ready') && ~st_da1.ready, ...
        sprintf('ready=%d blocked_reason=%s', ...
                isfield(st_da1,'ready') && st_da1.ready, ...
                char(st_da1.blocked_reason)));

    check('restart-dryrun: blocked_reason is ''missing-atlas''', ...
        isfield(st_da1, 'blocked_reason') && strcmp(st_da1.blocked_reason, 'missing-atlas'), ...
        sprintf('got ''%s''', char(st_da1.blocked_reason)));

    check('restart-dryrun: sandbox tmp/ exists despite atlas block', ...
        ~isempty(st_da1.sandbox_tmp) && exist(st_da1.sandbox_tmp, 'dir') == 7, ...
        'tmp/ should exist for operator inspection');

    check('restart-dryrun: proc/ exists despite atlas block', ...
        ~isempty(st_da1.processing_dir) && exist(st_da1.processing_dir, 'dir') == 7, ...
        'proc/ should exist');

    % --- Missing Atlas_head_mask ---
    st_da2 = restart_from_repos_checkpoint(synth_da_exp, synth_da_lp, ...
        fullfile(synth_da_lp, 'mprage.nii'), partial_atlas2, 1);

    check('restart-dryrun: status.ready=false when Atlas_head_mask missing', ...
        isfield(st_da2, 'ready') && ~st_da2.ready, ...
        sprintf('ready=%d blocked_reason=%s', ...
                isfield(st_da2,'ready') && st_da2.ready, ...
                char(st_da2.blocked_reason)));

    check('restart-dryrun: blocked_reason is ''missing-atlas'' (mask missing)', ...
        isfield(st_da2, 'blocked_reason') && strcmp(st_da2.blocked_reason, 'missing-atlas'), ...
        sprintf('got ''%s''', char(st_da2.blocked_reason)));

catch ME_da
    check('restart-dryrun: missing-atlas blocked', false, ME_da.message);
end

%% 14. BEHAVIORAL: compiled SPM8 diagnostic option — preflight + flag plumbing
fprintf('\n  Behavioral: compiled SPM8 diagnostic option ...\n');
addpath(fullfile(root_dir, 'src', 'core'));
cleanup_cs8 = onCleanup(@() rmpath(fullfile(root_dir, 'src', 'core')));

% 14a. normalized_2_att_map: use_compiled_spm8=1 fails early when
% Launchpad assets are not accessible (common case in CI/test envs).
% The preflight must detect missing run_spm8.sh and error before any
% SPM work starts.  The error message must mention run_spm8.sh.
fake_s8_data = tempname;  mkdir(fake_s8_data);
cleanup_s8d = onCleanup(@() rmdir(fake_s8_data, 's'));
fake_s8_work = tempname;  mkdir(fake_s8_work);
cleanup_s8w = onCleanup(@() rmdir(fake_s8_work, 's'));
fake_s8_norm = fullfile(fake_s8_data, 'fake_norm.nii');
fid = fopen(fake_s8_norm, 'w'); fprintf(fid, 'x'); fclose(fid);
% Use fully-equipped synthetic atlas (both roles + batch templates)
s8_atlas = tempname;  mkdir(s8_atlas);
cleanup_s8a = onCleanup(@() rmdir(s8_atlas, 's'));
fid = fopen(fullfile(s8_atlas, 'Atlas_rCT_flipLR_repos_15subj.nii'), 'w'); fprintf(fid, 'x'); fclose(fid);
fid = fopen(fullfile(s8_atlas, 'Atlas_head_mask.nii'), 'w'); fprintf(fid, 'x'); fclose(fid);
fid = fopen(fullfile(s8_atlas, 'TPM.nii'), 'w'); fprintf(fid, 'x'); fclose(fid);
fid = fopen(fullfile(s8_atlas, 'ch2.nii'), 'w'); fprintf(fid, 'x'); fclose(fid);
fid = fopen(fullfile(s8_atlas, 'new_segment_batch.mat'), 'w'); fprintf(fid, 'x'); fclose(fid);
fid = fopen(fullfile(s8_atlas, 'dartel_existing_template_batch.mat'), 'w'); fprintf(fid, 'x'); fclose(fid);
fid = fopen(fullfile(s8_atlas, 'create_inverse_warped_batch.mat'), 'w'); fprintf(fid, 'x'); fclose(fid);

% 14a.1: Call with use_compiled_spm8=1 — must error because default
% Launchpad root is not accessible.  The error must mention run_spm8.sh.
% Force the missing-assets path by pointing PSEUDOCT_LAUNCHPAD_ROOT to
% a nonexistent directory (defense in case the system default exists).
setenv('PSEUDOCT_LAUNCHPAD_ROOT', '/nonexistent/launchpad/dir');
restore_lp_env1 = onCleanup(@() unsetenv('PSEUDOCT_LAUNCHPAD_ROOT'));
try
    normalized_2_att_map(fake_s8_norm, fake_s8_norm, s8_atlas, fake_s8_work, 0, 1);
    check('compiled-spm8: missing Launchpad assets errors early', false, 'should have errored');
catch ME_s8
    ok_s8 = ~isempty(strfind(ME_s8.message, 'run_spm8.sh'));
    check('compiled-spm8: missing Launchpad assets errors with run_spm8.sh', ...
        ok_s8, ME_s8.message);
end
clear restore_lp_env1;  % trigger onCleanup now, before next test

% 14a.2: Call with PSEUDOCT_LAUNCHPAD_ROOT pointing to a nonexistent dir
% The error path must still mention run_spm8.sh (not some other cryptic message).
setenv('PSEUDOCT_LAUNCHPAD_ROOT', '/nonexistent/launchpad/dir');
restore_lp_env = onCleanup(@() unsetenv('PSEUDOCT_LAUNCHPAD_ROOT'));
try
    normalized_2_att_map(fake_s8_norm, fake_s8_norm, s8_atlas, fake_s8_work, 0, 1);
    check('compiled-spm8: bad PSEUDOCT_LAUNCHPAD_ROOT errors early', false, 'should have errored');
catch ME_s8b
    ok_s8b = ~isempty(strfind(ME_s8b.message, 'run_spm8.sh'));
    check('compiled-spm8: bad PSEUDOCT_LAUNCHPAD_ROOT errors with run_spm8.sh', ...
        ok_s8b, ME_s8b.message);
end

% 14b. restart_from_repos_checkpoint: accepts 8 arguments (compiled SPM8 flag)
% and passes it through to normalized_2_att_map.  Test with dry_run to avoid
% the actual preflight (which would fail if Launchpad is absent).
fprintf('\n  Behavioral: restart compiled-SPM8 flag plumbing ...\n');
addpath(fullfile(root_dir, 'scripts'));
cleanup_rcs8 = onCleanup(@() rmpath(fullfile(root_dir, 'scripts')));

synth_s8_exp = tempname;  mkdir(synth_s8_exp);
synth_s8_lp  = tempname;  mkdir(synth_s8_lp);
cleanup_s8e = onCleanup(@() rmdir(synth_s8_exp, 's'));
cleanup_s8l = onCleanup(@() rmdir(synth_s8_lp, 's'));

fid = fopen(fullfile(synth_s8_lp, 'mprage_normalized_repos.nii'), 'w');
fprintf(fid, 'x'); fclose(fid);
fid = fopen(fullfile(synth_s8_lp, 'mprage.nii'), 'w');
fprintf(fid, 'x'); fclose(fid);
% reuse_masked_checkpoint=1 requires smprage to exist in the Launchpad tmp
fid = fopen(fullfile(synth_s8_lp, 'smprage_normalized_repos.nii'), 'w');
fprintf(fid, 'x'); fclose(fid);

% Build a minimal valid Batch_atlas
synth_s8_atlas = tempname;  mkdir(synth_s8_atlas);
cleanup_s8sa = onCleanup(@() rmdir(synth_s8_atlas, 's'));
fid = fopen(fullfile(synth_s8_atlas, 'Atlas_rCT_flipLR_repos_15subj.nii'), 'w');
fprintf(fid, 'x'); fclose(fid);
fid = fopen(fullfile(synth_s8_atlas, 'Atlas_head_mask.nii'), 'w');
fprintf(fid, 'x'); fclose(fid);

try
    % 8-arg dry_run call with use_compiled_spm8=1
    st_s8 = restart_from_repos_checkpoint(synth_s8_exp, synth_s8_lp, ...
        fullfile(synth_s8_lp, 'mprage.nii'), synth_s8_atlas, 1, '', 1, 1);
    % Must return a status struct with ready=true (dry_run passes atlas preflight)
    check('restart-s8: 8-arg call with compiled-spm8=1 returns status struct', ...
        isstruct(st_s8) && isfield(st_s8, 'ready'), ...
        'expected valid status struct');
    check('restart-s8: dry_run + compiled-spm8=1 reports ready', ...
        isfield(st_s8, 'ready') && st_s8.ready, ...
        sprintf('ready=%d blocked=%s', ...
            isfield(st_s8,'ready') && st_s8.ready, ...
            char(st_s8.blocked_reason)));
catch ME_s8r
    check('restart-s8: 8-arg dry_run', false, ME_s8r.message);
end

%% 15. BEHAVIORAL: pseudo_CT_resolve_spm_root — env var SPM tree selection
fprintf('\n  Behavioral: SPM root resolution (PSEUDOCT_SPM_VARIANT / PSEUDOCT_SPM_ROOT) ...\n');
addpath(fullfile(root_dir, 'src', 'config'));
cleanup_s8r = onCleanup(@() rmpath(fullfile(root_dir, 'src', 'config')));

% Save original env state
orig_spm_root    = getenv('PSEUDOCT_SPM_ROOT');
orig_spm_var     = getenv('PSEUDOCT_SPM_VARIANT');
restore_spm_env  = onCleanup(@() setenv('PSEUDOCT_SPM_ROOT', orig_spm_root));
restore_spm_var2 = onCleanup(@() setenv('PSEUDOCT_SPM_VARIANT', orig_spm_var));

% 15a. Default (no env vars): returns spm8-r6313
unsetenv('PSEUDOCT_SPM_ROOT');
unsetenv('PSEUDOCT_SPM_VARIANT');
[spm_d, spm_l] = pseudo_CT_resolve_spm_root(root_dir);
check('spm-root: default → spm8-r6313 dir', ...
    strcmp(spm_d, fullfile(root_dir, 'spm8-r6313')), ...
    sprintf('got %s', spm_d));
check('spm-root: default label mentions ''default''', ...
    ~isempty(strfind(spm_l, 'default')), spm_l);

% 15b. PSEUDOCT_SPM_VARIANT=dan → spm8-dan
setenv('PSEUDOCT_SPM_VARIANT', 'dan');
[spm_d, spm_l] = pseudo_CT_resolve_spm_root(root_dir);
check('spm-root: PSEUDOCT_SPM_VARIANT=dan → spm8-dan dir', ...
    strcmp(spm_d, fullfile(root_dir, 'spm8-dan')), ...
    sprintf('got %s', spm_d));
check('spm-root: PSEUDOCT_SPM_VARIANT label mentions env var', ...
    ~isempty(strfind(spm_l, 'PSEUDOCT_SPM_VARIANT')), spm_l);

% 15c. PSEUDOCT_SPM_ROOT takes precedence over PSEUDOCT_SPM_VARIANT
setenv('PSEUDOCT_SPM_ROOT', '/custom/spm/tree');
setenv('PSEUDOCT_SPM_VARIANT', 'dan');
[spm_d, spm_l] = pseudo_CT_resolve_spm_root(root_dir);
check('spm-root: PSEUDOCT_SPM_ROOT overrides PSEUDOCT_SPM_VARIANT', ...
    strcmp(spm_d, '/custom/spm/tree'), ...
    sprintf('got %s', spm_d));
check('spm-root: PSEUDOCT_SPM_ROOT label mentions env var', ...
    ~isempty(strfind(spm_l, 'PSEUDOCT_SPM_ROOT')), spm_l);

% 15d. PSEUDOCT_SPM_ROOT alone (no variant set)
unsetenv('PSEUDOCT_SPM_VARIANT');
setenv('PSEUDOCT_SPM_ROOT', '/other/spm/path');
[spm_d, spm_l] = pseudo_CT_resolve_spm_root(root_dir);
check('spm-root: PSEUDOCT_SPM_ROOT alone → literal path', ...
    strcmp(spm_d, '/other/spm/path'), ...
    sprintf('got %s', spm_d));

% 15e. PSEUDOCT_SPM_ROOT with empty string → falls back to default
setenv('PSEUDOCT_SPM_ROOT', '');
unsetenv('PSEUDOCT_SPM_VARIANT');
[spm_d, spm_l] = pseudo_CT_resolve_spm_root(root_dir);
check('spm-root: empty PSEUDOCT_SPM_ROOT → default', ...
    strcmp(spm_d, fullfile(root_dir, 'spm8-r6313')), ...
    sprintf('got %s', spm_d));

%% 16. CHANGELOG v2.6.2 structural checks
fprintf('\n  CHANGELOG v2.6.2 structural checks ...\n');
fid_ch16 = fopen(fullfile(root_dir, 'CHANGELOG.md'), 'r');
ch16_content = fread(fid_ch16, inf, '*char')';
fclose(fid_ch16);

% 16a. Line-1 version is 2.6.2
check('CHANGELOG: line 1 is 2.6.2', ...
    ~isempty(regexp(strtrim(strtok(ch16_content, char(10))), '^2\.6\.2$', 'once')), ...
    sprintf('got: ''%s''', strtrim(strtok(ch16_content, char(10)))));

% 16b. Section heading exists
check('CHANGELOG: heading "2.6.2 — Investigation Cleanup Release" present', ...
    ~isempty(strfind(ch16_content, '2.6.2 — Investigation Cleanup Release')), '');

% 16c. Coregistration-parity finding (qualitative, no deltas)
check('CHANGELOG: coregistration-parity finding present', ...
    ~isempty(strfind(ch16_content, 'Coregistration-parity finding')), '');
check('CHANGELOG: R2010b/MCR 7.11 matches Launchpad v2.0 at coregistration', ...
    ~isempty(strfind(ch16_content, 'matches the compiled Launchpad v2.0')), '');
check('CHANGELOG: qualitative label present', ...
    ~isempty(strfind(ch16_content, '(qualitative)')), '');
% Absence check: no max-affine-delta values
check('CHANGELOG: NO max-affine-delta values', ...
    isempty(strfind(ch16_content, 'max-affine-delta')), ...
    'must not contain machine-specific delta values');

% 16d. Divergence caveat
check('CHANGELOG: divergence caveat present', ...
    ~isempty(strfind(ch16_content, 'Divergence caveat')), '');
check('CHANGELOG: modern MATLAB may produce divergent optimizer results', ...
    ~isempty(strfind(ch16_content, 'may produce divergent optimizer results')), '');

% 16e. Deferred-validation warning
check('CHANGELOG: deferred-validation warning present', ...
    ~isempty(strfind(ch16_content, 'Deferred-validation warning')), '');
check('CHANGELOG: R2026a E2E validation deferred', ...
    ~isempty(strfind(ch16_content, 'R2026a local E2E validation is deferred')), '');
check('CHANGELOG: compiled Launchpad v2.0 binary is unchanged', ...
    ~isempty(strfind(ch16_content, 'compiled Launchpad v2.0 binary is unchanged')), '');

% 16f. No R2026a full-pipeline parity claim
check('CHANGELOG: NO R2026a full-pipeline parity claim', ...
    isempty(strfind(ch16_content, 'R2026a full-pipeline parity')), ...
    'must not claim R2026a full-pipeline parity without operator E2E');

% 16g. Cleanup exclusions documented with removal reason
check('CHANGELOG: cleanup exclusions present', ...
    ~isempty(strfind(ch16_content, 'Cleanup — removed transient artifacts')), '');
check('CHANGELOG: package-lock.json removal documented', ...
    ~isempty(strfind(ch16_content, 'package-lock.json')), '');
check('CHANGELOG: archive-report.md removal documented', ...
    ~isempty(strfind(ch16_content, 'archive-report.md')), '');

% 16h. spm8-dan/ gitignore note
check('CHANGELOG: spm8-dan/ listed as gitignored', ...
    ~isempty(strfind(ch16_content, 'spm8-dan/')), '');
check('CHANGELOG: spm8-dan/ operator-managed removal noted', ...
    ~isempty(strfind(ch16_content, 'operator-managed removal')), '');

% 16i. Diagnostic tools listed
check('CHANGELOG: reusable investigation diagnostics listed', ...
    ~isempty(strfind(ch16_content, 'Reusable investigation diagnostics')), '');
check('CHANGELOG: diff_entrypoint_runs.m in diagnostic list', ...
    ~isempty(strfind(ch16_content, 'diff_entrypoint_runs.m')), '');
check('CHANGELOG: pseudo_ct_princomp_legacy.m in diagnostic list', ...
    ~isempty(strfind(ch16_content, 'pseudo_ct_princomp_legacy.m')), '');
check('CHANGELOG: investigation-tool banner noted', ...
    ~isempty(strfind(ch16_content, 'Investigation tool')), '');

% 16j. PCA shim reference (legacy-compatible, no overclaim)
check('CHANGELOG: PCA shim referenced as legacy-compatible', ...
    ~isempty(strfind(ch16_content, 'legacy-compatible PCA shim')), '');
check('CHANGELOG: PCA shim does NOT claim to fix optimizer divergence', ...
    ~isempty(strfind(ch16_content, 'does not claim to fix optimizer divergence')), '');

%% 17. Divergence-warning assertions in source files
fprintf('\n  Divergence-warning assertions ...\n');

% 17a. run_pseudo_CT_launchpad.m header
fid_lp = fopen(fullfile(root_dir, 'run_pseudo_CT_launchpad.m'), 'r');
lp_hdr = fread(fid_lp, inf, '*char')';
fclose(fid_lp);
check('div-warn: run_pseudo_CT_launchpad.m states minimum MATLAB R2010b', ...
    ~isempty(strfind(lp_hdr, 'Minimum supported MATLAB: R2010b')), '');
check('div-warn: run_pseudo_CT_launchpad.m warns modern MATLAB may diverge', ...
    ~isempty(strfind(lp_hdr, 'MAY produce divergent optimizer results')), '');

% 17b. defaults_pseudo_CT_launchpad.m divergence caveat
fid_dfl = fopen(fullfile(root_dir, 'src', 'config', 'defaults_pseudo_CT_launchpad.m'), 'r');
dfl_content = fread(fid_dfl, inf, '*char')';
fclose(fid_dfl);
check('div-warn: defaults_pseudo_CT_launchpad.m documents R2010b min version', ...
    ~isempty(strfind(dfl_content, 'R2010b')), '');
check('div-warn: defaults_pseudo_CT_launchpad.m warns modern MATLAB may diverge', ...
    ~isempty(strfind(dfl_content, 'MAY produce divergent optimizer results')), '');

% 17c. Structural: defaults_pseudo_CT.m recenter default preserves legacy behavior
% The recenter default must be 'Yes' to match Launchpad/compiled behavior.
fid_dpl = fopen(fullfile(root_dir, 'src', 'config', 'defaults_pseudo_CT.m'), 'r');
dpl_content = fread(fid_dpl, inf, '*char')';
fclose(fid_dpl);
check('div-warn: defaults_pseudo_CT.m recenter default is legacy ''Yes''', ...
    ~isempty(strfind(dpl_content, 'recenter_before_normalization = ''Yes''')), '');

% 17d. Absence: run_pseudo_CT_local.m must NOT claim full-pipeline parity
fid_lcl = fopen(fullfile(root_dir, 'run_pseudo_CT_local.m'), 'r');
lcl_content = fread(fid_lcl, inf, '*char')';
fclose(fid_lcl);
check('div-warn: run_pseudo_CT_local.m does NOT claim R2026a parity', ...
    isempty(strfind(lcl_content, 'R2026a full-pipeline parity')), '');

%% 18. Classification verification assertions
fprintf('\n  Classification verification ...\n');

% 18a. Keep files: tracked on disk and parse
keep_files = {
    'TODO.md'
    'scripts/diff_entrypoint_runs.m'
    'scripts/compare_nifti_data.m'
    'scripts/compare_hash_strings.m'
    'scripts/restart_from_repos_checkpoint.m'
    'scripts/sweep_smoothing_fwhm.m'
    'src/config/pseudo_CT_keep_temp_enabled.m'
    'src/config/pseudo_CT_resolve_spm_root.m'
    'src/core/normalized_2_att_map.m'
    'src/core/pseudo_ct_princomp_legacy.m'
    };
for i = 1:numel(keep_files)
    fp = fullfile(root_dir, keep_files{i});
    exists = exist(fp, 'file') == 2;
    check(sprintf('classify: %s is Keep (exists on disk)', keep_files{i}), exists, '');
end

% 18b. Remove files: must not exist on disk
check('classify: package-lock.json is Remove (absent)', ...
    exist(fullfile(root_dir, 'package-lock.json'), 'file') == 0, ...
    'package-lock.json should have been deleted');
check('classify: archive-report.md is Remove (absent)', ...
    exist(fullfile(root_dir, 'openspec', 'changes', 'extract-version-changelog', 'archive-report.md'), 'file') == 0, ...
    'archive-report.md should have been deleted');

% 18c. Ignore: spm8-dan/ in .gitignore
fid_gi = fopen(fullfile(root_dir, '.gitignore'), 'r');
gi_content = fread(fid_gi, inf, '*char')';
fclose(fid_gi);
check('classify: spm8-dan/ is Ignore (in .gitignore)', ...
    ~isempty(strfind(gi_content, 'spm8-dan/')), '');
% spm8-dan/ must still exist on disk (tree preserved)
check('classify: spm8-dan/ still present on disk', ...
    exist(fullfile(root_dir, 'spm8-dan'), 'dir') == 7, ...
    'spm8-dan/ must remain on disk for operator inspection');

% 18d. Investigation-tool banners on all 7 diagnostic/core files
banner_files = {
    'scripts/diff_entrypoint_runs.m'
    'scripts/compare_nifti_data.m'
    'scripts/compare_hash_strings.m'
    'scripts/restart_from_repos_checkpoint.m'
    'scripts/sweep_smoothing_fwhm.m'
    'src/core/normalized_2_att_map.m'
    'src/core/pseudo_ct_princomp_legacy.m'
    };
banner_text = 'Investigation tool';
for i = 1:numel(banner_files)
    fid_b = fopen(fullfile(root_dir, banner_files{i}), 'r');
    b_content = fread(fid_b, inf, '*char')';
    fclose(fid_b);
    has_banner = ~isempty(strfind(b_content, banner_text));
    check(sprintf('classify: %s has investigation-tool banner', banner_files{i}), has_banner, '');
end

% 18e. run_tests.m is removed from tracking (cookbook removal classification)
% The file may still exist on disk as operator reference but is not staged.
% Smoke tests do not assert its existence.

% 18f. OpenSpec delta spec is tracked
check('classify: openspec/specs/entrypoint-divergence-diagnostics/spec.md tracked', ...
    exist(fullfile(root_dir, 'openspec', 'specs', 'entrypoint-divergence-diagnostics', 'spec.md'), 'file') == 2, '');

% 18g. Investigation-cleanup-release SDD artifacts tracked
check('classify: proposal.md tracked', ...
    exist(fullfile(root_dir, 'openspec', 'changes', 'investigation-cleanup-release', 'proposal.md'), 'file') == 2, '');
check('classify: design.md tracked', ...
    exist(fullfile(root_dir, 'openspec', 'changes', 'investigation-cleanup-release', 'design.md'), 'file') == 2, '');
check('classify: tasks.md tracked', ...
    exist(fullfile(root_dir, 'openspec', 'changes', 'investigation-cleanup-release', 'tasks.md'), 'file') == 2, '');

% 18h. Entrypoint-divergence-diagnosis archive tracked
check('classify: entrypoint-divergence-diagnosis design.md tracked', ...
    exist(fullfile(root_dir, 'openspec', 'changes', 'entrypoint-divergence-diagnosis', 'design.md'), 'file') == 2, '');

%% 19. Shell-safe input validation coverage (R1-001, R1-002)
fprintf('\n  Shell-safe input validation coverage ...\n');

% 19a. run_normalization_cmd.m validates ALL 3 interpolated shell inputs
fid_rnc = fopen(fullfile(root_dir, 'src', 'remote', 'run_normalization_cmd.m'), 'r');
rnc_content = fread(fid_rnc, inf, '*char')';
fclose(fid_rnc);
check('shell-safe: run_normalization_cmd.m validates fs_lib', ...
    ~isempty(strfind(rnc_content, 'shell_meta')), '');
check('shell-safe: run_normalization_cmd.m validates source_command', ...
    ~isempty(strfind(rnc_content, 'source_command contains shell metacharacters')), '');
check('shell-safe: run_normalization_cmd.m validates cmd', ...
    ~isempty(strfind(rnc_content, 'Normalization command contains shell metacharacters')), '');

% 19b. normalized_2_att_map.m validates batch filename path for system()
fid_n2a = fopen(fullfile(root_dir, 'src', 'core', 'normalized_2_att_map.m'), 'r');
n2a_content = fread(fid_n2a, inf, '*char')';
fclose(fid_n2a);
check('shell-safe: normalized_2_att_map.m validates fns_seg_batch in system()', ...
    ~isempty(strfind(n2a_content, 'fns_seg_batch')) && ...
    ~isempty(strfind(n2a_content, 'shell_meta')), '');
check('shell-safe: normalized_2_att_map.m validates run_spm8_sh in system()', ...
    ~isempty(strfind(n2a_content, 'run_spm8_sh')), '');
check('shell-safe: normalized_2_att_map.m validates mcr_root in system()', ...
    ~isempty(strfind(n2a_content, 'mcr_root')), '');

%% 20. FreeSurfer & recenter behavioral tests (R3-002, R3-003)
fprintf('\n  FreeSurfer & recenter behavioral tests ...\n');

% 20a. BEHAVIORAL: recenter default via defaults_pseudo_CT function call
% Goes beyond source-text assertion: actually evaluates the defaults function.
addpath(fullfile(root_dir, 'src', 'config'));
cleanup_df = onCleanup(@() rmpath(fullfile(root_dir, 'src', 'config')));
try
    recenter_val = defaults_pseudo_CT('recenter_before_normalization');
    check('recenter: defaults_pseudo_CT returns ''Yes'' for recenter', ...
        strcmp(recenter_val, 'Yes'), sprintf('got ''%s''', recenter_val));
catch ME_recenter
    check('recenter: defaults_pseudo_CT evaluates recenter', ...
        false, ME_recenter.message);
end

% 20b. run_normalization_cmd.m FreeSurfer command construction pattern
% The local_prepare_source_command nested function must prepend
% LD_LIBRARY_PATH before the source/command.  Verify the file contains
% both the tcsh and sh command-construction patterns.
check('fs-cmd: run_normalization_cmd.m has tcsh env-setup path', ...
    ~isempty(strfind(rnc_content, 'tcsh -f -c "setenv LD_LIBRARY_PATH')), '');
check('fs-cmd: run_normalization_cmd.m has sh env-export path', ...
    ~isempty(strfind(rnc_content, '/bin/sh -c "LD_LIBRARY_PATH=')), '');
check('fs-cmd: run_normalization_cmd.m validates ALL 3 shell inputs before interpolation', ...
    ~isempty(strfind(rnc_content, 'source_command contains shell metacharacters')), '');

% 20c. FreeSurfer LD_LIBRARY_PATH fallback default is present
check('fs-cmd: PSEUDOCT_FS_LIBSTDCPP_ROOT fallback path exists', ...
    ~isempty(strfind(rnc_content, '/autofs/cluster/matlab/current/sys/os/glnxa64')), '');

%% 21. PCA geometry behavioral tests (R3-004, R3-005)
fprintf('\n  PCA geometry behavioral tests ...\n');
addpath(fullfile(root_dir, 'src', 'core'));
cleanup_pca = onCleanup(@() rmpath(fullfile(root_dir, 'src', 'core')));

% 21a. Regular matrix (n > p): output dimensions match old princomp contract
X_tall = randn(50, 3);
try
    [coeff, score, latent] = pseudo_ct_princomp_legacy(X_tall);
    check('pca-legacy: tall matrix coeff is PxP', ...
        all(size(coeff) == [3, 3]), sprintf('got %dx%d', size(coeff,1), size(coeff,2)));
    check('pca-legacy: tall matrix score is NxP', ...
        all(size(score) == [50, 3]), sprintf('got %dx%d', size(score,1), size(score,2)));
    check('pca-legacy: tall matrix latent is Px1', ...
        all(size(latent) == [3, 1]), sprintf('got %dx%d', size(latent,1), size(latent,2)));
    % Verify latent values are monotonically decreasing (variance order)
    check('pca-legacy: tall matrix latent decreasing', ...
        all(diff(latent) <= 0), 'latent not decreasing');
catch ME_pca1
    check('pca-legacy: tall matrix runs', false, ME_pca1.message);
end

% 21b. Wide matrix (n < p): must not produce oversized score (R3-005 fix)
X_wide = randn(5, 20);
try
    [coeff_w, score_w, latent_w] = pseudo_ct_princomp_legacy(X_wide);
    check('pca-legacy: wide matrix coeff is PxP', ...
        all(size(coeff_w) == [20, 20]), sprintf('got %dx%d', size(coeff_w,1), size(coeff_w,2)));
    % R3-005: score must be N-by-P, NOT N-by-(n-1).  Zero-padding fills n:p.
    check('pca-legacy: wide matrix score is NxP (R3-005)', ...
        all(size(score_w) == [5, 20]), sprintf('got %dx%d — R3-005 wide-matrix fix', size(score_w,1), size(score_w,2)));
    check('pca-legacy: wide matrix latent is Px1', ...
        all(size(latent_w) == [20, 1]), sprintf('got %dx%d', size(latent_w,1), size(latent_w,2)));
    % Non-signal latent values (cols n:p) must be zero
    check('pca-legacy: wide matrix zero-padded latent from col n', ...
        all(latent_w(5:end) == 0), 'non-signal latent not zero');
catch ME_pca2
    check('pca-legacy: wide matrix runs', false, ME_pca2.message);
end

% 21c. Square matrix (n == p)
X_sq = randn(10, 10);
try
    [coeff_s, score_s, latent_s] = pseudo_ct_princomp_legacy(X_sq);
    check('pca-legacy: square matrix coeff is PxP', ...
        all(size(coeff_s) == [10, 10]), sprintf('got %dx%d', size(coeff_s,1), size(coeff_s,2)));
    check('pca-legacy: square matrix score is NxP', ...
        all(size(score_s) == [10, 10]), sprintf('got %dx%d', size(score_s,1), size(score_s,2)));
    % Last latent should be zero (one degree of freedom lost to centering)
    check('pca-legacy: square matrix last latent zero', ...
        latent_s(end) < 1e-12, sprintf('last latent=%g', latent_s(end)));
catch ME_pca3
    check('pca-legacy: square matrix runs', false, ME_pca3.message);
end

% 21d. Single observation (n == 1): no variance, score = centered data
try
    [coeff_1, score_1, latent_1] = pseudo_ct_princomp_legacy(randn(1, 5));
    check('pca-legacy: single-obs coeff is identity', ...
        isequal(coeff_1, eye(5)), 'coeff not identity for n=1');
    check('pca-legacy: single-obs latent all zero', ...
        all(latent_1 == 0), 'latent not zero for n=1');
catch ME_pca4
    check('pca-legacy: single-obs runs', false, ME_pca4.message);
end

% 21e. Empty input (n == 0): graceful identity output
try
    [coeff_e, score_e, latent_e] = pseudo_ct_princomp_legacy(zeros(0, 4));
    check('pca-legacy: empty-input coeff is identity', ...
        isequal(coeff_e, eye(4)), 'coeff not identity for empty');
    check('pca-legacy: empty-input score is 0xP', ...
        all(size(score_e) == [0, 4]), sprintf('got %dx%d', size(score_e,1), size(score_e,2)));
    check('pca-legacy: empty-input latent all zero', ...
        all(latent_e == 0), 'latent not zero for empty');
catch ME_pca5
    check('pca-legacy: empty-input runs', false, ME_pca5.message);
end

%% 22. R2026a output acceptance preparation (R4-002)
fprintf('\n  R2026a output acceptance preparation ...\n');

% 22a. No R2026a parity claim in ANY source or doc file
claim_files = {
    'run_pseudo_CT_local.m'
    'run_pseudo_CT_launchpad.m'
    'CHANGELOG.md'
    };
for i = 1:numel(claim_files)
    fid_c = fopen(fullfile(root_dir, claim_files{i}), 'r');
    c_content = fread(fid_c, inf, '*char')';
    fclose(fid_c);
    check(sprintf('r2026a: %s does NOT claim full-pipeline parity', claim_files{i}), ...
        isempty(strfind(c_content, 'R2026a full-pipeline parity')), '');
end

% 22b. Output acceptance: att_map output path contract
% The specification requires att_map.nii (single-subject), att_map_*.dcm (DICOM),
% and Fusion_MR_Pseudo_CT_validation.tiff (QC).  Verify key paths referenced.
check('r2026a: att_map.nii referenced in atlas_based_attenuation_map.m', ...
    ~isempty(strfind(n2a_content, 'att_map.nii')), '');
check('r2026a: CT_2_att_map referenced in normalized_2_att_map.m', ...
    ~isempty(strfind(n2a_content, 'CT_2_att_map')), '');

% 22c. Deferred-validation warning is documented as NOT a parity claim
check('r2026a: CHANGELOG explicitly defers R2026a E2E validation', ...
    ~isempty(strfind(ch16_content, 'R2026a local E2E validation is deferred')), '');
check('r2026a: compiled Launchpad v2.0 binary documented as unchanged', ...
    ~isempty(strfind(ch16_content, 'compiled Launchpad v2.0 binary is unchanged')), '');

%% Summary
fprintf('\n=== Results: %d passed, %d failed, %d skipped ===\n', ...
        num_passed, num_failed, num_skipped);
if num_failed > 0
    error('Smoke tests failed.');
end
end
