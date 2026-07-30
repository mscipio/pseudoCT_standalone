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

recommended_count = sum(strcmp({profiles.group}, 'recommended'));
specialized_count = sum(strcmp({profiles.group}, 'specialized'));
layout = pseudo_CT_profile_selector_layout(recommended_count, ...
    specialized_count, get_screen_height());
dialog = figure('Name', 'Pseudo-CT Profile', 'NumberTitle', 'off', ...
    'MenuBar', 'none', 'ToolBar', 'none', 'Resize', 'off', ...
    'WindowStyle', 'modal', 'Units', 'pixels', ...
    'Position', [100 100 layout.dialog_width layout.dialog_height], ...
    'CloseRequestFcn', @cancel_selection);

uicontrol('Parent', dialog, 'Style', 'text', ...
    'String', 'Select a pseudo-CT execution profile', ...
    'HorizontalAlignment', 'left', 'FontSize', 12, 'FontWeight', 'bold', ...
    'Position', [24 layout.dialog_height - 38 730 24]);
uicontrol('Parent', dialog, 'Style', 'text', ...
    'String', 'Profile labels describe the workflow; scripts continue to use the stable canonical key.', ...
    'HorizontalAlignment', 'left', ...
    'Position', [24 layout.dialog_height - 60 730 18]);

viewport = uipanel('Parent', dialog, 'BorderType', 'none', 'Units', 'pixels', ...
    'Position', [layout.horizontal_margin layout.bottom_height ...
    layout.viewport_width layout.viewport_height]);
if layout.scroll_needed
    content_y = -layout.maximum_scroll;
else
    content_y = layout.viewport_height - layout.content_height;
end
content_panel = uipanel('Parent', viewport, 'BorderType', 'none', ...
    'Units', 'pixels', 'Position', [0 content_y layout.content_width ...
    layout.content_height]);

recommended_panel = [];
if recommended_count > 0
    recommended_panel = uipanel('Parent', content_panel, ...
        'Title', 'Recommended', 'FontWeight', 'bold', 'Units', 'pixels', ...
        'Position', layout.recommended_panel_position);
end
specialized_panel = [];
if specialized_count > 0
    specialized_panel = uipanel('Parent', content_panel, ...
        'Title', 'Specialized / Development', 'FontWeight', 'bold', ...
        'Units', 'pixels', 'Position', layout.specialized_panel_position);
end

if layout.scroll_needed
    step = min(1, layout.row_height / layout.maximum_scroll);
    page_step = min(1, layout.viewport_height / layout.maximum_scroll);
    uicontrol('Parent', dialog, 'Style', 'slider', 'Units', 'pixels', ...
        'Min', 0, 'Max', layout.maximum_scroll, ...
        'Value', layout.maximum_scroll, 'SliderStep', [step page_step], ...
        'Position', [layout.horizontal_margin + layout.content_width + ...
        layout.scrollbar_gap layout.bottom_height layout.scrollbar_width ...
        layout.viewport_height], 'Callback', @scroll_content);
end

recommended_row = 0;
specialized_row = 0;
for ii = 1:length(profiles)
    if strcmp(profiles(ii).group, 'recommended')
        panel = recommended_panel;
        recommended_row = recommended_row + 1;
        row = recommended_row;
    else
        panel = specialized_panel;
        specialized_row = specialized_row + 1;
        row = specialized_row;
    end
    panel_position = get(panel, 'Position');
    row_bottom = panel_position(4) - layout.panel_header_height - ...
        row * layout.row_height;
    label = profiles(ii).display_name;
    if profiles(ii).recommended
        label = sprintf('%s  [Recommended]', label);
    end
    radio_buttons{ii} = uicontrol('Parent', panel, 'Style', 'radiobutton', ...
        'String', label, 'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
        'Units', 'pixels', 'Position', [18 row_bottom + 30 ...
        panel_position(3) - 36 20], ...
        'Value', ii == selected_index, 'Callback', {@select_profile, ii});
    uicontrol('Parent', panel, 'Style', 'text', ...
        'String', profiles(ii).description, 'HorizontalAlignment', 'left', ...
        'Units', 'pixels', 'Position', [50 row_bottom + 6 ...
        panel_position(3) - 68 20]);
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

    function scroll_content(source, ~)
        position = get(content_panel, 'Position');
        position(2) = -get(source, 'Value');
        set(content_panel, 'Position', position);
    end
end

function screen_height = get_screen_height()
root_units = get(0, 'Units');
cleanup = onCleanup(@() set(0, 'Units', root_units));
set(0, 'Units', 'pixels');
screen_size = get(0, 'ScreenSize');
screen_height = screen_size(4);
end
