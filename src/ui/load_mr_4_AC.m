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

aliasing_default = 1;
recentering_default = 0;
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
set(handles.aliasing_button, 'Value', handles.correct_aliasing);
set(handles.recentering_button, 'Value', handles.recenter_before_normalization);

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

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function load_ute_edit_Callback(hObject, eventdata, handles)
% hObject    handle to load_ute_edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of load_ute_edit as text
%        str2double(get(hObject,'String')) returns contents of load_ute_edit as a double

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

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function load_umap_edit_Callback(hObject, eventdata, handles)
% hObject    handle to load_umap_edit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of load_umap_edit as text
%        str2double(get(hObject,'String')) returns contents of load_umap_edit as a double

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

handles.mprage_fn = get(handles.load_mprage_edit, 'String');
if ~isstr(handles.mprage_fn) | exist(handles.mprage_fn) ~= 2
    handles.mprage_fn = 0;
    warndlg('The MPRAGE file does not exist!!', 'Filename does NOT exist!');
else
    if strcmp(handles.gui_mode, 'mprage-only')
        handles.ute_fn = '';
        handles.umap_fn = '';
    else
        handles.ute_fn = get(handles.load_ute_edit, 'String');
        if ~isstr(handles.ute_fn) | exist(handles.ute_fn) ~= 2
            handles.ute_fn = '';
            %warndlg('The UTE_2 file does not exist!!', 'Filename does NOT exist!');
        end
        handles.umap_fn = get(handles.load_umap_edit, 'String');
        if ~isstr(handles.umap_fn) | exist(handles.umap_fn) ~= 2
            handles.umap_fn = 0;
            warndlg('The UMAP file does not exist!!', 'Filename does NOT exist!');
        end
    end
end

% Update handles structure
guidata(hObject, handles);

uiresume;

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
