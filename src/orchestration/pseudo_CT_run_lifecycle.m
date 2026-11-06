function report = pseudo_CT_run_lifecycle(varargin)
%PSEUDO_CT_RUN_LIFECYCLE Existing workflow lifecycle behind public dispatch.
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
%     'umap_files'       - Optional UMAP path or positionally paired cell
%                          array; empty entries request local autodiscovery.
%     'group_account'    - Optional MLSC group/account name selected at submit.
%     'correct_aliasing' - 0 or 1 to override the profile's
%                          anti-aliasing default. Omit to use the profile
%                          default.
%     'recenter_before_normalization'
%                        - 0 or 1 to override the profile's recentering
%                          default. Omit to use the profile default.
%     'cleanup_on_success' - 0 or 1 (or logical) to override the profile's
%                          cleanup_on_success default at runtime. Omit to
%                          keep the profile default. Explicit 0 retains the
%                          temporary working directory and retrievable
%                          intermediates for comparison; explicit 1 removes
%                          them on success. Never changes any profile file.
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
%   The artifact root selects runner/build/resource manifest paths. Artifact
%   checks recompute content hashes and validate runtime identity; wrong or
%   incomplete paths fail closed. MCR_ROOT remains pinned by the current
%   artifact contract and is never overridden.
%
%   Profiles are auto-discovered from src/config/profiles/. Each .m
%   file in that directory defines one execution profile. To add a new
%   profile, add a new .m file to that directory.
%
%   Examples:
%       run_pseudo_CT()
%       run_pseudo_CT('profile', 'local-current')
%       run_pseudo_CT('profile', 'mlsc-current', 'subjects', 'batch')
%       run_pseudo_CT('profile', 'local-current', 'subjects', subject_list, ...
%                     'correct_aliasing', 0)
%       run_pseudo_CT('profile', 'local-current', 'subjects', subject_list, ...
%                     'recenter_before_normalization', 0)
%       run_pseudo_CT('profile', 'mlsc-current', ...
%                     'mlsc_current_artifact_root', '/path/to/artifact')
%
%   RUN_PSEUDO_CT(DEFAULTS_MAT) is supported only in deployed mode.
%   DEFAULTS_MAT should point to a MAT file containing the defaults
%   structure expected by the compiled application (profile_name, profile,
%   or execution_profile must name the canonical profile).
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
pathp = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(fullfile(pathp, 'src', 'config'), '-begin');
addpath(fullfile(pathp, 'src', 'gui'), '-begin');
addpath(fullfile(pathp, 'src', 'io'), '-begin');
run_started = tic;
run_start_time = datestr(now, 'yyyy-mm-dd HH:MM:SS');
run_id = datestr(now, 'yyyymmdd_HHMMSS');
interactive_gui = ~isdeployed && isempty(varargin);
report = local_empty_run_report();
headless_mode = false;
headless_credentials = struct();
group_account = '';
umap_files_arg = [];
resolved_jobs = struct([]);

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

%% === 1. Handle deployed mode (before any argument parsing) ===
if isdeployed
    [profile_name, subjects_arg, aliasing_arg, recenter_arg, headless_mode, ...
        headless_credentials, group_account, mlsc_host_key_provider, ...
        mlsc_current_artifact_root, umap_files_arg, resolved_jobs] = ...
        parse_deployed_arguments(varargin{:});

    %% === Interactive mode (no args): show profile selector ===
