function config = pseudo_CT_apply_mlsc_current_overrides(config, profile_name, artifact_root, gate_a_record)
%PSEUDO_CT_APPLY_MLSC_CURRENT_OVERRIDES Operator artifact override (T009 Option A).
%   CONFIG = PSEUDO_CT_APPLY_MLSC_CURRENT_OVERRIDES(CONFIG, PROFILE_NAME,
%   ARTIFACT_ROOT, GATE_A_RECORD) applies the explicit public
%   run_pseudo_CT name-value overrides for operator-selected current MLSC
%   profiles (mlsc-current and mlsc-mprage-only)
%   artifacts. This is the real public config path in the normal
%   run_pseudo_CT(...) workflow (not an internal mutation/debug/test seam,
%   env backdoor, or validation bypass).
%
%   Supported overrides (current MLSC profiles only):
%     ARTIFACT_ROOT  - absolute directory deterministically supplying the
%                      T007 build-layout files:
%                        <root>/payload_build/run_mlsc_current_payload.sh
%                        <root>/mlsc_current_build.mat
%                        <root>/mlsc_current_resources.mat
%                      The runner lives under payload_build/ in the exact
%                      T007/Gate-A candidate (see the build manifest and
%                      Gate-A runner binding); manifests live at the root.
%                      There are NO independent runner/build/resource
%                      overrides. Empty (default '') means no override.
%     GATE_A_RECORD  - absolute .mat path to the structured Gate-A record.
%                      When ARTIFACT_ROOT is supplied and GATE_A_RECORD is
%                      omitted, it defaults to
%                      <root>/mlsc_current_gate_a.mat. The validated record
%                      for the current candidate lives in a separate
%                      directory, so callers MUST pass its explicit absolute
%                      path. Empty (default '') means default/keep profile.
%
%   Default behavior is unchanged: with both overrides omitted the profile
%   canonical /usr/pubsw paths are returned untouched.
%
%   Only mlsc-current and mlsc-mprage-only (mode 'mlsc', implementation
%   'current') may consume these options; any other profile/implementation
%   with non-empty overrides fails clearly. MCR_ROOT is never overridden and remains the pinned
%   /usr/pubsw/common/matlab/26.1 (T014 authority); there is no catalog or
%   resolver. Validation is unchanged: this function only selects which
%   exact paths populate config.current.runner/build_manifest/
%   resource_manifest/gate_a_record. validate_contract and
%   validate_for_execution still recompute every hash and binding; wrong or
%   incomplete paths fail closed there. No skip flag, alternate mode, test
%   token, or legacy fallback.
%
%   Minimum supported MATLAB: R2010b.

if nargin < 2
    profile_name = '';
end
if nargin < 3 || isempty(artifact_root)
    artifact_root = '';
end
if nargin < 4 || isempty(gate_a_record)
    gate_a_record = '';
end
if ~ischar(artifact_root)
    error('run_pseudo_CT:InvalidMlscCurrentOverride', ...
        'mlsc_current_artifact_root must be a character path.');
end
if ~ischar(gate_a_record)
    error('run_pseudo_CT:InvalidMlscCurrentOverride', ...
        'mlsc_current_gate_a_record must be a character path.');
end
artifact_root = strtrim(artifact_root(:)');
gate_a_record = strtrim(gate_a_record(:)');
if isempty(artifact_root) && isempty(gate_a_record)
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
        ['mlsc_current_artifact_root/gate_a_record overrides are ', ...
         'supported only for profiles ''mlsc-current'' and ', ...
         '''mlsc-mprage-only'' (mode mlsc, implementation current); ', ...
         'profile ''%s'' is incompatible.'], ...
        profile_name);
end
if ~isempty(artifact_root)
    local_require_absolute_dir(artifact_root, ...
        'mlsc_current_artifact_root must be an absolute directory.');
    root = local_strip_sep(artifact_root);
    config.current.runner = fullfile(root, 'payload_build', ...
        'run_mlsc_current_payload.sh');
    config.current.build_manifest = fullfile(root, ...
        'mlsc_current_build.mat');
    config.current.resource_manifest = fullfile(root, ...
        'mlsc_current_resources.mat');
    if isempty(gate_a_record)
        config.current.gate_a_record = fullfile(root, ...
            'mlsc_current_gate_a.mat');
    end
end
if ~isempty(gate_a_record)
    local_require_absolute_mat(gate_a_record, ...
        'mlsc_current_gate_a_record must be an absolute .mat path.');
    config.current.gate_a_record = gate_a_record;
end
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

function local_require_absolute_mat(value, message)
if ~ischar(value) || size(value, 1) ~= 1 || isempty(strtrim(value)) || ...
        any(value == char(0))
    error('run_pseudo_CT:InvalidMlscCurrentOverride', message);
end
trimmed = strtrim(value);
if trimmed(1) ~= '/'
    error('run_pseudo_CT:InvalidMlscCurrentOverride', message);
end
if length(trimmed) < 5 || ~strcmp(trimmed(end-3:end), '.mat')
    error('run_pseudo_CT:InvalidMlscCurrentOverride', message);
end
end

function value = local_strip_sep(value)
value = strtrim(value);
while length(value) > 1 && (value(end) == '/' || value(end) == char(92))
    value(end) = '';
end
end
