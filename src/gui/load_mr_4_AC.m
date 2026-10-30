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
if nargin && ischar(varargin{1})
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

% Choose default command line output for load_mr_4_AC
handles.mprage_fn = 0;
handles.ute_fn = 0;
handles.umap_fn = 0;
handles.gui_mode = 'mMR';
handles.resolved_job = [];
handles.validation_request = struct();

aliasing_default = 1;
recentering_default = 0;
gui_defaults = struct();
if numel(varargin) > 1 && isstruct(varargin{2}) && isscalar(varargin{2})
    gui_defaults = varargin{2};
    if isfield(gui_defaults, 'aliasing_default')
        aliasing_default = gui_defaults.aliasing_default;
    elseif isfield(gui_defaults, 'correct_aliasing')
        aliasing_default = gui_defaults.correct_aliasing;
    end
    if isfield(gui_defaults, 'recenter_before_normalization')
        recentering_default = gui_defaults.recenter_before_normalization;
    end
end

if nargin > 3
    switch varargin{1}
        case 0
            set(handles.load_ute_edit, 'Visible', 'Off');
            set(handles.load_ute_button, 'Visible', 'Off');
            set(handles.load_mprage_button, 'String', 'Load VIBE IN');
            set(handles.load_mprage_edit, 'String', '"Load VIBE IN image"');
        case 'mMR'
            set(handles.load_ute_edit, 'Visible', 'Off');
            set(handles.load_ute_button, 'Visible', 'Off');
            set(handles.load_mprage_button, 'String', 'Load MPRAGE');
            set(handles.load_mprage_edit, 'String', '"Load MPRAGE image (dicom or nifty)"');
        case 'mprage-only'
            handles.gui_mode = 'mprage-only';
            set(handles.load_ute_edit, 'Visible', 'Off');
            set(handles.load_ute_button, 'Visible', 'Off');
            set(handles.load_umap_edit, 'Visible', 'Off');
            set(handles.load_umap_button, 'Visible', 'Off');
            set(handles.load_mprage_button, 'String', 'Load MPRAGE');
            set(handles.load_mprage_edit, 'String', '"Load MPRAGE image (dicom or nifty)"');
        otherwise
    end
end

handles.correct_aliasing = normalize_gui_flag(aliasing_default, true);
handles.recenter_before_normalization = normalize_gui_flag(recentering_default, false);
handles.validation_config = gui_defaults;
set(handles.aliasing_button, 'Value', handles.correct_aliasing);
set(handles.recentering_button, 'Value', handles.recenter_before_normalization);

% Keep the GUIDE layout and its established controls; add the separate local
% validation action alongside Cancel and label the existing accept action.
if isfield(handles, 'ok_button') && ishghandle(handles.ok_button) && ...
        isfield(handles, 'cancel_button') && ishghandle(handles.cancel_button)
    set(handles.ok_button, 'String', 'Submit Job');
    set(handles.ok_button, 'Enable', 'off');
    cancel_position = get(handles.cancel_button, 'Position');
    button_units = get(handles.cancel_button, 'Units');
    validate_width = 36;
    validate_gap = 2;
    validate_x = max(2, cancel_position(1) - validate_width - validate_gap);
    validate_position = [validate_x cancel_position(2) validate_width ...
        cancel_position(4)];
    handles.validate_configuration_button = uicontrol( ...
        'Parent', get(handles.cancel_button, 'Parent'), ...
        'Style', 'pushbutton', 'String', 'Validate Configuration', ...
        'Units', button_units, 'Position', validate_position, ...
        'Tag', 'validate_configuration_button', ...
        'Callback', @validate_configuration_button_Callback);
end

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

% Get default command line output from handles structure
varargout{1} = handles.mprage_fn;
varargout{2} = handles.ute_fn;
varargout{3} = handles.umap_fn;
varargout{4} = handles.correct_aliasing;
if nargout > 4
    varargout{5} = handles.recenter_before_normalization;
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
% hObject    handle to ok_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

handles = guidata(hObject);
if ~isfield(handles, 'resolved_job') || isempty(handles.resolved_job)
    warndlg('Validate the configuration before submitting.', ...
        'Configuration not validated');
    return;
end

submit_request = struct('resolved_job', handles.resolved_job);
credentials = struct();
try
    current_request = local_build_gui_request(handles);
catch ME
    local_show_orchestration_error(ME, 'Submission failed');
    return;
end
if ~isequal(current_request, handles.validation_request)
    handles = local_invalidate_validation(handles);
    guidata(hObject, handles);
    warndlg('Inputs or options changed. Validate the configuration again.', ...
        'Validation required');
    return;
