function varargout = pseudo_CT_input_window(gui_mode, config, launch)
%PSEUDO_CT_INPUT_WINDOW pseudoCT input window (MATLAB frontend, programmatic layout).
%   PSEUDO_CT_INPUT_WINDOW(MODE, CONFIG, CONTEXT) opens the window for one profile.
%   MODE is 'mMR' or 'mprage-only' and must equal CONFIG.io_policy.gui. CONFIG is one
%   entry of pseudo_CT_profile_choices (its config). CONTEXT holds launcher, runtime,
%   mcr_root and root_dir (see run_pseudo_CT). FIG = PSEUDO_CT_INPUT_WINDOW(...) also
%   returns the figure. Each call opens a new window.
%
%   Subjects come from one of two sources, chosen with the radio buttons; only the
%   selected source is used by Run and the two are never merged:
%     - Manual: a list of subjects (identifier, MPRAGE and, for the standard profiles,
%       UMAP) with Add/Remove, File... and Folder... browsing, typed or pasted paths,
%       and Export to a subjects file. Setting an MPRAGE suggests the UMAP found beside
%       it (pseudo_CT_discover_umap) only while the UMAP is empty or still holds an
%       earlier suggestion; a UMAP chosen or typed by the user is never replaced.
%     - Subjects file: an existing subjects file, checked by the launcher's parser
%       (bin/pseudoct check-subjects --format tsv) and previewed read-only: the paths as
%       written in the file, with the resolved input and DICOM series detail below.
%   One subject or many use the same representation: Run always passes one subjects file
%   to the launcher ('Subject', FILE). For manual entry it is a temporary file written by
%   pseudo_CT_subjects_file and removed after the run.
%
%   Run checks the whole subject list with the launcher (check-subjects) and stops with
%   every error when it is invalid. A local profile then makes one launcher call (run
%   validates first and submits only when validation passes). An MLSC profile asks for
%   credentials, authenticates them through the launcher (retried on a rejected password
%   or account, no submission), then submits once. Subjects run one after another. The
%   launcher call is synchronous: MATLAB is busy until Run returns, and the window's
%   controls and its close button are disabled meanwhile.
%   Minimum supported MATLAB: R2010b (classic figure, uicontrol, uipanel and uitable only).

if nargin ~= 3 || ~ischar(gui_mode) || ~any(strcmp(gui_mode, {'mMR'; 'mprage-only'})) || ...
        ~isstruct(config) || numel(config) ~= 1 || ...
        ~isfield(config, 'profile_key') || ~isstruct(launch)
    error('pseudo_CT:GuiLaunch', ...
        'The window needs a mode, one profile configuration and a launch context.');
end
if ~isfield(launch, 'launcher') || ~isfield(launch, 'runtime') || ...
        ~isfield(launch, 'mcr_root') || ~isfield(launch, 'root_dir')
    error('pseudo_CT:GuiLaunch', 'The launch context is incomplete.');
end
if ~isfield(config, 'io_policy') || ~strcmp(gui_mode, config.io_policy.gui)
    error('pseudo_CT:InvalidProfile', ...
        'The window mode does not match the selected profile.');
end

% ---- State -------------------------------------------------------------------------
needs_umap = strcmp(gui_mode, 'mMR');
needs_credentials = isfield(config, 'mode') && ischar(config.mode) && ...
    strcmp(config.mode, 'mlsc');
source = 'manual';
manual = struct('ids', {{}}, 'mprage', {{}}, 'umap', {{}}, 'suggested', false(0, 1));
selected = 0;
last_dir = pwd;
loaded = struct('file', '', 'stamp', '', 'check', [], 'detail_first', []);
run_in_progress = false;
note = '';
enforcing_size = false;

% ---- Window and controls -----------------------------------------------------------
fig = figure('Name', 'Pseudo-CT Input', 'NumberTitle', 'off', 'MenuBar', 'none', ...
    'ToolBar', 'none', 'Units', 'pixels', 'Visible', 'off', 'Resize', 'on', ...
    'HandleVisibility', 'callback', 'IntegerHandle', 'off', ...
    'Tag', 'pseudo_CT_input_window', 'CloseRequestFcn', @on_close_request);
