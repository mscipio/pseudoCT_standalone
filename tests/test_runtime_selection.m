function test_runtime_selection()
%TEST_RUNTIME_SELECTION Protect source/installed Runtime binding boundaries.
%   A source checkout is development-only: an application validation is refused
%   with an actionable message before any artifact is consulted, and no legacy
%   compiled tree is resolved. An installed package binds one release through the
%   real launcher, whose only root sources are --mcr-root and the catalog location
%   <base>/<D>, D the first two dotted components of matlab_version (9.6.0.1072779
%   -> 9.6); environment variables never select a root. Every catalog release is
%   resolved from a synthetic base under scratch (the launcher's fixed base is replaced
%   in the test copy only), and the real /usr/pubsw tree is never consulted. Uses only
%   synthetic package layouts and a fake resolver. No mcc, science, scheduler, or
%   deployed worker is invoked. Minimum MATLAB: R2010b.

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
% Synthetic catalog base: the only place the launcher looks for catalog MCR roots here.
catalog_base = fullfile(work, 'catalog-matlab');
mkdir(catalog_base);

% A source-layout root with a resolver sentinel proves that source selection is a
% no-op and that no resolver is invoked.
source_root = fullfile(work, 'source-repo');
mkdir(fullfile(source_root, 'src'));
mkdir(fullfile(source_root, 'bin'));
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

% A source checkout refuses an application validation before any profile artifact
% is resolved: the refusal is actionable and names the installed distribution.
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
    'A source application validation must be returned as a handled failure.');
assert(~isempty(result.error_code) && strcmp(result.dispatch_status, ...
    'not_dispatched') && strcmp(result.submission_status, 'not_attempted'));
refused_identifier = '';
refused_message = '';
try
    pseudo_CT_orchestrate('validate', struct('profile', 'local-mprage-only', ...
        'subjects', missing_input, 'output_config', struct(), ...
        'invocation_id', request.invocation_id));
catch ME
    refused_identifier = ME.identifier;
    refused_message = ME.message;
end
assert(strcmp(refused_identifier, 'pseudo_CT:SourceCheckoutDevelopmentOnly'), ...
    sprintf('Source application validation must be refused, got [%s].', ...
    refused_identifier));
assert(~isempty(strfind(refused_message, 'install the pseudoCT distribution')), ...
    'The source refusal must tell the user to install the distribution.');
assert(exist(sentinel, 'file') ~= 2, ...
    'A refused source validation must not invoke the resolver.');

% Installed package with the real launcher. The synthetic catalog names a
% matlab_version whose catalog location is absent by construction, so only
% --mcr-root can select the root. Apostrophes in the package and root paths are
% passed as launcher arguments and decoded by MATLAB without evaluation.
actual_package_root = fullfile(work, ['installed-package' char(39) 's-root']);
actual_mcr_root = fullfile(work, ['mcr-it' char(39) 's-explicit']);
mkdir(fullfile(actual_package_root, 'bin'));
mkdir(fullfile(actual_package_root, 'runtimes', 'R2014b'));
mkdir(fullfile(actual_mcr_root, 'runtime', 'glnxa64'));
mkdir(fullfile(actual_mcr_root, 'toolbox', 'compiler'));
local_write(fullfile(actual_package_root, 'bin', 'pseudoct'), ...
    local_synthetic_launcher(root_dir, catalog_base));
local_chmod(fullfile(actual_package_root, 'bin', 'pseudoct'));
local_bundled_python(actual_package_root);
local_write(fullfile(actual_package_root, 'manifest.json'), { ...
    '{'; ...
    '  "catalog": {'; ...
    '    "schema": 1,'; ...
    '    "default": "R2014b",'; ...
    '    "releases": [{'; ...
    '      "label": "R2014b",'; ...
    '      "matlab_version": "99.99.0",'; ...
    '      "mcr_version": "8.4",'; ...
    '      "architecture": "glnxa64",'; ...
    '      "runtime_identity": {'; ...
    '        "mcr_version_file": "toolbox/compiler/mcrversion.ver",'; ...
    '        "library": "libmwmclmcrrt.so.8.4"'; ...
    '      }'; ...
    '    }]'; ...
    '  }'; ...
    '}'});
