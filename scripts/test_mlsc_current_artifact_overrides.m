function test_mlsc_current_artifact_overrides()
%TEST_MLSC_CURRENT_ARTIFACT_OVERRIDES T009 Option A override checks (A-H).
%   Focused offline verification for the explicit public run_pseudo_CT
%   name-value overrides (interpreted orchestration/config only):
%     (A) no override -> canonical /usr/pubsw default unchanged
%     (B) artifact root deterministically derives the 3 T007 layout paths
%     (C) explicit Gate-A record is used (separate directory supported)
%     (D) wrong/incomplete inputs fail closed (helper shape + validators)
%     (E) exact Gate-B candidate PASSES validate_contract + validate_for_execution
%         (+ non-submitting preflight); hashes unchanged
%     (F) wrong root / foreign record FAIL closed
%     (G) local-current / local-legacy / mlsc-legacy unaffected (reject overrides)
%     (H) summary displays the resolved artifact root and Gate-A record
%
%   No live SSH/Ganymed/Slurm/subject run, no Gate-B submission, no
%   /usr/pubsw mutation, no rebuild, no Gate-A rewrite. R2010b only.

root_dir = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root_dir, 'src', 'config'), '-begin');
addpath(fullfile(root_dir, 'src', 'mlsc'), '-begin');
addpath(fullfile(root_dir, 'src', 'io'), '-begin');
config_root = fullfile(root_dir, 'src', 'config');

pinned = '/usr/pubsw/common/matlab/26.1';
default_dir = '/usr/pubsw/packages/mrpet/standalone_apps/pseudoCT_mlsc_current';
artifact_root_exact = fullfile(root_dir, 'dist', ...
    'mlsc_current_build_20261009_contentbound');
gate_a_exact = fullfile(root_dir, 'dist', ...
    'gate_a_20261009_contentbound', 'mlsc_current_gate_a.mat');
assert(exist(artifact_root_exact, 'dir') == 7, 'Exact artifact root missing.');
assert(exist(gate_a_exact, 'file') == 2, 'Exact Gate-A record missing.');

mlsc_current = pseudo_CT_load_profile('mlsc-current', config_root);

% (A) No override leaves the canonical default untouched.
cfg_a = pseudo_CT_apply_mlsc_current_overrides(mlsc_current, ...
    'mlsc-current', '', '');
assert(isequal(cfg_a, mlsc_current), 'Default config changed without override.');
assert(strcmp(mlsc_current.current.runner, ...
    [default_dir '/run_mlsc_current_payload.sh']), 'Default runner drifted.');
assert(strcmp(mlsc_current.current.build_manifest, ...
    [default_dir '/mlsc_current_build.mat']), 'Default build drifted.');
assert(strcmp(mlsc_current.current.resource_manifest, ...
    [default_dir '/mlsc_current_resources.mat']), 'Default resources drifted.');
assert(strcmp(mlsc_current.current.mcr_root, pinned), 'Default MCR drifted.');
assert(strcmp(mlsc_current_validate('pinned_mcr_root'), pinned));

% (B) Artifact root derives exactly the 3 T007 layout paths.
cfg_b = pseudo_CT_apply_mlsc_current_overrides(mlsc_current, ...
    'mlsc-current', artifact_root_exact, '');
expected_runner = fullfile(artifact_root_exact, 'payload_build', ...
    'run_mlsc_current_payload.sh');
expected_build = fullfile(artifact_root_exact, 'mlsc_current_build.mat');
expected_resources = fullfile(artifact_root_exact, ...
    'mlsc_current_resources.mat');
expected_gate_default = fullfile(artifact_root_exact, ...
    'mlsc_current_gate_a.mat');
assert(strcmp(cfg_b.current.runner, expected_runner), 'Runner derivation changed.');
assert(strcmp(cfg_b.current.build_manifest, expected_build), 'Build derivation changed.');
assert(strcmp(cfg_b.current.resource_manifest, expected_resources), 'Resource derivation changed.');
assert(strcmp(cfg_b.current.gate_a_record, expected_gate_default), ...
    'Gate-A default derivation changed.');
assert(strcmp(cfg_b.current.mcr_root, pinned), 'MCR_ROOT was overridden.');
assert(exist(expected_runner, 'file') == 2, 'Derived runner missing.');
assert(exist(expected_build, 'file') == 2, 'Derived build missing.');
assert(exist(expected_resources, 'file') == 2, 'Derived resources missing.');

% (C) Explicit Gate-A record in a separate directory is honored.
cfg_c = pseudo_CT_apply_mlsc_current_overrides(mlsc_current, ...
    'mlsc-current', artifact_root_exact, gate_a_exact);
assert(strcmp(cfg_c.current.runner, expected_runner), 'Explicit record changed runner.');
assert(strcmp(cfg_c.current.build_manifest, expected_build), 'Explicit record changed build.');
assert(strcmp(cfg_c.current.resource_manifest, expected_resources), 'Explicit record changed resources.');
assert(strcmp(cfg_c.current.gate_a_record, gate_a_exact), 'Explicit record not used.');
assert(strcmp(cfg_c.current.mcr_root, pinned), 'MCR_ROOT was overridden.');
% Trailing separator is equivalent (same deterministic derivation).
cfg_trail = pseudo_CT_apply_mlsc_current_overrides(mlsc_current, ...
    'mlsc-current', [artifact_root_exact '/'], gate_a_exact);
