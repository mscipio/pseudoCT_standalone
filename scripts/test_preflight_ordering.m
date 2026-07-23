function test_preflight_ordering()
%TEST_PREFLIGHT_ORDERING RED-first checks that preflight validates seams.
%   Verifies that pseudo_CT_preflight rejects invalid PCA, normalization,
%   cleanup, and bone configurations before any filesystem, DICOM, network,
%   or output mutation. Uses a fake repo root so no real SPM/FreeSurfer
%   assets are required.
%
%   Minimum supported MATLAB: R2010b.

scripts_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(scripts_dir);
addpath(fullfile(root_dir, 'src', 'config'));
addpath(fullfile(root_dir, 'src', 'core'));

test_passed = 0;
test_failed = 0;
ids = pseudo_CT_error_ids();

%% Build a minimal fake repo.
[fake_root, cleanup_temp] = make_fake_repo_root();
valid_manifest = make_valid_manifest(fake_root);

%% 1) Invalid PCA order blocks before mutation.
bad_manifest = valid_manifest;
bad_manifest.pca_order = {'unknown_backend'};
run_error_test('preflight invalid PCA', ids.PCA.BackendUnavailable, ...
    @() pseudo_CT_preflight(bad_manifest, fake_root));

%% 2) Normalization shell metachar blocks before mutation.
bad_manifest = valid_manifest;
bad_manifest.normalization_resource.source_command = 'source /path; rm -rf /';
run_error_test('preflight normalization metachar', ids.NORMALIZATION.ShellMetachar, ...
    @() pseudo_CT_preflight(bad_manifest, fake_root));

%% 3) Invalid cleanup policy blocks before mutation.
bad_manifest = valid_manifest;
bad_manifest.cleanup_policy = 'sometimes';
run_error_test('preflight invalid cleanup policy', ids.PROFILE.InvalidValue, ...
    @() pseudo_CT_preflight(bad_manifest, fake_root));

%% 4) Disabled bone reduction blocks before mutation.
bad_manifest = valid_manifest;
bad_manifest.bone_enabled = false;
run_error_test('preflight disabled bone', ids.BONE.CleanupFixed, ...
    @() pseudo_CT_preflight(bad_manifest, fake_root));

%% 5) Valid local-current preflight passes (PCA/norm/cleanup/bone).
try
    pseudo_CT_preflight(valid_manifest, fake_root);
    test_passed = test_passed + 1;
    fprintf('  PASS  valid local-current preflight passes\n');
catch ME
    test_failed = test_failed + 1;
    fprintf('  FAIL  valid local-current preflight: %s\n', ME.message);
end

%% 6) Registry-built local-current passes preflight with fake root.
registry_manifest = pseudo_CT_profile_registry('local-current', fake_root);
registry_manifest.provenance.record_path = ''; % disable record check for fake root
try
    pseudo_CT_preflight(registry_manifest, fake_root);
    test_passed = test_passed + 1;
    fprintf('  PASS  registry local-current preflight passes\n');
catch ME
    test_failed = test_failed + 1;
    fprintf('  FAIL  registry local-current preflight: %s\n', ME.message);
end

%% Cleanup.
if ~isempty(cleanup_temp)
    rmdir(cleanup_temp, 's');
end

%% Report.
total = test_passed + test_failed;
fprintf('\n=== Preflight Ordering Tests: %d/%d passed ===\n', test_passed, total);
if test_failed > 0
    error('test_preflight_ordering:Failures', '%d test(s) failed.', test_failed);
end

%% ------------------------------------------------------------------------
function run_error_test(label, expected_id, thunk)
    caught = false;
    actual_id = '';
    try
        thunk();
    catch ME
        caught = true;
        actual_id = ME.identifier;
    end
    if caught && strcmp(actual_id, expected_id)
        test_passed = test_passed + 1;
        fprintf('  PASS  %s -> %s\n', label, expected_id);
    elseif caught
        test_failed = test_failed + 1;
        fprintf('  FAIL  %s: expected %s, got %s\n', label, expected_id, actual_id);
    else
        test_failed = test_failed + 1;
        fprintf('  FAIL  %s: expected %s, no error thrown\n', label, expected_id);
    end
end

