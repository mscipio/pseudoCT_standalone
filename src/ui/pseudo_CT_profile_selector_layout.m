function layout = pseudo_CT_profile_selector_layout(standard_count, ...
        custom_count, historical_count, custom_expanded, ...
        historical_expanded, screen_height, selected_section, ...
        selected_row, previous_scroll)
%PSEUDO_CT_PROFILE_SELECTOR_LAYOUT Calculate compact selector geometry.
%   Standard Processing stays visible. MPRAGE-only Processing and Legacy
%   Processing each have an always-visible heading/subtitle row and
%   independently sized option panels. Oversized layouts are capped at 90
%   percent of the screen height.

if nargin < 7
    selected_section = 0;
end
if nargin < 8
    selected_row = 0;
end
if nargin < 9
    previous_scroll = NaN;
end

layout.dialog_width = 780;
layout.row_height = 54;
layout.panel_header_height = 42;
layout.panel_padding = 4;
layout.group_gap = 8;
layout.disclosure_height = 46;
layout.horizontal_margin = 24;
layout.top_height = 94;
layout.bottom_height = 72;
layout.scrollbar_width = 16;
layout.scrollbar_gap = 8;

layout.standard_panel_height = panel_height(standard_count, layout, true);
if custom_expanded
    layout.custom_panel_height = panel_height(custom_count, layout, false);
else
    layout.custom_panel_height = 0;
end
if historical_expanded
    layout.historical_panel_height = panel_height(historical_count, layout, false);
else
    layout.historical_panel_height = 0;
end

layout.content_height = layout.group_gap + 2 * layout.disclosure_height + ...
    layout.custom_panel_height + layout.historical_panel_height;
layout.preferred_dialog_height = layout.top_height + ...
    layout.standard_panel_height + layout.group_gap + ...
    layout.content_height + layout.bottom_height;
layout.maximum_dialog_height = max(1, floor(0.90 * screen_height));
layout.dialog_height = min(layout.preferred_dialog_height, ...
    layout.maximum_dialog_height);
layout.viewport_height = max(1, layout.dialog_height - ...
    layout.top_height - layout.standard_panel_height - ...
    layout.group_gap - layout.bottom_height);
layout.viewport_width = layout.dialog_width - ...
    2 * layout.horizontal_margin;
layout.scroll_needed = layout.content_height > layout.viewport_height;
layout.maximum_scroll = max(0, layout.content_height - layout.viewport_height);

layout.content_width = layout.viewport_width;
if layout.scroll_needed
    layout.content_width = layout.content_width - ...
        layout.scrollbar_width - layout.scrollbar_gap;
end

layout.historical_panel_position = [0 0 layout.content_width ...
    layout.historical_panel_height];
layout.historical_disclosure_position = [0 ...
    layout.historical_panel_height layout.content_width ...
    layout.disclosure_height];
layout.custom_panel_position = [0 ...
    layout.historical_panel_height + layout.disclosure_height + ...
    layout.group_gap layout.content_width layout.custom_panel_height];
layout.custom_disclosure_position = [0 ...
    layout.custom_panel_position(2) + layout.custom_panel_height ...
    layout.content_width layout.disclosure_height];
layout.standard_panel_position = [layout.horizontal_margin ...
    layout.bottom_height + layout.viewport_height + layout.group_gap ...
    layout.viewport_width layout.standard_panel_height];

% Start at the top of newly scrollable content, but preserve the current
% viewport as sections change. If the selected option is in an expanded
% section, keep its radio button inside the viewport.
layout.scroll_value = layout.maximum_scroll;
if ~isnan(previous_scroll)
    layout.scroll_value = min(layout.maximum_scroll, ...
        max(0, previous_scroll));
end
selected_is_open = (selected_section == 2 && custom_expanded) || ...
    (selected_section == 3 && historical_expanded);
if selected_row > 0 && selected_is_open
    if selected_section == 2
        selected_panel_height = layout.custom_panel_height;
        selected_panel_bottom = layout.custom_panel_position(2);
    else
        selected_panel_height = layout.historical_panel_height;
        selected_panel_bottom = layout.historical_panel_position(2);
    end
    selected_row_bottom = selected_panel_height - ...
        selected_row * layout.row_height;
    selected_radio_center = selected_panel_bottom + ...
        selected_row_bottom + 40;
    layout.scroll_value = min(layout.maximum_scroll, max(0, ...
        selected_radio_center - layout.viewport_height / 2));
end
end

function height = panel_height(count, layout, titled)
height = count * layout.row_height + layout.panel_padding;
if count > 0 && titled
    height = height + layout.panel_header_height;
end
end
