function test_profile_authority()
%TEST_PROFILE_AUTHORITY Protect the canonical profile contract (one mechanism).
%   The registry is the only profile path in source and compiled modes. Profile
%   identity hashes the effective configuration, so a changed setting changes the
%   identity in both modes. No profile directory is scanned and no path is edited.

root_dir = fileparts(fileparts(mfilename('fullpath')));
old_path = path();
addpath(genpath(fullfile(root_dir, 'src')), '-begin');
addpath(root_dir, '-begin');
addpath(fullfile(root_dir, 'frontend'), '-begin');
cleanup = onCleanup(@() path(old_path)); %#ok<NASGU>

expected = sort({'local', 'mlsc', 'local-mprage-only', 'mlsc-mprage-only'});
profiles = pseudo_CT_list_profiles(false);
assert(isequal(sort({profiles.name}), expected), ...
    'The registry must expose exactly the four canonical profiles.');
assert(isequal(sort(pseudo_CT_profile_registry('keys'))', expected));

for ii = 1:length(expected)
    config = pseudo_CT_load_profile(expected{ii});
    assert(~isfield(config, 'implementation'));
    assert(isequal(config.pca_order, {'callable_pca'; 'repo_legacy'}));
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
        assert(strcmp(config.mode, 'mlsc') && isfield(config, 'current'));
    else
        assert(strcmp(config.mode, 'local'));
    end
end
presented = pseudo_CT_list_profiles(true);
assert(all(~cellfun('isempty', {presented.display_name})), ...
    'Every profile must carry its own presentation metadata.');

% Underscore spellings and display labels are rejected everywhere.
for alias = {'local_mprage_only', 'MLSC', 'mlsc mprage-only'}
    assert_identifier('pseudo_CT:InvalidProfile', ...
        @() pseudo_CT_load_profile(alias{1}), alias{1});
    assert_identifier('pseudo_CT:InvalidProfile', ...
        @() pseudo_CT_profile_registry('identity', alias{1}), alias{1});
end

% Identity: repeatable across calls, pairwise distinct for all four profiles,
% and changed by settings that alter results. Results are assigned to variables
% first because R2010b does not index a function result directly.
keys_all = pseudo_CT_profile_registry('keys');
hashes = cell(length(keys_all), 1);
for ii = 1:length(keys_all)
    first = pseudo_CT_profile_registry('identity', keys_all{ii});
    for rep = 1:5
        again = pseudo_CT_profile_registry('identity', keys_all{ii});
        assert(isequal(first, again), ...
            sprintf('Identity of %s must repeat exactly.', keys_all{ii}));
    end
    assert(strcmp(first.profile_identity_source, 'effective-config'));
    hashes{ii} = first.profile_sha256;
end
assert(length(unique(hashes)) == length(keys_all), ...
    'All four profile identities must be pairwise distinct.');
identity = pseudo_CT_profile_registry('identity', 'local-mprage-only');
config = pseudo_CT_profile_registry('invoke', 'local-mprage-only');
assert(strcmp(pseudo_CT_profile_registry('config_hash', config), identity.profile_sha256));
changed = config;
changed.fwhm = config.fwhm + 1;
assert(~strcmp(pseudo_CT_profile_registry('config_hash', changed), identity.profile_sha256), ...
    'A changed fwhm must change the profile identity.');
changed = config;
changed.io_policy.output = 'nifti-and-dicom';
assert(~strcmp(pseudo_CT_profile_registry('config_hash', changed), identity.profile_sha256), ...
    'A changed output policy must change the profile identity.');
changed = config;
changed.atlas_root = [config.atlas_root 'x'];
assert(~strcmp(pseudo_CT_profile_registry('config_hash', changed), identity.profile_sha256), ...
    'A changed atlas path must change the profile identity.');

% The registry is the only profile mechanism: direct references for compile
% closure and no discovery or path edits in the profile code.
registry_text = local_read(fullfile(root_dir, 'src', 'config', 'pseudo_CT_profile_registry.m'));
direct_calls = {'out = local();'; 'out = mlsc();'; ...
    'out = local_mprage_only();'; 'out = mlsc_mprage_only();'};
for ii = 1:length(direct_calls)
    assert(~isempty(strfind(registry_text, direct_calls{ii})), ...
        sprintf('Registry lost the direct reference %s.', direct_calls{ii}));
end
for name = {'pseudo_CT_list_profiles.m', 'pseudo_CT_load_profile.m'}
    text = local_read(fullfile(root_dir, 'src', 'config', name{1}));
    assert(isempty(strfind(text, 'dir(')) && isempty(strfind(text, 'addpath')) && ...
        isempty(strfind(text, 'fileparts(mfilename')), ...
        sprintf('%s must not scan profile files or edit the path.', name{1}));
end

% The development-only artifact-root override is accepted only by the MLSC profiles.
% A local profile is refused with the shared identifier; the MLSC profile applies it.
override_root = tempname;
override_identifier = '';
try
    pseudo_CT_apply_mlsc_current_overrides(pseudo_CT_load_profile('local'), ...
        'local', override_root);
catch ME
    override_identifier = ME.identifier;
end
assert(strcmp(override_identifier, 'run_pseudo_CT:InvalidMlscCurrentOverride'), ...
    'A local profile accepted the development-only artifact-root override.');
mlsc_override_config = pseudo_CT_apply_mlsc_current_overrides( ...
    pseudo_CT_load_profile('mlsc'), 'mlsc', override_root);
assert(~isempty(strfind(mlsc_override_config.current.runner, 'run_pseudoct_worker.sh')), ...
    'The MLSC profile did not apply the development-only artifact root.');

% Dispatch boundary without science or a scheduler: a deliberately missing
% MPRAGE input must fail in local validation before any job is dispatched.
work_dir = tempname;
mkdir(work_dir);
work_cleanup = onCleanup(@() rmdir(work_dir, 's')); %#ok<NASGU>
missing_input = fullfile(work_dir, 'missing_mprage.nii');
dispatch_profiles = {'local'; 'mlsc'; 'local-mprage-only'; 'mlsc-mprage-only'};
dispatch_backends = {'local'; 'mlsc'; 'local'; 'mlsc'};
for ii = 1:length(dispatch_profiles)
    % CLI path: run_pseudo_CT rejects a missing input before any launcher call.
    cli_identifier = '';
    try
        run_pseudo_CT('Profile', dispatch_profiles{ii}, 'MPRAGE', missing_input);
    catch ME
        cli_identifier = ME.identifier;
    end
    assert(strcmp(cli_identifier, 'pseudo_CT:OrchestrationInput'), ...
        sprintf('CLI path did not reject a missing input for %s.', dispatch_profiles{ii}));

    % Headless API path: a synthetic v2 validate request.
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

% The lifecycle has no interactive or subject-list entry any more: a run needs a
% profile and jobs resolved by validation; both refusals happen before processing.
assert_identifier('run_pseudo_CT:ProfileRequired', ...
    @() pseudo_CT_run_lifecycle(), 'A lifecycle run without arguments');
assert_identifier('pseudo_CT:ResolvedJobRequired', ...
    @() pseudo_CT_run_lifecycle('profile', 'local', 'subjects', missing_input), ...
    'A lifecycle run without validated jobs');

% Installed layout (no src/ tree): the same registry, no scan, and the resolved
% job carries the effective-configuration identity of that installation.
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
cleanup_env = onCleanup(@() local_restore(old_install, ...
    old_release, old_runtime_root, old_runtime_version)); %#ok<NASGU>
package = local_installed_package(work_root);
setenv('PSEUDOCT_INSTALL_ROOT', package.root);
setenv('PSEUDOCT_RUNTIME_RELEASE', '');
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', '');
setenv('PSEUDOCT_RUNTIME_MCR_VERSION', '');
installed = pseudo_CT_list_profiles(true);
assert(isequal(sort({installed.name}), expected));
installed_identity = pseudo_CT_profile_registry('identity', 'local-mprage-only');
assert(strcmp(installed_identity.profile_identity_source, 'effective-config'));
request = struct('profile', 'local-mprage-only', ...
    'subjects', {{package.input}}, ...
    'invocation_id', '6f1f5f0e-2b7a-4c1d-9e3a-0123456789ab');
validated = pseudo_CT_orchestrate('validate', request);
assert(validated.ok && strcmp(validated.authentication_status, 'not_attempted') && ...
    strcmp(validated.submission_status, 'not_attempted'));
assert(strcmp(validated.resolved_job.artifact_identity.profile_sha256, ...
    installed_identity.profile_sha256));
again = pseudo_CT_orchestrate('validate', request);
assert(isequal(validated.resolved_job.artifact_identity, ...
    again.resolved_job.artifact_identity), 'Repeated validation must agree.');

% A changed worker executable after validation makes the resolved job stale;
% submit rejects it before any dispatch.
local_write(fullfile(package.root, 'runtimes', 'R2014b', ...
    'pseudoct_worker'), {'changed synthetic payload executable'});
assert_identifier('pseudo_CT:StaleResolvedJob', ...
    @() pseudo_CT_orchestrate('submit', struct('resolved_job', validated.resolved_job)), ...
    'A changed payload executable');

% A changed input after a fresh validation makes that resolved job stale too.
fresh = pseudo_CT_orchestrate('validate', request);
assert(fresh.ok);
local_write(package.input, {'synthetic validation-only input', 'changed after validation'});
assert_identifier('pseudo_CT:StaleResolvedJob', ...
    @() pseudo_CT_orchestrate('submit', struct('resolved_job', fresh.resolved_job)), ...
    'A changed input');

fprintf(['Canonical registry, I/O policy, presentation, alias rejection, identity, ' ...
    'dispatch-boundary and installed validation checks passed.\n']);
end

function assert_identifier(identifier, handle, label)
raised = '';
try
    feval(handle);
catch ME
    raised = ME.identifier;
end
assert(strcmp(raised, identifier), ...
    sprintf('%s must raise %s, got [%s].', label, identifier, raised));
end

function package = local_installed_package(work)
%LOCAL_INSTALLED_PACKAGE Synthetic installed layout with a validation input.
package = struct('root', fullfile(work, 'installed-package'), ...
    'input', fullfile(work, 'synthetic-mprage.nii'), ...
    'mcr', fullfile(work, 'mcr-7.14'));
release_dir = fullfile(package.root, 'runtimes', 'R2014b');
mkdir(fullfile(package.root, 'bin'));
mkdir(fullfile(package.root, 'resources'));
mkdir(release_dir);
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
    ['printf "PSEUDOCT_RUNNER=\047%s\047\n" "$package/runtimes/R2014b/run_pseudoct_worker.sh"'];...
    ['printf "PSEUDOCT_MCR_ROOT=\047%s\047\n" ' local_shell_quote(package.mcr)]; ...
    'exit 0'});
