function profiles = pseudo_CT_list_profiles(config_root, include_presentation)
%PSEUDO_CT_LIST_PROFILES List editable MATLAB profile files.
%   PROFILES = PSEUDO_CT_LIST_PROFILES(CONFIG_ROOT) scans CONFIG_ROOT/profiles
%   and returns filename-derived canonical identity plus profile-owned
%   presentation metadata. Profile names are filenames with underscores
%   rendered as hyphens.
%   In an installed package (PSEUDOCT_INSTALL_ROOT with no src/) the four
%   compiled profiles are returned from the deterministic registry instead;
%   CONFIG_ROOT is then ignored and nothing is scanned or added to the path.

if nargin < 1 || isempty(config_root)
    config_root = fileparts(mfilename('fullpath'));
end
if nargin < 2
    include_presentation = true;
end
layout = pseudo_CT_package_layout();
if strcmp(layout.mode, 'installed')
    profiles = local_installed_profiles(include_presentation);
    return;
end
profile_dir = fullfile(config_root, 'profiles');
if exist(profile_dir, 'dir') ~= 7
    error('pseudo_CT:ProfileDirectoryMissing', ...
        'Profile directory not found: %s', profile_dir);
end

files = dir(fullfile(profile_dir, '*.m'));
profiles = struct('name', {}, 'function_name', {}, 'file_path', {}, ...
    'display_name', {}, 'description', {}, 'group', {}, ...
    'recommended', {}, 'order', {});
for ii = 1:length(files)
    if files(ii).isdir
        continue;
    end
    [~, function_name] = fileparts(files(ii).name);
    if isempty(function_name) || function_name(1) == '.' || function_name(1) == '_'
        continue;
    end
    profiles(end + 1).name = strrep(function_name, '_', '-'); %#ok<AGROW>
    profiles(end).function_name = function_name;
    profiles(end).file_path = fullfile(profile_dir, files(ii).name);
    if include_presentation
        presentation = read_presentation(profile_dir, function_name);
        profiles(end).display_name = presentation.display_name;
        profiles(end).description = presentation.description;
        profiles(end).group = presentation.group;
        profiles(end).recommended = presentation.recommended;
        profiles(end).order = presentation.order;
    else
        profiles(end).display_name = '';
        profiles(end).description = '';
        profiles(end).group = '';
        profiles(end).recommended = false;
        profiles(end).order = 0;
    end
end

if isempty(profiles)
    error('pseudo_CT:NoProfiles', ...
        'No profile files found in: %s', profile_dir);
end
end

function profiles = local_installed_profiles(include_presentation)
%LOCAL_INSTALLED_PROFILES Four compiled profiles from the direct registry.
keys = pseudo_CT_profile_registry('keys');
profiles = struct('name', {}, 'function_name', {}, 'file_path', {}, ...
    'display_name', {}, 'description', {}, 'group', {}, ...
    'recommended', {}, 'order', {});
for ii = 1:length(keys)
    profiles(ii).name = keys{ii};
    profiles(ii).function_name = strrep(keys{ii}, '-', '_');
    profiles(ii).file_path = '';
    if include_presentation
        config = pseudo_CT_profile_registry('invoke', keys{ii});
        presentation = check_presentation(config, keys{ii});
        profiles(ii).display_name = presentation.display_name;
        profiles(ii).description = presentation.description;
        profiles(ii).group = presentation.group;
        profiles(ii).recommended = presentation.recommended;
        profiles(ii).order = presentation.order;
    else
        profiles(ii).display_name = '';
        profiles(ii).description = '';
        profiles(ii).group = '';
        profiles(ii).recommended = false;
        profiles(ii).order = 0;
    end
end
end

function presentation = read_presentation(profile_dir, function_name)
path_was_added = isempty(strfind([path pathsep], [profile_dir pathsep]));
if path_was_added
    addpath(profile_dir, '-begin');
end
cleanup = onCleanup(@() remove_profile_path(profile_dir, ...
    function_name, path_was_added)); %#ok<NASGU>
clear(function_name);
rehash;
config = feval(function_name);
presentation = check_presentation(config, strrep(function_name, '_', '-'));
end

function presentation = check_presentation(config, profile_name)
if ~isstruct(config) || numel(config) ~= 1 || ...
        ~isfield(config, 'presentation') || ~isstruct(config.presentation)
    error('pseudo_CT:InvalidProfile', ...
        'Profile %s is missing presentation metadata.', profile_name);
end
presentation = config.presentation;
required = {'display_name'; 'description'; 'group'; 'recommended'; 'order'};
for ii = 1:length(required)
    if ~isfield(presentation, required{ii})
        error('pseudo_CT:InvalidProfile', ...
            'Profile %s presentation is missing %s.', ...
            profile_name, required{ii});
    end
end
end

function remove_profile_path(profile_dir, function_name, path_was_added)
clear(function_name);
if path_was_added
    rmpath(profile_dir);
end
end
