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

local_run_phase(config.current, 'prepare', job_manifest_path, ...
    config.current.resource_manifest, output_context);

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
    normalization_context = local_stage_context(output_context, 2);
    normalization_started = tic;
    pseudo_CT_output('INFO', normalization_context, ...
        'Normalizing MPRAGE with FreeSurfer.');
    normalized_path = strtrim(handoff.normalized_expected);
    if exist(normalized_path, 'file') == 2
        error('pseudo_CT:LocalCurrentNormalization', ...
            'An existing normalized output prevents fail-closed local normalization.');
    end
    normalization_connection = struct('hostname', config.normalization.host, ...
        'username', 'local', 'password', '', 'autoreconnect', 0);
    normalization_command = sprintf('mri_normalize %s %s', ...
        selected_input, normalized_path);
    normalization_status = run_normalization_cmd(normalization_command, ...
        normalization_connection, normalization_context, config);
    normalized_info = dir(normalized_path);
    if normalization_status ~= 0 || isempty(normalized_info) || ...
            normalized_info(1).bytes == 0
        error('pseudo_CT:LocalCurrentNormalization', ...
            'FreeSurfer did not produce a non-empty normalized NIfTI file.');
    end
    pseudo_CT_output('SUCCESS', normalization_context, ...
        'MPRAGE normalization completed (elapsed %s).', ...
        local_current_elapsed(toc(normalization_started)));
else
    normalization_context = local_stage_context(output_context, 2);
    pseudo_CT_output('INFO', normalization_context, ...
        'Normalization input already normalized; skipping.');
    normalized_path = selected_input;
end

if exist(normalized_path, 'file') ~= 2
    error('pseudo_CT:LocalCurrentNormalization', ...
        'The current payload normalized input is unavailable.');
end
local_run_phase(config.current, 'compute', job_manifest_path, ...
    config.current.resource_manifest, output_context);

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
        resource_manifest_path, output_context)
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
pseudo_CT_output('INFO', stage_context, ...
    'Running compiled current %s phase.', upper(phase));
if strcmp(phase, 'compute')
    pseudo_CT_output('INFO', stage_context, ...
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
    phase_started);
if status ~= 0
    if isfield(output_context, 'log_file') && ...
            ischar(output_context.log_file) && ...
            ~isempty(strtrim(output_context.log_file))
        pseudo_CT_output('ERROR', stage_context, ...
            'Compiled current %s phase failed (exit status %d); details are in %s.', ...
            upper(phase), status, strtrim(output_context.log_file));
    else
        pseudo_CT_output('ERROR', stage_context, ...
            'Compiled current %s phase failed with exit status %d.', ...
            upper(phase), status);
    end
    local_raise_current_runner_error(upper(phase), status);
end
pseudo_CT_output('SUCCESS', stage_context, ...
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
        phase_started)
%LOCAL_RUN_STREAMING Tail the tee file through MATLAB's byte-oriented reader.
scratch_dir = local_current_scratch_dir();
status_path = fullfile(scratch_dir, 'runner.exit');
status_tmp_path = [status_path '.tmp'];
if isempty(log_path)
    stream_path = fullfile(scratch_dir, 'runner.capture');
else
    stream_path = log_path;
end
if exist(stream_path, 'dir') == 7
    error('pseudo_CT:LocalCurrentRunner', ...
        'The current runner output path is a directory.');
end
[path_check, ~] = system(['test ! -L ' local_shell_quote(stream_path)]);
if path_check ~= 0
    error('pseudo_CT:LocalCurrentRunner', ...
        'The current runner output path is a symbolic link.');
end
stream_info = dir(stream_path);
byte_offset = 0;
if ~isempty(stream_info)
    byte_offset = stream_info(1).bytes;
end
if exist(status_path, 'file') == 2
    delete(status_path);
end
if exist(status_tmp_path, 'file') == 2
    delete(status_tmp_path);
end

