function report = pseudo_CT_run_lifecycle(varargin)
%PSEUDO_CT_RUN_LIFECYCLE Internal run lifecycle behind pseudo_CT_orchestrate.
%   REPORT = PSEUDO_CT_RUN_LIFECYCLE(NAME, VALUE, ...) runs the subjects of one
%   profile. pseudo_CT_orchestrate calls it on submit, after validation. It is
%   not a public entry point: users call run_pseudo_CT (MATLAB frontend) or
%   bin/pseudoct, which go through pseudo_CT_orchestrate. Calling it with no
%   arguments, or without a profile, stops with run_pseudo_CT:ProfileRequired.
%   Named parameters are defined by pseudo_CT_lifecycle_arguments:
%     'profile'          - Required. A canonical profile name (local,
%                          local-mprage-only, mlsc, mlsc-mprage-only). Profiles
%                          are discovered from src/config/profiles/.
%     'subjects'         - MPRAGE filename(s) as a char or cell, or 'batch'.
%     'umap_files'       - Optional UMAP path(s) paired with subjects. Empty
%                          entries request local autodiscovery.
%     'correct_aliasing' - 0 or 1. Omit to use the profile default.
%     'recenter_before_normalization' - 0 or 1. Omit to use the profile default.
%     'cleanup_on_success' - Logical or 0/1. Omit to use the profile default
%                          (true in all current profiles). An explicit 0 keeps
%                          the subject temporary folder and its intermediates
%                          for comparison; 1 removes them after success. Never
%                          changes a profile file.
%     'mlsc_current_artifact_root' - Absolute folder of the operator-selected
%                          compiled artifact. It selects the runner and manifest
%                          paths: from source <root>/payload_build/run_pseudoct_pipeline.sh
%                          (development compiled tree, not an installed layout) with
%                          <root>/mlsc_current_build.mat and
%                          <root>/mlsc_current_resources.mat, or installed
%                          <root>/run_pseudoct_pipeline.sh (flat runtimes/<LABEL>/) with
%                          <root>/build_manifest.mat and
%                          <root>/resource_manifest.mat. Only the mlsc
%                          and mlsc-mprage-only profiles accept it.
%     'group_account', 'headless_mode', 'headless_credentials',
%     'mlsc_host_key_provider' - MLSC submit inputs. Credentials are supplied
%                          out of band and are never logged or stored in a
%                          profile. A provider selects strict pinned host-key
%                          verification.
%   Deployed invocations with arguments are parsed by parse_deployed_arguments
%   (the headless submit request).
%
%   Stages per subject, in order: input preparation, optional MLSC submission
%   and monitoring, or the local current runner (prepare, FreeSurfer
%   normalization, compute), then DICOM output and promotion of final files
%   into MR_PET (NIfTI, QC and version files) and MR/pseudo_muMAP (DICOM).
%   DICOM is written with pseudo_CT_write_mu_map_dicom only when the profile's
%   io_policy.output is 'nifti-and-dicom'; 'nifti-only' skips it.
%
%   Outputs and temporary files (subject folder <subject>/MR_PET):
%     MR_PET/              final NIfTI, QC TIFF and version text files
%     MR/pseudo_muMAP/     final DICOM pseudo-muMAP (nifti-and-dicom profiles)
%     MR_PET/tmp/          per-subject working folder for intermediates. Removed
%                          after successful promotion when cleanup_on_success is
%                          true; kept when promotion fails or cleanup is off.
%   Progress and the run log are written through pseudo_CT_output; scientific
%   and MLSC lifecycle events are appended as JSONL under MR_PET.
%
%   Side effects: creates the subject folders, writes the run log, may submit
%   and monitor MLSC Slurm jobs, runs the compiled local runner, and removes
%   temporary files on success. Errors use run_pseudo_CT:* identifiers.
%   Minimum supported MATLAB: R2010b (MATLAB 7.11). The compiled application runs
%   on MCR 7.14.
%
%   Maintained by Michele Scipioni, PhD
%   mscipioni@mgh.harvard.edu
%   Updated: July 23, 2026.

%% === 0. Resolve repo root and add config/ui to path (before any calls) ===
pathp = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(pathp, 'src', 'config'), '-begin');
addpath(fullfile(pathp, 'src', 'gui'), '-begin');
addpath(fullfile(pathp, 'src', 'io'), '-begin');
run_started = tic;
run_start_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
run_id = datestr(now, 'yyyymmdd_HHMMSS');
% Interactive means no arguments at all, deployed or not (the compiled app
% launched without arguments reaches the same selector -> runtime bind -> GUI).
interactive_gui = isempty(varargin);
report = local_empty_run_report();
headless_mode = false;
headless_credentials = struct();
group_account = '';
umap_files_arg = [];
resolved_jobs = struct([]);
% Installed MATLAB Runtime label chosen in the selector ('' otherwise).
selected_runtime = '';

% Optional runtime-only MLSC trusted host-key material/provider seam.  It is
% never a profile field, never sourced from source control, and never logged;
% it is supplied out-of-band at runtime and defaults to empty.  An empty
% provider selects the normal MLSC workflow: the existing
% username/password dialog, Ganymed password authentication, account
% discovery, and the Slurm lifecycle without any known_hosts/fingerprint
% input or authentication block.  A supplied provider selects strict pinned
% host-key verification, which fails closed on any doubt.
mlsc_host_key_provider = [];
% Public current-MLSC artifact-root override. Empty keeps profile defaults.
mlsc_current_artifact_root = '';
recenter_arg = [];
% Optional runtime-only retention override (comparison use only). Empty
% keeps the profile default; an explicit 0/1 (or logical) overrides
% config.cleanup_on_success after the profile load without editing it.
cleanup_on_success_arg = [];

