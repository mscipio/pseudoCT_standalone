function test_profile_authority()
%TEST_PROFILE_AUTHORITY Verify the simple dynamic profile system.

tests_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(tests_dir);
src_path = genpath(fullfile(root_dir, 'src'));
old_path = path();
addpath(src_path, '-begin');
cleanup = onCleanup(@() restore_path(old_path)); %#ok<NASGU>

config_root = fullfile(root_dir, 'src', 'config');
profile_dir = fullfile(config_root, 'profiles');
files = dir(fullfile(profile_dir, '*.m'));
profiles = pseudo_CT_list_profiles(config_root);
assert(length(profiles) == length(files));
names = {profiles.name};
assert(length(unique(names)) == length(names));

for ii = 1:length(profiles)
    assert(isempty(strfind(profiles(ii).file_path, 'deprecated')));
    assert(strcmp(fileparts(profiles(ii).file_path), profile_dir));
end
expected_active = {'devel'; 'local-current'; 'local-mprage-only'; ...
    'mlsc-current'; 'mlsc-mprage-only'};
assert(length(profiles) == length(expected_active));
assert(isequal(sort(names(:)), sort(expected_active)));

configs = cell(length(profiles), 1);
for ii = 1:length(profiles)
    configs{ii} = pseudo_CT_load_profile(profiles(ii).name, config_root);
    assert(configs{ii}.aliasing_default == 1);
    assert(strcmp(configs{ii}.recenter_before_normalization, 'Yes'));
    assert(strcmp(profiles(ii).name, ...
        strrep(profiles(ii).function_name, '_', '-')));
    assert(strcmp(profiles(ii).display_name, ...
        configs{ii}.presentation.display_name));
    assert(~isempty(strtrim(profiles(ii).display_name)));
    assert(~isempty(strtrim(profiles(ii).description)));
    assert(ismember(profiles(ii).group, {'recommended'; 'specialized'}));
end

[ordered_profiles, default_index] = pseudo_CT_prepare_profile_choices(profiles);
assert(length(ordered_profiles) == length(profiles));
assert(strcmp(ordered_profiles(default_index).name, 'mlsc-current'));
mlsc_current = configs{local_config_index(names, 'mlsc-current')};
assert(strcmp(mlsc_current.presentation.group, 'specialized'));
assert(mlsc_current.presentation.recommended);
ordered_group_rank = 1 + strcmp({ordered_profiles.group}, 'specialized');
for ii = 2:length(ordered_profiles)
    assert(ordered_group_rank(ii) >= ordered_group_rank(ii - 1));
    if ordered_group_rank(ii) == ordered_group_rank(ii - 1)
        assert(ordered_profiles(ii).order >= ordered_profiles(ii - 1).order);
    end
end
without_local = profiles(~strcmp({profiles.name}, 'local-current'));
[without_local, fallback_index] = pseudo_CT_prepare_profile_choices(without_local);
assert(strcmp(without_local(fallback_index).name, 'mlsc-current'));
assert(without_local(fallback_index).recommended);
assert(strcmp(without_local(fallback_index).group, 'specialized'));
assert(~strcmp(ordered_profiles(1).display_name, ordered_profiles(1).name));
local = configs{local_config_index(names, 'local-current')};
local_mprage = configs{local_config_index(names, 'local-mprage-only')};
mlsc = configs{local_config_index(names, 'mlsc-current')};
mlsc_mprage = configs{local_config_index(names, 'mlsc-mprage-only')};
assert(strcmp(local.mode, 'local'));
assert(strcmp(mlsc.mode, 'mlsc'));
assert(strcmp(local.normalization.host, '127.0.0.1'));
assert(strcmp(local.io_policy.reference, 'umap-required'));
assert(strcmp(local.io_policy.output, 'nifti-and-dicom'));
assert(strcmp(local.io_policy.gui, 'mMR'));
assert(strcmp(local_mprage.io_policy.reference, 'none'));
assert(strcmp(local_mprage.io_policy.output, 'nifti-only'));
assert(strcmp(local_mprage.io_policy.gui, 'mprage-only'));
assert(strcmp(local_mprage.compatibility_profile, 'local-current'));
assert(strcmp(mlsc.io_policy.reference, 'umap-required'));
assert(strcmp(mlsc.io_policy.output, 'nifti-and-dicom'));
assert(strcmp(mlsc.io_policy.gui, 'mMR'));
assert(strcmp(mlsc.compatibility_profile, ''));
assert(strcmp(mlsc.presentation.group, 'specialized'));
assert(mlsc.presentation.recommended);
assert(~isempty(strfind(lower(mlsc.presentation.display_name), 'mlsc')));
assert(strcmp(mlsc_mprage.io_policy.reference, 'none'));
assert(strcmp(mlsc_mprage.io_policy.output, 'nifti-only'));
assert(strcmp(mlsc_mprage.io_policy.gui, 'mprage-only'));
assert(strcmp(mlsc_mprage.compatibility_profile, 'mlsc-current'));
assert(strcmp(mlsc_mprage.presentation.group, 'specialized'));
assert(~mlsc_mprage.presentation.recommended);
assert(strcmp(mlsc_mprage.mode, 'mlsc'));
assert(strcmp(mlsc_mprage.implementation, 'current'));
assert(isfield(mlsc_mprage, 'current'));
assert(isequal(mlsc_mprage.current, ...
    configs{local_config_index(names, 'mlsc-current')}.current));
