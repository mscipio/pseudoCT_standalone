function test_runtime_selection()
%TEST_RUNTIME_SELECTION Protect source/installed Runtime binding boundaries.
%   Uses only synthetic package layouts and a fake resolver. No mcc, science,
%   scheduler, or deployed payload is invoked. Minimum MATLAB: R2010b.

root_dir = fileparts(fileparts(mfilename('fullpath')));
old_path = path();
old_install = getenv('PSEUDOCT_INSTALL_ROOT');
old_release = getenv('PSEUDOCT_RUNTIME_RELEASE');
old_runtime_root = getenv('PSEUDOCT_RUNTIME_MCR_ROOT');
old_mcr_label = getenv('PSEUDOCT_MCR_ROOT_R2014b');
old_mcr_global = getenv('PSEUDOCT_MCR_ROOT');
old_resolver_log = getenv('PSEUDOCT_TEST_RESOLVER_LOG');
old_bad_root = getenv('PSEUDOCT_TEST_BAD_ROOT');
cleanup = onCleanup(@() local_restore(old_path, old_install, ...
    old_release, old_runtime_root, old_mcr_label, old_mcr_global, ...
    old_resolver_log, old_bad_root)); %#ok<NASGU>
addpath(genpath(fullfile(root_dir, 'src')), '-begin');

scratch_root = getenv('PSEUDOCT_TEST_SCRATCH');
if isempty(scratch_root)
    scratch_root = fullfile(root_dir, '.aria', 'scratch', 'unplanned', ...
        '20261106-173831-runtime-selection-regressions');
end
if exist(scratch_root, 'dir') ~= 7
    mkdir(scratch_root);
end
work = tempname(scratch_root);
mkdir(work);

% A source-layout root with a resolver sentinel proves source selection is a
% no-op even when the launcher-root environment variable is nonempty.
source_root = fullfile(work, 'source-repo');
mkdir(fullfile(source_root, 'src'));
mkdir(fullfile(source_root, 'bin'));
local_link(fullfile(source_root, 'external'), fullfile(root_dir, 'external'));
local_link(fullfile(source_root, 'compiled'), fullfile(root_dir, 'compiled'));
sentinel = fullfile(work, 'source-resolver-invoked.log');
local_write(fullfile(source_root, 'bin', 'pseudoct'), { ...
    '#!/bin/sh'; ...
    ['printf invoked > ' local_shell_quote(sentinel)]; ...
    'exit 99'});
local_chmod(fullfile(source_root, 'bin', 'pseudoct'));

setenv('PSEUDOCT_INSTALL_ROOT', source_root);
setenv('PSEUDOCT_RUNTIME_RELEASE', '');
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', '');
setenv('PSEUDOCT_MCR_ROOT_R2014b', '');
setenv('PSEUDOCT_MCR_ROOT', '');
source_config = struct('marker', 'source-unchanged', ...
    'current', struct('runner', 'before'));
source_before = source_config;
source_after = pseudo_CT_runtime_select(source_config, 'R2014b');
assert(isequal(source_after, source_before), ...
    'Source-mode runtime selection must leave the config unchanged.');
assert(exist(sentinel, 'file') ~= 2, ...
    'Source-mode runtime selection must not invoke the resolver.');

% Exercise the actual v2 headless validation boundary with a missing input.
% The fake source root reuses only offline repository dependencies and current
% manifests through symlinks; no scientific path is reached after rejection.
missing_input = fullfile(work, 'missing-input.nii');
request_path = fullfile(work, 'source-request.mat');
result_path = fullfile(work, 'source-result.mat');
request = struct('schema', 'pseudoCT.headless-request/v2', ...
    'invocation_id', '6f1f5f0e-2b7a-4c1d-9e3a-0123456789ab', ...
    'action', 'validate', 'profile', 'local-mprage-only', ...
    'subjects', missing_input, 'umap_files', {{}}, ...
    'output_config', struct(), 'options', struct(), ...
    'resolved_job', struct(), 'group_account', '', ...
    'credential_handoff', '', 'host_key_file', '', ...
    'current_artifact_root', '');
save(request_path, 'request', '-v6');
result = pseudo_CT_headless(request_path, result_path);
assert(strcmp(result.status, 'failed'), ...
    'A missing input must be returned as a handled validation failure.');
