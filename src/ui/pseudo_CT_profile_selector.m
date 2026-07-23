function profile = pseudo_CT_profile_selector()
%PSEUDO_CT_PROFILE_SELECTOR Show profile selection dialog.
%   PROFILE = PSEUDO_CT_PROFILE_SELECTOR() displays a listdlg with the
%   three canonical execution profiles and their descriptions. Returns one
%   of:
%       'local-current'
%       'local-near-parity-r2010b'
%       'launchpad'
%   or returns an empty string if the user cancels the dialog.
%
%   When 'local-near-parity-r2010b' is selected on a MATLAB release other
%   than R2010b (7.11), a warning dialog is shown explaining that results
%   may differ from the expected near-parity output. Execution is not
%   blocked.
%
%   Minimum supported MATLAB: R2010b (compatible with listdlg).

profiles = {
    'local-current'
    'local-near-parity-r2010b'
    'launchpad'
};

descriptions = {
    ['Local MATLAB/SPM pipeline using the system-installed MATLAB ' ...
     'version and compiled MEX dependencies. Recommended default.']
    ['Local pipeline pinned to near-R2010b (7.11) numerical parity ' ...
     'for consistent optimizer results across MATLAB versions.']
    ['Legacy compiled Launchpad backend via SSH. Intended for ' ...
     'subjects requiring the original cluster runtime environment.']
};

list_str = cell(size(profiles));
for ii = 1:numel(profiles)
    list_str{ii} = sprintf('%s  \u2014  %s', profiles{ii}, descriptions{ii});
end

[selection, ok] = listdlg( ...
    'PromptString', 'Select pseudo-CT execution profile:', ...
    'SelectionMode', 'single', ...
    'ListString', list_str, ...
    'ListSize', [640 150], ...
    'Name', 'Pseudo-CT Profile');

if ~ok || isempty(selection)
    profile = '';
    return;
end

profile = profiles{selection};

% Warn if near-parity profile selected on non-R2010b MATLAB
if strcmp(profile, 'local-near-parity-r2010b')
    v = ver('MATLAB');
    if ~isempty(v)
        release = v.Release;  % e.g., '(R2023b)'
        if isempty(strfind(lower(release), 'r2010b'))
            warndlg(sprintf( ...
                ['You selected the "local-near-parity-r2010b" profile, ' ...
                 'but you are running MATLAB %s.\n\n' ...
                 'This profile is intended for R2010b (7.11) to ensure ' ...
                 'numerical parity with the legacy cluster runtime.\n\n' ...
                 'Results on this MATLAB version MAY differ from the ' ...
                 'expected near-parity output.'], release), ...
                'MATLAB Version Warning');
        end
    end
end

end
