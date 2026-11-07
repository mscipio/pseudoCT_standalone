function test_profile_authority()
%TEST_PROFILE_AUTHORITY Protect the public profile and entrypoint contract.

root_dir = fileparts(fileparts(mfilename('fullpath')));
old_path = path();
addpath(genpath(fullfile(root_dir, 'src')), '-begin');
cleanup = onCleanup(@() path(old_path)); %#ok<NASGU>

config_root = fullfile(root_dir, 'src', 'config');
expected = sort({'local', 'mlsc', 'local-mprage-only', ...
    'mlsc-mprage-only'});
profiles = pseudo_CT_list_profiles(config_root, false);
actual = sort({profiles.name});
assert(isequal(actual, expected), 'Profile discovery must expose four profiles.');

for ii = 1:length(expected)
    config = pseudo_CT_load_profile(expected{ii}, config_root);
    assert(~isfield(config, 'implementation'));
    assert(isequal(config.pca_order, {'callable_pca'; 'repo_legacy'}));
    assert(isfield(config, 'io_policy'));
    if ~isempty(strfind(expected{ii}, 'mprage-only'))
        assert(strcmp(config.io_policy.reference, 'none'));
        assert(strcmp(config.io_policy.output, 'nifti-only'));
        assert(strcmp(config.io_policy.gui, 'mprage-only'));
    else
        assert(strcmp(config.io_policy.reference, 'umap-required'));
        assert(strcmp(config.io_policy.output, 'nifti-and-dicom'));
        assert(strcmp(config.io_policy.gui, 'mMR'));
    end
    if strncmp(expected{ii}, 'mlsc', 4)
        assert(strcmp(config.mode, 'mlsc'));
        assert(isfield(config, 'current'));
    else
        assert(strcmp(config.mode, 'local'));
    end
end

gui_dir = fullfile(root_dir, 'src', 'gui');
addpath(gui_dir, '-begin');
[gui_profiles, default_index] = ...
    pseudo_CT_prepare_routine_profile_choices(config_root);
assert(isequal(sort({gui_profiles.name}), expected));
assert(strcmp(gui_profiles(default_index).name, 'mlsc'));

assert(exist(fullfile(root_dir, 'run_pseudo_CT.m'), 'file') == 2);
assert(exist(fullfile(root_dir, 'src', 'api', ...
    'pseudo_CT_headless.m'), 'file') == 2);
assert(exist(fullfile(root_dir, 'bin', 'pseudoct'), 'file') == 2);

% Dispatch boundary without science or a scheduler: a deliberately missing
% MPRAGE input must fail in local validation before any job is dispatched.
% The backend is asserted from the profile only; nothing is submitted.
work_dir = tempname;
mkdir(work_dir);
work_cleanup = onCleanup(@() rmdir(work_dir, 's')); %#ok<NASGU>
missing_input = fullfile(work_dir, 'missing_mprage.nii');
dispatch_profiles = {'local'; 'mlsc'; 'local-mprage-only'; 'mlsc-mprage-only'};
dispatch_backends = {'local'; 'mlsc'; 'local'; 'mlsc'};
for ii = 1:length(dispatch_profiles)
    % CLI/script path: run_pseudo_CT -> pseudo_CT_orchestrate('run').
    cli_identifier = '';
    try
        run_pseudo_CT('profile', dispatch_profiles{ii}, 'subjects', missing_input);
    catch ME
        cli_identifier = ME.identifier;
    end
    assert(strcmp(cli_identifier, 'pseudo_CT:OrchestrationInput'), ...
        sprintf('CLI path did not reject a missing input for %s.', dispatch_profiles{ii}));

    % Headless API path: a synthetic v2 validate request in the work directory.
    file_stem = strrep(dispatch_profiles{ii}, '-', '_');
    request_path = fullfile(work_dir, ['request_' file_stem '.mat']);
    result_path = fullfile(work_dir, ['result_' file_stem '.mat']);
    request = struct('schema', 'pseudoCT.headless-request/v2', ...
        'invocation_id', '6f1f5f0e-2b7a-4c1d-9e3a-0123456789ab', ...
        'action', 'validate', 'profile', dispatch_profiles{ii}, ...
        'subjects', missing_input, 'umap_files', {{}}, ...
        'output_config', struct(), 'options', struct(), ...
        'resolved_job', struct(), 'group_account', '', ...
        'credential_handoff', '', 'host_key_file', '', ...
        'current_artifact_root', '');
    save(request_path, 'request', '-v6');
    result = pseudo_CT_headless(request_path, result_path);
    assert(strcmp(result.status, 'failed'));
    assert(~isempty(result.error_code));
    assert(strcmp(result.dispatch_status, 'not_dispatched'));
    assert(strcmp(result.submission_status, 'not_attempted'));
    assert(isempty(result.job_ids));
    assert(isempty(fieldnames(result.resolved_job)));
    assert(strcmp(result.backend, dispatch_backends{ii}), ...
        sprintf('Backend for %s must be %s.', dispatch_profiles{ii}, dispatch_backends{ii}));
    saved = load(result_path, 'result');
    assert(strcmp(saved.result.dispatch_status, 'not_dispatched'));
end

fprintf(['Four-profile, I/O policy, public-entrypoint, and missing-input ' ...
    'dispatch checks passed.\n']);
end
