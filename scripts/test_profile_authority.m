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
expected_active = {'devel'; 'local-current'; 'local-mprage-only'; ...
    'mlsc'; 'mlsc-mprage-only'};
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
mlsc = configs{local_config_index(names, 'mlsc')};
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
launchpad_source = read_text(fullfile(root_dir, 'src', 'launchpad', ...
    'batch_pseudo_CT_launchpad.m'));
assert(~isempty(strfind(entry_source, 'switch config.mode')));
assert(isempty(strfind(selector_source, 'listdlg')));
assert(~isempty(strfind(selector_source, '''Style'', ''radiobutton''')));
assert(~isempty(strfind(selector_source, 'pseudo_CT_profile_selector_layout')));
assert(~isempty(strfind(selector_source, '''Style'', ''slider''')));
assert(~isempty(strfind(selector_source, 'profiles(selected_index).name')));
assert(length(strfind(entry_source, 'config.fwhm')) >= 2);
assert(~isempty(strfind(atlas_source, 'if config.bone_enabled')));
assert(~isempty(strfind(atlas_source, 'config.zero_background')));
assert(~isempty(strfind(atlas_source, ...
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
production_names = {'local-current', 'local-mprage-only', 'mlsc', ...
    'mlsc-mprage-only'};
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

assert(~isempty(strfind(atlas_source, 'correct_aliasing(')));
assert(isempty(strfind(entry_source, 'correct_aliasing(')));
assert(~isempty(strfind(entry_source, '''check_aliasing''')));
assert(~isempty(strfind(launchpad_source, 'check_aliasing')));

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