pipeline_command = [command ' 2>&1 | tee -a ' ...
    local_shell_quote(stream_path) ...
    '; set -- ${PIPESTATUS[*]}; if [ "$1" -ne 0 ]; then ' ...
    'exit "$1"; fi; exit "$2"'];
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

console_buffer = '';
last_activity = tic;
while true
    previous_offset = byte_offset;
    [byte_offset, console_buffer] = local_tail_current_output( ...
        stream_path, byte_offset, console_buffer, false, output_context);
    if byte_offset > previous_offset
        last_activity = tic;
    elseif toc(last_activity) >= 60
        heartbeat = sprintf('Current processing still running (elapsed %s).', ...
            local_current_elapsed(toc(phase_started)));
        if strcmp(getenv('PSEUDOCT_CLI_OUTPUT'), '1')
            [heartbeat_visible, heartbeat_line] = ...
                pseudo_CT_output_console_visible('INFO', heartbeat, output_context);
            if heartbeat_visible
                fprintf(1, '%s\n', heartbeat_line);
            end
        end
        last_activity = tic;
    end
    [found, status] = local_read_current_runner_status(status_path);
    if found
        local_tail_current_output(stream_path, byte_offset, console_buffer, ...
            true, output_context);
        break;
    end
    [probe_status, ~] = system(sprintf('kill -0 %d', round(runner_pid)));
    if probe_status ~= 0
        [found, status] = local_read_current_runner_status(status_path);
        if found
            local_tail_current_output(stream_path, byte_offset, console_buffer, ...
                true, output_context);
            break;
        end
        local_tail_current_output(stream_path, byte_offset, console_buffer, ...
            true, output_context);
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
if isempty(log_path) && exist(stream_path, 'file') == 2
    delete(stream_path);
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

function [byte_offset, console_buffer] = local_tail_current_output( ...
        log_path, byte_offset, console_buffer, flush_console, output_context)
fid = fopen(log_path, 'rb');
if fid ~= -1
    if fseek(fid, byte_offset, 'bof') == 0
        while true
            new_bytes = fread(fid, 65536, 'uint8');
            if isempty(new_bytes)
                break;
            end
            new_bytes = uint8(new_bytes(:)');
            byte_offset = byte_offset + length(new_bytes);
            console_buffer = [console_buffer char(new_bytes)]; %#ok<AGROW>
            while true
                newline_at = find(console_buffer == char(10), 1);
                if isempty(newline_at)
                    break;
                end
                console_line = console_buffer(1:newline_at - 1);
                if ~isempty(console_line) && console_line(end) == char(13)
                    console_line = console_line(1:end - 1);
                end
                local_print_current_console_line(console_line, output_context);
                console_buffer = console_buffer(newline_at + 1:end);
            end
        end
    end
    fclose(fid);
end
if flush_console && ~isempty(console_buffer)
    local_print_current_console_line(console_buffer, output_context);
    console_buffer = '';
end
if flush_console && strcmp(getenv('PSEUDOCT_CLI_OUTPUT'), '1')
    pseudo_CT_output_console_visible('FLUSH');
end
end

function local_print_current_console_line(line, output_context)
if ~strcmp(getenv('PSEUDOCT_CLI_OUTPUT'), '1')
    return;
end
line_level = 'INFO';
severity_probe = lower(strtrim(line));
if strncmp(severity_probe, 'warn', 4)
    line_level = 'WARN';
elseif strncmp(severity_probe, 'error', 5) || ...
        strncmp(severity_probe, '??? error', 9)
    line_level = 'ERROR';
end
[console_visible, console_line] = pseudo_CT_output_console_visible( ...
    line_level, line, output_context);
if console_visible
    if ~strcmp(getenv('PSEUDOCT_OUTPUT_FORMAT'), 'jsonl')
        fprintf(1, '%s\n', console_line);
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
context.stage_count = 9;
if isfield(context, 'console_profile') && ischar(context.console_profile) && ...
        strcmp(context.console_profile, 'local-mprage-only')
    context.stage_count = 8;
end
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