% T013 narrow correction: active MPRAGE-only wording names the modality
% (specialized/not-recommended is already covered by group/recommended).
assert(~isempty(strfind(lower(mlsc_mprage.presentation.description), ...
    'mprage')));
assert(isfield(mlsc, 'mlsc') && isfield(mlsc_mprage, 'mlsc'));
assert(strcmp(mlsc.mlsc.host, 'mlsc.nmr.mgh.harvard.edu'));
assert(strcmp(mlsc.mlsc.shell, '/bin/bash'));
mlsc_current_config = configs{local_config_index(names, 'mlsc-current')};
assert(~isfield(mlsc_current_config.mlsc, 'runner'));
assert(~isfield(mlsc_mprage.mlsc, 'runner'));
assert(strcmp(mlsc_current_config.mlsc.freesurfer_env, ...
    mlsc_mprage.mlsc.freesurfer_env));
assert(strcmp(mlsc.normalization.host, mlsc.mlsc.host));
assert(strcmp(mlsc.normalization.cluster, 'Yes'));
assert(strcmp(mlsc_mprage.normalization.host, mlsc_mprage.mlsc.host));
assert(strcmp(mlsc_mprage.normalization.cluster, 'Yes'));
assert(isequal(mlsc_mprage.pca_order, {'callable_pca'; 'repo_legacy'}));

% Resource setup follows the selected mode only. The fixture intentionally
% leaves unrelated mode resources absent, so validating every backend would
% fail this check.
resource_root = tempname;
mkdir(resource_root);
resource_cleanup = onCleanup(@() local_cleanup(resource_root)); %#ok<NASGU>
local_fixture = local_resource_fixture(local, resource_root, 'local');
setup_pseudo_CT_paths(root_dir, local_fixture);
mlsc_fixture = local_resource_fixture(mlsc, resource_root, 'mlsc');
setup_pseudo_CT_paths(root_dir, mlsc_fixture);

% A newly added profile is discovered and ordered by its own metadata.
added_root = tempname;
mkdir(added_root);
mkdir(fullfile(added_root, 'profiles'));
added_cleanup = onCleanup(@() local_cleanup(added_root)); %#ok<NASGU>
copyfile(fullfile(profile_dir, 'local_current.m'), ...
    fullfile(added_root, 'profiles', 'local_current.m'));
local_write(fullfile(added_root, 'profiles', 'added_profile.m'), ...
    ['function config = added_profile()' char(10) ...
     'config.presentation.display_name = ''Added test profile'';' char(10) ...
     'config.presentation.description = ''Temporary test profile'';' char(10) ...
     'config.presentation.group = ''recommended'';' char(10) ...
     'config.presentation.recommended = true;' char(10) ...
     'config.presentation.order = 1;' char(10) 'end' char(10)]);
