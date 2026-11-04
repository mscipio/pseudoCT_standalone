function Pf = pseudo_CT_run_local_current_subject(input_path, work_dir, ...
        config, check_aliasing, recenter_before_normalization, output_context)
%PSEUDO_CT_RUN_LOCAL_CURRENT_SUBJECT Run the shared compiled current phases.
%   Uses the same pinned runner and job/resource manifest contract as
%   mlsc-current: prepare, the existing external local FreeSurfer
%   normalization, then compute. Scientific processing stays in the
%   compiled payload; this function only coordinates those phases.
%   Minimum supported MATLAB: R2010b.

% Narrow test seam for exercising the production child stream monitor without
% invoking a compiled payload. Production calls always pass six arguments.
if nargin == 2 && ischar(input_path) && ...
        strcmp(input_path, '__current_stream_test__') && isstruct(work_dir)
    Pf = local_current_stream_test_dispatch(work_dir);
    return;
end

if nargin ~= 6 || ~isstruct(config) || numel(config) ~= 1 || ...
        ~isstruct(output_context) || numel(output_context) ~= 1
    error('pseudo_CT:LocalCurrentRequest', ...
        'A local current input, work directory, profile, and output context are required.');
end
if ~isfield(config, 'mode') || ~strcmp(config.mode, 'local') || ...
        ~isfield(config, 'implementation') || ...
        ~strcmp(config.implementation, 'current')
    error('pseudo_CT:LocalCurrentRequest', ...
        'The selected profile does not use the local current implementation.');
end
if ~isfield(config, 'normalization') || ...
        ~isstruct(config.normalization) || ...
        ~isfield(config.normalization, 'host') || ...
        ~(strcmp(config.normalization.host, '127.0.0.1') || ...
        strcmpi(config.normalization.host, 'localhost')) || ...
        ~isfield(config.normalization, 'cluster') || ...
        ~strcmp(config.normalization.cluster, 'No')
    error('pseudo_CT:LocalCurrentNormalization', ...
        'Local-current requires local FreeSurfer normalization without a cluster.');
end
if ~isfield(config, 'current') || ~isstruct(config.current) || ...
        numel(config.current) ~= 1 || ...
        ~ischar(input_path) || size(input_path, 1) ~= 1 || ...
        isempty(strtrim(input_path)) || any(input_path == char(0)) || ...
        ~ischar(work_dir) || size(work_dir, 1) ~= 1 || ...
        isempty(strtrim(work_dir)) || any(work_dir == char(0)) || ...
        exist(strtrim(input_path), 'file') ~= 2 || ...
        exist(strtrim(work_dir), 'dir') ~= 7
    error('pseudo_CT:LocalCurrentRequest', ...
        'The current payload input or work directory is unavailable.');
end
if ~(isnumeric(check_aliasing) || islogical(check_aliasing)) || ...
        ~isscalar(check_aliasing) || ~ismember(double(check_aliasing), [0 1])
    error('pseudo_CT:LocalCurrentRequest', ...
        'The current payload aliasing flag must be scalar 0 or 1.');
end
if ~local_yes_no_or_flag(recenter_before_normalization) || ...
        ~isfield(config, 'atlas_root') || ~ischar(config.atlas_root) || ...
        ~isfield(config, 'zero_background') || ...
        ~isfield(config, 'bone_enabled') || ...
        ~(islogical(config.bone_enabled) || isnumeric(config.bone_enabled)) || ...
        ~isscalar(config.bone_enabled) || ...
        ~ismember(double(config.bone_enabled), [0 1])
    error('pseudo_CT:LocalCurrentRequest', ...
        'The current payload processing settings are invalid.');
end

% Project only the pinned artifact contract into the validator; local mode
% must not be mistaken for the MLSC scheduler profile.
artifact_config = struct();
artifact_config.implementation = 'current';
artifact_config.current = config.current;
mlsc_current_validate('validate_for_execution', artifact_config);

job = struct();
job.schema = 'pseudo-CT.mlsc-current-job/v1';
job.manifest_version = 1;
job.input_mprage = strtrim(input_path);
job.work_dir = strtrim(work_dir);
job.atlas_dir = config.atlas_root;
job.check_aliasing = double(check_aliasing);
job.recenter_before_normalization = recenter_before_normalization;
job.bone_enabled = logical(config.bone_enabled);
job.zero_background = config.zero_background;
job_manifest_path = [tempname(strtrim(work_dir)) '.mat'];
save(job_manifest_path, 'job', '-v6');

% Local Current public-stage state (stage 1 was reported by the orchestrator).
public = containers.Map();
public('stage') = 1;
public('open') = false;
public('started') = tic;

local_run_phase(config.current, 'prepare', job_manifest_path, ...
    config.current.resource_manifest, output_context, public);

handoff_path = fullfile(strtrim(work_dir), 'mlsc_current_handoff.mat');
if exist(handoff_path, 'file') ~= 2
    error('pseudo_CT:LocalCurrentPrepare', ...
        'Compiled current prepare did not produce its handoff.');
end
handoff_info = dir(handoff_path);
if isempty(handoff_info) || handoff_info(1).bytes == 0
    error('pseudo_CT:LocalCurrentPrepare', ...
        'Compiled current prepare produced an empty handoff.');
end
loaded = load(handoff_path, 'handoff');
if ~isfield(loaded, 'handoff') || ~isstruct(loaded.handoff) || ...
        numel(loaded.handoff) ~= 1
    error('pseudo_CT:LocalCurrentPrepare', ...
        'Compiled current prepare produced an invalid handoff.');