%% === 1. Branch on invocation (before any argument parsing) ===
% Deployed with arguments: parse_deployed_arguments (the headless submit
% request). Otherwise the named-argument parser. Interactive selection lives in
% run_pseudo_CT (frontend); without a profile this stops with ProfileRequired.
if isdeployed && ~isempty(varargin)
    [profile_name, subjects_arg, aliasing_arg, recenter_arg, headless_mode, ...
        headless_credentials, group_account, mlsc_host_key_provider, ...
        mlsc_current_artifact_root, umap_files_arg, resolved_jobs, ...
        cleanup_on_success_arg] = ...
        parse_deployed_arguments(varargin{:});
else
    args = pseudo_CT_lifecycle_arguments(varargin{:});
    profile_name = args.profile;
    subjects_arg = args.subjects;
    aliasing_arg = args.correct_aliasing;
    recenter_arg = args.recenter_before_normalization;
    mlsc_host_key_provider = args.mlsc_host_key_provider;
    mlsc_current_artifact_root = args.mlsc_current_artifact_root;
    cleanup_on_success_arg = args.cleanup_on_success;
    headless_mode = args.headless_mode;
    headless_credentials = args.headless_credentials;
    group_account = args.group_account;
    umap_files_arg = args.umap_files;
    resolved_jobs = args.resolved_jobs;
end
selected_runtime = '';
gui_credentials = struct();

%% === Validate profile name against available profile files ===
available_profiles = pseudo_CT_list_profiles(false);
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
if headless_mode
    if ~any(strcmp(requested_profile_name, {'mlsc'; ...
            'mlsc-mprage-only'})) || ...
            ~strcmp(requested_profile_name, profile_name)
        error('run_pseudo_CT:HeadlessProfile', ...
            'Headless execution requires one exact approved remote profile.');
    end
    local_validate_headless_subjects(subjects_arg);
    if ~isstruct(headless_credentials) || numel(headless_credentials) ~= 1 || ...
            ~isfield(headless_credentials, 'username') || ...
            ~isfield(headless_credentials, 'password') || ...
            ~local_credential_text(headless_credentials.username) || ...
            ~local_credential_text(headless_credentials.password)
        error('run_pseudo_CT:HeadlessCredentials', ...
            'Headless execution requires a validated one-time credential.');
    end
    if any(strcmp(profile_name, {'mlsc'; ...
            'mlsc-mprage-only'})) && ...
            (~ischar(group_account))
        error('run_pseudo_CT:HeadlessGroupAccount', ...
            'Headless MLSC submission requires a valid group account value.');
    end
end

%% === Warning handling ===
% Suppress all warnings during processing (SPM8 generates many
% benign warnings about version compatibility, deprecated functions, and
% Java classpath conflicts). The original state is restored on exit via
% the onCleanup guard.
[orig_warn] = warning;
warning('off', 'all');
warn_cleanup = onCleanup(@() warning(orig_warn));

%% === Load the selected profile once and set up its resources ===
config = pseudo_CT_load_profile(profile_name);
report.profile = profile_name;
% Installed distributions bind one MATLAB Runtime before any override,
% validation, or subject processing: the selector's choice, else
% PSEUDOCT_RUNTIME_RELEASE, else the catalog default. Source mode is a no-op.
config = pseudo_CT_runtime_select(config, selected_runtime);
if headless_mode && isdeployed
    config.headless_execution = true;
end
% Apply explicit MLSC artifact overrides through the
% real public config path. Default (both empty) leaves the canonical
% profile unchanged; only MLSC profiles may consume overrides.
config = pseudo_CT_apply_mlsc_current_overrides(config, profile_name, ...
    mlsc_current_artifact_root);
% Runtime retention override (comparison use only): omitted keeps the
% profile default; an explicit 0/1 (or logical) overrides
% config.cleanup_on_success without changing any profile file. The
% existing downstream gates (local and the shared remote finalizer)
% already read config.cleanup_on_success, so no other change is needed.
if ~isempty(cleanup_on_success_arg)
    config.cleanup_on_success = logical(cleanup_on_success_arg);
end
if ~isempty(config.required_matlab_release) && ...
        ~strcmp(version('-release'), config.required_matlab_release)
    pseudo_CT_output('WARN', struct('scope', 'run'), ...
        'Profile %s requires MATLAB R%s; running R%s. Results may differ.', ...
        profile_name, config.required_matlab_release, version('-release'));
end
setup_pseudo_CT_paths(pathp, config);

%% === Resolved jobs: the only run input (produced by validation) ===
if isempty(resolved_jobs)
    error('pseudo_CT:ResolvedJobRequired', ...
        'Run execution requires jobs resolved by validation (validate, then submit).');
end
% A source checkout runs no application profile without an explicit development
% artifact root; the refusal precedes any subject processing.
pseudo_CT_require_application_layout(mlsc_current_artifact_root);
jobs = resolved_jobs;
collection_stats = struct('requested', length(jobs), 'skipped', 0, ...
    'skipped_subjects', {{}});
