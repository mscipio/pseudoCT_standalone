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
addpath(fullfile(pathp, 'src', 'io'), '-begin');
run_started = tic;
run_start_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
run_id = datestr(now, 'yyyymmdd_HHMMSS');
interactive_gui = ~isdeployed && nargin == 0;

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

%% === Warning handling ===
% Suppress all warnings during processing (legacy SPM8 generates many
% benign warnings about version compatibility, deprecated functions, and
% Java classpath conflicts). The original state is restored on exit via
% the onCleanup guard.
[orig_warn] = warning;
warning('off', 'all');
warn_cleanup = onCleanup(@() warning(orig_warn));

%% === Load the selected profile once and set up its resources ===
config = pseudo_CT_load_profile(profile_name, fullfile(pathp, 'src', 'config'));
if ~isempty(config.required_matlab_release) && ...
        ~strcmp(version('-release'), config.required_matlab_release)
    % Legacy output: warning(['Profile ''%s'' requires MATLAB R%s; running R%s. ', ...
    %          'Results may differ from the intended profile output.'], ...
    %     profile_name, config.required_matlab_release, version('-release'));
    pseudo_CT_output('WARN', struct('scope', 'run'), ...
        'Profile %s requires MATLAB R%s; running R%s. Results may differ.', ...
        profile_name, config.required_matlab_release, version('-release'));
end
setup_pseudo_CT_paths(pathp, config);
dir_batch_templates = config.atlas_root;

%% === Collect jobs ===
if isempty(subjects_arg)
    [jobs, collection_stats] = collect_jobs(config);
elseif ischar(subjects_arg) && size(subjects_arg, 1) == 1 && ...
       strcmpi(strtrim(subjects_arg), 'batch')
    if isempty(aliasing_arg)
        [jobs, collection_stats] = collect_jobs(config, 'batch');
    else
        [jobs, collection_stats] = collect_jobs(config, 'batch', aliasing_arg);
    end
else
    if isempty(aliasing_arg)
        [jobs, collection_stats] = collect_jobs(config, subjects_arg);
    else
        [jobs, collection_stats] = collect_jobs(config, subjects_arg, aliasing_arg);
    end
end

%% === Create one correlated run log per requested subject ===
all_log_files = {};
processing_dirs = {};
for ii = 1:length(jobs)
    [pathr, ~, ~] = fileparts(deblank(jobs(ii).mprage_fn));
    [processing_dir, temp_dir, save_dir] = pseudo_CT_resolve_output_dirs(pathr);
    jobs(ii).processing_dir = processing_dir;
    jobs(ii).temp_dir = temp_dir;
    jobs(ii).save_dir = save_dir;
    jobs(ii).subject_started = tic;
    local_ensure_directory(processing_dir);
    local_ensure_directory(temp_dir);
    local_ensure_directory(save_dir);
    jobs(ii).log_file = fullfile(processing_dir, ...
        sprintf('pseudo_CT_%s_%s.log', profile_name, run_id));
    all_log_files{end + 1} = jobs(ii).log_file; %#ok<AGROW>
    processing_dirs{end + 1} = processing_dir; %#ok<AGROW>
    context = local_subject_context(jobs(ii), ii, length(jobs));
    pseudo_CT_output('INFO', context, 'Run log initialized.');
    local_write_log_header(context, profile_name, config.mode, ...
        jobs(ii).mprage_fn, run_start_time, processing_dir, temp_dir);
end
for ii = 1:length(collection_stats.skipped_subjects)
    skipped_input = collection_stats.skipped_subjects{ii};
    [pathr, ~, ~] = fileparts(deblank(skipped_input));
    [processing_dir, temp_dir, ~] = pseudo_CT_resolve_output_dirs(pathr);
    local_ensure_directory(processing_dir);
    skipped_log = fullfile(processing_dir, ...
        sprintf('pseudo_CT_%s_%s.log', profile_name, run_id));
    all_log_files{end + 1} = skipped_log; %#ok<AGROW>
    processing_dirs{end + 1} = processing_dir; %#ok<AGROW>
    context = struct('log_file', skipped_log, 'scope', 'subject');
    local_write_log_header(context, profile_name, config.mode, skipped_input, ...
        run_start_time, processing_dir, temp_dir);
    pseudo_CT_output('WARN', context, 'Subject skipped because no UMAP reference was found.');
    pseudo_CT_output('INFO', context, '    %s', skipped_input);