end
handoff = loaded.handoff;
clear loaded
local_validate_handoff(handoff, job_manifest_path, ...
    config.current.resource_manifest, config.atlas_root);

selected_input = strtrim(handoff.input_selected);
if logical(handoff.needs_normalization)
    normalization_context = local_public_context(output_context, 4, 'START');
    normalization_started = tic;
    public = local_public_set(public, 4, true);
    pseudo_CT_output('INFO', normalization_context, ...
        'Normalizing MPRAGE with FreeSurfer.');
    normalized_path = strtrim(handoff.normalized_expected);
    if exist(normalized_path, 'file') == 2
        local_normalization_failed(output_context, ...
            'An existing normalized output prevents fail-closed local normalization.');
        error('pseudo_CT:LocalCurrentNormalization', ...
            'An existing normalized output prevents fail-closed local normalization.');
    end
    normalization_connection = struct('hostname', config.normalization.host, ...
        'username', 'local', 'password', '', 'autoreconnect', 0);
    normalization_command = sprintf('mri_normalize %s %s', ...
        selected_input, normalized_path);
    try
        normalization_status = run_normalization_cmd(normalization_command, ...
            normalization_connection, normalization_context, config);
    catch normalization_error
        % Report the failed stage before the error propagates; no DONE.
        local_normalization_failed(output_context, sprintf( ...
            'FreeSurfer normalization could not be completed: %s', ...
            normalization_error.message));
        rethrow(normalization_error);
    end
    normalized_info = dir(normalized_path);
    if normalization_status ~= 0 || isempty(normalized_info) || ...
            normalized_info(1).bytes == 0
        local_normalization_failed(output_context, sprintf( ...
            'FreeSurfer did not produce a non-empty normalized NIfTI file (exit status %d).', ...
            normalization_status));
        error('pseudo_CT:LocalCurrentNormalization', ...
            'FreeSurfer did not produce a non-empty normalized NIfTI file.');
    end
    public = local_public_set(public, 4, false);
    pseudo_CT_output('SUCCESS', local_public_context(output_context, 4, 'DONE'), ...
        'MPRAGE normalization completed (elapsed %s).', ...
        local_current_elapsed(toc(normalization_started)));
else
    normalization_context = local_public_context(output_context, 4, 'SKIPPED', ...
        'Normalization skipped (input already normalized).');
    public = local_public_set(public, 4, false);
    pseudo_CT_output('INFO', normalization_context, ...
        'Normalization input already normalized; skipping.');
    normalized_path = selected_input;
end

if exist(normalized_path, 'file') ~= 2
    error('pseudo_CT:LocalCurrentNormalization', ...
        'The current payload normalized input is unavailable.');
end
local_run_phase(config.current, 'compute', job_manifest_path, ...
    config.current.resource_manifest, output_context, public);

for ii = 1:numel(config.current.required_outputs)
    output_path = fullfile(strtrim(work_dir), ...
        config.current.required_outputs{ii});
    output_info = dir(output_path);
    if isempty(output_info) || output_info(1).bytes == 0
        error('pseudo_CT:LocalCurrentCompute', ...
            'Compiled current compute did not produce a required output.');
    end
end
verification_path = fullfile(strtrim(work_dir), ...
    'mlsc_current_output_verification.txt');
if exist(verification_path, 'file') ~= 2
    error('pseudo_CT:LocalCurrentCompute', ...
        'Compiled current compute did not produce output verification evidence.');
end
verification_info = dir(verification_path);
if isempty(verification_info) || verification_info(1).bytes == 0
    error('pseudo_CT:LocalCurrentCompute', ...
        'Compiled current output verification evidence is empty.');
end
Pf = fullfile(strtrim(work_dir), 'att_map.nii');
end

function local_run_phase(current, phase, job_manifest_path, ...
        resource_manifest_path, output_context, public)
runner = strtrim(current.runner);
mcr_root = strtrim(current.mcr_root);
if ~local_runner_argument_safe(runner) || ...
        ~local_runner_argument_safe(mcr_root) || ...
        ~local_runner_argument_safe(job_manifest_path) || ...
        ~local_runner_argument_safe(resource_manifest_path)
    error('pseudo_CT:LocalCurrentRunner', ...
        'A current runner argument contains unsupported shell syntax.');
end
artifact_config = struct();
artifact_config.implementation = 'current';
artifact_config.current = current;
mlsc_current_validate('validate_for_execution', artifact_config);
command = ['env -u LD_LIBRARY_PATH ' local_shell_quote(runner) ' ' ...
    local_shell_quote(mcr_root) ' ' local_shell_quote(phase) ' ' ...
    local_shell_quote(job_manifest_path) ' ' ...
    local_shell_quote(resource_manifest_path)];
if strcmp(phase, 'prepare')
    phase_stage = 2;
else
    phase_stage = 3;
end
stage_context = local_stage_context(output_context, phase_stage);
% Phase wrappers are run-log detail; the public stages are reported from
% the stage events (status LOG keeps these off the console).
log_context = local_public_log_context(stage_context);
pseudo_CT_output('INFO', log_context, ...
    'Running compiled current %s phase.', upper(phase));
if strcmp(phase, 'compute')
    pseudo_CT_output('INFO', log_context, ...
        ['Current compute includes SPM segmentation, DARTEL atlas ', ...
         'registration/warping, and attenuation generation.']);
end
phase_started = tic;
stream_log = '';
if isfield(output_context, 'log_file') && ...
        ischar(output_context.log_file) && ...
        size(output_context.log_file, 1) == 1 && ...
        ~isempty(strtrim(output_context.log_file))
    stream_log = strtrim(output_context.log_file);
