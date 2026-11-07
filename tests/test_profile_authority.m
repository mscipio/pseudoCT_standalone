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

% Installed package (no src/ tree): the four compiled profiles come from the
% direct registry, nothing is scanned or path-edited, and the profile identity
% is bound to the installed manifest. Compiled dependency capabilities are
% emulated here by the pinned external trees on the path (test-only); the
% synthetic package itself contains no MATLAB source.
scratch_root = getenv('PSEUDOCT_TEST_SCRATCH');
if isempty(scratch_root)
    scratch_root = tempdir;
end
work_root = tempname(scratch_root);
mkdir(work_root);
old_install = getenv('PSEUDOCT_INSTALL_ROOT');
old_release = getenv('PSEUDOCT_RUNTIME_RELEASE');
old_runtime_root = getenv('PSEUDOCT_RUNTIME_MCR_ROOT');
old_runtime_version = getenv('PSEUDOCT_RUNTIME_MCR_VERSION');
% Path state is owned by the top-level cleanup, which also removes the test-only
% external capability paths added below.
cleanup_env = onCleanup(@() local_restore(old_install, ...
    old_release, old_runtime_root, old_runtime_version)); %#ok<NASGU>

package = local_installed_package(work_root);
setenv('PSEUDOCT_INSTALL_ROOT', package.root);
setenv('PSEUDOCT_RUNTIME_RELEASE', '');
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', '');
setenv('PSEUDOCT_RUNTIME_MCR_VERSION', '');
absent_config_root = fullfile(work_root, 'absent-src-config');
installed = pseudo_CT_list_profiles(absent_config_root, true);
assert(isequal(sort({installed.name}), expected), ...
    'Installed registry must expose exactly the four canonical profiles.');
assert(all(cellfun('isempty', {installed.file_path})), ...
    'Installed profiles must not carry physical profile file paths.');
for ii = 1:length(expected)
    config = pseudo_CT_load_profile(expected{ii}, absent_config_root);
    assert(isfield(config, 'presentation') && isfield(config, 'io_policy'));
    if strncmp(expected{ii}, 'mlsc', 4)
        assert(strcmp(config.mode, 'mlsc'));
    else
        assert(strcmp(config.mode, 'local'));
    end
end
alias_identifier = '';
try
    pseudo_CT_load_profile('local_mprage_only', absent_config_root);
catch ME
    alias_identifier = ME.identifier;
end
assert(strcmp(alias_identifier, 'pseudo_CT:InvalidProfile'), ...
    'Underscore profile aliases must be rejected in installed mode.');

% Deterministic installed identity: bound to the canonical key and the
% installed manifest.json digest, with no profile file path.
manifest_path = fullfile(package.root, 'manifest.json');
manifest_sha = mlsc_release_gate('sha256_file', manifest_path);
identity_a = pseudo_CT_profile_registry('identity', 'local-mprage-only', package.root);
identity_b = pseudo_CT_profile_registry('identity', 'local-mprage-only', package.root);
assert(isequal(identity_a, identity_b), 'Installed profile identity must be deterministic.');
assert(strcmp(identity_a.profile_sha256, manifest_sha) && ~isempty(identity_a.profile_sha256));
assert(isempty(identity_a.profile_path) && ...
    strcmp(identity_a.profile_identity_source, 'installed-manifest'));
assert(~isequal(identity_a, pseudo_CT_profile_registry('identity', ...
    'mlsc-mprage-only', package.root)), 'Installed identity must bind the canonical key.');
identity_ok = true;
try
    pseudo_CT_profile_registry('identity', 'local_mprage_only', package.root);
    identity_ok = false;
catch ME
    identity_ok = strcmp(ME.identifier, 'pseudo_CT:InvalidProfile');
end
assert(identity_ok, 'Installed identity must reject underscore aliases.');

