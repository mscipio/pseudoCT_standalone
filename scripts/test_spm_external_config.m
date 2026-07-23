function test_spm_external_config()
%TEST_SPM_EXTERNAL_CONFIG RED-first checks for deployment-owned SPM authority.
%   The test exercises the fixed canonical mapping and the injected config
%   directory seam without invoking SPM, a batch, a subject, or a network.
%
%   Minimum supported MATLAB: R2010b.

scripts_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(scripts_dir);
addpath(genpath(fullfile(root_dir, 'src')));
path_cleanup = onCleanup(@() rmpath(genpath(fullfile(root_dir, 'src')))); %#ok<NASGU>

test_passed = 0;
test_failed = 0;
fixture_root = tempname;
mkdir(fixture_root);
fixture_config = fullfile(fixture_root, 'spm_profiles');
mkdir(fixture_config);
fixture_cleanup = onCleanup(@() rmdir(fixture_root, 's')); %#ok<NASGU>

%% The shipped templates are fixed, blank deployment roots with exact revisions.
run_test('local-current template', check_default_config(root_dir, ...
    'local-current', 'local_current.m', 'r6313'));
run_test('local-near-parity-r2010b template', check_default_config(root_dir, ...
    'local-near-parity-r2010b', 'local_near_parity_r2010b.m', 'r4667'));
run_test('launchpad template', check_default_config(root_dir, ...
    'launchpad', 'launchpad.m', 'r6313'));

%% Blank, absolute, and config-relative roots have explicit behavior.
write_config(fixture_config, 'local_current', '', 'r6313');
write_config(fixture_config, 'local_near_parity_r2010b', ...
    fullfile(fixture_root, 'absolute-r4667'), 'r4667');
write_config(fixture_config, 'launchpad', 'relative-r6313', 'r6313');
mkdir(fullfile(fixture_root, 'absolute-r4667'));
mkdir(fullfile(fixture_config, 'relative-r6313'));
mkdir(fullfile(fixture_root, 'absolute-r6313'));
write_contents(fullfile(fixture_root, 'absolute-r4667'), '4667');
write_contents(fullfile(fixture_config, 'relative-r6313'), '6313');
write_contents(fullfile(fixture_root, 'absolute-r6313'), '6313');

blank = pseudo_CT_load_spm_profile_config('local-current', fixture_root);
run_test('blank root remains blank', isempty(blank.spm_root));
run_error_test('blank root has no fallback', 'SPM_ROOT:NotFound', ...
    @() pseudo_CT_compute_spm_root(blank, fixture_root));

absolute = pseudo_CT_load_spm_profile_config('local-near-parity-r2010b', fixture_root);
[absolute_root, ~] = pseudo_CT_compute_spm_root(absolute, fixture_root);
run_test('absolute root is used unchanged', strcmp(absolute_root, ...
    fullfile(fixture_root, 'absolute-r4667')));

relative = pseudo_CT_load_spm_profile_config('launchpad', fixture_root);
[relative_root, ~] = pseudo_CT_compute_spm_root(relative, fixture_root);
run_test('relative root uses profile config directory', strcmp(relative_root, ...
    fullfile(fixture_config, 'relative-r6313')));

%% Registry consumption keeps local and remote identities separate.
fake_repo = tempname;
mkdir(fake_repo);
mkdir(fullfile(fake_repo, 'src'));
mkdir(fullfile(fake_repo, 'src', 'config'));
mkdir(fullfile(fake_repo, 'src', 'config', 'spm_profiles'));
repo_fixture_cleanup = onCleanup(@() rmdir(fake_repo, 's')); %#ok<NASGU>
write_config(fullfile(fake_repo, 'src', 'config', 'spm_profiles'), ...
    'local_current', 'local-r6313', 'r6313');
write_config(fullfile(fake_repo, 'src', 'config', 'spm_profiles'), ...
    'local_near_parity_r2010b', 'near-r4667', 'r4667');
write_config(fullfile(fake_repo, 'src', 'config', 'spm_profiles'), ...
    'launchpad', 'launchpad-r6313', 'r6313');

local_manifest = pseudo_CT_resolve_profile('local-current', fake_repo);
near_manifest = pseudo_CT_resolve_profile('local-near-parity-r2010b', fake_repo);
launch_manifest = pseudo_CT_resolve_profile('launchpad', fake_repo);
run_test('registry consumes local-current revision', ...
    strcmp(local_manifest.spm_version, 'r6313') && ...
    strcmp(local_manifest.spm_root, 'local-r6313'));
run_test('registry consumes near-parity revision', ...
    strcmp(near_manifest.spm_version, 'r4667') && ...
    strcmp(near_manifest.spm_root, 'near-r4667'));
