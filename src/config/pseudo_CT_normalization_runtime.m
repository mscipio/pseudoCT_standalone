function [source_command, child_lib_path, ignored] = pseudo_CT_normalization_runtime(manifest)
%PSEUDO_CT_NORMALIZATION_RUNTIME Manifest-owned FreeSurfer normalization runtime.
%   [SOURCE_COMMAND, CHILD_LIB_PATH, IGNORED] = ...
%   PSEUDO_CT_NORMALIZATION_RUNTIME(MANIFEST) returns the FreeSurfer
%   environment source_command and the child-process LD_LIBRARY_PATH prefix
%   declared in the manifest.
%
%   PSEUDOCT_FS_LIBSTDCPP_ROOT is ignored and logged. Shell metacharacters
%   in either resource value are rejected with NORMALIZATION:ShellMetachar.
%
%   When MANIFEST is omitted, the local-current profile is used so that
%   legacy callers retain deterministic behavior without changing the
%   public entrypoint topology.
%
%   Minimum supported MATLAB: R2010b.

ids = pseudo_CT_error_ids();
ignored = '';

env_val = getenv('PSEUDOCT_FS_LIBSTDCPP_ROOT');
if ~isempty(env_val)
    ignored = ids.ENV_IGNORED.FS_LIBSTDCPP_ROOT;
    fprintf(1, '[profile-resource-authority] ignored %s=%s\n', ignored, env_val);
end

if nargin < 1 || isempty(manifest)
    manifest = pseudo_CT_profile_registry('local-current');
end

if ~isfield(manifest, 'normalization_resource') || ...
   ~isfield(manifest.normalization_resource, 'source_command')
    error(ids.NORMALIZATION.SourceCommandMissing, ...
          'normalization_resource.source_command missing.');
end

source_command = manifest.normalization_resource.source_command;
child_lib_path = manifest.normalization_resource.child_lib_path;

if ~ischar(source_command) || isempty(source_command)
    error(ids.NORMALIZATION.SourceCommandMissing, ...
          'normalization_resource.source_command is empty.');
end

validate_shell_safe(source_command, ids);
validate_shell_safe(child_lib_path, ids);

end

%% ------------------------------------------------------------------------
function validate_shell_safe(str, ids)

if ~ischar(str)
    error(ids.NORMALIZATION.ShellMetachar, 'Resource value must be a string.');
end

bad_chars = sprintf(';|&$`<>*?[]{}\\()''"\r\n\t');
for ii = 1:length(bad_chars)
    if ~isempty(strfind(str, bad_chars(ii)))
        error(ids.NORMALIZATION.ShellMetachar, ...
              'Normalization resource contains shell metacharacter: %c', bad_chars(ii));
    end
end

end
