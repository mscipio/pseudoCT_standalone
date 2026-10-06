function test_profile_selector_layout()
%TEST_PROFILE_SELECTOR_LAYOUT Verify count-aware selector geometry.
%   Covers the disclosure states headlessly: collapsed (3, 0) is the
%   every-open default and expanded (3, 3) reveals only the specialized
%   set. Inspection checks cover the ASCII disclosure control, the
%   Specialized / Custom title, and hidden-selection retention.

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

collapsed = pseudo_CT_profile_selector_layout(3, 0, 800);
expanded = pseudo_CT_profile_selector_layout(3, 3, 800);
assert(collapsed.specialized_panel_height == 0);
assert(collapsed.content_height == collapsed.recommended_panel_height);
assert(collapsed.recommended_panel_position(2) == 0);
assert(~collapsed.scroll_needed);
assert(expanded.recommended_panel_height == collapsed.recommended_panel_height);
assert(expanded.specialized_panel_height == ...
    expanded.panel_header_height + expanded.panel_padding + 3 * expanded.row_height);
assert(expanded.content_height == expanded.recommended_panel_height + ...
    expanded.group_gap + expanded.specialized_panel_height);
assert(expanded.recommended_panel_position(2) > ...
    expanded.specialized_panel_position(2));
assert(expanded.dialog_height > collapsed.dialog_height);
assert(expanded.row_height == collapsed.row_height);
assert(expanded.dialog_height == expanded.preferred_dialog_height);
assert(expanded.viewport_height > 0);
assert(expanded.content_width == expanded.viewport_width);
assert(collapsed.dialog_height > 0 && collapsed.viewport_height > 0);

collapsed_small = pseudo_CT_profile_selector_layout(3, 0, 600);
expanded_small = pseudo_CT_profile_selector_layout(3, 3, 600);
assert(~collapsed_small.scroll_needed);
assert(expanded_small.scroll_needed);
assert(expanded_small.dialog_height == floor(0.90 * 600));
assert(expanded_small.maximum_scroll == ...
    expanded_small.content_height - expanded_small.viewport_height);
assert(expanded_small.content_width < expanded_small.viewport_width);
assert(expanded_small.row_height == collapsed_small.row_height);

config_root = fullfile(root_dir, 'src', 'config');
profiles = pseudo_CT_list_profiles(config_root);
[ordered, default_index] = pseudo_CT_prepare_profile_choices(profiles);
assert(strcmp(ordered(default_index).name, 'local-current'));
recommended_names = {ordered(strcmp({ordered.group}, 'recommended')).name};
specialized_names = {ordered(strcmp({ordered.group}, 'specialized')).name};
assert(isequal(recommended_names(:)', ...
    {'local-current', 'local-legacy', 'mlsc-legacy'}));
assert(isequal(specialized_names(:)', ...
    {'local-mprage-only', 'mlsc-mprage-only', 'devel'}));
assert(length(recommended_names) == 3);
assert(length(specialized_names) == 3);
recommended_display = {ordered(1).display_name; ordered(2).display_name; ...
    ordered(3).display_name};
assert(isequal(recommended_display, {'LOCAL - Current'; ...
    'LOCAL - Legacy v2.0 (Aether)'; 'MLSC - Legacy v2.0 (Aether)'}));
local_current_config = pseudo_CT_load_profile('local-current', config_root);
local_legacy_config = pseudo_CT_load_profile('local-legacy', config_root);
mlsc_legacy_config = pseudo_CT_load_profile('mlsc-legacy', config_root);
local_mprage_config = pseudo_CT_load_profile('local-mprage-only', config_root);
mlsc_mprage_config = pseudo_CT_load_profile('mlsc-mprage-only', config_root);
devel_config = pseudo_CT_load_profile('devel', config_root);
assert(~isempty(strfind(local_current_config.presentation.display_name, ...
    'LOCAL')));
assert(strcmp(local_current_config.presentation.description, ...
    ['Run the full MPRAGE + UMAP workflow locally ' ...
    'using the current MATLAB source.']));
assert(strcmp(local_legacy_config.presentation.description, ...
    ['Run the full MPRAGE + UMAP workflow locally ' ...
    'using the legacy v2.0 compiled backend (Aether).']));
assert(strcmp(mlsc_legacy_config.presentation.description, ...
    ['Run the full MPRAGE + UMAP workflow on the MLSC cluster ' ...
    'using the legacy v2.0 compiled backend (Aether).']));
assert(isempty(strfind(local_current_config.presentation.description, char(10))));
assert(isempty(strfind(local_legacy_config.presentation.description, char(10))));
assert(isempty(strfind(mlsc_legacy_config.presentation.description, char(10))));
assert(strcmp(local_mprage_config.presentation.display_name, ...
    'Local MPRAGE Only'));