% Explicit runtime overrides also apply to GUI-collected jobs, while omitted
% values preserve each GUI control and the selected profile's defaults.
for ii = 1:length(jobs)
    if ~isempty(aliasing_arg)
        jobs(ii).correct_aliasing = logical(aliasing_arg);
    end
    if ~isempty(recenter_arg)
        jobs(ii).recenter_before_normalization = logical(recenter_arg);
    end
end

% Jobs are resolved by the orchestration API. Direct run has no separate
% full-preflight process; dependency checks remain in the execution paths.

%% === Create one persistent, owner-only run log per requested subject ===
% Log contract: <subject-root>/MR_PET/pseudoct-run-<UTC>-<invocationUUID>.log.
% Never deleted by this code, never pruned; created only after validation and
% destination resolution, so a failure before this point leaves no log.
[log_utc, log_uuid] = local_run_log_identity();
all_log_files = {};
processing_dirs = {};
for ii = 1:length(jobs)
    if ~isfield(jobs, 'processing_dir') || isempty(jobs(ii).processing_dir)
        [pathr, ~, ~] = fileparts(deblank(jobs(ii).mprage_fn));
        [processing_dir, temp_dir, save_dir] = ...
            pseudo_CT_resolve_output_dirs(pathr);
        jobs(ii).processing_dir = processing_dir;
        jobs(ii).temp_dir = temp_dir;
        jobs(ii).save_dir = save_dir;
    else
        processing_dir = jobs(ii).processing_dir;
        temp_dir = jobs(ii).temp_dir;
        save_dir = jobs(ii).save_dir;
    end
    jobs(ii).subject_started = tic;
    % The destination is trusted at this point (validated inputs plus the
    % existing resolver).  Create only MR_PET (when missing) and the single
    % owner-only run log first; tmp/ and DICOM directories follow the log.
    [jobs(ii).log_file, log_name] = local_create_run_log(processing_dir, ...
        log_utc, log_uuid);
    local_record_public_log(log_name, ii);
    local_ensure_directory(temp_dir);
    if strcmp(config.io_policy.output, 'nifti-and-dicom')
        local_ensure_directory(save_dir);
    end
    all_log_files{end + 1} = jobs(ii).log_file; %#ok<AGROW>
    processing_dirs{end + 1} = processing_dir; %#ok<AGROW>
    header_context = struct('log_file', jobs(ii).log_file, 'scope', 'run');
    % Boundary (a): the run start record, written before any pipeline or job is launched.
    % A copy carries the flags, so the header rows below stay LOG only.
    start_context = header_context;
    start_context.lifecycle = true;
    start_context.jsonl_boundary = true;
    pseudo_CT_output('INFO', start_context, 'Run log initialized.');
    local_write_log_header(header_context, profile_name, config.mode, ...
        jobs(ii).mprage_fn, run_start_time, processing_dir, temp_dir);
end
for ii = 1:length(collection_stats.skipped_subjects)
    skipped_input = collection_stats.skipped_subjects{ii};
    [pathr, ~, ~] = fileparts(deblank(skipped_input));
    [processing_dir, temp_dir, ~] = pseudo_CT_resolve_output_dirs(pathr);
    skipped_log = fullfile(processing_dir, ...
        sprintf('pseudoct-run-%s-%s.log', log_utc, log_uuid));
    if ~any(strcmp(skipped_log, all_log_files))
        % A destination already logged by this run is reused, never reopened.
        [skipped_log, ~] = local_create_run_log(processing_dir, log_utc, log_uuid);
    end
    all_log_files{end + 1} = skipped_log; %#ok<AGROW>
    processing_dirs{end + 1} = processing_dir; %#ok<AGROW>
    context = struct('log_file', skipped_log, 'scope', 'subject');
    local_write_log_header(context, profile_name, config.mode, skipped_input, ...
        run_start_time, processing_dir, temp_dir);
    pseudo_CT_output('WARN', context, 'Subject skipped because no UMAP reference was found.');
    pseudo_CT_output('INFO', context, '    %s', skipped_input);
end
run_context = struct('log_files', {all_log_files}, 'scope', 'run');
run_context.console_profile = profile_name;
run_context.console_run_id = run_id;
run_context.console_subject_count = collection_stats.requested;
run_context.console_release = version('-release');
run_context.console_started_at = run_start_time;
run_context.stage_map = pseudo_CT_stage_map(config);
if strcmp(config.io_policy.output, 'nifti-only')
    run_context.console_output = 'NIfTI';
elseif strcmp(config.io_policy.output, 'dicom-only')
    run_context.console_output = 'DICOM';
else
    run_context.console_output = 'NIfTI+DICOM';
end
mlsc_context = struct('log_files', {all_log_files}, 'scope', 'mlsc');
% The MLSC auth/account rows use the same presenter identity as the run so
% they are formatted as table rows (not raw text) with the contract fields.
mlsc_context.console_profile = run_context.console_profile;
mlsc_context.console_run_id = run_context.console_run_id;
mlsc_context.console_subject_count = run_context.console_subject_count;
mlsc_context.console_release = run_context.console_release;
mlsc_context.console_started_at = run_context.console_started_at;
mlsc_context.console_output = run_context.console_output;
mlsc_context.stage_map = run_context.stage_map;
pseudo_CT_output('INFO', run_context, 'Profile: %s; mode: %s; MATLAB: %s.', ...
    profile_name, config.mode, version);
