function varargout = load_mr_4_AC(varargin)
% LOAD_MR_4_AC pseudoCT input window (MATLAB frontend, GUIDE layout).
%   LOAD_MR_4_AC(MODE, CONFIG, CONTEXT) opens the window for one profile.
%   MODE is 'mMR' or 'mprage-only'. CONFIG is one entry of
%   pseudo_CT_profile_choices (name, config). CONTEXT holds launcher, runtime,
%   mcr_root and root_dir (see run_pseudo_CT).
%
%   Validate and Submit both go through the compiled launcher by way of
%   pseudo_CT_launch_request. Submit is enabled only after a successful
%   Validate of exactly the current inputs and options. The window stays open
%   for another job after each request, but the launcher call is synchronous:
%   MATLAB is busy until Validate or Submit returns.
%   Minimum supported MATLAB: R2010b.

% Edit the above text to modify the response to help load_mr_4_AC

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @load_mr_4_AC_OpeningFcn, ...
                   'gui_OutputFcn',  @load_mr_4_AC_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1}) && ...
        ~any(strcmp(varargin{1}, {'mMR'; 'mprage-only'}))
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% --- Executes just before load_mr_4_AC is made visible.
function load_mr_4_AC_OpeningFcn(hObject, eventdata, handles, varargin)
% varargin   MODE, CONFIG and CONTEXT (see the help above)

if numel(varargin) ~= 3 || ~ischar(varargin{1}) || ...
        ~any(strcmp(varargin{1}, {'mMR'; 'mprage-only'})) || ...
        ~isstruct(varargin{2}) || numel(varargin{2}) ~= 1 || ...
        ~isfield(varargin{2}, 'profile_key') || ~isstruct(varargin{3})
    error('pseudo_CT:GuiLaunch', ...
        'The window needs a mode, one profile configuration and a launch context.');
end
config = varargin{2};
launch = varargin{3};
if ~isfield(launch, 'launcher') || ~isfield(launch, 'runtime') || ...
        ~isfield(launch, 'mcr_root') || ~isfield(launch, 'root_dir')
    error('pseudo_CT:GuiLaunch', 'The launch context is incomplete.');
end

% The saved GUIDE figure can retain stale dimensions. Establish the window
% geometry in pixels before positioning any controls.
screen_size = get(0, 'ScreenSize');
figure_position = [max(1, floor((screen_size(3) - 780) / 2)), ...
    max(1, floor((screen_size(4) - 460) / 2)), 780, 460];
set(hObject, 'Units', 'pixels');
set(hObject, 'Position', figure_position);

handles = local_refresh_control_handles(handles, hObject);

handles.mprage_fn = 0;
handles.ute_fn = 0;
handles.umap_fn = 0;
handles.gui_mode = varargin{1};
handles.validation_config = config;
handles.launch = launch;
handles.validation = [];
handles.run_in_progress = false;
handles.gui_handoff = struct('credentials', struct(), 'group_account', '');

aliasing_default = config.aliasing_default;
recentering_default = config.recenter_before_normalization;
cleanup_default = config.cleanup_on_success;
if ~strcmp(handles.gui_mode, config.io_policy.gui)
    error('pseudo_CT:InvalidProfile', ...
        'The window mode does not match the selected profile.');
end
if strcmp(handles.gui_mode, 'mprage-only')
    handles.gui_mode = 'mprage-only';
    set(handles.load_ute_edit, 'Visible', 'Off');
    set(handles.load_ute_button, 'Visible', 'Off');
    set(handles.load_umap_edit, 'Visible', 'Off');
    set(handles.load_umap_button, 'Visible', 'Off');
    set(handles.load_mprage_button, 'String', 'Browse MPRAGE...');
    set(handles.load_mprage_edit, 'String', 'Load MPRAGE image (dicom or nifty)');
else
    set(handles.load_ute_edit, 'Visible', 'Off');
    set(handles.load_ute_button, 'Visible', 'Off');
    set(handles.load_mprage_button, 'String', 'Browse MPRAGE...');
    set(handles.load_mprage_edit, 'String', 'Load MPRAGE image (dicom or nifty)');
end

