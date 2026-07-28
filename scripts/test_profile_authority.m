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
local = configs{find(strcmp(names, 'local-current'), 1)};
near_parity = configs{find(strcmp(names, ...
    'local-near-parity-r2010b'), 1)};
launchpad = configs{find(strcmp(names, 'launchpad'), 1)};
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
atlas_source = read_text(fullfile(root_dir, 'src', 'core', ...
    'atlas_based_attenuation_map.m'));
launchpad_source = read_text(fullfile(root_dir, 'src', 'launchpad', ...
    'batch_pseudo_CT_launchpad.m'));
assert(~isempty(strfind(entry_source, 'switch config.mode')));
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