actual_artifacts = {'pseudoct_pipeline'; ...
    'run_pseudoct_pipeline.sh'; 'pseudoct_job_manager'};
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
% Environment decoys: a valid root in these variables must never be consulted.
setenv('PSEUDOCT_MCR_ROOT_R2014b', actual_mcr_root);
setenv('PSEUDOCT_MCR_ROOT', actual_mcr_root);
decoy_refused = false;
try
    pseudo_CT_runtime_select(local_runtime_config(), 'R2014b');
catch ME
    decoy_refused = strcmp(ME.identifier, 'pseudo_CT:RuntimeSelection');
end
assert(decoy_refused, ...
    'Environment variables must not select a MATLAB Runtime root.');
setenv('PSEUDOCT_MCR_ROOT_R2014b', '');
setenv('PSEUDOCT_MCR_ROOT', '');
setenv('PSEUDOCT_RUNTIME_RELEASE', 'R2014b');
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', actual_mcr_root);
actual_selected = pseudo_CT_runtime_select(local_runtime_config(), 'R2014b');
assert(strcmp(actual_selected.current.mcr_root, actual_mcr_root), ...
    'The --mcr-root value with an apostrophe was not decoded exactly.');
assert(strcmp(actual_selected.current.runner, fullfile(actual_package_root, ...
    'runtimes', 'R2014b', 'run_pseudoct_pipeline.sh')), ...
    'The resolver runner with an apostrophe was not decoded exactly.');

% Synthetic installed package and fake resolver. The package intentionally has no
% src/ directory, so the shared layout helper must select installed mode.
package_root = fullfile(work, 'installed-package');
mkdir(fullfile(package_root, 'bin'));
mkdir(fullfile(package_root, 'runtimes', 'R2014b'));
mkdir(fullfile(package_root, 'resources'));
local_write(fullfile(package_root, 'manifest.json'), {'synthetic manifest'});
runner = fullfile(package_root, 'runtimes', 'R2014b', 'run_pseudoct_pipeline.sh');
local_write(runner, {'#!/bin/sh'; 'exit 0'});
local_chmod(runner);
mcr_root = fullfile(work, 'mcr-explicit');
global_root = fullfile(work, 'mcr-global');
bad_root = fullfile(work, 'mcr-bad');
mkdir(mcr_root);
mkdir(global_root);
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
no_root_refused = false;
try
    pseudo_CT_runtime_select(config, 'R2014b');
catch ME
    no_root_refused = strcmp(ME.identifier, 'pseudo_CT:RuntimeSelection');
end
assert(no_root_refused, ...
    'Without --mcr-root the resolver has no root; environment roots are not used.');
% The launcher-bound root is inherited for the selected release.
setenv('PSEUDOCT_RUNTIME_RELEASE', 'R2014b');
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', mcr_root);
selected = pseudo_CT_runtime_select(config, 'R2014b');
assert(strcmp(selected.current.release, 'R2014b'));
assert(strcmp(selected.current.runner, runner));
assert(strcmp(selected.current.mcr_root, mcr_root));
% Installed direct mode carries no build or resource manifest paths.
assert(isempty(selected.current.build_manifest));
assert(isempty(selected.current.resource_manifest));
assert(strcmp(getenv('PSEUDOCT_RUNTIME_RELEASE'), 'R2014b'));
assert(strcmp(getenv('PSEUDOCT_RUNTIME_MCR_ROOT'), mcr_root));
paths = pseudo_CT_dependency_paths();
assert(strcmp(paths.install_root, package_root));
assert(strcmp(paths.atlas_root, fullfile(package_root, 'resources')));
assert(strcmp(mlsc_current_validate('pinned_mcr_root'), mcr_root));