handles.correct_aliasing = normalize_gui_flag(aliasing_default, true);
handles.recenter_before_normalization = normalize_gui_flag(recentering_default, false);
handles.cleanup_on_success = normalize_gui_flag(cleanup_default, true);
set(handles.aliasing_button, 'Value', handles.correct_aliasing);
set(handles.recentering_button, 'Value', handles.recenter_before_normalization);

set(handles.ok_button, 'String', 'Validate', 'Enable', 'on', 'FontSize', 12);
set(handles.cancel_button, 'String', 'Close', 'FontSize', 12);
handles.cleanup_on_success_checkbox = uicontrol( ...
    'Parent', get(handles.cancel_button, 'Parent'), ...
    'Style', 'checkbox', ...
    'String', 'Remove temporary files after successful processing', ...
    'Units', 'pixels', ...
    'Position', [24 46 732 22], ...
    'FontSize', get(handles.aliasing_button, 'FontSize'), ...
    'HorizontalAlignment', get(handles.aliasing_button, ...
        'HorizontalAlignment'), ...
    'Tag', 'cleanup_on_success_checkbox', ...
    'Value', handles.cleanup_on_success, ...
    'Callback', @cleanup_on_success_checkbox_Callback);
handles.submit_button = uicontrol( ...
    'Parent', get(handles.cancel_button, 'Parent'), ...
    'Style', 'pushbutton', 'String', 'Submit', ...
    'Units', 'pixels', 'Position', [590 10 166 32], ...
    'FontSize', 12, 'Enable', 'off', 'Tag', 'submit_button', ...
    'Callback', @submit_button_Callback);
handles.status_text = uicontrol( ...
    'Parent', get(handles.cancel_button, 'Parent'), ...
    'Style', 'text', 'String', '', 'Units', 'pixels', ...
    'Position', [24 10 200 32], 'FontSize', 10, ...
    'HorizontalAlignment', 'left', 'Tag', 'pseudo_CT_status');
handles = local_apply_control_layout(handles);
handles = local_refresh_buttons(handles);

guidata(hObject, handles);

% X-close is Close: the window is removed and nothing is left waiting.
set(hObject, 'CloseRequestFcn', @load_mr_4_AC_CloseRequestFcn);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% --- Outputs from this function are returned to the command line.
function varargout = load_mr_4_AC_OutputFcn(hObject, eventdata, handles)
% The window is not modal and returns no selection.
varargout{1} = [];

% --- Executes when the user attempts to close the figure (window-X).
function load_mr_4_AC_CloseRequestFcn(hObject, eventdata, handles)
if ishghandle(hObject)
    delete(hObject);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% --- Executes on button press in load_mprage_button.
function load_mprage_button_Callback(hObject, eventdata, handles)
handles = local_refresh_control_handles(handles, hObject);
P = pseudo_CT_select_file(['Select the MPRAGE file to use to obtain an ' ...
    'atlas-based attenuation map (It could be a Dicom)']);
if size(P, 1) == 0
    set(handles.load_mprage_edit, 'String', 'Load only 1 filename ... ');
    handles = local_invalidate_validation(handles);
    guidata(hObject, handles);
    warndlg('Load only 1 filename (even if there are many Dicoms!!)', 'Load only 1 filename');
    return;
end
if exist(P, 'file') ~= 2
    warndlg('The input should be a valid filename!', 'Error in filename!');
    return;
end
handles = local_set_mprage(handles, P);
guidata(hObject, handles);

% --- Executes on edit change of load_mprage_edit (typed path).
function load_mprage_edit_Callback(hObject, eventdata, handles)
handles = local_refresh_control_handles(handles, hObject);
fn = strtrim(get(hObject, 'String'));
handles = local_invalidate_validation(handles);
if ~ischar(fn) || exist(fn, 'file') ~= 2
    guidata(hObject, handles);
    return;
end
handles = local_set_mprage(handles, fn);
guidata(hObject, handles);

% --- Executes during object creation, after setting all properties.
function load_mprage_edit_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