temporary_profiles = pseudo_CT_list_profiles(added_root);
temporary_names = {temporary_profiles.name};
added_index = find(strcmp(temporary_names, 'added-profile'), 1);
assert(~isempty(added_index));
assert(strcmp(temporary_profiles(added_index).display_name, ...
    'Added test profile'));
[temporary_ordered, temporary_default] = ...
    pseudo_CT_prepare_profile_choices(temporary_profiles);
assert(strcmp(temporary_ordered(1).name, 'added-profile'));
assert(strcmp(temporary_ordered(temporary_default).name, 'local-current'));

assert(isequal(local_without_policy(local_mprage), ...
    local_without_policy(local)));
assert(isequal(local_without_policy(mlsc_mprage), ...
    local_without_policy(mlsc_current_config)));

unknown_failed = false;
try
    pseudo_CT_load_profile('not-a-profile', config_root);
catch ME
    unknown_failed = strcmp(ME.identifier, 'pseudo_CT:InvalidProfile');
end
assert(unknown_failed);

% Exercise malformed tuple and recursive baseline-drift rejection in an
% isolated profile directory, without modifying the repository manifests.
test_root = tempname;
mkdir(test_root);
mkdir(fullfile(test_root, 'profiles'));
test_cleanup = onCleanup(@() local_cleanup(test_root)); %#ok<NASGU>
copyfile(fullfile(profile_dir, 'local_current.m'), ...
    fullfile(test_root, 'profiles', 'local_current.m'));
local_write(fullfile(test_root, 'profiles', 'malformed_profile.m'), ...
    ['function config = malformed_profile()' char(10) ...
     'config.mode = ''local'';' char(10) 'end' char(10)]);
malformed_failed = false;
try
    pseudo_CT_load_profile('malformed-profile', test_root);
catch ME
    malformed_failed = strcmp(ME.identifier, 'pseudo_CT:InvalidProfile');
end
assert(malformed_failed);

baseline_text = local_read(fullfile(profile_dir, 'local_current.m'));
baseline_text = strrep(baseline_text, ...
    'function config = local_current()', ...
    'function config = drift_profile()');