% Preserve summaries for skipped subjects as well as jobs, then refresh each
% processable subject's file with that job's effective requested options.
pseudo_CT_print_profile_summary(profile_name, config, processing_dirs, run_context);
if ~isempty(jobs)
    for ii = 1:length(jobs)
        requested_options = struct( ...
            'correct_aliasing', jobs(ii).correct_aliasing, ...
            'recenter_before_normalization', ...
            jobs(ii).recenter_before_normalization);
        pseudo_CT_print_profile_summary(profile_name, config, ...
            jobs(ii).processing_dir, run_context, requested_options);
    end
end
if isempty(jobs)
    report.run_status = 'no_jobs';
    clear headless_credentials gui_credentials
    pseudo_CT_output('WARN', run_context, ...
        ['Run completed: requested %d, started 0, succeeded 0, failed 0, ', ...
         'skipped %d (elapsed %s).'], collection_stats.requested, ...
        collection_stats.skipped, local_elapsed(toc(run_started)));
    return;
end

%% === Dispatch by configured execution mode ===
report.run_status = 'running';
num_success = 0;
num_failed = 0;
num_started = length(jobs);

switch config.mode

    case 'mlsc'
        % ============================================================
        % MLSC/SLURM EXECUTION PATH
        % ============================================================
        report.authentication_status = 'not_attempted';
        report.account_status = 'not_attempted';
        report.preflight_status = 'not_attempted';
        num_started = 0;
        for ii = 1:length(jobs)
            context = local_subject_context(jobs(ii), ii, length(jobs));
            context.stage_map = pseudo_CT_stage_map(config);
            context.console_profile = profile_name;
            % Remote converter detail is kept in the subject log only. The
            % context carries no stage fields: the converter prints no numbered row.
            converter_context = context;
            converter_context.console_detail_remote = true;
            jobs(ii).seed_nii = pseudo_CT_prepare_input(jobs(ii).mprage_fn, ...
                fullfile(jobs(ii).temp_dir, 'mprage.nii'), converter_context, ...
                'mlsc-lifecycle');
            % Show the manager's stage 1 record before any submission.
            pseudo_CT_present_native_events(context, true);
        end

        account = '';
        mlsc_cancelled = false;
        if headless_mode
            PASSWORD = headless_credentials.password;
            USERNAME = headless_credentials.username;
        elseif ~isempty(fieldnames(gui_credentials))
            if ~isfield(gui_credentials, 'username') || ...
                    ~isfield(gui_credentials, 'password')
                error('run_pseudo_CT:GuiCredentialHandoff', ...
                    'The GUI authentication handoff is incomplete.');
            end
            PASSWORD = gui_credentials.password;
            USERNAME = gui_credentials.username;
            clear gui_credentials
        else
            [PASSWORD, USERNAME] = pseudo_CT_password_entry_dialog('enterUserName', true, ...
                'ValidatePassword', true, 'PasswordLengthMax', 50, ...
                'WindowName', sprintf('Login for: %s', config.mlsc.host));
        end
        if isequal(PASSWORD, -1) || isempty(USERNAME)
            clear USERNAME PASSWORD
            num_started = 0;
            mlsc_cancelled = true;
            report.authentication_status = 'not_attempted';
        else
            % GUI and one-shot headless credentials share this initializer.
            % Its verified transport is retained through submission and
            % monitoring; mlsc_backend's repeated verify is idempotent.
            session = mlsc_initialize_backend_session(config, USERNAME, ...
                PASSWORD, mlsc_host_key_provider, group_account, false);
            transport = session.transport;
            transport_cleanup = onCleanup(@() local_cleanup_mlsc_transport(transport));
            clear USERNAME PASSWORD
            clear headless_credentials

            report.authentication_status = session.authentication_status;
            report.account_status = session.account_status;
            report.preflight_status = session.preflight_status;
            report.error_code = session.error_code;
            report.error_message = session.error_message;
            if ~strcmp(session.authentication_status, 'authenticated')
                pseudo_CT_output('ERROR', run_context, ...
                    ['MLSC secure transport verification failed; no ', ...
                     'account query or submission was attempted.']);
                pseudo_CT_output('ERROR', run_context, ...
                    'MLSC transport diagnostic: %s', session.error_message);
                num_started = 0;
                num_failed = length(jobs);
                account = '';
            else
                pseudo_CT_output('SUCCESS', mlsc_context, ...
                    'MLSC connection and authentication succeeded.');
                pseudo_CT_output('INFO', mlsc_context, ...
                    'Discovered %d Slurm account(s).', length(session.accounts));
                account = session.selected_account;
                if ~isempty(account)
                    report.selected_account = account;
                    pseudo_CT_output('INFO', mlsc_context, ...
                        'Selected MLSC account %s.', account);
                else
                    if strcmp(session.error_code, 'NO_ACCOUNTS')
                        pseudo_CT_output('ERROR', run_context, ...
                            ['No Slurm account is available for the authenticated ', ...
                             'MLSC user; no job was submitted.']);
                    end
                    num_started = 0;
                    num_failed = length(jobs);
                    account = '';
                end
            end
        end
        if ~isempty(account)
            if exist('transport', 'var') ~= 1
                error('run_pseudo_CT:MLSCTransportRequired', ...
                    'MLSC account selection requires an authenticated transport.');
            end
                for ii = 1:length(jobs)
                    % Stage rows are shown only from the native event file: stage 1
                    % (input) above, stages 2-8 from the one pipeline invocation
                    % (drained by mlsc_lifecycle), and stages 9-10 (finalization)
                    % below. This block adds no numbered row.
                    % Guard: one subject-scoped terminal line per subject (see local path).
                    outcome_context = local_subject_context(jobs(ii), ii, length(jobs));
                    outcome_context.console_profile = profile_name;
                    outcome = pseudo_CT_subject_outcome( ...
                        outcome_context, jobs(ii).subject_started);
                    guard = onCleanup(@() pseudo_CT_subject_outcome.release(outcome));
                    context = local_subject_context(jobs(ii), ii, length(jobs));
                    output_context = local_subject_context(jobs(ii), ii, length(jobs));
                    context.stage_map = pseudo_CT_stage_map(config);
                    output_context.stage_map = context.stage_map;
                    context.console_profile = profile_name;
                    output_context.console_profile = profile_name;
                    runtime = struct('profile', profile_name, 'account', account, ...
                        'script_path', fullfile(jobs(ii).temp_dir, ...
                        sprintf('.pseudo_CT_mlsc_%s_%d.sh', run_id, ii)), ...
                        'evidence_dir', jobs(ii).processing_dir, ...
                        'log_archive_dir', jobs(ii).processing_dir, ...
                        'cleanup_script', true, 'output_context', output_context);
                    subject = struct('subject_id', jobs(ii).mprage_fn, ...
                        'shared_input', jobs(ii).seed_nii, ...
                        'shared_temp', jobs(ii).temp_dir);
                    % Credential-free per-job alias/recenter overrides travel
                    % in the subject so the job manifest carries the
                    % effective overrides (never profile defaults).
                    subject.check_aliasing = jobs(ii).correct_aliasing;
                    subject.recenter_before_normalization = ...
                        jobs(ii).recenter_before_normalization;
                    lifecycle = struct();
                    try
                        lifecycle = mlsc_lifecycle(subject, config, runtime, transport);
                        if lifecycle.submitted
                            num_started = num_started + 1;
                        end
                        mlsc_job_id = local_mlsc_job_id(lifecycle);
                        if mlsc_job_id > 0
                            report.job_ids(end + 1) = mlsc_job_id; %#ok<AGROW>
                            report.submission_status = 'accepted';
                            context.job_number = mlsc_job_id;
                        elseif isfield(lifecycle, 'submission_attempted') && ...
                                isequal(lifecycle.submission_attempted, true)
                            if isfield(lifecycle, 'submission_outcome') && ...
                                    ischar(lifecycle.submission_outcome) && ...
                                    strcmp(lifecycle.submission_outcome, 'rejected')
                                report.submission_status = 'rejected';
                            else
                                report.submission_status = 'unresolved';
                            end
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
                            if local_mlsc_summary_evidence_ready(lifecycle)
                                pseudo_CT_print_profile_summary(profile_name, ...
                                    config, jobs(ii).processing_dir, context, ...
                                    local_job_summary_options(jobs(ii)), lifecycle);
                            end
                            pseudo_CT_output('ERROR', context, ...
                                'Subject failed before local finalization: %s', failure_detail);
                            if ~(isfield(lifecycle, 'terminal') && ...
                                    isequal(lifecycle.terminal, true))
                                % Job state not observed terminal: a remote writer
                                % may still be appending, so no native terminal line.
                                outcome.markClosed();
                            elseif isfield(lifecycle, 'cancel_requested') && ...
                                    isequal(lifecycle.cancel_requested, true)
                                outcome.markClosed('CANCELLED', 'mlsc-lifecycle');
                            else
                                outcome.markClosed('FAILED', 'mlsc-lifecycle');
                            end
                            if isfield(lifecycle, 'terminal') && ...
                                    isequal(lifecycle.terminal, true)
                                if pseudo_CT_completion_failure_observed(lifecycle)
                                    report.completion_status = 'failed';
                                end
                            end
                            num_failed = num_failed + 1;
                            clear guard
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
                        finalization_context = local_subject_context(jobs(ii), ...
                            ii, length(jobs));
                        finalization_context = local_attach_mlsc_job( ...
                            finalization_context, mlsc_job_id);
                        finalization_context.console_profile = profile_name;
                        finalization_context.stage_map = pseudo_CT_stage_map(config);
                        [finalization_success, finalization_detail] = ...
                            pseudo_CT_finalize_subject(jobs(ii), ...
                            fullfile(jobs(ii).temp_dir, 'att_map.nii'), ...
                            jobs(ii).temp_dir, jobs(ii).seed_nii, config, ...
                            finalization_context, 'mlsc-lifecycle');
                        % Stages 9-10 are shown from their native records after finalization.
                        pseudo_CT_present_native_events(finalization_context, true);
                        if finalization_success
                            final_context = local_attach_mlsc_job( ...
                                local_subject_context(jobs(ii), ii, length(jobs)), ...
                                mlsc_job_id);
                            final_context.completion_verified = true;
                            pseudo_CT_output('SUCCESS', final_context, ...
                                'Subject completed (elapsed %s).', ...
                                local_elapsed(toc(jobs(ii).subject_started)));
                        elseif isempty(finalization_detail)
                            local_log_subject_failure(jobs(ii), context);
                        else
                            local_log_remote_failure(jobs(ii), context, ...
                                finalization_detail);
                        end
                        lifecycle = mlsc_record_finalization(lifecycle, runtime, ...
                            true, logical(finalization_success), ...
                            local_finalization_detail(finalization_success));
                        if finalization_success
                            outcome.markClosed('SUCCEEDED', 'mlsc-lifecycle');
                        else
                            outcome.markClosed('FAILED', 'mlsc-lifecycle');
                        end
                        if local_mlsc_summary_evidence_ready(lifecycle)
                            pseudo_CT_print_profile_summary(profile_name, ...
                                config, jobs(ii).processing_dir, context, ...
                                local_job_summary_options(jobs(ii)), lifecycle);
                        end
                        if lifecycle.finalization_evidence_save_failed
                            pseudo_CT_output('ERROR', context, ...
                                'MLSC finalization evidence could not be saved.');
                        end
                        if finalization_success
                            num_success = num_success + 1;
                        else
                            num_failed = num_failed + 1;
                            report.completion_status = 'failed';
                        end
                    catch ME
                        if exist('lifecycle', 'var') == 1 && ...
                                isstruct(lifecycle) && isfield(lifecycle, 'terminal')
                            lifecycle = mlsc_record_finalization(lifecycle, runtime, ...
                                true, false, ...
                                'Local MLSC finalization raised an error.');
                            if pseudo_CT_completion_failure_observed(lifecycle)
                                report.completion_status = 'failed';
                            end
                            if local_mlsc_summary_evidence_ready(lifecycle)
                                pseudo_CT_print_profile_summary(profile_name, ...
                                    config, jobs(ii).processing_dir, context, ...
                                    local_job_summary_options(jobs(ii)), lifecycle);
                            end
                        end
                        pseudo_CT_output('ERROR', context, ...
                            'Subject failed; see non-secret MLSC evidence (elapsed %s).', ...
                            local_elapsed(toc(jobs(ii).subject_started)));
                        if exist('lifecycle', 'var') == 1 && isstruct(lifecycle) && ...
                                isfield(lifecycle, 'terminal') && ...
                                isequal(lifecycle.terminal, true)
                            outcome.markClosed('FAILED', 'mlsc-lifecycle');
                        else
                            % Exception before the job was observed terminal: a
                            % remote writer may still append, so no native line.
                            outcome.markClosed();
                        end
                        num_failed = num_failed + 1;
                    end
                    clear guard
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
            % Guard: writes one subject-scoped ERROR if this iteration exits
            % without a closed outcome. The propagating error is not altered.
            outcome_context = local_subject_context(jobs(jj), jj, length(jobs));
            outcome_context.console_profile = profile_name;
            outcome = pseudo_CT_subject_outcome( ...
                outcome_context, jobs(jj).subject_started);
            guard = onCleanup(@() pseudo_CT_subject_outcome.release(outcome));
            try
                subject_success = local_run_subject(jobs(jj), ...
                    show_subject_dialog, profile_name, config, jj, length(jobs));
                if subject_success
                    num_success = num_success + 1;
                else
                    context = local_subject_context(jobs(jj), jj, length(jobs));
                    pseudo_CT_output('ERROR', context, 'Subject failed (elapsed %s).', ...
                        local_elapsed(toc(jobs(jj).subject_started)));
                    num_failed = num_failed + 1;
                end
                if subject_success
                    outcome.markClosed('SUCCEEDED', 'local-orchestrator');
                else
                    outcome.markClosed('FAILED', 'local-orchestrator');
                end
            catch ME
                context = local_subject_context(jobs(jj), jj, length(jobs));
                pseudo_CT_output('ERROR', context, 'Subject failed: %s (elapsed %s).', ...
                    ME.message, local_elapsed(toc(jobs(jj).subject_started)));
                outcome.markClosed('FAILED', 'local-orchestrator');
                num_failed = num_failed + 1;
            end
            clear guard
        end

    otherwise
        % ============================================================
        % Unsupported execution mode
        % ============================================================
        error('run_pseudo_CT:UnsupportedMode', ...
            'Unsupported execution mode: %s.', config.mode);
