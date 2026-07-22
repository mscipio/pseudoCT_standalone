function [bone_enabled, fixed] = fixed_bone_cleanup(manifest)
%PSEUDO_CT_FIXED_BONE_CLEANUP Manifest-owned bone reduction policy.
%   [BONE_ENABLED, FIXED] = PSEUDO_CT_FIXED_BONE_CLEANUP(MANIFEST) returns
%   true because bone reduction is mandatory and cannot be disabled by an
%   environment variable or default fallback. The manifest value is
%   validated: if it ever declares bone_enabled=false, BONE:CleanupFixed
%   is raised.
%
%   When MANIFEST is omitted, the local-current profile is used so that
%   legacy callers retain deterministic behavior without changing the
%   public entrypoint topology.
%
%   FIXED is always true, signalling that the policy is non-overrideable.
%
%   Minimum supported MATLAB: R2010b.

ids = pseudo_CT_error_ids();
fixed = true;

if nargin < 1 || isempty(manifest)
    manifest = pseudo_CT_profile_registry('local-current');
end

if ~isfield(manifest, 'bone_enabled')
    error(ids.PROFILE.MissingManifestField, 'manifest.bone_enabled missing.');
end

bone_enabled = manifest.bone_enabled;

if ~islogical(bone_enabled) || ~isscalar(bone_enabled)
    error(ids.PROFILE.InvalidValue, 'bone_enabled must be a scalar logical.');
end

if ~bone_enabled
    error(ids.BONE.CleanupFixed, ...
          'Bone reduction must remain enabled; manifest disabled it.');
end

end