assert(~isempty(result.error_code) && strcmp(result.dispatch_status, ...
    'not_dispatched') && strcmp(result.submission_status, 'not_attempted'));
% The headless result intentionally preserves the public result-code mapping;
% assert the underlying validation identifier separately so this regression
% cannot pass on a generic manifest/setup failure.
input_validation_request = struct('profile', 'local-mprage-only', ...
    'subjects', missing_input, 'output_config', struct(), ...
    'invocation_id', request.invocation_id);
input_validation_id = '';
try
    pseudo_CT_orchestrate('validate', input_validation_request);
catch ME
    input_validation_id = ME.identifier;
end
assert(strcmp(input_validation_id, 'pseudo_CT:OrchestrationInput'), ...
    'Source validation did not reach the missing-input check.');
assert(exist(sentinel, 'file') ~= 2, ...
    'Headless source validation must not invoke the resolver.');

% Exercise the real installed launcher with apostrophes in both the package
% and MATLAB Runtime roots. The resolver emits POSIX single-quote escapes;
% MATLAB must decode those values without sourcing or evaluating them.
actual_package_root = fullfile(work, ['installed-package' char(39) 's-root']);
actual_mcr_root = fullfile(work, ['mcr-it' char(39) 's-explicit']);
mkdir(fullfile(actual_package_root, 'bin'));
mkdir(fullfile(actual_package_root, 'runtimes', 'R2014b', 'app'));
mkdir(fullfile(actual_package_root, 'runtimes', 'R2014b', 'payload'));
mkdir(fullfile(actual_package_root, 'runtimes', 'R2014b', 'standalone'));
mkdir(fullfile(actual_mcr_root, 'runtime', 'glnxa64'));
mkdir(fullfile(actual_mcr_root, 'toolbox', 'compiler'));
assert(copyfile(fullfile(root_dir, 'bin', 'pseudoct'), ...
    fullfile(actual_package_root, 'bin', 'pseudoct')) == 1, ...
    'Cannot copy the real pseudoct launcher into the synthetic package.');
local_chmod(fullfile(actual_package_root, 'bin', 'pseudoct'));
local_write(fullfile(actual_package_root, 'manifest.json'), { ...
    '{'; ...
    '  "catalog": {'; ...
    '    "schema": 1,'; ...
    '    "default": "R2014b",'; ...
    '    "releases": [{'; ...
    '      "label": "R2014b",'; ...
    '      "matlab_version": "8.4",'; ...
    '      "mcr_version": "8.4",'; ...
    '      "architecture": "glnxa64",'; ...
    '      "runtime_identity": {'; ...
    '        "mcr_version_file": "toolbox/compiler/mcrversion.ver",'; ...
    '        "library": "libmwmclmcrrt.so.8.4"'; ...
    '      }'; ...
    '    }]'; ...
    '  }'; ...
    '}'});
actual_artifacts = {'app/run_pseudo_CT'; 'payload/mlsc_current_payload'; ...
    'payload/run_mlsc_current_payload.sh'; 'standalone/pseudoct_standalone'};
for ii = 1:length(actual_artifacts)
    artifact = fullfile(actual_package_root, 'runtimes', 'R2014b', ...
        actual_artifacts{ii});
    local_write(artifact, {'#!/bin/sh'; 'exit 0'});
    local_chmod(artifact);
end
local_write(fullfile(actual_mcr_root, 'runtime', 'glnxa64', ...
    'libmwmclmcrrt.so.8.4'), {'synthetic runtime library'});
local_write(fullfile(actual_mcr_root, 'toolbox', 'compiler', ...
    'mcrversion.ver'), {'8.4'});
setenv('PSEUDOCT_INSTALL_ROOT', actual_package_root);
setenv('PSEUDOCT_RUNTIME_RELEASE', '');
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', '');
setenv('PSEUDOCT_MCR_ROOT_R2014b', actual_mcr_root);
setenv('PSEUDOCT_MCR_ROOT', '');
actual_selected = pseudo_CT_runtime_select(local_runtime_config(), 'R2014b');
assert(strcmp(actual_selected.current.mcr_root, actual_mcr_root), ...
    'The resolver root with an apostrophe was not decoded exactly.');
