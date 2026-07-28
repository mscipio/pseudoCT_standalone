function run_pseudo_CT(varargin)
%RUN_PSEUDO_CT Run the pseudo-CT pipeline with a selected profile.
%   RUN_PSEUDO_CT() opens the profile selection dialog, then the existing
%   single-subject GUI (LOAD_MR_4_AC) for subject selection.
%
%   RUN_PSEUDO_CT('profile', NAME) runs with the specified profile.
%   RUN_PSEUDO_CT('profile', NAME, 'subjects', SUBJECT_LIST) batch mode.
%
%   Named parameters:
%     'profile'          - Required in CLI/script mode. Valid profiles are
%                          discovered from src/config/profiles/.
%     'subjects'         - Cell or char array of MPRAGE filenames, or
%                          the string 'batch' to open an SPM multi-select
%                          file picker. Omit to use the single-subject GUI.
%     'correct_aliasing' - 0 or 1 to override the profile's
%                          anti-aliasing default. Omit to use the profile
%                          default.
%
%   Profiles are auto-discovered from src/config/profiles/. Each .m
%   file in that directory defines one execution profile. To add a new
%   profile, add a new .m file to that directory.
%
%   Examples:
%       run_pseudo_CT()
%       run_pseudo_CT('profile', 'local-current')
%       run_pseudo_CT('profile', 'launchpad', 'subjects', 'batch')
%       run_pseudo_CT('profile', 'local-current', 'subjects', subject_list, ...
%                     'correct_aliasing', 0)
%
%   RUN_PSEUDO_CT(DEFAULTS_MAT) is supported only in deployed mode.
%   DEFAULTS_MAT should point to a MAT file containing the defaults
%   structure expected by the compiled application. This preserves the
%   existing launchpad deployed mode contract.
%
%   Outputs:
%       - final DICOM pseudo-muMAP images are written to MR/pseudo_muMAP
%       - final NIfTI/QC/version files are written to MR_PET
%       - intermediate files are staged in MR_PET/tmp and removed on
%         successful completion
%
%   Maintained by Michele Scipioni, PhD
%   mscipioni@mgh.harvard.edu
%   Updated: July 23, 2026.
%   Minimum supported MATLAB: R2010b (matches cluster's compiled-app runtime, MCR 7.11)

%% === 0. Resolve repo root and add config/ui to path (before any calls) ===
[pathp, ~, ~] = fileparts(mfilename('fullpath'));
addpath(fullfile(pathp, 'src', 'config'), '-begin');
addpath(fullfile(pathp, 'src', 'ui'), '-begin');

%% === 1. Handle deployed mode (before any argument parsing) ===
if isdeployed
    [profile_name, subjects_arg, aliasing_arg] = ...
        parse_deployed_arguments(varargin{:});
    
    %% === Interactive mode (no args): show profile selector ===
elseif nargin == 0
    profile_name = pseudo_CT_profile_selector();
    if isempty(profile_name)
        return;  % User cancelled
    end
    subjects_arg = '';
    aliasing_arg = [];
    
    %% === CLI/script mode: parse named arguments ===
else
    p = inputParser;
    p.addParamValue('profile', '', @(x) ischar(x));
    p.addParamValue('subjects', '', @(x) ischar(x) || iscell(x));
    p.addParamValue('correct_aliasing', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && ismember(x, [0 1])));
    p.parse(varargin{:});
    
    profile_name = p.Results.profile;
    subjects_arg = p.Results.subjects;
    aliasing_arg = p.Results.correct_aliasing;
end

%% === Validate profile name against available profile files ===
available_profiles = pseudo_CT_list_profiles(fullfile(pathp, 'src', 'config'));
valid_profiles = {available_profiles.name}';
if isempty(profile_name)
    error('run_pseudo_CT:ProfileRequired', ...
        'CLI/script invocation requires an explicit profile.');
end
requested_profile_name = profile_name;
profile_name = canonical_profile_name(requested_profile_name, available_profiles);
if isempty(profile_name)
    profile_list = join_strings(valid_profiles, ', ');
    error('run_pseudo_CT:InvalidProfile', ...
        'Unknown profile: ''%s''. Available profiles are: %s', ...
        requested_profile_name, profile_list);
end