end
run_context = struct('log_files', {all_log_files}, 'scope', 'run');
pseudo_CT_output('INFO', run_context, 'Profile: %s; mode: %s; MATLAB: %s.', ...
    profile_name, config.mode, version);
pseudo_CT_print_profile_summary(profile_name, config, processing_dirs, run_context);
if isempty(jobs)
    pseudo_CT_output('WARN', run_context, ...
        ['Run completed: requested %d, started 0, succeeded 0, failed 0, ', ...
         'skipped %d (elapsed %s).'], collection_stats.requested, ...
        collection_stats.skipped, local_elapsed(toc(run_started)));
    return;
end

%% === Dispatch by configured execution mode ===
num_success = 0;
num_failed = 0;
num_started = length(jobs);

switch config.mode
    
    case 'launchpad'
        % ============================================================
        % LAUNCHPAD EXECUTION PATH
        % ============================================================
        P = '';
        for ii = 1:length(jobs)
            context = local_subject_context(jobs(ii), ii, length(jobs));
            context = local_stage_context(context, 1);
            stage_started = tic;
            pseudo_CT_output('INFO', context, 'Preparing input MPRAGE.');
            if length(jobs) > 1
                % Legacy output: disp(sprintf('\nPreparing Launchpad pseudo-CT subject %d of %d:\n%s\n', ...
                %     ii, length(jobs), jobs(ii).mprage_fn));
            end
            jobs(ii).seed_nii = convert_dicom_i_2_nii(jobs(ii).mprage_fn, 'mprage.nii', jobs(ii).temp_dir);
            P(ii, 1:length(jobs(ii).seed_nii)) = jobs(ii).seed_nii;
            % Legacy output: disp(sprintf('\n\nThis is the temporary working directory where intermediate results will be saved:\n%s\n', temp_dir));
            pseudo_CT_output('SUCCESS', context, 'Input prepared (elapsed %s).', ...
                local_elapsed(toc(stage_started)));
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
            'check_aliasing', jobs(1).correct_aliasing, ...
            'output_contexts', {jobs.log_file}, config);
        
        for jj = 1:length(jobs)
            if ss_tot(jj) ~= 0
                % Legacy output: disp(sprintf('Pseudo-CT Launchpad processing failed for:\n%s\n', jobs(jj).mprage_fn));
                context = local_subject_context(jobs(jj), jj, length(jobs));
                pseudo_CT_output('ERROR', context, ...
                    'Subject failed during Launchpad processing (elapsed %s).', ...
                    local_elapsed(toc(jobs(jj).subject_started)));
                num_failed = num_failed + 1;
                continue;
            end
            
            if length(jobs) > 1
                % Legacy output: disp(sprintf('\nFinalizing Launchpad pseudo-CT subject %d of %d:\n%s\n', ...
                %     jj, length(jobs), jobs(jj).mprage_fn));
            end
            
            try
                context = local_subject_context(jobs(jj), jj, length(jobs));
                context = local_stage_context(context, 5);
                stage_started = tic;
                pseudo_CT_output('INFO', context, 'Applying local post-processing.');
                if strcmp(config.zero_background, 'Yes')
                    launchpad_apply_background_mask(jobs(jj).temp_dir, context);
                end
                pseudo_CT_output('SUCCESS', context, ...
                    'Local post-processing completed (elapsed %s).', ...
                    local_elapsed(toc(stage_started)));
                context = local_stage_context(context, 6);
                stage_started = tic;
                pseudo_CT_output('INFO', context, 'Writing DICOM output.');
                pseudo_CT_write_mu_map_dicom(fullfile(jobs(jj).temp_dir, 'att_map.nii'), ...
                    jobs(jj).save_dir, jobs(jj).umap_fn, jobs(jj).temp_dir, ...
                    config.fwhm);
                pseudo_CT_output('SUCCESS', context, 'DICOM output written (elapsed %s).', ...
                    local_elapsed(toc(stage_started)));
            catch ME
                % Legacy output: fprintf(1, '[launchpad-debug] Failed to write mu-map DICOM for subject:\n%s\n', jobs(jj).mprage_fn);
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
                        pseudo_CT_output('WARN', context, ...
                            'Failure detail: temporary files: %s', tmp_str);
                    end
                end
                % Legacy output: disp(ME.message);
                pseudo_CT_output('WARN', context, 'Failure detail: %s', ME.message);
                pseudo_CT_output('ERROR', local_subject_context(jobs(jj), jj, length(jobs)), ...
                    'Subject failed (elapsed %s).', ...
                    local_elapsed(toc(jobs(jj).subject_started)));
                num_failed = num_failed + 1;
                continue;
            end
            
            context = local_stage_context(context, 7);
            stage_started = tic;
            pseudo_CT_output('INFO', context, 'Promoting final outputs.');
            promotion_success = pseudo_CT_promote_final_outputs( ...
                jobs(jj).temp_dir, jobs(jj).processing_dir, deblank(P(jj, :)), context);
            if ~promotion_success
                % Legacy output: disp(sprintf('Final pseudo-CT files were left in the temporary folder:\n%s\n', ...
                %     jobs(jj).temp_dir));
                pseudo_CT_output('ERROR', context, 'Output promotion failed; temporary files were preserved.');
                pseudo_CT_output('INFO', context, '    %s', jobs(jj).temp_dir);
                pseudo_CT_output('ERROR', local_subject_context(jobs(jj), jj, length(jobs)), ...
                    'Subject failed (elapsed %s).', ...
                    local_elapsed(toc(jobs(jj).subject_started)));
                num_failed = num_failed + 1;
                continue;
            end
            pseudo_CT_output('SUCCESS', context, 'Outputs promoted (elapsed %s).', ...
                local_elapsed(toc(stage_started)));
            context = local_stage_context(context, 8);
            stage_started = tic;
            pseudo_CT_output('INFO', context, 'Cleaning up temporary files.');
            if config.cleanup_on_success
                [remove_success, msg] = rmdir(jobs(jj).temp_dir, 's');
                if ~remove_success
                    % Legacy output: disp(sprintf('There was an error removing the temporary directory %s\n%s', ...
                    %     jobs(jj).temp_dir, msg));
                    pseudo_CT_output('WARN', context, 'Temporary cleanup failed: %s', msg);
                end
            end
            pseudo_CT_output('SUCCESS', context, 'Cleanup completed (elapsed %s).', ...
                local_elapsed(toc(stage_started)));
            
            % Legacy output: disp(sprintf('\n\nYour att-map Dicom images have been saved in:\n%s\n', jobs(jj).save_dir));
            if promotion_success
                % Legacy output: disp(sprintf('The final pseudo-CT NIfTI/QC files were saved in:\n%s\n', ...
                %     jobs(jj).processing_dir));
            end
            num_success = num_success + 1;
            pseudo_CT_output('SUCCESS', local_subject_context(jobs(jj), jj, length(jobs)), ...
                'Subject completed (elapsed %s).', ...
                local_elapsed(toc(jobs(jj).subject_started)));
        end

        if ~isdeployed && length(jobs) > 1
            % Legacy output: disp(sprintf('\nLaunchpad pseudo-CT batch finished.  Success: %d  Failed: %d\n', ...
            %     num_success, num_failed));
        end
        
        if interactive_gui && num_success == 1
            warndlg('Pseudo-CT processing completed.', 'Pseudo-CT completed');
        end
        
    otherwise
        % ============================================================
        % LOCAL EXECUTION PATH
        % ============================================================
        show_subject_dialog = interactive_gui;
        for jj = 1:length(jobs)
            if length(jobs) > 1
                % Legacy output: disp(sprintf('\nStarting local pseudo-CT subject %d of %d:\n%s\n', ...
                %     jj, length(jobs), jobs(jj).mprage_fn));
            end
            try
                if local_run_subject(jobs(jj), dir_batch_templates, ...
                         show_subject_dialog, profile_name, config, jj, length(jobs))
                    num_success = num_success + 1;
                else
                    context = local_subject_context(jobs(jj), jj, length(jobs));
                    pseudo_CT_output('ERROR', context, 'Subject failed (elapsed %s).', ...
                        local_elapsed(toc(jobs(jj).subject_started)));
                    num_failed = num_failed + 1;
                end
            catch ME
                context = local_subject_context(jobs(jj), jj, length(jobs));
                pseudo_CT_output('ERROR', context, 'Subject failed: %s (elapsed %s).', ...
                    ME.message, local_elapsed(toc(jobs(jj).subject_started)));
                num_failed = num_failed + 1;
            end
        end

        if ~isdeployed && length(jobs) > 1
            % Legacy output: disp(sprintf('\nLocal pseudo-CT batch finished.  Success: %d  Failed: %d\n', ...
            %     num_success, num_failed));
        end
