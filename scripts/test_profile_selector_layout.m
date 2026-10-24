function test_profile_selector_layout()
%TEST_PROFILE_SELECTOR_LAYOUT Verify count-aware selector geometry.
%   Covers the disclosure states headlessly: collapsed is the every-open
%   default and expanded reveals the historical / other profile set.
%   Inspection checks cover the ASCII disclosure control and hidden-selection
%   retention.

scripts_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(scripts_dir);
src_path = genpath(fullfile(root_dir, 'src'));
old_path = path();
addpath(src_path, '-begin');
cleanup = onCleanup(@() path(old_path));

collapsed = pseudo_CT_profile_selector_layout(1, 2, 3, false, false, 1200);
custom_open = pseudo_CT_profile_selector_layout(1, 2, 3, true, false, 1200);
historical_open = pseudo_CT_profile_selector_layout(1, 2, 3, false, true, 1200);
both_open = pseudo_CT_profile_selector_layout(1, 2, 3, true, true, 1200);
assert(~collapsed.scroll_needed);
assert(collapsed.dialog_height == collapsed.preferred_dialog_height);
assert(collapsed.row_height == 54);
assert(collapsed.custom_panel_height == 0);
assert(collapsed.historical_panel_height == 0);
assert(collapsed.standard_panel_height == ...
    collapsed.panel_header_height + collapsed.panel_padding + collapsed.row_height);
assert(collapsed.content_height == ...
    collapsed.group_gap + 2 * collapsed.disclosure_height);
assert(collapsed.standard_panel_position(2) == ...
    collapsed.bottom_height + collapsed.viewport_height + collapsed.group_gap);
assert(collapsed.standard_panel_position(2) + ...
    collapsed.standard_panel_height == ...
    collapsed.dialog_height - collapsed.top_height);
assert(collapsed.standard_panel_position(2) > ...
    collapsed.custom_disclosure_position(2));
assert(collapsed.custom_disclosure_position(2) > ...
    collapsed.historical_disclosure_position(2));
assert(custom_open.custom_panel_height == ...
    custom_open.panel_padding + 2 * custom_open.row_height);
assert(custom_open.historical_panel_height == 0);
assert(custom_open.standard_panel_position(2) > ...
    custom_open.custom_disclosure_position(2));
assert(historical_open.custom_panel_height == 0);
assert(historical_open.historical_panel_height == ...
    historical_open.panel_padding + 3 * historical_open.row_height);
assert(both_open.custom_panel_height > 0 && both_open.historical_panel_height > 0);
assert(both_open.dialog_height > custom_open.dialog_height);
assert(both_open.dialog_height > historical_open.dialog_height);
assert(both_open.content_width == both_open.viewport_width);

collapsed_small = pseudo_CT_profile_selector_layout(1, 2, 3, false, false, 600);
both_open_small = pseudo_CT_profile_selector_layout(1, 2, 3, true, true, 600);
assert(~collapsed_small.scroll_needed);
assert(both_open_small.scroll_needed);
assert(both_open_small.dialog_height == floor(0.90 * 600));
assert(both_open_small.maximum_scroll == ...
    both_open_small.content_height - both_open_small.viewport_height);
assert(both_open_small.content_width < both_open_small.viewport_width);
assert(both_open_small.row_height == collapsed_small.row_height);
assert(both_open_small.bottom_height >= 60);
assert(both_open_small.bottom_height + both_open_small.viewport_height <= ...
    both_open_small.dialog_height);

custom_selected_small = pseudo_CT_profile_selector_layout(1, 2, 3, ...
    true, true, 600, 2, 2, NaN);
historical_selected_small = pseudo_CT_profile_selector_layout(1, 2, 3, ...
    true, true, 600, 3, 2, NaN);
custom_center = custom_selected_small.custom_panel_position(2) + ...
    custom_selected_small.custom_panel_height - ...
    2 * custom_selected_small.row_height + 40;
historical_center = historical_selected_small.historical_panel_position(2) + ...
    historical_selected_small.historical_panel_height - ...
    2 * historical_selected_small.row_height + 40;
assert(custom_selected_small.scroll_value <= custom_center);
assert(custom_center <= custom_selected_small.scroll_value + ...
    custom_selected_small.viewport_height);
assert(historical_selected_small.scroll_value <= historical_center);
assert(historical_center <= historical_selected_small.scroll_value + ...
    historical_selected_small.viewport_height);
preserved_scroll = pseudo_CT_profile_selector_layout(1, 2, 3, ...
    true, true, 600, 1, 1, 20);
assert(preserved_scroll.scroll_value == 20);