% A launching R2014b root is propagated as an explicit resolver argument.
explicit_root = fullfile(work, 'mcr-launched-explicit');
mkdir(explicit_root);
setenv('PSEUDOCT_RUNTIME_RELEASE', 'R2014b');
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', explicit_root);
selected = pseudo_CT_runtime_select(config, 'R2014b');
assert(strcmp(selected.current.mcr_root, explicit_root));
resolver_text = local_read(resolver_log);
assert(~isempty(strfind(resolver_text, ...
    ['resolve --mcr R2014b --mcr-root ' explicit_root])), ...
    'The inherited runtime root was not propagated to resolve.');

% Resolver failure for the inherited root must be terminal; the caller-visible
% config remains unchanged.
setenv('PSEUDOCT_RUNTIME_RELEASE', 'R2014b');
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', bad_root);
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

% Catalog discovery for every release (A-002): an installed package carries the real
% catalog text and each release's executables. The root is <base>/<D>, identity-validated.
all_root = fullfile(work, 'installed-all');
mkdir(fullfile(all_root, 'bin'));
local_write(fullfile(all_root, 'bin', 'pseudoct'), ...
    local_synthetic_launcher(root_dir, catalog_base));
local_chmod(fullfile(all_root, 'bin', 'pseudoct'));
local_bundled_python(all_root);
catalog_text = local_read(fullfile(root_dir, 'config', 'releases.json'));
local_write(fullfile(all_root, 'manifest.json'), ...
    {['{"catalog": ' strtrim(catalog_text) '}']});
all_labels = {'R2010b', 'R2019a', 'R2019b', 'R2022a', 'R2022b', 'R2026a'};
all_dirs = {'7.11', '9.6', '9.7', '9.12', '9.13', '26.1'};
all_mcr = {'7.14', '9.6', '9.7', '9.12', '9.13', '26.1'};
for ii = 1:length(all_labels)
    release_dir = fullfile(all_root, 'runtimes', all_labels{ii});
    mkdir(release_dir);
    artifacts = {'pseudoct_pipeline'; 'run_pseudoct_pipeline.sh'; 'pseudoct_job_manager'};
    for jj = 1:length(artifacts)
        artifact = fullfile(release_dir, artifacts{jj});
        local_write(artifact, {'#!/bin/sh'; 'exit 0'});
        local_chmod(artifact);
    end
    candidate = fullfile(catalog_base, all_dirs{ii});
    mkdir(fullfile(candidate, 'runtime', 'glnxa64'));
    mkdir(fullfile(candidate, 'toolbox', 'compiler'));
    local_write(fullfile(candidate, 'runtime', 'glnxa64', ...
        ['libmwmclmcrrt.so.' all_mcr{ii}]), {'synthetic runtime library'});
    local_write(fullfile(candidate, 'toolbox', 'compiler', 'mcrversion.ver'), ...
        {all_mcr{ii}});
end
setenv('PSEUDOCT_INSTALL_ROOT', all_root);
fprintf('MCR discovery (release, D, result):\n');
for ii = 1:length(all_labels)
    setenv('PSEUDOCT_RUNTIME_RELEASE', '');
    setenv('PSEUDOCT_RUNTIME_MCR_ROOT', '');
    candidate = fullfile(catalog_base, all_dirs{ii});
    selected = pseudo_CT_runtime_select(local_runtime_config(), all_labels{ii});
    assert(strcmp(selected.current.release, all_labels{ii}));
    assert(strcmp(selected.current.mcr_root, local_realpath(candidate)), ...
        ['Release ' all_labels{ii} ' did not resolve from ' all_dirs{ii} '.']);
    fprintf('  %s  D=%s  resolved from %s\n', all_labels{ii}, all_dirs{ii}, ...
        selected.current.mcr_root);
end
% Absent candidate: the 26.1 catalog directory is removed, so resolution must fail.
rmdir(fullfile(catalog_base, '26.1'), 's');
setenv('PSEUDOCT_RUNTIME_RELEASE', '');
setenv('PSEUDOCT_RUNTIME_MCR_ROOT', '');
absent_refused = false;
try
    pseudo_CT_runtime_select(local_runtime_config(), 'R2026a');
catch ME
    absent_refused = strcmp(ME.identifier, 'pseudo_CT:RuntimeSelection');