% --- Executes on button press in load_ute_button.
function load_ute_button_Callback(hObject, eventdata, handles)
handles = local_refresh_control_handles(handles, hObject);
P = pseudo_CT_select_file(['Select the UTE_2 file to use to obtain an ' ...
    'atlas-based attenuation map (It could be a Dicom)']);
if size(P, 1) == 0
    set(handles.load_ute_edit, 'String', 'Load only 1 filename ... ');
    handles = local_invalidate_validation(handles);
    guidata(hObject, handles);
    return;
end
handles.ute_fn = P;
set(handles.load_ute_edit, 'String', handles.ute_fn);
handles = local_invalidate_validation(handles);
guidata(hObject, handles);

% --- Executes on edit change of load_ute_edit.
function load_ute_edit_Callback(hObject, eventdata, handles)
handles = local_refresh_control_handles(handles, hObject);
handles.ute_fn = strtrim(get(hObject, 'String'));
handles = local_invalidate_validation(handles);
guidata(hObject, handles);

% --- Executes during object creation, after setting all properties.
function load_ute_edit_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

% --- Executes on button press in load_umap_button.
function load_umap_button_Callback(hObject, eventdata, handles)
handles = local_refresh_control_handles(handles, hObject);
P = pseudo_CT_select_file(['Select the UMAP file to use to obtain an ' ...
    'atlas-based attenuation map (It could be a Dicom)']);
if size(P, 1) == 0
    set(handles.load_umap_edit, 'String', 'Load only 1 filename ... ');
    handles = local_invalidate_validation(handles);
    guidata(hObject, handles);
    warndlg('Load only 1 filename (even if there are many Dicoms!!)', 'Load only 1 filename');
    return;
end
if exist(P, 'file') ~= 2
    warndlg('The input should be a valid filename!', 'Error in filename!');
    return;
end
handles.umap_fn = P;
set(handles.load_umap_edit, 'String', handles.umap_fn);
handles = local_invalidate_validation(handles);
guidata(hObject, handles);

% --- Executes on edit change of load_umap_edit.
function load_umap_edit_Callback(hObject, eventdata, handles)
handles = local_refresh_control_handles(handles, hObject);
handles.umap_fn = strtrim(get(hObject, 'String'));
handles = local_invalidate_validation(handles);
guidata(hObject, handles);

% --- Executes during object creation, after setting all properties.
function load_umap_edit_CreateFcn(hObject, eventdata, handles)
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% --- Executes on button press in ok_button: Validate through the launcher.
function ok_button_Callback(hObject, eventdata, handles)
handles = guidata(hObject);
handles = local_refresh_control_handles(handles, hObject);
if handles.run_in_progress
    return;
end
handles = local_set_run_state(handles, true);
guidata(hObject, handles);
drawnow;
try
    values = local_values(handles);
    args = pseudo_CT_gui_args(values, handles.launch, 'validate');
    request = pseudo_CT_launch_request('parse', args, handles.launch.root_dir);
    result = pseudo_CT_launch_request('invoke', request);
    handles.validation = struct('fingerprint', request.fingerprint, ...
        'ok', result.ok, 'result', result);
    if ~result.ok
        local_show_result_error(result, 'Validation failed');
    end
catch ME
    handles.validation = [];
    local_show_orchestration_error(ME, 'Validation failed');
end
handles = local_set_run_state(handles, false);
guidata(hObject, handles);

% --- Executes on button press in submit_button: launcher run with the same request.
function submit_button_Callback(hObject, eventdata, handles)
handles = guidata(hObject);
handles = local_refresh_control_handles(handles, hObject);
if handles.run_in_progress
    return;
end
handles = local_refresh_buttons(handles);
if ~strcmp(get(handles.submit_button, 'Enable'), 'on')
    warndlg('Validate the current inputs before Submit.', 'Submit not enabled');
    guidata(hObject, handles);
    return;