end
status = local_run_streaming(command, stream_log, stage_context, ...
    phase_started, phase, public);
if status ~= 0
    if isfield(output_context, 'log_file') && ...
            ischar(output_context.log_file) && ...
            ~isempty(strtrim(output_context.log_file))
        pseudo_CT_output('ERROR', local_public_active_context(stage_context, public, 'ERROR'), ...
            'Compiled current %s phase failed (exit status %d); details are in %s.', ...
            upper(phase), status, strtrim(output_context.log_file));
    else
        pseudo_CT_output('ERROR', local_public_active_context(stage_context, public, 'ERROR'), ...
            'Compiled current %s phase failed with exit status %d.', ...
            upper(phase), status);
    end
    local_raise_current_runner_error(upper(phase), status);
end
pseudo_CT_output('SUCCESS', log_context, ...
    'Compiled current %s phase completed (elapsed %.1f s).', ...
    upper(phase), toc(phase_started));
end

function status = local_current_stream_test_dispatch(request)
required = {'command'; 'log_path'; 'context'};
for ii = 1:length(required)
    if ~isfield(request, required{ii})
        error('pseudo_CT:LocalCurrentRunnerTest', ...
            'Current stream test request is missing a required field.');
    end
end
if ~ischar(request.command) || ~ischar(request.log_path) || ...
        ~isstruct(request.context)
    error('pseudo_CT:LocalCurrentRunnerTest', ...
        'Current stream test request fields have invalid types.');
end
phase = 'TEST';
if isfield(request, 'phase') && ischar(request.phase)
    phase = upper(request.phase);
end
status = local_run_streaming(request.command, request.log_path, ...
    request.context, tic);
if status ~= 0 && isfield(request, 'fail_on_nonzero') && ...
        isequal(request.fail_on_nonzero, true)
    local_raise_current_runner_error(phase, status);
end
end

function local_raise_current_runner_error(phase, status)
error('pseudo_CT:LocalCurrentRunner', ...
    'Compiled current %s phase failed with exit status %d.', phase, status);
end

function status = local_run_streaming(command, log_path, output_context, ...
        phase_started, phase_label, public)
%LOCAL_RUN_STREAMING Tail a private capture of the merged child stream.
%   The merged compiled stdout/stderr is teed into a private capture file in
%   scratch. Every line is secret-filtered and appended to the per-subject run
%   log (success, failure, or interruption); only structured lifecycle events
%   reach the shared presenter. Startup and dependency chatter stay log-only.
if nargin < 5
    phase_label = 'test';
end
if nargin < 6
    public = containers.Map();
    public('stage') = 0;
    public('open') = false;
    public('started') = tic;
end
scratch_dir = local_current_scratch_dir();
status_path = fullfile(scratch_dir, 'runner.exit');
status_tmp_path = [status_path '.tmp'];
capture_path = fullfile(scratch_dir, 'runner.capture');
persist_path = '';
if ~isempty(log_path)
    persist_path = log_path;
    if exist(persist_path, 'dir') == 7
        error('pseudo_CT:LocalCurrentRunner', ...
            'The current runner output path is a directory.');
    end
    [path_check, ~] = system(['test ! -L ' local_shell_quote(persist_path)]);
    if path_check ~= 0
        error('pseudo_CT:LocalCurrentRunner', ...
            'The current runner output path is a symbolic link.');
    end
end
if exist(status_path, 'file') == 2
    delete(status_path);
end
if exist(status_tmp_path, 'file') == 2
    delete(status_tmp_path);
end

stream_state = containers.Map();
stream_state('offset') = 0;
stream_state('buffer') = '';
stream_state('in_warning') = false;
stream_state('warn_buf') = '';
stream_state('warn_lines') = 0;
stream_state('warn_counts') = containers.Map();
stream_state('warn_order') = {};
stream_state('public') = public;
% Drain, persist, and remove the private capture on every exit path.
stream_guard = onCleanup(@() local_finish_current_stream( ...
    capture_path, persist_path, stream_state, output_context)); %#ok<NASGU>

% Credential redaction (same pattern as local_redact_current_secrets) runs
% between the child and tee, so no unredacted line is ever written to a file.
% Fail closed: if the filter cannot run, nothing reaches the capture and the
% pipeline status is nonzero. The runner status is the first nonzero of
% child, filter, tee.
redact_filter = ['LC_ALL=C sed -u -E ' local_shell_quote( ...
    ['s/(username|user|password|passphrase|account|token|secret)' ...
    '([ \t]*[:=][ \t]*|[ \t]+)[^ \t,;]+/\1\2<redacted>/Ig'])];
pipeline_command = [command ' 2>&1 | ' redact_filter ' | tee -a ' ...
    local_shell_quote(capture_path) ...
    '; set -- ${PIPESTATUS[*]}; if [ "$1" -ne 0 ]; then ' ...
    'exit "$1"; fi; if [ "$2" -ne 0 ]; then exit "$2"; fi; exit "$3"'];
launch_command = ['( /bin/bash -o pipefail -c ' ...
    local_shell_quote(pipeline_command) ...
    '; runner_status=$?; printf "%s\n" "$runner_status" > ' ...
    local_shell_quote(status_tmp_path) '; mv -f ' ...
    local_shell_quote(status_tmp_path) ' ' ...
    local_shell_quote(status_path) '; exit "$runner_status" ) ' ...
    '</dev/null >/dev/null 2>&1 & echo $!'];
