function test_profile_selector_layout()
%TEST_PROFILE_SELECTOR_LAYOUT Verify count-aware selector geometry.

scripts_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(scripts_dir);
src_path = genpath(fullfile(root_dir, 'src'));
old_path = path();
addpath(src_path, '-begin');
cleanup = onCleanup(@() path(old_path));

layout = pseudo_CT_profile_selector_layout(2, 4, 1200);
assert(~layout.scroll_needed);
assert(layout.dialog_height == layout.preferred_dialog_height);
assert(layout.row_height == 58);
assert(layout.recommended_panel_height == ...
    layout.panel_header_height + layout.panel_padding + 2 * layout.row_height);
assert(layout.specialized_panel_height == ...
    layout.panel_header_height + layout.panel_padding + 4 * layout.row_height);
assert(layout.recommended_panel_position(2) > ...
    layout.specialized_panel_position(2));

capped = pseudo_CT_profile_selector_layout(2, 20, 600);
assert(capped.scroll_needed);
assert(capped.dialog_height == floor(0.90 * 600));
assert(capped.dialog_height <= 600);
assert(capped.maximum_scroll == ...
    capped.content_height - capped.viewport_height);
assert(capped.row_height == layout.row_height);
assert(capped.content_width < capped.viewport_width);

recommended_only = pseudo_CT_profile_selector_layout(3, 0, 800);
assert(recommended_only.specialized_panel_height == 0);
assert(recommended_only.content_height == ...
    recommended_only.recommended_panel_height);
assert(recommended_only.recommended_panel_position(2) == 0);

fprintf('Profile selector layout tests passed: readable rows, screen cap, and scrolling fallback.\n');
end
