function varargout = load_mr_4_AC(varargin)
% LOAD_MR_4_AC pseudoCT input window (MATLAB frontend, GUIDE layout).
%   LOAD_MR_4_AC(MODE, CONFIG, CONTEXT) opens the window for one profile.
%   MODE is 'mMR' or 'mprage-only'. CONFIG is one entry of
%   pseudo_CT_profile_choices (name, config). CONTEXT holds launcher, runtime,
%   mcr_root and root_dir (see run_pseudo_CT).
%
%   Run is the single action. It goes through the compiled launcher by way of
%   pseudo_CT_launch_request: a local profile is one launcher call (run validates
%   first and submits only when validation passes); an MLSC profile validates,
%   asks for credentials, authenticates them through the launcher (retried on a
%   rejected password or account, no submission), then submits once. The launcher call
%   is synchronous: MATLAB is busy until Run returns, and Run is disabled meanwhile.
%   Minimum supported MATLAB: R2010b.

% Edit the above text to modify the response to help load_mr_4_AC

% Begin initialization code - DO NOT EDIT
% Not singleton: a second open creates a new window. A singleton re-ran
% OpeningFcn on the existing figure and duplicated the Tag-named controls.
gui_Singleton = 0;
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
% The saved figure is hidden (Visible off). GUIDE restores that saved visibility after
% this function returns, so the window is shown in OutputFcn, which runs only when
% initialization succeeded. A failed start removes the hidden window here.
try
    handles = local_initialize(hObject, handles, varargin{:});
catch ME
    if ishghandle(hObject)
        delete(hObject);
    end
    rethrow(ME);
end

function handles = local_initialize(hObject, handles, varargin)
% Builds the window state and controls for OpeningFcn; returns the guidata handles.
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

set(handles.ok_button, 'String', 'Run', 'Enable', 'on', 'FontSize', 12);
set(handles.cancel_button, 'String', 'Close', 'FontSize', 12);
handles.cleanup_on_success_checkbox = uicontrol( ...
    'Parent', get(handles.cancel_button, 'Parent'), ...
    'Style', 'checkbox', ...
    'String', 'Remove temporary files after successful processing', ...
    'Units', 'pixels', ...
    'Position', [24 46 460 22], ...
    'FontSize', get(handles.aliasing_button, 'FontSize'), ...
    'HorizontalAlignment', get(handles.aliasing_button, ...
        'HorizontalAlignment'), ...
    'Tag', 'cleanup_on_success_checkbox', ...
    'Value', handles.cleanup_on_success, ...
    'Callback', @cleanup_on_success_checkbox_Callback);
handles.status_text = uicontrol( ...
    'Parent', get(handles.cancel_button, 'Parent'), ...
    'Style', 'text', 'String', '', 'Units', 'pixels', ...
    'Position', [24 10 200 32], 'FontSize', 10, ...
    'HorizontalAlignment', 'left', 'Tag', 'pseudo_CT_status');
handles = local_apply_control_layout(handles);
handles = local_refresh_buttons(handles);

guidata(hObject, handles);

% Window-X closes the window when no Run is in progress; during a Run it is ignored
% (see load_mr_4_AC_CloseRequestFcn).
set(hObject, 'CloseRequestFcn', @load_mr_4_AC_CloseRequestFcn);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% --- Outputs from this function are returned to the command line.
function varargout = load_mr_4_AC_OutputFcn(hObject, eventdata, handles)
% The window is not modal and returns no selection. Showing it here, after the
% saved visibility has been restored, makes the window appear once it is ready.
set(hObject, 'Visible', 'on');
varargout{1} = [];

% --- Executes when the user attempts to close the figure (window-X).
function load_mr_4_AC_CloseRequestFcn(hObject, eventdata, handles)
% While a Run is in progress the window-X request is ignored.
if ~ishghandle(hObject)
    return;
end
handles = guidata(hObject);
if isstruct(handles) && isfield(handles, 'run_in_progress') && handles.run_in_progress
    return;
end
delete(hObject);

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

% --- Executes on button press in ok_button: Run.
% For MLSC, authenticate first, then run the normal execution workflow.
% Submission is blocked if authentication or essential input checks fail.
function ok_button_Callback(hObject, eventdata, handles)
handles = guidata(hObject);
handles = local_refresh_control_handles(handles, hObject);
if handles.run_in_progress
    return;