[launch_status, pid_text] = system(launch_command);
runner_pid = str2double(strtrim(pid_text));
if launch_status ~= 0 || ~isscalar(runner_pid) || ...
        ~isfinite(runner_pid) || runner_pid <= 0
    error('pseudo_CT:LocalCurrentRunner', ...
        'The current runner could not be started.');
end

last_activity = tic;
while true
    previous_offset = stream_state('offset');
    local_tail_current_output(capture_path, persist_path, stream_state, ...
        false, output_context);
    if stream_state('offset') > previous_offset
        last_activity = tic;
    elseif toc(last_activity) >= 60
        [heartbeat, heartbeat_context] = local_heartbeat_event( ...
            output_context, public, phase_label, phase_started);
        if strcmp(getenv('PSEUDOCT_CLI_OUTPUT'), '1')
            [heartbeat_visible, heartbeat_line] = ...
                pseudo_CT_output_console_visible('INFO', heartbeat, ...
                heartbeat_context);
            if heartbeat_visible && ~strcmp(getenv('PSEUDOCT_OUTPUT_FORMAT'), 'jsonl')
                fprintf(1, '%s\n', heartbeat_line);
            end
        end
        last_activity = tic;
    end
    [found, status] = local_read_current_runner_status(status_path);
    if found
        local_tail_current_output(capture_path, persist_path, ...
            stream_state, true, output_context);
        break;
    end
    [probe_status, ~] = system(sprintf('kill -0 %d', round(runner_pid)));
    if probe_status ~= 0
        [found, status] = local_read_current_runner_status(status_path);
        if found
            local_tail_current_output(capture_path, persist_path, ...
                stream_state, true, output_context);
            break;
        end
        local_tail_current_output(capture_path, persist_path, ...
            stream_state, true, output_context);
        error('pseudo_CT:LocalCurrentRunner', ...
            'The current runner ended without reporting an exit status.');
    end
    pause(0.1);
end

if exist(status_path, 'file') == 2
    delete(status_path);
end
if exist(status_tmp_path, 'file') == 2
    delete(status_tmp_path);
end
end

function scratch_dir = local_current_scratch_dir()
source_dir = fileparts(mfilename('fullpath'));
project_root = fileparts(fileparts(fileparts(source_dir)));
scratch_root = fullfile(project_root, 'scratch');
day_dir = fullfile(scratch_root, datestr(now, 'yyyy-mm-dd'));
paths = {scratch_root; day_dir};
for ii = 1:length(paths)
    [path_check, ~] = system(['test ! -L ' local_shell_quote(paths{ii})]);
    if path_check ~= 0
        error('pseudo_CT:LocalCurrentRunner', ...
            'The local-current scratch path must not be a symbolic link.');
    end
    if exist(paths{ii}, 'dir') ~= 7
        [made, message] = mkdir(paths{ii});
        if ~made && exist(paths{ii}, 'dir') ~= 7
            error('pseudo_CT:LocalCurrentRunner', ...
                'Could not create local-current scratch directory: %s', message);
        end
    end
end

stamp = datestr(now, 'HHMMSS');
for ii = 1:100
    if ii == 1
        suffix = '';
    else
        suffix = sprintf('-%d', ii);
    end
    candidate = fullfile(day_dir, [stamp '-local-current-runner' suffix]);
    [made, ~] = system(['mkdir -- ' local_shell_quote(candidate) ' 2>/dev/null']);
    if made == 0
        scratch_dir = candidate;
        return;
    end
end
error('pseudo_CT:LocalCurrentRunner', ...
    'Could not allocate a unique local-current scratch directory.');
end

function local_tail_current_output(capture_path, persist_path, ...
        stream_state, flush_console, output_context)
