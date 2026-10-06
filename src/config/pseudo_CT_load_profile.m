function config = pseudo_CT_load_profile(profile_name, config_root)
%PSEUDO_CT_LOAD_PROFILE Load and validate one discovered profile.

if nargin < 1 || ~ischar(profile_name) || isempty(strtrim(profile_name))
    error('pseudo_CT:InvalidProfile', 'Profile name must be a non-empty string.');
end
if nargin < 2 || isempty(config_root)
    config_root = fileparts(mfilename('fullpath'));
end

% Single canonical-resolution authority: accept only exact hyphenated
% canonical keys discovered from src/config/profiles plus the deprecated
% alias mlsc -> mlsc-legacy. Underscore spellings, display labels,
% mlsc-current, Launchpad and near-parity names are rejected. Discovery
% stays non-recursive so the alias creates no row.
trimmed = strtrim(profile_name);
if strcmp(trimmed, 'mlsc')
    trimmed = 'mlsc-legacy';
end
profiles = pseudo_CT_list_profiles(config_root, false);
profile = struct();
for ii = 1:length(profiles)
    if strcmp(trimmed, profiles(ii).name)
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

required = {'mode'; 'implementation'; 'spm_root'; 'atlas_root'; 'd2n_root'; ...
    'aliasing_root'; ...
    'recenter_before_normalization'; 'zero_background'; ...
    'cleanup_on_success'; 'pca_order'; 'required_matlab_release'; ...
    'bone_enabled'; 'fwhm'; 'aliasing_default'; 'io_policy'; ...
    'compatibility_profile'; 'presentation'; ...
    'normalization'};
require_fields(config, required, 'config');
require_fields(config.io_policy, {'reference'; 'output'; 'gui'}, ...
    'config.io_policy');
require_fields(config.presentation, ...
    {'display_name'; 'description'; 'group'; 'recommended'; 'order'}, ...
    'config.presentation');
require_fields(config.normalization, ...
    {'source_command'; 'child_lib_path'; 'host'; 'cluster'; 'host_folder'}, ...
    'config.normalization');

if ~ismember(config.mode, {'local', 'launchpad', 'mlsc'})
    error('pseudo_CT:InvalidProfile', ...
        ['config.mode must be ''local'', ''launchpad'', or ''mlsc'' ', ...
         'in profile %s.'], profile.name);
end
if ~ischar(config.implementation) || ...
        ~ismember(config.implementation, {'current', 'legacy-v2'})
    error('pseudo_CT:InvalidProfile', ...
        ['config.implementation must be ''current'' or ''legacy-v2'' ', ...
         'in profile %s.'], profile.name);
end
if strcmp(config.mode, 'launchpad')
    require_fields(config.launchpad, ...
        {'host'; 'runner'; 'mcr_root'; 'defaults_mat'; ...
         'batch_templates'; 'queue'; 'scratch'}, 'config.launchpad');
elseif strcmp(config.mode, 'mlsc')
    require_fields(config.mlsc, ...
        {'host'; 'runner'; 'mcr_root'; 'defaults_mat'; ...
         'batch_templates'; 'shell'; 'freesurfer_env'; 'partition'; ...
         'nodes'; 'ntasks'; 'cpus_per_task'; 'memory'; 'time'}, ...
        'config.mlsc');
    validate_mlsc(config.mlsc, profile.name);
end
if strcmp(config.implementation, 'legacy-v2')
    require_fields(config.legacy, ...
        {'runner'; 'mcr_root'; 'defaults_mat'; 'batch_templates'; ...
         'att_map'}, 'config.legacy');
    validate_legacy(config.legacy, profile.name);
end
if ~ischar(config.aliasing_root) || isempty(strtrim(config.aliasing_root))
    error('pseudo_CT:InvalidProfile', ...
        'config.aliasing_root must be a non-empty string in profile %s.', ...
        profile.name);
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

validate_io_policy(config, profile.name);
validate_presentation(config.presentation, profile.name);
if ~isempty(config.compatibility_profile)
    baseline = pseudo_CT_load_profile(config.compatibility_profile, config_root);
    if ~isequal(remove_io_policy(config), remove_io_policy(baseline))
        error('pseudo_CT:ProfileDrift', ...
            'Profile %s does not match its compatibility baseline %s.', ...
            profile.name, config.compatibility_profile);
    end
end

function validate_presentation(presentation, profile_name)
if ~ischar(presentation.display_name) || isempty(strtrim(presentation.display_name)) || ...
        ~ischar(presentation.description) || isempty(strtrim(presentation.description))
    error('pseudo_CT:InvalidProfile', ...
        'Profile %s requires non-empty presentation text.', profile_name);
end
if ~ischar(presentation.group) || ...
        ~ismember(presentation.group, {'recommended'; 'specialized'})
    error('pseudo_CT:InvalidProfile', ...
        'Profile %s has an unsupported presentation group.', profile_name);