config_root = fullfile(root_dir, 'src', 'config');
all_profiles = pseudo_CT_list_profiles(config_root);
all_names = {all_profiles.name};
assert(ismember('mlsc-current', all_names)); % Active canonical selector ID.
assert(ismember('devel', all_names)); % Definition remains for explicit developer paths.
assert(ismember('launchpad-legacy', all_names));
assert(~ismember('launchpad', all_names));
assert(~ismember('launchpad-mprage-only', all_names));
[ordered, default_index] = ...
    pseudo_CT_prepare_routine_profile_choices(config_root);
assert(strcmp(ordered(default_index).name, 'mlsc-current'));
expected_routine_names = {'local-current', 'mlsc-current', ...
    'local-mprage-only', 'mlsc-mprage-only', 'local-legacy', ...
    'mlsc-legacy', 'launchpad-legacy'};
assert(isequal(sort({ordered.name}), sort(expected_routine_names)));
assert(~ismember('devel', {ordered.name}));
recommended_group_names = ...
    {ordered(strcmp({ordered.group}, 'recommended')).name};
specialized_names = {ordered(strcmp({ordered.group}, 'specialized')).name};
assert(isequal(recommended_group_names, {'local-current'}));
assert(isequal(sort(specialized_names), sort({'local-legacy', ...
    'mlsc-current', 'mlsc-legacy', 'launchpad-legacy', ...
    'local-mprage-only', 'mlsc-mprage-only'})));
assert(length(recommended_group_names) == 1);
assert(length(specialized_names) == 6);
local_current_config = pseudo_CT_load_profile('local-current', config_root);
mlsc_current_config = pseudo_CT_load_profile('mlsc-current', config_root);
local_legacy_config = pseudo_CT_load_profile('local-legacy', config_root);
mlsc_legacy_config = pseudo_CT_load_profile('mlsc-legacy', config_root);
local_mprage_config = pseudo_CT_load_profile('local-mprage-only', config_root);
mlsc_mprage_config = pseudo_CT_load_profile('mlsc-mprage-only', config_root);
launchpad_legacy_config = pseudo_CT_load_profile('launchpad-legacy', config_root);
devel_config = pseudo_CT_load_profile('devel', config_root);
assert(~isempty(strfind(local_current_config.presentation.display_name, ...
    'Local MATLAB - This Computer')));
assert(strcmp(local_current_config.presentation.description, ...
    ['Run the pseudoCT pipeline on this computer using a chosen MATLAB ' ...
    'version. Results may vary.']));
assert(strcmp(local_legacy_config.presentation.description, ...
    ['Run the original v2 pipeline on this computer for comparison with ' ...
    'older studies.']));
assert(strcmp(mlsc_current_config.presentation.description, ...
    ['Run the pseudoCT pipeline on MLSC using a compiled MATLAB R2010b ' ...
    'backend.']));
assert(strcmp(mlsc_legacy_config.presentation.description, ...
    ['Run the original v2 pipeline on MLSC for comparison with older ' ...
    'studies.']));
assert(isempty(strfind(local_current_config.presentation.description, char(10))));
assert(isempty(strfind(mlsc_current_config.presentation.description, char(10))));
assert(isempty(strfind(local_legacy_config.presentation.description, char(10))));
assert(isempty(strfind(mlsc_legacy_config.presentation.description, char(10))));
assert(isempty(strfind(launchpad_legacy_config.presentation.description, char(10))));
assert(strcmp(local_mprage_config.presentation.display_name, ...
    'Local MPRAGE Only'));
assert(strcmp(local_mprage_config.presentation.description, ...
    ['Generate a NIfTI-only pseudoCT from MPRAGE alone on this computer. ' ...
    'No UMAP required.']));
assert(strcmp(mlsc_mprage_config.presentation.display_name, ...
    'MLSC MPRAGE Only'));
assert(strcmp(mlsc_mprage_config.presentation.description, ...
    ['Generate a NIfTI-only pseudoCT from MPRAGE alone on MLSC. ' ...
    'No UMAP required.']));
assert(strcmp(launchpad_legacy_config.presentation.display_name, ...
    'Launchpad - Legacy (Aether)'));
assert(strcmp(launchpad_legacy_config.presentation.description, ...
    ['Run the original v2 pipeline on Launchpad for comparison with older ' ...
    'studies.']));
assert(strcmp(launchpad_legacy_config.presentation.group, 'specialized'));
assert(~launchpad_legacy_config.presentation.recommended);
assert(strcmp(local_legacy_config.presentation.display_name, 'Aether - Local'));
assert(strcmp(mlsc_legacy_config.presentation.display_name, 'Aether - MLSC'));
assert(strcmp(mlsc_current_config.presentation.group, 'specialized'));
assert(mlsc_current_config.presentation.recommended);
assert(strcmp(devel_config.presentation.display_name, ...
    'Development Current MATLAB'));