end

if strcmp(config.mode, 'local')
    if num_failed > 0
        report.completion_status = 'failed';
    elseif num_success > 0 && num_success == length(jobs)
        report.completion_status = 'completed';
    end
elseif num_success > 0 && num_success == length(jobs)
    report.completion_status = 'completed';
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
report.run_status = 'returned';
clear headless_credentials PASSWORD USERNAME gui_credentials

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
function success = local_run_subject(job, ...
    show_dialog, profile_name, config, subject_index, subject_count)

success = 0;
context = local_subject_context(job, subject_index, subject_count);
context.console_profile = profile_name;
context.stage_map = pseudo_CT_stage_map(config);
if context.stage_map.total > 0
    context.public_stage_total = context.stage_map.total;
end
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
            pseudo_CT_output('ERROR', context, 'Could not create directory: %s', msg);
            pseudo_CT_output('INFO', context, '    %s', dir_list{ii});
            return;
        end
    end
end

% Prepare the manager-owned NIfTI input (convert DICOM or copy NIfTI input).
P = pseudo_CT_prepare_input(job.mprage_fn, fullfile(temp_dir, 'mprage.nii'), ...
    context, 'local-orchestrator');
% Show the manager's stage 1 record before the pipeline starts.
pseudo_CT_present_native_events(context, ...
    strcmp(getenv('PSEUDOCT_CLI_OUTPUT'), '1'));

