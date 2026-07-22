function [policy, ignored] = cleanup_owner(manifest)
%PSEUDO_CT_CLEANUP_OWNER Manifest-owned cleanup/retention policy.
%   [POLICY, IGNORED] = PSEUDO_CT_CLEANUP_OWNER(MANIFEST) returns the
%   cleanup policy declared in the profile manifest. The environment
%   variable PSEUDOCT_KEEP_TMP is logged but cannot alter cleanup or
%   retention.
%
%   When MANIFEST is omitted, the local-current profile is used so that
%   legacy callers retain deterministic behavior without changing the
%   public entrypoint topology.
%
%   POLICY is one of: 'remove_on_success', 'keep_on_success'.
%   IGNORED is the ENV_IGNORED identifier when KEEP_TMP is set, otherwise ''.
%
%   Minimum supported MATLAB: R2010b.

ids = pseudo_CT_error_ids();
ignored = '';

env_val = getenv('PSEUDOCT_KEEP_TMP');
if ~isempty(env_val)
    ignored = ids.ENV_IGNORED.KEEP_TMP;
    fprintf(1, '[profile-resource-authority] ignored %s=%s\n', ignored, env_val);
end

if nargin < 1 || isempty(manifest)
    manifest = pseudo_CT_profile_registry('local-current');
end

policy = manifest.cleanup_policy;

valid_policies = {'remove_on_success', 'keep_on_success'};
if ~ischar(policy) || ~ismember(policy, valid_policies)
    error(ids.PROFILE.InvalidValue, 'Invalid cleanup_policy: %s', char(policy));
end

end
