function [profiles, default_index] = pseudo_CT_prepare_routine_profile_choices(config_root)
%PSEUDO_CT_PREPARE_ROUTINE_PROFILE_CHOICES Prepare the routine user choices.
%   Canonical development profiles remain loadable by explicit key, but are
%   omitted from this user-facing routine selector. Current-lineage MLSC is
%   an available routine choice.

if nargin < 1 || isempty(config_root)
    config_root = fullfile(fileparts(mfilename('fullpath')), '..', 'config');
end
profiles = pseudo_CT_list_profiles(config_root);
not_routine = strcmp({profiles.name}, 'devel');
profiles(not_routine) = [];
[profiles, default_index] = pseudo_CT_prepare_profile_choices(profiles);
end
