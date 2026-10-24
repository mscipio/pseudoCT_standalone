function label = pseudo_CT_profile_selector_label(profile_name, fallback_label)
%PSEUDO_CT_PROFILE_SELECTOR_LABEL Return concise, user-facing profile labels.
%   Canonical profile names remain the runtime identifiers. The em dash is
%   generated at runtime to keep this source compatible with older MATLAB
%   installations that expect ASCII-only M-files.

if nargin < 2 || isempty(fallback_label)
    fallback_label = profile_name;
end
dash = char(8212);
switch profile_name
    case 'local-current'
        label = ['PseudoCT v3 ' dash ' Local'];
    case 'mlsc-current'
        label = ['PseudoCT v3 ' dash ' MLSC'];
    case 'local-mprage-only'
        label = ['MPRAGE-only ' dash ' Local'];
    case 'mlsc-mprage-only'
        label = ['MPRAGE-only ' dash ' MLSC'];
    case 'local-legacy'
        label = ['PseudoCT v2 (Aether) ' dash ' Local'];
    case 'mlsc-legacy'
        label = ['PseudoCT v2 (Aether) ' dash ' MLSC'];
    case 'launchpad-legacy'
        label = ['PseudoCT v2 (Aether) ' dash ' Launchpad'];
    otherwise
        label = fallback_label;
end
end