assert(strcmp(actual_selected.current.runner, fullfile(actual_package_root, ...
    'runtimes', 'R2014b', 'payload', 'run_mlsc_current_payload.sh')), ...
    'The resolver runner with an apostrophe was not decoded exactly.');

% Synthetic installed package and resolver. The package intentionally has no
% src/ directory, so the shared layout helper must select installed mode.
package_root = fullfile(work, 'installed-package');
mkdir(fullfile(package_root, 'bin'));
mkdir(fullfile(package_root, 'runtimes', 'R2014b', 'payload'));
mkdir(fullfile(package_root, 'resources'));
local_write(fullfile(package_root, 'manifest.json'), {'synthetic manifest'});
runner = fullfile(package_root, 'runtimes', 'R2014b', 'payload', ...
    'run_mlsc_current_payload.sh');
local_write(runner, {'#!/bin/sh'; 'exit 0'});
local_chmod(runner);
mcr_root = fullfile(work, 'mcr-explicit');
global_root = fullfile(work, 'mcr-global');
conflicting_root = fullfile(work, 'mcr-conflicting');
bad_root = fullfile(work, 'mcr-bad');
mkdir(mcr_root);
mkdir(global_root);
mkdir(conflicting_root);
mkdir(bad_root);
resolver_log = fullfile(work, 'resolver.log');
local_write(fullfile(package_root, 'bin', 'pseudoct'), ...
    local_resolver_script());
local_chmod(fullfile(package_root, 'bin', 'pseudoct'));

setenv('PSEUDOCT_INSTALL_ROOT', package_root);
setenv('PSEUDOCT_TEST_RESOLVER_LOG', resolver_log);
setenv('PSEUDOCT_TEST_BAD_ROOT', bad_root);
setenv('PSEUDOCT_RUNTIME_RELEASE', '');
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', '');
setenv('PSEUDOCT_MCR_ROOT_R2014b', mcr_root);
setenv('PSEUDOCT_MCR_ROOT', global_root);
config = local_runtime_config();
selected = pseudo_CT_runtime_select(config, 'R2014b');
assert(strcmp(selected.current.release, 'R2014b'));
assert(strcmp(selected.current.runner, runner));
assert(strcmp(selected.current.mcr_root, mcr_root));
assert(strcmp(selected.current.build_manifest, fullfile(package_root, ...
    'runtimes', 'R2014b', 'payload', 'build_manifest.mat')));
assert(strcmp(selected.current.resource_manifest, fullfile(package_root, ...
    'runtimes', 'R2014b', 'payload', 'resource_manifest.mat')));
assert(strcmp(getenv('PSEUDOCT_RUNTIME_RELEASE'), 'R2014b'));
assert(strcmp(getenv('PSEUDOCT_RUNTIME_MCR_ROOT'), mcr_root));
paths = pseudo_CT_dependency_paths();
assert(strcmp(paths.install_root, package_root));
assert(strcmp(paths.atlas_root, fullfile(package_root, 'resources')));
assert(strcmp(mlsc_current_validate('pinned_mcr_root'), mcr_root));

% A launching R2014b root is propagated as an explicit resolver argument,
% taking precedence over conflicting catalog environment roots.
explicit_root = fullfile(work, 'mcr-launched-explicit');
mkdir(explicit_root);
setenv('PSEUDOCT_RUNTIME_RELEASE', 'R2014b');
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', explicit_root);
setenv('PSEUDOCT_MCR_ROOT_R2014b', conflicting_root);
setenv('PSEUDOCT_MCR_ROOT', global_root);
selected = pseudo_CT_runtime_select(config, 'R2014b');
assert(strcmp(selected.current.mcr_root, explicit_root));
resolver_text = local_read(resolver_log);
assert(~isempty(strfind(resolver_text, ...
    ['resolve --mcr R2014b --mcr-root ' explicit_root])), ...
    'The inherited runtime root was not propagated to resolve.');

% Resolver failure for the inherited root must be terminal; no environment
% fallback is allowed and the caller-visible config remains unchanged.
setenv('PSEUDOCT_RUNTIME_RELEASE', 'R2014b');
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', bad_root);
setenv('PSEUDOCT_MCR_ROOT_R2014b', mcr_root);
setenv('PSEUDOCT_MCR_ROOT', global_root);
before = config;
raised = false;
try
    pseudo_CT_runtime_select(config, 'R2014b');
