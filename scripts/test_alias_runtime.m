function test_alias_runtime()
%TEST_ALIAS_RUNTIME RED-first checks for the fixed entrypoint bindings.
%   This focused test does not open a GUI, start SPM, touch a subject tree,
%   or contact SSH/PBS. It verifies the public invocation contract and the
%   source-level ordering that keeps profile/resource failures pre-mutation.
%
%   Minimum supported MATLAB: R2010b.

scripts_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(scripts_dir);
addpath(fullfile(root_dir, 'src', 'config'));

local_source = fileread(fullfile(root_dir, 'run_pseudo_CT_local.m'));
launchpad_source = fileread(fullfile(root_dir, 'run_pseudo_CT_launchpad.m'));
core_source = fileread(fullfile(root_dir, 'src', 'core', 'atlas_based_attenuation_map.m'));

test_passed = 0;
test_failed = 0;

%% Fixed internal bindings and no public selector.
run_test('local binds local-current', ...
    ~isempty(strfind(local_source, 'pseudo_CT_resolve_profile(''local-current''')));
run_test('launchpad binds launchpad', ...
    ~isempty(strfind(launchpad_source, 'pseudo_CT_resolve_profile(''launchpad''')));
run_test('local does not expose near-parity', ...
    isempty(strfind(local_source, 'local-near-parity-r2010b')));
run_test('launchpad does not expose near-parity', ...
    isempty(strfind(launchpad_source, 'local-near-parity-r2010b')));
run_test('local has no selector UI', ...
    isempty(strfind(lower(local_source), 'dropdown')) && ...
    isempty(strfind(lower(local_source), 'profile selector')));
run_test('launchpad has no selector UI', ...
    isempty(strfind(lower(launchpad_source), 'dropdown')) && ...
    isempty(strfind(lower(launchpad_source), 'profile selector')));

%% Compatibility forms remain represented by the existing collectors.
run_test('local keeps batch/cell/char/file forms', ...
    has_invocation_forms(local_source));
run_test('launchpad keeps batch/cell/char/file forms', ...
    has_invocation_forms(launchpad_source));
run_test('local no-arg collector guards varargin', ...
    has_empty_varargin_guard(local_source));
run_test('launchpad no-arg collector guards varargin', ...
    has_empty_varargin_guard(launchpad_source));
run_test('local one-argument batch does not read varargin{2}', ...
    has_single_public_arg_guard(local_source, 'local_collect_jobs', '''batch'''));
run_test('local one-argument cell list does not read varargin{2}', ...
    has_single_public_arg_guard(local_source, 'local_collect_jobs', 'iscell'));
run_test('local one-argument char matrix does not read varargin{2}', ...
    has_single_public_arg_guard(local_source, 'local_collect_jobs', 'size(varargin{1}, 1) > 1'));
run_test('local one-argument file does not read varargin{2}', ...
    has_single_public_arg_guard(local_source, 'local_collect_jobs', 'exist(strtrim(varargin{1}), ''file'') == 2'));
run_test('launchpad one-argument batch does not read varargin{2}', ...
    has_single_public_arg_guard(launchpad_source, 'launchpad_collect_jobs', '''batch'''));
run_test('launchpad one-argument cell list does not read varargin{2}', ...
    has_single_public_arg_guard(launchpad_source, 'launchpad_collect_jobs', 'iscell'));
run_test('launchpad one-argument char matrix does not read varargin{2}', ...
    has_single_public_arg_guard(launchpad_source, 'launchpad_collect_jobs', 'size(varargin{1}, 1) > 1'));
run_test('launchpad one-argument file does not read varargin{2}', ...
    has_single_public_arg_guard(launchpad_source, 'launchpad_collect_jobs', 'exist(strtrim(varargin{1}), ''file'') == 2'));
run_test('core preserves legacy five-argument defaults mapping', ...
    has_legacy_five_arg_core_mapping(core_source));
run_test('deployed MAT behavior remains', ...
    ~isempty(strfind(launchpad_source, 'if isdeployed')) && ...
    ~isempty(strfind(launchpad_source, 'load(varargin{1})')));
