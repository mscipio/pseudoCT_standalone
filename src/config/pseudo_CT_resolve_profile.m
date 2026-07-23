function manifest = pseudo_CT_resolve_profile(name, repo_root)
%PSEUDO_CT_RESOLVE_PROFILE Resolve a canonical profile by name.
%   MANIFEST = PSEUDO_CT_RESOLVE_PROFILE(NAME, REPO_ROOT) returns the
%   validated manifest for the named profile. Profiles are discovered
%   dynamically from src/config/spm_profiles/ -- any .m file in that
%   directory defines a valid profile.
%
%   Resolution is by canonical name only. No environment variable,
%   GUI dropdown, or public selector is consulted. Unknown names raise
%   PROFILE:InvalidName.
%
%   REPO_ROOT defaults to the repository root inferred from this file's
%   location.
%
%   Minimum supported MATLAB: R2010b.

if nargin < 2 || isempty(repo_root)
    config_dir = fileparts(mfilename('fullpath'));
    repo_root = fileparts(fileparts(config_dir));
end

manifest = pseudo_CT_profile_registry(name, repo_root);

end
