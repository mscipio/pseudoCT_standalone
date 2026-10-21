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
%     'mlsc_current_artifact_root'
%                        - Absolute directory supplying the operator-selected
%                          mlsc-current artifact (T007 build layout):
%                            <root>/payload_build/run_mlsc_current_payload.sh
%                            <root>/mlsc_current_build.mat
%                            <root>/mlsc_current_resources.mat
%                          No independent runner/build/resource overrides.
%                          Omit to use the installation-relative compiled
%                          artifact defaults, validated by content identity.
%                          Only mlsc-current may consume this option.
%     'mlsc_current_gate_a_record'
%                        - Absolute MAT path to the structured Gate-A record.
%                          When artifact_root is supplied and this is omitted,
%                          it defaults to <root>/mlsc_current_gate_a.mat.
%                          The packaged installation includes the validated
%                          record; explicit paths are for intentional overrides.
%                          Only mlsc-current may consume this option.
%
%   The artifact overrides only select which exact paths populate
%   config.current.runner/build_manifest/resource_manifest/gate_a_record.
%   They do NOT bypass Gate-A validation: validate_contract and
%   validate_for_execution still recompute every hash and binding, and wrong
%   or incomplete paths fail closed. MCR_ROOT is never overridable and stays
%   the pinned /usr/pubsw/common/matlab/26.1.
%
%   Profiles are auto-discovered from src/config/profiles/. Each .m
%   file in that directory defines one execution profile. To add a new
%   profile, add a new .m file to that directory.
%
%   Examples:
%       run_pseudo_CT()
%       run_pseudo_CT('profile', 'local-current')
%       run_pseudo_CT('profile', 'mlsc-legacy', 'subjects', 'batch')
%       run_pseudo_CT('profile', 'local-current', 'subjects', subject_list, ...
%                     'correct_aliasing', 0)
%       run_pseudo_CT('profile', 'mlsc-current', ...
%                     'mlsc_current_artifact_root', '/path/to/artifact', ...
%                     'mlsc_current_gate_a_record', '/path/to/mlsc_current_gate_a.mat')
%
%   RUN_PSEUDO_CT(DEFAULTS_MAT) is supported only in deployed mode.
%   DEFAULTS_MAT should point to a MAT file containing the defaults
%   structure expected by the compiled application. This preserves the
%   existing legacy compiled deployed-mode contract (historical Launchpad
%   contract).
%
%   Outputs:
%       - final DICOM pseudo-muMAP images are written to MR/pseudo_muMAP
%         when the selected profile declares nifti-and-dicom output
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