%% === Warning suppression ===
[orig_warn] = warning;
warning('off', 'all');
warn_cleanup = onCleanup(@() warning(orig_warn));

%% === Load the selected profile once and set up its resources ===
config = pseudo_CT_load_profile(profile_name, fullfile(pathp, 'src', 'config'));
if ~isempty(config.required_matlab_release) && ...
        ~strcmp(version('-release'), config.required_matlab_release)
    warning(['Profile ''%s'' requires MATLAB R%s; running R%s. ', ...
             'Results may differ from the intended profile output.'], ...
        profile_name, config.required_matlab_release, version('-release'));
end
setup_pseudo_CT_paths(pathp, config);
dir_batch_templates = config.atlas_root;

%% === Collect jobs ===
if isempty(subjects_arg)
    jobs = collect_jobs(config);
elseif ischar(subjects_arg) && size(subjects_arg, 1) == 1 && ...
       strcmpi(strtrim(subjects_arg), 'batch')
    if isempty(aliasing_arg)
        jobs = collect_jobs(config, 'batch');
    else
        jobs = collect_jobs(config, 'batch', aliasing_arg);
    end
else
    if isempty(aliasing_arg)
        jobs = collect_jobs(config, subjects_arg);
    else
        jobs = collect_jobs(config, subjects_arg, aliasing_arg);
    end
end

if isempty(jobs)
    warning(orig_warn);
    return;
end

%% === Dispatch by configured execution mode ===
num_success = 0;
num_failed = 0;

