function test_mlsc_current_profile()
%TEST_MLSC_CURRENT_PROFILE Focused T005 profile identity/config/selection checks (offline).
%   Proves the canonical 2x2 matrix wiring using fixtures only: no live
%   SSH/Slurm/sbatch, no artifact build, no real subject, no Gates.
%     1) local-current is local/current
%     2) local-legacy is local/legacy
%     3) mlsc-current is mlsc/current
%     4) mlsc-legacy is mlsc/legacy
%     5) mlsc alias resolves deterministically to mlsc-legacy (not mlsc-current)
%     6) mlsc-mprage-only stays legacy
%     7) local-mprage-only keeps its existing intent
%     8) default remains local-current
%     9) selector shows exactly five recommended rows + three specialized
%        (launchpad-legacy joins recommended, order 80)
%    10) deprecated profiles stay out of the primary selector
%    11) mlsc-current pins /usr/pubsw/common/matlab/26.1 (never .../current)
%    12) current-specific fields with no legacy leak (namespaces separate)
%    13) fail-closed pending Gate A (selectable, real execution blocked)
%    14) legacy invocation unchanged
%    15) no ambiguity (single coherent artifact layout, no catalog/resolver)
%
%   Minimum supported MATLAB: R2010b.

root_dir = fileparts(fileparts(mfilename('fullpath')));
old_path = path();
addpath(fullfile(root_dir, 'src', 'config'), '-begin');
addpath(fullfile(root_dir, 'src', 'ui'), '-begin');
addpath(fullfile(root_dir, 'src', 'io'), '-begin');
addpath(fullfile(root_dir, 'src', 'mlsc'), '-begin');
cleanup_path = onCleanup(@() path(old_path)); %#ok<NASGU>

config_root = fullfile(root_dir, 'src', 'config');
profile_dir = fullfile(config_root, 'profiles');
profiles = pseudo_CT_list_profiles(config_root);
names = {profiles.name};

% 10) Deprecated preserved under deprecated/, out of primary discovery.
deprecated_names = {'launchpad'; 'launchpad-mprage-only'; ...
    'local-near-parity-r2010b'};
for ii = 1:length(deprecated_names)
    assert(~ismember(deprecated_names{ii}, names), ...
        'Deprecated profile leaked into discovery.');
    assert(exist(fullfile(profile_dir, 'deprecated', ...
        [strrep(deprecated_names{ii}, '-', '_') '.m']), 'file') == 2, ...
        'Deprecated profile file missing.');
end
for ii = 1:length(profiles)
    assert(isempty(strfind(profiles(ii).file_path, 'deprecated')), ...
        'Discovery left the primary profile directory.');
end

% Canonical set is exactly eight (adds mlsc-current + launchpad-legacy).
expected_active = {'devel'; 'launchpad-legacy'; 'local-current'; 'local-legacy'; ...
    'local-mprage-only'; 'mlsc-current'; 'mlsc-legacy'; ...
    'mlsc-mprage-only'};
assert(length(profiles) == length(expected_active));
assert(isequal(sort(names(:)), sort(expected_active)));
assert(~ismember('mlsc', names));

local_current = pseudo_CT_load_profile('local-current', config_root);
local_legacy = pseudo_CT_load_profile('local-legacy', config_root);
mlsc_current = pseudo_CT_load_profile('mlsc-current', config_root);
mlsc_legacy = pseudo_CT_load_profile('mlsc-legacy', config_root);
mlsc_mprage = pseudo_CT_load_profile('mlsc-mprage-only', config_root);
local_mprage = pseudo_CT_load_profile('local-mprage-only', config_root);

% 1-4) 2x2 identity matrix.
assert(strcmp(local_current.mode, 'local'));
assert(strcmp(local_current.implementation, 'current'));
assert(strcmp(local_legacy.mode, 'local'));
assert(strcmp(local_legacy.implementation, 'legacy-v2'));
assert(strcmp(mlsc_current.mode, 'mlsc'));
assert(strcmp(mlsc_current.implementation, 'current'));
assert(strcmp(mlsc_legacy.mode, 'mlsc'));
assert(strcmp(mlsc_legacy.implementation, 'legacy-v2'));

