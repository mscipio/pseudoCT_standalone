function test_deterministic_error_ids()
%TEST_DETERMINISTIC_ERROR_IDS RED-first checks for PR1 foundation error IDs.
%   Verifies that pseudo_CT_resolve_profile, pseudo_CT_profile_registry,
%   pseudo_CT_preflight, and pseudo_CT_provenance_record raise the
%   deterministic error identifiers defined in pseudo_CT_error_ids.
%   No SPM batch, DICOM conversion, SSH/PBS, or subject mutation is run.
%
%   Minimum supported MATLAB: R2010b.

scripts_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(scripts_dir);
addpath(fullfile(root_dir, 'src', 'config'));

cleanup_temp = [];

test_passed = 0;
test_failed = 0;

ids = pseudo_CT_error_ids();

%% 1) Error ID struct exists and has expected values.
run_test('PROFILE:InvalidName', ...
    strcmp(ids.PROFILE.InvalidName, 'PROFILE:InvalidName'));
run_test('PROFILE:MissingManifestField', ...
    strcmp(ids.PROFILE.MissingManifestField, 'PROFILE:MissingManifestField'));
run_test('PROFILE:InvalidValue', ...
    strcmp(ids.PROFILE.InvalidValue, 'PROFILE:InvalidValue'));
run_test('PROFILE:R2010bOnly', ...
    strcmp(ids.PROFILE.R2010bOnly, 'PROFILE:R2010bOnly'));
run_test('SPM_ROOT:NotFound', ...
    strcmp(ids.SPM_ROOT.NotFound, 'SPM_ROOT:NotFound'));
run_test('VERS:Incomplete', ...
    strcmp(ids.VERS.Incomplete, 'VERS:Incomplete'));
run_test('VERS:WrongOrder', ...
    strcmp(ids.VERS.WrongOrder, 'VERS:WrongOrder'));
run_test('ATLAS:AssetMissing', ...
    strcmp(ids.ATLAS.AssetMissing, 'ATLAS:AssetMissing'));
run_test('PCA:BackendUnavailable', ...
    strcmp(ids.PCA.BackendUnavailable, 'PCA:BackendUnavailable'));
run_test('NORMALIZATION:SourceCommandMissing', ...
    strcmp(ids.NORMALIZATION.SourceCommandMissing, 'NORMALIZATION:SourceCommandMissing'));
run_test('NORMALIZATION:ShellMetachar', ...
    strcmp(ids.NORMALIZATION.ShellMetachar, 'NORMALIZATION:ShellMetachar'));
run_test('PROVENANCE:RecordMissing', ...
    strcmp(ids.PROVENANCE.RecordMissing, 'PROVENANCE:RecordMissing'));
run_test('PROVENANCE:InventoryMissing', ...
    strcmp(ids.PROVENANCE.InventoryMissing, 'PROVENANCE:InventoryMissing'));
run_test('RELEASE:ValidationIncomplete', ...
    strcmp(ids.RELEASE.ValidationIncomplete, 'RELEASE:ValidationIncomplete'));
run_test('ALIAS:InvalidOverride', ...
    strcmp(ids.ALIAS.InvalidOverride, 'ALIAS:InvalidOverride'));
run_test('BONE:CleanupFixed', ...
    strcmp(ids.BONE.CleanupFixed, 'BONE:CleanupFixed'));
run_test('ENV_IGNORED:PSEUDOCT_KEEP_TMP', ...
    strcmp(ids.ENV_IGNORED.KEEP_TMP, 'ENV_IGNORED:PSEUDOCT_KEEP_TMP'));

%% 2) Resolve unknown profile -> PROFILE:InvalidName.
run_error_test('resolve_profile unknown name', ids.PROFILE.InvalidName, @() pseudo_CT_resolve_profile('does-not-exist', root_dir));

%% 3) Registry unknown profile -> PROFILE:InvalidName.
run_error_test('registry unknown name', ids.PROFILE.InvalidName, @() pseudo_CT_profile_registry('does-not-exist', root_dir));

%% 4) Build a minimal fake repo for resource tests.
[fake_root, cleanup_temp] = make_fake_repo_root();
valid_manifest = make_valid_manifest(fake_root);

%% 5) Missing manifest field -> PROFILE:MissingManifestField.
bad_manifest = valid_manifest;
bad_manifest = rmfield(bad_manifest, 'name');
run_error_test('preflight missing name field', ids.PROFILE.MissingManifestField, ...
    @() pseudo_CT_preflight(bad_manifest, fake_root));

%% 6) Invalid manifest value -> PROFILE:InvalidValue.
bad_manifest = valid_manifest;
bad_manifest.recenter = 'Maybe';
run_error_test('preflight invalid recenter', ids.PROFILE.InvalidValue, ...
    @() pseudo_CT_preflight(bad_manifest, fake_root));

%% 7) Near-parity on non-R2010b runtime -> PROFILE:R2010bOnly.
near_manifest = pseudo_CT_profile_registry('local-near-parity-r2010b', fake_root);
run_error_test('near-parity runtime guard', ids.PROFILE.R2010bOnly, ...
    @() pseudo_CT_preflight(near_manifest, fake_root));

