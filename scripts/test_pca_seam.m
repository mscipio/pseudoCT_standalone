function test_pca_seam()
%TEST_PCA_SEAM RED-first checks for the manifest-owned PCA resolver.
%   Verifies that pseudo_CT_pca_resolver selects backends according to the
%   manifest's pca_order, never uses native princomp as the sole
%   implementation, ignores PSEUDOCT_USE_PRINCOMP, and returns a
%   legacy-compatible PCA function. No SPM batch, DICOM conversion,
%   SSH/PBS, or subject mutation is run.
%
%   Minimum supported MATLAB: R2010b.

scripts_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(scripts_dir);
addpath(fullfile(root_dir, 'src', 'config'));
addpath(fullfile(root_dir, 'src', 'core'));

test_passed = 0;
test_failed = 0;
ids = pseudo_CT_error_ids();

%% 1) local-current prefers callable_pca, then repo_legacy.
manifest = pseudo_CT_profile_registry('local-current', root_dir);
[pca_fn, backend_name, provenance] = pseudo_CT_pca_resolver(manifest);
run_test('local-current selects callable_pca', strcmp(backend_name, 'callable_pca'));
run_test('local-current provenance order', isequal(provenance.order, {'callable_pca'; 'repo_legacy'}));
run_test('local-current pca_fn is callable', isa(pca_fn, 'function_handle'));

%% 2) PCA function produces valid decomposition on a simple matrix.
X = [1 2; 3 4; 5 6];
[coef, score, latent] = pca_fn(X);
run_test('pca_fn returns coefficients', isnumeric(coef) && ~isempty(coef));
run_test('pca_fn returns scores', isnumeric(score) && ~isempty(score));
run_test('pca_fn returns latent', isnumeric(latent) && ~isempty(latent));

%% 3) near-parity prefers repo_legacy, then callable_pca.
near_manifest = pseudo_CT_profile_registry('local-near-parity-r2010b', root_dir);
near_manifest.runtime_guard = 'supported_matlab'; % disable R2010b-only guard for test
[pca_fn2, backend_name2, provenance2] = pseudo_CT_pca_resolver(near_manifest);
run_test('near-parity selects repo_legacy', strcmp(backend_name2, 'repo_legacy'));
run_test('near-parity provenance order', isequal(provenance2.order, {'repo_legacy'; 'callable_pca'}));

%% 4) launchpad remote PCA is not available locally.
launchpad_manifest = pseudo_CT_profile_registry('launchpad', root_dir);
run_error_test('launchpad remote PCA unavailable', ids.PCA.BackendUnavailable, ...
    @() pseudo_CT_pca_resolver(launchpad_manifest));

%% 5) Invalid PCA backend raises PCA:BackendUnavailable.
bad_manifest = manifest;
bad_manifest.pca_order = {'unknown_backend'};
run_error_test('invalid PCA backend', ids.PCA.BackendUnavailable, ...
    @() pseudo_CT_pca_resolver(bad_manifest));

%% 6) PSEUDOCT_USE_PRINCOMP is ignored and logged.
original_env = getenv('PSEUDOCT_USE_PRINCOMP');
cleanup_env = onCleanup(@() setenv('PSEUDOCT_USE_PRINCOMP', original_env)); %#ok<NASGU>
setenv('PSEUDOCT_USE_PRINCOMP', '1');
[~, ~, provenance_env] = pseudo_CT_pca_resolver(manifest);
run_test('USE_PRINCOMP ignored', strcmp(provenance_env.ignored_env, ids.ENV_IGNORED.USE_PRINCOMP));

%% 7) No manifest -> local-current default is used.
[~, backend_default, ~] = pseudo_CT_pca_resolver();
run_test('default manifest is local-current', strcmp(backend_default, 'callable_pca'));

%% Report.
total = test_passed + test_failed;
fprintf('\n=== PCA Seam Tests: %d/%d passed ===\n', test_passed, total);
if test_failed > 0
    error('test_pca_seam:Failures', '%d test(s) failed.', test_failed);
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
