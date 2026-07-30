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

handles.correct_aliasing = 1;
set(handles.aliasing_button, 'Value', handles.correct_aliasing);

% Update handles structure
guidata(hObject, handles);

% UIWAIT makes load_mr_4_AC wait for user response (see UIRESUME)
uiwait(handles.load_mr_4_AC);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% --- Outputs from this function are returned to the command line.
function varargout = load_mr_4_AC_OutputFcn(hObject, eventdata, handles) 
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
varargout{1} = handles.mprage_fn;
varargout{2} = handles.ute_fn;
varargout{3} = handles.umap_fn;
varargout{4} = handles.correct_aliasing;

delete(handles.load_mr_4_AC);

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

handles.correct_aliasing = get(hObject,'Value');

% Update handles structure
guidata(hObject, handles);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