%% 8) r4667 SPM root missing -> SPM_ROOT:NotFound.
% The fake repo intentionally lacks spm8-r4667, so the near-parity manifest
% already points at a missing tree. The runtime guard is checked before SPM
% root, so temporarily disable it to isolate the SPM_ROOT error.
near_manifest = pseudo_CT_profile_registry('local-near-parity-r2010b', fake_root);
near_manifest.runtime_guard = 'supported_matlab';
run_error_test('missing spm8-r4667 root', ids.SPM_ROOT.NotFound, ...
    @() pseudo_CT_preflight(near_manifest, fake_root));

%% 9) Vers incomplete -> VERS:Incomplete.
bad_manifest = valid_manifest;
bad_manifest.vers_path = fullfile(fake_root, 'vers_incomplete');
run_error_test('vers override missing', ids.VERS.Incomplete, ...
    @() pseudo_CT_preflight(bad_manifest, fake_root));

%% 10) Vers wrong order -> VERS:WrongOrder.
bad_manifest = valid_manifest;
bad_manifest.vers_policy.order = {'spm_preproc_write8.m'; 'spm_vol_nifti.m'; 'spm_dicom_convert.m'};
run_error_test('vers wrong order', ids.VERS.WrongOrder, ...
    @() pseudo_CT_preflight(bad_manifest, fake_root));

%% 11) Atlas asset missing -> ATLAS:AssetMissing.
bad_manifest = valid_manifest;
bad_manifest.atlas_assets.batch_atlas_path = fullfile(fake_root, 'NoBatch_atlas');
run_error_test('atlas directory missing', ids.ATLAS.AssetMissing, ...
    @() pseudo_CT_preflight(bad_manifest, fake_root));

%% 12) Normalization shell metachar -> NORMALIZATION:ShellMetachar.
bad_manifest = valid_manifest;
bad_manifest.normalization_resource.source_command = 'source /path/to/env.sh; rm -rf /';
run_error_test('normalization shell metachar', ids.NORMALIZATION.ShellMetachar, ...
    @() pseudo_CT_preflight(bad_manifest, fake_root));

%% 13) PCA backend unavailable -> PCA:BackendUnavailable.
bad_manifest = valid_manifest;
bad_manifest.pca_order = {'unknown_backend'};
run_error_test('PCA backend unavailable', ids.PCA.BackendUnavailable, ...
    @() pseudo_CT_preflight(bad_manifest, fake_root));

%% 14) Alias invalid override -> ALIAS:InvalidOverride.
bad_manifest = valid_manifest;
bad_manifest.aliasing_override = [0 2];
run_error_test('alias invalid override', ids.ALIAS.InvalidOverride, ...
    @() pseudo_CT_preflight(bad_manifest, fake_root));

%% 15) Provenance record missing -> PROVENANCE:RecordMissing.
run_error_test('provenance record missing', ids.PROVENANCE.RecordMissing, ...
    @() pseudo_CT_provenance_record(fullfile(fake_root, 'spm8-r4667')));

%% 16) Provenance inventory missing -> PROVENANCE:InventoryMissing.
mkdir_maybe(fullfile(fake_root, 'spm8-r6313'));
fid = fopen(fullfile(fake_root, 'spm8-r6313', 'SOURCES.md'), 'w');
if fid ~= -1, fclose(fid); end
run_error_test('provenance inventory missing', ids.PROVENANCE.InventoryMissing, ...
    @() pseudo_CT_provenance_record(fullfile(fake_root, 'spm8-r6313'), ...
                                    fullfile(fake_root, 'spm8-r6313', 'SOURCES.md')));

%% 17) Valid local-current preflight passes.
try
    pseudo_CT_preflight(valid_manifest, fake_root);
    test_passed = test_passed + 1;
    fprintf('  PASS  valid local-current preflight\n');
catch ME
    test_failed = test_failed + 1;
    fprintf('  FAIL  valid local-current preflight: %s\n', ME.message);
end

%% Cleanup.
if ~isempty(cleanup_temp)
    rmdir(cleanup_temp, 's');
end

%% Report.
total = test_passed + test_failed;
fprintf('\n=== Deterministic Error ID Tests: %d/%d passed ===\n', test_passed, total);
if test_failed > 0
    error('test_deterministic_error_ids:Failures', '%d test(s) failed.', test_failed);
end

%% ------------------------------------------------------------------------
function run_test(label, ok)
    if ok
        test_passed = test_passed + 1;
        fprintf('  PASS  %s\n', label);
    else
        test_failed = test_failed + 1;
        fprintf('  FAIL  %s\n', label);
    end
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
    fake_root = fullfile(tempdir, 'pseudo_ct_pr1_test_repo');
    if exist(fake_root, 'dir') == 7
        rmdir(fake_root, 's');
    end
    mkdir(fake_root);
    cleanup_dir = fake_root;

    % SPM r6313 tree (empty directory is enough for existence check).
    mkdir_maybe(fullfile(fake_root, 'spm8-r6313'));

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
    touch(fullfile(cfg_dir, 'fs_setenv_530_from_launchpad.sh'));
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
    manifest.normalization_resource.child_lib_path = '';
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
    manifest.provenance.record_path = fullfile(fake_root, 'spm8-r6313', 'INVENTORY.json');
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