baseline_text = strrep(baseline_text, ...
    'config.compatibility_profile = '''';', ...
    ['config.compatibility_profile = ''local-current'';' char(10) ...
     'config.spm_root = ''/deliberate-profile-drift'';']);
baseline_text = strrep(baseline_text, ...
    'config.io_policy.reference = ''umap-required'';', ...
    'config.io_policy.reference = ''none'';');
baseline_text = strrep(baseline_text, ...
    'config.io_policy.output = ''nifti-and-dicom'';', ...
    'config.io_policy.output = ''nifti-only'';');
baseline_text = strrep(baseline_text, ...
    'config.io_policy.gui = ''mMR'';', ...
    'config.io_policy.gui = ''mprage-only'';');
local_write(fullfile(test_root, 'profiles', 'drift_profile.m'), baseline_text);
drift_failed = false;
try
    pseudo_CT_load_profile('drift-profile', test_root);
catch ME
    drift_failed = strcmp(ME.identifier, 'pseudo_CT:ProfileDrift');
end
assert(drift_failed);

active_files = [{fullfile(root_dir, 'run_pseudo_CT.m')}; ...
    collect_m_files(fullfile(root_dir, 'src'))];
forbidden = {['pseudo_CT_' 'resolve_profile']; ...
    ['pseudo_CT_' 'load_spm_profile_config']; ['pseudo_CT_' 'preflight']; ...
    ['pseudo_CT_' 'compute_spm_root']; ['pseudo_CT_' 'resolve_spm_root']; ...
    ['pseudo_CT_' 'resolve_batch_atlas_path']; ['pseudo_CT_' 'profile_registry']; ...
    ['pseudo_CT_' 'supported_profiles']; ['spm_' 'profiles']; ...
    ['spm_' 'expected_revision']; ['expected_' 'spm_version']; ...
    ['validate_' 'spm_revision']};
for ii = 1:length(active_files)
    source = read_text(active_files{ii});
    for jj = 1:length(forbidden)
        assert(isempty(strfind(source, forbidden{jj})));
    end
end

entry_source = read_text(fullfile(root_dir, 'run_pseudo_CT.m'));
lifecycle_source = read_text(fullfile(root_dir, 'src', 'orchestration', ...
    'pseudo_CT_run_lifecycle.m'));
selector_source = read_text(fullfile(root_dir, 'src', 'gui', ...
    'pseudo_CT_profile_selector.m'));
compute_source = read_text(fullfile(root_dir, 'src', 'science', 'current', ...
    'pseudo_CT_current_compute.m'));
assert(~isempty(strfind(entry_source, 'pseudo_CT_orchestrate(')));
assert(~isempty(strfind(lifecycle_source, 'switch config.mode')));
assert(isempty(strfind(selector_source, 'listdlg')));
assert(~isempty(strfind(selector_source, '''Style'', ''radiobutton''')));
assert(~isempty(strfind(selector_source, 'pseudo_CT_profile_selector_layout')));
assert(~isempty(strfind(selector_source, '''Style'', ''slider''')));
assert(~isempty(strfind(selector_source, 'profiles(selected_index).name')));
assert(length(strfind(lifecycle_source, 'config.fwhm')) >= 2);
assert(~isempty(strfind(compute_source, 'if config.bone_enabled')));
assert(~isempty(strfind(compute_source, 'config.zero_background')));
assert(~isempty(strfind(compute_source, ...
    'move_image_2_MNI(P_orig, fullfile(dir_batch_templates, ''ch2.nii''), ...')));

% Active runtime files are independent of repository-only maintainer and
% compatibility content. Keep this assertion at the source boundary so a
% future path refactor cannot accidentally make the pipeline depend on an
% archive-excluded directory. Comments are stripped before the check so
% prose mentions of maintainer paths do not trip the executable-dependency
% invariant (e.g. src/backends/mlsc/mlsc_release_gate.m header references to the
% release tooling).
runtime_files = [{fullfile(root_dir, 'run_pseudo_CT.m')}; ...
    collect_m_files(fullfile(root_dir, 'src'))];
for ii = 1:length(runtime_files)
    runtime_source = read_text(runtime_files{ii});
    runtime_code = local_strip_matlab_comments(runtime_source);
    assert(isempty(strfind(runtime_code, 'Makefile')));
    assert(isempty(strfind(runtime_code, 'scripts/')));
    assert(isempty(strfind(runtime_code, 'docs/')));
end

% --- Aliasing regression checks (T003) ---
% Every active profile resolves the lock-pinned local artifact from install root.
canonical_aliasing_root = fullfile(root_dir, 'external', ...
    'correct_aliasing-0.4.0');
production_names = {'local-current', 'local-mprage-only', ...
    'mlsc-current', 'mlsc-mprage-only'};
for ii = 1:length(production_names)
    idx = find(strcmp(names, production_names{ii}), 1);
    assert(~isempty(idx));
    assert(strcmp(configs{idx}.aliasing_root, canonical_aliasing_root), ...
        sprintf('Profile %s aliasing_root mismatch', production_names{ii}));
end

% The devel profile uses the same identified local dependency as production.
devel_aliasing_root = canonical_aliasing_root;
devel_idx = find(strcmp(names, 'devel'), 1);
assert(~isempty(devel_idx));
assert(strcmp(configs{devel_idx}.aliasing_root, devel_aliasing_root), ...
    'devel profile aliasing_root must use the pinned local artifact');
assert(~isempty(configs{devel_idx}.aliasing_root));

loader_source = read_text(fullfile(root_dir, 'src', 'config', ...
    'pseudo_CT_load_profile.m'));
assert(~isempty(strfind(loader_source, '''aliasing_root''')));

setup_source = read_text(fullfile(root_dir, 'src', 'config', ...
    'setup_pseudo_CT_paths.m'));
assert(~isempty(strfind(setup_source, 'pseudo_CT:AliasingRootMissing')));
assert(~isempty(strfind(setup_source, ...
    'addpath(config.aliasing_root, ''-begin'')')));
assert(~isempty(strfind(setup_source, 'clear correct_aliasing')));
assert(~isempty(strfind(setup_source, 'rehash')));

active_nose = fullfile(root_dir, 'src', 'orchestration', ...
    'automatic_anti_aliasing_nose_2_back.m');
active_center = fullfile(root_dir, 'src', 'orchestration', ...
    'center_subject_in_image.m');
assert(exist(active_nose, 'file') ~= 2);
assert(exist(active_center, 'file') ~= 2);

% Shared boundary: the local path delegates the aliasing/recentering seam to
% the shared prepare helper and the computation to the shared compute helper;
% the facade itself performs no direct aliasing call.
prepare_check = read_text(fullfile(root_dir, 'src', 'science', 'current', ...
    'pseudo_CT_current_prepare.m'));
assert(~isempty(strfind(prepare_check, 'result = correct_aliasing(')));
assert(isempty(strfind(entry_source, 'correct_aliasing(')));

% --- T009 focused 2x2 architecture/parity/isolation checks (no live backend) ---
list_source = read_text(fullfile(root_dir, 'src', 'config', ...
    'pseudo_CT_list_profiles.m'));
assert(~isempty(strfind(list_source, 'dir(fullfile(profile_dir, ''*.m''))')));
% Five primary profiles: devel plus the local and MLSC current variants.
assert(length(files) == 5);
assert(exist(fullfile(profile_dir, 'mlsc.m'), 'file') ~= 2);
assert(~ismember('mlsc', names));

canonical_names = {'local-current'; 'local-mprage-only'; 'mlsc-current'; ...
    'mlsc-mprage-only'; 'devel'};
for ii = 1:length(canonical_names)
    resolved = pseudo_CT_load_profile(canonical_names{ii}, config_root);
    assert(isstruct(resolved) && numel(resolved) == 1);
end

% Removed profile keys and the retired mlsc alias must fail closed.
rejected_fixed = {'mlsc'; 'local-legacy'; 'mlsc-legacy'; 'launchpad-legacy'};
for ii = 1:length(rejected_fixed)
    rejected_ok = false;
    try
        pseudo_CT_load_profile(rejected_fixed{ii}, config_root);
    catch ME
        rejected_ok = strcmp(ME.identifier, 'pseudo_CT:InvalidProfile');
    end
    assert(rejected_ok);
end
for ii = 1:length(canonical_names)
    underscored = strrep(canonical_names{ii}, '-', '_');
    if strcmp(underscored, canonical_names{ii})
        continue;
    end
    underscored_ok = false;
    try
        pseudo_CT_load_profile(underscored, config_root);
    catch ME
        underscored_ok = strcmp(ME.identifier, 'pseudo_CT:InvalidProfile');
    end
    assert(underscored_ok);
end
for ii = 1:length(configs)
    label_ok = false;
    try
        pseudo_CT_load_profile(configs{ii}.presentation.display_name, ...
            config_root);
    catch ME
        label_ok = strcmp(ME.identifier, 'pseudo_CT:InvalidProfile');
    end
    assert(label_ok);
end
root_on_path = ~isempty(strfind([path pathsep], [root_dir pathsep]));
if ~root_on_path
    addpath(root_dir, '-begin');
end
entrypoint_rejected = {'mlsc-legacy'; ...
    'local_current'; ...
    configs{local_config_index(names, 'local-current')}.presentation.display_name};
for ii = 1:length(entrypoint_rejected)
    entry_ok = false;
    try
        run_pseudo_CT('profile', entrypoint_rejected{ii});
    catch ME
        entry_ok = strcmp(ME.identifier, 'run_pseudo_CT:InvalidProfile');
    end
    assert(entry_ok);
end
if ~root_on_path
    rmpath(root_dir);
end

for ii = 1:length(configs)
    assert(isfield(configs{ii}, 'mode'));
    assert(isfield(configs{ii}, 'implementation'));
    assert(ismember(configs{ii}.mode, {'local'; 'mlsc'}));
    assert(ismember(configs{ii}.implementation, {'current'}));
    % Current MLSC artifact contract is shared by standard and MPRAGE-only.
    if strcmp(configs{ii}.implementation, 'current') && ...
            strcmp(configs{ii}.mode, 'mlsc')
        assert(ismember(profiles(ii).name, ...
            {'mlsc-current'; 'mlsc-mprage-only'}));
    end
end
current_mlsc_names = {profiles(cellfun(@(cfg) ...
    strcmp(cfg.mode, 'mlsc') && strcmp(cfg.implementation, 'current'), ...
    configs)).name};
assert(isequal(sort(current_mlsc_names(:)), ...
    sort({'mlsc-current'; 'mlsc-mprage-only'})));
local_current_cfg = configs{local_config_index(names, 'local-current')};
mlsc_current_cfg = configs{local_config_index(names, 'mlsc-current')};
assert(strcmp(local_current_cfg.mode, 'local'));
assert(strcmp(local_current_cfg.implementation, 'current'));
assert(strcmp(mlsc_current_cfg.mode, 'mlsc'));
assert(strcmp(mlsc_current_cfg.implementation, 'current'));
assert(isfield(mlsc_current_cfg, 'current'));
assert(~isfield(local_current_cfg, 'current'));

% --- T014 pinned-MCR authority (R2010b current-profile contract) ---
% The profile pins the MATLAB R2010b installation root; the expected deployed
% Runtime identity is separately represented as MCR 7.14. Runner and
% manifests bind the current artifact contract.
t014_pinned = '/usr/pubsw/common/matlab/7.11';
assert(strcmp(mlsc_current_cfg.current.mcr_root, t014_pinned));
assert(strcmp(mlsc_current_validate('pinned_mcr_root'), t014_pinned));
t014_actual = mlsc_current_validate('expected_actual');
assert(strcmp(t014_actual.release, 'R2010b'));
assert(isequal(t014_actual.mcr_version, [7 14]));
assert(isfield(mlsc_current_cfg.current, 'build_manifest'));
assert(isfield(mlsc_current_cfg.current, 'resource_manifest'));
assert(isfield(mlsc_current_cfg.current, 'required_outputs'));
assert(ismember('att_map.nii', mlsc_current_cfg.current.required_outputs));
assert(ismember('Fusion_MR_Pseudo_CT_validation.tiff', ...
    mlsc_current_cfg.current.required_outputs));
assert(ismember('Pseudo_CT_AC_Version.txt', ...
    mlsc_current_cfg.current.required_outputs));
t014_loader = read_text(fullfile(root_dir, 'src', 'config', ...
    'pseudo_CT_load_profile.m'));
assert(~isempty(strfind(t014_loader, ...
    'function validate_current(current, profile_name)')));
assert(~isempty(strfind(t014_loader, '/usr/pubsw/common/matlab/7.11')));
assert(~isempty(strfind(t014_loader, ...
    'config.current.mcr_root must be the pinned')));
t014_setup = read_text(fullfile(root_dir, 'src', 'config', ...
    'setup_pseudo_CT_paths.m'));
assert(~isempty(strfind(t014_setup, 'local_validate_current_setup(config)')));
t014_validate = read_text(fullfile(root_dir, 'src', 'backends', 'mlsc', ...
    'mlsc_current_validate.m'));
assert(~isempty(strfind(t014_validate, '/usr/pubsw/common/matlab/7.11')));
assert(~isempty(strfind(t014_validate, 'runner_checksum')));
assert(~isempty(strfind(t014_validate, 'SHA-256')));
% The pinned R2010b profile and its referenced artifacts pass both validation
% stages; active execution validates the configured artifact and runtime directly.
assert(mlsc_current_validate('validate_contract', mlsc_current_cfg));
assert(mlsc_current_validate('validate_for_execution', mlsc_current_cfg));
t014_preflight = read_text(fullfile(root_dir, 'src', 'backends', 'mlsc', ...
    'mlsc_preflight.m'));
assert(~isempty(strfind(t014_preflight, ...
    'mlsc_current_validate(''validate_contract''')));