% 5) mlsc -> mlsc-legacy deterministically, never mlsc-current.
aliased = pseudo_CT_load_profile('mlsc', config_root);
assert(isequal(aliased, mlsc_legacy));
assert(~isequal(aliased, mlsc_current));

% 6) mlsc-mprage-only stays legacy.
assert(strcmp(mlsc_mprage.mode, 'mlsc'));
assert(strcmp(mlsc_mprage.implementation, 'legacy-v2'));
assert(strcmp(mlsc_mprage.compatibility_profile, 'mlsc'));
assert(~isfield(mlsc_mprage, 'current'));

% 7) local-mprage-only keeps its existing intent.
assert(strcmp(local_mprage.mode, 'local'));
assert(strcmp(local_mprage.implementation, 'current'));
assert(strcmp(local_mprage.io_policy.reference, 'none'));
assert(strcmp(local_mprage.io_policy.output, 'nifti-only'));
assert(strcmp(local_mprage.io_policy.gui, 'mprage-only'));
assert(strcmp(local_mprage.compatibility_profile, 'local-current'));

% 8) Default stays local-current (never MLSC).
[ordered, default_index] = pseudo_CT_prepare_profile_choices(profiles);
assert(strcmp(ordered(default_index).name, 'local-current'));

% 9) Selector shows exactly five recommended rows (launchpad-legacy joins
% recommended last, order 80 unchanged); specialized shrinks 4 -> 3.
% Default stays local-current via explicit lookup (never first-recommended).
recommended = ordered(strcmp({ordered.group}, 'recommended'));
specialized = ordered(strcmp({ordered.group}, 'specialized'));
assert(length(recommended) == 5);
assert(length(specialized) == 3);
assert(isequal({recommended.name}, {'local-current'; 'mlsc-current'; ...
    'local-legacy'; 'mlsc-legacy'; 'launchpad-legacy'}'));
assert(isequal({specialized.name}, {'local-mprage-only'; ...
    'mlsc-mprage-only'; 'devel'}'));
assert(isequal({recommended.display_name}, {'LOCAL - Current'; ...
    'MLSC - Current'; 'LOCAL - Legacy v2.0 (Aether)'; ...
    'MLSC - Legacy v2.0 (Aether)'; 'LAUNCHPAD - Legacy v2.0 (Aether)'}'));
assert(isempty(strfind(mlsc_current.presentation.display_name, 'v3')));
assert(isempty(strfind(lower(mlsc_current.presentation.display_name), ...
    'pseudoct3')));

% 3-detail) mlsc-current science settings match local-current.
assert(mlsc_current.aliasing_default == 1);
assert(strcmp(mlsc_current.recenter_before_normalization, 'Yes'));
assert(strcmp(mlsc_current.zero_background, 'No'));
assert(mlsc_current.bone_enabled == true);
assert(mlsc_current.fwhm == 0);
assert(isequal(mlsc_current.pca_order, {'callable_pca'; 'repo_legacy'}));
assert(strcmp(mlsc_current.io_policy.reference, 'umap-required'));
assert(strcmp(mlsc_current.io_policy.output, 'nifti-and-dicom'));
assert(strcmp(mlsc_current.io_policy.gui, 'mMR'));

% 11) Pinned MCR_ROOT is version-specific 26.1, never the current symlink.
pinned = '/usr/pubsw/common/matlab/26.1';
assert(strcmp(mlsc_current.current.mcr_root, pinned));
assert(strcmp(mlsc_current_validate('pinned_mcr_root'), pinned));

% 12) Current-specific fields with no legacy leak; namespaces separate.
assert(isfield(mlsc_current, 'current'));
assert(isfield(mlsc_current, 'mlsc'));
assert(~isfield(mlsc_current, 'legacy'));
assert(~isfield(mlsc_current.mlsc, 'runner'));
assert(~isfield(mlsc_current.mlsc, 'mcr_root'));
assert(~isfield(mlsc_current.mlsc, 'defaults_mat'));
assert(~isfield(mlsc_current.mlsc, 'batch_templates'));
assert(~isfield(local_current, 'current'));
assert(~isfield(local_current, 'legacy'));
assert(~isfield(local_legacy, 'current'));
assert(isfield(local_legacy, 'legacy'));
assert(~isfield(mlsc_legacy, 'current'));
assert(isfield(mlsc_legacy, 'legacy'));

% Malformed mlsc-current fails clearly (isolated dirs, no silent fallback).
local_assert_malformed(config_root, 'mcr_root', ...
    '/usr/pubsw/common/matlab/current');
local_assert_malformed(config_root, 'legacy_field', '');
local_assert_malformed(config_root, 'legacy_block', '');
local_assert_malformed(config_root, 'empty_runner', '');

% Underscore spellings and display labels stay rejected.
for ii = 1:length(expected_active)
    underscored = strrep(expected_active{ii}, '-', '_');
    if strcmp(underscored, expected_active{ii})
        continue;
    end
    rejected = false;
    try
        pseudo_CT_load_profile(underscored, config_root);
    catch ME
        rejected = strcmp(ME.identifier, 'pseudo_CT:InvalidProfile');
    end
    assert(rejected, 'Underscore spelling was accepted.');
end
label_rejected = false;
try
    pseudo_CT_load_profile(mlsc_current.presentation.display_name, ...
        config_root);
catch ME
    label_rejected = strcmp(ME.identifier, 'pseudo_CT:InvalidProfile');
end
assert(label_rejected, 'Display label was accepted as identity.');

% 15) No ambiguity: installation-relative staged artifact layout (one
% coherent artifact directory, launcher nested under payload_build/), no
% catalog/resolver, no runtime pin, no second layout, no fabricated
% Gate-A evidence, no absolute deployment fallback.
[build_dir, ~, ~] = fileparts(mlsc_current.current.build_manifest);
[resource_dir, ~, ~] = fileparts(mlsc_current.current.resource_manifest);
assert(strcmp(build_dir, resource_dir));
expected_runner = fullfile(build_dir, 'payload_build', ...
    'run_mlsc_current_payload.sh');
assert(strcmp(mlsc_current.current.runner, expected_runner));
expected_gate = fullfile(build_dir, 'mlsc_current_gate_a.mat');
assert(strcmp(mlsc_current.current.gate_a_record, expected_gate));
% Defaults anchor at the installed version directory derived from the
% profile location (profiles dir, four levels up), never /usr/pubsw.
profiles_dir_here = fullfile(config_root, 'profiles');
version_dir_here = fileparts(fileparts(fileparts(fileparts(profiles_dir_here))));
assert(strcmp(build_dir, fullfile(version_dir_here, 'compiled')));
default_paths = {mlsc_current.current.runner; ...
    mlsc_current.current.build_manifest; ...
    mlsc_current.current.resource_manifest; ...
    mlsc_current.current.gate_a_record};
for ii = 1:length(default_paths)
    assert(isempty(strfind(default_paths{ii}, ...
        '/usr/pubsw/packages/mrpet/standalone_apps/pseudoCT_mlsc_current')), ...
        'Absolute deployment fallback leaked into defaults.');
end
assert(~isfield(mlsc_current.current, 'runtime_root'));
assert(~isfield(mlsc_current, 'catalog'));
assert(exist(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_resolve_current_runtime.m'), 'file') ~= 2);
profile_source = local_read(fullfile(profile_dir, 'mlsc_current.m'));
profile_code = local_code_only(profile_source);
assert(isempty(strfind(profile_code, 'catalog')));
assert(isempty(strfind(profile_code, 'mlsc_resolve')));
assert(isempty(strfind(profile_code, '7.11')));
assert(isempty(strfind(profile_code, 't007-gate-a-validated')));
assert(isempty(strfind(profile_code, '/common/matlab/current')));
assert(isempty(strfind(profile_code, 'config.legacy')));
assert(isempty(strfind(profile_code, 'runtime_root')));
current_lines = local_config_current_lines(profile_code);
assert(isempty(strfind(current_lines, 'latest')));
assert(isempty(strfind(current_lines, '/current')));

% 13) Fail-closed pending Gate A: selectable/configurable, execution blocked.
fixture_root = tempname;
mkdir(fixture_root);
fixture_cleanup = onCleanup(@() local_cleanup(fixture_root)); %#ok<NASGU>
fixture_input = fullfile(fixture_root, 'mprage.nii');
local_write(fixture_input, 'fixture');
subject = struct('subject_id', 't005-fixture', ...
    'shared_input', fixture_input, 'shared_temp', fixture_root);
runtime = struct('account', 'fixture-account', ...
    'script_path', fullfile(fixture_root, 'job.sh'));
local_assert_error_id(@() mlsc_preflight(subject, mlsc_current, runtime), ...
    'pseudo_CT:MLSCCurrentRunner');
local_assert_error(@() mlsc_current_validate('validate_contract', ...
    mlsc_current));
local_assert_error_id(@() mlsc_current_validate('validate_for_execution', ...
    mlsc_current), 'pseudo_CT:MLSCCurrentRunner');

% Setup accepts the scheduler-only current shape with fixtures, and
% rejects a fake legacy field without touching the artifact gate.
setup_fixture = local_setup_fixture(mlsc_current, fixture_root);
setup_pseudo_CT_paths(root_dir, setup_fixture);
setup_bad = setup_fixture;
setup_bad.mlsc.runner = fullfile(fixture_root, 'fake-runner.sh');
setup_failed = false;
try
    setup_pseudo_CT_paths(root_dir, setup_bad);
catch ME
    setup_failed = strcmp(ME.identifier, 'pseudo_CT:InvalidProfile');
end
assert(setup_failed, 'Fake legacy field survived setup.');

% Summary renders the current artifact block; legacy output has no such block.
summary_dir = fullfile(fixture_root, 'summary');
mkdir(summary_dir);
pseudo_CT_print_profile_summary('mlsc-current', mlsc_current, ...
    summary_dir, struct('scope', 'run'));
current_summary = local_read(fullfile(summary_dir, ...
    'pseudo_CT_profile_summary.txt'));
assert(~isempty(strfind(current_summary, 'Implementation:     current')));
assert(~isempty(strfind(current_summary, pinned)));
assert(~isempty(strfind(current_summary, 'pending Gate-A verification')));
assert(~isempty(strfind(current_summary, ...
    'fails preflight pending artifact')));
assert(~isempty(strfind(current_summary, build_dir)), ...
    'Summary hides resolved artifact root.');
legacy_dir = fullfile(fixture_root, 'legacy-summary');
mkdir(legacy_dir);
pseudo_CT_print_profile_summary('mlsc-legacy', mlsc_legacy, ...
    legacy_dir, struct('scope', 'run'));
legacy_summary = local_read(fullfile(legacy_dir, ...
    'pseudo_CT_profile_summary.txt'));
assert(isempty(strfind(legacy_summary, 'MLSC Current Artifact')));

% 14) Legacy invocation unchanged: fixture legacy preflight/generate keeps
% the normalize->payload order and positional runner/MCR/args contract.
legacy_check = local_legacy_invocation(root_dir);

fprintf(['MLSC current profile tests passed: 2x2 identity, mlsc alias, ', ...
    'default local-current, five recommended, deprecated excluded, pinned ', ...
    '26.1, current-only contract, fail-closed Gate A, legacy unchanged, ', ...
    'single layout. Legacy check: %s\n'], legacy_check);
end

function local_assert_malformed(config_root, kind, value)
% Write one mutated mlsc_current copy into an isolated profile directory
% and require a clear InvalidProfile failure (never silent fallback).
profile_dir = fullfile(config_root, 'profiles');
test_root = tempname;
mkdir(test_root);
mkdir(fullfile(test_root, 'profiles'));
cleanup = onCleanup(@() local_cleanup(test_root)); %#ok<NASGU>
source = local_read(fullfile(profile_dir, 'mlsc_current.m'));
source = strrep(source, 'function config = mlsc_current()', ...
    'function config = mlsc_current()');
if strcmp(kind, 'mcr_root')
    source = strrep(source, ...
        'config.current.mcr_root = ''/usr/pubsw/common/matlab/26.1'';', ...
        ['config.current.mcr_root = ''' value ''';']);
elseif strcmp(kind, 'legacy_field')
    source = strrep(source, ...
        'config.mlsc.host = ''mlsc.nmr.mgh.harvard.edu'';', ...
        ['config.mlsc.host = ''mlsc.nmr.mgh.harvard.edu'';' char(10) ...
         'config.mlsc.runner = ''/fixture/fake-runner.sh'';']);
elseif strcmp(kind, 'legacy_block')
    source = strrep(source, ...
        '% Installation-relative Gate-A artifact directory (staged layout).', ...
        ['config.legacy.runner = ''/fixture/fake-runner.sh'';' char(10) ...
         '% Installation-relative Gate-A artifact directory (staged layout).']);
elseif strcmp(kind, 'empty_runner')
    source = strrep(source, ...
        ['config.current.runner = fullfile(artifact_dir_here, ''payload_build'', ...' char(10) ...
         '    ''run_mlsc_current_payload.sh'');'], ...
        'config.current.runner = '''';');
end
local_write(fullfile(test_root, 'profiles', 'mlsc_current.m'), source);
failed = false;
try
    pseudo_CT_load_profile('mlsc-current', test_root);
catch ME
    failed = strcmp(ME.identifier, 'pseudo_CT:InvalidProfile');
end
assert(failed, 'Malformed mlsc-current was not rejected clearly.');
end

function config = local_setup_fixture(config, parent_dir)
% Fixture scheduler/resource roots so setup stays offline and local-only.
fixture = fullfile(parent_dir, 'setup-fixture');
mkdir(fixture);
config.spm_root = fullfile(fixture, 'spm');
mkdir(config.spm_root);
mkdir(fullfile(config.spm_root, 'matlabbatch'));
config.atlas_root = fullfile(fixture, 'atlas');
mkdir(config.atlas_root);
config.d2n_root = fullfile(fixture, 'd2n');
mkdir(config.d2n_root);
config.mlsc.shell = '/bin/bash';
config.mlsc.freesurfer_env = fullfile(fixture, 'freesurfer-env');
local_write(config.mlsc.freesurfer_env, '# fixture');
vers = {'spm_vol_nifti.m'; 'spm_preproc_write8.m'; 'spm_dicom_convert.m'};
for ii = 1:length(vers)
    repo_root = fileparts(fileparts(mfilename('fullpath')));
    assert(exist(fullfile(repo_root, 'vers', vers{ii}), 'file') == 2, ...
        'Repository vers override missing.');
end
end

function detail = local_legacy_invocation(root_dir)
% Fixture legacy MLSC preflight/generate: order and args must be unchanged.
test_root = tempname;
mkdir(test_root);
runner = fullfile(test_root, 'runner.sh');
defaults = fullfile(test_root, 'defaults.mat');
freesurfer_env = fullfile(test_root, 'freesurfer-env');
mcr = fullfile(test_root, 'mcr');
templates = fullfile(test_root, 'Batch_atlas');
mkdir(mcr);
mkdir(templates);
local_write(runner, '# fixture');
local_write(defaults, 'fixture');
local_write(freesurfer_env, '# fixture');
shared = fullfile(test_root, 'shared');
mkdir(shared);
input_path = fullfile(shared, 'mprage.nii');
local_write(input_path, 'fixture');
subject = struct('subject_id', 'legacy-fixture', ...
    'shared_input', input_path, 'shared_temp', shared);
config = struct();
config.mode = 'mlsc';
config.aliasing_default = 1;
config.mlsc = struct('host', 'mlsc.nmr.mgh.harvard.edu', ...
    'runner', runner, 'mcr_root', mcr, ...
    'defaults_mat', defaults, 'batch_templates', templates, ...
    'shell', '/bin/bash', 'freesurfer_env', freesurfer_env, ...
    'partition', 'basic', 'nodes', 1, 'ntasks', 1, ...
    'cpus_per_task', 1, 'memory', '1G', 'time', '00:01:00');
runtime = struct('account', 'fixture-account', ...
    'script_path', fullfile(shared, 'job.sh'));
assert(~mlsc_current_validate('is_current', config));
preflight = mlsc_preflight(subject, config, runtime);
assert(preflight.needs_normalization);
artifact = mlsc_generate_slurm_script(subject, config, runtime);
script = artifact.script_text;
assert(~isempty(strfind(script, 'mri_normalize')));
assert(isempty(strfind(script, 'mlsc_current_job.mat')));
norm_pos = strfind(script, 'mri_normalize');
pseudo_pos = strfind(script, 'mlsc_record_progress ''pseudoCT|start''');
assert(~isempty(norm_pos) && ~isempty(pseudo_pos) && ...
    norm_pos(1) < pseudo_pos(1));
runner_pos = strfind(script, runner);
mcr_pos = strfind(script, mcr);
batch_pos = strfind(script, templates);
defaults_pos = strfind(script, defaults);
assert(~isempty(runner_pos) && ~isempty(mcr_pos) && ...
    ~isempty(batch_pos) && ~isempty(defaults_pos));
assert(runner_pos(1) < mcr_pos(1) && mcr_pos(1) < batch_pos(1) && ...
    batch_pos(1) < defaults_pos(1));
detail = 'normalize->payload, positional runner/MCR/args intact';
if exist(shared, 'dir') == 7
    rmdir(test_root, 's');
end
end

function local_assert_error(thunk)
failed = false;
try
    thunk();
catch %#ok<CTCH>
    failed = true;
end
assert(failed, 'Fail-closed gate did not reject.');
end

function local_assert_error_id(thunk, expected_id)
failed = false;
actual_id = '';
try
    thunk();
catch ME
    failed = true;
    actual_id = ME.identifier;
end
assert(failed, 'Fail-closed gate did not reject.');
assert(strcmp(actual_id, expected_id), 'Unexpected failure: %s', actual_id);
end

function text = local_read(path_name)
fid = fopen(path_name, 'r');
assert(fid ~= -1, 'Could not read fixture source.');
text = fread(fid, inf, '*char')';
fclose(fid);
end

function code = local_code_only(source)
%LOCAL_CODE_ONLY Keep non-comment code lines (R2010b-safe).
code = '';
parts = regexp(source, char(10), 'split');
for ii = 1:length(parts)
    trimmed = strtrim(parts{ii});
    if isempty(trimmed) || trimmed(1) == '%'
        continue;
    end
    code = [code parts{ii} char(10)]; %#ok<AGROW>
end
end

function lines = local_config_current_lines(code)
%LOCAL_CONFIG_CURRENT_LINES Concatenated config.current code lines.
lines = '';
parts = regexp(code, char(10), 'split');
for ii = 1:length(parts)
    if ~isempty(strfind(parts{ii}, 'config.current'))
        lines = [lines parts{ii} char(10)]; %#ok<AGROW>
    end
end
end

function local_write(path_name, text)
fid = fopen(path_name, 'w');
assert(fid ~= -1, 'Fixture could not be created.');
fwrite(fid, text);
fclose(fid);
end

function local_cleanup(directory)
if exist(directory, 'dir') == 7
    rmdir(directory, 's');
end
end
