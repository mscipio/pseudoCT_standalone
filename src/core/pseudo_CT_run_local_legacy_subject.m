function success = pseudo_CT_run_local_legacy_subject(job, config, subject_index, subject_count, show_dialog, test_seam)
%PSEUDO_CT_RUN_LOCAL_LEGACY_SUBJECT Direct-local legacy compiled subject.
%   Runs one subject with the legacy v2.0 compiled backend on the local
%   workstation: prepare input, isolated child normalization, synchronous
%   compiled invoke, verified gate, then the shared finalization utilities.
%   All paths are POSIX single-quoted. The child alone carries the
%   normalization environment; this workspace is never altered.
%
%   Minimum supported MATLAB: R2010b.

% Narrow deterministic test seam (T004, R2010b, char-only): tests exercise
% the PRODUCTION monitor directly via
%   pseudo_CT_run_local_legacy_subject('__legacy_backend_test__', req)
% where req.op selects launch/wait/stop/read/elapsed with injected
% clock/process/interruption. Production callers always pass a struct job,
% so this branch never triggers in production. No live 60 s waits.
if nargin >= 2 && ischar(job) && strcmp(job, '__legacy_backend_test__') && isstruct(config)
    success = local_legacy_backend_test_dispatch(config);
    return;
end
success = 0;
if nargin < 4
    error('pseudo_CT:InvalidJob', 'A job, config, and subject position are required.');
end
if nargin < 5 || isempty(show_dialog)
    show_dialog = false;
end
if nargin < 6 || isempty(test_seam)
    test_seam = struct();
end
if ~isstruct(test_seam)
    error('pseudo_CT:InvalidJob', 'Test seam must be a struct when provided.');
end
if ~isstruct(job) || numel(job) ~= 1
    error('pseudo_CT:InvalidJob', 'A single job struct is required.');
end
if ~isstruct(config) || numel(config) ~= 1
    error('pseudo_CT:ProfileRequired', 'A single profile config is required.');
end
if ~isnumeric(subject_index) || ~isscalar(subject_index) || ...
        ~isnumeric(subject_count) || ~isscalar(subject_count)
    error('pseudo_CT:InvalidJob', 'Subject position must be numeric scalars.');
end

base_context = struct('log_file', '', 'subject_index', subject_index, ...
    'subject_count', subject_count, 'scope', 'subject');
try
    base_context.log_file = job.log_file;
catch %#ok<CTCH>
    base_context.log_file = '';
end
try
    subject_started = job.subject_started;
catch %#ok<CTCH>
    subject_started = tic;
end

if ~isfield(config, 'mode') || ~ischar(config.mode) || ~strcmp(config.mode, 'local')
    pseudo_CT_output('ERROR', base_context, 'Legacy direct-local config requires local execution.');
    return;
end
if ~isfield(config, 'implementation') || ~ischar(config.implementation) || ...
        ~strcmp(config.implementation, 'legacy-v2')
    pseudo_CT_output('ERROR', base_context, 'Legacy direct-local config requires the legacy implementation.');
    return;
end
if ~isfield(config, 'normalization') || ~isstruct(config.normalization)
    pseudo_CT_output('ERROR', base_context, 'Legacy direct-local config is missing normalization.');
    return;
end
local_host = '';
try
    local_host = config.normalization.host;
catch %#ok<CTCH>
end
if ~(ischar(local_host) && (strcmp(local_host, '127.0.0.1') || strcmpi(local_host, 'localhost')))
    pseudo_CT_output('ERROR', base_context, 'Legacy direct-local config requires local normalization.');
    return;
end
cluster_flag = '';
try
    cluster_flag = config.normalization.cluster;
catch %#ok<CTCH>
end
if ~(ischar(cluster_flag) && strcmp(cluster_flag, 'No'))
    pseudo_CT_output('ERROR', base_context, 'Legacy direct-local config requires local normalization.');
    return;
end

if ~isfield(job, 'mprage_fn') || ~ischar(job.mprage_fn) || isempty(strtrim(job.mprage_fn))
    pseudo_CT_output('ERROR', base_context, 'Job is missing its MPRAGE input.');
    return;
