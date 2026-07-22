function value = pseudo_CT_validate_aliasing(value, manifest)
%PSEUDO_CT_VALIDATE_ALIASING Validate a public anti-aliasing override.
%   VALUE = PSEUDO_CT_VALIDATE_ALIASING(VALUE, MANIFEST) accepts numeric or
%   logical scalar 0/1 values only. The profile manifest owns the allowed
%   values; no environment or default fallback can widen this contract.
%
%   Minimum supported MATLAB: R2010b.

ids = pseudo_CT_error_ids();

if nargin < 2 || ~isstruct(manifest) || ...
        ~isfield(manifest, 'aliasing_override')
    error(ids.ALIAS.InvalidOverride, ...
          'Profile manifest has no aliasing_override policy.');
end

if ~(isnumeric(value) || islogical(value)) || ~isscalar(value) || ...
        ~ismember(double(value), manifest.aliasing_override)
    error(ids.ALIAS.InvalidOverride, ...
          'Aliasing override must be a scalar numeric or logical 0/1 value.');
end

value = double(value);
end
