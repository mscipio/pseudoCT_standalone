function varargout = load_mr_4_AC(varargin)
% LOAD_MR_4_AC MATLAB code for load_mr_4_AC.fig
%      LOAD_MR_4_AC, by itself, creates a new LOAD_MR_4_AC or raises the existing
%      singleton*.
%
%      H = LOAD_MR_4_AC returns the handle to a new LOAD_MR_4_AC or the handle to
%      the existing singleton*.
%
%      LOAD_MR_4_AC('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in LOAD_MR_4_AC.M with the given input arguments.
%
%      LOAD_MR_4_AC('Property','Value',...) creates a new LOAD_MR_4_AC or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before load_mr_4_AC_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to load_mr_4_AC_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

% Edit the above text to modify the response to help load_mr_4_AC

% Last Modified by GUIDE v2.5 18-Sep-2014 12:34:23

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
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to load_mr_4_AC (see VARARGIN)

% The saved GUIDE figure can retain stale dimensions. Establish the window
% geometry in pixels before positioning any controls, independent of the
% Units stored in the .fig file or the MATLAB release's character metrics.
screen_size = get(0, 'ScreenSize');
figure_position = [max(1, floor((screen_size(3) - 780) / 2)), ...
    max(1, floor((screen_size(4) - 460) / 2)), 780, 460];
set(hObject, 'Units', 'pixels');
set(hObject, 'Position', figure_position);

handles = local_refresh_control_handles(handles, hObject);

% Choose default command line output for load_mr_4_AC
handles.mprage_fn = 0;
handles.ute_fn = 0;
handles.umap_fn = 0;
handles.gui_mode = 'mMR';
handles.resolved_job = [];
handles.validation_request = struct();
handles.run_in_progress = false;
handles.gui_handoff = struct('credentials', struct(), 'group_account', '');

aliasing_default = 1;
recentering_default = 0;
cleanup_default = true;
gui_defaults = struct();
gui_mode_argument = false;
if ~isempty(varargin)
    if ischar(varargin{1})
        gui_mode_argument = any(strcmp(varargin{1}, {'mMR'; 'mprage-only'}));
    elseif isnumeric(varargin{1}) && isscalar(varargin{1}) && varargin{1} == 0
        gui_mode_argument = true;
    end
end
if gui_mode_argument && numel(varargin) > 1
    if ~isstruct(varargin{2}) || ~isscalar(varargin{2}) || ...
            isempty(fieldnames(varargin{2}))
        error('pseudo_CT:InvalidProfile', ...
            'The GUI was given an invalid profile configuration.');
    end
    gui_defaults = varargin{2};
    if isfield(gui_defaults, 'aliasing_default')
        aliasing_default = gui_defaults.aliasing_default;
    elseif isfield(gui_defaults, 'correct_aliasing')
        aliasing_default = gui_defaults.correct_aliasing;
    end
    if isfield(gui_defaults, 'recenter_before_normalization')
        recentering_default = gui_defaults.recenter_before_normalization;
    end
    if isfield(gui_defaults, 'cleanup_on_success')
        cleanup_default = gui_defaults.cleanup_on_success;
    end
else
    gui_defaults = local_default_gui_profile();
    if gui_mode_argument && (~ischar(varargin{1}) || ...
            ~strcmp(varargin{1}, gui_defaults.io_policy.gui))
        error('pseudo_CT:InvalidProfile', ...
            'A matching profile configuration is required for this GUI mode.');
    end
end

if nargin > 3
    switch varargin{1}
        case 0
            set(handles.load_ute_edit, 'Visible', 'Off');
            set(handles.load_ute_button, 'Visible', 'Off');
            set(handles.load_mprage_button, 'String', 'Browse VIBE IN...');
            set(handles.load_mprage_edit, 'String', 'Load VIBE IN image');
        case 'mMR'
            set(handles.load_ute_edit, 'Visible', 'Off');
            set(handles.load_ute_button, 'Visible', 'Off');
            set(handles.load_mprage_button, 'String', 'Browse MPRAGE...');
            set(handles.load_mprage_edit, 'String', 'Load MPRAGE image (dicom or nifty)');
        case 'mprage-only'
            handles.gui_mode = 'mprage-only';
            set(handles.load_ute_edit, 'Visible', 'Off');
            set(handles.load_ute_button, 'Visible', 'Off');
            set(handles.load_umap_edit, 'Visible', 'Off');
            set(handles.load_umap_button, 'Visible', 'Off');
            set(handles.load_mprage_button, 'String', 'Browse MPRAGE...');
            set(handles.load_mprage_edit, 'String', 'Load MPRAGE image (dicom or nifty)');
        otherwise
    end
end

handles.correct_aliasing = normalize_gui_flag(aliasing_default, true);
handles.recenter_before_normalization = normalize_gui_flag(recentering_default, false);
handles.cleanup_on_success = normalize_gui_flag(cleanup_default, true);
handles.validation_config = gui_defaults;
setappdata(hObject, 'pseudo_CT_validation_config', gui_defaults);
set(handles.aliasing_button, 'Value', handles.correct_aliasing);
set(handles.recentering_button, 'Value', handles.recenter_before_normalization);

% Keep the GUIDE layout and its established controls. Validation and submit
% remain separate orchestrator operations behind this single GUI action.
set(handles.ok_button, 'String', 'Run pseudoCT', 'Enable', 'on', ...
    'FontSize', 12);
set(handles.cancel_button, 'FontSize', 12);
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
handles = local_apply_control_layout(handles);

% Update handles structure
guidata(hObject, handles);

% X-close (window-X) before or after partial selection is explicit cancel:
% route through CloseRequestFcn so zero defaults are restored and uiwait is
% resumed instead of destroying the figure while uiwait is pending.
set(hObject, 'CloseRequestFcn', @load_mr_4_AC_CloseRequestFcn);

% UIWAIT makes load_mr_4_AC wait for user response (see UIRESUME)
uiwait(handles.load_mr_4_AC);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% --- Outputs from this function are returned to the command line.
function varargout = load_mr_4_AC_OutputFcn(hObject, eventdata, handles)
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% X-close before selection deletes the figure while uiwait is pending, so
% handles may arrive as a non-struct (historical 'Dot indexing not
% supported for double' at handles.mprage_fn). Treat any non-struct or
% incomplete handles as explicit cancel with zero defaults so collect_jobs
% returns empty jobs and run_pseudo_CT exits cleanly with no jobs started.
if ~isstruct(handles)
    try
        handles = guidata(hObject);
    catch
        handles = struct();
    end
end
if ~isstruct(handles)
    handles = struct('mprage_fn', 0, 'ute_fn', 0, 'umap_fn', 0, ...
        'correct_aliasing', 0, 'recenter_before_normalization', 0);
end
if ~isfield(handles, 'mprage_fn')
    handles.mprage_fn = 0;
end
if ~isfield(handles, 'ute_fn')
    handles.ute_fn = 0;
end
if ~isfield(handles, 'umap_fn')
    handles.umap_fn = 0;
end
if ~isfield(handles, 'correct_aliasing')
    handles.correct_aliasing = 0;
end
if ~isfield(handles, 'recenter_before_normalization')
    handles.recenter_before_normalization = 0;
end
if ~isfield(handles, 'cleanup_on_success')
    handles.cleanup_on_success = 0;
end
if ~isfield(handles, 'gui_handoff') || ~isstruct(handles.gui_handoff)
    handles.gui_handoff = struct('credentials', struct(), ...
        'group_account', '');
end

% Get default command line output from handles structure
varargout{1} = handles.mprage_fn;
varargout{2} = handles.ute_fn;
varargout{3} = handles.umap_fn;
varargout{4} = handles.correct_aliasing;
if nargout > 4
    varargout{5} = handles.recenter_before_normalization;
end
if nargout > 5
    varargout{6} = handles.cleanup_on_success;
end
if nargout > 6
    varargout{7} = handles.gui_handoff;
end

if isfield(handles, 'load_mr_4_AC') && ishghandle(handles.load_mr_4_AC)
    delete(handles.load_mr_4_AC);
elseif ishghandle(hObject)
    delete(hObject);
end

% --- Executes when the user attempts to close the figure (window-X).
function load_mr_4_AC_CloseRequestFcn(hObject, eventdata, handles)
% LOAD_MR_4_AC_CLOSEREQUESTFCN X-close is explicit cancel: restore zero
% defaults and resume so OutputFcn returns the empty-cancel contract.
% R2010b GUIDE API only: guidata/uiresume/ishghandle.
if nargin < 3
    handles = struct();
end
if ~isstruct(handles)
    handles = struct();
end
try
    stored = guidata(hObject);
    if isstruct(stored)
        handles = stored;
    end
catch
end
handles.mprage_fn = 0;
handles.ute_fn = 0;
handles.umap_fn = 0;
handles.correct_aliasing = 0;
handles.recenter_before_normalization = 0;
handles.cleanup_on_success = 0;
handles.gui_handoff = struct('credentials', struct(), 'group_account', '');
if ishghandle(hObject)
    if strcmp(get(hObject, 'waitstatus'), 'waiting')
        try
            guidata(hObject, handles);
        catch
        end
        uiresume(hObject);
    else
        delete(hObject);
    end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% --- Executes on button press in load_mprage_button.
function load_mprage_button_Callback(hObject, eventdata, handles)
% hObject    handle to load_mprage_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

handles = local_refresh_control_handles(handles, hObject);
P = spm_select(1, '*', 'Select the MPRAGE file to use to obtain an atlas-based attenuation map (It could be a Dicom)');
if size(P, 1) == 0
    set(handles.load_mprage_edit, 'String', 'Load only 1 filename ... ');
    handles = local_invalidate_validation(handles);
    guidata(hObject, handles);
    warndlg('Load only 1 filename (even if there are many Dicoms!!)', 'Load only 1 filename');
    return;
end

if exist(P) ~= 2
    warndlg('The input should be a valid filename!', 'Error in filename!');
    set(hObject, 'String', 'Input a valid filename ... ');
    return;
end

handles.mprage_fn = P;
set(handles.load_mprage_edit, 'String', handles.mprage_fn);
if strcmp(handles.gui_mode, 'mprage-only')
    handles.ute_fn = '';
    handles.umap_fn = '';
else
    [handles.ute_fn, handles.umap_fn] = pseudo_CT_discover_ute_umap(P);
    if isstr(handles.ute_fn)
        set(handles.load_ute_edit, 'String', handles.ute_fn);
    else
        %set(handles.load_ute_edit, 'String', 'No UTE_2 filename found!! Find your UTE_2 file!');
    end
    if isstr(handles.umap_fn)
        set(handles.load_umap_edit, 'String', handles.umap_fn);
    else
        set(handles.load_umap_edit, 'String', 'No UMAP filename found!! Find your UMAP file!');
    end
end
handles = local_invalidate_validation(handles);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function load_mprage_edit_Callback(hObject, eventdata, handles)
% hObject    handle to load_mprage_edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of load_mprage_edit as text
%        str2double(get(hObject,'String')) returns contents of load_mprage_edit as a double

handles = local_refresh_control_handles(handles, hObject);
fn = get(hObject, 'String');
handles = local_invalidate_validation(handles);
guidata(hObject, handles);
if ~ischar(fn) | exist(fn) ~= 2
    warndlg('The input should be a valid filename!', 'Error in filename!');
    set(hObject, 'String', 'Input a valid filename ... ');
    return;
end

handles.mprage_fn = fn;
if strcmp(handles.gui_mode, 'mprage-only')
    handles.ute_fn = '';
    handles.umap_fn = '';
else
    [handles.ute_fn, handles.umap_fn] = pseudo_CT_discover_ute_umap(fn);
    if isstr(handles.ute_fn)
        set(handles.load_ute_edit, 'String', handles.ute_fn);
    else
        set(handles.load_ute_edit, 'String', 'No UTE_2 filename found!! Find your UTE_2 file!');
    end
    if isstr(handles.umap_fn)
        set(handles.load_umap_edit, 'String', handles.umap_fn);
    else
        set(handles.load_umap_edit, 'String', 'No UMAP filename found!! Find your UMAP file!');
    end
end
handles = local_invalidate_validation(handles);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% --- Executes during object creation, after setting all properties.
function load_mprage_edit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to load_mprage_edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% --- Executes on button press in load_ute_button.
function load_ute_button_Callback(hObject, eventdata, handles)
% hObject    handle to load_ute_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

handles = local_refresh_control_handles(handles, hObject);
P = spm_select(1, '*', 'Select the UTE_2 file to use to obtain an atlas-based attenuation map (It could be a Dicom)');
if size(P, 1) == 0
    set(handles.load_ute_edit, 'String', 'Load only 1 filename ... ');
    handles = local_invalidate_validation(handles);
    guidata(hObject, handles);
    warndlg('Load only 1 filename (even if there are many Dicoms!!)', 'Load only 1 filename');
    return;
end

if exist(P) ~= 2 & length(P) > 0
    warndlg('The input should be a valid filename!', 'Error in filename!');
    set(hObject, 'String', 'Input a valid filename ... ');
    return;
end

handles.ute_fn = P;
set(handles.load_ute_edit, 'String', handles.ute_fn);
handles = local_invalidate_validation(handles);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function load_ute_edit_Callback(hObject, eventdata, handles)
% hObject    handle to load_ute_edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of load_ute_edit as text
%        str2double(get(hObject,'String')) returns contents of load_ute_edit as a double

handles = local_refresh_control_handles(handles, hObject);
handles.ute_fn = strtrim(get(hObject, 'String'));
handles = local_invalidate_validation(handles);
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% --- Executes during object creation, after setting all properties.
function load_ute_edit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to load_ute_edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% --- Executes on button press in load_umap_button.
function load_umap_button_Callback(hObject, eventdata, handles)
% hObject    handle to load_umap_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

handles = local_refresh_control_handles(handles, hObject);
P = spm_select(1, '*', 'Select the UMAP file to use to obtain an atlas-based attenuation map (It could be a Dicom)');
if size(P, 1) == 0
    set(handles.load_umap_edit, 'String', 'Load only 1 filename ... ');
    handles = local_invalidate_validation(handles);
    guidata(hObject, handles);
    warndlg('Load only 1 filename (even if there are many Dicoms!!)', 'Load only 1 filename');
    return;
end

if exist(P) ~= 2
    warndlg('The input should be a valid filename!', 'Error in filename!');
    set(hObject, 'String', 'Input a valid filename ... ');
    return;
end

handles.umap_fn = P;
set(handles.load_umap_edit, 'String', handles.umap_fn);
handles = local_invalidate_validation(handles);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function load_umap_edit_Callback(hObject, eventdata, handles)
% hObject    handle to load_umap_edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of load_umap_edit as text
%        str2double(get(hObject,'String')) returns contents of load_umap_edit as a double

handles = local_refresh_control_handles(handles, hObject);
handles.umap_fn = strtrim(get(hObject, 'String'));
handles = local_invalidate_validation(handles);
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% --- Executes during object creation, after setting all properties.
function load_umap_edit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to load_umap_edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% --- Executes on button press in ok_button.
function ok_button_Callback(hObject, eventdata, handles)
% Validate locally, hand off the selection/credentials, then return to the
% existing lifecycle so it dispatches exactly once after this window closes.
handles = guidata(hObject);
handles = local_refresh_control_handles(handles, hObject);
if isfield(handles, 'run_in_progress') && handles.run_in_progress
    return;
end
handles = local_set_run_state(handles, true);
guidata(hObject, handles);
drawnow;

password = '';
username = '';
group_account = '';
credentials = struct();
try
    validation_request = local_build_gui_request(handles);
    validation = pseudo_CT_orchestrate('validate', validation_request);
    if ~isstruct(validation) || ~isfield(validation, 'ok') || ...
            ~isequal(validation.ok, true)
        error('pseudo_CT:ValidationFailed', ...
            'Local validation did not approve the selected inputs and options.');
    end
catch ME
    handles = local_finish_run(guidata(hObject));
    guidata(hObject, handles);
    local_show_orchestration_error(ME, 'Run validation failed');
    return;
end

handles.resolved_job = validation.resolved_job;
handles.validation_request = validation_request;
guidata(hObject, handles);
if local_requires_gui_credentials(validation_request.config)
    try
        [password, username, group_account] = passwordEntryDialog( ...
            'enterUserName', true, 'enterGroupAccount', true, ...
            'DefaultUserName', '', 'DefaultGroupAccount', '', ...
            'CheckPasswordLength', true, 'PasswordLengthMin', 1, ...
            'PasswordLengthMax', 50, 'WindowName', 'MLSC submit login');
    catch ME
        handles = local_finish_run(guidata(hObject));
        guidata(hObject, handles);
        local_show_orchestration_error(ME, 'Authentication was not completed');
        return;
    end
    if isequal(password, -1) || isempty(username)
        clear password username group_account
        handles = local_finish_run(guidata(hObject));
        guidata(hObject, handles);
        return;
    end
    credentials = struct('username', username, 'password', password);
end

handles.gui_handoff = struct('credentials', credentials, ...
    'group_account', group_account);
handles.mprage_fn = validation_request.subjects{1};
handles.ute_fn = strtrim(get(handles.load_ute_edit, 'String'));
if isfield(handles, 'gui_mode') && strcmp(handles.gui_mode, 'mprage-only')
    handles.umap_fn = '';
else
    handles.umap_fn = validation_request.umap_files{1};
end
handles.correct_aliasing = validation_request.correct_aliasing;
handles.recenter_before_normalization = ...
    validation_request.recenter_before_normalization;
handles.cleanup_on_success = validation_request.cleanup_on_success;
guidata(hObject, handles);
clear credentials password username group_account
figure_handle = ancestor(hObject, 'figure');
if ~isempty(figure_handle) && ishghandle(figure_handle)
    set(figure_handle, 'Visible', 'off');
    uiresume(figure_handle);
end

function request = local_build_gui_request(handles)
config = [];
if isstruct(handles) && isfield(handles, 'validation_config')
    config = handles.validation_config;
elseif isstruct(handles) && isfield(handles, 'load_mprage_edit') && ...
        ishghandle(handles.load_mprage_edit)
    figure_handle = ancestor(handles.load_mprage_edit, 'figure');
    if ~isempty(figure_handle) && ishghandle(figure_handle) && ...
            isappdata(figure_handle, 'pseudo_CT_validation_config')
        config = getappdata(figure_handle, 'pseudo_CT_validation_config');
    end
end
if ~isstruct(config) || numel(config) ~= 1 || isempty(fieldnames(config))
    error('pseudo_CT:OrchestrationRequest', ...
        'The selected profile configuration is unavailable.');
end
mprage_fn = strtrim(get(handles.load_mprage_edit, 'String'));
request = struct();
request.config = config;
request.profile = local_profile_name(config);
request.subjects = {mprage_fn};
request.correct_aliasing = logical(get(handles.aliasing_button, 'Value'));
request.recenter_before_normalization = ...
    logical(get(handles.recentering_button, 'Value'));
request.cleanup_on_success = ...
    logical(get(handles.cleanup_on_success_checkbox, 'Value'));
if isfield(handles, 'gui_mode') && strcmp(handles.gui_mode, 'mprage-only')
    request.umap_files = {''};
else
    umap_fn = strtrim(get(handles.load_umap_edit, 'String'));
    if ~isempty(strfind(lower(umap_fn), 'no umap filename found')) || ...
            ~isempty(strfind(lower(umap_fn), 'load umap'))
        umap_fn = '';
    end
    request.umap_files = {umap_fn};
end

function handles = local_invalidate_validation(handles)
if ~isstruct(handles)
    return;
end
handles.resolved_job = [];
handles.validation_request = struct();
if isfield(handles, 'ok_button') && ishghandle(handles.ok_button)
    run_active = isfield(handles, 'run_in_progress') && ...
        handles.run_in_progress;
    if run_active
        set(handles.ok_button, 'Enable', 'off');
    else
        set(handles.ok_button, 'Enable', 'on');
    end
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
% Use pixel coordinates for both the window and every child control. MATLAB
% character units vary with release, display scaling, and platform fonts.
input_button_positions = [24 370 170 34; 24 286 170 34; 24 202 170 34];
input_field_positions = [24 332 732 30; 24 248 732 30; 24 164 732 30];
option_y = [98 72 46];
heading_y = 126;
if isfield(handles, 'gui_mode') && strcmp(handles.gui_mode, 'mprage-only')
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
set(handles.load_mprage_edit, 'FontSize', 11, ...
    'HorizontalAlignment', 'left');
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
    set(handles.(option_names{ii}), ...
        'Position', [24 option_y(ii) 732 22]);
    set(handles.(option_names{ii}), 'FontSize', 11, ...
        'HorizontalAlignment', 'left');
end
set(handles.ok_button, 'Units', 'pixels');
set(handles.ok_button, 'String', 'Run pseudoCT', ...
    'Position', [590 10 166 32], 'FontSize', 12);
set(handles.cancel_button, 'Units', 'pixels');
set(handles.cancel_button, 'Position', [414 10 150 32], 'FontSize', 12);

function profile_name = local_profile_name(config)
if ~isstruct(config) || ~isfield(config, 'presentation') || ...
        ~isstruct(config.presentation) || ...
        ~isfield(config.presentation, 'display_name') || ...
        ~ischar(config.presentation.display_name)
    error('pseudo_CT:InvalidProfile', ...
        'The selected profile identity is unavailable.');
end
gui_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(fileparts(gui_dir));
profiles = pseudo_CT_list_profiles(fullfile(root_dir, 'src', 'config'), true);
matches = [];
for ii = 1:length(profiles)
    if strcmp(profiles(ii).display_name, config.presentation.display_name)
        matches(end + 1) = ii; %#ok<AGROW>
    end
end
if length(matches) ~= 1
    error('pseudo_CT:InvalidProfile', ...
        'The selected profile identity is ambiguous or unavailable.');
end
profile_name = profiles(matches).name;

function flag = local_requires_gui_credentials(config)
flag = isstruct(config) && isfield(config, 'mode') && ...
    ischar(config.mode) && strcmp(config.mode, 'mlsc');

function handles = local_finish_run(handles)
if ~isstruct(handles)
    return;
end
handles = local_set_run_state(handles, false);

function handles = local_set_run_state(handles, running)
handles.run_in_progress = logical(running);
enable_value = 'on';
if running
    enable_value = 'off';
end
controls = {'load_mprage_button'; 'load_mprage_edit'; ...
    'load_ute_button'; 'load_ute_edit'; 'load_umap_button'; ...
    'load_umap_edit'; 'aliasing_button'; 'recentering_button'; ...
    'cleanup_on_success_checkbox'; 'cancel_button'; 'ok_button'};
for ii = 1:length(controls)
    field_name = controls{ii};
    if isfield(handles, field_name) && ishghandle(handles.(field_name))
        set(handles.(field_name), 'Enable', enable_value);
    end
end

function local_show_orchestration_error(ME, title_text)
identifier = ME.identifier;
if isempty(identifier)
    identifier = 'pseudo_CT:OrchestrationError';
end
warndlg(sprintf(['%s\n\n%s\n\nCorrect the selected inputs or options, ', ...
    'then click Run pseudoCT again.'], identifier, ME.message), title_text);

function local_show_submission_report(report)
code = '';
message = '';
if isfield(report, 'error_code')
    code = report.error_code;
end
if isfield(report, 'error_message')
    message = report.error_message;
end
if isempty(message)
    message = 'The submission did not complete. Correct the reported issue and retry.';
end
if isempty(code)
    code = 'SUBMISSION_FAILED';
end
warndlg(sprintf('%s\n\n%s', code, message), 'Submission failed');

function flag = local_submission_completed(report)
flag = false;
if isfield(report, 'submission_status') && ...
        strcmp(report.submission_status, 'accepted')
    flag = true;
elseif isfield(report, 'completion_status') && ...
        strcmp(report.completion_status, 'completed')
    flag = true;
end

function config = local_default_gui_profile()
gui_dir = fileparts(mfilename('fullpath'));
repo_root = fileparts(fileparts(gui_dir));
config_root = fullfile(repo_root, 'src', 'config');
addpath(config_root, '-begin');
profiles = pseudo_CT_list_profiles(config_root, true);
[profiles, default_index] = pseudo_CT_prepare_profile_choices(profiles);
if isempty(default_index) || default_index < 1 || ...
        default_index > length(profiles)
    error('pseudo_CT:NoProfiles', ...
        'No valid default execution profile is available for the GUI.');
end
config = pseudo_CT_load_profile(profiles(default_index).name, config_root);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% --- Executes on button press in cancel_button.
function cancel_button_Callback(hObject, eventdata, handles)
% hObject    handle to cancel_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

handles = local_refresh_control_handles(handles, hObject);
handles.mprage_fn = 0;
handles.ute_fn = 0;
handles.umap_fn = 0;
handles.correct_aliasing = 0;
handles.recenter_before_normalization = 0;
handles.cleanup_on_success = 0;
handles.gui_handoff = struct('credentials', struct(), 'group_account', '');
set(handles.aliasing_button, 'Value', handles.correct_aliasing);
set(handles.recentering_button, 'Value', handles.recenter_before_normalization);
if isfield(handles, 'cleanup_on_success_checkbox') && ...
        ishghandle(handles.cleanup_on_success_checkbox)
    set(handles.cleanup_on_success_checkbox, 'Value', ...
        handles.cleanup_on_success);
end

% Update handles structure
guidata(hObject, handles);

uiresume;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% --- Executes on button press in aliasing_button.
function aliasing_button_Callback(hObject, eventdata, handles)
% hObject    handle to aliasing_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of aliasing_button

handles = local_refresh_control_handles(handles, hObject);
handles.correct_aliasing = logical(get(hObject,'Value'));
handles = local_invalidate_validation(handles);

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% --- Executes on button press in recentering_button.
function recentering_button_Callback(hObject, eventdata, handles)
% hObject    handle to recentering_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of recentering_button

handles = local_refresh_control_handles(handles, hObject);
handles.recenter_before_normalization = logical(get(hObject,'Value'));
handles = local_invalidate_validation(handles);

% Update handles structure
guidata(hObject, handles);

function cleanup_on_success_checkbox_Callback(hObject, eventdata, handles)
if nargin < 3 || ~isstruct(handles)
    handles = guidata(hObject);
end
handles = local_refresh_control_handles(handles, hObject);
handles.cleanup_on_success = logical(get(hObject, 'Value'));
handles = local_invalidate_validation(handles);
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


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