run_test('local validates alias override', ...
    ~isempty(strfind(local_source, 'pseudo_CT_validate_aliasing')));
run_test('launchpad validates alias override', ...
    ~isempty(strfind(launchpad_source, 'pseudo_CT_validate_aliasing')));
run_test('local cleanup is manifest-owned', ...
    isempty(strfind(local_source, 'pseudo_CT_keep_temp_enabled')) && ...
    ~isempty(strfind(local_source, 'cleanup_owner(manifest)')));
run_test('launchpad cleanup is manifest-owned', ...
    isempty(strfind(launchpad_source, 'pseudo_CT_keep_temp_enabled')) && ...
    ~isempty(strfind(launchpad_source, 'cleanup_owner(manifest)')));

%% Strict alias values are accepted/rejected without pipeline execution.
manifest = struct('aliasing_override', [0 1]);
run_test('numeric zero accepted', pseudo_CT_validate_aliasing(0, manifest) == 0);
run_test('numeric one accepted', pseudo_CT_validate_aliasing(1, manifest) == 1);
run_test('logical false accepted', pseudo_CT_validate_aliasing(false, manifest) == 0);
run_test('logical true accepted', pseudo_CT_validate_aliasing(true, manifest) == 1);
run_error_test('numeric two rejected', 'ALIAS:InvalidOverride', ...
    @() pseudo_CT_validate_aliasing(2, manifest));
run_error_test('vector rejected', 'ALIAS:InvalidOverride', ...
    @() pseudo_CT_validate_aliasing([0 1], manifest));
run_error_test('text rejected', 'ALIAS:InvalidOverride', ...
    @() pseudo_CT_validate_aliasing('1', manifest));

%% Early resource failure is structurally before job collection/mutation.
run_test('local preflight precedes job collection', ...
    source_order(local_source, 'pseudo_CT_preflight', 'local_collect_jobs'));
run_test('launchpad preflight precedes job collection', ...
    source_order(launchpad_source, 'pseudo_CT_preflight', 'launchpad_collect_jobs'));
run_test('local preflight precedes setup', ...
    source_order(local_source, 'pseudo_CT_preflight', 'setup_pseudo_CT_paths'));
run_test('launchpad preflight precedes setup', ...
    source_order(launchpad_source, 'pseudo_CT_preflight', 'setup_pseudo_CT_paths'));
run_test('local setup receives bound manifest', ...
    ~isempty(strfind(local_source, 'setup_pseudo_CT_paths(pathp, manifest)')));
run_test('launchpad setup receives bound manifest', ...
    ~isempty(strfind(launchpad_source, 'setup_pseudo_CT_paths(pathp, manifest)')));
run_test('local passes explicit processing policy to core', ...
    ~isempty(strfind(local_source, 'atlas_based_attenuation_map(P, dir_batch_templates, ssh_log, job.correct_aliasing, defaults, manifest)')));
run_test('core consumes explicit recenter policy', ...
    ~isempty(strfind(core_source, 'processing_policy.recenter')));
run_test('core consumes explicit background policy', ...
    ~isempty(strfind(core_source, 'pseudo_CT_zero_background_enabled(processing_policy)')));
run_test('local warning state has exception cleanup', ...
    has_warning_cleanup(local_source));
run_test('launchpad warning state has exception cleanup', ...
    has_warning_cleanup(launchpad_source));

launchpad_manifest = pseudo_CT_profile_registry('launchpad', root_dir);
run_test('launchpad local support provenance is r6313', ...
    strcmp(launchpad_manifest.spm_version, 'r6313') && ...
    strcmp(launchpad_manifest.provenance.expected_spm_version, 'r6313'));
run_test('launchpad remote backend provenance is separate r4667', ...
    isfield(launchpad_manifest.launchpad_identity, 'backend_spm_version') && ...
    strcmp(launchpad_manifest.launchpad_identity.backend_spm_version, 'r4667'));
run_test('launchpad preflight accepts distinct local and remote identities', ...
    launchpad_preflight_accepts_distinct_identity(root_dir));

total = test_passed + test_failed;
fprintf('\n=== Alias/runtime tests: %d/%d passed ===\n', test_passed, total);
if test_failed > 0
    error('test_alias_runtime:Failures', '%d test(s) failed.', test_failed);
