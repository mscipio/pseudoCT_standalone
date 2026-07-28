function config = pseudo_CT_load_profile(profile_name, config_root)
%PSEUDO_CT_LOAD_PROFILE Load and validate one discovered profile.

if nargin < 1 || ~ischar(profile_name) || isempty(strtrim(profile_name))
    error('pseudo_CT:InvalidProfile', 'Profile name must be a non-empty string.');
end
if nargin < 2 || isempty(config_root)
    config_root = fileparts(mfilename('fullpath'));
end

profiles = pseudo_CT_list_profiles(config_root);
requested = strrep(strtrim(profile_name), '-', '_');
profile = struct();
for ii = 1:length(profiles)
    if strcmp(requested, profiles(ii).function_name)
        profile = profiles(ii);
        break;
    end
end
if isempty(fieldnames(profile))
    error('pseudo_CT:InvalidProfile', 'Unknown profile: %s', profile_name);
end

profile_dir = fullfile(config_root, 'profiles');
path_was_added = isempty(strfind([path pathsep], [profile_dir pathsep]));
if path_was_added
    addpath(profile_dir, '-begin');
end
cleanup = onCleanup(@() remove_profile_path(profile_dir, ...
    profile.function_name, path_was_added)); %#ok<NASGU>
clear(profile.function_name);
rehash;
config = feval(profile.function_name);

if ~isstruct(config) || numel(config) ~= 1
    error('pseudo_CT:InvalidProfile', ...
        'Profile %s must return one config struct.', profile.name);
end

required = {'mode'; 'spm_root'; 'atlas_root'; ...
    'recenter_before_normalization'; 'zero_background'; ...
    'cleanup_on_success'; 'pca_order'; 'required_matlab_release'; ...
    'bone_enabled'; 'fwhm'; 'aliasing_default'; ...
    'normalization'; 'launchpad'};
require_fields(config, required, 'config');
require_fields(config.normalization, ...
    {'source_command'; 'child_lib_path'; 'host'; 'cluster'; 'host_folder'}, ...
    'config.normalization');
require_fields(config.launchpad, ...
    {'host'; 'runner'; 'mcr_root'; 'defaults_mat'; ...
     'batch_templates'; 'queue'; 'scratch'}, ...
    'config.launchpad');

if ~ismember(config.mode, {'local', 'launchpad'})
    error('pseudo_CT:InvalidProfile', ...
        'config.mode must be ''local'' or ''launchpad'' in profile %s.', profile.name);
end
if ~ismember(config.recenter_before_normalization, {'Yes', 'No'}) || ...
        ~ismember(config.zero_background, {'Yes', 'No'})
    error('pseudo_CT:InvalidProfile', ...
        'Recenter and zero-background values must be ''Yes'' or ''No'' in profile %s.', ...
        profile.name);
end
if ~islogical(config.cleanup_on_success) || ...
        ~islogical(config.bone_enabled) || ...
        ~isscalar(config.cleanup_on_success) || ~isscalar(config.bone_enabled)
    error('pseudo_CT:InvalidProfile', ...
        'Cleanup and bone settings must be scalar logical values in profile %s.', ...
        profile.name);
end
if ~isnumeric(config.fwhm) || ~isscalar(config.fwhm) || config.fwhm < 0
    error('pseudo_CT:InvalidProfile', ...
        'config.fwhm must be a non-negative scalar in profile %s.', profile.name);
end
if ~isnumeric(config.aliasing_default) || ...
        ~isscalar(config.aliasing_default) || ...
        ~ismember(config.aliasing_default, [0 1])
    error('pseudo_CT:InvalidProfile', ...
        'config.aliasing_default must be 0 or 1 in profile %s.', profile.name);
end
end

function require_fields(value, fields, label)
if ~isstruct(value) || numel(value) ~= 1
    error('pseudo_CT:InvalidProfile', '%s must be one struct.', label);
end
for ii = 1:length(fields)
    if ~isfield(value, fields{ii})
        error('pseudo_CT:InvalidProfile', ...
            '%s is missing required field %s.', label, fields{ii});
    end
end
end

function remove_profile_path(profile_dir, function_name, path_was_added)
clear(function_name);
if path_was_added
    rmpath(profile_dir);
end
end