assert(strcmp(cfg_trail.current.runner, expected_runner), 'Trailing-sep derivation changed.');

% (D) Wrong/incomplete inputs fail closed (never silent fallback).
local_assert_override_id(mlsc_current, 'mlsc-current', 'relative/path', '', ...
    'run_pseudo_CT:InvalidMlscCurrentOverride');
local_assert_override_id(mlsc_current, 'mlsc-current', 'relative/path', gate_a_exact, ...
    'run_pseudo_CT:InvalidMlscCurrentOverride');
local_assert_override_id(mlsc_current, 'mlsc-current', artifact_root_exact, 'relative.mat', ...
    'run_pseudo_CT:InvalidMlscCurrentOverride');
local_assert_override_id(mlsc_current, 'mlsc-current', artifact_root_exact, '/tmp/not-a-mat.txt', ...
    'run_pseudo_CT:InvalidMlscCurrentOverride');
% Incomplete artifact (absolute dir without the 3 files) passes shape but
% must fail closed at validation, before any science.
incomplete_root = tempname;
mkdir(incomplete_root);
incomplete_cleanup = onCleanup(@() local_cleanup(incomplete_root)); %#ok<NASGU>
cfg_d = pseudo_CT_apply_mlsc_current_overrides(mlsc_current, ...
    'mlsc-current', incomplete_root, '');
local_assert_error(@() mlsc_current_validate('validate_contract', cfg_d));
local_assert_error(@() mlsc_current_validate('validate_for_execution', cfg_d));

% (E) Exact Gate-B candidate PASSES both validators + non-submitting preflight.
% Do NOT move/copy/modify the candidate or the Gate-A record.
assert(strcmp(cfg_c.current.runner, ...
    '/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/piano_mMR_devel/pseudoCT_standalone/dist/mlsc_current_build_20261009_contentbound/payload_build/run_mlsc_current_payload.sh') || ...
    ~isempty(strfind(cfg_c.current.runner, 'mlsc_current_build_20261009_contentbound')), ...
    'Exact runner binding changed.');
mlsc_current_validate('validate_contract', cfg_c);
mlsc_current_validate('validate_for_execution', cfg_c);
fixture_root = tempname;
mkdir(fixture_root);
fixture_cleanup = onCleanup(@() local_cleanup(fixture_root)); %#ok<NASGU>
fixture_input = fullfile(fixture_root, 'mprage.nii');
local_write(fixture_input, 'fixture');
fixture_subject = struct('subject_id', 't009-fixture', ...
    'shared_input', fixture_input, 'shared_temp', fixture_root);
fixture_runtime = struct('account', 'fixture-account', ...
    'script_path', fullfile(fixture_root, 'job.sh'));
preflight_report = mlsc_preflight(fixture_subject, cfg_c, fixture_runtime);
assert(isstruct(preflight_report) && preflight_report.ok, 'Exact preflight did not pass.');

% (F) Wrong root / foreign record FAIL closed.
wrong_root = fullfile(root_dir, 'dist', 'mlsc_current_build_20261009_nonexistent');
cfg_f1 = pseudo_CT_apply_mlsc_current_overrides(mlsc_current, ...
    'mlsc-current', wrong_root, gate_a_exact);
local_assert_error(@() mlsc_current_validate('validate_contract', cfg_f1));
local_assert_error(@() mlsc_current_validate('validate_for_execution', cfg_f1));
% Foreign record: a real .mat that is not the bound Gate-A record.
foreign_record = fullfile(root_dir, 'dist', 'gate_a_20261009_contentbound', ...
    'mut_resource_tampered.mat');
assert(exist(foreign_record, 'file') == 2, 'Foreign fixture missing.');
cfg_f2 = pseudo_CT_apply_mlsc_current_overrides(mlsc_current, ...
    'mlsc-current', artifact_root_exact, foreign_record);
local_assert_error(@() mlsc_current_validate('validate_for_execution', cfg_f2));
% Missing record path fails closed.
cfg_f3 = pseudo_CT_apply_mlsc_current_overrides(mlsc_current, ...
    'mlsc-current', artifact_root_exact, ...
    fullfile(artifact_root_exact, 'mlsc_current_gate_a.mat'));
local_assert_error(@() mlsc_current_validate('validate_for_execution', cfg_f3));
% Mismatched root with the exact record (paths bound, not just content).
copy_root = tempname;
mkdir(copy_root);
copy_cleanup = onCleanup(@() local_cleanup(copy_root)); %#ok<NASGU>
copyfile(expected_build, fullfile(copy_root, 'mlsc_current_build.mat'));
copyfile(expected_resources, fullfile(copy_root, 'mlsc_current_resources.mat'));
mkdir(fullfile(copy_root, 'payload_build'));
copyfile(expected_runner, fullfile(copy_root, 'payload_build', ...
    'run_mlsc_current_payload.sh'));