t014_backend = read_text(fullfile(root_dir, 'src', 'backends', 'mlsc', ...
    'mlsc_backend.m'));
assert(~isempty(strfind(t014_backend, ...
    'mlsc_current_validate(''validate_for_execution''')));
% CURRENT PREPARE->normalize->COMPUTE: prepare owns alias/recenter before
% the external FreeSurfer boundary; compute runs only on verified
% normalized output. The payload enters prepare before compute, never
% reversed.
t014_payload = read_text(fullfile(root_dir, 'src', 'science', 'current', ...
    'mlsc_current_payload.m'));
t014_prepare_pos = strfind(t014_payload, '= pseudo_CT_current_prepare(');
t014_compute_pos = strfind(t014_payload, '= pseudo_CT_current_compute(');
assert(length(t014_prepare_pos) == 1 && length(t014_compute_pos) == 1 && ...
    t014_prepare_pos(1) < t014_compute_pos(1));
assert(~isempty(strfind(t014_payload, 'Verified normalized input missing')));

generate_source = read_text(fullfile(root_dir, 'src', 'backends', 'mlsc', ...
    'mlsc_generate_slurm_script.m'));
assert(~isempty(strfind(generate_source, 'att_map.nii')));
assert(~isempty(strfind(generate_source, 'config.mlsc')));
assert(~isempty(strfind(generate_source, 'mlsc.freesurfer_env')));
mlsc_dir_files = dir(fullfile(root_dir, 'src', 'backends', 'mlsc', '*.m'));
assert(~isempty(mlsc_dir_files));
for ii = 1:length(mlsc_dir_files)
    assert(isempty(strfind(lower(mlsc_dir_files(ii).name), 'local')));
