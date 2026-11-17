function selected = pseudo_CT_select_file(prompt, kind, start_dir)
%PSEUDO_CT_SELECT_FILE One file or folder chosen by the user; '' when cancelled.
%   SELECTED = PSEUDO_CT_SELECT_FILE(PROMPT) selects one file.
%   SELECTED = PSEUDO_CT_SELECT_FILE(PROMPT, KIND, START_DIR) selects one 'file' or one
%   'dir' (folder, for a DICOM series directory), starting in START_DIR when it exists.
%   Uses the standard MATLAB dialogs uigetfile and uigetdir (R2010b to current releases).
%   Any file can be chosen (NIfTI, or a DICOM file without an extension); the launcher
%   checks the choice. Minimum supported MATLAB: R2010b.

if nargin < 2 || isempty(kind)
    kind = 'file';
end
if nargin < 3 || ~ischar(start_dir) || exist(start_dir, 'dir') ~= 7
    start_dir = pwd;
end
selected = '';
switch kind
    case 'file'
        [name, folder] = uigetfile({'*', 'All files (NIfTI or DICOM)'}, prompt, ...
            [start_dir filesep]);
        if ~isequal(name, 0) && ~isequal(folder, 0)
            selected = fullfile(folder, name);
        end
    case 'dir'
        folder = uigetdir(start_dir, prompt);
        if ~isequal(folder, 0)
            selected = folder;
        end
    otherwise
        error('pseudo_CT:FrontendUsage', 'The selection kind must be file or dir.');
end
end
