function [profiles, default_index] = pseudo_CT_prepare_routine_profile_choices()
%PSEUDO_CT_PREPARE_ROUTINE_PROFILE_CHOICES Prepare the routine user choices.
%   The four profiles come from the static frontend table
%   (pseudo_CT_profile_choices) and are ordered as the selector expects.
%   Minimum supported MATLAB: R2010b.

profiles = pseudo_CT_profile_choices();
[profiles, default_index] = pseudo_CT_prepare_profile_choices(profiles);
end
