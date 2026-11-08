function pseudo_CT_require_application_layout(artifact_root)
%PSEUDO_CT_REQUIRE_APPLICATION_LAYOUT Refuse an application run from a source checkout.
%   PSEUDO_CT_REQUIRE_APPLICATION_LAYOUT(ARTIFACT_ROOT) is a no-op for an installed
%   distribution. A source checkout is development-only: it has no installed
%   compiled Runtime and must never resolve a legacy artifact tree, so validation
%   and submission fail closed with an actionable message unless an explicit
%   development artifact root (ARTIFACT_ROOT, nonempty) is supplied.
%   Minimum supported MATLAB: R2010b.

layout = pseudo_CT_package_layout();
if strcmp(layout.mode, 'source')
    if nargin < 1 || ~ischar(artifact_root) || isempty(strtrim(artifact_root))
        error('pseudo_CT:SourceCheckoutDevelopmentOnly', ...
            ['The source checkout is development-only; install the pseudoCT ' ...
            'distribution to run an application profile. An explicit artifact root ' ...
            '(--current-artifact-root, accepted only for the MLSC profiles) is a ' ...
            'development-only override.']);
    end
end
end
