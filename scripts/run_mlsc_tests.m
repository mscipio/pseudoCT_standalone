function report = run_mlsc_tests()
%RUN_MLSC_TESTS Run all credential-free MLSC-focused tests.

scripts_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(scripts_dir);
old_path = path();
addpath(scripts_dir, '-begin');
cleanup = onCleanup(@() path(old_path)); %#ok<NASGU>

tests = {'test_profile_authority'; 'test_mlsc_backend'; ...
    'test_mlsc_slurm_lifecycle'; 'test_mlsc_dispatch_integration'; ...
    'test_mlsc_ssh2_compatibility'; ...
    'test_launchpad_evidence'};
passed = 0;
failed = 0;
failures = {};

fprintf('=== MLSC Focused Tests ===\n');
fprintf('Root: %s\n\n', root_dir);
for ii = 1:length(tests)
    try
        feval(tests{ii});
        passed = passed + 1;
        fprintf('  PASS  %s\n', tests{ii});
    catch ME
        failed = failed + 1;
        failures{end + 1} = sprintf('%s: %s', tests{ii}, ME.message); %#ok<AGROW>
        fprintf('  FAIL  %s: %s\n', tests{ii}, ME.message);
    end
end

report = struct('passed', passed, 'failed', failed, 'failures', {failures});
fprintf('\n=== MLSC Focused Results: %d passed, %d failed ===\n', ...
    passed, failed);
if failed > 0
    error('MLSC focused tests failed.');
end
end
