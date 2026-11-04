% Date: May/28/2026;
% Standalone copy of the piano_mMR Launchpad status helper.

function [ss_tot, queue_time, run_time] = check_launchpad_command_status(jobname, varargin)

if nargin < 6 || ~isstruct(varargin{end})
    error('pseudo_CT:ProfileRequired', ...
        'check_launchpad_command_status requires the selected profile config.');
end
config = varargin{end};
output_context = struct();
if length(varargin) >= 6 && isstruct(varargin{end - 1})
    output_context = varargin{end - 1};
end

pause_time = 30;
init_pause = 90;
jobnum = 1;
queue_time = [];
run_time = [];

if nargin > 1
    ssh2_conn = varargin{1};
else
    [PASSWORD, USERNAME] = passwordEntryDialog('enterUserName', true, 'ValidatePassword', true, 'PasswordLengthMax', 50, ...
        'WindowName', 'Enter your Martinos Login and Password to connect to Launchpad and check your jobs!');
    HOSTNAME = config.launchpad.host;

    % Legacy output: disp('Starting the ssh connection to Launchpad to check the job status  ... (be patient!)');
    pseudo_CT_output('INFO', output_context, 'Connecting to Launchpad to check job status.');
    ssh2_conn = ssh2_config(HOSTNAME, USERNAME, PASSWORD);
end
if nargin > 2
    pause_time = varargin{2};
end
if nargin > 3
    init_pause = varargin{3};
end
if nargin > 4
    jobnum = varargin{4};
end

% Legacy output: disp(sprintf('\nWaiting for %d seconds to start verifying ... ', init_pause));
pseudo_CT_output('INFO', output_context, 'Waiting %d seconds before the first status check.', init_pause);
pause(init_pause);
if ~iscell(jobname)
    aux = jobname;
    clear jobname;
    jobname{1, :} = aux;
end
ss_tot = [];
log_cursors = cell(length(jobname), 1);
for ii = 1:length(jobname)
    log_cursors{ii} = local_empty_log_cursor();
end
if isrow(jobname)
    jobname = jobname';
end
for ii=1:length(jobname)
    jobn = jobname{ii, :};
    jnum = jobnum(:, ii);
    ss = [];
    job_started = tic;
    subject_context = local_subject_output_context( ...
        output_context, ii, length(jobname), jnum);
    % Remote status text (compute host, generated-script block, PBS status,
    % JOB INFO) is diagnostic: it goes to the protected run log only.
    [ssh2_conn, ~] = launchpad_quiet_command(ssh2_conn, ...
        sprintf('cat /pbs/%s/%s.status | grep compute', ssh2_conn.username, jobn), subject_context);
    node = ssh2_command_response(ssh2_conn);
    counter = 0;
    f = 0;
    nodedown{1, 1} = '';
    while length(ss) == 0
        if counter * pause_time > 3000
            [ssh2_conn, ~] = launchpad_quiet_command(ssh2_conn, ...
                sprintf('ping %s.nmr.mgh.harvard.edu -c 1 | grep "Destination Host Unreachable"', node{1, 1}), subject_context);
            nodedown = ssh2_command_response(ssh2_conn);
            counter = 0;
        end

        [ssh2_conn, commando] = launchpad_quiet_command(ssh2_conn, ...
            sprintf('cat /pbs/%s/%s.status', ssh2_conn.username, jobn), subject_context);
        if length(nodedown{1, 1}) == 0
            commando = commando{end};
            ss = strfind(commando, 'status ');
            if length(ss) ~= 0
                break;
            end
            [ssh2_conn, log_cursors{ii}] = local_read_pbs_logs( ...
                ssh2_conn, jobn, jnum, log_cursors{ii}, subject_context);
            % Scheduler heartbeat: numeric PBS job ID, no stage cell.
            pseudo_CT_output('INFO', subject_context, ...
                'Launchpad job %d still active (elapsed %s).', ...
                jnum, local_elapsed(toc(job_started)));
            pause(pause_time);
            counter = counter + 1;
        else
            keep_command{f, :} = commando{4, :}; %#ok<AGROW>
            f = f + 1;
            commando(ss+7:end) = '';
            commando = [commando, '707'];
        end
    end
    [ssh2_conn, log_cursors{ii}] = local_read_pbs_logs( ...
        ssh2_conn, jobn, jnum, log_cursors{ii}, subject_context);
    [ssh2_conn, ~] = launchpad_quiet_command(ssh2_conn, ...
        sprintf('jobinfo %i', jnum), subject_context);
    ss_tot(ii) = str2num(commando(ss+7:end)); %#ok<ST2NM>
    if ss_tot(ii) ~= 0
        % Legacy output: disp(sprintf('\n##################################################\nSomething has gone wrong and the job %d has failed with code %d\n##################################################', jobn, ss_tot(ii)));
        detail_context = output_context;
        if isfield(detail_context, 'log_files')
            detail_context = rmfield(detail_context, 'log_files');
        end
        if isfield(output_context, 'subject_log_files') && ...
                length(output_context.subject_log_files) >= ii
            detail_context.log_file = output_context.subject_log_files{ii};
            detail_context.subject_index = ii;
            detail_context.subject_count = length(jobname);
        end
        detail_context.job_number = jnum;
        pseudo_CT_output('WARN', detail_context, ...
            'Failure detail: Launchpad job %d exited with code %d.', jnum, ss_tot(ii));
    else
        % Scheduler terminal exit status for this job (INFO row). Exit 0 is
        % not scientific completion; verification happens after retrieval.
        pseudo_CT_output('SUCCESS', subject_context, ...
            'Remote processing wait completed for job %d (exit status %d, elapsed %s).', ...
            jnum, ss_tot(ii), local_elapsed(toc(job_started)));
    end
    if pause_time > 60
        pause_time = 60;
    end