end
assert(absent_refused, 'An absent catalog candidate must fail closed.');
fprintf('  R2026a  D=26.1  absent candidate: refused (pseudo_CT:RuntimeSelection)\n');
% Identity mismatch: 9.13 reports 9.12 in mcrversion.ver, so resolution must fail.
local_write(fullfile(catalog_base, '9.13', 'toolbox', 'compiler', 'mcrversion.ver'), ...
    {'9.12'});
mismatch_refused = false;
try
    pseudo_CT_runtime_select(local_runtime_config(), 'R2022b');
catch ME
    mismatch_refused = strcmp(ME.identifier, 'pseudo_CT:RuntimeSelection');
end
assert(mismatch_refused, 'A mismatched catalog identity must fail closed.');
fprintf('  R2022b  D=9.13  identity mismatch (mcrversion.ver 9.12): refused\n');

fprintf('Source refusal, installed Runtime layout, root propagation and catalog MCR discovery checks passed.\n');
end

function config = local_runtime_config()
config = struct('mode', 'mlsc', 'current', struct( ...
    'runner', 'before-runner', 'mcr_root', 'before-mcr', ...
    'release', 'before-release', 'build_manifest', 'before-build', ...
    'resource_manifest', 'before-resource'));
end

function lines = local_resolver_script()
% Fake launcher: the root comes only from --mcr-root, as in the real launcher.
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
    'if [ -z "$root" ]; then exit 69; fi'; ...
    'if [ "$root" = "${PSEUDOCT_TEST_BAD_ROOT-}" ]; then exit 69; fi'; ...
    'package=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd -P)'; ...
    'printf "PSEUDOCT_RUNNER=\047%s\047\\n" "$package/runtimes/$label/run_pseudoct_pipeline.sh"'; ...
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

function local_bundled_python(package_root)
%LOCAL_BUNDLED_PYTHON Stand-in for the installed package's private python/bin/python3,
%   required by the real launcher: a wrapper around the development interpreter
%   (PSEUDOCT_PYTHON, else python3), resolved once here, as in test_standalone_release.py.
%   The real bundled runtime is checked by the release driver's --verify.
host = strtrim(getenv('PSEUDOCT_PYTHON'));
if isempty(host)
    [status, host] = system('command -v python3');
    assert(status == 0, 'A development python3 is needed for the synthetic bundled runtime.');
    host = strtrim(host);
end
mkdir(fullfile(package_root, 'python', 'bin'));
interpreter = fullfile(package_root, 'python', 'bin', 'python3');
local_write(interpreter, {'#!/bin/sh'; ['exec ' local_shell_quote(host) ' "$@"']});
local_chmod(interpreter);
end

function local_chmod(path_text)
[status, ~] = system(['chmod 755 ' local_shell_quote(path_text)]);
assert(status == 0, 'Cannot make synthetic resolver executable.');
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

function lines = local_synthetic_launcher(root_dir, catalog_base)
%LOCAL_SYNTHETIC_LAUNCHER Real bin/pseudoct lines with only its fixed catalog base replaced.
base_line = 'catalog_mcr_base=/usr/pubsw/common/matlab';
lines = {};
found = 0;
fid = fopen(fullfile(root_dir, 'bin', 'pseudoct'), 'r');
if fid == -1
    error('test_runtime_selection:Read', 'Cannot read the real launcher.');
end
cleanup_fid = onCleanup(@() fclose(fid)); %#ok<NASGU>
line = fgetl(fid);
while ischar(line)
    if strcmp(line, base_line)
        found = found + 1;
        line = ['catalog_mcr_base=' local_shell_quote(catalog_base)];
    end
    lines{end + 1} = line; %#ok<AGROW>
    line = fgetl(fid);
end
assert(found == 1, 'bin/pseudoct must define its catalog base exactly once.');
end

function path_text = local_realpath(dir_path)
%LOCAL_REALPATH Physical path of an existing directory, as the launcher reports it.
[status, text] = system(['cd ' local_shell_quote(dir_path) ' && pwd -P']);
assert(status == 0, 'Cannot resolve a synthetic runtime root.');
path_text = strtrim(text);
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