end
handles = local_set_run_state(handles, true);
guidata(hObject, handles);
drawnow;
values = local_values(handles);
handoff = '';
try
    % The Submit request must be the validated one: same fingerprint.
    check = pseudo_CT_launch_request('parse', ...
        pseudo_CT_gui_args(values, handles.launch, 'validate'), ...
        handles.launch.root_dir);
    if ~strcmp(check.fingerprint, handles.validation.fingerprint)
        error('pseudo_CT:GuiStaleValidation', ...
            'The inputs changed after validation. Validate again before Submit.');
    end
    if local_requires_gui_credentials(handles.validation_config)
        [password, username, group_account] = pseudo_CT_password_entry_dialog( ...
            'enterUserName', true, 'enterGroupAccount', true, ...
            'DefaultUserName', '', 'DefaultGroupAccount', '', ...
            'CheckPasswordLength', true, 'PasswordLengthMin', 1, ...
            'PasswordLengthMax', 50, 'WindowName', 'MLSC submit login');
        if isequal(password, -1) || isempty(username)
            clear password username group_account
            handles = local_set_run_state(handles, false);
            guidata(hObject, handles);
            return;
        end
        % The single-use handoff is the existing credential MAT format; its path
        % (not the secret) is the only value passed to the launcher.
        handoff = pseudo_CT_credentials('store', username, password);
        clear password username
        values.credential_handoff = handoff;
        values.group_account = group_account;
        clear group_account
    end
    args = pseudo_CT_gui_args(values, handles.launch, 'submit');
    request = pseudo_CT_launch_request('parse', args, handles.launch.root_dir);
    result = pseudo_CT_launch_request('invoke', request);
    if result.ok
        msgbox(local_job_text(result), 'Submitted');
    else
        local_show_result_error(result, 'Submission failed');
    end
catch ME
    local_show_orchestration_error(ME, 'Submission failed');
end
handles = local_discard_handoff(handles, handoff);
% A submission consumes its validation: Submit needs a new Validate.
handles.validation = [];
handles = local_set_run_state(handles, false);
guidata(hObject, handles);

% --- Executes on button press in cancel_button (Close).
function cancel_button_Callback(hObject, eventdata, handles)
figure_handle = ancestor(hObject, 'figure');
if ~isempty(figure_handle) && ishghandle(figure_handle)
    delete(figure_handle);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% --- Executes on button press in aliasing_button.
function aliasing_button_Callback(hObject, eventdata, handles)
handles = local_refresh_control_handles(handles, hObject);
handles.correct_aliasing = logical(get(hObject,'Value'));
handles = local_invalidate_validation(handles);
guidata(hObject, handles);

% --- Executes on button press in recentering_button.
function recentering_button_Callback(hObject, eventdata, handles)
handles = local_refresh_control_handles(handles, hObject);
handles.recenter_before_normalization = logical(get(hObject,'Value'));
handles = local_invalidate_validation(handles);
guidata(hObject, handles);

% --- Executes on button press in cleanup_on_success_checkbox.
function cleanup_on_success_checkbox_Callback(hObject, eventdata, handles)
if nargin < 3 || ~isstruct(handles)
    handles = guidata(hObject);
end
handles = local_refresh_control_handles(handles, hObject);
handles.cleanup_on_success = logical(get(hObject, 'Value'));
handles = local_invalidate_validation(handles);
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function handles = local_set_mprage(handles, P)
%LOCAL_SET_MPRAGE Store one MPRAGE path, show the discovered UMAP and invalidate.
handles.mprage_fn = P;
set(handles.load_mprage_edit, 'String', P);
if strcmp(handles.gui_mode, 'mprage-only')
    handles.ute_fn = '';
    handles.umap_fn = '';
else
    handles.ute_fn = 0;
    handles.umap_fn = pseudo_CT_discover_umap(P);
    set(handles.load_umap_edit, 'String', local_umap_text(handles.umap_fn));
end
handles = local_invalidate_validation(handles);

function text = local_umap_text(umap_fn)
if ischar(umap_fn) && ~isempty(umap_fn)
    text = umap_fn;
else
    text = 'No UMAP filename found!! Find your UMAP file!';
end

function values = local_values(handles)
%LOCAL_VALUES Control state as the values pseudo_CT_gui_args expects.
values = struct();
values.profile = handles.validation_config.profile_key;
values.mprage = strtrim(get(handles.load_mprage_edit, 'String'));
values.umap = strtrim(get(handles.load_umap_edit, 'String'));
if ~isempty(strfind(lower(values.umap), 'no umap filename found')) || ...
        ~isempty(strfind(lower(values.umap), 'load umap'))
    values.umap = '';