try
    metrics = measure_metrics();
    h = struct();
    h.header = uicontrol(fig, 'Style', 'text', 'HorizontalAlignment', 'left', ...
        'FontWeight', 'bold', 'String', header_text(), 'Tag', 'profile_header');

    h.subjects_panel = uipanel('Parent', fig, 'Title', 'Subjects', ...
        'FontWeight', 'bold', 'Units', 'pixels', 'Tag', 'subjects_panel');
    h.manual_radio = uicontrol(h.subjects_panel, 'Style', 'radiobutton', ...
        'String', 'Enter subjects manually', 'Value', 1, ...
        'Tag', 'source_manual', 'Callback', @(s, e) set_source('manual'));
    h.file_radio = uicontrol(h.subjects_panel, 'Style', 'radiobutton', ...
        'String', 'Load a subjects file', 'Value', 0, ...
        'Tag', 'source_file', 'Callback', @(s, e) set_source('file'));

    % Manual entry.
    h.manual_group = uipanel('Parent', h.subjects_panel, 'BorderType', 'none', ...
        'Units', 'pixels', 'Tag', 'manual_group');
    h.manual_table = uitable('Parent', h.manual_group, 'Data', cell(0, table_columns()), ...
        'ColumnName', table_names(), 'ColumnEditable', false(1, table_columns()), ...
        'RowName', 'numbered', 'Tag', 'manual_table', ...
        'CellSelectionCallback', @on_manual_table_select);
    h.add_button = uicontrol(h.manual_group, 'Style', 'pushbutton', ...
        'String', 'Add subject', 'Tag', 'add_subject', 'Callback', @on_add);
    h.remove_button = uicontrol(h.manual_group, 'Style', 'pushbutton', ...
        'String', 'Remove subject', 'Tag', 'remove_subject', 'Callback', @on_remove);
    h.export_button = uicontrol(h.manual_group, 'Style', 'pushbutton', ...
        'String', 'Export subjects file...', 'Tag', 'export_subjects', ...
        'Callback', @on_export);
    h.row_label = uicontrol(h.manual_group, 'Style', 'text', ...
        'HorizontalAlignment', 'left', 'FontWeight', 'bold', 'String', '', ...
        'Tag', 'selected_subject_label');
    h.id_label = uicontrol(h.manual_group, 'Style', 'text', ...
        'HorizontalAlignment', 'left', 'String', 'Subject ID');
    h.id_edit = uicontrol(h.manual_group, 'Style', 'edit', ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'white', ...
        'Tag', 'subject_id_edit', 'Callback', @on_id_edit);
    h.mprage_label = uicontrol(h.manual_group, 'Style', 'text', ...
        'HorizontalAlignment', 'left', 'String', 'MPRAGE');
    h.mprage_edit = uicontrol(h.manual_group, 'Style', 'edit', ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'white', ...
        'Tag', 'mprage_edit', 'Callback', @(s, e) on_path_edit('mprage'));
    h.mprage_file = uicontrol(h.manual_group, 'Style', 'pushbutton', ...
        'String', 'File...', 'Tag', 'mprage_file', ...
        'TooltipString', 'Select a NIfTI file or one DICOM file of the MPRAGE series', ...
        'Callback', @(s, e) on_browse('mprage', 'file'));
    h.mprage_dir = uicontrol(h.manual_group, 'Style', 'pushbutton', ...
        'String', 'Folder...', 'Tag', 'mprage_folder', ...
        'TooltipString', 'Select the folder that holds the MPRAGE DICOM series', ...
        'Callback', @(s, e) on_browse('mprage', 'dir'));
    h.umap_label = uicontrol(h.manual_group, 'Style', 'text', ...
        'HorizontalAlignment', 'left', 'String', 'UMAP');
    h.umap_edit = uicontrol(h.manual_group, 'Style', 'edit', ...
        'HorizontalAlignment', 'left', 'BackgroundColor', 'white', ...
        'Tag', 'umap_edit', 'Callback', @(s, e) on_path_edit('umap'));
    h.umap_file = uicontrol(h.manual_group, 'Style', 'pushbutton', ...
        'String', 'File...', 'Tag', 'umap_file', ...
        'TooltipString', 'Select one DICOM file of the UMAP series', ...
        'Callback', @(s, e) on_browse('umap', 'file'));
    h.umap_dir = uicontrol(h.manual_group, 'Style', 'pushbutton', ...
        'String', 'Folder...', 'Tag', 'umap_folder', ...
        'TooltipString', 'Select the folder that holds the UMAP DICOM series', ...
        'Callback', @(s, e) on_browse('umap', 'dir'));
    if ~needs_umap
        set([h.umap_label h.umap_edit h.umap_file h.umap_dir], 'Visible', 'off');
    end

    % Subjects file.
    h.file_group = uipanel('Parent', h.subjects_panel, 'BorderType', 'none', ...
        'Units', 'pixels', 'Visible', 'off', 'Tag', 'file_group');
    h.file_label = uicontrol(h.file_group, 'Style', 'text', ...
        'HorizontalAlignment', 'left', 'String', 'Subjects file');
    h.file_edit = uicontrol(h.file_group, 'Style', 'edit', 'Enable', 'inactive', ...
        'HorizontalAlignment', 'left', 'String', '', 'Tag', 'subjects_file_path');
    h.file_browse = uicontrol(h.file_group, 'Style', 'pushbutton', ...
        'String', 'Browse...', 'Tag', 'subjects_file_browse', 'Callback', @on_file_browse);
    h.file_recheck = uicontrol(h.file_group, 'Style', 'pushbutton', ...
        'String', 'Check again', 'Tag', 'subjects_file_recheck', ...
        'Callback', @(s, e) check_loaded_file(true));
    h.file_table = uitable('Parent', h.file_group, 'Data', cell(0, table_columns()), ...
        'ColumnName', table_names(), 'ColumnEditable', false(1, table_columns()), ...
        'RowName', 'numbered', 'Tag', 'subjects_file_table', ...
        'CellSelectionCallback', @on_file_table_select);
    h.file_details = uicontrol(h.file_group, 'Style', 'listbox', 'Min', 0, 'Max', 2, ...
        'Value', [], 'String', {'Select a subjects file.'}, ...
        'BackgroundColor', 'white', 'Tag', 'subjects_file_details');

    % Processing options: the three profile-defaulted options of the launcher. A later
    % execution group (for example the maximum number of concurrent subjects) has its
    % place to the right of these options in the same band (see layout_window).
    h.options_panel = uipanel('Parent', fig, 'Title', 'Processing options', ...
        'FontWeight', 'bold', 'Units', 'pixels', 'Tag', 'processing_options');
    h.aliasing = uicontrol(h.options_panel, 'Style', 'checkbox', ...
        'String', 'Auto-correct Nose-Neck aliasing (if required)', ...
        'Value', normalize_gui_flag(config.aliasing_default, true), ...
        'Tag', 'aliasing_button', 'Callback', @(s, e) refresh());
    h.recenter = uicontrol(h.options_panel, 'Style', 'checkbox', ...
        'String', 'Recenter MPRAGE before normalization', ...
        'Value', normalize_gui_flag(config.recenter_before_normalization, false), ...
        'Tag', 'recentering_button', 'Callback', @(s, e) refresh());
    h.cleanup = uicontrol(h.options_panel, 'Style', 'checkbox', ...
        'String', 'Remove temporary files after successful processing', ...
        'Value', normalize_gui_flag(config.cleanup_on_success, true), ...
        'Tag', 'cleanup_on_success_checkbox', 'Callback', @(s, e) refresh());

    % Bottom bar.
    h.status = uicontrol(fig, 'Style', 'text', 'HorizontalAlignment', 'left', ...
        'String', '', 'Tag', 'pseudo_CT_status');
    h.check_button = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Check subjects', ...
        'Tag', 'check_subjects', 'Callback', @on_check);
    h.close_button = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Close', ...
        'Tag', 'cancel_button', 'Callback', @on_close);
    h.run_button = uicontrol(fig, 'Style', 'pushbutton', 'String', 'Run', ...
        'FontWeight', 'bold', 'Tag', 'ok_button', 'Callback', @on_run);

    set(fig, 'Position', initial_position());
    if isprop(fig, 'SizeChangedFcn')
        set(fig, 'SizeChangedFcn', @(s, e) layout_window());
    else
        set(fig, 'ResizeFcn', @(s, e) layout_window());
    end
    layout_window();
    show_selected();
    refresh();
    set(fig, 'Visible', 'on');
catch ME
    if ishghandle(fig)
        delete(fig);
    end
    rethrow(ME);
end
if nargout
    varargout{1} = fig;
end

