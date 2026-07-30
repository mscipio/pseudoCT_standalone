function layout = pseudo_CT_profile_selector_layout( ...
        recommended_count, specialized_count, screen_height)
%PSEUDO_CT_PROFILE_SELECTOR_LAYOUT Calculate count-aware selector geometry.
%   The returned pixel geometry keeps every profile row at a readable fixed
%   height. When the preferred dialog is taller than 90% of the screen, the
%   content viewport is capped and the caller can expose the remaining rows
%   with a classic uicontrol slider.

layout.dialog_width = 780;
layout.row_height = 58;
layout.panel_header_height = 24;
layout.panel_padding = 4;
layout.group_gap = 12;
layout.horizontal_margin = 24;
layout.top_height = 80;
layout.bottom_height = 76;
layout.scrollbar_width = 16;
layout.scrollbar_gap = 8;

layout.recommended_panel_height = panel_height(recommended_count, layout);
layout.specialized_panel_height = panel_height(specialized_count, layout);
if recommended_count > 0 && specialized_count > 0
    gap_height = layout.group_gap;
else
    gap_height = 0;
end
layout.content_height = layout.recommended_panel_height + ...
    gap_height + layout.specialized_panel_height;

layout.preferred_dialog_height = layout.top_height + ...
    layout.content_height + layout.bottom_height;
layout.maximum_dialog_height = max(1, floor(0.90 * screen_height));
layout.dialog_height = min(layout.preferred_dialog_height, ...
    layout.maximum_dialog_height);
layout.viewport_height = max(1, layout.dialog_height - ...
    layout.top_height - layout.bottom_height);
layout.viewport_width = layout.dialog_width - 2 * layout.horizontal_margin;
layout.scroll_needed = layout.content_height > layout.viewport_height;
layout.maximum_scroll = max(0, layout.content_height - layout.viewport_height);

layout.content_width = layout.viewport_width;
if layout.scroll_needed
    layout.content_width = layout.content_width - ...
        layout.scrollbar_width - layout.scrollbar_gap;
end

specialized_y = 0;
recommended_y = layout.specialized_panel_height + gap_height;
layout.recommended_panel_position = [0 recommended_y layout.content_width ...
    layout.recommended_panel_height];
layout.specialized_panel_position = [0 specialized_y layout.content_width ...
    layout.specialized_panel_height];
end

function height = panel_height(count, layout)
if count > 0
    height = layout.panel_header_height + layout.panel_padding + ...
        count * layout.row_height;
else
    height = 0;
end
end
