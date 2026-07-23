function config = pseudo_CT_load_spm_profile_config(profile_name, config_root)
%PSEUDO_CT_LOAD_SPM_PROFILE_CONFIG Load a profile configuration file.
%   CONFIG = PSEUDO_CT_LOAD_SPM_PROFILE_CONFIG(PROFILE_NAME) loads the
%   configuration for a canonical profile name (e.g. 'local-current') from
%   the corresponding file in src/config/spm_profiles/. CONFIG_ROOT is an
%   internal test/deployment-package seam; production callers omit it.
%
%   The returned struct contains ALL settings defined in the profile config
%   file -- paths, pipeline parameters, and optional launchpad settings.
%   No SPM revision validation is performed; the SPM tree at spm_root is
%   used as-is.
%
%   Minimum supported MATLAB: R2010b.

ids = pseudo_CT_error_ids();

if ~is_scalar_char(profile_name) || isempty(strtrim(profile_name))
    error(ids.PROFILE.InvalidName, 'Profile name must be a non-empty string.');
end

profile_name = strtrim(profile_name);

% Map canonical name (with hyphens) to MATLAB function name (with underscores)
function_name = strrep(profile_name, '-', '_');
file_name = [function_name '.m'];

if nargin < 2 || isempty(config_root)
    config_root = fileparts(mfilename('fullpath'));
end
profile_dir = fullfile(config_root, 'spm_profiles');
config_path = fullfile(profile_dir, file_name);
if exist(config_path, 'file') ~= 2
    error(ids.SPM_CONFIG.Missing, ...
        'Profile config missing for %s: %s', profile_name, config_path);
end

% Make the function visible only for the duration of the load.
added_path = ~has_path_entry(profile_dir);
if added_path
    addpath(profile_dir, '-begin');
end
cleanup = onCleanup(@() remove_config_path(profile_dir, function_name, ...
    added_path)); %#ok<NASGU>
clear(function_name);
rehash;
try
    raw = feval(function_name);
catch ME
    error(ids.SPM_CONFIG.Invalid, ...
        'Profile config could not be evaluated for %s: %s', ...
        profile_name, ME.message);
end

if ~isstruct(raw) || ~isscalar(raw)
    error(ids.SPM_CONFIG.Invalid, ...
        'Profile config for %s must return a scalar struct.', profile_name);
end

% Enforce minimal required fields: at least spm_root must exist.
if ~isfield(raw, 'spm_root')
    error(ids.SPM_CONFIG.Invalid, ...
        'Profile config for %s must define spm_root.', profile_name);
end
if ~is_scalar_char(raw.spm_root)
    error(ids.SPM_CONFIG.Invalid, ...
        'Profile config for %s spm_root must be a scalar char.', profile_name);
end
if isempty(strtrim(raw.spm_root))
    raw.spm_root = '';
else
    raw.spm_root = strtrim(raw.spm_root);
end

config = raw;
config.profile_name = profile_name;
config.name = profile_name;
config.config_path = config_path;
config.config_dir = profile_dir;
config.config_root = config_root;

end

%% ------------------------------------------------------------------------
function result = is_scalar_char(value)
result = ischar(value) && (isempty(value) || size(value, 1) == 1);
end

%% ------------------------------------------------------------------------
function result = has_path_entry(profile_dir)
result = ~isempty(strfind([path pathsep], [profile_dir pathsep]));
end

%% ------------------------------------------------------------------------
function remove_config_path(profile_dir, function_name, added_path)
clear(function_name);
if added_path
    rmpath(profile_dir);
end
end