end
remote_source = read_text(fullfile(root_dir, 'src', 'backends', 'shared', ...
    'run_normalization_cmd.m'));
assert(~isempty(strfind(remote_source, 'setenv LD_LIBRARY_PATH')));
assert(~isempty(strfind(remote_source, 'tcsh -f -c')));

assert(~isempty(strfind(generate_source, 'env -u LD_LIBRARY_PATH')));
assert(~isempty(strfind(generate_source, 'tcsh -f -c')));
assert(~isempty(strfind(generate_source, '.mlsc_progress')));
lifecycle_source = read_text(fullfile(root_dir, 'src', 'backends', 'mlsc', ...
    'mlsc_lifecycle.m'));
assert(~isempty(strfind(lifecycle_source, 'att_map.nii')));
progress_source = read_text(fullfile(root_dir, 'src', 'backends', 'mlsc', ...
    'mlsc_progress.m'));
assert(~isempty(strfind(progress_source, '.mlsc_progress')));

r2010b_files = {fullfile(root_dir, 'src', 'config', 'pseudo_CT_load_profile.m'); ...
    fullfile(root_dir, 'src', 'config', 'pseudo_CT_list_profiles.m'); ...
    fullfile(root_dir, 'src', 'gui', 'pseudo_CT_profile_selector.m'); ...
    fullfile(root_dir, 'src', 'gui', 'pseudo_CT_profile_selector_layout.m'); ...
    fullfile(root_dir, 'src', 'gui', 'pseudo_CT_prepare_profile_choices.m'); ...
    fullfile(root_dir, 'run_pseudo_CT.m'); ...
    fullfile(root_dir, 'src', 'backends', 'shared', 'run_normalization_cmd.m'); ...
    fullfile(root_dir, 'src', 'config', 'profiles', 'local_current.m')};