end

summary_level = 'SUCCESS';
if num_failed > 0
    summary_level = 'ERROR';
end
pseudo_CT_output(summary_level, run_context, ...
    ['Run completed: requested %d, started %d, succeeded %d, failed %d, ', ...
     'skipped %d (elapsed %s).'], collection_stats.requested, num_started, ...
    num_success, num_failed, collection_stats.skipped, ...
    local_elapsed(toc(run_started)));

end


%% ========================================================================
%  LOCAL SUBJECT EXECUTION
%  ========================================================================
function success = local_run_subject(job, dir_batch_templates, ...
    show_dialog, profile_name, config, subject_index, subject_count)

success = 0;
context = local_subject_context(job, subject_index, subject_count);
subject_started = job.subject_started;

[pathr, ~, ~] = fileparts(deblank(job.mprage_fn));
[processing_dir, temp_dir, save_dir] = pseudo_CT_resolve_output_dirs(pathr);
dir_list = {processing_dir, temp_dir, save_dir};
for ii = 1:length(dir_list)
    if exist(dir_list{ii}, 'dir') ~= 7
        [mkdir_success, msg] = mkdir(dir_list{ii});
        if ~mkdir_success
            % Legacy output: disp(sprintf('There was an error creating the directory %s\n%s', ...
            %     dir_list{ii}, msg));
            pseudo_CT_output('ERROR', context, 'Could not create directory: %s', msg);
            pseudo_CT_output('INFO', context, '    %s', dir_list{ii});
            return;
        end
    end
