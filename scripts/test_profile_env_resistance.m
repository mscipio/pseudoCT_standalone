function test_profile_env_resistance()
%TEST_PROFILE_ENV_RESISTANCE RED-first checks for profile authority.
%   Each canonical profile is resolved with the prohibited variables unset
%   and with one hostile alternate value. Effective resource and processing
%   decisions must be identical. Environment restoration is exception-safe
%   for every case. No GUI, SPM batch, DICOM, FreeSurfer, SSH/PBS, or subject
%   mutation is run.
%
%   The supported selection surface is the explicit canonical profile name
%   plus the input-file path handled by the existing entrypoints. There is
%   no environment profile selector. PSEUDOCT_DEBUG_MOVE2MNI is intentionally
%   outside this matrix: it is a diagnostic artifact switch, not a workflow
%   policy or resource selector.
%
%   Minimum supported MATLAB: R2010b.

scripts_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(scripts_dir);
addpath(genpath(fullfile(root_dir, 'src')));
path_cleanup = onCleanup(@() rmpath(genpath(fullfile(root_dir, 'src')))); %#ok<NASGU>

fake_root = tempname;
mkdir(fake_root);
make_fixture(fake_root);
fixture_cleanup = onCleanup(@() rmdir(fake_root, 's')); %#ok<NASGU>

profiles = {'local-current'; 'local-near-parity-r2010b'; 'launchpad'};
matrix = prohibited_matrix(fake_root);
matrix_names = {matrix.name};

test_passed = 0;
test_failed = 0;

% Every canonical name remains the only profile selection input, even when
% all prohibited variables are hostile. This also proves near-parity cannot
% be selected by an environment value.
for profile_idx = 1:length(profiles)
    original = save_environment(matrix_names);
    restore = onCleanup(@() restore_environment(matrix_names, original)); %#ok<NASGU>
    set_all_environment(matrix_names, 'hostile-profile-value');
    selected = pseudo_CT_resolve_profile(profiles{profile_idx}, fake_root);
    run_test(sprintf('canonical profile selection: %s', profiles{profile_idx}), ...
        strcmp(selected.name, profiles{profile_idx}));
end

% Compare the complete decision snapshot for every variable/profile pair.
for matrix_idx = 1:length(matrix)
    run_environment_case(matrix(matrix_idx), profiles, fake_root, matrix_names);
end

% The supported input-file path remains in the public collector path, while
% the entrypoints themselves do not consume PSEUDOCT_* selection variables.
local_source = read_text(fullfile(root_dir, 'run_pseudo_CT_local.m'));
launchpad_source = read_text(fullfile(root_dir, 'run_pseudo_CT_launchpad.m'));
normalization_source = read_text(fullfile(root_dir, 'src', 'remote', 'run_normalization_cmd.m'));
legacy_cleanup_source = read_text(fullfile(root_dir, 'src', 'config', 'pseudo_CT_keep_temp_enabled.m'));
run_test('local entrypoint binds fixed local-current profile', ...
    ~isempty(strfind(local_source, 'pseudo_CT_resolve_profile(''local-current'', pathp)')));
run_test('Launchpad entrypoint binds fixed launchpad profile', ...
    ~isempty(strfind(launchpad_source, 'pseudo_CT_resolve_profile(''launchpad'', pathp)')));
run_test('local input-file path remains collector input', ...
    ~isempty(strfind(local_source, 'local_collect_jobs(manifest, varargin{:})')));
run_test('Launchpad input-file path remains collector input', ...
    ~isempty(strfind(launchpad_source, 'launchpad_collect_jobs(manifest, varargin{:})')));
run_test('local entrypoint has no prohibited environment selector', ...
    isempty(strfind(local_source, 'getenv(''PSEUDOCT_')));
run_test('Launchpad entrypoint has no prohibited environment selector', ...
    isempty(strfind(launchpad_source, 'getenv(''PSEUDOCT_')));
run_test('normalization fallback does not consume FS library environment', ...
    isempty(strfind(normalization_source, 'getenv(''PSEUDOCT_FS_LIBSTDCPP_ROOT'')')));
run_test('legacy cleanup helper does not consume KEEP_TMP environment', ...
    isempty(strfind(legacy_cleanup_source, 'getenv(''PSEUDOCT_KEEP_TMP'')')));

total = test_passed + test_failed;
fprintf('\n=== Profile Environment Resistance Tests: %d/%d passed ===\n', ...
    test_passed, total);
if test_failed > 0
    error('test_profile_env_resistance:Failures', '%d test(s) failed.', test_failed);
end

%% ------------------------------------------------------------------------
function matrix = prohibited_matrix(fake_root)

matrix(1).name = 'PSEUDOCT_ZERO_BACKGROUND';
matrix(1).category = 'background policy';
matrix(1).hostile = 'Yes';
matrix(2).name = 'PSEUDOCT_USE_PRINCOMP';
matrix(2).category = 'PCA backend order';
matrix(2).hostile = '1';
matrix(3).name = 'PSEUDOCT_SPM_ROOT';
matrix(3).category = 'SPM tree';
matrix(3).hostile = fullfile(fake_root, 'spm8-r4667');
matrix(4).name = 'PSEUDOCT_SPM_VARIANT';
matrix(4).category = 'SPM version/variant';
matrix(4).hostile = 'r4667';
matrix(5).name = 'PSEUDOCT_BATCH_ATLAS';
matrix(5).category = 'atlas/template resources';
matrix(5).hostile = fullfile(fake_root, 'hostile-atlas');
matrix(6).name = 'PSEUDOCT_KEEP_TMP';
matrix(6).category = 'cleanup/retention';
matrix(6).hostile = 'Yes';
matrix(7).name = 'PSEUDOCT_FS_LIBSTDCPP_ROOT';
matrix(7).category = 'normalization child runtime';
matrix(7).hostile = fullfile(fake_root, 'hostile-libstdc++');
end

