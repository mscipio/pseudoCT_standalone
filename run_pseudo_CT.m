function run_pseudo_CT(varargin)
%RUN_PSEUDO_CT Run the pseudo-CT pipeline with a selected profile.
%   RUN_PSEUDO_CT() opens the profile selection dialog, then the existing
%   single-subject GUI (LOAD_MR_4_AC) for subject selection.
%
%   RUN_PSEUDO_CT('profile', NAME) runs with the specified profile.
%   RUN_PSEUDO_CT('profile', NAME, 'subjects', SUBJECT_LIST) batch mode.
%
%   Named parameters:
%     'profile'          - Execution profile. One of:
%                          'local-current' (default)
%                          'local-near-parity-r2010b'
%                          'launchpad'
%     'subjects'         - Cell or char array of MPRAGE filenames, or
%                          the string 'batch' to open an SPM multi-select
%                          file picker. Omit to use the single-subject GUI.
%     'correct_aliasing' - 0 or 1 to override the profile manifest's
%                          anti-aliasing default. Omit to use the manifest
%                          default.
%
%   Profiles:
%     local-current         Local MATLAB/SPM pipeline with the
%                           system-installed MATLAB version and compiled
%                           MEX dependencies. Recommended default.
%     local-near-parity-r2010b
%                           Local pipeline pinned to near-R2010b (7.11)
%                           numerical parity for consistent optimizer
%                           results across MATLAB versions. When selected
%                           on a MATLAB release other than R2010b, a
%                           warning is shown and the runtime guard is
%                           bypassed.
%     launchpad             Legacy compiled Launchpad backend via SSH.
%                           Intended for subjects requiring the original
%                           cluster runtime environment.
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

%% === 0. Handle deployed mode (before any argument parsing) ===
defaults = '';
if isdeployed
    if nargin == 1
        load(varargin{1});  % Load variable defaults! (creates 'defaults' struct)
    else
        disp('The Deployed application requires the defaults *.mat file!!');
        return;
    end
    profile_name = 'local-current';
    subjects_arg = '';
    aliasing_arg = [];
    
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
    p.addParamValue('profile', 'local-current', @(x) ischar(x));
    p.addParamValue('subjects', '', @(x) ischar(x) || iscell(x));
    p.addParamValue('correct_aliasing', [], ...
        @(x) isempty(x) || (isnumeric(x) && isscalar(x) && ismember(x, [0 1])));
    p.parse(varargin{:});
    
    profile_name = p.Results.profile;
    subjects_arg = p.Results.subjects;
    aliasing_arg = p.Results.correct_aliasing;
end

%% === Validate profile name ===
valid_profiles = {'local-current', 'local-near-parity-r2010b', 'launchpad'};
if ~ismember(profile_name, valid_profiles)
    error('run_pseudo_CT:InvalidProfile', ...
        'Unknown profile: ''%s''. Valid profiles are: local-current, local-near-parity-r2010b, launchpad', ...
        profile_name);
end

%% === Warning suppression ===
[orig_warn] = warning;
warning('off', 'all');
warn_cleanup = onCleanup(@() warning(orig_warn));

%% === Resolve repo root and add config to path ===
[pathp, ~, ~] = fileparts(mfilename('fullpath'));
addpath(fullfile(pathp, 'src', 'config'), '-begin');

%% === Resolve and patch manifest ===
manifest = pseudo_CT_resolve_profile(profile_name, pathp);

% If near-parity profile on non-R2010b MATLAB: warn and bypass runtime guard
if strcmp(profile_name, 'local-near-parity-r2010b')
    v = ver('MATLAB');
    if ~isempty(v)
        release = v.Release;  % e.g. '(R2023b)'
        if isempty(strfind(release, 'R2010b'))
            warning(['Profile ''local-near-parity-r2010b'' selected on MATLAB %s. ', ...
                     'Results may differ from expected near-parity output.'], release);
            manifest.runtime_guard = 'supported_matlab';
        end
    end
end

manifest = pseudo_CT_preflight(manifest, pathp);
setup_pseudo_CT_paths(pathp, manifest);
dir_batch_templates = pseudo_CT_resolve_batch_atlas_path(pathp, manifest);

%% === Collect jobs ===
if isempty(subjects_arg)
    jobs = collect_jobs(manifest);
elseif ischar(subjects_arg) && size(subjects_arg, 1) == 1 && ...
       strcmpi(strtrim(subjects_arg), 'batch')
    if isempty(aliasing_arg)
        jobs = collect_jobs(manifest, 'batch');
    else
        jobs = collect_jobs(manifest, 'batch', aliasing_arg);
    end
else
    if isempty(aliasing_arg)
        jobs = collect_jobs(manifest, subjects_arg);
    else
        jobs = collect_jobs(manifest, subjects_arg, aliasing_arg);
    end
end

if isempty(jobs)
    warning(orig_warn);
    return;
end

%% === Dispatch by profile ===
num_success = 0;
num_failed = 0;

