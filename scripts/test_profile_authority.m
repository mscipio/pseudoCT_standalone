function test_profile_authority()
%TEST_PROFILE_AUTHORITY Verify the simple dynamic profile system.

scripts_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(scripts_dir);
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

% Active discovery is top-level only: profiles/deprecated/ is excluded.
deprecated_dir = fullfile(profile_dir, 'deprecated');
deprecated_files = dir(fullfile(deprecated_dir, '*.m'));
assert(length(deprecated_files) == 3);
deprecated_names = {'launchpad'; 'launchpad-mprage-only'; ...
    'local-near-parity-r2010b'};
for ii = 1:length(deprecated_names)
    assert(~ismember(deprecated_names{ii}, names));
end
for ii = 1:length(profiles)
    assert(isempty(strfind(profiles(ii).file_path, 'deprecated')));
    assert(strcmp(fileparts(profiles(ii).file_path), profile_dir));
end
% T005 narrow update: canonical set grows 6 -> 7 with mlsc-current only.
% Launchpad restoration: canonical set grows 7 -> 8 with launchpad-legacy only.
expected_active = {'devel'; 'launchpad-legacy'; 'local-current'; 'local-legacy'; ...
    'local-mprage-only'; 'mlsc-current'; 'mlsc-legacy'; 'mlsc-mprage-only'};
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
assert(strcmp(ordered_profiles(default_index).name, 'local-current'));
ordered_group_rank = 1 + strcmp({ordered_profiles.group}, 'specialized');
for ii = 2:length(ordered_profiles)
    assert(ordered_group_rank(ii) >= ordered_group_rank(ii - 1));
    if ordered_group_rank(ii) == ordered_group_rank(ii - 1)
        assert(ordered_profiles(ii).order >= ordered_profiles(ii - 1).order);
    end
end
without_local = profiles(~strcmp({profiles.name}, 'local-current'));
[without_local, fallback_index] = pseudo_CT_prepare_profile_choices(without_local);
assert(without_local(fallback_index).recommended);
assert(strcmp(without_local(fallback_index).group, 'recommended'));
assert(~strcmp(ordered_profiles(1).display_name, ordered_profiles(1).name));
local = configs{local_config_index(names, 'local-current')};
local_mprage = configs{local_config_index(names, 'local-mprage-only')};
mlsc = configs{local_config_index(names, 'mlsc-legacy')};
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
assert(strcmp(mlsc.presentation.group, 'recommended'));
assert(mlsc.presentation.recommended);
assert(~isempty(strfind(lower(mlsc.presentation.display_name), 'mlsc')));
% T013 narrow correction: active MLSC wording uses legacy-compiled-backend
% and cluster phrasing (no runtime change).
assert(~isempty(strfind(lower(mlsc.presentation.display_name), 'legacy')));
assert(~isempty(strfind(lower(mlsc.presentation.description), 'cluster')));
% Presentation update: launchpad-legacy moves to recommended last (order 80
% unchanged). Identity/mode/implementation untouched; default stays
% local-current via the explicit lookup in pseudo_CT_prepare_profile_choices
% (verified at the ordering asserts above), never first-recommended fallback.
launchpad_legacy = configs{local_config_index(names, 'launchpad-legacy')};
assert(strcmp(launchpad_legacy.mode, 'launchpad'));
assert(strcmp(launchpad_legacy.implementation, 'legacy-v2'));
assert(strcmp(launchpad_legacy.presentation.display_name, ...
    'LAUNCHPAD - Legacy v2.0 (Aether)'));
assert(strcmp(launchpad_legacy.presentation.description, ...
    'Remote pseudoCT processing using Aether v2.0.'));
assert(isempty(strfind(launchpad_legacy.presentation.description, char(10))));
assert(strcmp(launchpad_legacy.presentation.group, 'recommended'));
assert(launchpad_legacy.presentation.recommended);
assert(~strcmp(ordered_profiles(default_index).name, 'launchpad-legacy'));
assert(strcmp(mlsc_mprage.io_policy.reference, 'none'));
assert(strcmp(mlsc_mprage.io_policy.output, 'nifti-only'));
assert(strcmp(mlsc_mprage.io_policy.gui, 'mprage-only'));
assert(strcmp(mlsc_mprage.compatibility_profile, 'mlsc'));
assert(strcmp(mlsc_mprage.presentation.group, 'specialized'));
assert(~mlsc_mprage.presentation.recommended);
% T013 narrow correction: active MPRAGE-only wording names the modality
% (specialized/not-recommended is already covered by group/recommended).
assert(~isempty(strfind(lower(mlsc_mprage.presentation.description), ...
    'mprage')));
assert(~isfield(mlsc, 'launchpad'));
assert(~isfield(mlsc_mprage, 'launchpad'));
assert(isfield(mlsc, 'mlsc') && isfield(mlsc_mprage, 'mlsc'));
assert(strcmp(mlsc.mlsc.host, 'mlsc.nmr.mgh.harvard.edu'));
assert(strcmp(mlsc.mlsc.shell, '/bin/bash'));
assert(strcmp(mlsc.mlsc.runner, mlsc_mprage.mlsc.runner));
assert(strcmp(mlsc.mlsc.defaults_mat, mlsc_mprage.mlsc.defaults_mat));
assert(strcmp(mlsc.mlsc.batch_templates, mlsc_mprage.mlsc.batch_templates));
assert(strcmp(mlsc.mlsc.freesurfer_env, mlsc_mprage.mlsc.freesurfer_env));
assert(strcmp(mlsc.normalization.host, mlsc.mlsc.host));
assert(strcmp(mlsc.normalization.cluster, 'Yes'));
assert(isequal(mlsc.pca_order, {'remote'}));
assert(strcmp(mlsc_mprage.normalization.host, mlsc_mprage.mlsc.host));
assert(strcmp(mlsc_mprage.normalization.cluster, 'Yes'));
assert(isequal(mlsc_mprage.pca_order, {'remote'}));