end
if ~isfield(job, 'temp_dir') || ~ischar(job.temp_dir) || isempty(job.temp_dir)
    pseudo_CT_output('ERROR', base_context, 'Job is missing its temporary directory.');
    return;
end
if ~isfield(job, 'processing_dir') || ~ischar(job.processing_dir) || isempty(job.processing_dir)
    pseudo_CT_output('ERROR', base_context, 'Job is missing its processing directory.');
    return;
end
temp_dir = job.temp_dir;
processing_dir = job.processing_dir;
save_dir = '';
if isfield(job, 'save_dir') && ischar(job.save_dir)
    save_dir = job.save_dir;
end
umap_fn = '';
if isfield(job, 'umap_fn') && ischar(job.umap_fn)
    umap_fn = job.umap_fn;
end
check_aliasing = 1;
if isfield(config, 'aliasing_default')
    check_aliasing = config.aliasing_default;
end
if isfield(job, 'correct_aliasing')
    check_aliasing = job.correct_aliasing;
elseif isfield(job, 'check_aliasing')
    check_aliasing = job.check_aliasing;
end
if islogical(check_aliasing)
    check_aliasing = double(check_aliasing);
end
if ~isnumeric(check_aliasing) || ~isscalar(check_aliasing) || ~ismember(check_aliasing, [0 1])
    pseudo_CT_output('ERROR', base_context, 'Aliasing flag must be a scalar 0 or 1.');
    return;
end

legacy_runner = '';
legacy_mcr = '';
legacy_defaults = '';
legacy_batch = '';
legacy_att = '';
legacy_atlas = '';
legacy_source = '';
try
    legacy_runner = config.legacy.runner;
    legacy_mcr = config.legacy.mcr_root;
    legacy_defaults = config.legacy.defaults_mat;
    legacy_batch = config.legacy.batch_templates;
    legacy_att = config.legacy.att_map;
    legacy_atlas = config.atlas_root;
    legacy_source = config.normalization.source_command;
catch %#ok<CTCH>
end
if ~ischar(legacy_runner) || isempty(legacy_runner) || exist(legacy_runner, 'file') ~= 2
    pseudo_CT_output('ERROR', base_context, 'Legacy runner was not found.');
    return;
end
if ~ischar(legacy_mcr) || isempty(legacy_mcr) || exist(legacy_mcr, 'dir') ~= 7
    pseudo_CT_output('ERROR', base_context, 'Legacy runtime directory was not found.');
    return;
end
if ~ischar(legacy_defaults) || isempty(legacy_defaults) || exist(legacy_defaults, 'file') ~= 2
    pseudo_CT_output('ERROR', base_context, 'Legacy defaults file was not found.');
    return;
end
if ~ischar(legacy_batch) || isempty(legacy_batch) || exist(legacy_batch, 'dir') ~= 7
    pseudo_CT_output('ERROR', base_context, 'Legacy template directory was not found.');
    return;
end
if ~ischar(legacy_atlas) || isempty(legacy_atlas) || exist(legacy_atlas, 'dir') ~= 7
    pseudo_CT_output('ERROR', base_context, 'Legacy atlas directory was not found.');
    return;
end
if ~ischar(legacy_att) || isempty(strtrim(legacy_att))
    pseudo_CT_output('ERROR', base_context, 'Legacy attenuation-map name was not found.');
    return;
end
if ~ischar(legacy_source) || isempty(strtrim(legacy_source))
    pseudo_CT_output('ERROR', base_context, 'Legacy normalization command was not found.');
    return;
end
legacy_env = local_parse_source_env(legacy_source);
if ~ischar(legacy_env) || isempty(legacy_env) || exist(legacy_env, 'file') ~= 2
    pseudo_CT_output('ERROR', base_context, 'Legacy environment file was not found.');
    return;
end
if exist(temp_dir, 'dir') ~= 7
    [made, made_msg] = mkdir(temp_dir);
    if ~made
        pseudo_CT_output('ERROR', base_context, 'Could not create temporary directory: %s', made_msg);
        return;
    end
end
if ~local_is_writable_directory(temp_dir)
    pseudo_CT_output('ERROR', base_context, 'Temporary directory is not writable.');
    return;