[temp_working_dir, ~, ~] = fileparts(deblank(P));

% Run the pseudo-CT code. The compiled pipeline runs stages 2-8 once for this
% subject; FreeSurfer normalization is inside it, as on MLSC.
Pf = pseudo_CT_run_local_current_subject(P, temp_dir, config, ...
    job.correct_aliasing, job.recenter_before_normalization, context);
if ~ischar(Pf) || isempty(strtrim(Pf))
    pseudo_CT_output('ERROR', context, 'Processing stopped before atlas outputs were generated.');
    return;
end

% Finalize only after the local pipeline runner has verified its outputs.
[temp_working_dir, ~, ~] = fileparts(deblank(Pf(end, :)));
finalization_job = job;
finalization_job.processing_dir = processing_dir;
finalization_job.temp_dir = temp_dir;
finalization_job.save_dir = save_dir;
[success, ~] = pseudo_CT_finalize_subject(finalization_job, ...
    fullfile(temp_working_dir, 'att_map.nii'), temp_working_dir, P, ...
    config, context, 'local-orchestrator');
% Stages 9-10 are shown from their native records after finalization.
pseudo_CT_present_native_events(context, ...
    strcmp(getenv('PSEUDOCT_CLI_OUTPUT'), '1'));
if ~success
    return;
