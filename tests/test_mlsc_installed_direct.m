function test_mlsc_installed_direct()
%TEST_MLSC_INSTALLED_DIRECT Offline installed-direct and manifest-mode MLSC staging.
%   Generates the MLSC Slurm script from synthetic fixtures in two modes:
%   installed direct (build and resource manifest paths cleared, no manifest
%   read, hashed or staged, two-argument worker calls) and source manifest
%   mode (manifest paths set, three-argument worker calls, unchanged staging).
%   Also checks the node-local lifecycle contract and that a missing packaged
%   resource fails closed. No SSH, scheduler command, worker, or science runs:
%   the submit callback only returns a fixed job identifier.

root_dir = fileparts(fileparts(mfilename('fullpath')));
old_path = path();
addpath(genpath(fullfile(root_dir, 'src')), '-begin');
cleanup_path = onCleanup(@() path(old_path)); %#ok<NASGU>

env_names = {'PSEUDOCT_INSTALL_ROOT'; 'PSEUDOCT_RUNTIME_RELEASE'; ...
    'PSEUDOCT_RUNTIME_MCR_ROOT'; 'PSEUDOCT_RUNTIME_MCR_VERSION'};
old_env = cell(size(env_names));
for ii = 1:length(env_names)
    old_env{ii} = getenv(env_names{ii});
end
cleanup_env = onCleanup(@() local_restore_env(env_names, old_env)); %#ok<NASGU>

scratch_root = getenv('PSEUDOCT_TEST_SCRATCH');
if isempty(scratch_root)
    scratch_root = fullfile(root_dir, '.aria', 'scratch', 'unplanned', ...
        [datestr(now, 'yyyymmdd-HHMMSS') '-pseudoct-tests']);
end
if exist(scratch_root, 'dir') ~= 7
    mkdir(scratch_root);
end
test_root = tempname(scratch_root);
mkdir(test_root);
cleanup_root = onCleanup(@() local_cleanup(test_root)); %#ok<NASGU>

fix = fullfile(test_root, 'fixtures');
local_make_fixtures(fix);
resources_dir = fullfile(fix, 'resources');
runner_path = fullfile(fix, 'runner', 'run_pseudoct_worker.sh');
newline = sprintf('\n');

% Source manifest mode control: both manifests set, runner and manifests unchanged.
local_clear_env(env_names);
config = pseudo_CT_load_profile('mlsc');
config.current.runner = runner_path;
config.current.build_manifest = fullfile(fix, 'build', 'mlsc_current_build.mat');
config.current.resource_manifest = fullfile(fix, 'build', 'mlsc_current_resources.mat');
case_root = fullfile(test_root, 'manifest');
[artifact, subject_dir] = local_generate(case_root, config);
script = artifact.script_text;
assert(~isempty(strfind(script, ['cp -- "$shared_resource_manifest" ' ...
    '"$local_resource_manifest"'])), ...
    'Manifest mode must keep staging the resource manifest.');
assert(~isempty(strfind(script, ['"$current_runner" "$current_mcr_root" ' ...
    'prepare "$local_job_manifest" "$local_resource_manifest"' newline])), ...
    'Manifest mode must keep the three-argument prepare call.');
assert(~isempty(strfind(script, ['"$current_runner" "$current_mcr_root" ' ...
    'compute "$local_job_manifest" "$local_resource_manifest"' newline])), ...
    'Manifest mode must keep the three-argument compute call.');
assert(strcmp(artifact.current_resource_manifest, config.current.resource_manifest));
assert(strcmp(artifact.current_build_manifest, config.current.build_manifest));
result = local_lifecycle(case_root, config);
assert(result.contract.represented && result.contract.shared_input_staging && ...
    result.contract.shared_output_staging, ...
    'Manifest-mode lifecycle node-local contract was not represented.');

