function config = pseudo_CT_apply_mlsc_current_overrides(config, profile_name, artifact_root)
%PSEUDO_CT_APPLY_MLSC_CURRENT_OVERRIDES Apply the current-MLSC artifact root.
%   ARTIFACT_ROOT supplies the current runner and build/resource manifests
%   under the pinned layout. It is a development and internal-API option, never
%   an installed-use prerequisite. Source mode uses the development manifest
%   names (mlsc_current_build.mat / mlsc_current_resources.mat); installed mode
%   uses build_manifest.mat/resource_manifest.mat. Only mlsc and mlsc-mprage-only
%   may consume this option. Empty keeps the profile-owned placeholders, which
%   runtime selection (installed) or the source-checkout refusal resolves.
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
        (strcmp(profile_name, 'mlsc') || ...
         strcmp(profile_name, 'mlsc-mprage-only')) && ...
        isfield(config, 'mode') && ischar(config.mode) && ...
        strcmp(config.mode, 'mlsc') && ...
        isfield(config, 'current') && isstruct(config.current);
catch %#ok<CTCH>
    is_current = false;
end
if ~is_current
    error('run_pseudo_CT:InvalidMlscCurrentOverride', ...
        ['mlsc_current_artifact_root is supported only for profiles ', ...
         '''mlsc'' and ''mlsc-mprage-only'' (mode mlsc); profile ''%s'' ', ...
         'is incompatible.'], ...
        profile_name);
end
local_require_absolute_dir(artifact_root, ...
    'mlsc_current_artifact_root must be an absolute directory.');
root = local_strip_sep(artifact_root);
layout = pseudo_CT_package_layout();
% Source mode: root is a development compiled tree, whose runner sits in
% payload_build/. Installed mode: root is a flat runtimes/<LABEL>/ folder.
if strcmp(layout.mode, 'installed')
    build_manifest_name = 'build_manifest.mat';
    resource_manifest_name = 'resource_manifest.mat';
    runner_path = fullfile(root, 'run_pseudoct_pipeline.sh');
else
    build_manifest_name = 'mlsc_current_build.mat';
    resource_manifest_name = 'mlsc_current_resources.mat';
    runner_path = fullfile(root, 'payload_build', 'run_pseudoct_pipeline.sh');
end
config.current.runner = runner_path;
config.current.build_manifest = fullfile(root, ...
    build_manifest_name);
config.current.resource_manifest = fullfile(root, ...
    resource_manifest_name);
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