% Validation-only path through the public orchestrator, then a changed
% installed package. Submit revalidates the resolved job and must stop at the
% identity comparison, before any lifecycle dispatch. No science runs.
addpath(fullfile(root_dir, 'external', 'dicom2nifti-1.2.5'), '-begin');
addpath(fullfile(root_dir, 'external', 'spm8-r6313'), '-begin');
request = struct('profile', 'local-mprage-only', ...
    'subjects', {{package.input}}, ...
    'invocation_id', '6f1f5f0e-2b7a-4c1d-9e3a-0123456789ab');
validated = pseudo_CT_orchestrate('validate', request);
assert(validated.ok && strcmp(validated.authentication_status, 'not_attempted') && ...
    strcmp(validated.submission_status, 'not_attempted'));
assert(strcmp(validated.resolved_job.artifact_identity.profile_sha256, manifest_sha));
again = pseudo_CT_orchestrate('validate', request);
assert(isequal(validated.resolved_job.artifact_identity, ...
    again.resolved_job.artifact_identity), 'Repeated installed validation must agree.');
local_write(manifest_path, {'{"schema": "synthetic-installed-manifest", "changed": true}'});
rejected = '';
try
    pseudo_CT_orchestrate('submit', struct('resolved_job', validated.resolved_job));
catch ME
    rejected = ME.identifier;
end
assert(strcmp(rejected, 'pseudo_CT:StaleResolvedJob'), ...
    'A changed installed package must reject the resolved job before dispatch.');

% Source mode is unchanged for profile identity: a physical profile edit must
% change the identity. The edit is made to a scratch copy of the profiles.
setenv('PSEUDOCT_INSTALL_ROOT', '');
source_copy = fullfile(work_root, 'source-copy');
copy_profile_dir = fullfile(source_copy, 'src', 'config', 'profiles');
mkdir(copy_profile_dir);
profile_files = dir(fullfile(root_dir, 'src', 'config', 'profiles', '*.m'));
for ii = 1:length(profile_files)
    assert(copyfile(fullfile(root_dir, 'src', 'config', 'profiles', ...
        profile_files(ii).name), fullfile(copy_profile_dir, ...
        profile_files(ii).name)) == 1);
end
source_before = pseudo_CT_profile_registry('identity', 'local-mprage-only', source_copy);
assert(strcmp(source_before.profile_identity_source, 'source-file'));
assert(strcmp(source_before.profile_sha256, ...
    mlsc_release_gate('sha256_file', source_before.profile_path)));
local_append(fullfile(copy_profile_dir, 'local_mprage_only.m'), '% T001 edit probe');
source_after = pseudo_CT_profile_registry('identity', 'local-mprage-only', source_copy);
assert(~strcmp(source_before.profile_sha256, source_after.profile_sha256), ...
    'A source profile edit must change the profile identity.');

% Compile-closure contract: MATLAB Compiler reaches a profile only through a
% direct reference, so the registry must keep one direct call per profile
% (feval-only dispatch would drop the profile from the compiled package).
registry_text = local_read(fullfile(root_dir, 'src', 'config', ...
    'pseudo_CT_profile_registry.m'));
direct_calls = {'out = local();'; 'out = mlsc();'; ...
    'out = local_mprage_only();'; 'out = mlsc_mprage_only();'};
for ii = 1:length(direct_calls)
    assert(~isempty(strfind(registry_text, direct_calls{ii})), ...
        sprintf('Registry lost the direct reference %s.', direct_calls{ii}));
end

fprintf(['Four-profile, I/O policy, public-entrypoint, missing-input dispatch, ' ...
    'installed registry, identity, and changed-package checks passed.\n']);
end

function package = local_installed_package(work)
%LOCAL_INSTALLED_PACKAGE Synthetic installed layout with a validation input.
package = struct('root', fullfile(work, 'installed-package'), ...
    'input', fullfile(work, 'synthetic-mprage.nii'), ...
    'mcr', fullfile(work, 'mcr-7.14'));