end
if exist(processing_dir, 'dir') ~= 7
    [made, made_msg] = mkdir(processing_dir);
    if ~made
        pseudo_CT_output('ERROR', base_context, 'Could not create processing directory: %s', made_msg);
        return;
    end
end
if isfield(config, 'io_policy') && isstruct(config.io_policy) && ...
        isfield(config.io_policy, 'output') && strcmp(config.io_policy.output, 'nifti-and-dicom')
    if isempty(save_dir)
        pseudo_CT_output('ERROR', base_context, 'Job is missing its DICOM directory.');
        return;
    end
    if exist(save_dir, 'dir') ~= 7
        [made, made_msg] = mkdir(save_dir);
        if ~made
            pseudo_CT_output('ERROR', base_context, 'Could not create DICOM directory: %s', made_msg);
            return;
        end
    end
end

stage_context = local_stage_context(base_context, 1);
pseudo_CT_output('INFO', stage_context, 'Preparing input MPRAGE.');
try
    seed_nii = dcm2nii(job.mprage_fn, fullfile(temp_dir, 'mprage.nii'), 'Overwrite', true);
catch ME_stage
    pseudo_CT_output('ERROR', base_context, 'Input preparation failed: %s', ME_stage.message);
    return;
end
if ~ischar(seed_nii) || isempty(strtrim(seed_nii))
    pseudo_CT_output('ERROR', base_context, 'Input preparation produced no output.');
    return;
end
seed_nii = deblank(seed_nii);
if exist(seed_nii, 'file') ~= 2
    pseudo_CT_output('ERROR', base_context, 'Prepared input was not found.');
    return;
end
pseudo_CT_output('SUCCESS', stage_context, 'Input prepared (elapsed %s).', ...
    local_elapsed(toc(subject_started)));

[~, input_base, input_ext] = fileparts(seed_nii);
if isempty(input_base) || isempty(input_ext)
    pseudo_CT_output('ERROR', base_context, 'Prepared input has no valid filename.');
    return;
end
normalized_name = [input_base '_normalized' input_ext];
needs_normalization = isempty(regexp(lower([input_base input_ext]), '_normalized\.nii$', 'once'));
input_path = seed_nii;
normalized_path = fullfile(temp_dir, normalized_name);

if needs_normalization
    norm_context = local_stage_context(base_context, 2);
    pseudo_CT_output('INFO', norm_context, 'Normalizing MPRAGE with FreeSurfer.');
    q_env = local_shell_quote(legacy_env);
    q_in = local_shell_quote(input_path);
    q_out = local_shell_quote(normalized_path);
    inner_cmd = ['source ' q_env '; mri_normalize ' q_in ' ' q_out];
    q_inner = local_shell_quote(inner_cmd);
    norm_cmd = ['env -u LD_LIBRARY_PATH tcsh -f -c ' q_inner];
    [norm_status, norm_detail] = system(norm_cmd);
    if norm_status ~= 0
        pseudo_CT_output('ERROR', norm_context, 'FreeSurfer normalization failed.');
        if ischar(norm_detail) && ~isempty(strtrim(norm_detail))
            pseudo_CT_output('ERROR', norm_context, 'FreeSurfer failure detail: %s', strtrim(norm_detail));
        end
        pseudo_CT_output('ERROR', norm_context, 'FreeSurfer exit status: %d.', norm_status);
        return;
    end
    if exist(normalized_path, 'file') ~= 2
        pseudo_CT_output('ERROR', norm_context, 'FreeSurfer did not create the normalized NIfTI file.');
        return;
    end
    norm_info = dir(normalized_path);
    if isempty(norm_info) || norm_info(1).bytes == 0
        pseudo_CT_output('ERROR', norm_context, 'FreeSurfer normalized file is empty.');
        return;
    end
    pseudo_CT_output('SUCCESS', norm_context, 'MPRAGE normalization completed (elapsed %s).', ...
        local_elapsed(toc(subject_started)));
else
    norm_context = local_stage_context(base_context, 2);
    pseudo_CT_output('INFO', norm_context, 'Normalization input already normalized; skipping.');
    normalized_path = input_path;