dash = char(8212);
assert(strcmp(pseudo_CT_profile_selector_label('local-current'), ...
    ['PseudoCT v3 ' dash ' Local']));
assert(strcmp(pseudo_CT_profile_selector_label('mlsc-current'), ...
    ['PseudoCT v3 ' dash ' MLSC']));
assert(strcmp(pseudo_CT_profile_selector_label('local-mprage-only'), ...
    ['MPRAGE-only ' dash ' Local']));
assert(strcmp(pseudo_CT_profile_selector_label('mlsc-mprage-only'), ...
    ['MPRAGE-only ' dash ' MLSC']));
assert(strcmp(pseudo_CT_profile_selector_label('local-legacy'), ...
    ['PseudoCT v2 (Aether) ' dash ' Local']));
assert(strcmp(pseudo_CT_profile_selector_label('mlsc-legacy'), ...
    ['PseudoCT v2 (Aether) ' dash ' MLSC']));
assert(strcmp(pseudo_CT_profile_selector_label('launchpad-legacy'), ...
    ['PseudoCT v2 (Aether) ' dash ' Launchpad']));
assert(strcmp(pseudo_CT_profile_selector_label('devel', 'Developer'), ...
    'Developer'));
assert(isempty(strfind(local_mprage_config.presentation.display_name, ...
    '[CUSTOM]')));
assert(isempty(strfind(mlsc_mprage_config.presentation.display_name, ...
    '[CUSTOM]')));
assert(isempty(strfind(devel_config.presentation.display_name, ...
    '[DEVELOPMENT]')));
assert(all(double(local_current_config.presentation.description) < 128));
assert(all(double(mlsc_current_config.presentation.description) < 128));
assert(all(double(local_legacy_config.presentation.description) < 128));
assert(all(double(mlsc_legacy_config.presentation.description) < 128));
assert(all(double(local_mprage_config.presentation.display_name) < 128));
assert(all(double(mlsc_mprage_config.presentation.display_name) < 128));
assert(all(double(launchpad_legacy_config.presentation.display_name) < 128));
assert(all(double(launchpad_legacy_config.presentation.description) < 128));
assert(all(double(devel_config.presentation.display_name) < 128));
assert(~ismember('mlsc', {ordered.name}));
assert(~ismember('launchpad', {ordered.name}));
assert(ismember('launchpad-legacy', {ordered.name}));
assert(~ismember('launchpad-mprage-only', {ordered.name}));
assert(~ismember('local-near-parity-r2010b', {ordered.name}));

selector_source = local_read(fullfile(root_dir, 'src', 'ui', ...
    'pseudo_CT_profile_selector.m'));
assert(~isempty(strfind(selector_source, ...
    'Choose a workflow below, then select Run Selected.')));
assert(~isempty(strfind(selector_source, 'char(8212)')));
assert(isempty(strfind(selector_source, 'T001 is blocked')));
assert(isempty(strfind(selector_source, 'artifact contract exists')));
assert(~isempty(strfind(selector_source, 'Standard Processing')));
assert(~isempty(strfind(selector_source, 'MPRAGE-only Processing')));
assert(~isempty(strfind(selector_source, 'Legacy Processing')));
assert(~isempty(strfind(selector_source, 'MPRAGE + UMAP required')));
assert(~isempty(strfind(selector_source, 'NIfTI and DICOM output')));
assert(~isempty(strfind(selector_source, 'No UMAP required')));
assert(~isempty(strfind(selector_source, 'NIfTI output only')));
assert(~isempty(strfind(selector_source, 'Previous software version')));
assert(~isempty(strfind(selector_source, 'MATLAB R2010b host required')));
assert(~isempty(strfind(selector_source, 'Historical compatibility')));
assert(~isempty(strfind(selector_source, 'standard_processing_subtitle')));
assert(~isempty(strfind(selector_source, ...
    'standard_subtitle = uicontrol(''Parent'', standard_panel')));
assert(~isempty(strfind(selector_source, ...
    'custom_subtitle = uicontrol(''Parent'', content_panel')));
assert(~isempty(strfind(selector_source, ...
    'historical_subtitle = uicontrol(''Parent'', content_panel')));
assert(length(strfind(selector_source, 'char(183)')) == 4);
assert(isempty(strfind(selector_source, ...
    'set(standard_subtitle, ''Visible'', ''off''')));
assert(isempty(strfind(selector_source, ...
    'set(custom_subtitle, ''Visible'', ''off''')));