run_test('Launchpad local and remote identities stay separate', ...
    strcmp(launch_manifest.spm_version, 'r6313') && ...
    strcmp(launch_manifest.launchpad_identity.backend_spm_version, 'r4667') && ...
    strcmp(launch_manifest.launchpad_identity.backend_runtime, 'MCR7.11'));
run_test('near-parity is a fixed internal canonical name', ...
    strcmp(near_manifest.name, 'local-near-parity-r2010b'));

write_config(fixture_config, 'local_current', ...
    fullfile(fixture_root, 'absolute-r6313'), 'r6313');
local_gate = pseudo_CT_load_spm_profile_config('local-current', fixture_root);
run_test('r6313 local-current/launchpad packages pass revision gate', ...
    gate_passes(local_gate, fixture_root) && gate_passes(relative, fixture_root));
run_test('near-parity r4667 package passes revision gate', gate_passes(absolute, fixture_root));

write_config(fixture_config, 'local_current', ...
    fullfile(fixture_root, 'absolute-r4667'), 'r6313');
cross_local = pseudo_CT_load_spm_profile_config('local-current', fixture_root);
cross_local_ok = gate_fails(cross_local, fixture_root, ...
    {'local-current', 'expected r6313', 'observed/missing r4667'});
write_config(fixture_config, 'local_near_parity_r2010b', ...
    fullfile(fixture_root, 'absolute-r6313'), 'r4667');
cross_near = pseudo_CT_load_spm_profile_config('local-near-parity-r2010b', fixture_root);
cross_near_ok = gate_fails(cross_near, fixture_root, ...
    {'local-near-parity-r2010b', 'expected r4667', 'observed/missing r6313'});
run_test('cross-linked packages fail deterministically', cross_local_ok && cross_near_ok);

missing_root = fullfile(fixture_root, 'missing-contents');
mkdir(missing_root);
write_config(fixture_config, 'local_current', missing_root, 'r6313');
missing = pseudo_CT_load_spm_profile_config('local-current', fixture_root);
missing_ok = gate_fails(missing, fixture_root, {'local-current', 'missing Contents.m'});
malformed_root = fullfile(fixture_root, 'malformed-contents');
mkdir(malformed_root);
write_contents(malformed_root, 'unknown');
write_config(fixture_config, 'local_current', malformed_root, 'r6313');
malformed = pseudo_CT_load_spm_profile_config('local-current', fixture_root);
malformed_ok = gate_fails(malformed, fixture_root, {'local-current', 'malformed Contents.m'});
run_test('missing/malformed Contents.m fail clearly', missing_ok && malformed_ok);

%% Unknown, malformed, and wrong-revision config files fail closed.
run_error_test('unknown profile rejected', 'PROFILE:InvalidName', ...
    @() pseudo_CT_load_spm_profile_config('not-a-profile', fixture_root));
write_config(fixture_config, 'local_current', 'x', 'r6313', 'missing_root');
run_error_test('missing spm_root rejected', 'SPM_CONFIG:Invalid', ...
    @() pseudo_CT_load_spm_profile_config('local-current', fixture_root));
write_config(fixture_config, 'local_current', 'x', 'r6313', 'nonchar_root');
run_error_test('non-char spm_root rejected', 'SPM_CONFIG:Invalid', ...
    @() pseudo_CT_load_spm_profile_config('local-current', fixture_root));
write_config(fixture_config, 'local_current', 'x', 'r6313', 'nonchar_revision');
run_error_test('non-char expected_revision rejected', 'SPM_CONFIG:Invalid', ...
    @() pseudo_CT_load_spm_profile_config('local-current', fixture_root));
write_config(fixture_config, 'local_current', 'x', 'r4667');
run_error_test('wrong canonical revision rejected', 'SPM_CONFIG:Invalid', ...
    @() pseudo_CT_load_spm_profile_config('local-current', fixture_root));

%% Hostile environment variables cannot redirect the fixed loader or registry.
write_config(fixture_config, 'local_current', 'x', 'r6313');
baseline = pseudo_CT_load_spm_profile_config('local-current', fixture_root);
environment_names = {'PSEUDOCT_SPM_ROOT', 'PSEUDOCT_SPM_VARIANT', ...
    'PSEUDOCT_PROFILE', 'SPM_ROOT'};
environment_values = save_environment(environment_names);
environment_cleanup = onCleanup(@() restore_environment(environment_names, ...
    environment_values)); %#ok<NASGU>
for ii = 1:length(environment_names)
    setenv(environment_names{ii}, fullfile(fixture_root, 'hostile-root'));
end
hostile = pseudo_CT_load_spm_profile_config('local-current', fixture_root);
run_test('hostile environment has no effect on config', ...
    strcmp(hostile.spm_root, baseline.spm_root) && ...
    strcmp(hostile.expected_revision, baseline.expected_revision));