end

%% ------------------------------------------------------------------------
function ok = has_invocation_forms(source)
ok = ~isempty(strfind(source, '''batch''')) && ...
     ~isempty(strfind(source, 'iscell')) && ...
     ~isempty(strfind(source, 'size(varargin{1}, 1) > 1')) && ...
     ~isempty(strfind(source, 'exist(strtrim(varargin{1}), ''file'') == 2')) && ...
     ~isempty(strfind(source, 'load_mr_4_AC'));
end

%% ------------------------------------------------------------------------
function ok = has_empty_varargin_guard(source)
ok = ~isempty(strfind(source, 'if ~isdeployed && ~isempty(varargin)'));
end

%% ------------------------------------------------------------------------
function ok = has_single_public_arg_guard(source, collector_name, shape_token)
collector_start = strfind(source, ['function jobs = ' collector_name]);
builder_name = strrep(collector_name, '_collect_jobs', '_build_jobs_from_subject_list');
builder_start = strfind(source, ['function jobs = ' builder_name]);
if isempty(collector_start) || isempty(builder_start)
    ok = false;
    return;
end
collector_source = source(collector_start(1):builder_start(1)-1);
ok = ~isempty(strfind(collector_source, shape_token)) && ...
     ~isempty(strfind(collector_source, 'if numel(varargin) > 1')) && ...
     isempty(strfind(collector_source, 'if nargin > 1'));
end

%% ------------------------------------------------------------------------
function ok = has_legacy_five_arg_core_mapping(source)
legacy_start = strfind(source, 'elseif nargin < 6');
explicit_start = strfind(source, 'elseif nargin == 6');
if isempty(legacy_start) || isempty(explicit_start) || ...
        legacy_start(1) >= explicit_start(1)
    ok = false;
    return;
end
legacy_source = source(legacy_start(1):explicit_start(1)-1);
explicit_source = source(explicit_start(1):end);
ok = ~isempty(strfind(legacy_source, 'defaults = varargin{5}')) && ...
     isempty(strfind(legacy_source, 'varargin{6}')) && ...
     ~isempty(strfind(explicit_source, 'processing_policy = varargin{6}'));
end

%% ------------------------------------------------------------------------
function ok = has_warning_cleanup(source)
ok = ~isempty(strfind(source, 'warn_cleanup = onCleanup(@() warning(orig_warn))'));
end

%% ------------------------------------------------------------------------
function ok = launchpad_preflight_accepts_distinct_identity(root_dir)
manifest = pseudo_CT_profile_registry('launchpad', root_dir);
% This isolates provenance ordering from the optional, absent checkout atlas.
manifest.atlas_assets.batch_atlas_path = root_dir;
manifest.atlas_assets.required_files = {};
ok = true;
try
    pseudo_CT_preflight(manifest, root_dir);
catch
    ok = false;
end
end

%% ------------------------------------------------------------------------
function ok = source_order(source, first_token, second_token)
first_pos = strfind(source, first_token);
second_pos = strfind(source, second_token);
ok = ~isempty(first_pos) && ~isempty(second_pos) && first_pos(1) < second_pos(1);
end

%% ------------------------------------------------------------------------
function run_test(label, ok)
if ok
    test_passed = test_passed + 1;
    fprintf('  PASS  %s\n', label);
else
    test_failed = test_failed + 1;
    fprintf('  FAIL  %s\n', label);
end
end

%% ------------------------------------------------------------------------
function run_error_test(label, expected_id, thunk)
caught = false;
actual_id = '';
try
    thunk();
catch ME
    caught = true;
    actual_id = ME.identifier;
end
if caught && strcmp(actual_id, expected_id)
    test_passed = test_passed + 1;
    fprintf('  PASS  %s -> %s\n', label, expected_id);
elseif caught
    test_failed = test_failed + 1;
    fprintf('  FAIL  %s: expected %s, got %s\n', label, expected_id, actual_id);
else
    test_failed = test_failed + 1;
    fprintf('  FAIL  %s: expected %s, no error thrown\n', label, expected_id);
end
end

end