for ii = 1:length(r2010b_files)
    seam_source = read_text(r2010b_files{ii});
    assert(isempty(strfind(seam_source, 'strjoin(')));
    assert(isempty(strfind(seam_source, 'addParameter')));
    assert(isempty(strfind(seam_source, 'string(')));
end

fprintf(['Profile authority tests passed: %d dynamically discovered profiles, ', ...
    'mode-conditional schemas/resources, exact MLSC policies and metadata, ', ...
    'metadata-driven ordering, local/MLSC compatibility, bone and FWHM ', ...
    'consumption, enabled operation defaults, aliasing root uniform, ', ...
    'runtime path boundary intact.\n'], ...
    length(profiles));
end

function files = collect_m_files(directory)
files = {};
entries = dir(directory);
for ii = 1:length(entries)
    if entries(ii).isdir
        if ~strcmp(entries(ii).name, '.') && ~strcmp(entries(ii).name, '..')
            files = [files; collect_m_files(fullfile(directory, entries(ii).name))]; %#ok<AGROW>
        end
    elseif length(entries(ii).name) > 2 && ...
            strcmp(entries(ii).name(end-1:end), '.m')
        files{end+1, 1} = fullfile(directory, entries(ii).name); %#ok<AGROW>
    end
end
end

function text = read_text(path_name)
fid = fopen(path_name, 'r');
if fid == -1
    error('test_profile_authority:Read', 'Could not read %s.', path_name);