end

staged_input = normalized_path;
invoke_context = local_stage_context(base_context, 3);
q_runner = local_shell_quote(legacy_runner);
q_mcr = local_shell_quote(legacy_mcr);
q_staged = local_shell_quote(staged_input);
q_batch = local_shell_quote(legacy_batch);
q_defaults = local_shell_quote(legacy_defaults);
runner_cmd = [q_runner ' ' q_mcr ' ' q_staged ' ' q_batch ' 0 ' num2str(check_aliasing) ' ' q_defaults];
backend_log = fullfile(temp_dir, 'legacy_backend.log');
backend_status_path = fullfile(temp_dir, 'legacy_backend.exit');
backend_started = tic;
[backend_pid, launch_error] = local_launch_legacy_backend(runner_cmd, backend_log, backend_status_path);
if ~(isnumeric(backend_pid) && isscalar(backend_pid) && isfinite(backend_pid) && backend_pid > 0)
    pseudo_CT_output('ERROR', invoke_context, 'Legacy pseudo-CT failed to start (elapsed %s).', ...
        local_elapsed(toc(backend_started)));
    if ischar(launch_error) && ~isempty(strtrim(launch_error))
        pseudo_CT_output('ERROR', invoke_context, 'Backend launch detail: %s', strtrim(launch_error));
    end
    return;
end
pseudo_CT_output('INFO', invoke_context, 'Legacy pseudo-CT started.');
try
    [backend_done, runner_status, backend_failure] = ...
        local_wait_legacy_backend(backend_pid, backend_status_path, invoke_context, backend_started, test_seam);
catch ME_backend
    local_stop_legacy_backend(backend_pid);
    pseudo_CT_output('ERROR', invoke_context, 'Legacy pseudo-CT interrupted (elapsed %s).', ...
        local_elapsed(toc(backend_started)));
    pseudo_CT_output('ERROR', invoke_context, 'Backend interrupt detail: %s', ME_backend.message);
    pseudo_CT_output('INFO', invoke_context, '    %s', backend_log);
    return;
end
if ~backend_done
    local_stop_legacy_backend(backend_pid);
    pseudo_CT_output('ERROR', invoke_context, 'Legacy pseudo-CT failed (elapsed %s).', ...
        local_elapsed(toc(backend_started)));
    if ischar(backend_failure) && ~isempty(strtrim(backend_failure))
        pseudo_CT_output('ERROR', invoke_context, 'Backend failure detail: %s', strtrim(backend_failure));
    end
    pseudo_CT_output('INFO', invoke_context, '    %s', backend_log);
    return;
end
if runner_status ~= 0
    pseudo_CT_output('ERROR', invoke_context, 'Legacy pseudo-CT failed (elapsed %s).', ...
        local_elapsed(toc(backend_started)));
    backend_tail = local_read_log_tail(backend_log);
    if ischar(backend_tail) && ~isempty(strtrim(backend_tail))
        pseudo_CT_output('ERROR', invoke_context, 'Backend failure detail: %s', strtrim(backend_tail));
    end
    pseudo_CT_output('ERROR', invoke_context, 'Backend exit status: %d.', runner_status);
    pseudo_CT_output('INFO', invoke_context, '    %s', backend_log);
    return;
end
pseudo_CT_output('SUCCESS', invoke_context, 'Legacy pseudo-CT completed (elapsed %s).', ...
    local_elapsed(toc(backend_started)));

verify_context = local_stage_context(base_context, 4);
pseudo_CT_output('INFO', verify_context, 'Verifying attenuation map.');
att_path = fullfile(temp_dir, legacy_att);
if exist(att_path, 'file') ~= 2
    pseudo_CT_output('ERROR', verify_context, 'Required attenuation map was not found.');
    pseudo_CT_output('INFO', verify_context, '    %s', att_path);
    return;
end
att_info = dir(att_path);
if isempty(att_info) || att_info(1).bytes == 0
    pseudo_CT_output('ERROR', verify_context, 'Required attenuation map is empty.');
    return;
end
pseudo_CT_output('SUCCESS', verify_context, 'Attenuation map verified (elapsed %s).', ...
    local_elapsed(toc(subject_started)));