end

% Legacy output: pseudo_CT_print_profile_summary(profile_name, config, processing_dir);

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
context = local_stage_context(context, 1);
stage_started = tic;
pseudo_CT_output('INFO', context, 'Preparing input MPRAGE.');
P = convert_dicom_i_2_nii(job.mprage_fn, 'mprage.nii', temp_dir);
pseudo_CT_output('SUCCESS', context, 'Input prepared (elapsed %s).', ...
    local_elapsed(toc(stage_started)));

[temp_working_dir, ~, ~] = fileparts(deblank(P));
% Legacy output: disp(sprintf('\n\nThis is the temporary working directory where intermediate results will be saved:\n%s\n', ...
%     temp_working_dir));

% Run the pseudo-CT code
[Pf] = atlas_based_attenuation_map(P, dir_batch_templates, ssh_log, ...
    job.correct_aliasing, context, config);
if ~ischar(Pf) || isempty(strtrim(Pf))
    % Legacy output: disp('Pseudo-CT processing stopped before generating atlas outputs.');
    pseudo_CT_output('ERROR', context, 'Processing stopped before atlas outputs were generated.');
    return;
end

% Convert att_map.nii to DICOM
[temp_working_dir, ~, ~] = fileparts(deblank(Pf(end, :)));
try
    context = local_stage_context(context, 7);
    stage_started = tic;
    pseudo_CT_output('INFO', context, 'Writing DICOM output.');
    pseudo_CT_write_mu_map_dicom(fullfile(temp_working_dir, 'att_map.nii'), ...
        save_dir, job.umap_fn, temp_dir, config.fwhm);
    pseudo_CT_output('SUCCESS', context, 'DICOM output written (elapsed %s).', ...
        local_elapsed(toc(stage_started)));
catch ME
    % Legacy output: disp(ME.message);
    pseudo_CT_output('ERROR', context, 'DICOM output failed: %s', ME.message);
    return;
end

% Promote final outputs and clean up according to the selected profile.
context = local_stage_context(context, 8);
stage_started = tic;
pseudo_CT_output('INFO', context, 'Promoting outputs and cleaning up.');
promotion_success = pseudo_CT_promote_final_outputs(temp_working_dir, processing_dir, P, context);
if ~promotion_success
    % Legacy output: disp(sprintf('Final pseudo-CT files were left in the temporary folder:\n%s\n', temp_working_dir));
    pseudo_CT_output('ERROR', context, 'Output promotion failed; temporary files were preserved.');
    pseudo_CT_output('INFO', context, '    %s', temp_working_dir);
    return;
elseif config.cleanup_on_success
    [remove_success, msg] = rmdir(temp_working_dir, 's');
    if ~remove_success
        % Legacy output: disp(sprintf('There was an error removing the temporary directory %s\n%s', ...
        %     temp_working_dir, msg));
        pseudo_CT_output('WARN', context, 'Temporary cleanup failed: %s', msg);
    end