% Resource setup follows the selected mode only. The fixture intentionally
% leaves unrelated mode resources absent, so validating every backend would
% fail this check.
resource_root = tempname;
mkdir(resource_root);
resource_cleanup = onCleanup(@() local_cleanup(resource_root)); %#ok<NASGU>
local_fixture = local_resource_fixture(local, resource_root, 'local');
setup_pseudo_CT_paths(root_dir, local_fixture);
mlsc_fixture = local_resource_fixture(mlsc, resource_root, 'mlsc');
mlsc_fixture.launchpad = struct('runner', fullfile(resource_root, ...
    'missing-launchpad-runner'));
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
    local_without_policy(mlsc)));

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
selector_source = read_text(fullfile(root_dir, 'src', 'ui', ...
    'pseudo_CT_profile_selector.m'));
atlas_source = read_text(fullfile(root_dir, 'src', 'core', ...
    'atlas_based_attenuation_map.m'));
compute_source = read_text(fullfile(root_dir, 'src', 'core', ...
    'pseudo_CT_current_compute.m'));
launchpad_source = read_text(fullfile(root_dir, 'src', 'launchpad', ...
    'batch_pseudo_CT_launchpad.m'));
assert(~isempty(strfind(entry_source, 'switch config.mode')));
assert(isempty(strfind(selector_source, 'listdlg')));
assert(~isempty(strfind(selector_source, '''Style'', ''radiobutton''')));
assert(~isempty(strfind(selector_source, 'pseudo_CT_profile_selector_layout')));
assert(~isempty(strfind(selector_source, '''Style'', ''slider''')));
assert(~isempty(strfind(selector_source, 'profiles(selected_index).name')));
assert(length(strfind(entry_source, 'config.fwhm')) >= 2);
% Shared-boundary refactor: post-normalization computation (bone gate,
% background policy, MNI alignment) lives in pseudo_CT_current_compute;
% atlas_based_attenuation_map stays a thin prepare/normalize/compute facade.
assert(~isempty(strfind(compute_source, 'if config.bone_enabled')));
assert(~isempty(strfind(compute_source, 'config.zero_background')));
assert(~isempty(strfind(compute_source, ...
    'move_image_2_MNI(P_orig, fullfile(dir_batch_templates, ''ch2.nii''), ...')));
assert(~isempty(strfind(launchpad_source, 'config.launchpad.runner')));
assert(isempty(strfind(launchpad_source, 'pseudo_CT_load_profile')));

% Active runtime files are independent of repository-only maintainer and
% compatibility content. Keep this assertion at the source boundary so a
% future path refactor cannot accidentally make the pipeline depend on an
% archive-excluded directory.
runtime_files = [{fullfile(root_dir, 'run_pseudo_CT.m')}; ...
    collect_m_files(fullfile(root_dir, 'src'))];
for ii = 1:length(runtime_files)
    runtime_source = read_text(runtime_files{ii});
    assert(isempty(strfind(runtime_source, 'Makefile')));
    assert(isempty(strfind(runtime_source, 'scripts/')));
    assert(isempty(strfind(runtime_source, 'docs/')));
    assert(isempty(strfind(runtime_source, 'deprecated/')));
end

% --- Aliasing regression checks (T003) ---
% Production/release profiles must use the canonical shared-filesystem path.
canonical_aliasing_root = ['/usr/pubsw/packages/mrpet/standalone_apps/' ...
    'correct_aliasing/correct_aliasing_standalone-latest'];
% T005 narrow update: mlsc-current uses the same canonical aliasing root.
production_names = {'local-current', 'local-legacy', 'local-mprage-only', ...
    'mlsc-current', 'mlsc-legacy', 'mlsc-mprage-only'};
for ii = 1:length(production_names)
    idx = find(strcmp(names, production_names{ii}), 1);
    assert(~isempty(idx));
    assert(strcmp(configs{idx}.aliasing_root, canonical_aliasing_root), ...
        sprintf('Profile %s aliasing_root mismatch', production_names{ii}));
end

% The devel profile intentionally uses a development path for local testing.
devel_aliasing_root = '/autofs/cluster/catanagp/users/mscipioni/Biograph_mMR/piano_mMR_devel/correct_aliasing_standalone';
devel_idx = find(strcmp(names, 'devel'), 1);
assert(~isempty(devel_idx));
assert(strcmp(configs{devel_idx}.aliasing_root, devel_aliasing_root), ...
    'devel profile aliasing_root must use development path');
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
assert(~isempty(strfind(setup_source, ...
    'strcmp(config.mode, ''launchpad'')')));

deprecated_nose = fullfile(root_dir, 'deprecated', ...
    'automatic_anti_aliasing_nose_2_back.m');
deprecated_center = fullfile(root_dir, 'deprecated', ...
    'center_subject_in_image.m');
deprecated_converter = fullfile(root_dir, 'deprecated', ...
    'convert_dicom_i_2_nii.m');
active_nose = fullfile(root_dir, 'src', 'core', ...
    'automatic_anti_aliasing_nose_2_back.m');