end
handles = local_set_run_state(handles, true);
guidata(hObject, handles);
drawnow;
handoff = '';
login = struct('ok', false, 'username', '', 'password', '', 'group_account', '');
outcome = 'Run stopped: nothing was submitted.';
try
    values = local_values(handles);
    needs_credentials = local_requires_gui_credentials(handles.validation_config);
    submit = true;
    if submit && needs_credentials
        [login, outcome] = local_mlsc_login(hObject, handles, values);
        submit = login.ok;
    end
    if submit && ~ishghandle(hObject)
        submit = false;
        outcome = 'Window closed: nothing was submitted.';
    end
    if submit
        if needs_credentials
            % Fresh single-use handoff from the same in-memory credentials that just
            % authenticated; its path (not the secret) is the only value passed on.
            handoff = pseudo_CT_credentials('store', login.username, login.password);
            values.credential_handoff = handoff;
            values.group_account = login.group_account;
        end
        % One launcher call: resolve essential inputs and dispatch the run.
        handles = local_set_status(handles, 'Starting processing...');
        result = local_launcher(values, handles, 'submit');
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
login = local_clear_login(login);
handles = local_discard_handoff(handles, handoff);
handles = local_set_run_state(handles, false);
if ishghandle(hObject)
    handles = local_set_status(handles, outcome);
    guidata(hObject, handles);
end

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
%LOCAL_INVALIDATE_VALIDATION Any input or option change refreshes Run and the status.
if ~isstruct(handles)
    return;
end
handles = local_refresh_buttons(handles);

function handles = local_refresh_buttons(handles)
%LOCAL_REFRESH_BUTTONS Run enable flag and status. Run needs readable inputs (the
%   same parse Run uses) and no run in progress; pseudo_CT_gui_state supplies the flag.
fingerprint = '';
problem = '';
try
    request = pseudo_CT_launch_request('parse', ...
        pseudo_CT_gui_args(local_values(handles), handles.launch, 'validate'), ...
        handles.launch.root_dir);
    fingerprint = request.fingerprint;
catch ME
    problem = ME.message;
end
busy = isfield(handles, 'run_in_progress') && handles.run_in_progress;
state = pseudo_CT_gui_state(fingerprint, [], busy);
if isfield(handles, 'ok_button') && all(ishghandle(handles.ok_button))
    set(handles.ok_button, 'Enable', local_on_off(state.validate_enabled && ~busy));
end
if isfield(handles, 'status_text') && all(ishghandle(handles.status_text))
    if busy
        text = state.message;
    elseif isempty(fingerprint)
        text = problem;
        if isempty(text)
            text = 'Select a profile and an MPRAGE input.';
        end
    elseif local_requires_gui_credentials(handles.validation_config)
        text = 'Ready. Run asks for MLSC credentials, then starts processing.';
    else
        text = 'Ready. Run starts processing.';
    end
    set(handles.status_text, 'String', text);
end

function result = local_launcher(values, handles, action)
%LOCAL_LAUNCHER One launcher call for the window values: parse, then invoke.
args = pseudo_CT_gui_args(values, handles.launch, action);
request = pseudo_CT_launch_request('parse', args, handles.launch.root_dir);
result = pseudo_CT_launch_request('invoke', request);

function [login, outcome] = local_mlsc_login(hObject, handles, values)
%LOCAL_MLSC_LOGIN Ask for the MLSC login and authenticate it through the launcher
%   (authenticate only) until it succeeds or the user cancels. Nothing is submitted.
%   AUTHENTICATION_FAILED and INVALID_GROUP_ACCOUNT show the launcher message (no secret)
%   and re-open the dialog with the username and account pre-filled; any other error
%   code stops with that message. Each attempt's handoff is discarded at once. On
%   success LOGIN.password holds the in-memory password for the fresh submit handoff;
%   the caller clears it.
login = struct('ok', false, 'username', '', 'password', '', 'group_account', '');
outcome = 'Cancelled: nothing was submitted.';
username_default = '';
group_default = '';
failures = 0;
limit = local_auth_retry_limit();
while true
    if ~ishghandle(hObject)
        outcome = 'Window closed: nothing was submitted.';
        return;
    end
    [password, username, group_account] = pseudo_CT_password_entry_dialog( ...
        'enterUserName', true, 'enterGroupAccount', true, ...
        'DefaultUserName', username_default, 'DefaultGroupAccount', group_default, ...
        'CheckPasswordLength', true, 'PasswordLengthMin', 1, ...
        'PasswordLengthMax', 50, 'WindowName', 'MLSC login');
    if isequal(password, -1) || isempty(username)
        clear password username group_account
        return;
    end
    username_default = username;
    group_default = group_account;
    % The single-use handoff is the existing credential MAT format; its path (not the
    % secret) is the only value passed to the launcher.
    handoff = pseudo_CT_credentials('store', username, password);
    % Discards this attempt's handoff on every exit from the attempt, including a thrown
    % launcher error (the explicit discard below covers the normal path).
    cleanup_handoff = onCleanup(@() local_discard_handoff(handles, handoff)); %#ok<NASGU>
    values.credential_handoff = handoff;
    values.group_account = group_account;
    handles = local_set_status(handles, 'Checking the MLSC login...');
    result = local_launcher(values, handles, 'authenticate');
    handles = local_discard_handoff(handles, handoff);
    if result.ok && strcmp(result.authentication_status, 'authenticated') && ...
            isempty(result.error_code)
        login = struct('ok', true, 'username', username, 'password', password, ...
            'group_account', group_account);
        clear password username group_account
        outcome = 'Login accepted.';
        return;
    end
    code = local_error_code(result);
    clear password username group_account
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
    handles = local_set_status(handles, sprintf( ...
        'Login rejected (%s). Enter the credentials again or cancel.', code));