fid = fopen(capture_path, 'rb');
if fid ~= -1
    cleanup_fid = onCleanup(@() fclose(fid)); %#ok<NASGU>
    if fseek(fid, stream_state('offset'), 'bof') == 0
        while true
            new_bytes = fread(fid, 65536, 'uint8');
            if isempty(new_bytes)
                break;
            end
            new_bytes = uint8(new_bytes(:)');
            stream_state('offset') = stream_state('offset') + length(new_bytes);
            console_buffer = [stream_state('buffer') char(new_bytes)];
            while true
                newline_at = find(console_buffer == char(10), 1);
                if isempty(newline_at)
                    break;
                end
                console_line = console_buffer(1:newline_at - 1);
                console_buffer = console_buffer(newline_at + 1:end);
                % Store the remainder first so an interrupted handler cannot
                % replay or lose the following lines.
                stream_state('buffer') = console_buffer;
                if ~isempty(console_line) && console_line(end) == char(13)
                    console_line = console_line(1:end - 1);
                end
                local_handle_current_line(console_line, persist_path, ...
                    stream_state, output_context);
            end
            stream_state('buffer') = console_buffer;
        end
    end
end
if flush_console && ~isempty(stream_state('buffer'))
    console_line = stream_state('buffer');
    stream_state('buffer') = '';
    local_handle_current_line(console_line, persist_path, stream_state, ...
        output_context);
end
if flush_console
    % Child EOF, nonzero exit, or interruption: an open warning block is
    % never lost. Present it, then record the grouped counts in the log.
    local_flush_warning_block(stream_state, output_context);
end
if flush_console && strcmp(getenv('PSEUDOCT_CLI_OUTPUT'), '1')
    pseudo_CT_output_console_visible('FLUSH');
end
if flush_console
    local_log_warning_summary(persist_path, stream_state);
end
end

function local_finish_current_stream(capture_path, persist_path, ...
        stream_state, output_context)
% Runs on success, failure, and interruption. Never masks the original error.
try
    local_tail_current_output(capture_path, persist_path, stream_state, ...
        true, output_context);
catch %#ok<CTCH>
end
try
    if exist(capture_path, 'file') == 2
        delete(capture_path);
    end
catch %#ok<CTCH>
end
end

function local_handle_current_line(line, persist_path, stream_state, ...
        output_context)
% Detailed stream: secret-filtered before it is persisted or presented.
safe_line = local_redact_current_secrets(line);
if ~isempty(persist_path)
    fid = fopen(persist_path, 'a');
    if fid ~= -1
        try
            fprintf(fid, '%s\n', safe_line);
        catch %#ok<CTCH>
        end
        try
            fclose(fid);
        catch %#ok<CTCH>
        end
    end
end
local_print_current_console_line(safe_line, stream_state, output_context);
end

function local_flush_warning_block(stream_state, output_context)
%LOCAL_FLUSH_WARNING_BLOCK Present one complete (possibly multiline) warning.
%   Every raw line is already in the run log. The joined text keeps severity
%   WARN and all numerical content; only the public row is length-capped.
if ~stream_state.isKey('warn_buf') || isempty(stream_state('warn_buf'))
    return;
end
joined = stream_state('warn_buf');
stream_state('warn_buf') = '';
stream_state('warn_lines') = 0;
key = regexprep(joined, '^[{ \t]*[Ww]arning[ \t]*:[ \t]*', '');
key = strtrim(regexprep(key, '[} \t]+$', ''));
counts = stream_state('warn_counts');
if counts.isKey(key)
    counts(key) = counts(key) + 1;
else
    counts(key) = 1;
    stream_state('warn_order') = [stream_state('warn_order') {key}];
end
if ~strcmp(getenv('PSEUDOCT_CLI_OUTPUT'), '1')
    return;
end
public_text = joined;
if length(public_text) > 600
    public_text = [public_text(1:600) ' ... [truncated; full text in run log]}'];
end
warn_context = output_context;
if stream_state.isKey('public')
    warn_context = local_public_active_context(output_context, ...
        stream_state('public'), 'WARN');
end
pseudo_CT_output_console_visible('WARN', public_text, warn_context);
end

function local_log_warning_summary(persist_path, stream_state)
% Append exact per-text warning counts once, so grouped public counts can be
% reconciled with the raw occurrences that precede them in the log.
order = stream_state('warn_order');
if isempty(order) || isempty(persist_path)
    return;
end
counts = stream_state('warn_counts');
stream_state('warn_order') = {};
stream_state('warn_counts') = containers.Map();
fid = fopen(persist_path, 'a');
if fid == -1
    return;
end
try
    stamp = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    for ii = 1:length(order)
        fprintf(fid, '[%s] WARN    Warning summary: %d occurrence(s): %s\n', ...
            stamp, counts(order{ii}), local_redact_current_secrets(order{ii}));
    end
catch %#ok<CTCH>
end
try
    fclose(fid);
catch %#ok<CTCH>
end
end

function text = local_redact_current_secrets(text)
% Keep in lockstep with redact_secrets in bin/pseudoct.
text = regexprep(text, ...
    ['(?i)(username|user|password|passphrase|account|token|secret)' ...
    '([ \t]*[:=][ \t]*|[ \t]+)[^ \t,;]+'], '$1$2<redacted>');
end

function local_print_current_console_line(line, stream_state, output_context)
% Outside the CLI the original bracketed MATLAB logging is unchanged: nothing
% is echoed here and the detailed stream is only persisted to the run log.
in_block = stream_state('in_warning');
% The compiled MATLAB runtime emits "{<BS>Warning: ...}<BS>" (backspace,
% which STRTRIM does not remove). The raw line is already in the run log;
% classification, grouping and presentation use the backspace-free text.
line = line(line ~= char(8));
[line_class, line_level] = local_classify_current_line(line, stream_state);
% Warning blocks are joined and presented once, at the closing brace, at
% the next non-warning line, or at stream end (see local_flush_warning_block).
if strcmp(line_class, 'warning')
    local_flush_warning_block(stream_state, output_context);
    stream_state('warn_buf') = strtrim(line);
    stream_state('warn_lines') = 1;
    if ~stream_state('in_warning')
        local_flush_warning_block(stream_state, output_context);
    end
    return;
elseif strcmp(line_class, 'continuation') && ...
        ~isempty(stream_state('warn_buf'))
    stream_state('warn_buf') = [stream_state('warn_buf') ' ' strtrim(line)];
    stream_state('warn_lines') = stream_state('warn_lines') + 1;
    if ~stream_state('in_warning')
        local_flush_warning_block(stream_state, output_context);
    end
    return;
elseif strcmp(line_class, 'private') && in_block && isempty(strtrim(line))
    return;  % blank line inside an open warning block
end
local_flush_warning_block(stream_state, output_context);
if ~strcmp(getenv('PSEUDOCT_CLI_OUTPUT'), '1')
    return;
end
if strcmp(line_class, 'private')
    return;
end
context = output_context;
mapped = false;
if stream_state.isKey('public') && local_is_public_profile(output_context)
    % Local Current: map this compiled-stream event to its canonical public
    % stage event here (adapter layer); the presenter only formats it.
    [context, mapped] = local_canonical_stream_event(line, ...
        output_context, stream_state('public'));
end
if ~mapped && (strcmp(line_class, 'unstructured') || ...
        strcmp(line_class, 'continuation'))
    % Only phrases the presenter recognizes as lifecycle events may surface;
    % the stage-based ACTIVE fallback must not apply to child chatter.
    context.console_unstructured = true;
end
[console_visible, console_line] = pseudo_CT_output_console_visible( ...
    line_level, line, context);
if console_visible
    if ~strcmp(getenv('PSEUDOCT_OUTPUT_FORMAT'), 'jsonl')
        fprintf(1, '%s\n', console_line);
    end
end
end

function [line_class, line_level] = local_classify_current_line(line, stream_state)
%LOCAL_CLASSIFY_CURRENT_LINE Separate child chatter from public events.
%   event        timestamped orchestration record from the payload
%   warning      start of a MATLAB {Warning: ...} block
%   continuation open multi-line warning text
%   error        MATLAB/runner error line
%   private      startup/environment chatter, stack frames, SPM batch and
%                dcm2nii diagnostics (log only)
%   unstructured anything else; surfaces only if the presenter recognizes it
line_class = 'unstructured';
line_level = 'INFO';
text = strtrim(line);
lowered = lower(text);
if isempty(text)
    line_class = 'private';
    return;
end
if ~isempty(regexp(text, ...
        '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\][ \t]+(INFO|WARN|ERROR|SUCCESS)[ \t]', ...
        'once'))
    stream_state('in_warning') = false;
    line_class = 'event';
    return;
end
if ~isempty(regexp(lowered, '^(>+[ \t]*)?in .+ at [0-9]+$', 'once')) || ...
        ~isempty(regexp(lowered, '^error in .+ at [0-9]+$', 'once'))
    line_class = 'private';
    return;
end
if ~isempty(regexp(lowered, '^[{ \t]*warning[ \t]*:', 'once'))
    % Only a brace-opened block spans lines; a bare "Warning:" is one line.
    stream_state('in_warning') = text(1) == '{' && isempty(strfind(text, '}'));
    line_class = 'warning';
    line_level = 'WARN';
    return;
end
if stream_state('in_warning')
    if ~isempty(strfind(text, '}'))
        stream_state('in_warning') = false;
    end
    line_class = 'continuation';
    return;
end
if strncmp(lowered, 'error', 5) || strncmp(lowered, '??? error', 9)
    line_class = 'error';
    line_level = 'ERROR';
    return;
end
chatter = { ...
    '^-+$', ...
    '^setting up environment variables', ...
    '^(ld_library_path|xapplresdir|mcr_cache_root|mcrroot)\b', ...
    '^no display', '^no window system', '^java option', ...
    '^new segment batch save diagnostics', ...
    '^(filename|paths|destination directory|matlabbatch|top-level batch fields)\b.*[:,]', ...
    '^chris rorden', '^dcm2nii\b', '^compression will be', ...
    '^found [0-9]+ dicom', '^convert [0-9]+ dicom', '^conversion required'};
for ii = 1:length(chatter)
    if ~isempty(regexp(lowered, chatter{ii}, 'once'))
        line_class = 'private';
        return;
    end
end
end
function [found, status] = local_read_current_runner_status(status_path)
found = false;
status = -1;
fid = fopen(status_path, 'r');
if fid == -1
    return;
end
raw = fscanf(fid, '%c');
fclose(fid);
candidate = str2double(strtrim(char(raw)));
if isscalar(candidate) && isfinite(candidate) && ...
        candidate == floor(candidate) && candidate >= 0
    found = true;
    status = candidate;
end
end

function local_validate_handoff(handoff, job_manifest_path, ...
        resource_manifest_path, atlas_dir)
required = {'schema'; 'input_selected'; 'atlas_dir'; ...
    'needs_normalization'; 'normalized_expected'; 'job_manifest'; ...
    'resource_manifest'};
for ii = 1:length(required)
    if ~isfield(handoff, required{ii})
        error('pseudo_CT:LocalCurrentPrepare', ...
            'Compiled current handoff is missing required data.');
    end
end
if ~ischar(handoff.schema) || ...
        ~strcmp(handoff.schema, 'pseudo-CT.current-handoff/v1') || ...
        ~ischar(handoff.job_manifest) || ...
        ~strcmp(handoff.job_manifest, job_manifest_path) || ...
        ~ischar(handoff.resource_manifest) || ...
        ~strcmp(handoff.resource_manifest, resource_manifest_path) || ...
        ~ischar(handoff.atlas_dir) || ...
        ~strcmp(local_strip_sep(handoff.atlas_dir), local_strip_sep(atlas_dir)) || ...
        ~islogical(handoff.needs_normalization) || ...
        ~isscalar(handoff.needs_normalization)
    error('pseudo_CT:LocalCurrentPrepare', ...
        'Compiled current handoff does not match this local invocation.');
end
local_controlled_nii(handoff.input_selected, 'selected input');
local_controlled_nii(handoff.normalized_expected, 'normalized output');
expected = local_derived_normalized(strtrim(handoff.input_selected));
if ~strcmp(expected, strtrim(handoff.normalized_expected))
    error('pseudo_CT:LocalCurrentPrepare', ...
        'Compiled current handoff contains contradictory input paths.');
end
selected_is_normalized = ~isempty(strfind( ...
    strtrim(handoff.input_selected), '_normalized.nii'));
if logical(handoff.needs_normalization) == selected_is_normalized || ...
        exist(strtrim(handoff.input_selected), 'file') ~= 2
    error('pseudo_CT:LocalCurrentPrepare', ...
        'Compiled current handoff normalization state is inconsistent.');
end
end

function local_controlled_nii(path_text, label)
if ~ischar(path_text) || size(path_text, 1) ~= 1 || ...
        isempty(strtrim(path_text)) || any(path_text == char(0)) || ...
        ~isempty(strfind(path_text, '..'))
    error('pseudo_CT:LocalCurrentPrepare', ...
        'Compiled current handoff %s is invalid.', label);
end
trimmed = strtrim(path_text);
if length(trimmed) >= 2 && strcmp(trimmed(end-1:end), ',1')
    trimmed = trimmed(1:end-2);
end
if length(trimmed) < 5 || ~strcmp(lower(trimmed(end-3:end)), '.nii')
    error('pseudo_CT:LocalCurrentPrepare', ...
        'Compiled current handoff %s is not a NIfTI path.', label);
end
end

function expected = local_derived_normalized(selected)
[pathn, namen, extn] = fileparts(selected);
if length(extn) >= 2 && strcmp(extn(end-1:end), ',1')
    extn = extn(1:end-2);
end
if isempty(extn)
    extn = '.nii';
end
expected = fullfile(pathn, [namen '_normalized' extn]);
end

function valid = local_yes_no_or_flag(value)
valid = false;
if ischar(value) && size(value, 1) == 1
    valid = strcmp(value, 'Yes') || strcmp(value, 'No');
elseif (islogical(value) || isnumeric(value)) && isscalar(value) && ...
        isfinite(double(value)) && ismember(double(value), [0 1])
    valid = true;
end
end

function value = local_strip_sep(value)
value = strtrim(value);
while length(value) > 1 && value(end) == '/'
    value(end) = '';
end
end

function context = local_stage_context(context, stage_index)
context.stage_index = stage_index;
if isfield(context, 'stage_map') && isstruct(context.stage_map) && ...
        isfield(context.stage_map, 'producer_total') && ...
        context.stage_map.producer_total > 0
    [~, public_stage, public_total] = pseudo_CT_stage_map( ...
        context.stage_map, stage_index, context.stage_map.producer_total);
    if public_stage > 0
        context.stage_index = public_stage;
        context.stage_count = public_total;
        return;
    end
end
if ~(local_is_public_profile(context) && isfield(context, 'stage_count') && ...
        isnumeric(context.stage_count) && isscalar(context.stage_count) && ...
        any(context.stage_count == [9 10]))
    context.stage_count = 9;
end
end

%% ========================================================================
%  LOCAL CURRENT PUBLIC STAGES (canonical events)
%  ========================================================================
% Public stages: 1 input MPRAGE, 2 MPRAGE recentering, 3 aliasing correction,
% 4 FreeSurfer normalization, 5 alignment and masking, 6 SPM New Segment,
% 7 DARTEL registration, 8 attenuation map and QC, 9 DICOM output (omitted
% for NIfTI-only), then output promotion (10, or 9 for NIfTI-only). The
% orchestrator reports 1, DICOM and promotion; this adapter reports 2-8.
% A canonical event is a context with stage_index, stage_count (total from
% the resolved output policy), stage_status (START, DONE, SKIPPED, INFO,
% WARN, ERROR or LOG) and optional stage_message. Active-computation
% heartbeats are INFO events naming the operation.
function yes = local_is_public_profile(output_context)
yes = isfield(output_context, 'console_profile') && ...
    ischar(output_context.console_profile) && ...
    any(strcmp(output_context.console_profile, ...
    {'local-current'; 'local-mprage-only'}));
end

function name = local_public_name(stage_number, output_context)
name = '';
if ~isfield(output_context, 'stage_map') || ...
        ~isstruct(output_context.stage_map)
    return;
end
[~, ~, ~, name] = pseudo_CT_stage_map(output_context.stage_map, ...
    stage_number, output_context.stage_map.producer_total);
end

function context = local_public_context(context, stage_number, status, message)
% Canonical event context for Local Current; other profiles keep the legacy
% stage tag.
if ~local_is_public_profile(context)
    context = local_stage_context(context, 2);
    return;
end
total = 10;
if isfield(context, 'stage_count') && isnumeric(context.stage_count) && ...
        isscalar(context.stage_count) && any(context.stage_count == [9 10])
    total = context.stage_count;
end
context.stage_index = stage_number;
context.stage_count = total;
context.stage_status = status;
if nargin > 3 && ~isempty(message)
    context.stage_message = message;
elseif isfield(context, 'stage_message')
    context = rmfield(context, 'stage_message');
end
end

function context = local_public_log_context(context)
% Run-log-only detail (never a console row).
if local_is_public_profile(context)
    context.stage_status = 'LOG';
end
end

function public = local_public_set(public, stage_number, is_open)
public('stage') = stage_number;
public('open') = is_open;
public('started') = tic;
end

function context = local_public_active_context(context, public, status)
% Context of the currently active public stage (for WARN and ERROR rows).
if ~local_is_public_profile(context) || public('stage') < 1
    return;
end
context = local_public_context(context, public('stage'), status);
end

function [text, context] = local_heartbeat_event(output_context, public, phase_label, phase_started)
% Heartbeat names the operation actually running: the open public stage, or
% the compiled phase when no stage is open.
if local_is_public_profile(output_context) && public('open')
    operation = local_public_name(public('stage'), output_context);
    elapsed = local_current_elapsed(toc(public('started')));
else
    operation = sprintf('Compiled current %s phase', upper(phase_label));
    elapsed = local_current_elapsed(toc(phase_started));
end
text = sprintf('%s still running (elapsed %s).', operation, elapsed);
context = output_context;
if local_is_public_profile(output_context) && public('stage') >= 1
    context = local_public_context(output_context, public('stage'), 'INFO');
end
end

function [context, mapped] = local_canonical_stream_event(line, output_context, public)
%LOCAL_CANONICAL_STREAM_EVENT Canonical event for a compiled-stream line.
%   The stage knowledge of the compiled PREPARE/COMPUTE messages lives here.
%   Lines that are not stage events keep the active stage context only.
context = output_context;
mapped = false;
active = public('stage');
if active >= 1
    context = local_public_context(output_context, active, 'INFO');
    context = rmfield(context, 'stage_status');
end
tokens = regexp(line, ...
    '^\[[^\]]+\][ \t]+(INFO|WARN|ERROR|SUCCESS)[ \t]+(.*)$', 'tokens', 'once');
if isempty(tokens)
    return;
end
level = tokens{1};
body = tokens{2};
while true
    stripped = regexprep(body, ...
        ['^\[(stage[ \t]+[0-9]+/[0-9]+|subject[^\]]*|run|job[^\]]*|' ...
         'mlsc[^\]]*)\][ \t]*'], '', 'ignorecase');
    if strcmp(stripped, body)
        break;
    end
    body = stripped;
end
text = lower(strtrim(body));

% Outcome events without a start event (stages 2 and 3).
outcome = {'[recentering]', 2; '[aliasing correction]', 3};
for ii = 1:size(outcome, 1)
    if strncmp(text, outcome{ii, 1}, length(outcome{ii, 1}))
        rest = strtrim(body(length(outcome{ii, 1}) + 1:end));
        rest_lower = lower(rest);
        n = outcome{ii, 2};
        if strcmp(level, 'ERROR')
            status = 'ERROR';
        elseif strncmp(rest_lower, 'skipped', 7) || ...
                strncmp(rest_lower, 'not required', 12)
            status = 'SKIPPED';
        elseif strncmp(rest_lower, 'successfully applied', 20)
            status = 'DONE';
        else
            return;  % other detail keeps the generic path
        end
        context = local_public_context(output_context, n, status, ...
            [local_public_name(n, output_context) ' ' ...
             lower(rest(1)) rest(2:end)]);
        public('stage') = n;
        public('open') = false;
        mapped = true;
        return;
    end
end

if strcmp(level, 'WARN') || strcmp(level, 'ERROR')
    return;
end
starts = {'aligning mprage and creating subject mask', 5; ...
    'running spm new segment', 6; 'starting the new segment process', 6; ...
    'registering atlases with dartel', 7; ...
    'starting the dartel coregistration process', 7; ...
    'building attenuation map and qc image', 8};
dones = {'alignment and masking completed (elapsed ', 5; ...
    'segmentation completed (elapsed ', 6; ...
    'atlas registration completed (elapsed ', 7; ...
    'attenuation map and qc completed (elapsed ', 8};
substeps = {'applying inverse warp', 'reslicing atlases into mprage space', ...
    'coregistration and reslicing finished', 'starting the inverse warped process', ...
    'starting the final reslicing', 'done ''create inverse warped'''};
if strcmp(level, 'INFO')
    for ii = 1:size(starts, 1)
        if strncmp(text, starts{ii, 1}, length(starts{ii, 1}))
            n = starts{ii, 2};
            if public('stage') == n && public('open')
                status = 'INFO';   % further message of the running stage
            else
                status = 'START';
                public('started') = tic;
            end
            public('stage') = n;
            public('open') = true;
            context = local_public_context(output_context, n, status);
            mapped = true;
            return;
        end
    end
    if public('stage') == 7
        for ii = 1:length(substeps)
            if strncmp(text, substeps{ii}, length(substeps{ii}))
                context = local_public_context(output_context, 7, 'INFO');
                mapped = true;
                return;
            end
        end
    end
elseif strcmp(level, 'SUCCESS')
    for ii = 1:size(dones, 1)
        if strncmp(text, dones{ii, 1}, length(dones{ii, 1}))
            n = dones{ii, 2};
            public('stage') = n;
            public('open') = false;
            context = local_public_context(output_context, n, 'DONE');
            mapped = true;
            return;
        end
    end
end
end

function local_normalization_failed(output_context, reason)
% Canonical stage-4 ERROR event (no stage-4 DONE follows).
pseudo_CT_output('ERROR', local_public_context(output_context, 4, 'ERROR'), ...
    'MPRAGE normalization failed: %s', reason);
end

function value = local_current_elapsed(seconds)
seconds = max(0, floor(seconds));
hours = floor(seconds / 3600);
minutes = floor(rem(seconds, 3600) / 60);
seconds = rem(seconds, 60);
if hours > 0
    value = sprintf('%02d:%02d:%02d', hours, minutes, seconds);
else
    value = sprintf('%02d:%02d', minutes, seconds);
end
end

function safe = local_runner_argument_safe(value)
safe = ischar(value) && size(value, 1) == 1 && ~isempty(value) && ...
    ~any(value == char(0));
if ~safe
    return;
end
unsafe_characters = [';' '&' '|' '`' '$' '(' ')' '{' '}' '[' ']' ...
    '<' '>' '!' char(92) char(39) char(34)];
safe = isempty(intersect(value, unsafe_characters));
end

function quoted = local_shell_quote(value)
if ~ischar(value) || size(value, 1) ~= 1 || any(value == char(0))
    error('pseudo_CT:LocalCurrentRunner', ...
        'A current runner shell argument is invalid.');
end
single_quote = char(39);
double_quote = char(34);
quoted = single_quote;
for ii = 1:length(value)
    if value(ii) == single_quote
        quoted = [quoted single_quote double_quote single_quote ...
            double_quote single_quote]; %#ok<AGROW>
    else
        quoted = [quoted value(ii)]; %#ok<AGROW>
    end
end
quoted = [quoted single_quote];
end