%% ------------------------------------------------------------------------
function run_environment_case(entry, profiles, fake_root, matrix_names)

original = save_environment(matrix_names);
restore = onCleanup(@() restore_environment(matrix_names, original)); %#ok<NASGU>
set_all_environment(matrix_names, '');

for pp = 1:length(profiles)
    baseline = capture_decisions(profiles{pp}, fake_root);
    setenv(entry.name, entry.hostile);
    hostile = capture_decisions(profiles{pp}, fake_root);
    run_test(sprintf('%s / %s', entry.name, profiles{pp}), ...
        isequal(baseline.decisions, hostile.decisions));
    setenv(entry.name, '');
end
end

%% ------------------------------------------------------------------------
function snapshot = capture_decisions(profile_name, fake_root)

manifest = pseudo_CT_resolve_profile(profile_name, fake_root);
[spm_dir, spm_label] = pseudo_CT_compute_spm_root(manifest, fake_root);
atlas_dir = pseudo_CT_resolve_batch_atlas_path(fake_root, manifest);
[~, pca_backend, pca_provenance] = resolve_pca(manifest);
[source_command, child_lib_path, normalization_ignored] = ...
    pseudo_CT_normalization_runtime(manifest);
[cleanup_policy, cleanup_ignored] = cleanup_owner(manifest);
zero_background = pseudo_CT_zero_background_enabled(manifest);
aliasing_default = pseudo_CT_validate_aliasing(manifest.aliasing_default, manifest);

snapshot.decisions = struct( ...
    'name', manifest.name, ...
    'spm_root', spm_dir, ...
    'spm_label', spm_label, ...
    'spm_version', manifest.spm_version, ...
    'vers_path', manifest.vers_path, ...
    'vers_order', {manifest.vers_policy.order}, ...
    'atlas_path', atlas_dir, ...
    'atlas_required_files', {manifest.atlas_assets.required_files}, ...
    'pca_order', {manifest.pca_order}, ...
    'pca_backend', pca_backend, ...
    'runtime_guard', manifest.runtime_guard, ...
    'normalization_source', source_command, ...
    'normalization_child_lib', child_lib_path, ...
    'recenter', manifest.recenter, ...
    'zero_background', zero_background, ...
    'bone_enabled', manifest.bone_enabled, ...
    'fwhm', manifest.fwhm, ...
    'aliasing_default', aliasing_default, ...
    'aliasing_override', manifest.aliasing_override, ...
    'cleanup_policy', cleanup_policy, ...
    'launchpad_identity', manifest.launchpad_identity, ...
    'provenance', manifest.provenance);

% Diagnostics are deliberately excluded from decisions: a seam may report
% that a variable was ignored without allowing it to change the manifest.
snapshot.diagnostics = struct('pca', pca_provenance.ignored_env, ...
    'normalization', normalization_ignored, 'cleanup', cleanup_ignored);
end

%% ------------------------------------------------------------------------
function [pca_fn, backend_name, provenance] = resolve_pca(manifest)

try
    [pca_fn, backend_name, provenance] = pseudo_CT_pca_resolver(manifest);
catch ME
    if strcmp(manifest.runtime_guard, 'launchpad_opaque') && ...
            strcmp(ME.identifier, 'PCA:BackendUnavailable')
        pca_fn = [];
        backend_name = 'remote';
        provenance = struct('ignored_env', '');
    else
        rethrow(ME);
    end
end
end

%% ------------------------------------------------------------------------
function make_fixture(fake_root)

mkdir(fullfile(fake_root, 'spm8-r6313'));
mkdir(fullfile(fake_root, 'spm8-r4667'));
atlas_dir = fullfile(fake_root, 'Batch_atlas');
mkdir(atlas_dir);
required = {'TPM.nii'; 'ch2.nii'; 'Template_0.nii'; 'Template_1.nii'; ...
    'Template_2.nii'; 'Template_3.nii'; 'Template_4.nii'; 'Template_5.nii'; ...
    'Template_6.nii'};
for ii = 1:length(required)
    touch(fullfile(atlas_dir, required{ii}));
end
mkdir(fullfile(atlas_dir, 'ganymed-ssh2-build250'));
touch(fullfile(atlas_dir, 'ganymed-ssh2-build250', 'ganymed-ssh2-build250.jar'));
end

%% ------------------------------------------------------------------------
function touch(path_name)

fid = fopen(path_name, 'w');
if fid == -1
    error('test_profile_env_resistance:Fixture', 'Could not create %s.', path_name);
end
fclose(fid);
end

%% ------------------------------------------------------------------------
function values = save_environment(names)

values = cell(size(names));
for env_idx = 1:length(names)
    values{env_idx} = getenv(names{env_idx});
end
end

%% ------------------------------------------------------------------------
function set_all_environment(names, value)

for env_idx = 1:length(names)
    setenv(names{env_idx}, value);
end
end

%% ------------------------------------------------------------------------
function restore_environment(names, values)

for restore_idx = 1:length(names)
    setenv(names{restore_idx}, values{restore_idx});
end
end

%% ------------------------------------------------------------------------
function text = read_text(path_name)

fid = fopen(path_name, 'r');
if fid == -1
    text = '';
    return;
end
text = fread(fid, inf, '*char')';
end

%% ------------------------------------------------------------------------
function run_test(label, ok)

if ok
    test_passed = test_passed + 1; %#ok<NASGU>
    fprintf('  PASS  %s\n', label);
else
    test_failed = test_failed + 1; %#ok<NASGU>
    fprintf('  FAIL  %s\n', label);
end
end

end