% Optional runtime-only MLSC trusted host-key material/provider seam.  It is
% never a profile field, never sourced from source control, and never logged;
% it is supplied out-of-band at runtime and defaults to empty.  An empty
% provider selects the normal Launchpad-style MLSC workflow: the existing
% username/password dialog, Ganymed password authentication, account
% discovery, and the Slurm lifecycle without any known_hosts/fingerprint
% input or authentication block.  A supplied provider selects strict pinned
% host-key verification, which fails closed on any doubt.
mlsc_host_key_provider = [];
% Public mlsc-current artifact overrides (T009 Option A). Empty defaults
% keep the canonical /usr/pubsw profile paths unchanged.
mlsc_current_artifact_root = '';
mlsc_current_gate_a_record = '';

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
    % Optional, out-of-band MLSC trusted host-key material/provider.  Accepts a
    % character known_hosts record or a zero-argument function handle returning
    % one; it is never read from a profile and never logged.  Empty (default)
    % selects the Launchpad-style password-authentication workflow; a supplied
    % value selects strict pinned host-key verification.
    p.addParamValue('mlsc_host_key_provider', [], ...
        @(x) isempty(x) || ischar(x) || isa(x, 'function_handle'));
    % T009 Option A: explicit operator-selected mlsc-current artifact
    % overrides. Only mlsc-current may consume them (enforced after profile
    % load); they never bypass Gate-A validation and never override MCR_ROOT.
    p.addParamValue('mlsc_current_artifact_root', '', @(x) ischar(x));
    p.addParamValue('mlsc_current_gate_a_record', '', @(x) ischar(x));
    p.parse(varargin{:});

    profile_name = p.Results.profile;
    subjects_arg = p.Results.subjects;
    aliasing_arg = p.Results.correct_aliasing;
    mlsc_host_key_provider = p.Results.mlsc_host_key_provider;
    mlsc_current_artifact_root = p.Results.mlsc_current_artifact_root;
    mlsc_current_gate_a_record = p.Results.mlsc_current_gate_a_record;
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
% T009 Option A: apply explicit mlsc-current artifact overrides through the
% real public config path. Default (both empty) leaves the canonical
% /usr/pubsw profile unchanged; only mlsc-current may consume overrides.
config = pseudo_CT_apply_mlsc_current_overrides(config, profile_name, ...
    mlsc_current_artifact_root, mlsc_current_gate_a_record);
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
    if strcmp(config.io_policy.output, 'nifti-and-dicom')
        local_ensure_directory(save_dir);
    end
    jobs(ii).log_file = fullfile(processing_dir, ...
        sprintf('pseudo_CT_%s_%s.log', profile_name, run_id));
    all_log_files{end + 1} = jobs(ii).log_file; %#ok<AGROW>
    processing_dirs{end + 1} = processing_dir; %#ok<AGROW>
    header_context = struct('log_file', jobs(ii).log_file, 'scope', 'run');
    pseudo_CT_output('INFO', header_context, 'Run log initialized.');
    local_write_log_header(header_context, profile_name, config.mode, ...
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
mlsc_context = struct('log_files', {all_log_files}, 'scope', 'mlsc');
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
            jobs(ii).seed_nii = dcm2nii(jobs(ii).mprage_fn, fullfile(jobs(ii).temp_dir, 'mprage.nii'), 'Overwrite', true);
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
                % The shared finalizer preserves the historical order of
                % launchpad_apply_background_mask(jobs(jj).temp_dir, context),
                % pseudo_CT_write_mu_map_dicom, and
                % pseudo_CT_promote_final_outputs.
                if local_finalize_remote_subject(jobs(jj), deblank(P(jj, :)), ...
                        config, jj, length(jobs))
                    num_success = num_success + 1;
                else
                    num_failed = num_failed + 1;
                end
            catch ME
                context = local_subject_context(jobs(jj), jj, length(jobs));
                local_log_remote_failure(jobs(jj), context, ME.message);
                num_failed = num_failed + 1;
                continue;
            end
        end

        if ~isdeployed && length(jobs) > 1
            % Legacy output: disp(sprintf('\nLaunchpad pseudo-CT batch finished.  Success: %d  Failed: %d\n', ...
            %     num_success, num_failed));
        end
        
        if interactive_gui && num_success == 1
            warndlg('Pseudo-CT processing completed.', 'Pseudo-CT completed');
        end
        
    case 'mlsc'
        % ============================================================
        % MLSC/SLURM EXECUTION PATH
        % ============================================================
        num_started = 0;
        for ii = 1:length(jobs)
            context = local_subject_context(jobs(ii), ii, length(jobs));
            context = local_stage_context(context, 1);
            stage_started = tic;
            pseudo_CT_output('INFO', context, 'Preparing input MPRAGE.');
            jobs(ii).seed_nii = dcm2nii(jobs(ii).mprage_fn, ...
                fullfile(jobs(ii).temp_dir, 'mprage.nii'), 'Overwrite', true);
            pseudo_CT_output('SUCCESS', context, 'Input prepared (elapsed %s).', ...
                local_elapsed(toc(stage_started)));
        end

        account = '';
        mlsc_cancelled = false;
        [PASSWORD, USERNAME] = passwordEntryDialog('enterUserName', true, ...
            'ValidatePassword', true, 'PasswordLengthMax', 50, ...
            'WindowName', sprintf('Login for: %s', config.mlsc.host));
        if isequal(PASSWORD, -1) || isempty(USERNAME)
            clear USERNAME PASSWORD
            num_started = 0;
            mlsc_cancelled = true;
        else
            % The provider is optional: an empty provider creates a
            % provider-free transport that authenticates with the dialog
            % credentials over the Ganymed password path and still reaches
            % account discovery and the Slurm lifecycle below; a supplied
            % provider selects strict pinned host-key verification first.
            transport = local_create_mlsc_transport(config, USERNAME, ...
                PASSWORD, mlsc_host_key_provider);
            transport_cleanup = onCleanup(@() local_cleanup_mlsc_transport(transport));
            clear USERNAME PASSWORD

            transport_ready = false;
            try
                transport_ready = feval(transport.verify);
            catch ME
                pseudo_CT_output('ERROR', run_context, ...
                    'MLSC secure transport verification failed; no account query or submission was attempted: %s', ...
                    ME.message);
            end
            if ~transport_ready
                num_started = 0;
                num_failed = length(jobs);
                account = '';
            else
                pseudo_CT_output('SUCCESS', mlsc_context, ...
                    'MLSC connection and authentication succeeded.');
                try
                    accounts = mlsc_parse_slurm_accounts( ...
                        feval(transport.query_accounts));
                    pseudo_CT_output('INFO', mlsc_context, ...
                        'Discovered %d Slurm account(s).', length(accounts));
                    account = mlsc_select_account(accounts);
                    if ~isempty(account)
                        pseudo_CT_output('INFO', mlsc_context, ...
                            'Selected MLSC account %s.', account);
                    end
                    mlsc_cancelled = isempty(account);
                catch ME
                    if strcmp(ME.identifier, 'pseudo_CT:MLSCNoAccounts')
                        pseudo_CT_output('ERROR', run_context, ...
                            'No Slurm account is available for the authenticated MLSC user; no job was submitted.');
                        num_started = 0;
                        num_failed = length(jobs);
                        account = '';
                    else
                        rethrow(ME);
                    end
                end
            end
        end
        if ~isempty(account)
            if exist('transport', 'var') ~= 1
                error('run_pseudo_CT:MLSCTransportRequired', ...
                    'MLSC account selection requires an authenticated transport.');
            end
                for ii = 1:length(jobs)
                    % T005 MLSC user-facing events (non-secret only): 4 input
                    % was stage 1 above; 5 submit is stage 2 below; 6
                    % accepted ID, 7 initial observed state, 8 transitions,
                    % 9 heartbeat, 10 compute milestones, and 11 terminal
                    % summary render inside mlsc_lifecycle via the
                    % non-secret output_context (stage 3 Running for
                    % stage-in/normalize/pseudoCT/running/heartbeat,
                    % stage 4 Retrieving for verify/copy-back/verified
                    % return); 12 return to finalization is below before
                    % retained stages 5-8.
                    context = local_subject_context(jobs(ii), ii, length(jobs));
                    output_context = local_subject_context(jobs(ii), ii, length(jobs));
                    runtime = struct('profile', profile_name, 'account', account, ...
                        'script_path', fullfile(jobs(ii).temp_dir, ...
                        sprintf('.pseudo_CT_mlsc_%s_%d.sh', run_id, ii)), ...
                        'evidence_dir', jobs(ii).processing_dir, ...
                        'log_archive_dir', jobs(ii).processing_dir, ...
                        'cleanup_script', true, 'output_context', output_context);
                    submit_context = local_stage_context(context, 2);
                    pseudo_CT_output('INFO', submit_context, ...
                        'Submitting MLSC job.');
                    subject = struct('subject_id', jobs(ii).mprage_fn, ...
                        'shared_input', jobs(ii).seed_nii, ...
                        'shared_temp', jobs(ii).temp_dir);
                    % T004 current seam: credential-free per-job alias/
                    % recenter overrides travel in the subject so the
                    % current job manifest carries effective overrides
                    % (never profile defaults). Legacy path unchanged.
                    try
                        if isfield(config, 'implementation') && ...
                                ischar(config.implementation) && ...
                                strcmp(config.implementation, 'current')
                            subject.check_aliasing = jobs(ii).correct_aliasing;
                            subject.recenter_before_normalization = ...
                                jobs(ii).recenter_before_normalization;
                        end
                    catch %#ok<CTCH>
                    end
                    lifecycle = struct();
                    try
                        lifecycle = mlsc_lifecycle(subject, config, runtime, transport);
                        if lifecycle.submitted
                            num_started = num_started + 1;
                        end
                        mlsc_job_id = local_mlsc_job_id(lifecycle);
                        if mlsc_job_id > 0
                            context.job_number = mlsc_job_id;
                        end
                        if ~lifecycle.eligible_for_finalization || ...
                                ~lifecycle.copy_back.verified
                            failure_detail = lifecycle.failure_detail;
                            if isempty(failure_detail)
                                failure_detail = ...
                                    'MLSC output was not verified in the shared subject temporary directory.';
                            end
                            lifecycle = mlsc_record_finalization(lifecycle, runtime, ...
                                false, false, failure_detail);
                            pseudo_CT_output('ERROR', context, ...
                                'Subject failed before local finalization: %s', failure_detail);
                            num_failed = num_failed + 1;
                            continue;
                        end
                        if mlsc_job_id > 0
                            pseudo_CT_output('INFO', context, ...
                                'MLSC verified return to shared temp for job %d; returning to local finalization.', ...
                                mlsc_job_id);
                        else
                            pseudo_CT_output('INFO', context, ...
                                'MLSC verified return to shared temp; returning to local finalization.');
                        end
                        finalization_success = local_finalize_remote_subject(jobs(ii), ...
                                jobs(ii).seed_nii, config, ii, length(jobs), mlsc_job_id);
                        lifecycle = mlsc_record_finalization(lifecycle, runtime, ...
                            true, logical(finalization_success), ...
                            local_finalization_detail(finalization_success));
                        if lifecycle.finalization_evidence_save_failed
                            pseudo_CT_output('ERROR', context, ...
                                'MLSC finalization evidence could not be saved.');
                            num_failed = num_failed + 1;
                        elseif finalization_success
                            num_success = num_success + 1;
                        else
                            num_failed = num_failed + 1;
                        end
                    catch ME
                        if exist('lifecycle', 'var') == 1 && ...
                                isstruct(lifecycle) && isfield(lifecycle, 'terminal')
                            lifecycle = mlsc_record_finalization(lifecycle, runtime, ...
                                true, false, ...
                                'Local MLSC finalization raised an error.');
                        end
                        pseudo_CT_output('ERROR', context, ...
                            'Subject failed: %s (elapsed %s).', ME.message, ...
                            local_elapsed(toc(jobs(ii).subject_started)));
                        num_failed = num_failed + 1;
                    end
                end
        else
            num_started = 0;
            if mlsc_cancelled
                pseudo_CT_output('INFO', run_context, ...
                    'MLSC submission was cancelled; no Slurm job was submitted.');
            end
        end

    case 'local'
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
                if strcmp(config.implementation, 'legacy-v2')
                    subject_success = pseudo_CT_run_local_legacy_subject( ...
                        jobs(jj), config, jj, length(jobs), show_subject_dialog);
                else
                    subject_success = local_run_subject(jobs(jj), dir_batch_templates, ...
                         show_subject_dialog, profile_name, config, jj, length(jobs));
                end
                if subject_success
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

    otherwise
        % ============================================================
        % Unsupported execution mode
        % ============================================================
        error('run_pseudo_CT:UnsupportedMode', ...
            'Unsupported execution mode: %s.', config.mode);
end

if exist('transport', 'var') == 1
    local_cleanup_mlsc_transport(transport);
    clear transport
end
if exist('transport_cleanup', 'var') == 1
    clear transport_cleanup
end
clear account accounts runtime lifecycle subject

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

function detail = local_finalization_detail(success)
if success
    detail = 'Local MLSC finalization completed.';
else
    detail = 'Local MLSC finalization did not complete.';
end
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
dir_list = {processing_dir, temp_dir};
if strcmp(config.io_policy.output, 'nifti-and-dicom')
    dir_list{end + 1} = save_dir;
end
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
P = dcm2nii(job.mprage_fn, fullfile(temp_dir, 'mprage.nii'), 'Overwrite', true);
pseudo_CT_output('SUCCESS', context, 'Input prepared (elapsed %s).', ...
    local_elapsed(toc(stage_started)));

[temp_working_dir, ~, ~] = fileparts(deblank(P));
% Legacy output: disp(sprintf('\n\nThis is the temporary working directory where intermediate results will be saved:\n%s\n', ...
%     temp_working_dir));

% Run the pseudo-CT code
[Pf] = atlas_based_attenuation_map(P, dir_batch_templates, ssh_log, ...
    job.correct_aliasing, context, job.recenter_before_normalization, config);
if ~ischar(Pf) || isempty(strtrim(Pf))
    % Legacy output: disp('Pseudo-CT processing stopped before generating atlas outputs.');
    pseudo_CT_output('ERROR', context, 'Processing stopped before atlas outputs were generated.');
    return;
end

% Convert att_map.nii to DICOM only when the selected policy requests it.
[temp_working_dir, ~, ~] = fileparts(deblank(Pf(end, :)));
if strcmp(config.io_policy.output, 'nifti-and-dicom')
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
else
    pseudo_CT_output('INFO', context, 'Skipping DICOM output by profile policy.');
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


function success = local_finalize_remote_subject(job, seed_nii, config, ...
        subject_index, subject_count, job_id)
%LOCAL_FINALIZE_REMOTE_SUBJECT Apply the common post-remote finalization order.
%   Optional JOB_ID propagates the accepted numeric MLSC job ID through the
%   stage 5-8 tags.  Launchpad callers omit it and observe unchanged output.

success = 0;
if nargin < 6
    job_id = [];
end
context = local_subject_context(job, subject_index, subject_count);
context = local_attach_mlsc_job(context, job_id);
context = local_stage_context(context, 5);
stage_started = tic;
pseudo_CT_output('INFO', context, 'Applying local post-processing.');
% T004 current: the shared current core owns zero-background policy, so the
% legacy post-fetch re-mask is skipped for current. Legacy/launchpad keep
% the historical post-fetch mask.
is_current_finalize = false;
try
    is_current_finalize = isfield(config, 'implementation') && ...
        ischar(config.implementation) && ...
        strcmp(config.implementation, 'current');
catch %#ok<CTCH>
    is_current_finalize = false;
end
if strcmp(config.zero_background, 'Yes') && ~is_current_finalize
    pseudo_CT_apply_background_mask(job.temp_dir, context);
end
pseudo_CT_output('SUCCESS', context, ...
    'Local post-processing completed (elapsed %s).', ...
    local_elapsed(toc(stage_started)));

if strcmp(config.io_policy.output, 'nifti-and-dicom')
    context = local_stage_context(context, 6);
    stage_started = tic;
    pseudo_CT_output('INFO', context, 'Writing DICOM output.');
    try
        pseudo_CT_write_mu_map_dicom(fullfile(job.temp_dir, 'att_map.nii'), ...
            job.save_dir, job.umap_fn, job.temp_dir, config.fwhm);
    catch ME
        local_log_remote_failure(job, context, ME.message);
        return;
    end
    pseudo_CT_output('SUCCESS', context, 'DICOM output written (elapsed %s).', ...
        local_elapsed(toc(stage_started)));
else
    pseudo_CT_output('INFO', context, 'Skipping DICOM output by profile policy.');
end

context = local_stage_context(context, 7);
stage_started = tic;
pseudo_CT_output('INFO', context, 'Promoting final outputs.');
promotion_success = pseudo_CT_promote_final_outputs( ...
    job.temp_dir, job.processing_dir, seed_nii, context);
if ~promotion_success
    pseudo_CT_output('ERROR', context, ...
        'Output promotion failed; temporary files were preserved.');
    pseudo_CT_output('INFO', context, '    %s', job.temp_dir);
    local_log_subject_failure(job, context);
    return;
end
pseudo_CT_output('SUCCESS', context, 'Outputs promoted (elapsed %s).', ...
    local_elapsed(toc(stage_started)));

context = local_stage_context(context, 8);
stage_started = tic;
pseudo_CT_output('INFO', context, 'Cleaning up temporary files.');
if config.cleanup_on_success
    [remove_success, msg] = rmdir(job.temp_dir, 's');
    if ~remove_success
        pseudo_CT_output('WARN', context, 'Temporary cleanup failed: %s', msg);
    end
end
pseudo_CT_output('SUCCESS', context, 'Cleanup completed (elapsed %s).', ...
    local_elapsed(toc(stage_started)));

success = 1;
final_context = local_subject_context(job, subject_index, subject_count);
final_context = local_attach_mlsc_job(final_context, job_id);
pseudo_CT_output('SUCCESS', final_context, ...
    'Subject completed (elapsed %s).', local_elapsed(toc(job.subject_started)));
end


function job_id = local_mlsc_job_id(lifecycle)
%LOCAL_MLSC_JOB_ID Return the accepted numeric Slurm job ID or zero.
job_id = 0;
try
    if isstruct(lifecycle) && isfield(lifecycle, 'job_id') && ...
            isnumeric(lifecycle.job_id) && isscalar(lifecycle.job_id) && ...
            isfinite(lifecycle.job_id) && ...
            lifecycle.job_id == floor(lifecycle.job_id) && ...
            lifecycle.job_id >= 1
        job_id = lifecycle.job_id;
    end
catch %#ok<CTCH>
    job_id = 0;
end
end


function context = local_attach_mlsc_job(context, job_id)
%LOCAL_ATTACH_MLSC_JOB Add the numeric job tag without other context changes.
try
    if isnumeric(job_id) && isscalar(job_id) && isfinite(job_id) && ...
            job_id == floor(job_id) && job_id >= 1
        context.job_number = job_id;
    end
catch %#ok<CTCH>
end
end


function local_log_remote_failure(job, context, detail)
tmp_list = dir(job.temp_dir);
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
pseudo_CT_output('WARN', context, 'Failure detail: %s', detail);
local_log_subject_failure(job, context);
end


function local_log_subject_failure(job, context)
failure_context = local_subject_context(job, context.subject_index, ...
    context.subject_count);
try
    if isfield(context, 'job_number')
        failure_context = local_attach_mlsc_job(failure_context, context.job_number);
    end
catch %#ok<CTCH>
end
pseudo_CT_output('ERROR', failure_context, 'Subject failed (elapsed %s).', ...
    local_elapsed(toc(job.subject_started)));
end


function transport = local_create_mlsc_transport(config, username, password, ...
        host_key_provider)
%LOCAL_CREATE_MLSC_TRANSPORT Build the credential-free callback surface.
%   Credentials remain in this runtime closure only.  The optional
%   HOST_KEY_PROVIDER selects the host-key trust model.  When it is empty
%   (the normal MLSC workflow), VERIFY uses the bundled Ganymed password
%   authentication path with an empty verifier, exactly like the Launchpad
%   login model: no known_hosts/fingerprint input and no authentication
%   block, after which account discovery and the Slurm lifecycle proceed
%   normally.  When an explicitly supplied, independently trusted MLSC
%   known_hosts record (character text or a zero-argument provider handle,
%   never a profile field or logged value) is given, VERIFY resolves it
%   into an in-memory Ganymed KnownHosts database and a strict
%   ServerHostKeyVerifier, and Connection.connect(verifier) runs before
%   authentication; missing, malformed, unsupported, new, changed, or
%   mismatched host keys then fail closed before authentication, account
%   discovery, or submission, and only a key reported as HOSTKEY_IS_OK is
%   accepted.  No host-key material is ever persisted or logged.

connection = [];
host_key_verifier = [];
verified = false;
if nargin < 4
    host_key_provider = [];
end
strict_host_key_trust = ~isempty(host_key_provider);
transport = struct('verify', @local_verify, ...
    'query_accounts', @local_query_accounts, ...
    'submit_script', @local_submit_script, ...
    'query_squeue', @local_query_squeue, ...
    'query_sacct', @local_query_sacct, ...
    'query_squeue_by_name', @local_query_squeue_by_name, ...
    'query_sacct_by_name', @local_query_sacct_by_name, ...
    'cancel_job', @local_cancel_job, ...
    'cleanup', @local_cleanup);

    function accepted = local_verify()
        accepted = false; %#ok<NASGU>
        % Idempotent: an authenticated connection from an earlier verify
        % (run_pseudo_CT and mlsc_backend both call verify) is reused rather
        % than re-opened, so no duplicate socket is ever created.
        if verified && ~isempty(connection) && ...
                isfield(connection, 'authenticated') && ...
                connection.authenticated == 1
            accepted = true;
            return;
        end
        verified = false;
        if strict_host_key_trust
            % Resolve the trusted material and bind a strict verifier BEFORE
            % any connection; a missing/malformed/unsupported source fails
            % closed here.
            verifier = [];
            try
                verifier = mlsc_host_key_trust( ...
                    config.mlsc.host, 22, host_key_provider);
            catch ME
                error('pseudo_CT:MLSCTransportRejected', ...
                    ['The supplied MLSC host-key provider could not ', ...
                     'establish strict pinned host-key trust; no ', ...
                     'connection, authentication, account query, or ', ...
                     'submission was attempted. (%s)'], ME.message);
            end
            if isempty(verifier)
                error('pseudo_CT:MLSCTransportRejected', ...
                    ['The supplied MLSC host-key provider requires a ', ...
                     'non-null strict host-key verifier; no connection or ', ...
                     'submission was attempted.']);
            end
            host_key_verifier = verifier;
        end
        % Provider-free: host_key_verifier stays empty and ssh2_main uses its
        % existing password-authentication connect branch, matching the
        % Launchpad operational model without any host-key input.
        % Open the connection: ssh2_main runs Connection.connect (strictly
        % through the verifier when one was resolved) before
        % authenticateWithPassword, so a rejected host key aborts the
        % handshake before any credential use.
        try
            connection = local_open_verified_connection();
        catch ME
            connection = [];
            host_key_verifier = [];
            if strict_host_key_trust
                error('pseudo_CT:MLSCTransportRejected', ...
                    ['Strict MLSC host-key verification or password ', ...
                     'authentication failed before account discovery; no ', ...
                     'account query or submission was attempted. (%s)'], ...
                    ME.message);
            end
            error('pseudo_CT:MLSCTransportRejected', ...
                ['MLSC password authentication failed; no account query or ', ...
                 'submission was attempted. (%s)'], ME.message);
        end
        verified = true;
        accepted = true;
    end

    function response = local_query_accounts()
        local_require_verified();
        response = local_remote_command('sshare -U -u $USER');
    end

    function response = local_submit_script(command)
        local_require_verified();
        response = local_remote_command(command);
    end

    function response = local_query_squeue(job_id)
        local_require_verified();
        response = local_remote_command(['squeue --noheader --jobs=' ...
            local_job_id_text(job_id) ' --format=%T']);
    end

    function response = local_query_sacct(job_id)
        local_require_verified();
        response = local_remote_command(['sacct --allocations --noheader ', ...
            '--parsable2 --jobs=' local_job_id_text(job_id) ...
            ' --format=JobIDRaw,State,ExitCode,Start,End,Elapsed']);
    end

    function response = local_query_squeue_by_name(job_name)
        local_require_verified();
        response = local_remote_command(['squeue --noheader --user="$USER" ', ...
            '--name=' local_job_name_text(job_name) ' --format=%A']);
    end

    function response = local_query_sacct_by_name(job_name)
        local_require_verified();
        response = local_remote_command(['sacct --allocations --noheader ', ...
            '--parsable2 --user="$USER" --name=' local_job_name_text(job_name) ...
            ' --format=JobIDRaw,State,ExitCode,Start,End,Elapsed']);
    end

    function response = local_cancel_job(job_id)
        local_require_verified();
        response = local_remote_command(['scancel -- ' local_job_id_text(job_id)]);
    end

    function response = local_remote_command(command)
        if isempty(connection)
            connection = local_open_verified_connection();
        end
        [connection, response] = ssh2_command(connection, command, 0);
    end

    function verified_connection = local_open_verified_connection()
        % Build a connection struct that carries the verifier selected for
        % this runtime: the non-null strict verifier when a host-key provider
        % was supplied, or empty for the provider-free Launchpad-style
        % password-authentication workflow, whose empty verifier routes
        % ssh2_main to its existing connect()/authenticateWithPassword
        % branch.  A supplied provider must never reach the empty-verifier
        % branch: the null verifier is rejected here.
        if strict_host_key_trust && isempty(host_key_verifier)
            error('pseudo_CT:MLSCTransportRejected', ...
                ['MLSC requires a non-null strict host-key verifier before any ', ...
                 'secure connection; no connection or submission was attempted.']);
        end
        verified_connection = ssh2_config(config.mlsc.host, username, password, 22);
        verified_connection.server_host_key_verifier = host_key_verifier;
        % Connect + authenticate now (empty command), then reuse the
        % authenticated connection for subsequent commands.
        verified_connection = ssh2(verified_connection);
        if ~(isfield(verified_connection, 'authenticated') && ...
                verified_connection.authenticated == 1)
            error('pseudo_CT:MLSCTransportRejected', ...
                ['MLSC authentication did not complete on the secure ', ...
                 'connection; no account query or submission was attempted.']);
        end
    end

    function local_require_verified()
        if ~verified
            error('pseudo_CT:MLSCTransportRejected', ...
                'MLSC transport was not verified.');
        end
    end

    function text = local_job_id_text(job_id)
        if ~isnumeric(job_id) || ~isscalar(job_id) || ~isfinite(job_id) || ...
                job_id ~= floor(job_id) || job_id < 1
            error('pseudo_CT:MLSCJobId', ...
                'A positive numeric Slurm job ID is required.');
        end
        text = num2str(job_id, '%.0f');
    end

    function text = local_job_name_text(job_name)
        if ~ischar(job_name) || isempty(job_name) || length(job_name) > 128 || ...
                isempty(regexp(job_name, '^[A-Za-z0-9_.-]+$', 'once'))
            error('pseudo_CT:MLSCJobName', ...
                'A safe MLSC correlation job name is required.');
        end
        text = job_name;
    end

    function local_cleanup()
        if ~isempty(connection)
            try
                ssh2_close(connection);
            catch
            end
        end
        connection = [];
        username = '';
        password = '';
        host_key_verifier = [];
        verified = false;
    end
end


function local_cleanup_mlsc_transport(transport)
if isstruct(transport) && isfield(transport, 'cleanup') && ...
        isa(transport.cleanup, 'function_handle')
    feval(transport.cleanup);
end
end


%% ========================================================================
%  LEGACY LAUNCHPAD BACKGROUND MASK WRAPPER
%  ========================================================================
function launchpad_apply_background_mask(temp_dir, context)
% The mode-neutral helper retains the legacy fallback that the fetched
% Launchpad attenuation map will remain unmasked when mprage_normalized.nii
% or the optional masking operation is unavailable.
pseudo_CT_apply_background_mask(temp_dir, context);
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
%CANONICAL_PROFILE_NAME Resolve exact hyphenated keys plus deprecated alias.
%   Accepts only exact hyphenated canonical keys discovered from
%   src/config/profiles plus the deprecated alias mlsc -> mlsc-legacy.
%   Underscore spellings, display labels, Launchpad and
%   near-parity names are rejected. Discovery stays non-recursive so the
%   alias creates no row.

if ~ischar(requested)
    name = '';
    return;
end
requested = strtrim(requested);
if strcmp(requested, 'mlsc')
    requested = 'mlsc-legacy';
end
name = '';
for ii = 1:length(profiles)
    if strcmp(requested, profiles(ii).name)
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
