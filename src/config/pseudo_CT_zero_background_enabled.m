function out = pseudo_CT_zero_background_enabled(manifest_or_defaults, manifest)
%PSEUDO_CT_ZERO_BACKGROUND_ENABLED Resolve manifest-owned background policy.
%   Explicit MANIFEST values always win. Legacy defaults handles remain
%   accepted for callers that have not yet been profile-bound; environment
%   variables are never consulted.

if nargin > 1 && isstruct(manifest)
    manifest_or_defaults = manifest;
end
if nargin < 1 || isempty(manifest_or_defaults)
    manifest_or_defaults = pseudo_CT_resolve_profile('local-current');
end

if isstruct(manifest_or_defaults)
    if ~isfield(manifest_or_defaults, 'zero_background')
        error('PROFILE:MissingManifestField', ...
            'Profile manifest has no zero_background field.');
    end
    out = manifest_or_defaults.zero_background;
    return;
end

out = 'No';
if isa(manifest_or_defaults, 'function_handle')
    handle_name = func2str(manifest_or_defaults);
    if ~isempty(strfind(handle_name, 'defaults_pseudo_CT_launchpad'))
        tmp = pseudo_CT_resolve_profile('launchpad');
        out = tmp.zero_background;
        return;
    elseif ~isempty(strfind(handle_name, 'defaults_pseudo_CT'))
        tmp = pseudo_CT_resolve_profile('local-current');
        out = tmp.zero_background;
        return;
    end
    try
        defaults_value = manifest_or_defaults('zero_background');
        if ischar(defaults_value) && strcmpi(defaults_value, 'Yes')
            out = 'Yes';
        end
    catch  %#ok<CTCH>
    end
end
end
