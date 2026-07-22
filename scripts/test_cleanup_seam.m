function test_cleanup_seam()
%TEST_CLEANUP_SEAM RED-first checks for the manifest-owned cleanup seam.
%   Verifies that cleanup_owner returns the manifest's cleanup_policy,
%   ignores PSEUDOCT_KEEP_TMP, and rejects invalid policies with
%   PROFILE:InvalidValue. No filesystem cleanup, SPM batch, or subject
%   mutation is run.
%
%   Minimum supported MATLAB: R2010b.

scripts_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(scripts_dir);
addpath(fullfile(root_dir, 'src', 'config'));
addpath(fullfile(root_dir, 'src', 'core'));

test_passed = 0;
test_failed = 0;
ids = pseudo_CT_error_ids();

%% 1) local-current returns remove_on_success.
manifest = pseudo_CT_profile_registry('local-current', root_dir);
[policy, ignored] = cleanup_owner(manifest);
run_test('local-current cleanup policy', strcmp(policy, 'remove_on_success'));
run_test('local-current no env ignored', isempty(ignored));

%% 2) PSEUDOCT_KEEP_TMP is ignored.
original_env = getenv('PSEUDOCT_KEEP_TMP');
cleanup_env = onCleanup(@() setenv('PSEUDOCT_KEEP_TMP', original_env)); %#ok<NASGU>
setenv('PSEUDOCT_KEEP_TMP', '1');
[policy2, ignored2] = cleanup_owner(manifest);
run_test('KEEP_TMP ignored', strcmp(ignored2, ids.ENV_IGNORED.KEEP_TMP));
run_test('cleanup policy unchanged', strcmp(policy2, 'remove_on_success'));

%% 3) Explicit keep_on_success policy.
keep_manifest = manifest;
keep_manifest.cleanup_policy = 'keep_on_success';
[policy3, ~] = cleanup_owner(keep_manifest);
run_test('keep_on_success policy', strcmp(policy3, 'keep_on_success'));

%% 4) Invalid cleanup policy raises PROFILE:InvalidValue.
bad_manifest = manifest;
bad_manifest.cleanup_policy = 'maybe';
run_error_test('invalid cleanup policy', ids.PROFILE.InvalidValue, ...
    @() cleanup_owner(bad_manifest));

%% 5) No manifest -> local-current default.
[policy_default, ~] = cleanup_owner();
run_test('default cleanup policy', strcmp(policy_default, 'remove_on_success'));

%% 6) fixed_bone_cleanup returns true and is mandatory.
[bone_enabled, fixed] = fixed_bone_cleanup(manifest);
run_test('bone reduction enabled', bone_enabled == true);
run_test('bone policy is fixed', fixed == true);

%% 7) Disabling bone in manifest raises BONE:CleanupFixed.
bad_bone = manifest;
bad_bone.bone_enabled = false;
run_error_test('bone disabled is rejected', ids.BONE.CleanupFixed, ...
    @() fixed_bone_cleanup(bad_bone));

%% 8) PSEUDOCT_KEEP_TMP does not affect bone policy.
[bone_enabled2, ~] = fixed_bone_cleanup(manifest);
run_test('bone unaffected by KEEP_TMP', bone_enabled2 == true);

%% Report.
total = test_passed + test_failed;
fprintf('\n=== Cleanup Seam Tests: %d/%d passed ===\n', test_passed, total);
if test_failed > 0
    error('test_cleanup_seam:Failures', '%d test(s) failed.', test_failed);
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
