function config = pseudo_CT_load_spm_profile_config(profile_name, config_root)
%PSEUDO_CT_LOAD_SPM_PROFILE_CONFIG Load one fixed deployer SPM template.
%   CONFIG = PSEUDO_CT_LOAD_SPM_PROFILE_CONFIG(PROFILE_NAME) loads the
%   configuration file mapped to a canonical profile name. CONFIG_ROOT is
%   an internal test/deployment-package seam; production callers omit it.
%   The loader never accepts an arbitrary configuration filename and never
%   reads environment variables.
%
%   Minimum supported MATLAB: R2010b.

ids = pseudo_CT_error_ids();
[canonical_name, function_name, file_name, canonical_revision] = ...
    fixed_mapping(profile_name, ids);

if nargin < 2 || isempty(config_root)
    config_root = fileparts(mfilename('fullpath'));
end
profile_dir = fullfile(config_root, 'spm_profiles');
config_path = fullfile(profile_dir, file_name);
if exist(config_path, 'file') ~= 2
    error(ids.SPM_CONFIG.Missing, ...
        'SPM config missing for profile %s: %s', canonical_name, config_path);
end

% The fixed function name is made visible only for the duration of the
% load. This keeps the test seam deterministic without evaluating file text.
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
        'SPM config could not be evaluated for profile %s: %s', ...
        canonical_name, ME.message);
end

if ~isstruct(raw) || ~isscalar(raw) || ...
        ~isfield(raw, 'spm_root') || ~isfield(raw, 'expected_revision')
    error(ids.SPM_CONFIG.Invalid, ...
        'SPM config for profile %s must define scalar char spm_root and expected_revision.', ...
        canonical_name);
end
if ~is_scalar_char(raw.spm_root) || ~is_scalar_char(raw.expected_revision)
    error(ids.SPM_CONFIG.Invalid, ...
        'SPM config for profile %s must define scalar char fields.', canonical_name);
end

if isempty(strtrim(raw.spm_root))
    raw.spm_root = '';
else
    raw.spm_root = strtrim(raw.spm_root);
end
if ~strcmp(raw.expected_revision, canonical_revision)
    error(ids.SPM_CONFIG.Invalid, ...
        'Profile %s requires %s, but config declares %s.', ...
        canonical_name, canonical_revision, raw.expected_revision);
end

config = raw;
config.profile_name = canonical_name;
config.name = canonical_name;
config.spm_expected_revision = config.expected_revision;
config.config_path = config_path;
config.config_dir = profile_dir;
config.spm_root_base = profile_dir;
end

%% ------------------------------------------------------------------------
function [canonical_name, function_name, file_name, revision] = fixed_mapping(name, ids)
if ~is_scalar_char(name) || isempty(strtrim(name))
    error(ids.PROFILE.InvalidName, 'Profile name must be a non-empty string.');
end
switch lower(strtrim(name))
    case 'local-current'
        canonical_name = 'local-current';
        function_name = 'local_current';
        file_name = 'local_current.m';
        revision = 'r6313';
    case 'local-near-parity-r2010b'
        canonical_name = 'local-near-parity-r2010b';
        function_name = 'local_near_parity_r2010b';
        file_name = 'local_near_parity_r2010b.m';
        revision = 'r4667';
    case 'launchpad'
        canonical_name = 'launchpad';
        function_name = 'launchpad';
        file_name = 'launchpad.m';
        revision = 'r6313';
    otherwise
        error(ids.PROFILE.InvalidName, 'Unknown profile name: %s', name);
end
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