total = test_passed + test_failed;
fprintf('\n=== External SPM Config Tests: %d/%d passed ===\n', ...
    test_passed, total);
if test_failed > 0
    error('test_spm_external_config:Failures', '%d test(s) failed.', test_failed);
end

%% ------------------------------------------------------------------------
function ok = check_default_config(repo_root, profile_name, file_name, revision)
    config = pseudo_CT_load_spm_profile_config(profile_name, ...
        fullfile(repo_root, 'src', 'config'));
    ok = isempty(config.spm_root) && ...
        strcmp(config.expected_revision, revision) && ...
        strcmp(config.config_path, fullfile(repo_root, 'src', 'config', ...
        'spm_profiles', file_name));
end

%% ------------------------------------------------------------------------
function write_config(config_dir, function_name, root_name, revision, malformed)
    if nargin < 5
        malformed = '';
    end
    path_name = fullfile(config_dir, [function_name '.m']);
    fid = fopen(path_name, 'w');
    if fid == -1
        error('test_spm_external_config:Fixture', 'Could not write %s.', path_name);
    end
    fprintf(fid, 'function c = %s()\n', function_name);
    fprintf(fid, 'c = struct();\n');
    switch malformed
        case 'missing_root'
            fprintf(fid, 'c.expected_revision = ''%s'';\n', revision);
        case 'nonchar_root'
            fprintf(fid, 'c.spm_root = 7;\n');
            fprintf(fid, 'c.expected_revision = ''%s'';\n', revision);
        case 'nonchar_revision'
            fprintf(fid, 'c.spm_root = ''%s'';\n', escape_quotes(root_name));
            fprintf(fid, 'c.expected_revision = 7;\n');
        otherwise
            fprintf(fid, 'c.spm_root = ''%s'';\n', escape_quotes(root_name));
            fprintf(fid, 'c.expected_revision = ''%s'';\n', revision);
    end
    fprintf(fid, 'end\n');
    fclose(fid);
    rehash;
end

%% ------------------------------------------------------------------------
function write_contents(root_name, revision)
    fid = fopen(fullfile(root_name, 'Contents.m'), 'w');
    if fid == -1
        error('test_spm_external_config:Fixture', 'Could not write Contents.m.');
    end
    fprintf(fid, '%% Version %s (SPM8)\n', revision);
    fclose(fid);
end

%% ------------------------------------------------------------------------
function ok = gate_passes(config, root_name)
try
    pseudo_CT_preflight(preflight_manifest(config, root_name), root_name);
    ok = true;
catch
    ok = false;
end
end

%% ------------------------------------------------------------------------
function ok = gate_fails(config, root_name, fragments)
try
    pseudo_CT_preflight(preflight_manifest(config, root_name), root_name);
    ok = false;
catch ME
    ok = strcmp(ME.identifier, 'SPM_ROOT:RevisionMismatch');
    for ii = 1:length(fragments)
        ok = ok && ~isempty(strfind(ME.message, fragments{ii}));
    end
end
end

%% ------------------------------------------------------------------------
function manifest = preflight_manifest(config, root_name)
    manifest = config; manifest.name = config.profile_name; manifest.spm_root = config.spm_root; manifest.spm_version = config.expected_revision; manifest.spm_expected_revision = config.expected_revision; manifest.spm_root_base = config.config_dir; manifest.vers_path = root_name; manifest.vers_policy = struct('required', false); manifest.atlas_assets = struct('batch_atlas_path', root_name, 'required_files', {{}}); manifest.pca_order = {'callable_pca'}; manifest.runtime_guard = 'supported_matlab'; manifest.normalization_resource = struct('source_command', 'source /tmp'); manifest.recenter = 'No'; manifest.zero_background = 'Yes'; manifest.bone_enabled = true; manifest.fwhm = 0; manifest.aliasing_default = 1; manifest.aliasing_override = [0 1]; manifest.cleanup_policy = 'remove_on_success'; manifest.launchpad_identity = struct(); manifest.provenance = struct('expected_spm_version', config.expected_revision, 'record_path', '');
end

%% ------------------------------------------------------------------------
function value = escape_quotes(value)
    value = strrep(value, '''', '''''');
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
    run_test(label, caught && strcmp(actual_id, expected_id));
    if caught && ~strcmp(actual_id, expected_id)
        fprintf('         expected %s, got %s\n', expected_id, actual_id);
    end
end

%% ------------------------------------------------------------------------
function values = save_environment(names)
    values = cell(size(names));
    for ii = 1:length(names)
        values{ii} = getenv(names{ii});
    end
end

%% ------------------------------------------------------------------------
function restore_environment(names, values)
    for ii = 1:length(names)
        setenv(names{ii}, values{ii});
    end
end

end