post_context = local_stage_context(base_context, 5);
pseudo_CT_output('INFO', post_context, 'Applying local post-processing.');
if isfield(config, 'zero_background') && ischar(config.zero_background) && strcmp(config.zero_background, 'Yes')
    pseudo_CT_apply_background_mask(temp_dir, post_context);
end
pseudo_CT_output('SUCCESS', post_context, 'Local post-processing completed (elapsed %s).', ...
    local_elapsed(toc(subject_started)));

writes_dicom = isfield(config, 'io_policy') && isstruct(config.io_policy) && ...
    isfield(config.io_policy, 'output') && strcmp(config.io_policy.output, 'nifti-and-dicom');
if writes_dicom
    dicom_context = local_stage_context(base_context, 6);
    pseudo_CT_output('INFO', dicom_context, 'Writing DICOM output.');
    try
        fwhm_value = 0;
        if isfield(config, 'fwhm')
            fwhm_value = config.fwhm;
        end
        pseudo_CT_write_mu_map_dicom(att_path, save_dir, umap_fn, temp_dir, fwhm_value);
    catch ME_dicom
        pseudo_CT_output('ERROR', dicom_context, 'DICOM output failed: %s', ME_dicom.message);
        return;
    end
    pseudo_CT_output('SUCCESS', dicom_context, 'DICOM output written (elapsed %s).', ...
        local_elapsed(toc(subject_started)));
else
    pseudo_CT_output('INFO', post_context, 'Skipping DICOM output by profile policy.');
end

promote_context = local_stage_context(base_context, 7);
pseudo_CT_output('INFO', promote_context, 'Promoting final outputs.');
promotion_success = pseudo_CT_promote_final_outputs(temp_dir, processing_dir, seed_nii, promote_context);
if ~promotion_success
    pseudo_CT_output('ERROR', promote_context, 'Output promotion failed; temporary files were preserved.');
    pseudo_CT_output('INFO', promote_context, '    %s', temp_dir);
    return;
end
pseudo_CT_output('SUCCESS', promote_context, 'Outputs promoted (elapsed %s).', ...
    local_elapsed(toc(subject_started)));

cleanup_context = local_stage_context(base_context, 8);
pseudo_CT_output('INFO', cleanup_context, 'Cleaning up temporary files.');
do_cleanup = false;
if isfield(config, 'cleanup_on_success')
    do_cleanup = isequal(config.cleanup_on_success, true);
end
if do_cleanup
    [remove_success, remove_msg] = rmdir(temp_dir, 's');
    if ~remove_success
        pseudo_CT_output('WARN', cleanup_context, 'Temporary cleanup failed: %s', remove_msg);
    end
end
pseudo_CT_output('SUCCESS', cleanup_context, 'Cleanup completed (elapsed %s).', ...
    local_elapsed(toc(subject_started)));

if show_dialog && ~isdeployed
    try
        warndlg('Pseudo-CT processing completed.', 'Pseudo-CT completed');
    catch %#ok<CTCH>
    end
end

success = 1;
pseudo_CT_output('SUCCESS', base_context, 'Subject completed (elapsed %s).', ...
    local_elapsed(toc(subject_started)));
end

function context = local_stage_context(context, stage_index)
context.stage_index = stage_index;
context.stage_count = 8;
end

function value = local_elapsed(seconds)
seconds = max(0, floor(seconds));
hours = floor(seconds / 3600);
minutes = floor(rem(seconds, 3600) / 60);
seconds = rem(seconds, 60);
value = sprintf('%02d:%02d:%02d', hours, minutes, seconds);
end

function result = local_legacy_backend_test_dispatch(req)
% Narrow test entry only: dispatches to the PRODUCTION helpers above with
% an injected seam. Production never calls this (see the char-token guard
% at the top of the main function). R2010b-compatible, char-only.
result = struct();
if ~isstruct(req) || ~isfield(req, 'op') || ~ischar(req.op)
    error('pseudo_CT:InvalidTestRequest', 'Test request requires a char op.');
