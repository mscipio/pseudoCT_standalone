function report = run_smoke_tests()
%RUN_SMOKE_TESTS Run the retained offline regression checks (no science).

tests_dir = fileparts(mfilename('fullpath'));
old_path = path();
addpath(tests_dir, '-begin');
cleanup = onCleanup(@() path(old_path)); %#ok<NASGU>
tests = {'test_profile_authority'; 'test_dependency_paths'; ...
    'test_runtime_selection'; ...
    'test_headless_result_validator'; 'test_cli_progress_output'; ...
    'test_exact_comparators'; 'test_mlsc_slurm_lifecycle'; 'test_build_application'; ...
    'test_frontend_launch'; 'test_lifecycle_arguments'};
failures = {};
for ii = 1:length(tests)
    try
        feval(tests{ii});
        fprintf('  PASS  %s\n', tests{ii});
    catch ME
        failures{end + 1} = sprintf('%s: %s', tests{ii}, ME.message); %#ok<AGROW>
        fprintf('  FAIL  %s: %s\n', tests{ii}, ME.message);
    end
end
report = struct('passed', length(tests) - length(failures), ...
    'failed', length(failures), 'failures', {failures});
if report.failed > 0
    error('pseudo_CT:FocusedTestsFailed', ...
        '%d focused test(s) failed.', report.failed);
end
end