end
if sum(ss_tot(:)) ~= 0
    % Legacy output: disp(sprintf('Something has gone wrong with some of the jobs:\n'));
    for ii=1:length(jobname)
        % Legacy output: disp(sprintf('%s: %d\n', jobname{ii, :}, ss_tot(ii)));
    end
return
end
% Legacy output: disp(sprintf('\n\nGood News Everyone!! The commands ran properly!\n\n'));
% Per-job exit rows above already report the scheduler status; this summary is
% log-only so no console row reads as a completion claim.
summary_context = output_context;
summary_context.console_detail_only = true;
summary_context.console_detail_remote = true;
pseudo_CT_output('INFO', summary_context, ...
    'All Launchpad jobs reported exit status 0.');
return
end

function context = local_subject_output_context(output_context, subject_index, ...
        subject_count, job_number)
context = output_context;
context.console_profile = 'launchpad-legacy';
context.subject_index = subject_index;
context.subject_count = subject_count;
context.job_number = job_number;
if isfield(context, 'subject_log_files') && ...
        length(context.subject_log_files) >= subject_index
    context.log_file = context.subject_log_files{subject_index};
end
end

function cursor = local_empty_log_cursor()
cursor = struct('stdout_lines', 0, 'stderr_lines', 0, ...
    'stdout_diagnostic', '', 'stderr_diagnostic', '', ...
    'stdout_braced', false, 'stderr_braced', false, ...
    'stdout_diagnostic_lines', 0, 'stderr_diagnostic_lines', 0, ...
    'stdout_error_using', false, 'stderr_error_using', false, ...
    'stdout_blank_seen', false, 'stderr_blank_seen', false);
end

function [ssh2_conn, cursor] = local_read_pbs_logs(ssh2_conn, job_name, ...
        job_number, cursor, output_context)
if ~ischar(job_name) || isempty(regexp(job_name, ...
        '^pbsjob_[A-Za-z0-9_.-]+$', 'once')) || ...
        ~isnumeric(job_number) || ~isscalar(job_number) || ...
        ~isfinite(job_number) || job_number < 1 || ...
        job_number ~= floor(job_number)
    return;