end

function limit = local_auth_retry_limit()
%LOCAL_AUTH_RETRY_LIMIT Retry limit of the GUI login loop: [] (no limit), so the user
%   retries until a login succeeds or cancels. The matching terminal setting is
%   PSEUDOCT_AUTH_RETRY_LIMIT in bin/pseudoct (empty: no limit; N: N retries after the
%   first failed attempt). The GUI sets no numeric limit of its own.
limit = [];

function login = local_clear_login(login)
%LOCAL_CLEAR_LOGIN Erase the in-memory MLSC password and login fields.
if isstruct(login)
    login.password = '';
    login.username = '';
    login.group_account = '';
end

function handles = local_set_status(handles, text)
%LOCAL_SET_STATUS Show one status line now (MATLAB is busy during launcher calls).
if isfield(handles, 'status_text') && all(ishghandle(handles.status_text))
    set(handles.status_text, 'String', text);
    drawnow;
end

function code = local_error_code(result)
code = result.error_code;
if isempty(code)
    code = 'LAUNCHER_FAILED';
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
    if ~isfield(handles, name) || isempty(handles.(name)) || ~all(ishghandle(handles.(name)))
        handles.(name) = figure_handles.(name);
    end
end
required = {'load_mprage_edit'; 'load_mprage_button'; ...
    'load_ute_edit'; 'load_ute_button'; 'load_umap_edit'; ...
    'load_umap_button'; 'aliasing_button'; 'recentering_button'; ...
    'ok_button'; 'cancel_button'; 'processing_options_heading'};
for ii = 1:length(required)
    name = required{ii};
    if ~isfield(handles, name) || isempty(handles.(name)) || ~all(ishghandle(handles.(name)))
        error('pseudo_CT:GuiControlMissing', ...
        'The GUIDE control Tag "%s" is missing; check load_mr_4_AC.fig.', ...
        name);
    end
end

function handles = local_apply_control_layout(handles)
% Use pixel coordinates for both the window and every child control. Static text
% and checkboxes take the figure colour, so no grey strip shows behind them.
fig_color = get(get(handles.cancel_button, 'Parent'), 'Color');
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
if isfield(handles, 'text1') && all(ishghandle(handles.text1))
    set(handles.text1, 'Units', 'pixels');
    set(handles.text1, 'Position', [24 422 732 28], 'BackgroundColor', fig_color);
end
set(handles.processing_options_heading, 'Units', 'pixels');
set(handles.processing_options_heading, 'String', 'Processing options', ...
    'Position', [24 heading_y 732 24], 'FontSize', 12, ...
    'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
    'BackgroundColor', fig_color);
option_names = {'aliasing_button'; 'recentering_button'; ...
    'cleanup_on_success_checkbox'};
for ii = 1:3
    set(handles.(option_names{ii}), 'Units', 'pixels', 'Style', 'checkbox');
    set(handles.(option_names{ii}), 'Position', [24 option_y(ii) 460 22]);
    set(handles.(option_names{ii}), 'FontSize', 11, 'HorizontalAlignment', 'left', ...
        'BackgroundColor', fig_color);
end
set(handles.ok_button, 'Units', 'pixels', 'String', 'Run', ...
    'Position', [590 10 166 32], 'FontSize', 12);
set(handles.cancel_button, 'Units', 'pixels', 'Position', [414 10 150 32], 'FontSize', 12);
set(handles.status_text, 'Units', 'pixels', 'Position', [24 10 380 32], ...
    'FontSize', 10, 'BackgroundColor', fig_color);

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
    'cleanup_on_success_checkbox'; 'cancel_button'};
for ii = 1:length(controls)
    field_name = controls{ii};
    if isfield(handles, field_name) && all(ishghandle(handles.(field_name)))
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
    'then press Run again.'], identifier, ME.message), title_text);

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
