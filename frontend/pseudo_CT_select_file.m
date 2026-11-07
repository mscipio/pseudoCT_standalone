function selected = pseudo_CT_select_file(prompt)
%PSEUDO_CT_SELECT_FILE One file chosen by the user; '' when cancelled.
%   Uses SPM's file selector when SPM is on the path (the original GUI
%   control); otherwise the MATLAB file dialog, so an installed distribution
%   without SPM still lets the user browse. Minimum supported MATLAB: R2010b.

if exist('spm_select', 'file') == 2
    selected = spm_select(1, '*', prompt);
else
    [name, folder] = uigetfile('*', prompt);
    if isequal(name, 0)
        selected = '';
    else
        selected = fullfile(folder, name);
    end
end
end