end
if ~islogical(presentation.recommended) || ~isscalar(presentation.recommended) || ...
        ~isnumeric(presentation.order) || ~isscalar(presentation.order) || ...
        ~isfinite(presentation.order)
    error('pseudo_CT:InvalidProfile', ...
        'Profile %s has invalid presentation ordering metadata.', profile_name);
end
end
end

function validate_io_policy(config, profile_name)
if ~ischar(config.compatibility_profile)
    error('pseudo_CT:InvalidProfile', ...
        'compatibility_profile must be a string in profile %s.', profile_name);
end
if ~ischar(config.io_policy.reference) || ...
        ~ischar(config.io_policy.output) || ~ischar(config.io_policy.gui)
    error('pseudo_CT:InvalidProfile', ...
        'io_policy values must be strings in profile %s.', profile_name);
end

legacy = strcmp(config.io_policy.reference, 'umap-required') && ...
    strcmp(config.io_policy.output, 'nifti-and-dicom') && ...
    strcmp(config.io_policy.gui, 'mMR') && isempty(config.compatibility_profile);
mprage_only = strcmp(config.io_policy.reference, 'none') && ...
    strcmp(config.io_policy.output, 'nifti-only') && ...
    strcmp(config.io_policy.gui, 'mprage-only') && ...
    ismember(config.compatibility_profile, ...
             {'local-current'; 'launchpad'; 'mlsc'});
if ~(legacy || mprage_only)
    error('pseudo_CT:InvalidProfile', ...
        'Unsupported or inconsistent io_policy tuple in profile %s.', profile_name);
end
end

function validate_mlsc(mlsc, profile_name)
string_fields = {'host'; 'runner'; 'mcr_root'; 'defaults_mat'; ...
    'batch_templates'; 'shell'; 'freesurfer_env'; 'partition'; ...
    'memory'; 'time'};
for ii = 1:length(string_fields)
    field_name = string_fields{ii};
    if ~ischar(mlsc.(field_name)) || isempty(strtrim(mlsc.(field_name)))
        error('pseudo_CT:InvalidProfile', ...
            'config.mlsc.%s must be a non-empty string in profile %s.', ...
            field_name, profile_name);
    end
end

integer_fields = {'nodes'; 'ntasks'; 'cpus_per_task'};
for ii = 1:length(integer_fields)
    field_name = integer_fields{ii};
    value = mlsc.(field_name);
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
            value < 1 || value ~= floor(value)
        error('pseudo_CT:InvalidProfile', ...
            'config.mlsc.%s must be a positive integer in profile %s.', ...
            field_name, profile_name);
    end
end

if isempty(regexp(mlsc.memory, '^[1-9][0-9]*[KMGTP]$', 'once')) || ...
        isempty(regexp(mlsc.time, '^[0-9][0-9]:[0-5][0-9]:[0-5][0-9]$', 'once'))
    error('pseudo_CT:InvalidProfile', ...
        'config.mlsc memory/time must use Slurm formats in profile %s.', ...
        profile_name);
end

forbidden_fields = {'account'; 'username'; 'password'; 'passphrase'; ...
    'credentials'};
for ii = 1:length(forbidden_fields)
    if isfield(mlsc, forbidden_fields{ii})
        error('pseudo_CT:InvalidProfile', ...
            'config.mlsc must not persist credentials or a Slurm account in profile %s.', ...
            profile_name);
    end
end
end

function validate_legacy(legacy, profile_name)
string_fields = {'runner'; 'mcr_root'; 'defaults_mat'; ...
    'batch_templates'; 'att_map'};
for ii = 1:length(string_fields)
    field_name = string_fields{ii};
    if ~ischar(legacy.(field_name)) || isempty(strtrim(legacy.(field_name)))
        error('pseudo_CT:InvalidProfile', ...
            'config.legacy.%s must be a non-empty string in profile %s.', ...
            field_name, profile_name);
    end
end
if ~strcmp(legacy.att_map, 'att_map.nii')
    error('pseudo_CT:InvalidProfile', ...
        'config.legacy.att_map must be ''att_map.nii'' in profile %s.', ...
        profile_name);
end
orchestration_fields = {'host'; 'shell'; 'freesurfer_env'; 'partition'; ...
    'nodes'; 'ntasks'; 'cpus_per_task'; 'memory'; 'time'};
for ii = 1:length(orchestration_fields)
    if isfield(legacy, orchestration_fields{ii})
        error('pseudo_CT:InvalidProfile', ...
            'config.legacy must not carry orchestration field %s in profile %s.', ...
            orchestration_fields{ii}, profile_name);
    end
end
end

function value = remove_io_policy(config)
value = rmfield(config, {'io_policy'; 'compatibility_profile'; 'presentation'});
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
