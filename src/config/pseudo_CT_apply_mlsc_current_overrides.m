function config = pseudo_CT_apply_mlsc_current_overrides(config, profile_name, artifact_root)
%PSEUDO_CT_APPLY_MLSC_CURRENT_OVERRIDES Apply the current-MLSC artifact root.
%   ARTIFACT_ROOT supplies the current runner and build/resource manifests
%   under the pinned layout. Only mlsc-current and mlsc-mprage-only may
%   consume this option. Empty keeps the profile-owned defaults.
%   Minimum supported MATLAB: R2010b.

if nargin < 2
    profile_name = '';
end
if nargin < 3 || isempty(artifact_root)
    artifact_root = '';
end
if ~ischar(artifact_root)
    error('run_pseudo_CT:InvalidMlscCurrentOverride', ...
        'mlsc_current_artifact_root must be a character path.');
end
artifact_root = strtrim(artifact_root(:)');
if isempty(artifact_root)
    return;
end
is_current = false;
try
    is_current = isstruct(config) && numel(config) == 1 && ...
        ischar(profile_name) && ...
        (strcmp(profile_name, 'mlsc-current') || ...
         strcmp(profile_name, 'mlsc-mprage-only')) && ...
        isfield(config, 'mode') && ischar(config.mode) && ...
        strcmp(config.mode, 'mlsc') && ...
        isfield(config, 'implementation') && ...
        ischar(config.implementation) && ...
        strcmp(config.implementation, 'current') && ...
        isfield(config, 'current') && isstruct(config.current);
catch %#ok<CTCH>
    is_current = false;
end
if ~is_current
    error('run_pseudo_CT:InvalidMlscCurrentOverride', ...
        ['mlsc_current_artifact_root is supported only for profiles ', ...
         '''mlsc-current'' and ''mlsc-mprage-only'' (mode mlsc, ', ...
         'implementation current); profile ''%s'' is incompatible.'], ...
        profile_name);
end
local_require_absolute_dir(artifact_root, ...
    'mlsc_current_artifact_root must be an absolute directory.');
root = local_strip_sep(artifact_root);
config.current.runner = fullfile(root, 'payload_build', ...
    'run_mlsc_current_payload.sh');
config.current.build_manifest = fullfile(root, ...
    'mlsc_current_build.mat');
config.current.resource_manifest = fullfile(root, ...
    'mlsc_current_resources.mat');
end

function local_require_absolute_dir(value, message)
if ~ischar(value) || size(value, 1) ~= 1 || isempty(strtrim(value)) || ...
        any(value == char(0))
    error('run_pseudo_CT:InvalidMlscCurrentOverride', message);
end
trimmed = strtrim(value);
if trimmed(1) ~= '/'
    error('run_pseudo_CT:InvalidMlscCurrentOverride', message);
end
end

function value = local_strip_sep(value)
value = strtrim(value);
while length(value) > 1 && (value(end) == '/' || value(end) == char(92))
    value(end) = '';
end
end