end
for ii = 1:2
    if ii == 1
        stream = 'stdout';
        suffix = 'o';
        cursor_field = 'stdout_lines';
    else
        stream = 'stderr';
        suffix = 'e';
        cursor_field = 'stderr_lines';
    end
    remote_file = sprintf('%s.%s%.0f', job_name, suffix, job_number);
    offset = cursor.(cursor_field);
    marker = '__PSEUDOCT_PBS_LINES__';
    command = sprintf(['if [ -f "%s" ]; then n=$(wc -l < "%s"); ' ...
        's=%d; if [ "$n" -lt %d ]; then s=1; fi; ' ...
        'printf "%s%%s\\n" "$n"; ' ...
        'if [ "$n" -ge "$s" ]; then tail -n +"$s" "%s" | ' ...
        'head -n "$((n-s+1))"; fi; fi'], ...
        remote_file, remote_file, offset + 1, offset, marker, remote_file);
    try
        % Every raw PBS output line is recorded in the protected run log by
        % the quiet helper; only WARN/ERROR text is forwarded to the console.
        [ssh2_conn, response] = launchpad_quiet_command(ssh2_conn, command, ...
            output_context);
        if ischar(response)
            response = regexp(response, '\r?\n', 'split');
        end
        if ~iscell(response)
            continue;
        end
        marker_index = [];
        line_count = [];
        for jj = 1:length(response)
            if ischar(response{jj}) && strncmp(response{jj}, marker, ...
                    length(marker))
                marker_index = jj;
                line_count = str2double(response{jj}(length(marker) + 1:end));
                break;
            end
        end
        if isempty(marker_index) || ~isfinite(line_count) || ...
                line_count < 0 || line_count ~= floor(line_count)
            continue;
        end
        cursor.(cursor_field) = line_count;
        for jj = marker_index + 1:length(response)
            if ~ischar(response{jj})
                continue;
            end
            cursor = local_forward_pbs_log_line(response{jj}, stream, ...
                cursor, output_context);
        end
    catch %#ok<CTCH>
    end
end
end

function cursor = local_forward_pbs_log_line(line, stream, cursor, context)
diagnostic_field = [stream '_diagnostic'];
braced_field = [stream '_braced'];
diagnostic_lines_field = [stream '_diagnostic_lines'];
error_using_field = [stream '_error_using'];
blank_seen_field = [stream '_blank_seen'];
if local_launchpad_is_noise(line)
    return;
end
[level, message, stage, event_time] = local_launchpad_log_event(line);
if isempty(strtrim(line))
    if cursor.(error_using_field)
        cursor.(blank_seen_field) = true;
    end
    return;
end
if isempty(level)
    text = lower(strtrim(line));
    if cursor.(error_using_field) && ...
            local_launchpad_error_body_continuation(line, cursor, ...
            blank_seen_field)
        cursor.(blank_seen_field) = false;
        is_continuation = true;
    elseif cursor.(error_using_field)
        cursor.(diagnostic_field) = '';
        cursor.(braced_field) = false;
        cursor.(diagnostic_lines_field) = 0;
        cursor.(error_using_field) = false;
        cursor.(blank_seen_field) = false;
        return;
    else
        is_continuation = ~isempty(cursor.(diagnostic_field)) && ...
            cursor.(diagnostic_lines_field) < 32 && ...
            (cursor.(braced_field) || local_starts_with(text, '> in ') || ...
             local_starts_with(text, 'in ') || ...
             local_starts_with(text, 'caused by:') || ...
             local_starts_with(text, 'error in '));
    end
    if is_continuation
        level = cursor.(diagnostic_field);
        message = local_launchpad_safe_message(line);
        cursor.(diagnostic_lines_field) = ...
            cursor.(diagnostic_lines_field) + 1;
        if ~isempty(strfind(line, '}'))
            cursor.(braced_field) = false;
        end
    else
        cursor.(diagnostic_field) = '';
        cursor.(braced_field) = false;
        cursor.(diagnostic_lines_field) = 0;
        cursor.(error_using_field) = false;
        cursor.(blank_seen_field) = false;
        return;
    end
