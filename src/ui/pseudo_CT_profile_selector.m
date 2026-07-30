function profile = pseudo_CT_profile_selector()
%PSEUDO_CT_PROFILE_SELECTOR Show the profile selection dialog.
%   Returns the filename-derived canonical profile key, or an empty string
%   when the user cancels or closes the window.
%
%   Minimum supported MATLAB: R2010b.

config_root = fullfile(fileparts(mfilename('fullpath')), '..', 'config');
[profiles, selected_index] = pseudo_CT_prepare_profile_choices( ...
    pseudo_CT_list_profiles(config_root));
profile = '';
radio_buttons = cell(length(profiles), 1);

dialog_width = 780;
dialog_height = 500;
dialog = figure('Name', 'Pseudo-CT Profile', 'NumberTitle', 'off', ...
    'MenuBar', 'none', 'ToolBar', 'none', 'Resize', 'off', ...
    'WindowStyle', 'modal', 'Position', [100 100 dialog_width dialog_height], ...
    'CloseRequestFcn', @cancel_selection);

uicontrol('Parent', dialog, 'Style', 'text', ...
    'String', 'Select a pseudo-CT execution profile', ...
    'HorizontalAlignment', 'left', 'FontSize', 12, 'FontWeight', 'bold', ...
    'Position', [24 458 730 24]);
uicontrol('Parent', dialog, 'Style', 'text', ...
    'String', 'Profile labels describe the workflow; scripts continue to use the stable canonical key.', ...
    'HorizontalAlignment', 'left', 'Position', [24 436 730 18]);

recommended_panel = uipanel('Parent', dialog, 'Title', 'Recommended', ...
    'FontWeight', 'bold', 'Position', [0.03 0.49 0.94 0.36]);
specialized_panel = uipanel('Parent', dialog, ...
    'Title', 'Specialized / Development', 'FontWeight', 'bold', ...
    'Position', [0.03 0.15 0.94 0.31]);

recommended_count = sum(strcmp({profiles.group}, 'recommended'));
specialized_count = sum(strcmp({profiles.group}, 'specialized'));
recommended_row = 0;
specialized_row = 0;
for ii = 1:length(profiles)
    if strcmp(profiles(ii).group, 'recommended')
        panel = recommended_panel;
        recommended_row = recommended_row + 1;
        row = recommended_row;
        count = recommended_count;
    else
        panel = specialized_panel;
        specialized_row = specialized_row + 1;
        row = specialized_row;
        count = specialized_count;
    end
    row_height = 1 / max(count, 1);
    row_top = 1 - row * row_height;
    label = profiles(ii).display_name;
    if profiles(ii).recommended
        label = sprintf('%s  [Recommended]', label);
    end
    radio_buttons{ii} = uicontrol('Parent', panel, 'Style', 'radiobutton', ...
        'String', label, 'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
        'Units', 'normalized', 'Position', [0.025 row_top + 0.48 * row_height 0.94 0.34 * row_height], ...
        'Value', ii == selected_index, 'Callback', {@select_profile, ii});
    uicontrol('Parent', panel, 'Style', 'text', ...
        'String', profiles(ii).description, 'HorizontalAlignment', 'left', ...
        'Units', 'normalized', 'Position', [0.065 row_top + 0.08 * row_height 0.90 0.34 * row_height]);
end

uicontrol('Parent', dialog, 'Style', 'pushbutton', 'String', 'Cancel', ...
    'Position', [550 28 90 32], 'Callback', @cancel_selection);
uicontrol('Parent', dialog, 'Style', 'pushbutton', 'String', 'Run Selected', ...
    'FontWeight', 'bold', 'Position', [650 28 105 32], ...
    'Callback', @run_selection);

movegui(dialog, 'center');
uiwait(dialog);
if ishghandle(dialog)
    delete(dialog);
end

    function select_profile(~, ~, index)
        selected_index = index;
        for jj = 1:length(radio_buttons)
            set(radio_buttons{jj}, 'Value', 0);
        end
        set(radio_buttons{index}, 'Value', 1);
    end

    function run_selection(~, ~)
        if ~isempty(selected_index)
            profile = profiles(selected_index).name;
        end
        uiresume(dialog);
    end

    function cancel_selection(~, ~)
        profile = '';
        uiresume(dialog);
    end
end