local_chmod(launcher);
local_write(fullfile(package.root, 'manifest.json'), ...
    {'{"schema": "synthetic-installed-manifest"}'});
runner = fullfile(release_dir, 'run_pseudoct_worker.sh');
local_write(runner, {'#!/bin/sh'; 'exit 0'});
local_chmod(runner);
local_write(fullfile(package.mcr, 'runtime', 'glnxa64', 'libmwmclmcrrt.so.8.4'), ...
    {'synthetic runtime library'});
local_write(fullfile(package.mcr, 'toolbox', 'compiler', 'mcrversion.ver'), {'8.4'});
% Installed direct mode: no build or resource manifests. The worker executable
% and the standalone are identified by SHA-256 at validation and submit.
local_write(fullfile(release_dir, 'pseudoct_worker'), {'synthetic payload executable'});
local_write(fullfile(release_dir, 'pseudoct_standalone'), {'synthetic standalone'});
local_write_resources(fullfile(package.root, 'resources'));
local_write(package.input, {'synthetic validation-only input'});
% Installed setup verifies the packaged SPM DICOM dictionary; a synthetic one is enough.
dict = struct('values', 1); %#ok<NASGU>
save(fullfile(package.root, 'resources', 'spm_dicom_dict.mat'), 'dict', '-v6');
end

function local_write_resources(resources_dir)
%LOCAL_WRITE_RESOURCES Synthetic installed resource files (existence only).
names = {'ch2.nii'; 'new_segment_batch.mat'; ...
    'dartel_existing_template_batch.mat'; 'create_inverse_warped_batch.mat'; ...
    'Template_1.nii'; 'Template_2.nii'; 'Template_3.nii'; ...
    'Template_4.nii'; 'Template_5.nii'; 'Template_6.nii'; 'TPM.nii'; ...
    'Atlas_synthetic.nii'};
for ii = 1:length(names)
    local_write(fullfile(resources_dir, names{ii}), {'synthetic resource'});
end
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