switch profile_name
    
    case {'local-current', 'local-near-parity-r2010b'}
        % ============================================================
        % LOCAL EXECUTION PATH
        % ============================================================
        show_subject_dialog = (length(jobs) == 1);
        for jj = 1:length(jobs)
            if length(jobs) > 1
                disp(sprintf('\nStarting local pseudo-CT subject %d of %d:\n%s\n', ...
                    jj, length(jobs), jobs(jj).mprage_fn));
            end
            if local_run_subject(jobs(jj), dir_batch_templates, defaults, ...
                    show_subject_dialog, manifest)
                num_success = num_success + 1;
            else
                num_failed = num_failed + 1;
            end
        end
        
        if ~isdeployed && length(jobs) > 1
            disp(sprintf('\nLocal pseudo-CT batch finished.  Success: %d  Failed: %d\n', ...
                num_success, num_failed));
        end
        
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
            
            if length(jobs) > 1
                disp(sprintf('\nPreparing Launchpad pseudo-CT subject %d of %d:\n%s\n', ...
                    ii, length(jobs), jobs(ii).mprage_fn));
            end
            jobs(ii).seed_nii = convert_dicom_i_2_nii(jobs(ii).mprage_fn, 'mprage.nii', temp_dir);
            P(ii, 1:length(jobs(ii).seed_nii)) = jobs(ii).seed_nii;
            disp(sprintf('\n\nThis is the temporary working directory where intermediate results will be saved:\n%s\n', temp_dir));
        end
        
        % SSH credentials
        HOSTNAME = defaults_pseudo_CT_launchpad('HOSTNAME');
        if isdeployed && isstruct(defaults) && isfield(defaults, 'HOSTNAME')
            HOSTNAME = defaults.HOSTNAME;
        end
        [PASSWORD, USERNAME] = passwordEntryDialog('enterUserName', true, ...
            'ValidatePassword', true, 'PasswordLengthMax', 50, ...
            'WindowName', sprintf('Login for: %s', HOSTNAME));
        ssh_log = {USERNAME, PASSWORD, HOSTNAME};
        clear USERNAME PASSWORD HOSTNAME
        
        % Cleanup policy
        [cleanup_policy, ignored_keep_tmp] = cleanup_owner(manifest);
        if ~isempty(ignored_keep_tmp)
            fprintf(1, '[profile-resource-authority] cleanup policy = %s (ignored env)\n', cleanup_policy);
        else
            fprintf(1, '[profile-resource-authority] cleanup policy = %s\n', cleanup_policy);
        end
        zero_background = pseudo_CT_zero_background_enabled(manifest);
        keep_tmp_val = strcmp(cleanup_policy, 'keep_on_success');
        [~, ~, ~, ss_tot] = batch_pseudo_CT_launchpad(P, ssh_log, ...
            'clean_folder', 0, 'keep_tmp', keep_tmp_val, ...
            'check_aliasing', jobs(1).correct_aliasing);
        
        should_cleanup = strcmp(cleanup_policy, 'remove_on_success');
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
                if strcmp(zero_background, 'Yes')
                    launchpad_apply_background_mask(jobs(jj).temp_dir);
                end
                pseudo_CT_write_mu_map_dicom(fullfile(jobs(jj).temp_dir, 'att_map.nii'), ...
                    jobs(jj).save_dir, jobs(jj).umap_fn, jobs(jj).temp_dir, 0);
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
            elseif should_cleanup
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
        
end

%% === Restore warnings (redundant with onCleanup, but explicit) ===
warning(orig_warn);

end


%% ========================================================================
%  LOCAL SUBJECT EXECUTION
%  ========================================================================
function success = local_run_subject(job, dir_batch_templates, defaults, ...
    show_dialog, manifest)

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

% Resolve SSH host for FreeSurfer normalization
HOSTNAME = defaults_pseudo_CT('HOSTNAME');
if isdeployed && isstruct(defaults) && isfield(defaults, 'HOSTNAME')
    HOSTNAME = defaults.HOSTNAME;
end
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
    job.correct_aliasing, defaults, manifest);
if ~ischar(Pf) || isempty(strtrim(Pf))
    disp('Pseudo-CT processing stopped before generating atlas outputs.');
    return;
end

% Convert att_map.nii to DICOM
FWHM = 0;
[temp_working_dir, ~, ~] = fileparts(deblank(Pf(end, :)));
try
    pseudo_CT_write_mu_map_dicom(fullfile(temp_working_dir, 'att_map.nii'), ...
        save_dir, job.umap_fn, temp_dir, FWHM);
catch ME
    disp(ME.message);
    return;
end

% Promote final outputs and cleanup
[cleanup_policy, ignored_keep_tmp] = cleanup_owner(manifest);
if ~isempty(ignored_keep_tmp)
    fprintf(1, '[profile-resource-authority] cleanup policy = %s (ignored env)\n', cleanup_policy);
else
    fprintf(1, '[profile-resource-authority] cleanup policy = %s\n', cleanup_policy);
end
should_cleanup = strcmp(cleanup_policy, 'remove_on_success');
promotion_success = pseudo_CT_promote_final_outputs(temp_working_dir, processing_dir, P);
if ~promotion_success
    disp(sprintf('Final pseudo-CT files were left in the temporary folder:\n%s\n', temp_working_dir));
elseif should_cleanup
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