catch ME
    raised = strcmp(ME.identifier, 'pseudo_CT:RuntimeSelection');
end
assert(raised, 'A resolver identity failure must be raised unchanged.');
assert(isequal(config, before), ...
    'Runtime selection must not change config after resolver failure.');

fprintf('Source/installed Runtime layout and root propagation checks passed.\n');
end

function config = local_runtime_config()
config = struct('mode', 'mlsc', 'current', struct( ...
    'runner', 'before-runner', 'mcr_root', 'before-mcr', ...
    'release', 'before-release', 'build_manifest', 'before-build', ...
    'resource_manifest', 'before-resource'));
end

function lines = local_resolver_script()
lines = { ...
    '#!/bin/sh'; ...
    'log=${PSEUDOCT_TEST_RESOLVER_LOG-}'; ...
    'printf "%s\\n" "$*" >> "$log"'; ...
    'if [ "$1" = "--list-releases" ]; then'; ...
    '  printf "R2014b\\t8.4\\tdefault\\n"'; ...
    '  exit 0'; ...
    'fi'; ...
    'label=""'; ...
    'root=""'; ...
    'while [ "$#" -gt 0 ]; do'; ...
    '  case "$1" in'; ...
    '    resolve) shift ;;'; ...
    '    --mcr) label=$2; shift 2 ;;'; ...
    '    --mcr-root) root=$2; shift 2 ;;'; ...
    '    *) shift ;;'; ...
    '  esac'; ...
    'done'; ...
    'if [ -z "$root" ]; then'; ...
    '  eval "root=\${PSEUDOCT_MCR_ROOT_${label}-}"'; ...
    '  [ -n "$root" ] || root=${PSEUDOCT_MCR_ROOT-}'; ...
    'fi'; ...
    'if [ "$root" = "${PSEUDOCT_TEST_BAD_ROOT-}" ]; then exit 69; fi'; ...
    'package=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)'; ...
    'printf "PSEUDOCT_RUNNER=\047%s\047\\n" "$package/runtimes/$label/payload/run_mlsc_current_payload.sh"'; ...
    'printf "PSEUDOCT_MCR_ROOT=\047%s\047\\n" "$root"'; ...
    'exit 0'};
end

function local_write(path_text, lines)
fid = fopen(path_text, 'w');
if fid == -1
    error('test_runtime_selection:Write', 'Cannot write %s.', path_text);
end
cleanup_fid = onCleanup(@() fclose(fid)); %#ok<NASGU>
for ii = 1:length(lines)
    fprintf(fid, '%s\n', lines{ii});
end
end

function local_chmod(path_text)
[status, ~] = system(['chmod 755 ' local_shell_quote(path_text)]);
assert(status == 0, 'Cannot make synthetic resolver executable.');
end

function local_link(link_path, target_path)
parent = fileparts(link_path);
if exist(parent, 'dir') ~= 7
    mkdir(parent);
end
[status, ~] = system(['ln -s ' local_shell_quote(target_path) ' ' ...
    local_shell_quote(link_path)]);
assert(status == 0, 'Cannot create synthetic dependency link.');
end

function text = local_read(path_text)
fid = fopen(path_text, 'r');
if fid == -1
    text = '';
    return;
end
cleanup_fid = onCleanup(@() fclose(fid)); %#ok<NASGU>
text = fscanf(fid, '%c');
end

function quoted = local_shell_quote(value)
quote = char(39);
quoted = [quote strrep(value, quote, [quote char(92) quote quote]) quote];
end

function local_restore(old_path, old_install, old_release, old_runtime_root, ...
        old_mcr_label, old_mcr_global, old_resolver_log, old_bad_root)
path(old_path);
setenv('PSEUDOCT_INSTALL_ROOT', old_install);
setenv('PSEUDOCT_RUNTIME_RELEASE', old_release);
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', old_runtime_root);
setenv('PSEUDOCT_MCR_ROOT_R2014b', old_mcr_label);
setenv('PSEUDOCT_MCR_ROOT', old_mcr_global);
setenv('PSEUDOCT_TEST_RESOLVER_LOG', old_resolver_log);
setenv('PSEUDOCT_TEST_BAD_ROOT', old_bad_root);
end