end
if strcmp(req.op, 'wait')
    if isfield(req, 'seam')
        seam = req.seam;
    else
        seam = struct();
    end
    [completed, exit_status, failure_reason] = local_wait_legacy_backend(req.pid, req.status_path, req.invoke_context, req.backend_started, seam);
    result = struct('completed', completed, 'exit_status', exit_status, 'failure_reason', failure_reason);
    return;
elseif strcmp(req.op, 'stop')
    local_stop_legacy_backend(req.pid);
    result = struct('stopped', true);
    return;
elseif strcmp(req.op, 'launch')
    [pid, launch_error] = local_launch_legacy_backend(req.runner_cmd, req.log_path, req.status_path);
    result = struct('pid', pid, 'launch_error', launch_error);
    return;
elseif strcmp(req.op, 'read')
    [found, exit_status] = local_read_legacy_backend_exit(req.status_path);
    result = struct('found', found, 'exit_status', exit_status);
    return;
elseif strcmp(req.op, 'elapsed')
    result = struct('text', local_elapsed(req.seconds));
    return;
else
    error('pseudo_CT:InvalidTestRequest', 'Unknown test op.');
end
end

function quoted = local_shell_quote(value)
single_quote = char(39);
double_quote = char(34);
quoted = single_quote;
for ii = 1:length(value)
    if value(ii) == char(0)
        error('pseudo_CT:InvalidPath', 'A shell value contains a NUL character.');
    elseif value(ii) == single_quote
        quoted = [quoted single_quote double_quote single_quote double_quote single_quote]; %#ok<AGROW>
    else
        quoted = [quoted value(ii)]; %#ok<AGROW>
    end
end
quoted = [quoted single_quote];
end

function env_path = local_parse_source_env(source_command)
env_path = '';
if ~ischar(source_command) || isempty(strtrim(source_command))
    return;
end
trimmed = strtrim(source_command);
prefix = 'source ';
if strncmp(trimmed, prefix, length(prefix))
    env_path = strtrim(trimmed(length(prefix) + 1:end));
else
    return;
end
if length(env_path) >= 2 && env_path(1) == char(39) && env_path(end) == char(39)
    env_path = env_path(2:end - 1);
end
end

function writable = local_is_writable_directory(directory_path)
if exist(directory_path, 'dir') ~= 7
    writable = false;
    return;
end
probe_path = tempname(directory_path);
fid = fopen(probe_path, 'w');
writable = fid ~= -1;
if writable
    fclose(fid);
    if exist(probe_path, 'file') == 2
        delete(probe_path);
    end
end
end

function [pid, launch_error] = local_launch_legacy_backend(runner_cmd, log_path, status_path)
% Owns launch only: start the compiled runner detached from MATLAB with
% stdout/stderr redirected to the per-run log, the runner exit code
% recorded in the status file, and the wrapper PID reported. Monitoring,
% exit retrieval, and interruption belong to the helpers below.
% Command/args/env arrive unchanged; logging adds only redirection.
%
% Uncapped log: the wrapper sets no file-size limit of its own, so the
% runner and its descendants inherit the normal host limit and a verbose
% backend can fill the per-run log over ~1 h runs without the wrapper
% failing its writes. The log simply grows in temp_dir and is retained
% for diagnostics (removed only by the stage-8 cleanup policy). No log
% parsing into states; the 4 KiB tail stays opaque failure detail.
%
% Interrupt ownership: the runner backgrounds inside the wrapper
% ('runner > log 2>&1 & runner_pid=$!'), the wrapper traps TERM and
% forwards it to the runner ('trap ''kill $runner_pid ...'' TERM'), then
% waits, publishes the exit code atomically (tmp file then mv -f), and
% exits with the runner code. $! remains the wrapper PID (owned), but
% SIGTERM reliably reaches the runner without process-tree scans
% and without SIGKILL (TERM only, so the runner can
% flush). 'Dead PID + no status file' still means abnormal end (see wait).
pid = -1;
launch_error = '';
status_tmp_path = [status_path '.tmp'];
if exist(status_path, 'file') == 2
    try
        delete(status_path);
    catch %#ok<CTCH>
    end