% Installed direct mode: both manifest paths cleared under an installed layout.
case_root = fullfile(test_root, 'direct');
config = pseudo_CT_load_profile('mlsc');
config.current.runner = runner_path;
config.current.mcr_root = fullfile(fix, 'mcr');
config.current.build_manifest = '';
config.current.resource_manifest = '';
config.atlas_root = resources_dir;
setenv('PSEUDOCT_INSTALL_ROOT', fullfile(fix, 'install'));
setenv('PSEUDOCT_RUNTIME_RELEASE', 'R2016a');
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', fullfile(fix, 'mcr'));
setenv('PSEUDOCT_RUNTIME_MCR_VERSION', '9.4');
[artifact, subject_dir] = local_generate(case_root, config);
script = artifact.script_text;
forbidden = {'shared_resource_manifest'; 'local_resource_manifest'; ...
    'shared_build_manifest'; 'expected_build_'; 'expected_resource_'; ...
    'resource_manifest'; 'mlsc_current_build'; 'mlsc_current_resources'};
for ii = 1:length(forbidden)
    assert(isempty(strfind(script, forbidden{ii})), ...
        sprintf('Direct-mode script must not reference %s.', forbidden{ii}));
end
assert(isempty(strfind(script, 'resource_manifest.mat')));
assert(isempty(strfind(script, 'build_manifest.mat')));
assert(~isempty(strfind(script, ['"$current_runner" "$current_mcr_root" ' ...
    'prepare "$local_job_manifest"' newline])), ...
    'Direct mode must call prepare with the two-argument worker form.');
assert(~isempty(strfind(script, ['"$current_runner" "$current_mcr_root" ' ...
    'compute "$local_job_manifest"' newline])), ...
    'Direct mode must call compute with the two-argument worker form.');
assert(~isempty(strfind(script, ['cp -- "$shared_job_manifest" ' ...
    '"$local_job_manifest"'])), 'Direct mode must stage the job manifest.');
