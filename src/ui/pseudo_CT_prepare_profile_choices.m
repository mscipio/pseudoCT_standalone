function [profiles, default_index] = pseudo_CT_prepare_profile_choices(profiles)
%PSEUDO_CT_PREPARE_PROFILE_CHOICES Order profile metadata for the selector.
%   Recommended profiles precede specialized profiles. Profile-owned order
%   values determine order within each group. LOCAL-CURRENT is selected by
%   default when present; otherwise the first recommended profile is used.

group_rank = zeros(length(profiles), 1);
order_rank = zeros(length(profiles), 1);
for ii = 1:length(profiles)
    group_rank(ii) = 1 + strcmp(profiles(ii).group, 'specialized');
    order_rank(ii) = profiles(ii).order;
end
[~, indices] = sortrows([group_rank order_rank (1:length(profiles))']);
profiles = profiles(indices);

default_index = find(strcmp({profiles.name}, 'local-current'), 1);
if isempty(default_index)
    default_index = find([profiles.recommended], 1);
end
if isempty(default_index) && ~isempty(profiles)
    default_index = 1;
end
end