elseif isempty(varargin)
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
    p.addParamValue('umap_files', [], @(x) isempty(x) || ischar(x) || iscell(x));
    p.addParamValue('resolved_jobs', struct([]), @(x) isstruct(x));
    p.addParamValue('correct_aliasing', [], ...
        @(x) isempty(x) || ((isnumeric(x) || islogical(x)) && ...
        isscalar(x) && ismember(double(x), [0 1])));
    p.addParamValue('recenter_before_normalization', [], ...
        @(x) isempty(x) || ((isnumeric(x) || islogical(x)) && ...
        isscalar(x) && ismember(double(x), [0 1])));
    % Optional runtime retention override for profile comparison. Omitted
    % keeps the profile default; an explicit 0/1 (or scalar logical)
    % overrides config.cleanup_on_success after the profile load.
    p.addParamValue('cleanup_on_success', [], ...
        @(x) isempty(x) || (islogical(x) && isscalar(x)) || ...
        (isnumeric(x) && isscalar(x) && ismember(x, [0 1])));
    % Optional, out-of-band MLSC trusted host-key material/provider.  Accepts a
    % character known_hosts record or a zero-argument function handle returning
    % one; it is never read from a profile and never logged.  Empty (default)
    % selects the password-authentication workflow; a supplied
    % value selects strict pinned host-key verification.
    p.addParamValue('mlsc_host_key_provider', [], ...
        @(x) isempty(x) || ischar(x) || isa(x, 'function_handle'));
    % Explicit operator-selected current-MLSC artifact-root override.
    p.addParamValue('mlsc_current_artifact_root', '', @(x) ischar(x));
    p.addParamValue('headless_mode', false, ...
        @(x) islogical(x) && isscalar(x));
    p.addParamValue('headless_credentials', struct(), ...
        @(x) isstruct(x) && numel(x) == 1);
    p.addParamValue('group_account', '', @(x) ischar(x));
    p.parse(varargin{:});

    profile_name = p.Results.profile;
    subjects_arg = p.Results.subjects;
    aliasing_arg = p.Results.correct_aliasing;
    recenter_arg = p.Results.recenter_before_normalization;
    mlsc_host_key_provider = p.Results.mlsc_host_key_provider;
    mlsc_current_artifact_root = p.Results.mlsc_current_artifact_root;
    cleanup_on_success_arg = p.Results.cleanup_on_success;
    headless_mode = p.Results.headless_mode;
    headless_credentials = p.Results.headless_credentials;
    group_account = p.Results.group_account;
    umap_files_arg = p.Results.umap_files;
    resolved_jobs = p.Results.resolved_jobs;