elseif any(strcmp(level, {'WARN'; 'ERROR'}))
    cursor.(diagnostic_field) = level;
    cursor.(braced_field) = ~isempty(strfind(line, '{')) && ...
        isempty(strfind(line, '}'));
    cursor.(diagnostic_lines_field) = 1;
    cursor.(error_using_field) = ...
        local_launchpad_is_error_using(message);
    cursor.(blank_seen_field) = false;
else
    cursor.(diagnostic_field) = '';
    cursor.(braced_field) = false;
    cursor.(diagnostic_lines_field) = 0;
    cursor.(error_using_field) = false;
    cursor.(blank_seen_field) = false;
end
if isempty(message)
    return;
end
% Only remote WARN/ERROR text is forwarded to the console. INFO/SUCCESS remote
% text (including scientific-looking phrases) is not exposed as a stage: no
% reliable public-stage marker has been verified in the remote output, so it
% stays in the protected run log as raw output (see launchpad_quiet_command).
if ~any(strcmp(level, {'WARN'; 'ERROR'}))
    return;
end
event_context = context;
if ~isempty(stage)
    event_context.stage_index = stage(1);
    event_context.stage_count = stage(2);
end
if ~isempty(event_time)
    event_context.console_timestamp = event_time;
end
pseudo_CT_output(level, event_context, '%s', message);
end

function yes = local_launchpad_error_body_continuation(line, cursor, ...
        blank_seen_field)
yes = false;
if ~ischar(line) || isempty(strtrim(line))
    return;
end
if cursor.(blank_seen_field) && ...
        local_launchpad_is_record_boundary(line)
    return;
end
text = lower(strtrim(line));
if local_starts_with(text, '> in ') || local_starts_with(text, 'error in ') || ...
        local_starts_with(text, 'in ') || ...
        local_starts_with(text, 'caused by:')
    return;
end
yes = true;
end

function yes = local_launchpad_is_record_boundary(line)
text = strtrim(line);
yes = ~isempty(regexp(text, ...
    '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\]', ...
    'once')) || ~isempty(regexp(text, ...
    '^\[(run|subject([ \t]|\])|stage[ \t]|job[ \t]|mlsc[^\]]*)\]', ...
    'once', 'ignorecase'));
end

function yes = local_launchpad_is_error_using(message)
yes = ischar(message) && ~isempty(regexp(lower(strtrim(message)), ...
    '^(\?+ *error|error)[ \t]+using([ \t]|$)', 'once'));
end

function [level, message, stage, event_time] = local_launchpad_log_event(line)
level = '';
message = '';
stage = [];
event_time = '';
if ~ischar(line) || isempty(line) || length(line) > 8192
    return;
end
text = local_launchpad_clean_line(line);
if isempty(text) || local_launchpad_is_noise(text)
    return;
end
time_match = regexp(text, ...
    '^\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\]', ...
    'tokens', 'once');
if ~isempty(time_match)
    event_time = time_match{1};
end
stage_match = regexp(text, '\[stage[ \t]+([0-9]+)/([0-9]+)\]', ...
    'tokens', 'once', 'ignorecase');
if ~isempty(stage_match)
    stage = [str2double(stage_match{1}) str2double(stage_match{2})];
    if any(~isfinite(stage)) || stage(1) < 1 || ...
            stage(2) < stage(1) || any(stage ~= floor(stage))
        stage = [];
    end
end
body = regexprep(text, ...
    '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\][ \t]*(INFO|SUCCESS|WARN|ERROR)[ \t]*', ...
    '', 'ignorecase');
level_match = regexp(text, ...
    '^\[[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\][ \t]*(INFO|SUCCESS|WARN|ERROR)', ...
    'tokens', 'once', 'ignorecase');
if ~isempty(level_match)
    level = upper(level_match{1});