end
values.aliasing = logical(get(handles.aliasing_button, 'Value'));
values.recenter = logical(get(handles.recentering_button, 'Value'));
values.cleanup = logical(get(handles.cleanup_on_success_checkbox, 'Value'));
values.gui_mode = handles.gui_mode;
values.group_account = '';
values.credential_handoff = '';

function handles = local_invalidate_validation(handles)
%LOCAL_INVALIDATE_VALIDATION Any input or option change removes the validation.
if ~isstruct(handles)
    return;
end
handles.validation = [];
handles = local_refresh_buttons(handles);

function handles = local_refresh_buttons(handles)
%LOCAL_REFRESH_BUTTONS Enable flags and status from pseudo_CT_gui_state.
fingerprint = '';
try
    values = local_values(handles);
    request = pseudo_CT_launch_request('parse', ...
        pseudo_CT_gui_args(values, handles.launch, 'validate'), ...
        handles.launch.root_dir);
    fingerprint = request.fingerprint;
catch %#ok<CTCH>
    fingerprint = '';
end
validation = [];
if isfield(handles, 'validation')
    validation = handles.validation;
end
busy = isfield(handles, 'run_in_progress') && handles.run_in_progress;
state = pseudo_CT_gui_state(fingerprint, validation, busy);
if isfield(handles, 'ok_button') && ishghandle(handles.ok_button)
    set(handles.ok_button, 'Enable', local_on_off(state.validate_enabled && ~busy));
end
if isfield(handles, 'submit_button') && ishghandle(handles.submit_button)
    set(handles.submit_button, 'Enable', local_on_off(state.submit_enabled && ~busy));
end
if isfield(handles, 'status_text') && ishghandle(handles.status_text)
    set(handles.status_text, 'String', state.message);
end

function text = local_on_off(flag)
if flag
    text = 'on';
else
    text = 'off';
end

function handles = local_refresh_control_handles(handles, hObject)
% Rebuild missing GUIDE handle fields from the current figure's Tags.
if ~isstruct(handles)
    handles = struct();
end
figure_handle = ancestor(hObject, 'figure');
if isempty(figure_handle) || ~ishghandle(figure_handle)
    error('pseudo_CT:GuiControlMissing', ...
        'The GUI figure is unavailable; close and reopen the input window.');
end
figure_handles = guihandles(figure_handle);
names = fieldnames(figure_handles);
for ii = 1:length(names)
    name = names{ii};
    if ~isfield(handles, name) || ~ishghandle(handles.(name))
        handles.(name) = figure_handles.(name);
    end
end
required = {'load_mprage_edit'; 'load_mprage_button'; ...
    'load_ute_edit'; 'load_ute_button'; 'load_umap_edit'; ...
    'load_umap_button'; 'aliasing_button'; 'recentering_button'; ...
    'ok_button'; 'cancel_button'; 'processing_options_heading'};
for ii = 1:length(required)
    name = required{ii};
    if ~isfield(handles, name) || ~ishghandle(handles.(name))
        error('pseudo_CT:GuiControlMissing', ...
        'The GUIDE control Tag "%s" is missing; check load_mr_4_AC.fig.', ...
        name);
    end
end

function handles = local_apply_control_layout(handles)
% Use pixel coordinates for both the window and every child control.
input_button_positions = [24 370 170 34; 24 286 170 34; 24 202 170 34];
input_field_positions = [24 332 732 30; 24 248 732 30; 24 164 732 30];
option_y = [98 72 46];
heading_y = 126;
if strcmp(handles.gui_mode, 'mprage-only')
    % Collapse hidden UTE/UMAP rows and bring the options directly below the
    % single visible input instead of leaving two misleading empty slots.
    option_y = [257 231 205];
    heading_y = 285;
    set(handles.load_ute_edit, 'Visible', 'off');
    set(handles.load_ute_button, 'Visible', 'off');
    set(handles.load_umap_edit, 'Visible', 'off');
    set(handles.load_umap_button, 'Visible', 'off');
end