%% ------------------------------------------------------------------------
function [fake_root, cleanup_dir] = make_fake_repo_root()
    fake_root = fullfile(tempdir, 'pseudo_ct_pr2_preflight_test_repo');
    if exist(fake_root, 'dir') == 7
        rmdir(fake_root, 's');
    end
    mkdir(fake_root);
    cleanup_dir = fake_root;

    % SPM r6313 tree (empty directory is enough for existence check).
    mkdir_maybe(fullfile(fake_root, 'spm8-r6313'));
    copyfile(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'spm8-r6313', 'Contents.m'), fullfile(fake_root, 'spm8-r6313'));

    % vers/ overrides in spec order.
    vers_dir = fullfile(fake_root, 'vers');
    mkdir_maybe(vers_dir);
    touch(fullfile(vers_dir, 'spm_vol_nifti.m'));
    touch(fullfile(vers_dir, 'spm_preproc_write8.m'));
    touch(fullfile(vers_dir, 'spm_dicom_convert.m'));

    % Atlas assets.
    atlas_dir = fullfile(fake_root, 'Batch_atlas');
    mkdir_maybe(atlas_dir);
    touch(fullfile(atlas_dir, 'TPM.nii'));
    touch(fullfile(atlas_dir, 'ch2.nii'));
    for ii = 0:6
        touch(fullfile(atlas_dir, sprintf('Template_%d.nii', ii)));
    end
    jar_dir = fullfile(atlas_dir, 'ganymed-ssh2-build250');
    mkdir_maybe(jar_dir);
    touch(fullfile(jar_dir, 'ganymed-ssh2-build250.jar'));

    % FreeSurfer env script referenced by the manifest source_command.
    cfg_dir = fullfile(fake_root, 'src', 'config');
    mkdir_maybe(cfg_dir);
    profile_dir = fullfile(cfg_dir, 'spm_profiles');
    mkdir_maybe(profile_dir);
    write_profile_config(profile_dir, 'local_current', ...
        '../../../spm8-r6313', 'r6313');
    touch(fullfile(cfg_dir, 'fs_setenv_530_from_launchpad.sh'));
end

%% ------------------------------------------------------------------------
function write_profile_config(config_dir, function_name, root_name, revision)
    fid = fopen(fullfile(config_dir, [function_name '.m']), 'w');
    fprintf(fid, 'function c = %s()\n', function_name);
    fprintf(fid, 'c.spm_root = ''%s'';\n', root_name);
    fprintf(fid, 'c.expected_revision = ''%s'';\n', revision);
    fprintf(fid, 'end\n');
    fclose(fid);
    rehash;
end

%% ------------------------------------------------------------------------
function manifest = make_valid_manifest(fake_root)
    manifest = struct();
    manifest.name = 'local-current';
    manifest.spm_root = fullfile(fake_root, 'spm8-r6313');
    manifest.spm_version = 'r6313';
    manifest.vers_path = fullfile(fake_root, 'vers');
    manifest.vers_policy = struct('order', {{'spm_vol_nifti.m'; 'spm_preproc_write8.m'; 'spm_dicom_convert.m'}}, 'required', true);
    manifest.atlas_assets = struct();
    manifest.atlas_assets.batch_atlas_path = fullfile(fake_root, 'Batch_atlas');
    manifest.atlas_assets.required_files = { ...
        'TPM.nii'; 'ch2.nii'; ...
        'Template_0.nii'; 'Template_1.nii'; 'Template_2.nii'; ...
        'Template_3.nii'; 'Template_4.nii'; 'Template_5.nii'; 'Template_6.nii'; ...
        fullfile('ganymed-ssh2-build250', 'ganymed-ssh2-build250.jar') ...
        };
    manifest.pca_order = {'callable_pca'; 'repo_legacy'};
    manifest.runtime_guard = 'supported_matlab';
    manifest.normalization_resource = struct();
    manifest.normalization_resource.source_command = sprintf('source %s', fullfile(fake_root, 'src', 'config', 'fs_setenv_530_from_launchpad.sh'));
    manifest.normalization_resource.child_lib_path = '/autofs/cluster/matlab/current/sys/os/glnxa64';
    manifest.recenter = 'No';
    manifest.zero_background = 'Yes';
    manifest.bone_enabled = true;
    manifest.fwhm = 0;
    manifest.aliasing_default = 1;
    manifest.aliasing_override = [0 1];
    manifest.cleanup_policy = 'remove_on_success';
    manifest.launchpad_identity = struct();
    manifest.provenance = struct();
    manifest.provenance.source = '';
    manifest.provenance.license = '';
    manifest.provenance.tree_inventory = '';
    manifest.provenance.file_count = 0;
    manifest.provenance.bytes = 0;
    manifest.provenance.expected_spm_version = 'r6313';
    manifest.provenance.sha256_map = struct();
    manifest.provenance.record_path = '';
end

%% ------------------------------------------------------------------------
function mkdir_maybe(p)
    if exist(p, 'dir') ~= 7
        mkdir(p);
    end
end

%% ------------------------------------------------------------------------
function touch(p)
    fid = fopen(p, 'w');
    if fid ~= -1
        fclose(fid);
    end
end

end