assert(strcmp(mlsc_mprage_config.presentation.display_name, ...
    'MLSC MPRAGE Only'));
assert(strcmp(devel_config.presentation.display_name, ...
    'Development Current MATLAB'));
assert(isempty(strfind(local_mprage_config.presentation.display_name, ...
    '[CUSTOM]')));
assert(isempty(strfind(mlsc_mprage_config.presentation.display_name, ...
    '[CUSTOM]')));
assert(isempty(strfind(devel_config.presentation.display_name, ...
    '[DEVELOPMENT]')));
assert(all(double(local_current_config.presentation.description) < 128));
assert(all(double(local_legacy_config.presentation.description) < 128));
assert(all(double(mlsc_legacy_config.presentation.description) < 128));
assert(all(double(local_mprage_config.presentation.display_name) < 128));
assert(all(double(mlsc_mprage_config.presentation.display_name) < 128));
assert(all(double(devel_config.presentation.display_name) < 128));
assert(~ismember('mlsc', {ordered.name}));
assert(~ismember('launchpad', {ordered.name}));
assert(~ismember('launchpad-mprage-only', {ordered.name}));
assert(~ismember('local-near-parity-r2010b', {ordered.name}));

selector_source = local_read(fullfile(root_dir, 'src', 'ui', ...
    'pseudo_CT_profile_selector.m'));
assert(~isempty(strfind(selector_source, 'Specialized / Custom')));
assert(isempty(strfind(selector_source, 'Specialized / Development')));
assert(~isempty(strfind(selector_source, 'expanded = false')));
assert(~isempty(strfind(selector_source, 'profiles(selected_index).display_name')));
layout_source = local_read(fullfile(root_dir, 'src', 'ui', ...
    'pseudo_CT_profile_selector_layout.m'));
prepare_source = local_read(fullfile(root_dir, 'src', 'ui', ...
    'pseudo_CT_prepare_profile_choices.m'));
assert(isempty(strfind(layout_source, 'strjoin(')));
assert(isempty(strfind(layout_source, 'addParameter')));
assert(isempty(strfind(layout_source, 'string(')));
assert(isempty(strfind(prepare_source, 'strjoin(')));
assert(isempty(strfind(prepare_source, 'addParameter')));
assert(isempty(strfind(prepare_source, 'string(')));
assert(isempty(strfind(selector_source, 'addParameter')));
assert(isempty(strfind(selector_source, 'string(')));
assert(~isempty(strfind(selector_source, '[+]')));
assert(~isempty(strfind(selector_source, '[-]')));
assert(isempty(strfind(selector_source, '[Recommended]')));
assert(isempty(strfind(selector_source, 'Profile labels describe the workflow')));
assert(~isempty(strfind(selector_source, '''Cancel''')));
assert(~isempty(strfind(selector_source, 'Run Selected')));
assert(~isempty(strfind(selector_source, 'Selected (hidden)')));
assert(~isempty(strfind(selector_source, '''Visible'', ''off''')));
assert(~isempty(strfind(selector_source, '''Visible'', ''on''')));
assert(~isempty(strfind(selector_source, 'expanded = ~expanded')));
assert(~isempty(strfind(selector_source, ...
    'pseudo_CT_profile_selector_layout(recommended_count,')));
assert(~isempty(strfind(selector_source, ...
    'strcmp(profiles(selected_index).group')));
assert(~isempty(strfind(selector_source, '''Style'', ''radiobutton''')));
assert(~isempty(strfind(selector_source, 'pseudo_CT_profile_selector_layout')));
assert(~isempty(strfind(selector_source, '''Style'', ''slider''')));
assert(~isempty(strfind(selector_source, 'profiles(selected_index).name')));
assert(isempty(strfind(selector_source, 'listdlg')));
assert(isempty(strfind(selector_source, 'strjoin')));
assert(isempty(strfind(selector_source, '''Style'', ''listbox''')));
assert(isempty(strfind(selector_source, '''Style'', ''checkbox''')));
assert(isempty(strfind(selector_source, '''Style'', ''togglebutton''')));
assert(isempty(strfind(selector_source, '''Style'', ''popupmenu''')));
assert(all(double(selector_source) < 128));

fprintf('Profile selector layout tests passed: readable rows, screen cap, and scrolling fallback.\n');
fprintf('Selector disclosure tests passed: collapsed default, expand contents, hidden-selection retention, valid layouts both states.\n');
end

function text = local_read(file_path)
fid = fopen(file_path, 'r');
assert(fid ~= -1);
text = fread(fid, inf, '*char')';
fclose(fid);
end