end
gui_cleanup_on_success = [];
gui_handoff = struct('credentials', struct(), 'group_account', '');
gui_credentials = struct();

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
if headless_mode
    if ~any(strcmp(requested_profile_name, {'mlsc-current'; ...
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
    if any(strcmp(profile_name, {'mlsc-current'; ...
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
config = pseudo_CT_load_profile(profile_name, fullfile(pathp, 'src', 'config'));
report.profile = profile_name;
if headless_mode && isdeployed
    % collect_jobs retains deployed defaults-MAT behavior and accepts an
    % explicit subject list only for this opt-in headless execution path.
    config.headless_execution = true;
end
% T009 Option A: apply explicit mlsc-current artifact overrides through the
% real public config path. Default (both empty) leaves the canonical
% /usr/pubsw profile unchanged; only mlsc-current may consume overrides.
config = pseudo_CT_apply_mlsc_current_overrides(config, profile_name, ...
    mlsc_current_artifact_root);
% Runtime retention override (comparison use only): omitted keeps the
% profile default; an explicit 0/1 (or logical) overrides
% config.cleanup_on_success without changing any profile file. The
% existing downstream gates (local-current and the shared remote finalizer)
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

%% === Collect jobs ===
if ~isempty(resolved_jobs)
    jobs = resolved_jobs;
    collection_stats = struct('requested', length(jobs), 'skipped', 0, ...
        'skipped_subjects', {{}});
elseif isempty(subjects_arg)
    [jobs, collection_stats, gui_cleanup_on_success, gui_handoff] = ...
        collect_jobs(config);
elseif ischar(subjects_arg) && size(subjects_arg, 1) == 1 && ...
       strcmpi(strtrim(subjects_arg), 'batch')
    [jobs, collection_stats] = collect_jobs(config, 'batch', ...
        aliasing_arg, recenter_arg);
else
    [jobs, collection_stats] = collect_jobs(config, subjects_arg, ...
        aliasing_arg, recenter_arg, umap_files_arg);
end
if isempty(cleanup_on_success_arg) && ~isempty(gui_cleanup_on_success)
    config.cleanup_on_success = logical(gui_cleanup_on_success);
end
if isstruct(gui_handoff) && isfield(gui_handoff, 'credentials') && ...
        isstruct(gui_handoff.credentials)
    gui_credentials = gui_handoff.credentials;
end
if isempty(group_account) && isstruct(gui_handoff) && ...
        isfield(gui_handoff, 'group_account') && ...
        ischar(gui_handoff.group_account)
    group_account = gui_handoff.group_account;
end
clear gui_handoff
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

% Repeat local-only checks immediately before output/log setup and before any
% processing, authentication, or scheduler work. The MLSC lifecycle performs
% its existing execution-time artifact check again immediately before submit.
validation_request = struct();
validation_request.profile = profile_name;
validation_request.config = config;
validation_request.subjects = {jobs.mprage_fn};
validation_request.umap_files = {jobs.umap_fn};
if isfield(config, 'cleanup_on_success')
    validation_request.cleanup_on_success = config.cleanup_on_success;
end
if ~isempty(jobs)
    validation_request.correct_aliasing = jobs(1).correct_aliasing;
    validation_request.recenter_before_normalization = ...
        jobs(1).recenter_before_normalization;
end
pseudo_CT_orchestrate('validate', validation_request);

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
    pseudo_CT_output('INFO', header_context, 'Run log initialized.');
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
            context = local_stage_context(context, 1);
            stage_started = tic;
            pseudo_CT_output('INFO', context, 'Preparing input MPRAGE.');
            % Remote converter detail is kept in the subject log only.
            converter_context = context;
            converter_context.console_detail_remote = true;
            jobs(ii).seed_nii = local_convert_dicom(jobs(ii).mprage_fn, ...
                fullfile(jobs(ii).temp_dir, 'mprage.nii'), converter_context);
            pseudo_CT_output('SUCCESS', context, 'Input prepared (elapsed %s).', ...
                local_elapsed(toc(stage_started)));
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
            [PASSWORD, USERNAME] = passwordEntryDialog('enterUserName', true, ...
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
                    % Guard: one subject-scoped terminal line per subject (see local path).
                    outcome = pseudo_CT_subject_outcome( ...
                        local_subject_context(jobs(ii), ii, length(jobs)), jobs(ii).subject_started);
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
                    submit_context = local_stage_context(context, 2);
                    pseudo_CT_output('INFO', submit_context, ...
                        'Submitting MLSC job.');
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
                            outcome.markClosed();
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
                        finalization_success = local_finalize_remote_subject(jobs(ii), ...
                                jobs(ii).seed_nii, config, ii, length(jobs), mlsc_job_id);
                        lifecycle = mlsc_record_finalization(lifecycle, runtime, ...
                            true, logical(finalization_success), ...
                            local_finalization_detail(finalization_success));
                        % The finalizer writes its own SUCCESS or ERROR before returning.
                        outcome.markClosed();
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
                        outcome.markClosed();
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
            outcome = pseudo_CT_subject_outcome( ...
                local_subject_context(jobs(jj), jj, length(jobs)), jobs(jj).subject_started);
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
                outcome.markClosed();
            catch ME
                context = local_subject_context(jobs(jj), jj, length(jobs));
                pseudo_CT_output('ERROR', context, 'Subject failed: %s (elapsed %s).', ...
                    ME.message, local_elapsed(toc(jobs(jj).subject_started)));
                outcome.markClosed();
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

% Convert DICOM to NIfTI
context = local_stage_context(context, 1);
stage_started = tic;
pseudo_CT_output('INFO', local_status_context(context, 'START'), 'Preparing input MPRAGE.');
P = local_convert_dicom(job.mprage_fn, fullfile(temp_dir, 'mprage.nii'), context);
pseudo_CT_output('SUCCESS', local_status_context(context, 'DONE'), 'Input prepared (elapsed %s).', ...
    local_elapsed(toc(stage_started)));

[temp_working_dir, ~, ~] = fileparts(deblank(P));

% Run the pseudo-CT code. The compiled prepare and compute runner shared with
% mlsc-current runs with the existing external local FreeSurfer normalization
% between phases.
Pf = pseudo_CT_run_local_current_subject(P, temp_dir, config, ...
    job.correct_aliasing, job.recenter_before_normalization, context);
if ~ischar(Pf) || isempty(strtrim(Pf))
    pseudo_CT_output('ERROR', context, 'Processing stopped before atlas outputs were generated.');
    return;
end

% Convert att_map.nii to DICOM only when the selected policy requests it.
[temp_working_dir, ~, ~] = fileparts(deblank(Pf(end, :)));
if strcmp(config.io_policy.output, 'nifti-and-dicom')
    try
        dicom_stage = local_dicom_producer_stage(context);
        context = local_stage_context(context, dicom_stage);
        stage_started = tic;
        pseudo_CT_output('INFO', local_status_context(context, 'START'), 'Writing DICOM output.');
        pseudo_CT_write_mu_map_dicom(fullfile(temp_working_dir, 'att_map.nii'), ...
            save_dir, job.umap_fn, temp_dir, config.fwhm, context);
        pseudo_CT_output('SUCCESS', local_status_context(context, 'DONE'), 'DICOM output written (elapsed %s).', ...
            local_elapsed(toc(stage_started)));
    catch ME
        pseudo_CT_output('ERROR', local_status_context(context, 'ERROR'), 'DICOM output failed: %s', ME.message);
        return;
    end
else
    % Not a DICOM stage: report the policy skip without attributing it to the
    % (long finished) input stage that this context still carries.
    skip_context = rmfield(context, {'stage_index', 'stage_count'});
    if isfield(config, 'io_policy') && isfield(config.io_policy, 'gui') && ...
            strcmp(config.io_policy.gui, 'mprage-only')
        skip_context = local_workflow_stage_context(skip_context, 9, ...
            'SKIPPED', 'workflow.dicom_output', 'profile_policy:mprage_only');
        pseudo_CT_output('INFO', skip_context, ...
            'DICOM output skipped by MPRAGE-only policy.');
    else
        skip_context = local_status_context(skip_context, 'INFO');
        pseudo_CT_output('INFO', skip_context, 'Skipping DICOM output by profile policy.');
    end
end

% Promote final outputs and clean up according to the selected profile.
% Full-mode promotion is stage 10. NIfTI-only promotion is separate finalizer
% work, not a substitute for either MPRAGE-only policy skip.
if isfield(config, 'io_policy') && isfield(config.io_policy, 'gui') && ...
        strcmp(config.io_policy.gui, 'mprage-only')
    stage10_context = local_workflow_stage_context(context, 10, ...
        'SKIPPED', 'workflow.full_output_finalize', ...
        'profile_policy:mprage_only');
    pseudo_CT_output('INFO', stage10_context, ...
        'Full-mode output finalization skipped by MPRAGE-only policy.');
    promotion_context = local_output_event_context(context, ...
        'output.promote_nifti', 'operation_started');
else
    promotion_context = local_workflow_stage_context(context, 10, ...
        'START', 'workflow.full_output_finalize', '');
end
stage_started = tic;
pseudo_CT_output('INFO', promotion_context, 'Promoting final NIfTI outputs.');
promotion_success = pseudo_CT_promote_final_outputs(temp_working_dir, processing_dir, P, promotion_context);
if ~promotion_success
    pseudo_CT_output('ERROR', promotion_context, 'Output promotion failed; temporary files were preserved.');
    pseudo_CT_output('INFO', promotion_context, '    %s', temp_working_dir);
    return;
end
pseudo_CT_output('SUCCESS', local_promotion_completed_context(promotion_context), ...
    'Outputs promoted (elapsed %s).', local_elapsed(toc(stage_started)));
pseudo_CT_output('SUCCESS', local_output_event_context(promotion_context, ...
    'output.verify', 'output_verified'), 'Promoted outputs verified.');
if config.cleanup_on_success
    [remove_success, msg] = pseudo_CT_cleanup_subject_temp(temp_working_dir);
    if ~remove_success
        pseudo_CT_output('WARN', local_output_event_context(context, ...
            'output.cleanup', 'warning'), 'Temporary cleanup failed: %s', msg);
    else
        pseudo_CT_output('INFO', local_output_event_context(context, ...
            'output.cleanup', 'operation_completed'), 'Temporary files removed.');
    end
end

if show_dialog && ~isdeployed
    warndlg('Pseudo-CT processing completed.', 'Pseudo-CT completed');
end

success = 1;
% Reached only after att_map verification, promotion, and cleanup succeeded.
completion_context = local_subject_context(job, subject_index, subject_count);
completion_context.completion_verified = true;
pseudo_CT_output('SUCCESS', completion_context, ...
    'Subject completed (elapsed %s).', local_elapsed(toc(subject_started)));

end


function success = local_finalize_remote_subject(job, seed_nii, config, ...
        subject_index, subject_count, job_id)
%LOCAL_FINALIZE_REMOTE_SUBJECT Apply the common post-remote finalization order.
%   Optional JOB_ID propagates the accepted numeric MLSC job ID through the
%   stage 5-8 tags.  Callers without an accepted job ID omit it.

success = 0;
if nargin < 6
    job_id = [];
end
context = local_subject_context(job, subject_index, subject_count);
context = local_attach_mlsc_job(context, job_id);
context.stage_map = pseudo_CT_stage_map(config);
context = local_stage_context(context, 5);
stage_started = tic;
pseudo_CT_output('INFO', context, 'Applying local post-processing.');
% The shared current core owns zero-background policy; no post-fetch re-mask.
pseudo_CT_output('SUCCESS', context, ...
    'Local post-processing completed (elapsed %s).', ...
    local_elapsed(toc(stage_started)));

if strcmp(config.io_policy.output, 'nifti-and-dicom')
    context = local_stage_context(context, 6);
    stage_started = tic;
    pseudo_CT_output('INFO', context, 'Writing DICOM output.');
    try
        % Passing the event context routes the converter output to the run
        % log (pseudo_CT_convert_dicom_quiet) instead of the console. The
        % remote-detail flag suppresses it from every console mode; milestones
        % and WARN/ERROR rows on this context are unaffected.
        converter_context = context;
        converter_context.console_detail_remote = true;
        pseudo_CT_write_mu_map_dicom(fullfile(job.temp_dir, 'att_map.nii'), ...
            job.save_dir, job.umap_fn, job.temp_dir, config.fwhm, converter_context);
    catch ME
        local_log_remote_failure(job, context, ME.message);
        return;
    end
    pseudo_CT_output('SUCCESS', context, 'DICOM output written (elapsed %s).', ...
        local_elapsed(toc(stage_started)));
else
    % Policy skip is not stage 5 work (mirrors the Local path): no stage cell.
    skip_context = rmfield(context, {'stage_index', 'stage_count'});
    if isfield(config, 'io_policy') && isfield(config.io_policy, 'gui') && ...
            strcmp(config.io_policy.gui, 'mprage-only')
        skip_context = local_workflow_stage_context(skip_context, 9, ...
            'SKIPPED', 'workflow.dicom_output', 'profile_policy:mprage_only');
        pseudo_CT_output('INFO', skip_context, ...
            'DICOM output skipped by MPRAGE-only policy.');
    else
        pseudo_CT_output('INFO', skip_context, 'Skipping DICOM output by profile policy.');
    end
end

if isfield(config, 'io_policy') && isfield(config.io_policy, 'gui') && ...
        strcmp(config.io_policy.gui, 'mprage-only')
    stage10_context = local_workflow_stage_context(context, 10, ...
        'SKIPPED', 'workflow.full_output_finalize', ...
        'profile_policy:mprage_only');
    pseudo_CT_output('INFO', stage10_context, ...
        'Full-mode output finalization skipped by MPRAGE-only policy.');
    promotion_context = local_output_event_context(context, ...
        'output.promote_nifti', 'operation_started');
else
    promotion_context = local_workflow_stage_context(context, 10, ...
        'START', 'workflow.full_output_finalize', '');
end
stage_started = tic;
pseudo_CT_output('INFO', promotion_context, 'Promoting final outputs.');
promotion_success = pseudo_CT_promote_final_outputs( ...
    job.temp_dir, job.processing_dir, seed_nii, promotion_context);
if ~promotion_success
    pseudo_CT_output('ERROR', promotion_context, ...
        'Output promotion failed; temporary files were preserved.');
    pseudo_CT_output('INFO', promotion_context, '    %s', job.temp_dir);
    local_log_subject_failure(job, promotion_context);
    return;
end
pseudo_CT_output('SUCCESS', local_promotion_completed_context(promotion_context), ...
    'Outputs promoted (elapsed %s).', local_elapsed(toc(stage_started)));
pseudo_CT_output('SUCCESS', local_output_event_context(promotion_context, ...
    'output.verify', 'output_verified'), 'Promoted outputs verified.');

stage_started = tic;
cleanup_context = local_output_event_context(context, ...
    'output.cleanup', 'operation_started');
pseudo_CT_output('INFO', cleanup_context, 'Cleaning up temporary files.');
if config.cleanup_on_success
    [remove_success, msg] = pseudo_CT_cleanup_subject_temp(job.temp_dir);
    if ~remove_success
        pseudo_CT_output('WARN', local_output_event_context(cleanup_context, ...
            'output.cleanup', 'warning'), 'Temporary cleanup failed: %s', msg);
    end
end
pseudo_CT_output('SUCCESS', local_output_event_context(cleanup_context, ...
    'output.cleanup', 'operation_completed'), 'Cleanup completed (elapsed %s).', ...
    local_elapsed(toc(stage_started)));

success = 1;
final_context = local_subject_context(job, subject_index, subject_count);
final_context = local_attach_mlsc_job(final_context, job_id);
% Reached only after att_map verification, promotion, and cleanup succeeded.
final_context.completion_verified = true;
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


% MLSC transport construction lives in src/backends/mlsc/mlsc_credentials_transport.m
% (shared with the sixth comparison command; extracted verbatim, same behavior).


function local_cleanup_mlsc_transport(transport)
if isstruct(transport) && isfield(transport, 'cleanup') && ...
        isa(transport.cleanup, 'function_handle')
    feval(transport.cleanup);
end
end


function seed_nii = local_convert_dicom(input_file, output_file, context)
%LOCAL_CONVERT_DICOM Run dcm2nii with its console output kept off the table.
%   Shared with the stage-9 reference conversion (see
%   PSEUDO_CT_CONVERT_DICOM_QUIET): converter lines go to the subject run log
%   only; the public table keeps the stage events.
seed_nii = pseudo_CT_convert_dicom_quiet(input_file, output_file, context);
end


function context = local_subject_context(job, subject_index, subject_count)
context = struct('log_file', job.log_file, 'subject_index', subject_index, ...
    'subject_count', subject_count, 'scope', 'subject');
end


function stage_number = local_dicom_producer_stage(context)
% Producer stage number of the DICOM output step, read from the active
% policy map (the map's 'Writing DICOM output' title). Never a hard-coded number.
stage_number = 0;
if isfield(context, 'stage_map') && isstruct(context.stage_map) && ...
        isfield(context.stage_map, 'titles') && ...
        isfield(context.stage_map, 'producer_stage_numbers')
    slot = find(strcmp(context.stage_map.titles, 'Writing DICOM output'), 1);
    if ~isempty(slot)
        stage_number = context.stage_map.producer_stage_numbers(slot);
    end
end
if stage_number < 1
    error('pseudo_CT:StageMap:NoDicomStage', ...
        'Active stage map declares no DICOM output stage.');
end
end

function context = local_stage_context(context, stage_index)
context.stage_index = stage_index;
context.stage_count = 8;
if isfield(context, 'stage_map') && isstruct(context.stage_map) && ...
        isfield(context.stage_map, 'producer_total') && ...
        context.stage_map.producer_total > 0
    [~, public_stage, public_total] = pseudo_CT_stage_map( ...
        context.stage_map, stage_index, context.stage_map.producer_total);
    if public_stage > 0
        context.stage_index = public_stage;
        context.stage_count = public_total;
    else
        context = rmfield(context, {'stage_index', 'stage_count'});
    end
end
end

function context = local_workflow_stage_context(context, stage_number, status, ...
        stage_id, reason)
% Attach an explicit ten-stage public event without changing producer behavior.
context.workflow_event = true;
context.stage_index = stage_number;
context.stage_count = 10;
context.stage_id = stage_id;
context.operation_id = stage_id;
context.stage_status = status;
context.event_kind = local_workflow_event_kind(status);
context.source = 'orchestrator';
context.source_file = 'src/orchestration/pseudo_CT_run_lifecycle.m';
context.live = true;
if isempty(reason)
    if isfield(context, 'reason')
        context = rmfield(context, 'reason');
    end
else
    context.reason = reason;
end
end

function context = local_workflow_event_context(context, stage_id, ...
        operation_id, event_kind, status)
% Attach an unnumbered orchestration event with explicit provenance.
if isfield(context, 'stage_index')
    context = rmfield(context, 'stage_index');
end
if isfield(context, 'stage_count')
    context = rmfield(context, 'stage_count');
end
context.workflow_event = true;
context.stage_id = stage_id;
context.operation_id = operation_id;
context.event_kind = event_kind;
context.event_category = 'preparation';
context.stage_status = status;
context.source = 'orchestrator';
context.source_file = 'src/orchestration/pseudo_CT_run_lifecycle.m';
context.live = true;
end

function context = local_output_event_context(context, operation_id, event_kind)
% Structured, unnumbered finalization events remain distinct from workflow steps.
stale_fields = {'stage_index'; 'stage_count'; 'stage_id'; 'reason'; ...
    'stage_span'; 'operation_ids'; 'event_category'; 'stage_message'};
for ii = 1:length(stale_fields)
    if isfield(context, stale_fields{ii})
        context = rmfield(context, stale_fields{ii});
    end
end
context.workflow_event = true;
context.operation_id = operation_id;
context.event_kind = event_kind;
context.source = 'orchestrator';
context.source_file = 'src/orchestration/pseudo_CT_run_lifecycle.m';
context.live = true;
if strcmp(event_kind, 'warning')
    context.stage_status = 'WARN';
elseif strcmp(event_kind, 'output_verified')
    context.stage_status = 'DONE';
elseif strcmp(event_kind, 'operation_completed')
    context.stage_status = 'DONE';
elseif strcmp(event_kind, 'operation_started')
    context.stage_status = 'START';
end
end

function context = local_promotion_completed_context(context)
if isfield(context, 'stage_id') && ischar(context.stage_id) && ...
        strcmp(context.stage_id, 'workflow.full_output_finalize')
    context = local_workflow_stage_context(context, 10, 'DONE', ...
        'workflow.full_output_finalize', '');
else
    context = local_output_event_context(context, ...
        'output.promote_nifti', 'operation_completed');
end
end

function event_kind = local_workflow_event_kind(status)
if strcmp(status, 'START')
    event_kind = 'stage_started';
elseif strcmp(status, 'DONE')
    event_kind = 'stage_completed';
elseif strcmp(status, 'SKIPPED')
    event_kind = 'stage_skipped';
elseif strcmp(status, 'WARN')
    event_kind = 'warning';
elseif strcmp(status, 'ERROR')
    event_kind = 'failure';
else
    event_kind = 'stage_event';
end
end

function context = local_status_context(context, status)
% Canonical semantic status (START, DONE, WARN, ERROR, INFO) of a Local
% Current stage event; the console presenter formats it without interpreting
% the message. Other profiles are unchanged. Returns a copy (never stored).
if isfield(context, 'console_profile') && ischar(context.console_profile) && ...
        any(strcmp(context.console_profile, ...
        {'local-current'; 'local-mprage-only'}))
    context.stage_status = status;
end
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
        artifact_root, umap_files_arg, resolved_jobs] = ...
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
p.addParamValue('umap_files', [], @(x) isempty(x) || ischar(x) || iscell(x));
p.addParamValue('resolved_jobs', struct([]), @(x) isstruct(x));
p.addParamValue('correct_aliasing', [], ...
    @(x) isempty(x) || ((isnumeric(x) || islogical(x)) && ...
    isscalar(x) && ismember(double(x), [0 1])));
p.addParamValue('recenter_before_normalization', [], ...
    @(x) isempty(x) || ((isnumeric(x) || islogical(x)) && ...
    isscalar(x) && ismember(double(x), [0 1])));
p.addParamValue('mlsc_host_key_provider', [], ...
    @(x) isempty(x) || ischar(x) || isa(x, 'function_handle'));
p.addParamValue('mlsc_current_artifact_root', '', @(x) ischar(x));
p.addParamValue('headless_mode', false, ...
    @(x) islogical(x) && isscalar(x));
p.addParamValue('headless_credentials', struct(), ...
    @(x) isstruct(x) && numel(x) == 1);
p.addParamValue('group_account', '', @(x) ischar(x));
p.parse(varargin{:});
profile_name = p.Results.profile;
subjects_arg = p.Results.subjects;
aliasing_arg = p.Results.correct_aliasing;
recenter_arg = p.Results.recenter_before_normalization;
host_key_provider = p.Results.mlsc_host_key_provider;
artifact_root = p.Results.mlsc_current_artifact_root;
headless_mode = p.Results.headless_mode;
headless_credentials = p.Results.headless_credentials;
group_account = p.Results.group_account;
umap_files_arg = p.Results.umap_files;
resolved_jobs = p.Results.resolved_jobs;
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