button_names = {'load_mprage_button'; 'load_ute_button'; 'load_umap_button'};
field_names = {'load_mprage_edit'; 'load_ute_edit'; 'load_umap_edit'};
for ii = 1:3
    set(handles.(button_names{ii}), 'Units', 'pixels');
    set(handles.(button_names{ii}), 'Position', input_button_positions(ii,:));
    set(handles.(field_names{ii}), 'Units', 'pixels');
    set(handles.(field_names{ii}), 'Position', input_field_positions(ii,:));
end
set(handles.load_mprage_button, 'FontSize', 11);
set(handles.load_ute_button, 'String', 'Browse UTE...', 'FontSize', 11);
set(handles.load_umap_button, 'String', 'Browse UMAP...', 'FontSize', 11);
set(handles.load_mprage_edit, 'FontSize', 11, 'HorizontalAlignment', 'left');
set(handles.load_ute_edit, 'FontSize', 11, 'HorizontalAlignment', 'left');
set(handles.load_umap_edit, 'FontSize', 11, 'HorizontalAlignment', 'left');
if isfield(handles, 'text1') && ishghandle(handles.text1)
    set(handles.text1, 'Units', 'pixels');
    set(handles.text1, 'Position', [24 422 732 28]);
end
set(handles.processing_options_heading, 'Units', 'pixels');
set(handles.processing_options_heading, 'String', 'Processing options', ...
    'Position', [24 heading_y 732 24], 'FontSize', 12, ...
    'FontWeight', 'bold', 'HorizontalAlignment', 'left');
option_names = {'aliasing_button'; 'recentering_button'; ...
    'cleanup_on_success_checkbox'};
for ii = 1:3
    set(handles.(option_names{ii}), 'Units', 'pixels');
    set(handles.(option_names{ii}), 'Position', [24 option_y(ii) 732 22]);
    set(handles.(option_names{ii}), 'FontSize', 11, 'HorizontalAlignment', 'left');
end
set(handles.ok_button, 'Units', 'pixels');
set(handles.ok_button, 'String', 'Validate', 'Position', [414 10 150 32], 'FontSize', 12);
set(handles.submit_button, 'Units', 'pixels', 'Position', [590 10 166 32]);
set(handles.cancel_button, 'Units', 'pixels');
set(handles.cancel_button, 'Position', [238 10 150 32], 'FontSize', 12);
set(handles.status_text, 'Units', 'pixels', 'Position', [24 10 200 32]);

function flag = local_requires_gui_credentials(config)
flag = isstruct(config) && isfield(config, 'mode') && ...
    ischar(config.mode) && strcmp(config.mode, 'mlsc');

function handles = local_set_run_state(handles, running)
%LOCAL_SET_RUN_STATE Lock the inputs while the launcher runs, then refresh.
handles.run_in_progress = logical(running);
enable_value = 'on';
if running
    enable_value = 'off';
end
controls = {'load_mprage_button'; 'load_mprage_edit'; ...
    'load_ute_button'; 'load_ute_edit'; 'load_umap_button'; ...
    'load_umap_edit'; 'aliasing_button'; 'recentering_button'; ...
    'cleanup_on_success_checkbox'};
for ii = 1:length(controls)
    field_name = controls{ii};
    if isfield(handles, field_name) && ishghandle(handles.(field_name))
        set(handles.(field_name), 'Enable', enable_value);
    end
end
handles = local_refresh_buttons(handles);

function handles = local_discard_handoff(handles, handoff)
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

function text = local_job_text(result)
if isempty(result.job_ids)
    text = sprintf('Submitted (%s).', result.outcome);
else
    text = sprintf('Submitted. Job ids: %s', sprintf('%s ', result.job_ids{:}));
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

function local_show_orchestration_error(ME, title_text)
identifier = ME.identifier;
if isempty(identifier)
    identifier = 'pseudo_CT:GuiError';
end
warndlg(sprintf(['%s\n\n%s\n\nCorrect the selected inputs or options, ', ...
    'then validate again.'], identifier, ME.message), title_text);

function value = normalize_gui_flag(value, fallback)
%NORMALIZE_GUI_FLAG Normalize profile/default values for GUIDE controls.
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