payload = fullfile(package.root, 'runtimes', 'R2014b', 'payload');
mkdir(fullfile(package.root, 'bin'));
mkdir(fullfile(package.root, 'resources'));
mkdir(payload);
mkdir(fullfile(package.mcr, 'runtime', 'glnxa64'));
mkdir(fullfile(package.mcr, 'toolbox', 'compiler'));
launcher = fullfile(package.root, 'bin', 'pseudoct');
local_write(launcher, { ...
    '#!/bin/sh'; ...
    'if [ "$1" = "--list-releases" ]; then'; ...
    '  printf "R2014b\t8.4\tdefault\n"'; ...
    '  exit 0'; ...
    'fi'; ...
    'package=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)'; ...
    ['printf "PSEUDOCT_RUNNER=\047%s\047\n" "$package/runtimes/R2014b/payload/run_mlsc_current_payload.sh"'];...
    ['printf "PSEUDOCT_MCR_ROOT=\047%s\047\n" ' local_shell_quote(package.mcr)]; ...
    'exit 0'});
local_chmod(launcher);
local_write(fullfile(package.root, 'manifest.json'), ...
    {'{"schema": "synthetic-installed-manifest"}'});
runner = fullfile(payload, 'run_mlsc_current_payload.sh');
local_write(runner, {'#!/bin/sh'; 'exit 0'});
local_chmod(runner);
local_write(fullfile(package.mcr, 'runtime', 'glnxa64', 'libmwmclmcrrt.so.8.4'), ...
    {'synthetic runtime library'});
local_write(fullfile(package.mcr, 'toolbox', 'compiler', 'mcrversion.ver'), {'8.4'});
build = struct('schema', 'pseudo-CT.mlsc-current-build/v1', ...
    'manifest_version', 1, 'runner', runner, 'mcr_root', package.mcr, ...
    'release', 'R2014b', 'update_minimum', 0, 'mcr_version', [8 4], ...
    'arch', 'glnxa64', 'generation', '8.4', ...
    'runner_checksum', mlsc_release_gate('sha256_file', runner), ...
    'source_commit', 'synthetic-commit', ...
    'source_provenance_fingerprint', repmat('a', 1, 64), ...
    'required_outputs', {{'att_map.nii'; ...
        'Fusion_MR_Pseudo_CT_validation.tiff'; 'Pseudo_CT_AC_Version.txt'}});
save(fullfile(payload, 'build_manifest.mat'), 'build', '-v6');
resources = struct('schema', 'pseudo-CT.mlsc-current-resources/v1', ...
    'manifest_version', 1);
save(fullfile(payload, 'resource_manifest.mat'), 'resources', '-v6');
local_write(package.input, {'synthetic validation-only input'});
end

function local_write(path_text, lines)
fid = fopen(path_text, 'w');
if fid == -1
    error('test_profile_authority:Write', 'Cannot write %s.', path_text);
end
cleanup_fid = onCleanup(@() fclose(fid)); %#ok<NASGU>
for ii = 1:length(lines)
    fprintf(fid, '%s\n', lines{ii});
end
end

function text = local_read(path_text)
fid = fopen(path_text, 'r');
if fid == -1
    error('test_profile_authority:Read', 'Cannot read %s.', path_text);
end
cleanup_fid = onCleanup(@() fclose(fid)); %#ok<NASGU>
text = fscanf(fid, '%c');
end

function local_append(path_text, line)
fid = fopen(path_text, 'a');
if fid == -1
    error('test_profile_authority:Append', 'Cannot append %s.', path_text);
end
cleanup_fid = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%s\n', line);
end

function local_chmod(path_text)
[status, ~] = system(['chmod 755 ' local_shell_quote(path_text)]);
assert(status == 0, 'Cannot make synthetic launcher executable.');
end

function quoted = local_shell_quote(value)
quote = char(39);
quoted = [quote strrep(value, quote, [quote char(92) quote quote]) quote];
end

function local_restore(old_install, old_release, old_runtime_root, old_version)
setenv('PSEUDOCT_INSTALL_ROOT', old_install);
setenv('PSEUDOCT_RUNTIME_RELEASE', old_release);
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', old_runtime_root);
setenv('PSEUDOCT_RUNTIME_MCR_VERSION', old_version);
end