switch config.mode
    
    case 'launchpad'
        % ============================================================
        % LAUNCHPAD EXECUTION PATH
        % ============================================================
        P = '';
        for ii = 1:length(jobs)
            [pathr, ~, ~] = fileparts(deblank(jobs(ii).mprage_fn));
            [processing_dir, temp_dir, save_dir] = pseudo_CT_resolve_output_dirs(pathr);
            jobs(ii).processing_dir = processing_dir;
            jobs(ii).temp_dir = temp_dir;
            jobs(ii).save_dir = save_dir;
            
            dir_list = {processing_dir, temp_dir, save_dir};
            for kk = 1:length(dir_list)
                if exist(dir_list{kk}, 'dir') ~= 7
                    [success, msg] = mkdir(dir_list{kk});
                    if ~success
                        warning(orig_warn);
                        disp(sprintf('There was an error creating the directory %s\n%s', ...
                            dir_list{kk}, msg));
                        return;
                    end
                end
            end
            
            % Print and save profile summary (first subject only)
            if ii == 1
                pseudo_CT_print_profile_summary(profile_name, config, processing_dir);
            end
            
            if length(jobs) > 1
                disp(sprintf('\nPreparing Launchpad pseudo-CT subject %d of %d:\n%s\n', ...
                    ii, length(jobs), jobs(ii).mprage_fn));
            end
            jobs(ii).seed_nii = convert_dicom_i_2_nii(jobs(ii).mprage_fn, 'mprage.nii', temp_dir);
            P(ii, 1:length(jobs(ii).seed_nii)) = jobs(ii).seed_nii;
            disp(sprintf('\n\nThis is the temporary working directory where intermediate results will be saved:\n%s\n', temp_dir));
        end

        % SSH credentials
        HOSTNAME = config.launchpad.host;
        [PASSWORD, USERNAME] = passwordEntryDialog('enterUserName', true, ...
            'ValidatePassword', true, 'PasswordLengthMax', 50, ...
            'WindowName', sprintf('Login for: %s', HOSTNAME));
        ssh_log = {USERNAME, PASSWORD, HOSTNAME};
        clear USERNAME PASSWORD HOSTNAME
        
        keep_tmp_val = ~config.cleanup_on_success;
        [~, ~, ~, ss_tot] = batch_pseudo_CT_launchpad(P, ssh_log, ...
            'clean_folder', 0, 'keep_tmp', keep_tmp_val, ...
            'check_aliasing', jobs(1).correct_aliasing, config);
        
        for jj = 1:length(jobs)
            if ss_tot(jj) ~= 0
                disp(sprintf('Pseudo-CT Launchpad processing failed for:\n%s\n', jobs(jj).mprage_fn));
                num_failed = num_failed + 1;
                continue;
            end
            
            if length(jobs) > 1
                disp(sprintf('\nFinalizing Launchpad pseudo-CT subject %d of %d:\n%s\n', ...
                    jj, length(jobs), jobs(jj).mprage_fn));
            end
            
            try
                if strcmp(config.zero_background, 'Yes')
                    launchpad_apply_background_mask(jobs(jj).temp_dir);
                end
                pseudo_CT_write_mu_map_dicom(fullfile(jobs(jj).temp_dir, 'att_map.nii'), ...
                    jobs(jj).save_dir, jobs(jj).umap_fn, jobs(jj).temp_dir, ...
                    config.fwhm);
            catch ME
                fprintf(1, '[launchpad-debug] Failed to write mu-map DICOM for subject:\n%s\n', jobs(jj).mprage_fn);
                tmp_list = dir(jobs(jj).temp_dir);
                if ~isempty(tmp_list)
                    tmp_names = {tmp_list(~ismember({tmp_list.name}, {'.', '..'})).name};
                    if ~isempty(tmp_names)
                        tmp_str = '';
                        for ti = 1:length(tmp_names)
                            if ti > 1
                                tmp_str = [tmp_str ', ']; %#ok<AGROW>
                            end
                            tmp_str = [tmp_str tmp_names{ti}]; %#ok<AGROW>
                        end
                        fprintf(1, '[launchpad-debug] temp_dir (%s) contents: %s\n', ...
                            jobs(jj).temp_dir, tmp_str);
                    end
                end
                disp(ME.message);
                num_failed = num_failed + 1;
                continue;
            end
            
            promotion_success = pseudo_CT_promote_final_outputs( ...
                jobs(jj).temp_dir, jobs(jj).processing_dir, deblank(P(jj, :)));
            if ~promotion_success
                disp(sprintf('Final pseudo-CT files were left in the temporary folder:\n%s\n', ...
                    jobs(jj).temp_dir));
            elseif config.cleanup_on_success
                [remove_success, msg] = rmdir(jobs(jj).temp_dir, 's');
                if ~remove_success
                    disp(sprintf('There was an error removing the temporary directory %s\n%s', ...
                        jobs(jj).temp_dir, msg));
                end
            end
            
            disp(sprintf('\n\nYour att-map Dicom images have been saved in:\n%s\n', jobs(jj).save_dir));
            if promotion_success
                disp(sprintf('The final pseudo-CT NIfTI/QC files were saved in:\n%s\n', ...
                    jobs(jj).processing_dir));
            end
            num_success = num_success + 1;
        end

        if ~isdeployed && length(jobs) > 1
            disp(sprintf('\nLaunchpad pseudo-CT batch finished.  Success: %d  Failed: %d\n', ...
                num_success, num_failed));
        end
        
        if ~isdeployed && length(jobs) == 1
            warndlg('Pseudo-CT image finished!!', 'Pseudo-CT finished!!');
        end
        
    otherwise
        % ============================================================
        % LOCAL EXECUTION PATH
        % ============================================================
        show_subject_dialog = (length(jobs) == 1);
        for jj = 1:length(jobs)
            if length(jobs) > 1
                disp(sprintf('\nStarting local pseudo-CT subject %d of %d:\n%s\n', ...
                    jj, length(jobs), jobs(jj).mprage_fn));
            end
            if local_run_subject(jobs(jj), dir_batch_templates, ...
                     show_subject_dialog, profile_name, config)
                num_success = num_success + 1;
            else
                num_failed = num_failed + 1;
            end
        end

        if ~isdeployed && length(jobs) > 1
            disp(sprintf('\nLocal pseudo-CT batch finished.  Success: %d  Failed: %d\n', ...
                num_success, num_failed));
        end
end

%% === Restore warnings (redundant with onCleanup, but explicit) ===
warning(orig_warn);

end


%% ========================================================================
%  LOCAL SUBJECT EXECUTION
%  ========================================================================
function success = local_run_subject(job, dir_batch_templates, ...
    show_dialog, profile_name, config)

success = 0;

[pathr, ~, ~] = fileparts(deblank(job.mprage_fn));
[processing_dir, temp_dir, save_dir] = pseudo_CT_resolve_output_dirs(pathr);
dir_list = {processing_dir, temp_dir, save_dir};
for ii = 1:length(dir_list)
    if exist(dir_list{ii}, 'dir') ~= 7
        [mkdir_success, msg] = mkdir(dir_list{ii});
        if ~mkdir_success
            disp(sprintf('There was an error creating the directory %s\n%s', ...
                dir_list{ii}, msg));
            return;
        end
    end