end
if exist(status_tmp_path, 'file') == 2
    try
        delete(status_tmp_path);
    catch %#ok<CTCH>
    end
end
q_log = local_shell_quote(log_path);
q_status = local_shell_quote(status_path);
q_status_tmp = local_shell_quote(status_tmp_path);
launch_cmd = ['( ' runner_cmd ' > ' q_log ' 2>&1 & runner_pid=$!; trap ''kill $runner_pid 2>/dev/null'' TERM; wait $runner_pid; code=$?; echo $code > ' q_status_tmp '; mv -f ' q_status_tmp ' ' q_status '; trap - TERM; exit $code ) & echo $!'];
[launch_status, pid_text] = system(launch_cmd);
if launch_status ~= 0
    launch_error = strtrim(char(pid_text));
    return;
end
candidate = str2double(strtrim(char(pid_text)));
if isscalar(candidate) && isfinite(candidate) && candidate > 0
    pid = candidate;
else
    launch_error = strtrim(char(pid_text));
end
end

function [completed, exit_status, failure_reason] = ...
    local_wait_legacy_backend(pid, status_path, invoke_context, backend_started, seam)
% Owns monitoring and completion: sleep between probes (no busy-wait),
% emit a time-based heartbeat about every 60 s (never parsed from backend
% output, so a silent backend still heartbeats), and return when the
% status file appears. A healthy backend has no runtime timeout; an
% unverifiable child (dead PID with no status file) returns failure and
% never success. Short 1 s polls while elapsed < 30 s settle instant
% backends without waiting a full 30 s; longer runs keep the steady 30 s
% cadence. A dead-PID probe re-reads the status file once because the
% wrapper publishes it atomically just before the subshell exits.
%
% Deterministic test seam (T004, narrow, R2010b, char/numeric only): when
% SEAM is a non-empty struct, clock/process/sleep are injected so tests
% exercise THIS production loop with no real 60 s waits. Recognized fields
% (all optional): seam.exit_tick (iteration where status appears; finite
% completes with seam.exit_code, Inf never appears e.g. garbage/missing,
% absent uses the real status file), seam.exit_code, seam.alive_values
% (numeric 1/0 per iteration, fake kill -0; absent means alive in seam
% mode and the real probe in live mode; short vectors hold last value;
% dead PID with no status returns the same disappeared failure, never
% success), seam.clock_values (numeric fake toc elapsed per iteration;
% absent uses the real toc; short vectors hold last value; heartbeats are
% still emitted by THIS production code via pseudo_CT_output), and
% seam.throw_at (iteration where THIS loop throws fixture:Interrupted to
% simulate Ctrl-C; the production caller unwinds via stop). When SEAM is
% present there are no real pauses. When SEAM is absent/empty, behavior is
% exactly the live loop above with no timeout. A high iteration guard
% (5000) exists ONLY in seam mode as a test-harness safety net; tests must
% terminate via production completion/failure, never via the guard.
completed = false;
exit_status = -1;
failure_reason = '';
last_heartbeat = 0;
use_seam = (nargin >= 5 && isstruct(seam) && ~isempty(fieldnames(seam)));
seam_iter = 0;
while true
    seam_iter = seam_iter + 1;
    if use_seam && seam_iter > 5000
        error('pseudo_CT:TestSeamExhausted', 'Test seam exceeded its safety bound.');
    end
    if use_seam && isfield(seam, 'throw_at') && ~isempty(seam.throw_at) && isfinite(seam.throw_at) && seam_iter == seam.throw_at
        error('fixture:Interrupted', 'Simulated backend wait interrupt.');
    end
    if use_seam && isfield(seam, 'exit_tick') && ~isempty(seam.exit_tick)
        if isfinite(seam.exit_tick) && seam_iter >= seam.exit_tick
            if isfield(seam, 'exit_code') && ~isempty(seam.exit_code)
                code = seam.exit_code;
            else
                code = 0;
            end
            completed = true;
            exit_status = code;
            return;
        end
    else
        [found, code] = local_read_legacy_backend_exit(status_path);
        if found
            completed = true;
            exit_status = code;
            return;
        end
    end
    if use_seam
        if isfield(seam, 'alive_values') && ~isempty(seam.alive_values)
            idx = seam_iter;
            if idx > length(seam.alive_values)
                idx = length(seam.alive_values);
            end
            alive = (seam.alive_values(idx) ~= 0);
        else
            alive = true;
        end
    else
        alive = local_is_legacy_backend_alive(pid);
    end
    if ~alive
        if use_seam && isfield(seam, 'exit_tick') && ~isempty(seam.exit_tick)
            found2 = false;
        else
            [found2, code2] = local_read_legacy_backend_exit(status_path);
            if found2
                completed = true;
                exit_status = code2;
                return;
            end
        end
        failure_reason = 'Backend process disappeared before reporting an exit status.';
        return;
    end
    if use_seam && isfield(seam, 'clock_values') && ~isempty(seam.clock_values)
        idx = seam_iter;
        if idx > length(seam.clock_values)
            idx = length(seam.clock_values);
        end
        elapsed = seam.clock_values(idx);
    else
        elapsed = toc(backend_started);
    end
    if elapsed - last_heartbeat >= 60
        last_heartbeat = elapsed;
        pseudo_CT_output('INFO', invoke_context, 'Legacy pseudo-CT still running (elapsed %s).', ...
            local_elapsed(elapsed));
    end
    if use_seam
        % No real pause in seam mode (deterministic instant polls).
    else
        if elapsed < 30
            pause(1);
        else
            pause(30);
        end
    end