end
text = fread(fid, inf, '*char')';
fclose(fid);
end

function code = local_strip_matlab_comments(source)
%LOCAL_STRIP_MATLAB_COMMENTS Remove %-to-end-of-line comments (string-aware).
%   Keeps code and single-quoted string literals so executable references to
%   maintainer paths still trip the boundary check; drops comment prose.
%   R2010b-safe char-only.
code = '';
lines = regexp(source, '\r\n|\n|\r', 'split');
for kk = 1:numel(lines)
    line = lines{kk};
    out = '';
    in_str = false;
    ii = 1;
    while ii <= length(line)
        ch = line(ii);
        if in_str
            out(end + 1) = ch; %#ok<AGROW>
            if ch == char(39)
                if ii < length(line) && line(ii + 1) == char(39)
                    out(end + 1) = char(39); %#ok<AGROW>
                    ii = ii + 1;
                else
                    in_str = false;
                end
            end
        else
            if ch == char(39)
                in_str = true;
                out(end + 1) = ch; %#ok<AGROW>
            elseif ch == '%'
                break;
            else
                out(end + 1) = ch; %#ok<AGROW>
            end
        end
        ii = ii + 1;
    end
    if kk > 1
        code = [code char(10)]; %#ok<AGROW>
    end
    code = [code out]; %#ok<AGROW>
end
end

function restore_path(old_path)
path(old_path);
end

function value = local_without_policy(config)
value = rmfield(config, {'io_policy'; 'compatibility_profile'; 'presentation'});
end

function index = local_config_index(names, requested)
index = find(strcmp(names, requested), 1);
assert(~isempty(index), 'Expected profile was not discovered: %s', requested);
end

function config = local_resource_fixture(config, root_dir, mode_name)
config.spm_root = fullfile(root_dir, 'spm');
config.atlas_root = fullfile(root_dir, 'atlas');
config.d2n_root = fullfile(root_dir, 'd2n');
config.aliasing_root = fullfile(root_dir, 'aliasing');
local_mkdir(config.spm_root);
local_mkdir(fullfile(config.spm_root, 'matlabbatch'));
local_mkdir(config.atlas_root);
local_mkdir(config.d2n_root);
local_mkdir(config.aliasing_root);

if strcmp(mode_name, 'mlsc')
    config.mlsc.shell = '/bin/bash';
    config.mlsc.freesurfer_env = fullfile(root_dir, 'mlsc_freesurfer_env');
    config.mlsc.host = 'mlsc.nmr.mgh.harvard.edu';
    config.mlsc.partition = 'basic';
    config.mlsc.nodes = 1;
    config.mlsc.ntasks = 1;
    config.mlsc.cpus_per_task = 1;
    config.mlsc.memory = '1G';
    config.mlsc.time = '00:01:00';
    local_write(config.mlsc.freesurfer_env, '#!/bin/bash\n');
end
end

function local_mkdir(directory)
if exist(directory, 'dir') ~= 7
    mkdir(directory);
end
end

function text = local_read(file_path)
fid = fopen(file_path, 'r');
assert(fid ~= -1);
text = fread(fid, inf, '*char')';
fclose(fid);
end

function local_write(file_path, text)
fid = fopen(file_path, 'w');
assert(fid ~= -1);
fwrite(fid, text);
fclose(fid);
end

function local_cleanup(directory)
if exist(directory, 'dir') == 7
    rmdir(directory, 's');
end
end
