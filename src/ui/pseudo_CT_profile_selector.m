function profile = pseudo_CT_profile_selector()
%PSEUDO_CT_PROFILE_SELECTOR Show the profile selection dialog.
%   Returns the filename-derived canonical profile key, or an empty string
%   when the user cancels or closes the window.
%
%   Recommended profiles are always visible. Specialized / Custom profiles
%   start collapsed on every open. The disclosure pushbutton toggles between
%   an expand marker [+] and a collapse marker [-] (ASCII-safe expand and
%   collapse affordance) with clean reflow through
%   pseudo_CT_profile_selector_layout. A collapsed specialized selection is
%   retained and shown in the collapsed summary label; re-expand restores
%   the checked row. No silent switch to local-current occurs.
%
%   Minimum supported MATLAB: R2010b.

config_root = fullfile(fileparts(mfilename('fullpath')), '..', 'config');
[profiles, selected_index] = pseudo_CT_prepare_profile_choices( ...
    pseudo_CT_list_profiles(config_root));
profile = '';
radio_buttons = cell(length(profiles), 1);
description_handles = cell(length(profiles), 1);

recommended_count = sum(strcmp({profiles.group}, 'recommended'));
specialized_count = sum(strcmp({profiles.group}, 'specialized'));
screen_height = get_screen_height();
expanded = false;
layout = pseudo_CT_profile_selector_layout(recommended_count, ...
    0, screen_height);
expanded_layout = pseudo_CT_profile_selector_layout(recommended_count, ...
    specialized_count, screen_height);
dialog = figure('Name', 'Pseudo-CT Profile', 'NumberTitle', 'off', ...
    'MenuBar', 'none', 'ToolBar', 'none', 'Resize', 'off', ...
    'WindowStyle', 'modal', 'Units', 'pixels', ...
    'Position', [100 100 layout.dialog_width layout.dialog_height], ...
    'CloseRequestFcn', @cancel_selection);

header_title = uicontrol('Parent', dialog, 'Style', 'text', ...
    'String', 'Select a pseudo-CT execution profile', ...
    'HorizontalAlignment', 'left', 'FontSize', 12, 'FontWeight', 'bold', ...
    'Position', [24 layout.dialog_height - 38 730 24]);
header_subtitle = uicontrol('Parent', dialog, 'Style', 'text', ...
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
        'Title', 'Specialized / Custom', 'FontWeight', 'bold', ...
        'Units', 'pixels', 'Position', expanded_layout.specialized_panel_position, ...
        'Visible', 'off');
end

slider_handle = uicontrol('Parent', dialog, 'Style', 'slider', ...
    'Units', 'pixels', 'Min', 0, 'Max', max(1, layout.maximum_scroll), ...
    'Value', layout.maximum_scroll, 'Visible', 'off', ...
    'Position', [layout.horizontal_margin + layout.content_width + ...
    layout.scrollbar_gap layout.bottom_height layout.scrollbar_width ...
    layout.viewport_height], 'Callback', @scroll_content);
if layout.scroll_needed
    step = min(1, layout.row_height / layout.maximum_scroll);
    page_step = min(1, layout.viewport_height / layout.maximum_scroll);
    set(slider_handle, 'Max', layout.maximum_scroll, ...
        'Value', layout.maximum_scroll, ...
        'SliderStep', [step page_step], 'Visible', 'on');
end

recommended_row = 0;
specialized_row = 0;
for ii = 1:length(profiles)
    if strcmp(profiles(ii).group, 'recommended')
        panel = recommended_panel;
        recommended_row = recommended_row + 1;
        row = recommended_row;
        row_layout = layout;
        panel_height = layout.recommended_panel_height;
    else
        panel = specialized_panel;
        specialized_row = specialized_row + 1;
        row = specialized_row;
        row_layout = expanded_layout;
        panel_height = expanded_layout.specialized_panel_height;
    end
    row_bottom = panel_height - row_layout.panel_header_height - ...
        row * row_layout.row_height;
    label = profiles(ii).display_name;
    if profiles(ii).recommended
        label = sprintf('%s  [Recommended]', label);
    end
    row_width = row_layout.content_width;
    radio_buttons{ii} = uicontrol('Parent', panel, 'Style', 'radiobutton', ...
        'String', label, 'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
        'Units', 'pixels', 'Position', [18 row_bottom + 30 ...
        row_width - 36 20], ...
        'Value', ii == selected_index, 'Callback', {@select_profile, ii});
    if strcmp(profiles(ii).group, 'specialized')
        set(radio_buttons{ii}, 'Visible', 'off');
    end
    description_handles{ii} = uicontrol('Parent', panel, 'Style', 'text', ...
        'String', profiles(ii).description, 'HorizontalAlignment', 'left', ...
        'Units', 'pixels', 'Position', [50 row_bottom + 6 ...
        row_width - 68 20]);
    if strcmp(profiles(ii).group, 'specialized')
        set(description_handles{ii}, 'Visible', 'off');
    end