end
end

function alive = local_is_legacy_backend_alive(pid)
% Owns the liveness probe only: signal 0 checks existence without
% affecting the child. Any probe error reads as not-alive; the caller
% treats that as failure, never success.
alive = false;
if ~(isnumeric(pid) && isscalar(pid) && isfinite(pid) && pid > 0)
    return;
end
[probe_status, ~] = system(sprintf('kill -0 %d', round(pid)));
alive = (probe_status == 0);
end

function [found, exit_status] = local_read_legacy_backend_exit(status_path)
% Owns exit-status retrieval only: the status file holds the runner exit
% code written by the launch wrapper. Missing/unreadable/unparseable
% content reads as not-found so the caller can fail closed.
found = false;
exit_status = -1;
if exist(status_path, 'file') ~= 2
    return;
end
fid = fopen(status_path, 'r');
if fid == -1
    return;
end
try
    raw = fscanf(fid, '%c');
catch %#ok<CTCH>
    raw = '';
end
try
    fclose(fid);
catch %#ok<CTCH>
end
code = str2double(strtrim(char(raw)));
if isscalar(code) && isfinite(code) && code == floor(code) && code >= 0
    found = true;
    exit_status = code;
end
end

function local_stop_legacy_backend(pid)
% Interrupt-path cleanup only: one best-effort SIGTERM so an interrupted
% MATLAB session does not orphan a multi-hour compiled runner. SIGTERM
% (never SIGKILL) lets the runner flush and exit on its own; a failed
% kill is ignored because the caller already treats the run as failed.
% Never used for healthy, completed, or already-reaped runs.
if ~(isnumeric(pid) && isscalar(pid) && isfinite(pid) && pid > 0)
    return;
end
try
    system(sprintf('kill %d', round(pid)));
catch %#ok<CTCH>
end
end

function tail_text = local_read_log_tail(log_path)
% Opaque failure detail only: returns the tail of the per-run backend log
% without parsing it into states. The per-run log itself is uncapped (the
% wrapper sets no file-size limit); the 4 KiB window below limits display
% only. The log is retained in temp_dir for diagnostics and removed only
% by the stage-8 cleanup policy.
tail_text = '';
if exist(log_path, 'file') ~= 2
    return;
end
fid = fopen(log_path, 'r');
if fid == -1
    return;
end
try
    fseek(fid, 0, 'eof');
    total = ftell(fid);
    window = 4096;
    if total > window
        fseek(fid, -window, 'eof');
    else
        fseek(fid, 0, 'bof');
    end
    tail_text = char(fread(fid, '*char')');
catch %#ok<CTCH>
    tail_text = '';
end
try
    fclose(fid);
catch %#ok<CTCH>
end
tail_text = strtrim(tail_text);
end
