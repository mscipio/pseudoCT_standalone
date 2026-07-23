function test_spm_preflight()
%TEST_SPM_PREFLIGHT RED-first compact fake-package and threat-case preflight checks.
%   Exercises the external SPM revision gate, vers/atlas/normalization/bone
%   checks, and fail-before-mutation contract using compact fake r6313/r4667
%   packages. No real SPM, subject, DICOM, FreeSurfer, SSH/PBS, or network
%   execution is required.
%
%   Minimum supported MATLAB: R2010b.

scripts_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(scripts_dir);
addpath(fullfile(root_dir, 'src', 'config'));
addpath(fullfile(root_dir, 'src', 'core'));

test_passed = 0;
test_failed = 0;
ids = pseudo_CT_error_ids();

%% Build compact fake r6313 and r4667 packages.
[fixture, cleanup_temp] = make_fake_packages(root_dir);

%% 1) Valid local-current (r6313) preflight passes.
manifest = make_manifest(fixture, 'local-current', 'r6313');
run_test('valid local-current r6313 preflight passes', ...
    preflight_passes(manifest, fixture.root));

%% 2) Valid near-parity (r4667) preflight passes.
manifest_np = make_manifest(fixture, 'local-near-parity-r2010b', 'r4667');
run_test('valid near-parity r4667 preflight passes', ...
    preflight_passes(manifest_np, fixture.root));

%% 3) Valid launchpad (r6313) preflight passes.
manifest_lp = make_manifest(fixture, 'launchpad', 'r6313');
run_test('valid launchpad r6313 preflight passes', ...
    preflight_passes(manifest_lp, fixture.root));

%% --- Threat: SPM root missing ---
bad = make_manifest(fixture, 'local-current', 'r6313');
bad.spm_root = fullfile(fixture.root, 'nonexistent-spm');
run_error_test('missing SPM root', ids.SPM_ROOT.NotFound, ...
    @() pseudo_CT_preflight(bad, fixture.root));

%% --- Threat: cross-linked package (r6313 profile -> r4667 Contents.m) ---
bad = make_manifest(fixture, 'local-current', 'r6313');
bad.spm_root = fixture.r4667_dir;
bad.spm_expected_revision = 'r6313';
run_error_test('cross-linked r6313->r4667 rejected', ids.SPM_ROOT.RevisionMismatch, ...
    @() pseudo_CT_preflight(bad, fixture.root));

%% --- Threat: cross-linked package (r4667 profile -> r6313 Contents.m) ---
bad = make_manifest(fixture, 'local-near-parity-r2010b', 'r4667');
bad.spm_root = fixture.r6313_dir;
bad.spm_expected_revision = 'r4667';
run_error_test('cross-linked r4667->r6313 rejected', ids.SPM_ROOT.RevisionMismatch, ...
    @() pseudo_CT_preflight(bad, fixture.root));

%% --- Threat: missing Contents.m ---
bad = make_manifest(fixture, 'local-current', 'r6313');
no_contents = fullfile(fixture.root, 'spm-no-contents');
mkdir(no_contents);
bad.spm_root = no_contents;
run_error_test('missing Contents.m rejected', ids.SPM_ROOT.RevisionMismatch, ...
    @() pseudo_CT_preflight(bad, fixture.root));
rmdir(no_contents, 's');

%% --- Threat: malformed Contents.m (unknown revision) ---
bad = make_manifest(fixture, 'local-current', 'r6313');
mal_root = fullfile(fixture.root, 'spm-malformed');
mkdir(mal_root);
write_contents(mal_root, '9999');
bad.spm_root = mal_root;
run_error_test('malformed Contents.m rejected', ids.SPM_ROOT.RevisionMismatch, ...
    @() pseudo_CT_preflight(bad, fixture.root));
rmdir(mal_root, 's');

%% --- Threat: missing vers overrides ---
bad = make_manifest(fixture, 'local-current', 'r6313');
bad.vers_path = fullfile(fixture.root, 'empty-vers');
mkdir(bad.vers_path);
run_error_test('missing vers overrides rejected', ids.VERS.Incomplete, ...
    @() pseudo_CT_preflight(bad, fixture.root));
rmdir(bad.vers_path, 's');

%% --- Threat: wrong vers order ---
bad = make_manifest(fixture, 'local-current', 'r6313');
bad.vers_policy.order = {'spm_preproc_write8.m'; 'spm_vol_nifti.m'; 'spm_dicom_convert.m'};
run_error_test('wrong vers order rejected', ids.VERS.WrongOrder, ...
    @() pseudo_CT_preflight(bad, fixture.root));

%% --- Threat: missing atlas assets ---
bad = make_manifest(fixture, 'local-current', 'r6313');
bad.atlas_assets.batch_atlas_path = fullfile(fixture.root, 'empty-atlas');
mkdir(bad.atlas_assets.batch_atlas_path);
run_error_test('missing atlas assets rejected', ids.ATLAS.AssetMissing, ...
    @() pseudo_CT_preflight(bad, fixture.root));
rmdir(bad.atlas_assets.batch_atlas_path, 's');

%% --- Threat: shell metachar in normalization command ---
bad = make_manifest(fixture, 'local-current', 'r6313');
bad.normalization_resource.source_command = 'source /tmp/x; rm -rf /';
run_error_test('normalization shell metachar rejected', ids.NORMALIZATION.ShellMetachar, ...
    @() pseudo_CT_preflight(bad, fixture.root));

%% --- Threat: disabled bone ---
bad = make_manifest(fixture, 'local-current', 'r6313');
bad.bone_enabled = false;
run_error_test('disabled bone rejected', ids.BONE.CleanupFixed, ...
    @() pseudo_CT_preflight(bad, fixture.root));

