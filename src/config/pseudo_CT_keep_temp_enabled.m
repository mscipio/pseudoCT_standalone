function out = pseudo_CT_keep_temp_enabled(defaults_handle)
%PSEUDO_CT_KEEP_TEMP_ENABLED Resolve whether intermediate temp files should be kept.
%   OUT = PSEUDO_CT_KEEP_TEMP_ENABLED(DEFAULTS_HANDLE) returns 'Yes' when
%   intermediate MR_PET/tmp/ files should be preserved, and 'No' otherwise.
%
%   Resolution order:
%     1. Environment variable PSEUDOCT_KEEP_TMP: if set to '1', 'true', or
%        'yes' (case-insensitive), returns 'Yes'.
%     2. Otherwise evaluates DEFAULTS_HANDLE('keep_temp_files'). The
%        defaults files define keep_temp_files = 'No'.
%
%   DEFAULTS_HANDLE should be a function handle: @defaults_pseudo_CT or
%   @defaults_pseudo_CT_launchpad.
%
%   Minimum supported MATLAB: R2010b (strcmpi, no contains/startsWith).

env_val = getenv('PSEUDOCT_KEEP_TMP');
if ~isempty(env_val)
    if strcmpi(env_val, '1') || strcmpi(env_val, 'true') || strcmpi(env_val, 'yes')
        out = 'Yes';
        return;
    end
end

try
    out = defaults_handle('keep_temp_files');
catch
    out = 'No';
end

return
