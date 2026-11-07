function profiles = pseudo_CT_list_profiles(include_presentation)
%PSEUDO_CT_LIST_PROFILES Canonical profiles from the registry.
%   PROFILES = PSEUDO_CT_LIST_PROFILES() returns one struct per canonical key
%   (name, function_name, display_name, description, group, recommended, order)
%   in registry order. Presentation metadata comes from each profile's own
%   configuration; PSEUDO_CT_LIST_PROFILES(false) returns the keys only.
%   Minimum supported MATLAB: R2010b.

if nargin < 1
    include_presentation = true;
end
keys = pseudo_CT_profile_registry('keys');
profiles = struct('name', {}, 'function_name', {}, 'display_name', {}, ...
    'description', {}, 'group', {}, 'recommended', {}, 'order', {});
for ii = 1:length(keys)
    presentation = struct('display_name', '', 'description', '', 'group', '', ...
        'recommended', false, 'order', 0);
    if include_presentation
        config = pseudo_CT_profile_registry('invoke', keys{ii});
        presentation = check_presentation(config, keys{ii});
    end
    profiles(ii) = struct('name', keys{ii}, ...
        'function_name', strrep(keys{ii}, '-', '_'), ...
        'display_name', presentation.display_name, ...
        'description', presentation.description, ...
        'group', presentation.group, ...
        'recommended', presentation.recommended, ...
        'order', presentation.order);
end
end

function presentation = check_presentation(config, profile_name)
if ~isstruct(config) || numel(config) ~= 1 || ...
        ~isfield(config, 'presentation') || ~isstruct(config.presentation)
    error('pseudo_CT:InvalidProfile', ...
        'Profile %s is missing presentation metadata.', profile_name);
end
presentation = config.presentation;
required = {'display_name'; 'description'; 'group'; 'recommended'; 'order'};
for ii = 1:length(required)
    if ~isfield(presentation, required{ii})
        error('pseudo_CT:InvalidProfile', ...
            'Profile %s presentation is missing %s.', ...
            profile_name, required{ii});
    end
end
end