active_center = fullfile(root_dir, 'src', 'core', ...
    'center_subject_in_image.m');
assert(exist(deprecated_nose, 'file') == 2);
assert(exist(deprecated_center, 'file') == 2);
assert(exist(deprecated_converter, 'file') == 2);
assert(exist(active_nose, 'file') ~= 2);
assert(exist(active_center, 'file') ~= 2);

legacy_entrypoints = {fullfile(root_dir, 'run_pseudo_CT_local.m'); ...
    fullfile(root_dir, 'run_pseudo_CT_launchpad.m'); ...
    fullfile(root_dir, 'deprecated', 'run_pseudo_CT_local.m'); ...
    fullfile(root_dir, 'deprecated', 'run_pseudo_CT_launchpad.m')};
for ii = 1:length(legacy_entrypoints)
    assert(exist(legacy_entrypoints{ii}, 'file') ~= 2);
end

% Shared boundary (pre-facade): the local path still performs aliasing
% correction directly in the facade; the new prepare helper owns the same
% contract for the mlsc-current path. No facade delegation yet (out of scope).
prepare_check = read_text(fullfile(root_dir, 'src', 'core', ...
    'pseudo_CT_current_prepare.m'));
assert(~isempty(strfind(prepare_check, 'result = correct_aliasing(')));
assert(~isempty(strfind(atlas_source, 'result = correct_aliasing(')));
assert(isempty(strfind(entry_source, 'correct_aliasing(')));
assert(~isempty(strfind(entry_source, '''check_aliasing''')));
assert(~isempty(strfind(launchpad_source, 'check_aliasing')));

% --- T009 focused 2x2 architecture/parity/isolation checks (no live backend) ---
list_source = read_text(fullfile(root_dir, 'src', 'config', ...
    'pseudo_CT_list_profiles.m'));
assert(~isempty(strfind(list_source, 'dir(fullfile(profile_dir, ''*.m''))')));
% T005 narrow update: seven primary profiles (adds mlsc-current only).
% Launchpad restoration: eight grows 7 -> 8 with launchpad-legacy only.
assert(length(files) == 8);
assert(exist(fullfile(profile_dir, 'mlsc.m'), 'file') ~= 2);
assert(~ismember('mlsc', names));

% T005 narrow update: mlsc-current joins the canonical set.
% Launchpad restoration: launchpad-legacy joins the canonical set (accepted);
% bare 'launchpad' stays rejected (deprecated, no discovery row).
canonical_names = {'local-current'; 'local-legacy'; 'mlsc-current'; ...
    'mlsc-legacy'; 'local-mprage-only'; 'mlsc-mprage-only'; 'devel'; ...
    'launchpad-legacy'};
for ii = 1:length(canonical_names)
    resolved = pseudo_CT_load_profile(canonical_names{ii}, config_root);
    assert(isstruct(resolved) && numel(resolved) == 1);
end
aliased = pseudo_CT_load_profile('mlsc', config_root);
assert(isequal(aliased, configs{local_config_index(names, 'mlsc-legacy')}));

loader_source = read_text(fullfile(root_dir, 'src', 'config', ...
    'pseudo_CT_load_profile.m'));
assert(~isempty(strfind(loader_source, 'strcmp(trimmed, ''mlsc'')')));
assert(~isempty(strfind(loader_source, 'trimmed = ''mlsc-legacy''')));
assert(~isempty(strfind(entry_source, 'strcmp(requested, ''mlsc'')')));
assert(~isempty(strfind(entry_source, 'requested = ''mlsc-legacy''')));