end

% Print and save profile summary
pseudo_CT_print_profile_summary(profile_name, config, processing_dir);

% Resolve SSH host for FreeSurfer normalization from the selected profile.
HOSTNAME = config.normalization.host;
if strcmp(HOSTNAME, '127.0.0.1') || strcmpi(HOSTNAME, 'localhost')
    USERNAME = getenv('USER');
    if isempty(USERNAME)
        USERNAME = getenv('LOGNAME');
    end
    if isempty(USERNAME)
        USERNAME = 'local';
    end
    ssh_log = struct('username', USERNAME, 'password', '', ...
        'hostname', HOSTNAME, 'autoreconnect', 0);
else
    [PASSWORD, USERNAME] = passwordEntryDialog('enterUserName', true, ...
        'ValidatePassword', true, 'PasswordLengthMax', 50, ...
        'WindowName', sprintf('Login for: %s', HOSTNAME));
    ssh_log = struct('username', USERNAME, 'password', PASSWORD, ...
        'hostname', HOSTNAME, 'autoreconnect', 0);
end

clear USERNAME PASSWORD HOSTNAME

% Convert DICOM to NIfTI
P = convert_dicom_i_2_nii(job.mprage_fn, 'mprage.nii', temp_dir);

[temp_working_dir, ~, ~] = fileparts(deblank(P));
disp(sprintf('\n\nThis is the temporary working directory where intermediate results will be saved:\n%s\n', ...
    temp_working_dir));

% Run the pseudo-CT code
[Pf] = atlas_based_attenuation_map(P, dir_batch_templates, ssh_log, ...
    job.correct_aliasing, config);
if ~ischar(Pf) || isempty(strtrim(Pf))
    disp('Pseudo-CT processing stopped before generating atlas outputs.');
    return;
end

% Convert att_map.nii to DICOM
[temp_working_dir, ~, ~] = fileparts(deblank(Pf(end, :)));
try
    pseudo_CT_write_mu_map_dicom(fullfile(temp_working_dir, 'att_map.nii'), ...
        save_dir, job.umap_fn, temp_dir, config.fwhm);
catch ME
    disp(ME.message);
    return;
end

% Promote final outputs and clean up according to the selected profile.
promotion_success = pseudo_CT_promote_final_outputs(temp_working_dir, processing_dir, P);
if ~promotion_success
    disp(sprintf('Final pseudo-CT files were left in the temporary folder:\n%s\n', temp_working_dir));
elseif config.cleanup_on_success
    [remove_success, msg] = rmdir(temp_working_dir, 's');
    if ~remove_success
        disp(sprintf('There was an error removing the temporary directory %s\n%s', ...
            temp_working_dir, msg));
    end
end

disp(sprintf('\n\nYour att-map Dicom images have been saved in:\n%s\n', save_dir));
if promotion_success
    disp(sprintf('The final pseudo-CT NIfTI/QC files were saved in:\n%s\n', processing_dir));
end

if show_dialog && ~isdeployed
    warndlg('Pseudo-CT image finished!!', 'Pseudo-CT finished!!');
end

success = 1;

end


%% ========================================================================
%  LAUNCHPAD BACKGROUND MASK
%  ========================================================================
function launchpad_apply_background_mask(temp_dir)

att_map_path = fullfile(temp_dir, 'att_map.nii');
normalized_path = fullfile(temp_dir, 'mprage_normalized.nii');
if exist(normalized_path, 'file') ~= 2
    fprintf(1, ['WARNING: zero_background was requested, but %s is missing.\n', ...
                'The fetched Launchpad attenuation map will remain unmasked.\n'], normalized_path);
    return;
end