end

% Legacy output: disp(sprintf('\n\nYour att-map Dicom images have been saved in:\n%s\n', save_dir));
if promotion_success
    % Legacy output: disp(sprintf('The final pseudo-CT NIfTI/QC files were saved in:\n%s\n', processing_dir));
end
pseudo_CT_output('SUCCESS', context, 'Outputs promoted and cleanup completed (elapsed %s).', ...
    local_elapsed(toc(stage_started)));

if show_dialog && ~isdeployed
    % Legacy output: warndlg('Pseudo-CT image finished!!', 'Pseudo-CT finished!!');
    warndlg('Pseudo-CT processing completed.', 'Pseudo-CT completed');
end

success = 1;
pseudo_CT_output('SUCCESS', local_subject_context(job, subject_index, subject_count), ...
    'Subject completed (elapsed %s).', local_elapsed(toc(subject_started)));

end


%% ========================================================================
%  LAUNCHPAD BACKGROUND MASK
%  ========================================================================
function launchpad_apply_background_mask(temp_dir, context)

att_map_path = fullfile(temp_dir, 'att_map.nii');
normalized_path = fullfile(temp_dir, 'mprage_normalized.nii');
if exist(normalized_path, 'file') ~= 2
    % Legacy output: fprintf(1, ['WARNING: zero_background was requested, but %s is missing.\n', ...
    %             'The fetched Launchpad attenuation map will remain unmasked.\n'], normalized_path);
    pseudo_CT_output('WARN', context, ...
        'Background masking skipped because normalized MPRAGE is missing.');
    return;
end

try
    V_att_map = spm_vol(att_map_path);
    att_map = spm_read_vols(V_att_map);
    V_orig = spm_vol(normalized_path);
    orig_mprage = spm_read_vols(V_orig);
    if ~isequal(size(att_map), size(orig_mprage))
        % Legacy output: fprintf(1, ['WARNING: zero_background could not be applied because att_map.nii ', ...
        %             'and mprage_normalized.nii have different dimensions.\n', ...
        %             'The fetched Launchpad attenuation map will remain unmasked.\n']);
        pseudo_CT_output('WARN', context, ...
            'Background masking skipped because NIfTI dimensions differ.');
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
    % Legacy output: fprintf(1, ['WARNING: zero_background could not be applied: %s\n', ...
    %             'The fetched Launchpad attenuation mask will remain unmasked.\n'], ME_mask.message);
    pseudo_CT_output('WARN', context, 'Background masking skipped: %s', ME_mask.message);
end

end


function context = local_subject_context(job, subject_index, subject_count)
context = struct('log_file', job.log_file, 'subject_index', subject_index, ...
    'subject_count', subject_count, 'scope', 'subject');
end


function context = local_stage_context(context, stage_index)
context.stage_index = stage_index;
context.stage_count = 8;
end


function local_write_log_header(context, profile_name, mode_name, input_path, ...
    start_time, processing_dir, temp_dir)
pseudo_CT_output('INFO', context, 'Log header: profile=%s', profile_name);
pseudo_CT_output('INFO', context, 'Log header: mode=%s', mode_name);
pseudo_CT_output('INFO', context, 'Log header: MATLAB=%s', version);
pseudo_CT_output('INFO', context, 'Log header: start=%s', start_time);
pseudo_CT_output('INFO', context, 'Log header: input');
pseudo_CT_output('INFO', context, '    %s', input_path);
pseudo_CT_output('INFO', context, 'Log header: MR_PET path');
pseudo_CT_output('INFO', context, '    %s', processing_dir);
pseudo_CT_output('INFO', context, 'Log header: temporary path');
pseudo_CT_output('INFO', context, '    %s', temp_dir);
end


function local_ensure_directory(directory)
if exist(directory, 'dir') == 7
    return;
end
[success, message] = mkdir(directory);
if ~success
    error('pseudo_CT:CreateDirectoryFailed', ...
        'Could not create directory %s: %s', directory, message);
end
end


function value = local_elapsed(seconds)
seconds = max(0, floor(seconds));
hours = floor(seconds / 3600);
minutes = floor(rem(seconds, 3600) / 60);
seconds = rem(seconds, 60);
value = sprintf('%02d:%02d:%02d', hours, minutes, seconds);
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
