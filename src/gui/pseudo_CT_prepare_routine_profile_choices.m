function [profiles, default_index] = pseudo_CT_prepare_routine_profile_choices(config_root)
%PSEUDO_CT_PREPARE_ROUTINE_PROFILE_CHOICES Prepare the routine user choices.
%   The four discovered profiles are available through this user-facing
%   selector.

if nargin < 1 || isempty(config_root)
    config_root = fullfile(fileparts(mfilename('fullpath')), '..', 'config');
end
profiles = pseudo_CT_list_profiles(config_root);
[profiles, default_index] = pseudo_CT_prepare_profile_choices(profiles);
end