cfg_f4 = pseudo_CT_apply_mlsc_current_overrides(mlsc_current, ...
    'mlsc-current', copy_root, gate_a_exact);
local_assert_error(@() mlsc_current_validate('validate_for_execution', cfg_f4));

% (G) Other profiles are unaffected: overrides are rejected clearly.
other_names = {'local-current'; 'local-legacy'; 'mlsc-legacy'};
for ii = 1:length(other_names)
    other_cfg = pseudo_CT_load_profile(other_names{ii}, config_root);
    unchanged = pseudo_CT_apply_mlsc_current_overrides(other_cfg, ...
        other_names{ii}, '', '');
    assert(isequal(unchanged, other_cfg), 'Unaffected profile changed.');
    local_assert_override_id(other_cfg, other_names{ii}, ...
        artifact_root_exact, gate_a_exact, ...
        'run_pseudo_CT:InvalidMlscCurrentOverride');
    local_assert_override_id(other_cfg, other_names{ii}, ...
        artifact_root_exact, '', ...
        'run_pseudo_CT:InvalidMlscCurrentOverride');
end

% (H) Summary displays the resolved artifact root and Gate-A record.
summary_root = tempname;
mkdir(summary_root);
summary_cleanup = onCleanup(@() local_cleanup(summary_root)); %#ok<NASGU>
summary_dir = fullfile(summary_root, 'exact');
mkdir(summary_dir);
pseudo_CT_print_profile_summary('mlsc-current', cfg_c, ...
    summary_dir, struct('scope', 'run'));
exact_summary = local_read(fullfile(summary_dir, ...
    'pseudo_CT_profile_summary.txt'));
assert(~isempty(strfind(exact_summary, 'Artifact root:')), 'Summary hides artifact root.');
assert(~isempty(strfind(exact_summary, artifact_root_exact)), 'Summary hides exact root.');
assert(~isempty(strfind(exact_summary, 'Gate-A record:')), 'Summary hides Gate-A record.');
assert(~isempty(strfind(exact_summary, gate_a_exact)), 'Summary hides exact record.');
default_dir_path = fullfile(summary_root, 'default');
mkdir(default_dir_path);
pseudo_CT_print_profile_summary('mlsc-current', mlsc_current, ...
    default_dir_path, struct('scope', 'run'));
default_summary = local_read(fullfile(default_dir_path, ...
    'pseudo_CT_profile_summary.txt'));
assert(~isempty(strfind(default_summary, default_dir)), 'Default summary drifted.');
assert(~isempty(strfind(default_summary, pinned)), 'Summary hides pinned MCR.');

% Public surface: exactly the two supported overrides, no independent
% runner/build/resource/MCR overrides, no catalog/resolver.
entry_source = local_read(fullfile(root_dir, 'run_pseudo_CT.m'));
assert(~isempty(strfind(entry_source, 'mlsc_current_artifact_root')), 'Override A missing.');
assert(~isempty(strfind(entry_source, 'mlsc_current_gate_a_record')), 'Override B missing.');
assert(isempty(strfind(entry_source, 'mlsc_current_runner')), 'Independent runner override leaked.');
assert(isempty(strfind(entry_source, 'mlsc_current_build_manifest')), 'Independent build override leaked.');
assert(isempty(strfind(entry_source, 'mlsc_current_resource_manifest')), 'Independent resource override leaked.');
assert(isempty(strfind(entry_source, 'mlsc_current_mcr_root')), 'MCR override leaked.');
helper_source = local_read(fullfile(root_dir, 'src', 'config', ...
    'pseudo_CT_apply_mlsc_current_overrides.m'));
assert(isempty(strfind(helper_source, 'mlsc_resolve')), 'Resolver leaked into override.');
assert(isempty(strfind(helper_source, 'catalog_root')), 'Catalog leaked into override.');

fprintf(['MLSC current artifact override tests passed: (A) default intact, ', ...
    '(B) root derives 3 paths, (C) explicit record, (D) incomplete fails, ', ...
    '(E) exact candidate PASS both validators + preflight, (F) wrong/foreign FAIL, ', ...
    '(G) other profiles rejected, (H) summary shows root/record.\n']);
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

function local_assert_override_id(config, profile_name, root_value, record_value, expected_id)
failed = false;
actual_id = '';
try
    pseudo_CT_apply_mlsc_current_overrides(config, profile_name, ...
        root_value, record_value);
catch ME
    failed = true;
    actual_id = ME.identifier;
end
assert(failed, 'Incompatible override was not rejected.');
assert(strcmp(actual_id, expected_id), 'Unexpected override failure: %s', actual_id);
end

function local_write(path_name, text)
fid = fopen(path_name, 'w');
assert(fid ~= -1, 'Fixture could not be created.');
fwrite(fid, text);
fclose(fid);
end

function text = local_read(path_name)
fid = fopen(path_name, 'r');
assert(fid ~= -1, 'Could not read summary.');
text = fread(fid, inf, '*char')';
fclose(fid);
end

function local_cleanup(directory)
if exist(directory, 'dir') == 7
    rmdir(directory, 's');
end
end
