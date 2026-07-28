function profile = pseudo_CT_profile_selector()
%PSEUDO_CT_PROFILE_SELECTOR Show the dynamic profile selection dialog.
%   The dialog lists editable profiles found under src/config/profiles.
%
%   Minimum supported MATLAB: R2010b.

config_root = fullfile(fileparts(mfilename('fullpath')), '..', 'config');
profiles = pseudo_CT_list_profiles(config_root);
list_str = cell(length(profiles), 1);
for ii = 1:length(profiles)
    desc = profiles(ii).description;
    if isempty(desc)
        list_str{ii} = profiles(ii).name;
    else
        list_str{ii} = sprintf('%s -- %s', profiles(ii).name, desc);
    end
end

[selection, ok] = listdlg( ...
    'PromptString', 'Select pseudo-CT execution profile:', ...
    'SelectionMode', 'single', 'ListString', list_str, ...
    'ListSize', [640 150], 'Name', 'Pseudo-CT Profile');
if ~ok || isempty(selection)
    profile = '';
    return;
end
profile = profiles(selection).name;
end
