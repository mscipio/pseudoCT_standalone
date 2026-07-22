function test_normalization_seam()
%TEST_NORMALIZATION_SEAM RED-first checks for the normalization runtime seam.
%   Verifies that pseudo_CT_normalization_runtime returns the manifest's
%   source_command and child_lib_path, ignores PSEUDOCT_FS_LIBSTDCPP_ROOT,
%   rejects shell metacharacters with NORMALIZATION:ShellMetachar, and
%   preserves deterministic error IDs. No FreeSurfer command, SSH/PBS, or
%   subject mutation is run.
%
%   Minimum supported MATLAB: R2010b.

scripts_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(scripts_dir);
addpath(fullfile(root_dir, 'src', 'config'));

test_passed = 0;
test_failed = 0;
ids = pseudo_CT_error_ids();

%% 1) local-current returns manifest source_command and child_lib_path.
manifest = pseudo_CT_profile_registry('local-current', root_dir);
[source_command, child_lib_path, ignored] = pseudo_CT_normalization_runtime(manifest);
run_test('local-current source_command is set', ~isempty(source_command));
run_test('local-current child_lib_path is set', ~isempty(child_lib_path));
run_test('local-current no env ignored', isempty(ignored));

%% 2) PSEUDOCT_FS_LIBSTDCPP_ROOT is ignored.
original_env = getenv('PSEUDOCT_FS_LIBSTDCPP_ROOT');
cleanup_env = onCleanup(@() setenv('PSEUDOCT_FS_LIBSTDCPP_ROOT', original_env)); %#ok<NASGU>
setenv('PSEUDOCT_FS_LIBSTDCPP_ROOT', '/malicious/path');
[source_command2, child_lib_path2, ignored2] = pseudo_CT_normalization_runtime(manifest);
run_test('FS_LIBSTDCPP_ROOT ignored', strcmp(ignored2, ids.ENV_IGNORED.FS_LIBSTDCPP_ROOT));
run_test('child_lib_path still from manifest', strcmp(child_lib_path2, child_lib_path));
run_test('source_command unchanged', strcmp(source_command2, source_command));

%% 3) Shell metachar in source_command is rejected.
bad_manifest = manifest;
bad_manifest.normalization_resource.source_command = 'source /path/to/env.sh; rm -rf /';
run_error_test('source_command shell metachar', ids.NORMALIZATION.ShellMetachar, ...
    @() pseudo_CT_normalization_runtime(bad_manifest));

%% 4) Shell metachar in child_lib_path is rejected.
bad_manifest2 = manifest;
bad_manifest2.normalization_resource.child_lib_path = '/path; rm -rf /';
run_error_test('child_lib_path shell metachar', ids.NORMALIZATION.ShellMetachar, ...
    @() pseudo_CT_normalization_runtime(bad_manifest2));

%% 5) Missing source_command raises SourceCommandMissing.
bad_manifest3 = manifest;
bad_manifest3.normalization_resource = rmfield(bad_manifest3.normalization_resource, 'source_command');
run_error_test('missing source_command', ids.NORMALIZATION.SourceCommandMissing, ...
    @() pseudo_CT_normalization_runtime(bad_manifest3));

%% 6) Empty source_command raises SourceCommandMissing.
bad_manifest4 = manifest;
bad_manifest4.normalization_resource.source_command = '';
run_error_test('empty source_command', ids.NORMALIZATION.SourceCommandMissing, ...
    @() pseudo_CT_normalization_runtime(bad_manifest4));

%% 7) No manifest -> local-current default is used.
[source_default, child_default, ~] = pseudo_CT_normalization_runtime();
run_test('default source_command is set', ~isempty(source_default));
run_test('default child_lib_path is set', ~isempty(child_default));

%% Report.
total = test_passed + test_failed;
fprintf('\n=== Normalization Seam Tests: %d/%d passed ===\n', test_passed, total);
if test_failed > 0
    error('test_normalization_seam:Failures', '%d test(s) failed.', test_failed);
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

end