assert(isempty(strfind(selector_source, ...
    'set(historical_subtitle, ''Visible'', ''off''')));
assert(isempty(strfind(selector_source, 'Development')));
assert(~isempty(strfind(selector_source, 'custom_expanded = false')));
assert(~isempty(strfind(selector_source, 'historical_expanded = false')));
assert(~isempty(strfind(selector_source, 'profiles(selected_index).name')));
layout_source = local_read(fullfile(root_dir, 'src', 'ui', ...
    'pseudo_CT_profile_selector_layout.m'));
prepare_source = local_read(fullfile(root_dir, 'src', 'ui', ...
    'pseudo_CT_prepare_profile_choices.m'));
routine_choices_source = local_read(fullfile(root_dir, 'src', 'ui', ...
    'pseudo_CT_prepare_routine_profile_choices.m'));
label_source = local_read(fullfile(root_dir, 'src', 'ui', ...
    'pseudo_CT_profile_selector_label.m'));
assert(isempty(strfind(layout_source, 'strjoin(')));
assert(isempty(strfind(layout_source, 'addParameter')));
assert(isempty(strfind(layout_source, 'string(')));
assert(isempty(strfind(prepare_source, 'strjoin(')));
assert(isempty(strfind(prepare_source, 'addParameter')));
assert(isempty(strfind(prepare_source, 'string(')));
assert(isempty(strfind(selector_source, 'addParameter')));
assert(isempty(strfind(selector_source, 'string(')));
assert(isempty(strfind(label_source, 'strjoin(')));
assert(isempty(strfind(label_source, 'addParameter')));
assert(isempty(strfind(label_source, 'string(')));
assert(all(double(label_source) < 128));
assert(~isempty(strfind(selector_source, '[+]')));
assert(~isempty(strfind(selector_source, '[-]')));
assert(~isempty(strfind(selector_source, '''Cancel''')));
assert(~isempty(strfind(selector_source, 'Run Selected')));
assert(~isempty(strfind(selector_source, 'Selected:')));
assert(~isempty(strfind(selector_source, '''Visible'', ''off''')));
assert(~isempty(strfind(selector_source, '''Visible'', ''on''')));
assert(~isempty(strfind(selector_source, 'custom_expanded = ~custom_expanded')));
assert(~isempty(strfind(selector_source, ...
    'historical_expanded = ~historical_expanded')));
assert(~isempty(strfind(selector_source, ...
    'pseudo_CT_profile_selector_layout(standard_count,')));
assert(~isempty(strfind(selector_source, '''Style'', ''radiobutton''')));
assert(~isempty(strfind(selector_source, '''FontSize'', 8')));
assert(~isempty(strfind(selector_source, ...
    '[42 row_bottom + 6 row_layout.content_width - 54 20]')));
assert(~isempty(strfind(selector_source, ...
    'current_layout.content_width - 54 20')));
assert(collapsed.row_height >= 30 + 20);
assert(30 >= 6 + 20);
assert(~isempty(strfind(selector_source, 'pseudo_CT_profile_selector_layout')));
assert(~isempty(strfind(selector_source, 'previous_scroll = get(slider_handle')));
assert(~isempty(strfind(selector_source, '''Value'', layout.scroll_value')));
assert(~isempty(strfind(selector_source, '''Style'', ''slider''')));
assert(~isempty(strfind(prepare_source, ...
    'strcmp({profiles.name}, ''mlsc-current'')')));
assert(~isempty(strfind(routine_choices_source, ...
    'strcmp({profiles.name}, ''devel'')')));
assert(~isempty(strfind(selector_source, 'Recommended')));
assert(~isempty(strfind(selector_source, 'profiles(selected_index).name')));
assert(isempty(strfind(selector_source, 'listdlg')));
assert(isempty(strfind(selector_source, 'strjoin')));
assert(isempty(strfind(selector_source, '''Style'', ''listbox''')));
assert(isempty(strfind(selector_source, '''Style'', ''checkbox''')));
assert(isempty(strfind(selector_source, '''Style'', ''togglebutton''')));
assert(isempty(strfind(selector_source, '''Style'', ''popupmenu''')));
assert(all(double(selector_source) < 128));

fprintf('Profile selector layout tests passed: readable rows, screen cap, and scrolling fallback.\n');
fprintf('Selector disclosure tests passed: standard default, independent collapsed sections, hidden-selection retention, and scrolling.\n');
end

function text = local_read(file_path)
fid = fopen(file_path, 'r');
assert(fid ~= -1);
text = fread(fid, inf, '*char')';
fclose(fid);
end