end

if show_dialog && ~isdeployed
    warndlg('Pseudo-CT processing completed.', 'Pseudo-CT completed');
end

success = 1;
completion_context = local_subject_context(job, subject_index, subject_count);
completion_context.completion_verified = true;
pseudo_CT_output('SUCCESS', completion_context, ...
    'Subject completed (elapsed %s).', local_elapsed(toc(subject_started)));

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


% MLSC transport construction lives in src/backends/mlsc/mlsc_credentials_transport.m
% (shared with the sixth comparison command; extracted verbatim, same behavior).


function local_cleanup_mlsc_transport(transport)
if isstruct(transport) && isfield(transport, 'cleanup') && ...
        isa(transport.cleanup, 'function_handle')
    feval(transport.cleanup);
end
end


function context = local_subject_context(job, subject_index, subject_count)
context = struct('log_file', job.log_file, 'subject_index', subject_index, ...
    'subject_count', subject_count, 'scope', 'subject');
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


function [utc_stamp, uuid] = local_run_log_identity()
%LOCAL_RUN_LOG_IDENTITY UTC stamp and invocation UUID for the run-log name.
%   The CLI exports its invocation UUID; direct MATLAB callers get a fresh one.
[status, out] = system('date -u +%Y%m%dT%H%M%SZ');
utc_stamp = strtrim(out);
if status ~= 0 || isempty(regexp(utc_stamp, '^\d{8}T\d{6}Z$', 'once'))
    error('pseudo_CT:RunLogIdentityFailed', ...
        'The run-log timestamp could not be established; no processing was started.');
end
uuid = lower(strtrim(getenv('PSEUDOCT_CLI_INVOCATION_ID')));
if isempty(regexp(uuid, ...
        '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$', 'once'))
    uuid = lower(char(java.util.UUID.randomUUID().toString()));
end
end


function [log_file, log_name] = local_create_run_log(processing_dir, utc_stamp, uuid)
%LOCAL_CREATE_RUN_LOG Exclusively create the owner-only run log.
%   A missing MR_PET is created 0700 (an existing one keeps its mode).  The
%   file is created 0600 with noclobber (O_EXCL), so an existing file or
%   symlink is never overwritten or followed.  No fallback location exists;
%   failure messages carry no filesystem path.
log_name = sprintf('pseudoct-run-%s-%s.log', utc_stamp, uuid);
log_file = fullfile(processing_dir, log_name);
failure_message = ['The per-run log could not be created in the subject ', ...
    'MR_PET directory; no processing was started.'];
if exist(processing_dir, 'dir') ~= 7
    status = system(sprintf('umask 077 && mkdir -- %s >/dev/null 2>&1', ...
        local_shell_quote(processing_dir)));
    if status ~= 0 && exist(processing_dir, 'dir') ~= 7
        error('pseudo_CT:RunLogCreateFailed', '%s', failure_message);
    end
end
quoted = local_shell_quote(log_file);
status = system(sprintf(['exec 2>/dev/null; umask 077 && set -C && : > %s && chmod 600 %s && ', ...
    '[ -f %s ] && [ ! -L %s ]'], quoted, quoted, quoted, quoted));
if status ~= 0
    error('pseudo_CT:RunLogCreateFailed', '%s', failure_message);
end
end