try
    V_att_map = spm_vol(att_map_path);
    att_map = spm_read_vols(V_att_map);
    V_orig = spm_vol(normalized_path);
    orig_mprage = spm_read_vols(V_orig);
    if ~isequal(size(att_map), size(orig_mprage))
        fprintf(1, ['WARNING: zero_background could not be applied because att_map.nii ', ...
                    'and mprage_normalized.nii have different dimensions.\n', ...
                    'The fetched Launchpad attenuation map will remain unmasked.\n']);
        return;
    end
    
    [~, subj_mask] = head_mask_mprage(orig_mprage, 20);
    [L, num] = bwlabeln(subj_mask);
    if num > 1
        component_sizes = zeros(1, num);
        for ii = 1:num
            component_sizes(ii) = sum(L(:) == ii);
        end
        [~, pos_max] = max(component_sizes);
        subj_mask = L == pos_max;
    end
    subj_mask_dil = imdilate(subj_mask, ones(7, 7, 7));
    att_map = att_map .* ((subj_mask_dil + (orig_mprage > 20)) > 0);
    spm_write_vol(V_att_map, att_map);
catch ME_mask
    fprintf(1, ['WARNING: zero_background could not be applied: %s\n', ...
                'The fetched Launchpad attenuation mask will remain unmasked.\n'], ME_mask.message);
end

end


function str = join_strings(cell_arr, delimiter)
%JOIN_STRINGS Join cell array of strings with a delimiter (R2010b-compatible).
%   STR = JOIN_STRINGS(CELL_ARR, DELIMITER) concatenates the strings in
%   the cell array CELL_ARR separated by DELIMITER. Compatible with MATLAB
%   R2010b which does not have the built-in strjoin function.

str = '';
for ii = 1:numel(cell_arr)
    if ii > 1
        str = [str, delimiter]; %#ok<AGROW>
    end
    str = [str, char(cell_arr{ii})]; %#ok<AGROW>
end
end


function name = canonical_profile_name(requested, profiles)
%CANONICAL_PROFILE_NAME Accept profile display names or function filenames.

requested = strtrim(requested);
requested_function = strrep(requested, '-', '_');
name = '';
for ii = 1:length(profiles)
    if strcmp(requested, profiles(ii).name) || ...
            strcmp(requested_function, profiles(ii).function_name)
        name = profiles(ii).name;
        return;
    end
end
end


function [profile_name, subjects_arg, aliasing_arg] = ...
    parse_deployed_arguments(varargin)
%PARSE_DEPLOYED_ARGUMENTS Require an explicit profile in deployed mode.

subjects_arg = '';
aliasing_arg = [];

if nargin == 1 && ischar(varargin{1}) && exist(varargin{1}, 'file') == 2
    loaded = load(varargin{1});
    defaults = loaded;
    if isfield(loaded, 'defaults') && isstruct(loaded.defaults)
        defaults = loaded.defaults;
    end
    profile_name = deployed_profile_name(loaded, defaults);
    return;
end

if nargin == 0
    error('run_pseudo_CT:DeployedProfileRequired', ...
        'Deployed invocation requires an explicit profile selection.');
end

p = inputParser;
p.addParamValue('profile', '', @(x) ischar(x));
p.addParamValue('subjects', '', @(x) ischar(x) || iscell(x));
p.addParamValue('correct_aliasing', [], ...
    @(x) isempty(x) || (isnumeric(x) && isscalar(x) && ismember(x, [0 1])));
p.parse(varargin{:});
profile_name = p.Results.profile;
subjects_arg = p.Results.subjects;
aliasing_arg = p.Results.correct_aliasing;
if isempty(profile_name)
    error('run_pseudo_CT:DeployedProfileRequired', ...
        'Deployed invocation requires an explicit profile selection.');
end
end


function profile_name = deployed_profile_name(loaded, defaults)
%DEPLOYED_PROFILE_NAME Read the canonical profile from a compatibility MAT.

profile_name = '';
containers = {defaults, loaded};
field_names = {'profile_name'; 'profile'; 'execution_profile'};
for ii = 1:length(containers)
    candidate = containers{ii};
    if ~isstruct(candidate)
        continue;
    end
    for jj = 1:length(field_names)
        field_name = field_names{jj};
        if isfield(candidate, field_name) && ischar(candidate.(field_name))
            profile_name = strtrim(candidate.(field_name));
            if ~isempty(profile_name)
                return;
            end
        end
    end
end

error('run_pseudo_CT:DeployedProfileRequired', ...
    ['Deployed defaults MAT does not declare profile_name, profile, ', ...
     'or execution_profile. Silent local-current fallback is disabled.']);
end