% =====================================================================================
% Layout
% =====================================================================================
    function metrics = measure_metrics()
        % Text height and average character width of the default uicontrol font, so the
        % layout follows the font size and display scaling of the running MATLAB.
        probe = uicontrol(fig, 'Style', 'text', 'Units', 'pixels', 'Visible', 'off', ...
            'String', 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789/_');
        extent = get(probe, 'Extent');
        delete(probe);
        metrics.char_w = max(5, extent(3) / 64);
        metrics.text_h = max(14, ceil(extent(4)));
        metrics.row_h = max(24, ceil(metrics.text_h * 1.6));
        metrics.gap = max(6, round(metrics.text_h / 2));
        metrics.margin = max(10, round(metrics.text_h * 0.8));
        metrics.title_h = metrics.text_h + metrics.gap;
    end

    function width = button_width(labels)
        width = 0;
        for kk = 1:numel(labels)
            width = max(width, ceil(length(labels{kk}) * metrics.char_w) + 3 * metrics.gap);
        end
        width = max(width, 80);
    end

    function position = initial_position()
        screen = get(0, 'ScreenSize');
        [min_w, min_h] = minimum_size();
        width = min(max([940, round(130 * metrics.char_w), min_w]), screen(3) - 60);
        rows_needed = 22 + needs_umap;
        height = min(max([600, rows_needed * (metrics.row_h + metrics.gap), min_h]), ...
            screen(4) - 100);
        position = [max(1, floor((screen(3) - width) / 2)), ...
            max(1, floor((screen(4) - height) / 2)), width, height];
    end

    function [min_w, min_h] = minimum_size()
        % Smallest window in which no control overlaps another: the bottom bar, the
        % three options, the header and a subjects area with a few table rows and the
        % subject editor (manual) or the file row and error list (file).
        m = metrics.margin;
        g = metrics.gap;
        r = metrics.row_h;
        th = metrics.text_h;
        bw = button_width({'Check subjects', 'Close', 'Run'});
        min_w = max(760, 2 * m + 3 * bw + 3 * g + round(50 * metrics.char_w));
        table_min = 4 * r;
        manual_min = g + (2 + needs_umap) * (r + g) + (th + 2 + g) + (r + g) + ...
            table_min + g;
        file_min = (r + g) + table_min + 3 * th + 3 * g;
        panel_min = metrics.title_h + th + g + g + max(manual_min, file_min);
        option_h = metrics.title_h + 3 * (th + g) + g;
        min_h = m + max(r, 2 * th + 2) + g + option_h + g + panel_min + g + th + 2 + m;
    end

    function layout_window()
        if ~ishghandle(fig)
            return;
        end
        m = metrics.margin;
        g = metrics.gap;
        r = metrics.row_h;
        fig_pos = get(fig, 'Position');
        [min_w, min_h] = minimum_size();
        if (fig_pos(3) < min_w || fig_pos(4) < min_h) && ~enforcing_size
            % Grow back to the minimum, keeping the top edge where it is unless that
            % would move the bottom bar (Run, Close) below the screen. If the window
            % manager refuses, the layout below still uses the minimum (no overlap).
            enforcing_size = true;
            new_h = max(fig_pos(4), min_h);
            new_y = max(1, fig_pos(2) + fig_pos(4) - new_h);
            set(fig, 'Position', [fig_pos(1), new_y, max(fig_pos(3), min_w), new_h]);
            enforcing_size = false;
            fig_pos = get(fig, 'Position');
        end
        W = max(fig_pos(3), min_w);
        H = max(fig_pos(4), min_h);
        inner_w = W - 2 * m;

        % Bottom bar: status on the left, Check subjects / Close / Run on the right.
        bw = button_width({'Check subjects', 'Close', 'Run'});
        set(h.run_button, 'Position', [W - m - bw, m, bw, r]);
        set(h.close_button, 'Position', [W - m - 2 * bw - g, m, bw, r]);
        set(h.check_button, 'Position', [W - m - 3 * bw - 2 * g, m, bw, r]);
        set(h.status, 'Position', [m, m, max(50, W - 2 * m - 3 * bw - 3 * g), ...
            2 * metrics.text_h + 2]);
        y = m + max(r, 2 * metrics.text_h + 2) + g;

        % Processing options band. Its full width is used by the three options today; a
        % later execution group would take the right part of this band.
        option_h = metrics.title_h + 3 * (metrics.text_h + g) + g;
        set(h.options_panel, 'Position', [m, y, inner_w, option_h]);
        names = {'aliasing', 'recenter', 'cleanup'};
        for kk = 1:3
            set(h.(names{kk}), 'Position', [m, option_h - metrics.title_h - ...
                kk * (metrics.text_h + g), inner_w - 3 * m, metrics.text_h + 4]);
        end
        y = y + option_h + g;

        % Header.
        set(h.header, 'Position', [m, H - m - metrics.text_h - 2, inner_w, ...
            metrics.text_h + 2]);

        % Subjects panel fills the rest.
        panel_h = max(200, H - m - metrics.text_h - 2 - g - y);
        set(h.subjects_panel, 'Position', [m, y, inner_w, panel_h]);
        pw = inner_w - 4;
        ph = panel_h - metrics.title_h;
        radio_y = ph - metrics.text_h - g;
        radio_w = round(36 * metrics.char_w);
        set(h.manual_radio, 'Position', [m, radio_y, radio_w, metrics.text_h + 4]);
        set(h.file_radio, 'Position', [m + radio_w + 2 * g, radio_y, radio_w, ...
            metrics.text_h + 4]);
        group_h = max(120, radio_y - g);
        set(h.manual_group, 'Position', [1, 1, pw, group_h]);
        set(h.file_group, 'Position', [1, 1, pw, group_h]);
        layout_manual(pw, group_h);
        layout_file(pw, group_h);
        update_tables();
    end

    function layout_manual(pw, gh)
        m = metrics.margin;
        g = metrics.gap;
        r = metrics.row_h;
        label_w = round(12 * metrics.char_w);
        bw = button_width({'File...', 'Folder...'});
        edit_x = m + label_w + g;
        edit_w = max(80, pw - edit_x - 2 * bw - 2 * g - m);
        y = g;
        if needs_umap
            set(h.umap_label, 'Position', [m, y + 3, label_w, metrics.text_h + 2]);
            set(h.umap_edit, 'Position', [edit_x, y, edit_w, r]);
            set(h.umap_file, 'Position', [edit_x + edit_w + g, y, bw, r]);
            set(h.umap_dir, 'Position', [edit_x + edit_w + bw + 2 * g, y, bw, r]);
            y = y + r + g;
        end
        set(h.mprage_label, 'Position', [m, y + 3, label_w, metrics.text_h + 2]);
        set(h.mprage_edit, 'Position', [edit_x, y, edit_w, r]);
        set(h.mprage_file, 'Position', [edit_x + edit_w + g, y, bw, r]);
        set(h.mprage_dir, 'Position', [edit_x + edit_w + bw + 2 * g, y, bw, r]);
        y = y + r + g;
        set(h.id_label, 'Position', [m, y + 3, label_w, metrics.text_h + 2]);
        set(h.id_edit, 'Position', [edit_x, y, min(edit_w, round(40 * metrics.char_w)), r]);
        y = y + r + g;
        set(h.row_label, 'Position', [m, y, pw - 2 * m, metrics.text_h + 2]);
        y = y + metrics.text_h + 2 + g;
        abw = button_width({'Add subject', 'Remove subject'});
        ebw = button_width({'Export subjects file...'});
        set(h.add_button, 'Position', [m, y, abw, r]);
        set(h.remove_button, 'Position', [m + abw + g, y, abw, r]);
        set(h.export_button, 'Position', [pw - m - ebw, y, ebw, r]);
        y = y + r + g;
        set(h.manual_table, 'Position', [m, y, pw - 2 * m, max(60, gh - y - g)]);
    end

    function layout_file(pw, gh)
        m = metrics.margin;
        g = metrics.gap;
        r = metrics.row_h;
        label_w = round(14 * metrics.char_w);
        bw = button_width({'Browse...', 'Check again'});
        top = gh - r - g;
        edit_w = max(80, pw - 2 * m - label_w - 2 * bw - 3 * g);
        set(h.file_label, 'Position', [m, top + 3, label_w, metrics.text_h + 2]);
        set(h.file_edit, 'Position', [m + label_w + g, top, edit_w, r]);
        set(h.file_browse, 'Position', [m + label_w + edit_w + 2 * g, top, bw, r]);
        set(h.file_recheck, 'Position', [m + label_w + edit_w + bw + 3 * g, top, bw, r]);
        details_h = max(3 * metrics.text_h, round((top - 2 * g) * 0.4));
        set(h.file_details, 'Position', [m, g, pw - 2 * m, details_h]);
        set(h.file_table, 'Position', [m, 2 * g + details_h, pw - 2 * m, ...
            max(60, top - 3 * g - details_h)]);
    end

    function n = table_columns()
        n = 2 + needs_umap;
    end

    function names = table_names()
        names = {'Subject ID', 'MPRAGE'};
        if needs_umap
            names{end + 1} = 'UMAP';
        end
    end

    function widths = column_widths(table_handle)
        % Column widths (pixels) shared by the manual and file tables: the table width
        % less the row-number gutter, a vertical scrollbar and the borders, split about
        % 18/41/41 (ID/MPRAGE/UMAP), or 20/80 without UMAP. The last column takes the
        % rounding remainder so the columns fill the table exactly.
        position = get(table_handle, 'Position');
        gutter = max(32, round(4 * metrics.char_w) + 12);
        scrollbar = 20;
        usable = max(200, floor(position(3) - gutter - scrollbar - 4));
        if needs_umap
            fractions = [0.18 0.41 0.41];
        else
            fractions = [0.20 0.80];
        end
        pixels = floor(usable * fractions);
        pixels(1) = max(pixels(1), round(8 * metrics.char_w));
        pixels(end) = usable - sum(pixels(1:end - 1));
        widths = num2cell(pixels);
    end

    function text = fit_path(path_text, width)
        % Shows the end of a long path (the file and series names) in a table cell.
        chars = max(8, floor(width / metrics.char_w) - 2);
        text = path_text;
        if length(text) > chars
            text = ['...' text(end - chars + 4:end)];
        end
    end

% =====================================================================================
% Table contents and the selected subject
% =====================================================================================
    function update_tables()
        widths = column_widths(h.manual_table);
        n = numel(manual.ids);
        data = cell(n, table_columns());
        for kk = 1:n
            data{kk, 1} = manual.ids{kk};
            data{kk, 2} = fit_path(manual.mprage{kk}, widths{2});
            if needs_umap
                if manual.suggested(kk) && ~isempty(manual.umap{kk})
                    marker = '(suggested) ';
                    data{kk, 3} = [marker fit_path(manual.umap{kk}, ...
                        widths{3} - length(marker) * metrics.char_w)];
                else
                    data{kk, 3} = fit_path(manual.umap{kk}, widths{3});
                end
            end
        end
        set(h.manual_table, 'Data', data, 'ColumnWidth', widths);

        widths = column_widths(h.file_table);
        data = cell(0, table_columns());
        if isstruct(loaded.check) && ~isempty(loaded.check.subjects)
            subjects = loaded.check.subjects;
            data = cell(numel(subjects), table_columns());
            for kk = 1:numel(subjects)
                data{kk, 1} = subjects(kk).id;
                data{kk, 2} = fit_path(subjects(kk).mprage, widths{2});
                if needs_umap
                    data{kk, 3} = fit_path(subjects(kk).umap, widths{3});
                end
            end
        end
        set(h.file_table, 'Data', data, 'ColumnWidth', widths);
    end

    function show_selected()
        n = numel(manual.ids);
        editors = [h.id_edit h.mprage_edit h.mprage_file h.mprage_dir ...
            h.umap_edit h.umap_file h.umap_dir];
        if selected < 1 || selected > n
            selected = 0;
            set(h.row_label, 'String', ...
                'No subject selected. Add a subject, or select one in the list.');
            set([h.id_edit h.mprage_edit h.umap_edit], 'String', '');
            set(editors, 'Enable', 'off');
            return;
        end
        set(h.row_label, 'String', sprintf('Subject %d of %d', selected, n));
        set(h.id_edit, 'String', manual.ids{selected});
        set(h.mprage_edit, 'String', manual.mprage{selected}, ...
            'TooltipString', manual.mprage{selected});
        set(h.umap_edit, 'String', manual.umap{selected}, ...
            'TooltipString', manual.umap{selected});
        if ~run_in_progress
            set(editors, 'Enable', 'on');
        end
    end

    function on_manual_table_select(~, event)
        if run_in_progress || ~isstruct(event) && ~isobject(event)
            return;
        end
        indices = event.Indices;
        if isempty(indices)
            return;
        end
        selected = indices(1, 1);
        show_selected();
        refresh();
    end

    function on_add(~, ~)
        n = numel(manual.ids);
        number = n + 1;
        id = sprintf('Subject_%03d', number);
        while any(strcmpi(manual.ids, id))
            number = number + 1;
            id = sprintf('Subject_%03d', number);
        end
        manual.ids{n + 1} = id;
        manual.mprage{n + 1} = '';
        manual.umap{n + 1} = '';
        manual.suggested(n + 1, 1) = false;
        selected = n + 1;
        note = '';
        update_tables();
        show_selected();
        refresh();
    end

    function on_remove(~, ~)
        n = numel(manual.ids);
        if selected < 1 || selected > n
            note = 'Select the subject to remove in the list.';
            refresh();
            return;
        end
        keep = true(1, n);
        keep(selected) = false;
        manual.ids = manual.ids(keep);
        manual.mprage = manual.mprage(keep);
        manual.umap = manual.umap(keep);
        manual.suggested = manual.suggested(keep');
        selected = min(selected, n - 1);
        note = '';
        update_tables();
        show_selected();
        refresh();
    end

    function on_id_edit(source, ~)
        if selected < 1
            return;
        end
        manual.ids{selected} = strtrim(get(source, 'String'));
        set(source, 'String', manual.ids{selected});
        note = '';
        update_tables();
        refresh();
    end

    function on_path_edit(field)
        if selected < 1
            return;
        end
        text = strtrim(get(h.([field '_edit']), 'String'));
        set_path(field, absolute_path(text));
    end

    function on_browse(field, kind)
        if selected < 1
            return;
        end
        if strcmp(field, 'mprage')
            prompt = 'Select the MPRAGE input (NIfTI file, DICOM file or DICOM series folder)';
        else
            prompt = 'Select the UMAP input (DICOM file or DICOM series folder)';
        end
        if strcmp(kind, 'dir')
            prompt = strrep(prompt, 'input (', 'series folder (');
        end
        % Start beside the current input (the parent of a file or of a series folder),
        % else in the last folder used.
        start = last_dir;
        current = manual.(field){selected};
        if ~isempty(current) && exist(fileparts(current), 'dir') == 7
            start = fileparts(current);
        end
        chosen = pseudo_CT_select_file(prompt, kind, start);
        if ~ishghandle(fig) || isempty(chosen)
            return;
        end
        last_dir = fileparts(chosen);
        set_path(field, chosen);
    end

    function set_path(field, path_text)
        if strcmp(field, 'umap')
            manual.umap{selected} = path_text;
            manual.suggested(selected) = false;
            note = '';
        else
            manual.mprage{selected} = path_text;
            note = '';
            % Suggest the UMAP found beside the MPRAGE only when the UMAP is empty or still
            % holds an earlier suggestion; a UMAP the user set is never replaced.
            if needs_umap && (isempty(manual.umap{selected}) || manual.suggested(selected))
                manual.umap{selected} = '';
                manual.suggested(selected) = false;
                if ~isempty(path_text)
                    probe = path_text;
                    if exist(probe, 'dir') == 7 && probe(end) ~= filesep
                        % A series folder: look beside the folder itself, as for a file
                        % inside it.
                        probe = [probe filesep];
                    end
                    found = pseudo_CT_discover_umap(probe);
                    if ischar(found) && ~isempty(found)
                        manual.umap{selected} = found;
                        manual.suggested(selected) = true;
                        note = 'UMAP suggested from the MPRAGE location; check it.';
                    else
                        note = 'No UMAP found beside the MPRAGE: select the UMAP.';
                    end
                end
            end
        end
        update_tables();
        show_selected();
        refresh();
    end

% =====================================================================================
% Subjects file
% =====================================================================================
    function on_file_browse(~, ~)
        start = last_dir;
        if ~isempty(loaded.file)
            start = fileparts(loaded.file);
        end
        if exist(start, 'dir') ~= 7
            start = pwd;
        end
        [name, folder] = uigetfile({'*.txt', 'Subjects files (*.txt)'; '*', 'All files'}, ...
            'Select a subjects file', [start filesep]);
        if ~ishghandle(fig) || isequal(name, 0) || isequal(folder, 0)
            return;
        end
        loaded.file = fullfile(folder, name);
        last_dir = folder;
        set(h.file_edit, 'String', loaded.file, 'TooltipString', loaded.file);
        check_loaded_file(true);
    end

    function check_loaded_file(show_busy)
        loaded.check = [];
        loaded.stamp = '';
        loaded.detail_first = [];
        if isempty(loaded.file)
            set(h.file_details, 'String', {'Select a subjects file.'}, 'Value', []);
            update_tables();
            refresh();
            return;
        end
        if show_busy
            set_status('Checking the subjects file...');
        end
        try
            loaded.stamp = file_stamp(loaded.file);
            loaded.check = pseudo_CT_launch_request('check-subjects', launch.launcher, ...
                config.profile_key, loaded.file);
        catch ME
            loaded.check = struct('ok', false, 'exit_code', -1, 'subjects', [], ...
                'errors', [], 'message', ME.message);
        end
        if ~ishghandle(fig)
            return;
        end
        [lines, first] = check_lines(loaded.check, loaded.file, true);
        loaded.detail_first = first;
        set(h.file_details, 'String', lines, 'Value', [], 'ListboxTop', 1);
        update_tables();
        refresh();
    end

    function on_file_table_select(~, event)
        if run_in_progress || ~isstruct(event) && ~isobject(event)
            return;
        end
        indices = event.Indices;
        if isempty(indices) || isempty(loaded.detail_first) || ...
                indices(1, 1) > numel(loaded.detail_first)
            return;
        end
        line = loaded.detail_first(indices(1, 1));
        set(h.file_details, 'Value', line, 'ListboxTop', line);
    end

    function [lines, first] = check_lines(check, display, with_details)
        % Readable lines for a check result: every error, or every subject with its
        % paths and the resolved DICOM detail. FIRST(k) is the line of subject k.
        first = [];
        if ~isempty(check.message)
            lines = [{'The subjects could not be checked:'}, ...
                regexp(check.message, '\n', 'split')];
            return;
        end
        if ~isempty(check.errors)
            lines = {sprintf('%d error(s); nothing can be run until they are corrected:', ...
                numel(check.errors))};
            for kk = 1:numel(check.errors)
                item = check.errors(kk);
                where = '';
                if ~isempty(display) && ~isnan(item.line)
                    where = sprintf('line %d: ', item.line);
                end
                if ~isempty(item.subject)
                    where = [where 'subject ' item.subject ': ']; %#ok<AGROW>
                end
                lines{end + 1} = [where item.message]; %#ok<AGROW>
            end
            return;
        end
        lines = {sprintf('%d subject(s) valid for profile %s.', numel(check.subjects), ...
            config.profile_key)};
        if ~with_details
            return;
        end
        first = zeros(1, numel(check.subjects));
        for kk = 1:numel(check.subjects)
            item = check.subjects(kk);
            first(kk) = numel(lines) + 1;
            lines{end + 1} = sprintf('[%s]', item.id); %#ok<AGROW>
            lines = [lines, input_lines('MPRAGE', item.mprage, item.mprage_path, ...
                item.mprage_resolved, item.mprage_detail)]; %#ok<AGROW>
            if needs_umap
                lines = [lines, input_lines('UMAP', item.umap, item.umap_path, ...
                    item.umap_resolved, item.umap_detail)]; %#ok<AGROW>
            end
        end
    end

    function lines = input_lines(label, written, absolute, resolved, detail)
        lines = {sprintf('    %-7s %s', [label ':'], written)};
        if ~strcmp(absolute, written)
            lines{end + 1} = sprintf('            path: %s', absolute);
        end
        lines{end + 1} = sprintf('            %s', detail);
        if ~strcmp(resolved, absolute)
            lines{end + 1} = sprintf('            uses: %s', resolved);
        end
    end

% =====================================================================================
% Source, readiness and status
% =====================================================================================
    function set_source(name)
        if run_in_progress
            set(h.manual_radio, 'Value', strcmp(source, 'manual'));
            set(h.file_radio, 'Value', strcmp(source, 'file'));
            return;
        end
        source = name;
        set(h.manual_radio, 'Value', strcmp(source, 'manual'));
        set(h.file_radio, 'Value', strcmp(source, 'file'));
        set(h.manual_group, 'Visible', on_off(strcmp(source, 'manual')));
        set(h.file_group, 'Visible', on_off(strcmp(source, 'file')));
        note = '';
        refresh();
    end

    function [ready, problem] = readiness()
        % Local completeness only (no parsing): the launcher checks the list at Run.
        ready = false;
        if strcmp(source, 'manual')
            n = numel(manual.ids);
            if n == 0
                problem = 'Add a subject, or load a subjects file.';
                return;
            end
            for kk = 1:n
                label = sprintf('Subject %d (%s)', kk, manual.ids{kk});
                if isempty(manual.ids{kk})
                    problem = sprintf('Subject %d: enter a subject ID.', kk);
                    return;
                end
                if isempty(manual.mprage{kk})
                    problem = [label ': select the MPRAGE.'];
                    return;
                end
                if ~path_exists(manual.mprage{kk})
                    problem = [label ': the MPRAGE input does not exist.'];
                    return;
                end
                if needs_umap && isempty(manual.umap{kk})
                    problem = [label ': select the UMAP.'];
                    return;
                end
                if needs_umap && ~path_exists(manual.umap{kk})
                    problem = [label ': the UMAP input does not exist.'];
                    return;
                end
            end
        else
            if isempty(loaded.file)
                problem = 'Select a subjects file.';
                return;
            end
            if ~isstruct(loaded.check) || ~loaded.check.ok
                problem = 'The subjects file is not valid; see the list above.';
                return;
            end
            if ~strcmp(file_stamp(loaded.file), loaded.stamp)
                problem = 'The subjects file changed: press Check again.';
                return;
            end
        end
        ready = true;
        problem = '';
    end

    function refresh()
        if ~ishghandle(fig)
            return;
        end
        [ready, problem] = readiness();
        set(h.run_button, 'Enable', on_off(ready && ~run_in_progress));
        if run_in_progress
            return;
        end
        if ~ready
            text = problem;
        elseif needs_credentials
            text = 'Ready. Run asks for MLSC credentials, then starts processing.';
        else
            text = 'Ready. Run starts processing.';
        end
        if ~isempty(note)
            text = [note ' ' text];
        end
        set(h.status, 'String', text);
    end

    function set_status(text)
        if ishghandle(fig)
            set(h.status, 'String', text);
            drawnow;
        end
    end

% =====================================================================================
% Check, export and run
% =====================================================================================
    function on_check(~, ~)
        if run_in_progress
            return;
        end
        if strcmp(source, 'file')
            check_loaded_file(true);
            return;
        end
        if isempty(manual.ids)
            note = '';
            refresh();
            return;
        end
        set_busy(true);
        set_status('Checking the subjects...');
        try
            [file, temporary] = subjects_file_for_run();
            cleanup_file = onCleanup(@() delete_file(temporary)); %#ok<NASGU>
            check = pseudo_CT_launch_request('check-subjects', launch.launcher, ...
                config.profile_key, file);
            lines = check_lines(check, '', false);
            if check.ok
                msgbox(lines, 'Subjects checked');
            else
                show_lines(lines, 'Subjects not valid');
            end
        catch ME
            local_show_orchestration_error(ME, 'Check failed');
        end
        set_busy(false);
    end

    function on_export(~, ~)
        if run_in_progress
            return;
        end
        if isempty(manual.ids)
            warndlg('Add at least one subject before exporting.', 'Export subjects file');
            return;
        end
        start = last_dir;
        if exist(start, 'dir') ~= 7
            start = pwd;
        end
        [name, folder] = uiputfile({'*.txt', 'Subjects files (*.txt)'}, ...
            'Export subjects file', fullfile(start, 'subjects.txt'));
        if ~ishghandle(fig) || isequal(name, 0) || isequal(folder, 0)
            return;
        end
        target = fullfile(folder, name);
        try
            write_manual_file(target);
        catch ME
            local_show_orchestration_error(ME, 'Export failed');
            return;
        end
        set_busy(true);
        set_status('Checking the exported subjects file...');
        try
            check = pseudo_CT_launch_request('check-subjects', launch.launcher, ...
                config.profile_key, target);
            lines = check_lines(check, target, false);
            if check.ok
                msgbox([{sprintf('Exported %d subject(s) to:', numel(manual.ids)), ...
                    target, ''}, lines], 'Subjects file exported');
            else
                show_lines([{'The file was written, but it is not valid yet:', target}, ...
                    lines], 'Subjects file exported');
            end
        catch ME
            local_show_orchestration_error(ME, 'Export check failed');
        end
        set_busy(false);
    end

    function write_manual_file(target)
        umap = {};
        if needs_umap
            umap = manual.umap;
        end
        % Manual paths are stored absolute (absolute_path, the dialogs and UMAP discovery
        % all give absolute paths). Refuse anything else rather than let the parser
        % resolve it against the folder of TARGET (a temporary folder for Run).
        all_paths = [manual.mprage, umap];
        for kk = 1:numel(all_paths)
            if ~isempty(all_paths{kk}) && all_paths{kk}(1) ~= '/'
                error('pseudo_CT:GuiRelativePath', ['The path %s is not absolute; ' ...
                    'select it again with File... or Folder....'], all_paths{kk});
            end
        end
        pseudo_CT_subjects_file('write', target, manual.ids, manual.mprage, umap);
    end

    function [file, temporary] = subjects_file_for_run()
        % The one subjects file of a run: the loaded file, or a temporary file written
        % from the manual list (TEMPORARY is its path, '' for a loaded file).
        if strcmp(source, 'file')
            file = loaded.file;
            temporary = '';
            return;
        end
        temporary = [tempname '.txt'];
        try
            write_manual_file(temporary);
        catch ME
            delete_file(temporary);
            rethrow(ME);
        end
        file = temporary;
    end

    function on_run(~, ~)
        if run_in_progress
            return;
        end
        set_busy(true);
        handoff = '';
        temporary = '';
        login = struct('ok', false, 'username', '', 'password', '', 'group_account', '');
        outcome = 'Run stopped: nothing was submitted.';
        try
            [file, temporary] = subjects_file_for_run();
            set_status('Checking the subjects...');
            check = pseudo_CT_launch_request('check-subjects', launch.launcher, ...
                config.profile_key, file);
            submit = check.ok;
            if ~submit
                display = file;
                if ~isempty(temporary)
                    display = '';
                end
                show_lines(check_lines(check, display, false), 'Run stopped');
                outcome = 'Not submitted: the subject list is not valid.';
                if strcmp(source, 'file')
                    check_loaded_file(false);
                end
            end
            values = run_values(file);
            if submit && needs_credentials
                [login, outcome] = local_mlsc_login(values);
                submit = login.ok;
            end
            if submit && ~ishghandle(fig)
                submit = false;
                outcome = 'Window closed: nothing was submitted.';
            end
            if submit
                if needs_credentials
                    % Fresh single-use handoff from the same in-memory credentials that
                    % just authenticated; its path (not the secret) is the only value
                    % passed on.
                    handoff = pseudo_CT_credentials('store', login.username, login.password);
                    values.credential_handoff = handoff;
                    values.group_account = login.group_account;
                end
                % One launcher call: resolve the subjects and dispatch the run.
                set_status(sprintf(['Processing %d subject(s) - see MATLAB Command ' ...
                    'Window for progress.'], numel(check.subjects)));
                result = local_launcher(values, 'submit');
                if result.ok
                    outcome = local_job_text(result);
                    msgbox(outcome, 'Submitted');
                else
                    local_show_result_error(result, 'Run failed');
                    outcome = sprintf('Not submitted: %s', local_error_code(result));
                end
            end
        catch ME
            local_show_orchestration_error(ME, 'Run failed');
            outcome = 'Not submitted: see the error message.';
        end
        login = local_clear_login(login); %#ok<NASGU>
        local_discard_handoff(handoff);
        delete_file(temporary);
        set_busy(false);
        if ishghandle(fig)
            note = '';
            set(h.status, 'String', outcome);
        end
    end

    function values = run_values(file)
        %RUN_VALUES Window state as the values pseudo_CT_gui_args expects.
        values = struct();
        values.profile = config.profile_key;
        values.subjects_file = file;
        values.mprage = '';
        values.umap = '';
        values.aliasing = logical(get(h.aliasing, 'Value'));
        values.recenter = logical(get(h.recenter, 'Value'));
        values.cleanup = logical(get(h.cleanup, 'Value'));
        values.gui_mode = gui_mode;
        values.group_account = '';
        values.credential_handoff = '';
    end

    function result = local_launcher(values, action)
        %LOCAL_LAUNCHER One launcher call for the window values: parse, then invoke.
        args = pseudo_CT_gui_args(values, launch, action);
        request = pseudo_CT_launch_request('parse', args, launch.root_dir);
        result = pseudo_CT_launch_request('invoke', request);
    end

    function [login, outcome] = local_mlsc_login(values)
        %LOCAL_MLSC_LOGIN Ask for the MLSC login and authenticate it through the launcher
        %   (authenticate only) until it succeeds or the user cancels. Nothing is
        %   submitted. AUTHENTICATION_FAILED and INVALID_GROUP_ACCOUNT show the launcher
        %   message (no secret) and re-open the dialog with the username and account
        %   pre-filled; any other error code stops with that message. Each attempt's
        %   handoff is discarded at once. On success LOGIN.password holds the in-memory
        %   password for the fresh submit handoff; the caller clears it.
        login = struct('ok', false, 'username', '', 'password', '', 'group_account', '');
        outcome = 'Cancelled: nothing was submitted.';
        username_default = '';
        group_default = '';
        failures = 0;
        limit = local_auth_retry_limit();
        while true
            if ~ishghandle(fig)
                outcome = 'Window closed: nothing was submitted.';
                return;
            end
            [password, username, group_account] = pseudo_CT_password_entry_dialog( ...
                'enterUserName', true, 'enterGroupAccount', true, ...
                'DefaultUserName', username_default, ...
                'DefaultGroupAccount', group_default, ...
                'CheckPasswordLength', true, 'PasswordLengthMin', 1, ...
                'PasswordLengthMax', 50, 'WindowName', 'MLSC login');
            if isequal(password, -1) || isempty(username)
                password = ''; %#ok<NASGU>
                return;
            end
            username_default = username;
            group_default = group_account;
            % The single-use handoff is the existing credential MAT format; its path (not
            % the secret) is the only value passed to the launcher.
            handoff = pseudo_CT_credentials('store', username, password);
            % Discards this attempt's handoff on every exit from the attempt, including a
            % thrown launcher error (the explicit discard below covers the normal path).
            cleanup_handoff = onCleanup(@() local_discard_handoff(handoff)); %#ok<NASGU>
            values.credential_handoff = handoff;
            values.group_account = group_account;
            set_status('Checking the MLSC login...');
            result = local_launcher(values, 'authenticate');
            local_discard_handoff(handoff);
            if result.ok && strcmp(result.authentication_status, 'authenticated') && ...
                    isempty(result.error_code)
                login = struct('ok', true, 'username', username, 'password', password, ...
                    'group_account', group_account);
                password = ''; %#ok<NASGU>
                outcome = 'Login accepted.';
                return;
            end
            code = local_error_code(result);
            password = ''; %#ok<NASGU>
            if ~any(strcmp(code, {'AUTHENTICATION_FAILED'; 'INVALID_GROUP_ACCOUNT'}))
                local_show_result_error(result, 'Login failed');
                outcome = sprintf('Not submitted: %s', code);
                return;
            end
            failures = failures + 1;
            if ~isempty(limit) && failures > limit
                local_show_result_error(result, 'Login failed');
                outcome = sprintf('Not submitted: %s after %d attempts', code, failures);
                return;
            end
            local_show_result_error(result, 'Login rejected');
            set_status(sprintf( ...
                'Login rejected (%s). Enter the credentials again or cancel.', code));
        end
    end

% =====================================================================================
% Busy state and closing
% =====================================================================================
    function set_busy(running)
        %SET_BUSY Lock every input while the launcher runs, then restore and refresh.
        run_in_progress = logical(running);
        if ~ishghandle(fig)
            return;
        end
        controls = [h.manual_radio h.file_radio h.manual_table h.add_button ...
            h.remove_button h.export_button h.id_edit h.mprage_edit h.mprage_file ...
            h.mprage_dir h.umap_edit h.umap_file h.umap_dir h.file_browse ...
            h.file_recheck h.file_table h.file_details h.aliasing h.recenter h.cleanup ...
            h.check_button h.close_button];
        if running
            set(controls, 'Enable', 'off');
            set(h.run_button, 'Enable', 'off');
            set(h.status, 'String', 'Working: the launcher is running.');
            drawnow;
            return;
        end
        set(controls, 'Enable', 'on');
        set(h.file_edit, 'Enable', 'inactive');
        show_selected();
        refresh();
    end

    function on_close(~, ~)
        if ~run_in_progress && ishghandle(fig)
            delete(fig);
        end
    end

    function on_close_request(~, ~)
        % While a Run is in progress the window-X request is ignored.
        if run_in_progress
            return;
        end
        delete(fig);
    end

% =====================================================================================
% Small helpers
% =====================================================================================
    function text = header_text()
        name = config.profile_key;
        if isfield(config, 'presentation') && isfield(config.presentation, 'display_name')
            name = config.presentation.display_name;
        end
        runtime = launch.runtime;
        if isempty(runtime)
            runtime = 'development launcher';
        end
        if needs_umap
            inputs = 'MPRAGE and UMAP per subject';
        else
            inputs = 'MPRAGE per subject (no UMAP)';
        end
        text = sprintf('Profile: %s   |   Runtime: %s   |   Inputs: %s', name, ...
            runtime, inputs);
    end

    function show_lines(lines, title_text)
        % A modal list of message lines (all errors, however many).
        screen = get(0, 'ScreenSize');
        width = min(screen(3) - 80, round(110 * metrics.char_w));
        height = min(screen(4) - 120, round(24 * metrics.row_h));
        dialog = figure('Name', title_text, 'NumberTitle', 'off', 'MenuBar', 'none', ...
            'ToolBar', 'none', 'Units', 'pixels', 'WindowStyle', 'modal', ...
            'Resize', 'off', 'IntegerHandle', 'off', 'HandleVisibility', 'callback', ...
            'Position', [floor((screen(3) - width) / 2), floor((screen(4) - height) / 2), ...
            width, height]);
        m = metrics.margin;
        uicontrol(dialog, 'Style', 'listbox', 'String', lines, 'Min', 0, 'Max', 2, ...
            'Value', [], 'BackgroundColor', 'white', ...
            'Position', [m, 2 * m + metrics.row_h, width - 2 * m, ...
            height - 3 * m - metrics.row_h]);
        uicontrol(dialog, 'Style', 'pushbutton', 'String', 'OK', ...
            'Position', [width - m - 100, m, 100, metrics.row_h], ...
            'Callback', @(s, e) delete(dialog));
        uiwait(dialog);
    end

    function local_discard_handoff(handoff)
        %LOCAL_DISCARD_HANDOFF Erase a handoff the launcher did not consume.
        if isempty(handoff) || exist(handoff, 'file') ~= 2
            return;
        end
        try
            pseudo_CT_credentials('consume', handoff);
        catch %#ok<CTCH>
            warndlg('A credential handoff could not be erased; remove it from /dev/shm.', ...
                'Credential cleanup');
        end
    end
end

% =======================================================================================
% Subfunctions (no window state)
% =======================================================================================
function path_text = absolute_path(path_text)
%ABSOLUTE_PATH A typed or pasted manual path as an absolute path with the meaning it has
%   now: '~' and '~/...' name the home folder; a relative path is taken against the
%   current MATLAB folder; '.' and '..' segments of an existing input are resolved by the
%   file system (so a symbolic link keeps its meaning). The subjects file then never
%   holds a relative path, which its parser would resolve against the subjects file's
%   own folder (a temporary folder for Run).
if isempty(path_text)
    return;
end
if strcmp(path_text, '~') || strncmp(path_text, '~/', 2)
    path_text = [getenv('HOME') path_text(2:end)];
end
if path_text(1) ~= '/'
    path_text = fullfile(pwd, path_text);
end
if isempty(regexp(path_text, '(^|/)\.\.?(/|$)', 'once'))
    return;
end
if exist(path_text, 'dir') == 7
    path_text = physical_dir(path_text);
elseif exist(path_text, 'file') == 2
    [folder, name, ext] = fileparts(path_text);
    path_text = fullfile(physical_dir(folder), [name ext]);
end
end

function folder = physical_dir(folder)
%PHYSICAL_DIR The folder as the file system resolves it (no '.' or '..' segments).
previous = pwd;
restore = onCleanup(@() cd(previous)); %#ok<NASGU>
cd(folder);
folder = pwd;
end

function flag = path_exists(path_text)
flag = exist(path_text, 'file') == 2 || exist(path_text, 'dir') == 7;
end

function stamp = file_stamp(path_text)
info = dir(path_text);
if isempty(info) || numel(info) ~= 1 || info(1).isdir
    stamp = 'missing';
else
    stamp = sprintf('%d|%.6f', info(1).bytes, info(1).datenum);
end
end

function delete_file(path_text)
if ~isempty(path_text) && exist(path_text, 'file') == 2
    delete(path_text);
end
end

function text = on_off(flag)
if flag
    text = 'on';
else
    text = 'off';
end
end

function limit = local_auth_retry_limit()
%LOCAL_AUTH_RETRY_LIMIT Retry limit of the GUI login loop: [] (no limit), so the user
%   retries until a login succeeds or cancels. The matching terminal setting is
%   PSEUDOCT_AUTH_RETRY_LIMIT in bin/pseudoct (empty: no limit; N: N retries after the
%   first failed attempt). The GUI sets no numeric limit of its own.
limit = [];
end

function login = local_clear_login(login)
%LOCAL_CLEAR_LOGIN Erase the in-memory MLSC password and login fields.
if isstruct(login)
    login.password = '';
    login.username = '';
    login.group_account = '';
end
end

function code = local_error_code(result)
code = result.error_code;
if isempty(code)
    code = 'LAUNCHER_FAILED';
end
end

function text = local_job_text(result)
if isempty(result.job_ids)
    text = sprintf('Submitted (%s).', result.outcome);
else
    text = sprintf('Submitted. Job ids: %s', sprintf('%s ', result.job_ids{:}));
end
end

function local_show_result_error(result, title_text)
code = result.error_code;
message = result.error_message;
if isempty(code)
    code = 'LAUNCHER_FAILED';
end
if isempty(message)
    message = result.outcome;
end
warndlg(sprintf('%s\n\n%s', code, message), title_text);
end

function local_show_orchestration_error(ME, title_text)
identifier = ME.identifier;
if isempty(identifier)
    identifier = 'pseudo_CT:GuiError';
end
warndlg(sprintf(['%s\n\n%s\n\nCorrect the selected inputs or options, ', ...
    'then press Run again.'], identifier, ME.message), title_text);
end

function value = normalize_gui_flag(value, fallback)
%NORMALIZE_GUI_FLAG Normalize profile/default values for the option checkboxes.
input_value = value;
value = logical(fallback);
if islogical(input_value) && isscalar(input_value)
    value = input_value;
elseif isnumeric(input_value) && isscalar(input_value) && ...
        ismember(input_value, [0 1])
    value = logical(input_value);
elseif ischar(input_value)
    input_value = lower(strtrim(input_value));
    if ismember(input_value, {'yes'; 'true'; 'on'; '1'})
        value = true;
    elseif ismember(input_value, {'no'; 'false'; 'off'; '0'})
        value = false;
    end
end
value = double(value);
end