% T005 narrow update: mlsc-current is now a valid canonical profile.
% Launchpad restoration: launchpad-legacy is accepted via canonical_names above;
% the bare deprecated 'launchpad' key stays rejected (no discovery row).
rejected_fixed = {'launchpad'; 'launchpad-mprage-only'; ...
    'local-near-parity-r2010b'};
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
% T005 narrow update: mlsc-current is now accepted at the entrypoint.
entrypoint_rejected = {'launchpad'; ...
    'local-near-parity-r2010b'; 'local_current'; ...
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
    assert(ismember(configs{ii}.mode, {'local'; 'mlsc'; 'launchpad'}));
    assert(ismember(configs{ii}.implementation, {'current'; 'legacy-v2'}));
    assert(~strcmp(configs{ii}.mode, 'legacy'));
    assert(~strcmp(configs{ii}.implementation, 'mlsc'));
    % T005 narrow update: exactly one mlsc+current cell (mlsc-current).
    if strcmp(configs{ii}.implementation, 'current') && ...
            strcmp(configs{ii}.mode, 'mlsc')
        assert(strcmp(profiles(ii).name, 'mlsc-current'));
    end
end
local_current_cfg = configs{local_config_index(names, 'local-current')};
local_legacy_cfg = configs{local_config_index(names, 'local-legacy')};
mlsc_current_cfg = configs{local_config_index(names, 'mlsc-current')};
mlsc_legacy_cfg = configs{local_config_index(names, 'mlsc-legacy')};
assert(strcmp(local_current_cfg.mode, 'local'));
assert(strcmp(local_current_cfg.implementation, 'current'));
assert(strcmp(local_legacy_cfg.mode, 'local'));
assert(strcmp(local_legacy_cfg.implementation, 'legacy-v2'));
assert(strcmp(mlsc_current_cfg.mode, 'mlsc'));
assert(strcmp(mlsc_current_cfg.implementation, 'current'));
assert(strcmp(mlsc_legacy_cfg.mode, 'mlsc'));
assert(strcmp(mlsc_legacy_cfg.implementation, 'legacy-v2'));
% T005 narrow update: current/legacy namespaces stay separate.
assert(~isfield(mlsc_current_cfg, 'legacy'));
assert(isfield(mlsc_current_cfg, 'current'));
assert(~isfield(local_current_cfg, 'current'));
assert(~isfield(local_legacy_cfg, 'current'));
assert(~isfield(mlsc_legacy_cfg, 'current'));

% --- T014 pinned-MCR authority (fail-closed pre-Gate-A) ---
% T014 is authoritative over stale T004 catalog/resolver wording: the only
% accepted MCR_ROOT is the pinned version-specific tree (never the current
% symlink), bound by SHA-256 runner identity plus build/resource manifests
% carrying the T007-pending native marker. Loader, setup, and validator
% own disjoint pieces of one contract; execution stays fail-closed.
t014_pinned = '/usr/pubsw/common/matlab/26.1';
assert(strcmp(mlsc_current_cfg.current.mcr_root, t014_pinned));
assert(strcmp(mlsc_current_validate('pinned_mcr_root'), t014_pinned));
assert(isfield(mlsc_current_cfg.current, 'build_manifest'));
assert(isfield(mlsc_current_cfg.current, 'resource_manifest'));
assert(isfield(mlsc_current_cfg.current, 'required_outputs'));
assert(ismember('att_map.nii', mlsc_current_cfg.current.required_outputs));
assert(ismember('Fusion_MR_Pseudo_CT_validation.tiff', ...
    mlsc_current_cfg.current.required_outputs));
assert(ismember('Pseudo_CT_AC_Version.txt', ...
    mlsc_current_cfg.current.required_outputs));
t014_profile = read_text(fullfile(profile_dir, 'mlsc_current.m'));
assert(~isempty(strfind(t014_profile, 'Gate A has NOT occurred')));
assert(~isempty(strfind(t014_profile, 'never the current symlink')));
t014_loader = read_text(fullfile(root_dir, 'src', 'config', ...
    'pseudo_CT_load_profile.m'));
assert(~isempty(strfind(t014_loader, ...
    'function validate_current(current, mlsc, profile_name)')));
assert(~isempty(strfind(t014_loader, '/usr/pubsw/common/matlab/26.1')));
assert(~isempty(strfind(t014_loader, ...
    'config.current.mcr_root must be the pinned')));
t014_setup = read_text(fullfile(root_dir, 'src', 'config', ...
    'setup_pseudo_CT_paths.m'));
assert(~isempty(strfind(t014_setup, 'local_validate_current_setup(config)')));
assert(~isempty(strfind(t014_setup, 'must not carry a legacy block')));
t014_validate = read_text(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_current_validate.m'));
assert(~isempty(strfind(t014_validate, '/usr/pubsw/common/matlab/26.1')));
assert(~isempty(strfind(t014_validate, 'runner_checksum')));
assert(~isempty(strfind(t014_validate, 'SHA-256')));
assert(~isempty(strfind(t014_validate, ...
    't007-gate-a-pending: existence-only; production loadability evidence comes later')));
% Fail-closed pre-Gate-A on the real (artifact-absent) profile: contract
% and execution validation both reject without simulating success.
t014_contract_failed = false;
try
    mlsc_current_validate('validate_contract', mlsc_current_cfg);
catch ME
    t014_contract_failed = strncmp(ME.identifier, 'pseudo_CT:MLSC', ...
        length('pseudo_CT:MLSC'));
end
assert(t014_contract_failed);
t014_exec_failed = false;
try
    mlsc_current_validate('validate_for_execution', mlsc_current_cfg);
catch ME
    t014_exec_failed = strncmp(ME.identifier, 'pseudo_CT:MLSC', ...
        length('pseudo_CT:MLSC'));
end
assert(t014_exec_failed);
t014_preflight = read_text(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_preflight.m'));
assert(~isempty(strfind(t014_preflight, ...
    'mlsc_current_validate(''validate_contract''')));
t014_backend = read_text(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_backend.m'));
assert(~isempty(strfind(t014_backend, ...
    'mlsc_current_validate(''validate_for_execution''')));
% CURRENT PREPARE->normalize->COMPUTE: prepare owns alias/recenter before
% the external FreeSurfer boundary; compute runs only on verified
% normalized output. The payload enters prepare before compute, never
% reversed.
t014_payload = read_text(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_current_payload.m'));
t014_prepare_pos = strfind(t014_payload, '= pseudo_CT_current_prepare(');
t014_compute_pos = strfind(t014_payload, '= pseudo_CT_current_compute(');
assert(length(t014_prepare_pos) == 1 && length(t014_compute_pos) == 1 && ...
    t014_prepare_pos(1) < t014_compute_pos(1));
assert(~isempty(strfind(t014_payload, 'Verified normalized input missing')));

assert(isfield(local_legacy_cfg, 'legacy'));
assert(isfield(mlsc_legacy_cfg, 'legacy'));
assert(isfield(mlsc_legacy_cfg, 'mlsc'));
assert(~isfield(local_legacy_cfg, 'mlsc'));
assert(strcmp(local_legacy_cfg.legacy.runner, mlsc_legacy_cfg.legacy.runner));
assert(strcmp(local_legacy_cfg.legacy.mcr_root, mlsc_legacy_cfg.legacy.mcr_root));
assert(strcmp(local_legacy_cfg.legacy.defaults_mat, ...
    mlsc_legacy_cfg.legacy.defaults_mat));
assert(strcmp(local_legacy_cfg.legacy.batch_templates, ...
    mlsc_legacy_cfg.legacy.batch_templates));
assert(strcmp(local_legacy_cfg.legacy.att_map, ...
    mlsc_legacy_cfg.legacy.att_map));
assert(strcmp(local_legacy_cfg.legacy.att_map, 'att_map.nii'));
assert(strcmp(mlsc_legacy_cfg.legacy.runner, mlsc_legacy_cfg.mlsc.runner));
assert(strcmp(mlsc_legacy_cfg.legacy.mcr_root, mlsc_legacy_cfg.mlsc.mcr_root));
assert(strcmp(mlsc_legacy_cfg.legacy.defaults_mat, ...
    mlsc_legacy_cfg.mlsc.defaults_mat));
assert(strcmp(mlsc_legacy_cfg.legacy.batch_templates, ...
    mlsc_legacy_cfg.mlsc.batch_templates));
assert(strcmp(mlsc_legacy_cfg.mlsc.host, 'mlsc.nmr.mgh.harvard.edu'));
assert(strcmp(mlsc_legacy_cfg.mlsc.shell, '/bin/bash'));
assert(strcmp(mlsc_legacy_cfg.mlsc.partition, 'basic'));
assert(strcmp(local_legacy_cfg.aliasing_root, mlsc_legacy_cfg.aliasing_root));
assert(strcmp(local_legacy_cfg.atlas_root, mlsc_legacy_cfg.atlas_root));
assert(isequal(local_legacy_cfg.pca_order, mlsc_legacy_cfg.pca_order));
assert(strcmp(local_legacy_cfg.normalization.source_command, ...
    mlsc_legacy_cfg.normalization.source_command));
helper_source = read_text(fullfile(root_dir, 'src', 'core', ...
    'pseudo_CT_run_local_legacy_subject.m'));
assert(~isempty(strfind(helper_source, 'env -u LD_LIBRARY_PATH')));
assert(~isempty(strfind(helper_source, 'tcsh -f -c')));
assert(~isempty(strfind(helper_source, 'mri_normalize')));
assert(~isempty(strfind(helper_source, 'local_shell_quote')));
assert(~isempty(strfind(helper_source, 'legacy_att')));
assert(~isempty(strfind(helper_source, ''' 0 ''')));
assert(~isempty(strfind(helper_source, 'num2str(check_aliasing)')));
assert(~isempty(strfind(helper_source, 'config.legacy.runner')));
assert(~isempty(strfind(helper_source, 'config.legacy.att_map')));
assert(isempty(strfind(helper_source, 'config.mlsc')));
local_legacy_source = read_text(fullfile(root_dir, 'src', 'config', ...
    'profiles', 'local_legacy.m'));
assert(isempty(strfind(local_legacy_source, 'config.mlsc')));
assert(~isempty(strfind(local_legacy_source, 'config.legacy.runner')));
assert(~isempty(strfind(local_legacy_source, 'config.legacy.att_map')));
assert(~isempty(strfind(local_legacy_source, 'att_map.nii')));
generate_source = read_text(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_generate_slurm_script.m'));
assert(~isempty(strfind(generate_source, ''' 0 ''')));
assert(~isempty(strfind(generate_source, 'num2str(check_aliasing)')));
assert(~isempty(strfind(generate_source, 'att_map.nii')));
assert(~isempty(strfind(generate_source, 'config.mlsc')));
assert(~isempty(strfind(generate_source, 'mlsc.freesurfer_env')));

assert(isempty(strfind(helper_source, 'glnxa64')));
assert(isempty(strfind(helper_source, 'setenv')));
assert(isempty(strfind(helper_source, 'export')));
assert(isempty(strfind(helper_source, 'LD_LIBRARY_PATH=')));
lower_helper = lower(helper_source);
isolation_forbidden = {'passwordentrydialog'; 'ganymed'; 'ssh'; 'scp'; ...
    'sbatch'; 'squeue'; 'sacct'; 'mlsc_backend'; 'mlsc_lifecycle'; ...
    'mlsc_progress'; 'mlsc_evidence'; 'preflight'; 'generate_slurm'; ...
    '.mlsc_progress'};
for ii = 1:length(isolation_forbidden)
    assert(isempty(strfind(lower_helper, isolation_forbidden{ii})));
end
mlsc_dir_files = dir(fullfile(root_dir, 'src', 'mlsc', '*.m'));
assert(~isempty(mlsc_dir_files));
for ii = 1:length(mlsc_dir_files)
    assert(isempty(strfind(lower(mlsc_dir_files(ii).name), 'local')));
end
assert(exist(fullfile(root_dir, 'src', 'core', ...
    'pseudo_CT_run_local_legacy_subject.m'), 'file') == 2);
% Intentional divergence (not a failure): the historical local-current path
% keeps its setenv-prepend model in run_normalization_cmd, while the new
% local-legacy helper uses isolated env -u. Both are pinned against drift.
remote_source = read_text(fullfile(root_dir, 'src', 'remote', ...
    'run_normalization_cmd.m'));
assert(~isempty(strfind(remote_source, 'setenv LD_LIBRARY_PATH')));
assert(~isempty(strfind(remote_source, 'tcsh -f -c')));

assert(~isempty(strfind(generate_source, 'env -u LD_LIBRARY_PATH')));
assert(~isempty(strfind(generate_source, 'tcsh -f -c')));
assert(~isempty(strfind(generate_source, '.mlsc_progress')));
lifecycle_source = read_text(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_lifecycle.m'));
assert(~isempty(strfind(lifecycle_source, 'att_map.nii')));
progress_source = read_text(fullfile(root_dir, 'src', 'mlsc', ...
    'mlsc_progress.m'));
assert(~isempty(strfind(progress_source, '.mlsc_progress')));

r2010b_files = {fullfile(root_dir, 'src', 'core', ...
    'pseudo_CT_run_local_legacy_subject.m'); ...
    fullfile(root_dir, 'src', 'config', 'pseudo_CT_load_profile.m'); ...
    fullfile(root_dir, 'src', 'config', 'pseudo_CT_list_profiles.m'); ...
    fullfile(root_dir, 'src', 'ui', 'pseudo_CT_profile_selector.m'); ...
    fullfile(root_dir, 'src', 'ui', 'pseudo_CT_profile_selector_layout.m'); ...
    fullfile(root_dir, 'src', 'ui', 'pseudo_CT_prepare_profile_choices.m'); ...
    fullfile(root_dir, 'run_pseudo_CT.m'); ...
    fullfile(root_dir, 'src', 'remote', 'run_normalization_cmd.m'); ...
    fullfile(root_dir, 'src', 'config', 'profiles', 'local_legacy.m'); ...
    fullfile(root_dir, 'src', 'config', 'profiles', 'mlsc_legacy.m'); ...
    fullfile(root_dir, 'src', 'config', 'profiles', 'local_current.m')};
for ii = 1:length(r2010b_files)
    seam_source = read_text(r2010b_files{ii});
    assert(isempty(strfind(seam_source, 'strjoin(')));
    assert(isempty(strfind(seam_source, 'addParameter')));
    assert(isempty(strfind(seam_source, 'string(')));
end

% --- T009 F2 local-legacy behavioral fixture (non-live, deterministic) ---
% Fake local commands and artifacts prove behavior, not source strings:
% spaced paths exercise POSIX single-quote handling through real system
% calls; nonzero runner exit and success-but-missing att_map both reject.
% dcm2nii is shadowed with a fixture copy stub, mri_normalize is a fake
% PATH executable, and each runner is a fixture shell script. nifti-only
% plus no-cleanup isolates runner and verification without live DICOM
% work; production nifti-and-dicom parity is asserted separately above.
% R2010b-safe char-only.
local_legacy_behavioral_fixture(local_legacy_cfg);

fprintf(['Profile authority tests passed: %d dynamically discovered profiles, ', ...
    'mode-conditional schemas/resources, exact MLSC policies and metadata, ', ...
    'metadata-driven ordering, local/MLSC compatibility, bone and FWHM ', ...
    'consumption, enabled operation defaults, aliasing root uniform, ', ...
    'deprecated helpers retained, obsolete entrypoints absent, runtime path ', ...
    'boundary and Launchpad delegation intact.\n'], ...
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
    if isfield(config, 'launchpad')
        config = rmfield(config, 'launchpad');
    end
    config.mlsc.runner = fullfile(root_dir, 'mlsc_runner.sh');
    config.mlsc.mcr_root = fullfile(root_dir, 'mlsc_mcr');
    config.mlsc.defaults_mat = fullfile(root_dir, 'mlsc_defaults.mat');
    config.mlsc.batch_templates = fullfile(root_dir, 'mlsc_batch');
    config.mlsc.shell = '/bin/bash';
    config.mlsc.freesurfer_env = fullfile(root_dir, 'mlsc_freesurfer_env');
    config.mlsc.host = 'mlsc.nmr.mgh.harvard.edu';
    config.mlsc.partition = 'basic';
    config.mlsc.nodes = 1;
    config.mlsc.ntasks = 1;
    config.mlsc.cpus_per_task = 1;
    config.mlsc.memory = '1G';
    config.mlsc.time = '00:01:00';
    local_mkdir(config.mlsc.mcr_root);
    local_mkdir(config.mlsc.batch_templates);
    local_write(config.mlsc.runner, '#!/bin/bash\n');
    local_write(config.mlsc.defaults_mat, 'fixture');
    local_write(config.mlsc.freesurfer_env, '#!/bin/bash\n');
elseif strcmp(mode_name, 'launchpad')
    if isfield(config, 'mlsc')
        config = rmfield(config, 'mlsc');
    end
    config.launchpad.runner = fullfile(root_dir, 'launchpad_runner.sh');
    config.launchpad.mcr_root = fullfile(root_dir, 'launchpad_mcr');
    config.launchpad.defaults_mat = fullfile(root_dir, 'launchpad_defaults.mat');
    config.launchpad.batch_templates = fullfile(root_dir, 'launchpad_batch');
    config.launchpad.host = 'fixture-launchpad';
    config.launchpad.scratch = fullfile(root_dir, 'launchpad_scratch');
    local_mkdir(config.launchpad.mcr_root);
    local_mkdir(config.launchpad.batch_templates);
    local_mkdir(config.launchpad.scratch);
    local_write(config.launchpad.runner, '#!/bin/bash\n');
    local_write(config.launchpad.defaults_mat, 'fixture');
else
    if isfield(config, 'launchpad')
        config = rmfield(config, 'launchpad');
    end
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

function local_legacy_behavioral_fixture(base_config)
fixture_root = [tempname ' with space'];
mkdir(fixture_root);
fixture_cleanup = onCleanup(@() local_cleanup(fixture_root)); %#ok<NASGU>
stub_dir = fullfile(fixture_root, 'stub dir');
fake_bin = fullfile(fixture_root, 'fake bin');
fixture_data = fullfile(fixture_root, 'fixture data with space');
local_mkdir(stub_dir);
local_mkdir(fake_bin);
local_mkdir(fixture_data);
local_write(fullfile(stub_dir, 'dcm2nii.m'), ...
    ['function out_path = dcm2nii(in_path, out_path, varargin)' char(10) ...
     'if ~ischar(in_path) || ~ischar(out_path)' char(10) ...
     'error(''fixture:InvalidPath'', ''paths must be char'');' char(10) ...
     'end' char(10) ...
     '[copy_ok, copy_msg] = copyfile(in_path, out_path, ''f'');' char(10) ...
     'if ~copy_ok' char(10) ...
     'error(''fixture:CopyFailed'', ''copy failed: %s'', copy_msg);' char(10) ...
     'end' char(10) 'end' char(10)]);
local_write(fullfile(fake_bin, 'mri_normalize'), ...
    ['#!/bin/bash' char(10) ...
     'printf ''%s\n'' "$1" >> "$LOCAL_LEGACY_FS_LOG"' char(10) ...
     'printf ''%s\n'' "$2" >> "$LOCAL_LEGACY_FS_LOG"' char(10) ...
     'cp -- "$1" "$2"' char(10)]);
mcr_dir = fullfile(fixture_data, 'mcr root with space');
batch_dir = fullfile(fixture_data, 'batch templates with space');
atlas_dir = fullfile(fixture_data, 'atlas root with space');
local_mkdir(mcr_dir);
local_mkdir(batch_dir);
local_mkdir(atlas_dir);
defaults_file = fullfile(fixture_data, 'defaults file with space.mat');
local_write(defaults_file, 'fixture');
env_file = fullfile(fixture_data, 'freesurfer env with space');
local_write(env_file, ['setenv LOCAL_LEGACY_FIXTURE 1' char(10)]);
input_dir = fullfile(fixture_data, 'input dir with space');
local_mkdir(input_dir);
input_file = fullfile(input_dir, 'input image with space.nii');
local_write(input_file, 'MPRAGE-FIXTURE');
runner_ok = fullfile(fixture_data, 'runner ok with space.sh');
runner_fail = fullfile(fixture_data, 'runner fail with space.sh');
runner_noatt = fullfile(fixture_data, 'runner noatt with space.sh');
runner_body = ['printf ''%s\n'' "$1" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10) ...
    'printf ''%s\n'' "$2" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10) ...
    'printf ''%s\n'' "$3" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10) ...
    'printf ''%s\n'' "$4" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10) ...
    'printf ''%s\n'' "$5" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10) ...
    'printf ''%s\n'' "$6" >> "$LOCAL_LEGACY_RUNNER_LOG"' char(10)];
local_write(runner_ok, ['#!/bin/bash' char(10) runner_body ...
    'att_dir=$(dirname "$2")' char(10) ...
    'printf ''fixture-att-map'' > "$att_dir/att_map.nii"' char(10) ...
    'exit 0' char(10)]);
local_write(runner_fail, ['#!/bin/bash' char(10) runner_body 'exit 7' char(10)]);
local_write(runner_noatt, ['#!/bin/bash' char(10) runner_body 'exit 0' char(10)]);
fs_log = fullfile(fixture_data, 'fs.log');
runner_log = fullfile(fixture_data, 'runner.log');
local_legacy_make_executable(fullfile(fake_bin, 'mri_normalize'));
local_legacy_make_executable(runner_ok);
local_legacy_make_executable(runner_fail);
local_legacy_make_executable(runner_noatt);
old_matlab_path = path();
old_path_env = getenv('PATH');
old_fs_env = getenv('LOCAL_LEGACY_FS_LOG');
old_runner_env = getenv('LOCAL_LEGACY_RUNNER_LOG');
addpath(stub_dir, '-begin');
clear('dcm2nii');
rehash;
stub_cleanup = onCleanup(@() local_legacy_restore_stub(old_matlab_path)); %#ok<NASGU>
setenv('PATH', [fake_bin pathsep old_path_env]);
setenv('LOCAL_LEGACY_FS_LOG', fs_log);
setenv('LOCAL_LEGACY_RUNNER_LOG', runner_log);
env_cleanup = onCleanup(@() local_legacy_restore_env(old_path_env, old_fs_env, old_runner_env)); %#ok<NASGU>
cfg_ok = base_config;
cfg_ok.atlas_root = atlas_dir;
cfg_ok.normalization.source_command = ['source ' env_file];
cfg_ok.io_policy.output = 'nifti-only';
cfg_ok.cleanup_on_success = false;
cfg_ok.legacy.runner = runner_ok;
cfg_ok.legacy.mcr_root = mcr_dir;
cfg_ok.legacy.defaults_mat = defaults_file;
cfg_ok.legacy.batch_templates = batch_dir;
temp_ok = fullfile(fixture_data, 'temp ok with space');
proc_ok = fullfile(fixture_data, 'proc ok with space');
if exist(fs_log, 'file') == 2
    delete(fs_log);
end
if exist(runner_log, 'file') == 2
    delete(runner_log);
end
job_ok = struct('mprage_fn', input_file, 'temp_dir', temp_ok, 'processing_dir', proc_ok);
job_ok.correct_aliasing = 1;
ok = pseudo_CT_run_local_legacy_subject(job_ok, cfg_ok, 1, 1, false);
assert(ok == 1);
seed_ok = fullfile(temp_ok, 'mprage.nii');
normalized_ok = fullfile(temp_ok, 'mprage_normalized.nii');
assert(exist(seed_ok, 'file') == 2);
assert(exist(normalized_ok, 'file') == 2);
assert(dir(normalized_ok).bytes > 0);
assert(exist(fullfile(temp_ok, 'att_map.nii'), 'file') == 2);
assert(dir(fullfile(temp_ok, 'att_map.nii')).bytes > 0);
assert(exist(fullfile(proc_ok, 'att_map.nii'), 'file') == 2);
fs_lines = local_legacy_read_lines(fs_log);
assert(length(fs_lines) == 2);
assert(strcmp(fs_lines{1}, seed_ok));
assert(strcmp(fs_lines{2}, normalized_ok));
runner_lines = local_legacy_read_lines(runner_log);
assert(length(runner_lines) == 6);
assert(strcmp(runner_lines{1}, mcr_dir));
assert(strcmp(runner_lines{2}, normalized_ok));
assert(strcmp(runner_lines{3}, batch_dir));
assert(strcmp(runner_lines{4}, '0'));
assert(strcmp(runner_lines{5}, '1'));
assert(strcmp(runner_lines{6}, defaults_file));
cfg_fail = cfg_ok;
cfg_fail.legacy.runner = runner_fail;
temp_fail = fullfile(fixture_data, 'temp fail with space');
proc_fail = fullfile(fixture_data, 'proc fail with space');
if exist(fs_log, 'file') == 2
    delete(fs_log);
end
if exist(runner_log, 'file') == 2
    delete(runner_log);
end
job_fail = struct('mprage_fn', input_file, 'temp_dir', temp_fail, 'processing_dir', proc_fail);
job_fail.correct_aliasing = 1;
failed = pseudo_CT_run_local_legacy_subject(job_fail, cfg_fail, 1, 1, false);
assert(failed == 0);
normalized_fail = fullfile(temp_fail, 'mprage_normalized.nii');
assert(exist(normalized_fail, 'file') == 2);
assert(exist(fullfile(temp_fail, 'att_map.nii'), 'file') ~= 2);
assert(exist(fullfile(proc_fail, 'att_map.nii'), 'file') ~= 2);
fail_runner_lines = local_legacy_read_lines(runner_log);
assert(length(fail_runner_lines) == 6);
assert(strcmp(fail_runner_lines{2}, normalized_fail));
cfg_noatt = cfg_ok;
cfg_noatt.legacy.runner = runner_noatt;
temp_noatt = fullfile(fixture_data, 'temp noatt with space');
proc_noatt = fullfile(fixture_data, 'proc noatt with space');
if exist(fs_log, 'file') == 2
    delete(fs_log);
end
if exist(runner_log, 'file') == 2
    delete(runner_log);
end
job_noatt = struct('mprage_fn', input_file, 'temp_dir', temp_noatt, 'processing_dir', proc_noatt);
job_noatt.correct_aliasing = 1;
missing = pseudo_CT_run_local_legacy_subject(job_noatt, cfg_noatt, 1, 1, false);
assert(missing == 0);
normalized_noatt = fullfile(temp_noatt, 'mprage_normalized.nii');
assert(exist(normalized_noatt, 'file') == 2);
assert(exist(fullfile(temp_noatt, 'att_map.nii'), 'file') ~= 2);
assert(exist(fullfile(proc_noatt, 'att_map.nii'), 'file') ~= 2);
noatt_runner_lines = local_legacy_read_lines(runner_log);
assert(length(noatt_runner_lines) == 6);
assert(strcmp(noatt_runner_lines{2}, normalized_noatt));
path(old_matlab_path);
clear('dcm2nii');
rehash;
setenv('PATH', old_path_env);
setenv('LOCAL_LEGACY_FS_LOG', old_fs_env);
setenv('LOCAL_LEGACY_RUNNER_LOG', old_runner_env);
fprintf('Local-legacy behavioral fixture passed: spaced quoting, runner failure, missing att_map.\n');
end

function quoted = local_legacy_shell_quote(value)
single_quote = char(39);
quoted = single_quote;
for ii = 1:length(value)
    if value(ii) == single_quote
        quoted = [quoted single_quote char(34) single_quote char(34) single_quote]; %#ok<AGROW>
    else
        quoted = [quoted value(ii)]; %#ok<AGROW>
    end
end
quoted = [quoted single_quote];
end

function local_legacy_make_executable(file_path)
[status, detail] = system(['/bin/chmod 700 ' local_legacy_shell_quote(file_path)]);
assert(status == 0, detail);
end

function lines = local_legacy_read_lines(file_path)
fid = fopen(file_path, 'r');
assert(fid ~= -1);
text = fread(fid, inf, '*char')';
fclose(fid);
lines = regexp(text, '\r\n|\n|\r', 'split');
if ~isempty(lines) && isempty(lines{end})
    lines = lines(1:end-1);
end
lines = lines(:);
end

function local_legacy_restore_env(old_path, old_fs, old_runner)
setenv('PATH', old_path);
setenv('LOCAL_LEGACY_FS_LOG', old_fs);
setenv('LOCAL_LEGACY_RUNNER_LOG', old_runner);
end

function local_legacy_restore_stub(old_path)
clear('dcm2nii');
path(old_path);
try
    rehash;
catch %#ok<CTCH>
end
end
