function out = pseudo_CT_zero_background_enabled(defaults_handle)
%PSEUDO_CT_ZERO_BACKGROUND_ENABLED Resolve whether final att_map background should be zeroed.
%   OUT = PSEUDO_CT_ZERO_BACKGROUND_ENABLED(DEFAULTS_HANDLE) returns 'Yes' when
%   the final att_map.nii background (non-head voxels) should be set to zero,
%   and 'No' otherwise.
%
%   Resolution order:
%     1. PSEUDOCT_ZERO_BACKGROUND values '1', 'true', or 'yes'.
%     2. DEFAULTS_HANDLE('zero_background').
%     3. 'No' when the defaults key is unavailable or invalid.
%
%   DEFAULTS_HANDLE should be @defaults_pseudo_CT,
%   @defaults_pseudo_CT_launchpad, or an equivalent deployed-defaults
%   function handle.
%
%   Clinical warning: 'Yes' zeros the final att_map background and may
%   alter PET AC results. Intended for research/diagnostic use only.
%
%   Minimum supported MATLAB: R2010b (strcmpi, no contains/startsWith).

env_val = getenv('PSEUDOCT_ZERO_BACKGROUND');
if ~isempty(env_val)
    if strcmpi(env_val, '1') || strcmpi(env_val, 'true') || strcmpi(env_val, 'yes')
        out = 'Yes';
        return;
    end
end

out = 'No';
try
    defaults_value = defaults_handle('zero_background');
    if ischar(defaults_value) && strcmpi(defaults_value, 'Yes')
        out = 'Yes';
    end
catch  %#ok<CTCH>
end

return
