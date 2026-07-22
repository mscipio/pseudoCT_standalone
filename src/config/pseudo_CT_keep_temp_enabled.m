function out = pseudo_CT_keep_temp_enabled(defaults_handle)
%PSEUDO_CT_KEEP_TEMP_ENABLED Resolve whether intermediate temp files should be kept.
%   OUT = PSEUDO_CT_KEEP_TEMP_ENABLED(DEFAULTS_HANDLE) returns 'Yes' when
%   intermediate MR_PET/tmp/ files should be preserved, and 'No' otherwise.
%
%   The legacy helper evaluates DEFAULTS_HANDLE('keep_temp_files') only.
%   PSEUDOCT_KEEP_TMP is intentionally not consulted; cleanup_owner is the
%   profile-owned authority for supported processing.
%
%   DEFAULTS_HANDLE should be a function handle: @defaults_pseudo_CT or
%   @defaults_pseudo_CT_launchpad.
%
%   Minimum supported MATLAB: R2010b (strcmpi, no contains/startsWith).

try
    out = defaults_handle('keep_temp_files');
catch
    out = 'No';
end

return
