function profiles = pseudo_CT_list_profiles(config_root)
%PSEUDO_CT_LIST_PROFILES List editable MATLAB profile files.
%   PROFILES = PSEUDO_CT_LIST_PROFILES(CONFIG_ROOT) scans CONFIG_ROOT/profiles
%   and returns a struct array with fields name, function_name, file_path, and
%   description. Profile names are filenames with underscores rendered as
%   hyphens.

if nargin < 1 || isempty(config_root)
    config_root = fileparts(mfilename('fullpath'));
end
profile_dir = fullfile(config_root, 'profiles');
if exist(profile_dir, 'dir') ~= 7
    error('pseudo_CT:ProfileDirectoryMissing', ...
        'Profile directory not found: %s', profile_dir);
end

files = dir(fullfile(profile_dir, '*.m'));
profiles = struct('name', {}, 'function_name', {}, 'file_path', {}, 'description', {});
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
    profiles(end).description = read_h1_description(profiles(end).file_path);
end

if isempty(profiles)
    error('pseudo_CT:NoProfiles', ...
        'No profile files found in: %s', profile_dir);
end
end

function desc = read_h1_description(file_path)
desc = '';
fid = fopen(file_path, 'r');
if fid == -1
    return;
end
cleanup = onCleanup(@() fclose(fid));
while true
    line = fgetl(fid);
    if line == -1
        return;
    end
    line = strtrim(line);
    if isempty(line)
        continue;
    end
    if line(1) == '%'
        desc = strtrim(line(2:end));
    end
    return;
end
end
