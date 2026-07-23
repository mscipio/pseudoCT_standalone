function profile = pseudo_CT_profile_selector()
%PSEUDO_CT_PROFILE_SELECTOR Show profile selection dialog.
%   PROFILE = PSEUDO_CT_PROFILE_SELECTOR() scans the spm_profiles/
%   directory for all .m configuration files and presents them in a
%   listdlg selection dialog. Each profile's H1 description line is
%   shown alongside its canonical name.
%
%   Returns the selected profile name (e.g. 'local-current'), or an empty
%   string if the user cancels the dialog.
%
%   When a profile with near-parity in its name is selected on a MATLAB
%   release other than R2010b (7.11), a warning dialog is shown explaining
%   that results may differ from the expected near-parity output.
%   Execution is not blocked.
%
%   Minimum supported MATLAB: R2010b (compatible with listdlg).

% Discover profiles by scanning the spm_profiles directory
profile_dir = fullfile(fileparts(mfilename('fullpath')), '..', 'config', ...
    'spm_profiles');
profiles = discover_profiles(profile_dir);

if isempty(profiles)
    error('PSEUDO_CT:NoProfiles', ...
        'No profile configuration files found in %s', profile_dir);
end

% Build display list: canonical name -- first-line description
num_profiles = size(profiles, 1);
list_str = cell(num_profiles, 1);
for ii = 1:num_profiles
    canonical = profiles{ii, 1};
    desc = read_h1_description(profile_dir, profiles{ii, 2});
    if isempty(desc)
        list_str{ii} = canonical;
    else
        list_str{ii} = sprintf('%s -- %s', canonical, desc);
    end
end

canonical_names = profiles(:, 1);

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

profile = canonical_names{selection};

% Warn if near-parity profile selected on non-R2010b MATLAB
if ~isempty(strfind(lower(profile), 'near-parity'))
    v = ver('MATLAB');
    if ~isempty(v)
        release = v.Release;  % e.g., '(R2023b)'
        if isempty(strfind(lower(release), 'r2010b'))
            warndlg(sprintf( ...
                ['You selected the "%s" profile, ' ...
                 'but you are running MATLAB %s.\n\n' ...
                 'This profile is intended for R2010b (7.11) to ensure ' ...
                 'numerical parity with the legacy cluster runtime.\n\n' ...
                 'Results on this MATLAB version MAY differ from the ' ...
                 'expected near-parity output.'], profile, release), ...
                'MATLAB Version Warning');
        end
    end
end

end

%% ------------------------------------------------------------------------
function profiles = discover_profiles(profile_dir)
%DISCOVER_PROFILES Scan a directory for profile config .m files.
%   PROFILES = DISCOVER_PROFILES(PROFILE_DIR) returns an Nx2 cell array
%   where column 1 is the canonical profile name (e.g. 'local-current')
%   and column 2 is the filename (e.g. 'local_current.m').

files = dir(fullfile(profile_dir, '*.m'));
profiles = cell(numel(files), 2);
count = 0;

for ii = 1:numel(files)
    % Skip non-function files (e.g. plain scripts, package directories)
    if files(ii).isdir, continue; end
    
    [~, fname] = fileparts(files(ii).name);
    
    % Convert underscore-based filename to canonical hyphenated name
    canonical = strrep(fname, '_', '-');
    
    count = count + 1;
    profiles{count, 1} = canonical;
    profiles{count, 2} = files(ii).name;
end

% Trim unused rows
if count < size(profiles, 1)
    profiles(count + 1:end, :) = [];
end

end

%% ------------------------------------------------------------------------
function desc = read_h1_description(profile_dir, file_name)
%READ_H1_DESCRIPTION Read the H1 (first comment) line from an .m file.
%   DESC = READ_H1_DESCRIPTION(PROFILE_DIR, FILE_NAME) returns the first
%   contiguous comment line after the function signature, which is the
%   MATLAB convention for a one-line description.

desc = '';
file_path = fullfile(profile_dir, file_name);
if exist(file_path, 'file') ~= 2
    return;
end

try
    fid = fopen(file_path, 'r');
    if fid == -1
        return;
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    
    % Skip the function declaration line
    found_func = false;
    while true
        line = fgetl(fid);
        if line == -1
            return;
        end
        line = strtrim(line);
        if ~isempty(line) && strncmp(line, 'function', 8)
            found_func = true;
            break;
        end
    end
    
    if ~found_func
        return;
    end
    
    % Read the next non-blank comment line
    while true
        line = fgetl(fid);
        if line == -1
            return;
        end
        line = strtrim(line);
        if isempty(line)
            continue;
        end
        if ~isempty(line) && line(1) == '%'
            % Strip leading % and whitespace
            desc = strtrim(line(2:end));
            return;
        end
        % Non-blank, non-comment line means no H1 line
        return;
    end
catch ME %#ok<NASGU>
    % Silently return empty description
end
end