end
if local_is_mlsc_profile(handles.resolved_job.profile)
    [password, username, group_account] = passwordEntryDialog( ...
        'enterUserName', true, 'enterGroupAccount', true, ...
        'DefaultUserName', '', 'DefaultGroupAccount', '', ...
        'CheckPasswordLength', true, 'PasswordLengthMin', 1, ...
        'PasswordLengthMax', 50, 'WindowName', 'MLSC submit login');
    if isequal(password, -1) || isempty(username)
        clear password username group_account
        return;
    end
    credentials = struct('username', username, 'password', password);
    submit_request.credentials = credentials;
    submit_request.group_account = group_account;
end

try
    report = pseudo_CT_orchestrate('submit', submit_request);
catch ME
    clear credentials password username group_account submit_request
    if strcmp(ME.identifier, 'pseudo_CT:StaleResolvedJob')
        handles = local_invalidate_validation(handles);
        guidata(hObject, handles);
    end
    local_show_orchestration_error(ME, 'Submission failed');
    return;
end
clear credentials password username group_account submit_request

if isfield(report, 'error_code') && ~isempty(report.error_code)
    local_show_submission_report(report);
    % Keep the resolved job so correcting an MLSC account does not repeat
    % input discovery or require another local validation pass.
    return;
end
if local_submission_completed(report)
    handles.mprage_fn = 0;
    handles.ute_fn = 0;
    handles.umap_fn = 0;
    guidata(hObject, handles);
    uiresume;
else
    local_show_submission_report(report);
end

function validate_configuration_button_Callback(hObject, eventdata)
%VALIDATE_CONFIGURATION_BUTTON_CALLBACK Run local-only checks without closing.
handles = guidata(hObject);
try
    request = local_build_gui_request(handles);
    validation = pseudo_CT_orchestrate('validate', request);
    handles.resolved_job = validation.resolved_job;
    handles.validation_request = request;
    set(handles.ok_button, 'Enable', 'on');
    guidata(hObject, handles);
    msgbox(local_validation_summary(validation), 'Configuration validated');
catch ME
    handles = local_invalidate_validation(handles);
    guidata(hObject, handles);
    local_show_orchestration_error(ME, 'Configuration validation failed');
end

function request = local_build_gui_request(handles)
if ~isstruct(handles) || ~isfield(handles, 'validation_config') || ...
        ~isstruct(handles.validation_config) || ...
        numel(handles.validation_config) ~= 1
    error('pseudo_CT:OrchestrationRequest', ...
        'The selected profile configuration is unavailable.');
end
mprage_fn = strtrim(get(handles.load_mprage_edit, 'String'));
request = struct();
request.config = handles.validation_config;
request.profile = local_profile_name(handles.validation_config);
request.subjects = {mprage_fn};
request.correct_aliasing = logical(get(handles.aliasing_button, 'Value'));
request.recenter_before_normalization = ...
    logical(get(handles.recentering_button, 'Value'));
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
    set(handles.ok_button, 'Enable', 'off');
end

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

function flag = local_is_mlsc_profile(profile_name)
flag = any(strcmp(profile_name, {'mlsc-current'; 'mlsc-legacy'; ...
    'mlsc-mprage-only'}));

function summary = local_validation_summary(report)
resolved = report.resolved_job;
subject = resolved.subjects(1);
summary = sprintf(['Profile: %s\nSubjects: %d\nMPRAGE: %s\n', ...
    'UMAP: %s\nCorrect aliasing: %s\nRecenter: %s\n', ...
    'Processing directory: %s\nTemporary directory: %s\n', ...
    'Save directory: %s\n\nNo authentication or remote action was performed.'], ...
    report.profile, report.subject_count, subject.mprage_fn, ...
    local_display_path(subject.umap_fn), ...
    local_on_off(resolved.options.correct_aliasing), ...
    local_on_off(resolved.options.recenter_before_normalization), ...
    subject.processing_dir, subject.temp_dir, subject.save_dir);

function text = local_display_path(value)
if isempty(value)
    text = '(none)';
else
    text = value;
end

function text = local_on_off(value)
if value
    text = 'on';
else
    text = 'off';
end

function local_show_orchestration_error(ME, title_text)
identifier = ME.identifier;
if isempty(identifier)
    identifier = 'pseudo_CT:OrchestrationError';
end
warndlg(sprintf('%s\n\n%s', identifier, ME.message), title_text);

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
    message = 'The submission did not complete. You may retry from Submit.';
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

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% --- Executes on button press in cancel_button.
function cancel_button_Callback(hObject, eventdata, handles)
% hObject    handle to cancel_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

handles.mprage_fn = 0;
handles.ute_fn = 0;
handles.umap_fn = 0;
handles.correct_aliasing = 0;
handles.recenter_before_normalization = 0;
set(handles.aliasing_button, 'Value', handles.correct_aliasing);
set(handles.recentering_button, 'Value', handles.recenter_before_normalization);

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

handles.recenter_before_normalization = logical(get(hObject,'Value'));
handles = local_invalidate_validation(handles);

% Update handles structure
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