end
while true
    if isempty(body) || body(1) ~= '['
        break;
    end
    closing = find(body == ']', 1);
    if isempty(closing)
        break;
    end
    tag = lower(body(2:closing - 1));
    if ~(strcmp(tag, 'run') || strcmp(tag, 'subject') || ...
            local_starts_with(tag, 'subject ') || ...
            local_starts_with(tag, 'stage ') || ...
            local_starts_with(tag, 'job ') || ...
            local_starts_with(tag, 'mlsc'))
        break;
    end
    body = strtrim(body(closing + 1:end));
end
body = strtrim(body);
lower_body = lower(body);
if ~isempty(regexp(lower_body, '^[^a-z]*warning[ \t]*:', 'once'))
    level = 'WARN';
elseif ~isempty(regexp(lower_body, ...
        '^([?]+[ \t]*error|error)([ \t]*:|[ \t]+using([ \t]|$))', 'once'))
    level = 'ERROR';
elseif isempty(level) && local_launchpad_scientific_message(lower_body)
    if ~isempty(regexp(lower_body, ...
            '(completed|verified|written|promoted|prepared)', 'once'))
        level = 'SUCCESS';
    else
        level = 'INFO';
    end
end
if isempty(level)
    return;
end
if any(strcmp(level, {'WARN'; 'ERROR'}))
    message = local_launchpad_safe_message(body);
elseif local_launchpad_scientific_message(lower_body)
    message = body;
else
    level = '';
end
end

function yes = local_launchpad_scientific_message(text)
phrases = {'preparing input mprage'; 'normalizing mprage with freesurfer'; ...
    'legacy pseudo-ct'; 'verifying attenuation map'; ...
    'applying local post-processing'; 'aligning mprage and creating subject mask'; ...
    'running spm new segment'; 'starting the new segment process'; ...
    'registering atlases with dartel'; 'starting the dartel coregistration process'; ...
    'applying inverse warp'; 'reslicing atlases into mprage space'; ...
    'building attenuation map and qc image'; 'segmentation completed'; ...
    'atlas registration completed'; 'attenuation map and qc completed'; ...
    'writing dicom output'; 'promoting final outputs'; ...
    'cleaning up temporary files'};
yes = false;
for ii = 1:length(phrases)
    if local_starts_with(text, phrases{ii})
        yes = true;
        return;
    end
end
end

function yes = local_launchpad_is_noise(text)
lower_text = lower(strtrim(text));
noise = {'java.lang'; 'libjvm'; 'matlab compiler runtime'; ...
    'matlab runtime'; 'matlab compiler'; 'mcr runtime'; 'ganymed'; ...
    'ssh connection'; 'ssh exception'; 'no display'; 'ld_library_path'; ...
    'selected launchpad account'; 'selected mlsc account'};
yes = false;
if ~isempty(regexp(lower_text, ...
        '^[{ \t]*(warning|error)[ \t]*:[ \t]*(java|ssh|mcr)\b', 'once'))
    yes = true;
    return;
end
for ii = 1:length(noise)
    if ~isempty(strfind(lower_text, noise{ii}))
        yes = true;
        return;
    end
end
end

function text = local_launchpad_clean_line(text)
keep = (text >= char(32) & text ~= char(127)) | text == char(9);
text = strtrim(text(keep));
end

function text = local_launchpad_safe_message(text)
text = local_launchpad_clean_line(text);
text = regexprep(text, '/[^ \t,;:(){}]+', '<path>');
text = regexprep(text, '[A-Za-z]:\\[^ \t,;:(){}]+', '<path>');
text = regexprep(text, ...
    '(?i)(username|user|password|passphrase|account|token|secret)([ \t]*[:=][ \t]*|[ \t]+)[^ \t,;]+', ...
    '$1$2<redacted>');
if length(text) > 512
    text = text(1:512);
end
end

function yes = local_starts_with(text, prefix)
yes = length(text) >= length(prefix) && ...
    strcmp(text(1:length(prefix)), prefix);
end

function elapsed = local_elapsed(seconds)
seconds = max(0, floor(seconds));
elapsed = sprintf('%02d:%02d:%02d', floor(seconds / 3600), ...
    floor(rem(seconds, 3600) / 60), rem(seconds, 60));
end