end

disclosure_handle = uicontrol('Parent', dialog, 'Style', 'pushbutton', ...
    'String', collapsed_label(specialized_count), ...
    'HorizontalAlignment', 'center', ...
    'Position', [24 28 250 32], 'Callback', @toggle_disclosure);
summary_handle = uicontrol('Parent', dialog, 'Style', 'text', ...
    'String', '', 'HorizontalAlignment', 'left', ...
    'Position', [284 28 256 32]);
update_summary();

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
        update_summary();
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

    function toggle_disclosure(~, ~)
        expanded = ~expanded;
        apply_disclosure_state();
    end

    function apply_disclosure_state()
        if expanded
            visible_count = specialized_count;
        else
            visible_count = 0;
        end
        layout = pseudo_CT_profile_selector_layout(recommended_count, ...
            visible_count, screen_height);
        set(dialog, 'Position', ...
            [100 100 layout.dialog_width layout.dialog_height]);
        set(header_title, 'Position', ...
            [24 layout.dialog_height - 38 730 24]);
        set(header_subtitle, 'Position', ...
            [24 layout.dialog_height - 60 730 18]);
        set(viewport, 'Position', [layout.horizontal_margin ...
            layout.bottom_height layout.viewport_width ...
            layout.viewport_height]);
        if layout.scroll_needed
            content_y = -layout.maximum_scroll;
        else
            content_y = layout.viewport_height - layout.content_height;
        end
        set(content_panel, 'Position', [0 content_y ...
            layout.content_width layout.content_height]);
        if ~isempty(recommended_panel)
            set(recommended_panel, 'Position', ...
                layout.recommended_panel_position);
        end
        if ~isempty(specialized_panel)
            if expanded
                set(specialized_panel, 'Position', ...
                    layout.specialized_panel_position, 'Visible', 'on');
            else
                set(specialized_panel, 'Visible', 'off');
            end
        end
        for kk = 1:length(profiles)
            radio_position = get(radio_buttons{kk}, 'Position');
            radio_position(3) = layout.content_width - 36;
            set(radio_buttons{kk}, 'Position', radio_position);
            desc_position = get(description_handles{kk}, 'Position');
            desc_position(3) = layout.content_width - 68;
            set(description_handles{kk}, 'Position', desc_position);
            if strcmp(profiles(kk).group, 'specialized')
                if expanded
                    set(radio_buttons{kk}, 'Visible', 'on');
                    set(description_handles{kk}, 'Visible', 'on');
                else
                    set(radio_buttons{kk}, 'Visible', 'off');
                    set(description_handles{kk}, 'Visible', 'off');
                end
            end
        end
        if layout.scroll_needed
            step = min(1, layout.row_height / layout.maximum_scroll);
            page_step = min(1, layout.viewport_height / layout.maximum_scroll);
            set(slider_handle, 'Max', layout.maximum_scroll, ...
                'Value', layout.maximum_scroll, ...
                'SliderStep', [step page_step], ...
                'Position', [layout.horizontal_margin + ...
                layout.content_width + layout.scrollbar_gap ...
                layout.bottom_height layout.scrollbar_width ...
                layout.viewport_height], 'Visible', 'on');
        else
            set(slider_handle, 'Visible', 'off', ...
                'Position', [layout.horizontal_margin + ...
                layout.content_width + layout.scrollbar_gap ...
                layout.bottom_height layout.scrollbar_width ...
                layout.viewport_height]);
        end
        if expanded
            set(disclosure_handle, 'String', '[-] Hide Specialized / Custom');
        else
            set(disclosure_handle, 'String', ...
                collapsed_label(specialized_count));
        end
        update_summary();
    end

    function update_summary()
        if ~expanded && ~isempty(selected_index) && ...
                strcmp(profiles(selected_index).group, 'specialized')
            set(summary_handle, 'String', ['Selected (hidden): ' ...
                profiles(selected_index).display_name]);
        else
            set(summary_handle, 'String', '');
        end
    end
end

function label = collapsed_label(specialized_count)
label = sprintf('[+] Show Specialized / Custom (%d)', specialized_count);
end

function screen_height = get_screen_height()
root_units = get(0, 'Units');
cleanup = onCleanup(@() set(0, 'Units', root_units));
set(0, 'Units', 'pixels');
screen_size = get(0, 'ScreenSize');
screen_height = screen_size(4);
end