%% --- Fail-before-mutation contract ---
% Verify that pseudo_CT_preflight does NOT call addpath/genpath/rehash/which
% by checking that the MATLAB path is unchanged after a failing preflight.
path_before = path();
bad = make_manifest(fixture, 'local-current', 'r6313');
bad.spm_root = fullfile(fixture.root, 'nonexistent-spm');
try
    pseudo_CT_preflight(bad, fixture.root);
catch
    % expected
end
path_after = path();
run_test('failing preflight does not mutate MATLAB path', strcmp(path_before, path_after));

%% Cleanup.
if ~isempty(cleanup_temp)
    rmdir(cleanup_temp, 's');
end

%% Report.
total = test_passed + test_failed;
fprintf('\n=== SPM Preflight Threat Tests: %d/%d passed ===\n', test_passed, total);
if test_failed > 0
    error('test_spm_preflight:Failures', '%d test(s) failed.', test_failed);
end

%% ======================================================================
%  Helper functions
%  ======================================================================

%% ------------------------------------------------------------------------
function [fixture, cleanup_dir] = make_fake_packages(root_dir)
    fixture = struct();
    fixture.root = tempname;
    mkdir(fixture.root);
    cleanup_dir = fixture.root;

    % Fake r6313 package.
    fixture.r6313_dir = fullfile(fixture.root, 'spm8-r6313');
    mkdir(fixture.r6313_dir);
    write_contents(fixture.r6313_dir, '6313');

    % Fake r4667 package.
    fixture.r4667_dir = fullfile(fixture.root, 'spm8-r4667');
    mkdir(fixture.r4667_dir);
    write_contents(fixture.r4667_dir, '4667');

    % vers/ overrides.
    fixture.vers_dir = fullfile(fixture.root, 'vers');
    mkdir(fixture.vers_dir);
    touch(fullfile(fixture.vers_dir, 'spm_vol_nifti.m'));
    touch(fullfile(fixture.vers_dir, 'spm_preproc_write8.m'));
    touch(fullfile(fixture.vers_dir, 'spm_dicom_convert.m'));

    % Atlas assets.
    fixture.atlas_dir = fullfile(fixture.root, 'Batch_atlas');
    mkdir(fixture.atlas_dir);
    touch(fullfile(fixture.atlas_dir, 'TPM.nii'));
    touch(fullfile(fixture.atlas_dir, 'ch2.nii'));
    for ii = 0:6
        touch(fullfile(fixture.atlas_dir, sprintf('Template_%d.nii', ii)));
    end
    jar_dir = fullfile(fixture.atlas_dir, 'ganymed-ssh2-build250');
    mkdir(jar_dir);
    touch(fullfile(jar_dir, 'ganymed-ssh2-build250.jar'));

    % FreeSurfer env script.
    cfg_dir = fullfile(fixture.root, 'src', 'config');
    mkdir(cfg_dir);
    touch(fullfile(cfg_dir, 'fs_setenv_530_from_launchpad.sh'));
end

%% ------------------------------------------------------------------------
function manifest = make_manifest(fixture, profile_name, revision)
    manifest = struct();
    manifest.name = profile_name;
    manifest.spm_version = revision;
    manifest.spm_expected_revision = revision;
    manifest.vers_path = fixture.vers_dir;
    manifest.vers_policy = struct('order', ...
        {{'spm_vol_nifti.m'; 'spm_preproc_write8.m'; 'spm_dicom_convert.m'}}, ...
        'required', true);
    manifest.atlas_assets = struct();
    manifest.atlas_assets.batch_atlas_path = fixture.atlas_dir;
    manifest.atlas_assets.required_files = { ...
        'TPM.nii'; 'ch2.nii'; ...
        'Template_0.nii'; 'Template_1.nii'; 'Template_2.nii'; ...
        'Template_3.nii'; 'Template_4.nii'; 'Template_5.nii'; 'Template_6.nii'; ...
        fullfile('ganymed-ssh2-build250', 'ganymed-ssh2-build250.jar') ...
        };
    manifest.pca_order = {'callable_pca'; 'repo_legacy'};
    manifest.runtime_guard = 'supported_matlab';
    manifest.normalization_resource = struct();
    manifest.normalization_resource.source_command = ...
        sprintf('source %s', fullfile(fixture.root, 'src', 'config', 'fs_setenv_530_from_launchpad.sh'));
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
    manifest.provenance.expected_spm_version = revision;
    manifest.provenance.sha256_map = struct();
    manifest.provenance.record_path = '';

    % Set SPM root based on profile.
    switch lower(profile_name)
        case 'local-current'
            manifest.spm_root = fixture.r6313_dir;
        case 'local-near-parity-r2010b'
            manifest.spm_root = fixture.r4667_dir;
        case 'launchpad'
            manifest.spm_root = fixture.r6313_dir;
        otherwise
            manifest.spm_root = '';
    end
end

%% ------------------------------------------------------------------------
function ok = preflight_passes(manifest, root_dir)
    try
        pseudo_CT_preflight(manifest, root_dir);
        ok = true;
    catch
        ok = false;
    end
end

%% ------------------------------------------------------------------------
function write_contents(root_name, revision)
    fid = fopen(fullfile(root_name, 'Contents.m'), 'w');
    if fid == -1
        error('test_spm_preflight:Fixture', 'Could not write Contents.m.');
    end
    fprintf(fid, '%% Version %s (SPM8)\n', revision);
    fclose(fid);
end

%% ------------------------------------------------------------------------
function touch(p)
    fid = fopen(p, 'w');
    if fid ~= -1
        fclose(fid);
    end
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
    run_test(label, caught && strcmp(actual_id, expected_id));
    if caught && ~strcmp(actual_id, expected_id)
        fprintf('         expected %s, got %s\n', expected_id, actual_id);
    end
end

end