function quoted = local_shell_quote(text)
quoted = ['''' strrep(text, '''', '''\''''') ''''];
end


function local_record_public_log(log_name, subject_index)
%LOCAL_RECORD_PUBLIC_LOG Publish only the relative MR_PET log path.
%   Detailed paths stay inside the subject's own log.  The CLI exports a
%   private index file; direct MATLAB callers just see the relative line.
relative_path = ['MR_PET/' log_name];
index_file = getenv('PSEUDOCT_CLI_LOG_INDEX');
if ~isempty(index_file)
    fid = fopen(index_file, 'a');
    if fid ~= -1
        fprintf(fid, '%d\t%s\n', subject_index, relative_path);
        fclose(fid);
    end
end
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
%CANONICAL_PROFILE_NAME Resolve exact hyphenated keys discovered from profiles.
%   Accepts only exact hyphenated canonical keys discovered from
%   src/config/profiles. Underscore spellings and display labels are rejected.

if ~ischar(requested)
    name = '';
    return;
end
requested = strtrim(requested);
name = '';
for ii = 1:length(profiles)
    if strcmp(requested, profiles(ii).name)
        name = profiles(ii).name;
        return;
    end
end
end


function [profile_name, subjects_arg, aliasing_arg, recenter_arg, headless_mode, ...
        headless_credentials, group_account, host_key_provider, ...
        artifact_root, umap_files_arg, resolved_jobs, cleanup_on_success_arg] = ...
    parse_deployed_arguments(varargin)
%PARSE_DEPLOYED_ARGUMENTS Require an explicit profile in deployed mode.

subjects_arg = '';
aliasing_arg = [];
recenter_arg = [];
headless_mode = false;
headless_credentials = struct();
group_account = '';
host_key_provider = [];
artifact_root = '';
umap_files_arg = [];
resolved_jobs = struct([]);
cleanup_on_success_arg = [];

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

args = pseudo_CT_lifecycle_arguments(varargin{:});
profile_name = args.profile;
subjects_arg = args.subjects;
aliasing_arg = args.correct_aliasing;
recenter_arg = args.recenter_before_normalization;
host_key_provider = args.mlsc_host_key_provider;
artifact_root = args.mlsc_current_artifact_root;
headless_mode = args.headless_mode;
headless_credentials = args.headless_credentials;
group_account = args.group_account;
umap_files_arg = args.umap_files;
resolved_jobs = args.resolved_jobs;
cleanup_on_success_arg = args.cleanup_on_success;
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
     'or execution_profile. Silent local fallback is disabled.']);
end

function options = local_job_summary_options(job)
options = struct();
if isfield(job, 'correct_aliasing')
    options.correct_aliasing = job.correct_aliasing;
end
if isfield(job, 'recenter_before_normalization')
    options.recenter_before_normalization = ...
        job.recenter_before_normalization;
end
end

function ready = local_mlsc_summary_evidence_ready(lifecycle)
ready = isstruct(lifecycle) && numel(lifecycle) == 1 && ...
    isfield(lifecycle, 'terminal') && isequal(lifecycle.terminal, true) && ...
    isfield(lifecycle, 'evidence') && isstruct(lifecycle.evidence) && ...
    isfield(lifecycle, 'finalization_evidence_save_failed') && ...
    isequal(lifecycle.finalization_evidence_save_failed, false);
end

function report = local_empty_run_report()
report = struct();
report.schema = 'pseudo-CT.run-report/v1';
report.profile = '';
report.run_status = 'not_started';
report.authentication_status = 'not_attempted';
report.account_status = 'not_attempted';
report.preflight_status = 'not_attempted';
report.selected_account = '';
report.error_code = '';
report.error_message = '';
report.submission_status = 'not_attempted';
report.job_ids = [];
report.completion_status = 'not_observed';
report.warnings = struct('code', {}, 'message', {}, 'profile', {}, ...
    'requested_correct_aliasing', {}, ...
    'requested_recenter_before_normalization', {}, ...
    'effective_behavior', {}, 'reason', {});
end

function local_validate_headless_subjects(subjects)
if ischar(subjects)
    if size(subjects, 1) ~= 1
        error('run_pseudo_CT:HeadlessSubjects', ...
            'Headless execution requires explicit subject file paths.');
    end
    subjects = {subjects};
end
if ~iscell(subjects) || isempty(subjects)
    error('run_pseudo_CT:HeadlessSubjects', ...
        'Headless execution requires explicit subject file paths.');
end
for ii = 1:length(subjects)
    if ~ischar(subjects{ii}) || size(subjects{ii}, 1) ~= 1 || ...
            isempty(strtrim(subjects{ii})) || ...
            strcmpi(strtrim(subjects{ii}), 'batch') || ...
            any(subjects{ii} == char(0)) || ...
            exist(subjects{ii}, 'file') ~= 2
        error('run_pseudo_CT:HeadlessSubjects', ...
            'Headless subject entries must name existing input files.');
    end
end
end

function valid = local_credential_text(value)
valid = ischar(value) && size(value, 1) == 1 && ...
    ~isempty(value) && ~any(value == char(0));
end

function authenticated = local_connection_authenticated(connection)
authenticated = false;
try
    authenticated = isstruct(connection) && ...
        isfield(connection, 'authenticated') && ...
        isequal(connection.authenticated, 1);
catch %#ok<CTCH>
    authenticated = false;
end
end

function job_ids = local_valid_job_ids(values)
job_ids = [];
try
    if isnumeric(values)
        values = double(values(:)');
        valid = isfinite(values) & values >= 1 & values == floor(values);
        job_ids = values(valid);
    end
catch %#ok<CTCH>
    job_ids = [];
end
end

function verified = local_mlsc_copyback_verified(lifecycle)
%LOCAL_MLSC_COPYBACK_VERIFIED Return only explicit copy-back verification.
try
    verified = isstruct(lifecycle) && isscalar(lifecycle) && ...
        isfield(lifecycle, 'copy_back') && ...
        isstruct(lifecycle.copy_back) && ...
        isfield(lifecycle.copy_back, 'verified') && ...
        isequal(lifecycle.copy_back.verified, true);
catch %#ok<CTCH>
    verified = false;
end
end