assert(~isempty(strfind(script, ['current_runner=''' runner_path ''''])));
assert(isempty(strfind(script, 'run_mlsc_current_payload')));
assert(strcmp(artifact.current_resource_manifest, ''));
assert(strcmp(artifact.current_build_manifest, ''));
assert(~isempty(artifact.submission_command));
assert(exist(fullfile(subject_dir, 'resource_manifest.mat'), 'file') ~= 2);
assert(exist(fullfile(subject_dir, 'build_manifest.mat'), 'file') ~= 2);
job = local_load_struct(fullfile(subject_dir, 'mlsc_current_job.mat'), 'job');
assert(strcmp(job.schema, 'pseudo-CT.mlsc-current-job/v1'));
assert(strcmp(job.atlas_dir, resources_dir), ...
    'Direct-mode job atlas_dir must be the packaged resources folder.');
% Setup (validate purpose) accepts the manifest-free installed direct contract:
% the packaged resources and SPM dictionary are checked by name, and neither a
% manifest nor a source ssh2 tree is required.
setup_pseudo_CT_paths(fullfile(fix, 'install'), config, 'validate', false, false);
result = local_lifecycle(case_root, config);
assert(result.contract.represented && result.contract.shared_input_staging && ...
    result.contract.shared_output_staging, ...
    'Direct-mode lifecycle node-local contract was not represented.');

% Negative: a source layout must not accept the cleared manifest pair. Direct mode
% is an installed-only contract. The T002 application guard is not run by setup,
% so the refusal comes from the MLSC current-artifact check in setup itself.
local_clear_env(env_names);
source_config = pseudo_CT_load_profile('mlsc');
source_config.current.runner = runner_path;
source_config.current.build_manifest = '';
source_config.current.resource_manifest = '';
caught = '';
try
    setup_pseudo_CT_paths(root_dir, source_config, 'validate', false, false);
catch ME
    caught = ME.identifier;
end
assert(strcmp(caught, 'pseudo_CT:InvalidProfile'), ...
    'Source layout must reject a cleared build and resource manifest pair.');

% Fail closed: a missing packaged resource stops generation before submission.
local_clear_env(env_names);
setenv('PSEUDOCT_INSTALL_ROOT', fullfile(fix, 'install'));
setenv('PSEUDOCT_RUNTIME_RELEASE', 'R2016a');
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', fullfile(fix, 'mcr'));
setenv('PSEUDOCT_RUNTIME_MCR_VERSION', '9.4');
missing_dir = fullfile(fix, 'resources_missing');
local_make_resources(missing_dir, 'TPM.nii');
config.atlas_root = missing_dir;
caught = '';
try
    local_generate(fullfile(test_root, 'missing'), config);
catch ME
    caught = ME.identifier;
end
assert(strcmp(caught, 'pseudo_CT:MissingResource'), ...
    'A missing installed resource must fail closed before generation.');

fprintf('Installed-direct and manifest-mode MLSC generation/staging checks passed.\n');
end

function [artifact, subject_dir] = local_generate(case_root, config)
subject_dir = fullfile(case_root, 'subject');
mkdir(subject_dir);
input_path = fullfile(subject_dir, 'mprage.nii');
local_write(input_path, 'synthetic input');
subject = struct('subject_id', 't003-direct', 'shared_input', input_path, ...
    'shared_temp', subject_dir, 'check_aliasing', 0, ...
    'recenter_before_normalization', 'No');
runtime = struct('account', 'test-account', ...
    'script_path', fullfile(case_root, 'job.sh'), ...
    'submission_correlation_id', 't003direct');
artifact = mlsc_generate_slurm_script(subject, config, runtime);
end

function result = local_lifecycle(case_root, config)
subject_dir = fullfile(case_root, 'lifecycle');
evidence_dir = fullfile(case_root, 'evidence');
mkdir(subject_dir);
mkdir(evidence_dir);
input_path = fullfile(subject_dir, 'mprage.nii');
local_write(input_path, 'synthetic input');
subject = struct('subject_id', 't003-lifecycle', 'shared_input', input_path, ...
    'shared_temp', subject_dir, 'check_aliasing', 0, ...
    'recenter_before_normalization', 'No');
runtime = struct('account', 'test-account', ...
    'script_path', fullfile(case_root, 'job.sh'), ...
    'evidence_dir', evidence_dir, 'log_archive_dir', evidence_dir, ...
    'timeout_seconds', 60, 'poll_interval_seconds', 1, ...
    'accounting_timeout_seconds', 1, 'max_polls', 1, ...
    'max_accounting_polls', 2, 'max_reconciliation_polls', 1, ...
    'reconciliation_interval_seconds', 1, ...
    'submission_correlation_id', 't003lifecycle');
transport = struct('verify', @() true, ...
    'submit_script', @(command) '31415;mlsc', ...
    'query_squeue', @(varargin) 'RUNNING', ...
    'query_sacct', @(varargin) ...
    '31415|FAILED|2:0|2026-11-06T12:00:00|2026-11-06T12:01:00|60', ...
    'query_squeue_by_name', @(varargin) '', ...
    'query_sacct_by_name', @(varargin) '', ...
    'cancel_job', @(varargin) [], 'sleep', @(varargin) [], ...
    'clock', @(varargin) datenum(2026, 11, 6, 12, 0, 0));
evalc('result = mlsc_lifecycle(subject, config, runtime, transport);');
end

function local_make_fixtures(fix)
%LOCAL_MAKE_FIXTURES Synthetic placeholder files only; nothing is executed.
local_make_dir(fullfile(fix, 'runner'));
local_make_dir(fullfile(fix, 'build'));
local_make_dir(fullfile(fix, 'install', 'runtimes'));
local_make_dir(fullfile(fix, 'install', 'bin'));
local_make_dir(fullfile(fix, 'mcr', 'runtime', 'glnxa64'));
local_make_dir(fullfile(fix, 'mcr', 'toolbox', 'compiler'));
local_write(fullfile(fix, 'runner', 'run_pseudoct_worker.sh'), ...
    sprintf('#!/bin/sh\n# Synthetic runner fixture; never executed.\n'));
local_write(fullfile(fix, 'runner', 'pseudoct_worker'), ...
    sprintf('Synthetic payload fixture; never executed.\n'));
local_write(fullfile(fix, 'install', 'bin', 'pseudoct'), sprintf('#!/bin/sh\n'));
local_write(fullfile(fix, 'install', 'manifest.json'), sprintf('{}\n'));
local_write(fullfile(fix, 'mcr', 'runtime', 'glnxa64', 'libmwmclmcrrt.so.9.4'), ...
    sprintf('synthetic\n'));
local_write(fullfile(fix, 'mcr', 'toolbox', 'compiler', 'mcrversion.ver'), ...
    sprintf('9.4\n'));
resources_dir = fullfile(fix, 'resources');
local_make_resources(resources_dir, '');
dict = struct('synthetic_dictionary', 1); %#ok<NASGU>
save(fullfile(resources_dir, 'spm_dicom_dict.mat'), 'dict', '-v6');
names = local_resource_names();
runner_sha = local_sha256(fullfile(fix, 'runner', 'run_pseudoct_worker.sh'));
build = struct('schema', 'pseudo-CT.mlsc-current-build/v1', ...
    'manifest_version', 1, 'runner', fullfile(fix, 'runner', 'run_pseudoct_worker.sh'), ...
    'mcr_root', '/usr/pubsw/common/matlab/7.11', 'release', 'R2010b', ...
    'update_minimum', 0, 'mcr_version', [7 14], 'arch', 'glnxa64', ...
    'generation', '7.14', 'runner_checksum', runner_sha, ...
    'source_commit', 't003-fixture', ...
    'source_provenance_fingerprint', repmat('a', 1, 64), ...
    'required_outputs', {{'att_map.nii'; ...
    'Fusion_MR_Pseudo_CT_validation.tiff'; 'Pseudo_CT_AC_Version.txt'}});
save(fullfile(fix, 'build', 'mlsc_current_build.mat'), 'build', '-v6');
resources = struct('schema', 'pseudo-CT.mlsc-current-resources/v1', ...
    'manifest_version', 1, 'atlas_dir', resources_dir, ...
    'atlas_list', {{'Fixture_Atlas.nii'}}, 'resource_names', {names});
save(fullfile(fix, 'build', 'mlsc_current_resources.mat'), 'resources', '-v6');
end

function local_make_resources(resources_dir, omit_name)
local_make_dir(resources_dir);
names = local_resource_names();
for ii = 1:length(names)
    if ~strcmp(names{ii}, omit_name)
        local_write(fullfile(resources_dir, names{ii}), sprintf('synthetic %d\n', ii));
    end
end
end

function names = local_resource_names()
names = {'ch2.nii'; 'new_segment_batch.mat'; ...
    'dartel_existing_template_batch.mat'; 'create_inverse_warped_batch.mat'; ...
    'Template_1.nii'; 'Template_2.nii'; 'Template_3.nii'; ...
    'Template_4.nii'; 'Template_5.nii'; 'Template_6.nii'; 'TPM.nii'; ...
    'Fixture_Atlas.nii'};
end

function value = local_sha256(path_name)
[status, output] = system(['sha256sum ''' path_name ''' 2>/dev/null']);
assert(status == 0, 'SHA-256 fixture utility unavailable.');
tokens = regexp(strtrim(output), '^([0-9a-fA-F]{64})(?![0-9a-fA-F])', ...
    'tokens', 'once');
assert(~isempty(tokens), 'Unable to parse SHA-256 fixture digest.');
value = lower(tokens{1});
end

function value = local_load_struct(path_name, variable_name)
loaded = load(path_name);
assert(isfield(loaded, variable_name), 'Job fixture variable is missing.');
value = loaded.(variable_name);
end

function local_clear_env(names)
for ii = 1:length(names)
    setenv(names{ii}, '');
end
end

function local_restore_env(names, values)
for ii = 1:length(names)
    setenv(names{ii}, values{ii});
end
end

function local_make_dir(directory)
if exist(directory, 'dir') ~= 7
    mkdir(directory);
end
end

function local_write(path_name, text)
fid = fopen(path_name, 'w');
assert(fid ~= -1, 'Unable to create a MLSC fixture.');
fwrite(fid, text);
fclose(fid);
end

function local_cleanup(directory)
if exist(directory, 'dir') == 7
    rmdir(directory, 's');
end
end
