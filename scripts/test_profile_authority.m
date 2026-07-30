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

configs = cell(length(profiles), 1);
for ii = 1:length(profiles)
    configs{ii} = pseudo_CT_load_profile(profiles(ii).name, config_root);
end

top_fields = fieldnames(configs{1});
normalization_fields = fieldnames(configs{1}.normalization);
launchpad_fields = fieldnames(configs{1}.launchpad);
for ii = 2:length(configs)
    assert(isequal(top_fields, fieldnames(configs{ii})));
    assert(isequal(normalization_fields, ...
        fieldnames(configs{ii}.normalization)));
    assert(isequal(launchpad_fields, fieldnames(configs{ii}.launchpad)));
end

names = {profiles.name};
[ordered_profiles, default_index] = pseudo_CT_prepare_profile_choices(profiles);
assert(isequal({ordered_profiles.name}, ...
    {'local-current', 'launchpad', 'local-mprage-only', ...
     'launchpad-mprage-only', 'local-near-parity-r2010b'}));
assert(strcmp(ordered_profiles(default_index).name, 'local-current'));
without_local = profiles(~strcmp({profiles.name}, 'local-current'));
[without_local, fallback_index] = pseudo_CT_prepare_profile_choices(without_local);
assert(strcmp(without_local(fallback_index).name, 'launchpad'));
assert(isequal({ordered_profiles(1:2).group}, ...
    {'recommended', 'recommended'}));
assert(all([ordered_profiles(1:2).recommended]));
assert(isequal({ordered_profiles(3:5).group}, ...
    {'specialized', 'specialized', 'specialized'}));
assert(~any([ordered_profiles(3:5).recommended]));
for ii = 1:length(profiles)
    assert(~isempty(strtrim(profiles(ii).display_name)));
    assert(~isempty(strtrim(profiles(ii).description)));
    assert(strcmp(profiles(ii).name, strrep(profiles(ii).function_name, '_', '-')));
    assert(strcmp(profiles(ii).display_name, configs{ii}.presentation.display_name));
end
assert(~strcmp(ordered_profiles(1).display_name, ordered_profiles(1).name));
local = configs{find(strcmp(names, 'local-current'), 1)};
near_parity = configs{find(strcmp(names, ...
    'local-near-parity-r2010b'), 1)};
launchpad = configs{find(strcmp(names, 'launchpad'), 1)};
local_mprage = configs{find(strcmp(names, 'local-mprage-only'), 1)};
launchpad_mprage = configs{find(strcmp(names, 'launchpad-mprage-only'), 1)};
assert(strcmp(local.mode, 'local'));
assert(strcmp(near_parity.mode, 'local'));
assert(strcmp(launchpad.mode, 'launchpad'));
assert(strcmp(local.normalization.host, '127.0.0.1'));
assert(strcmp(near_parity.required_matlab_release, '2010b'));
assert(strcmp(launchpad.normalization.host, launchpad.launchpad.host));
assert(~isempty(launchpad.launchpad.runner));
assert(~isempty(launchpad.launchpad.defaults_mat));
assert(~isempty(launchpad.launchpad.batch_templates));
assert(~isempty(launchpad.launchpad.mcr_root));
assert(strcmp(local.io_policy.reference, 'umap-required'));
assert(strcmp(local.io_policy.output, 'nifti-and-dicom'));
assert(strcmp(local.io_policy.gui, 'mMR'));
assert(strcmp(local_mprage.io_policy.reference, 'none'));
assert(strcmp(local_mprage.io_policy.output, 'nifti-only'));
assert(strcmp(local_mprage.io_policy.gui, 'mprage-only'));
assert(strcmp(local_mprage.compatibility_profile, 'local-current'));
assert(strcmp(launchpad_mprage.compatibility_profile, 'launchpad'));
assert(isequal(local_without_policy(local_mprage), ...
    local_without_policy(local)));
assert(isequal(local_without_policy(launchpad_mprage), ...
    local_without_policy(launchpad)));

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
assert(~isempty(strfind(selector_source, 'profiles(selected_index).name')));
assert(length(strfind(entry_source, 'config.fwhm')) >= 2);
assert(~isempty(strfind(atlas_source, 'if config.bone_enabled')));
assert(~isempty(strfind(atlas_source, 'config.zero_background')));
assert(~isempty(strfind(atlas_source, ...
    'move_image_2_MNI(P_orig, fullfile(dir_batch_templates, ''ch2.nii''), ...')));
assert(~isempty(strfind(launchpad_source, 'config.launchpad.runner')));
assert(isempty(strfind(launchpad_source, 'pseudo_CT_load_profile')));

fprintf(['Profile authority tests passed: %d dynamically discovered profiles, ', ...
    'identical schemas, explicit local/Launchpad config flow, bone and FWHM consumption.\n'], ...
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
