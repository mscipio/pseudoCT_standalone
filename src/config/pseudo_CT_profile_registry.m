function out = pseudo_CT_profile_registry(action, key, root_dir)
%PSEUDO_CT_PROFILE_REGISTRY Canonical profile registry and identity authority.
%   KEYS = PSEUDO_CT_PROFILE_REGISTRY('keys') returns the four canonical
%   hyphenated profile keys in registry order as a cell column.
%
%   CONFIG = PSEUDO_CT_PROFILE_REGISTRY('invoke', KEY) calls the profile
%   function for KEY through direct callable references. This is the installed
%   profile path: it never scans src/config/profiles, never changes the MATLAB
%   path, and never opens a profile .m file. Underscore spellings are rejected.
%
%   IDENTITY = PSEUDO_CT_PROFILE_REGISTRY('identity', KEY, ROOT_DIR) returns
%   the resolved profile identity struct with fields profile_key,
%   profile_identity_source, profile_path and profile_sha256.
%     Installed mode: KEY is bound to the SHA-256 of the installed
%       manifest.json (no profile file is opened, profile_path is empty).
%     Source mode: the physical profile file under ROOT_DIR/src/config/profiles
%       is hashed, exactly as before.
%   Minimum supported MATLAB: R2010b.

if nargin < 1 || ~ischar(action)
    error('pseudo_CT:ProfileRegistry', 'A profile registry action is required.');
end
switch action
    case 'keys'
        out = {'local'; 'local-mprage-only'; 'mlsc'; 'mlsc-mprage-only'};
    case 'invoke'
        key = local_require_key(key);
        switch key
            case 'local'
                out = local();
            case 'mlsc'
                out = mlsc();
            case 'local-mprage-only'
                out = local_mprage_only();
            otherwise
                out = mlsc_mprage_only();
        end
    case 'identity'
        out = local_identity(key, root_dir);
    otherwise
        error('pseudo_CT:ProfileRegistry', 'Unknown profile registry action.');
end
end

function key = local_require_key(key)
%LOCAL_REQUIRE_KEY Exact canonical key among the four installed profiles.
if ~ischar(key) || size(key, 1) ~= 1 || ~any(strcmp(key, ...
        {'local'; 'mlsc'; 'local-mprage-only'; 'mlsc-mprage-only'}))
    error('pseudo_CT:InvalidProfile', 'Unknown profile: %s', local_text(key));
end
end

function identity = local_identity(key, root_dir)
layout = pseudo_CT_package_layout();
if strcmp(layout.mode, 'installed')
    if ~ischar(key) || size(key, 1) ~= 1 || ~any(strcmp(key, ...
            {'local'; 'mlsc'; 'local-mprage-only'; 'mlsc-mprage-only'}))
        error('pseudo_CT:InvalidProfile', 'The selected profile is unavailable.');
    end
    identity = struct('profile_key', key, ...
        'profile_identity_source', 'installed-manifest', ...
        'profile_path', '', ...
        'profile_sha256', local_sha256(fullfile(layout.root, 'manifest.json')));
    return;
end
profiles = pseudo_CT_list_profiles(fullfile(root_dir, 'src', 'config'), false);
profile_path = '';
for ii = 1:length(profiles)
    if ischar(key) && strcmp(profiles(ii).name, key)
        profile_path = profiles(ii).file_path;
        break;
    end
end
if isempty(profile_path)
    error('pseudo_CT:InvalidProfile', 'The selected profile is unavailable.');
end
identity = struct('profile_key', key, ...
    'profile_identity_source', 'source-file', ...
    'profile_path', profile_path, ...
    'profile_sha256', local_sha256(profile_path));
end

function hash = local_sha256(path_name)
try
    hash = mlsc_release_gate('sha256_file', path_name);
catch ME
    error('pseudo_CT:OrchestrationArtifact', ...
        'A local input or artifact could not be fingerprinted: %s', ME.message);
end
if ~ischar(hash) || isempty(hash)
    error('pseudo_CT:OrchestrationArtifact', ...
        'A local input or artifact could not be fingerprinted.');
end
end

function text = local_text(value)
if ischar(value)
    text = value;
else
    text = '<non-text>';
end
end
