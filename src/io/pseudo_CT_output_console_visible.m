function [visible, console_line, event_record] = pseudo_CT_output_console_visible(level, message, varargin)
%PSEUDO_CT_OUTPUT_CONSOLE_VISIBLE Incremental event-to-console presenter (v4).
%   Each arriving line is classified and its rows are rendered before the call
%   returns; output order equals arrival order. Bounded exception: a stage-5
%   start that MLSC reports before stage 4 completes is held until DONE(4)
%   arrives (or the next parent-stage event, or FLUSH), then shown after it.
%   [VISIBLE, CONSOLE_LINE, EVENT] = PSEUDO_CT_OUTPUT_CONSOLE_VISIBLE(LEVEL,
%       MESSAGE, CONTEXT, SOURCE_LINE)
%   Verbs: 'RESET'; 'FLUSH' (prints a held row); 'EVIDENCE' (struct with
%   logical subject/run: producer-verified completion); 'DRAIN_EVENTS'.
%   Text mode returns rows in CONSOLE_LINE (newline-joined). JSONL mode
%   (PSEUDOCT_OUTPUT_FORMAT=jsonl) writes each row to stdout when produced.
%   Minimum MATLAB: R2010b.

persistent S;
if isempty(S)
    S = local_new_state();
end
visible = false;
console_line = '';
event_record = local_unavailable_event();
if ~ischar(level)
    return;
end
verb = upper(strtrim(level));
if nargin <= 2 && any(strcmp(verb, {'RESET'; 'FLUSH'; 'EVIDENCE'; 'DRAIN_EVENTS'; 'EVENTS'}))
    if strcmp(verb, 'RESET')
        S = local_new_state();
    elseif strcmp(verb, 'FLUSH')
        S = local_flush(S);
    elseif strcmp(verb, 'EVIDENCE')
        if nargin == 2 && isstruct(message) && numel(message) == 1
            S.evidence = struct('subject', local_flag(message, 'subject'), ...
                'run', local_flag(message, 'run'));
        end
    else
        visible = S.records;
        S.records = local_empty_events();
    end
    return;
end
if nargin < 2
    error('pseudo_CT:InvalidPresenterVerb', 'Unknown presenter verb: %s', level);
end
if ~ischar(message)
    return;
end
context = struct();
source_line = message;
if nargin >= 3 && isstruct(varargin{1}) && numel(varargin{1}) == 1
    context = varargin{1};
end
if nargin >= 4 && ischar(varargin{2}) && ~isempty(varargin{2})
    source_line = varargin{2};
end
if isfield(context, 'stage_status') && ischar(context.stage_status) && ...
        strcmpi(strtrim(context.stage_status), 'LOG')
    return;  % run-log-only detail
end
if isfield(context, 'console_profile') && ischar(context.console_profile) && ...
        ~isempty(context.console_profile)
    S.profile = context.console_profile;
end
S = local_source_context(S, context);
S.context = context;
S = local_subject_slot(S, local_subject_index(context));
if isfield(context, 'stage_map') && isstruct(context.stage_map) && isscalar(context.stage_map)
    S.stage_map = context.stage_map;
end
row = local_parse(source_line, verb);
[cands, S] = local_classify(S, row, context);
emitted = {};
for ci = 1:length(cands)
    if ~isempty(cands{ci}.dedupe)
        cands{ci}.dedupe = [cands{ci}.dedupe '|' row.message];
    end
    [out, S] = local_admit(S, cands{ci});
    emitted = [emitted out]; %#ok<AGROW>
end
[visible, console_line, event_record, S] = local_output(S, emitted);
end

% ---------------------------------------------------------------- state ----

function S = local_new_state()
S = struct('profile', '', 'kind', 'pipeline', 'src', 'pipeline', ...
    'file', '', 'lineno', 0, 'live', true, 'replay', false, ...
    'subjects', local_new_subject(1), 'subject_slot', 1, ...
    'warning_messages', {{}}, 'warning_sources', {{}}, ...
    'hb_keys', {{}}, 'hb_vals', zeros(1, 0), ...
    'evidence', struct('subject', false, 'run', false), ...
    'records', local_empty_events(), 'header_done', false, ...
    'context', struct(), 'stage_map', [], 'terminal', false);
end

function subject = local_new_subject(idx)
subject = struct('index', idx, 'stage_state', zeros(1, 10), ...
    'label_shown', false(1, 10), 'seen', {{}}, ...
    'has_held', false, 'held', struct(), ...
    'terminal', false, 'last_ts', '');
end

function idx = local_subject_index(context)
idx = 1;
if isfield(context, 'subject_index') && isnumeric(context.subject_index) && ...
        isscalar(context.subject_index) && isfinite(context.subject_index) && ...
        context.subject_index >= 1 && context.subject_index == floor(context.subject_index)
    idx = context.subject_index;
end
end

function S = local_subject_slot(S, idx)
slot = find([S.subjects.index] == idx, 1);
if isempty(slot)
    slot = length(S.subjects) + 1;
    S.subjects(slot) = local_new_subject(idx);
end
S.subject_slot = slot;
end

function S = local_source_context(S, context)
% Identify this line's source: pipeline log, scheduler stdout, or
% compiled backend stdout. Replay files carry source_file; live calls do not.
S.kind = 'pipeline';
S.src = 'orchestrator';
S.file = '';
S.lineno = 0;
S.live = true;
if isfield(context, 'live') && (islogical(context.live) || isnumeric(context.live)) && ...
        isscalar(context.live) && isfinite(double(context.live))
    S.live = logical(context.live);
end
S.replay = ~S.live;
if isfield(context, 'source_file') && ischar(context.source_file) && ...
        ~isempty(context.source_file)
[~, base, ext] = fileparts(context.source_file);
name = [base ext];
S.file = context.source_file;
is_pipeline = strncmp(name, 'pseudoct-run-', 13) && strcmp(ext, '.log');
is_pipeline = is_pipeline || local_flag(context, 'workflow_event') || ...
    (isfield(context, 'source') && strcmp(context.source, 'orchestrator'));
is_scheduler = ~is_pipeline && (isfield(context, 'source') && ...
    ischar(context.source) && strcmp(context.source, 'scheduler'));
if is_pipeline
    S.kind = 'pipeline';
elseif is_scheduler
    S.kind = 'scheduler';
else
    S.kind = 'backend';
    S.src = local_backend_source(S.profile);
end
end
if isfield(context, 'source') && ischar(context.source) && ~isempty(context.source)
    S.src = context.source;
    if strcmp(context.source, 'scheduler')
        S.kind = 'scheduler';
    elseif any(strcmp(context.source, {'backend'; 'local_backend'; 'mlsc_stdout'}))
        S.kind = 'backend';
    end
end
if isfield(context, 'source_line_number') && isnumeric(context.source_line_number) && ...
        isscalar(context.source_line_number)
    S.lineno = context.source_line_number;
end
end

function src = local_backend_source(profile)
if ~isempty(strfind(profile, 'mlsc'))
    src = 'mlsc_stdout';
else
    src = 'local_backend';
end
end

function yes = local_flag(s, name)
yes = isfield(s, name) && islogical(s.(name)) && isscalar(s.(name)) && s.(name);
end

function S = local_flush(S)
% End of input or explicit flush: release any held stage-5 start.
slot = S.subject_slot;
for si = 1:length(S.subjects)
    S.subject_slot = si;
    [out, S] = local_release_held(S, false);
    [visible, console_line, ~, S] = local_output(S, out);
    if visible && ~strcmp(getenv('PSEUDOCT_OUTPUT_FORMAT'), 'jsonl')
        fprintf(1, '%s\n', console_line);
    end
end
S.subject_slot = slot;
end

% ------------------------------------------------------------- constants ---

function ids = local_stage_ids()
ids = {'workflow.input_prepare'; 'workflow.recenter'; 'workflow.alias_correct'; ...
    'workflow.normalize'; 'workflow.align_mask'; 'workflow.segment'; ...
    'workflow.dartel'; 'workflow.attenuation_qc'; 'workflow.dicom_output'; ...
    'workflow.full_output_finalize'};
end

function text = local_stage_text(n, status)
% Ten-stage wording shared by every profile.
active = {'Preparing input MPRAGE'; 'Recentering MPRAGE'; 'Correcting aliasing'; ...
    'Normalizing MPRAGE with FreeSurfer'; 'Aligning MPRAGE and generating subject mask'; ...
    'Running SPM New Segment'; 'Registering and reslicing atlases with DARTEL'; ...
    'Generating attenuation map'; 'Writing DICOM output'; 'Promoting final outputs'};
done = {'Input MPRAGE prepared'; 'MPRAGE recentering completed'; ...
    'Aliasing correction completed'; 'MPRAGE normalization completed'; ...
    'Alignment and masking completed'; 'SPM New Segment completed'; ...
    'DARTEL, inverse warp and atlas reslicing completed'; ...
    'Attenuation map generated'; 'DICOM output written'; 'Final outputs promoted'};
if strcmp(status, 'ACTIVE')
    text = active{n};
else
    text = done{n};
end
end

function label = local_stage_label(n)
labels = {'MPRAGE preparation'; 'MPRAGE recentering'; 'Aliasing correction'; ...
    'FreeSurfer normalization'; 'Alignment and masking'; 'SPM New Segment'; ...
    'DARTEL / inverse warp / atlas reslice'; 'Attenuation-map generation'; ...
    'Full-mode DICOM output'; 'Full-mode final output promotion'};
label = labels{n};
end

function category = local_stage_category(n)
if n <= 5
    category = 'preparation';
elseif n <= 8
    category = 'scientific';
else
    category = 'finalization';
end
end

function title = local_profile_title(profile)
switch profile
    case 'local', title = 'Local v3';
    case 'local-mprage-only', title = 'Local v3 MPRAGE-only';
    case 'mlsc', title = 'MLSC v3';
    case 'mlsc-mprage-only', title = 'MLSC v3 MPRAGE-only';
    otherwise, title = profile;
end
end

function text = local_child_text(op, status)
% Fixed INFO wording for child operations; '' when the op has no table entry.
active = strcmp(status, 'ACTIVE');
switch op
    case 'input.dcm2nii'
        text = ['Input DICOM conversion ' local_verb(active)];
    case 'output.dcm2nii'
        text = ['Reference DICOM conversion ' local_verb(active)];
    case 'scientific.inverse_warp'
        text = ['  Inverse atlas warping ' local_verb(active, 'finished')];
    case 'scientific.atlas_reslice'
        text = ['  Atlas reslicing ' local_verb(active, 'finished')];
    case 'scientific.dartel_registration'
        text = '  DARTEL registration finished';
    case 'output.cleanup'
        if active
            text = 'Temporary-file cleanup started';
        else
            text = 'Temporary files removed';
        end
    case 'transport.remote_verify'
        text = ['Remote results inspection ' local_verb(active)];
    case 'transport.copyback'
        if active
            text = 'Retrieving remote results';
        else
            text = 'Remote results retrieved';
        end
    case 'output.postprocess'
        if active
            text = 'Applying local post-processing';
        else
            text = 'Local post-processing completed';
        end
    otherwise
        text = '';
end
end

function word = local_verb(active, finished_word)
if nargin < 2
    finished_word = 'completed';
end
if active
    word = 'started';
else
    word = finished_word;
end
end


function yes = local_is_mprage_only(profile)
yes = ~isempty(strfind(profile, 'mprage-only'));
end

% -------------------------------------------------------------- parsing ----

function row = local_parse(text, verb)
% Structured line: [date time] LEVEL [tags...] message. Other text is raw.
row = struct('structured', false, 'date', '', 'time', '', 'level', '', ...
    'job', '', 'dcm2nii', false, 'message', '');
t = local_strip_ctrl(text);
tok = regexp(t, ['^\[(\d{4}-\d\d-\d\d) (\d\d:\d\d:\d\d)\]\s+' ...
    '(INFO|SUCCESS|WARN|WARNING|ERROR|FAILURE)\s+(.*)$'], 'tokens', 'once');
if isempty(tok)
    row.message = t;
    if any(strcmp(verb, {'INFO'; 'SUCCESS'; 'WARN'; 'WARNING'; 'ERROR'; 'FAILURE'}))
        row.level = verb;
    end
    return;
end
row.structured = true;
row.date = tok{1};
row.time = tok{2};
row.level = tok{3};
rem = tok{4};
while ~isempty(rem) && rem(1) == '['
    tk = regexp(rem, '^\[([^\]]+)\]\s*', 'tokens', 'once');
    if isempty(tk)
        break;
    end
    token = tk{1};
    m_end = regexp(rem, '^\[[^\]]+\]\s*', 'end', 'once');
    if ~isempty(regexp(token, '^stage \d+/\d+$', 'once')) || strncmp(token, 'subject ', 8)
        % stage and subject tags are consumed; numbering is by the rules below
    elseif strncmp(token, 'job ', 4)
        row.job = token(5:end);
    elseif strcmp(token, 'dcm2nii')
        row.dcm2nii = true;
    elseif any(strcmp(token, {'run'; 'mlsc'}))
        % scope tags are consumed
    else
        break;  % e.g. [recentering] is message text
    end
    rem = rem(m_end + 1:end);
end
row.message = local_strip_ctrl(rem);
end

function t = local_strip_ctrl(text)
t = regexprep(text, [char(27) '\[[0-9;]*[A-Za-z]'], '');
t = strrep(t, char(8), '');
t = strrep(t, char(13), '');
t = strrep(t, char(0), '');
t = strtrim(t);
end

function t = local_public(text)
% Redact paths and DICOM file names; collapse whitespace.
t = local_strip_ctrl(text);
t = regexprep(t, '(?<![\w/])/[^\s:;,()<>]+', '<path>');
t = regexprep(t, '\<[^\s/]+\.dcm\>', '<DICOM file>', 'ignorecase');
t = strtrim(regexprep(t, '\s+', ' '));
end

function label = local_warning_label(m)
% Stable warning label; '' when the text does not open a warning.
label = '';
[st, en] = regexpi(m, '\<Warning\s*:\s*', 'start', 'end', 'once');
if isempty(st)
    return;
end
msg = regexprep(m(en + 1:end), '^[ {}]+|[ {}]+$', '');
known = {'QFORM0', 'QFORM0 representation has been rounded'; ...
    'Rank deficient', 'Rank deficient during fitting'; ...
    'Some columns of the Jacobian', 'Jacobian insensitive to some parameters'; ...
    'No display specified', 'No display available'; ...
    '"images.jar"', 'images.jar already on the Java path'; ...
    '"bioinfo.jar"', 'bioinfo.jar already on the Java path'; ...
    '1 invisible figure', 'Invisible MATLAB figure at compiler termination'};
for ki = 1:size(known, 1)
    if strncmp(msg, known{ki, 1}, length(known{ki, 1}))
        label = known{ki, 2};
        return;
    end
end
close_at = find(msg == '}', 1);
if ~isempty(close_at)
    msg = msg(1:close_at - 1);
end
label = local_public(msg);
if length(label) > 130
    label = label(1:130);
end
end

function seconds = local_elapsed_seconds(m)
seconds = [];
tk = regexpi(m, 'elapsed\s+(\d+):(\d+):(\d+)', 'tokens', 'once');
if ~isempty(tk)
    seconds = str2double(tk{1}) * 3600 + str2double(tk{2}) * 60 + str2double(tk{3});
end
end

function q = local_recenter_match(m)
% '[recentering] Not required.' style lines: returns [] or struct(n, skipped).
q = [];
tk = regexpi(m, '^\[(recentering|aliasing correction)\]\s*(Not required\.|Skipped\.|Successfully applied\.)', 'tokens', 'once');
if isempty(tk)
    return;
end
q = struct('n', 3, 'skipped', false);
if strncmpi(tk{1}, 'recentering', 11)
    q.n = 2;
end
q.skipped = strncmpi(tk{2}, 'not required', 12) || strncmpi(tk{2}, 'skipped', 7);
end

function yes = local_is_continuation(m)
yes = ~isempty(regexpi(m, ['\<In [\w@.>]+ at \d+|^> In |^In |^\}|^indicating that|' ...
    '^be because|^affect |^model function|^parameter values|^unreliable\.|' ...
    '^The figure ID'], 'once'));
end

% ------------------------------------------------------------ candidates ---

function c = local_cand(S, row, status, stage, op, kind, text, category)
% A presentable candidate before admission.
c = struct('status', status, 'stage', stage, 'op', op, 'kind', kind, ...
    'text', text, 'category', category, 'src', S.src, 'ts', '', 'orig', '', ...
    'job', '', 'file', S.file, 'lines', [], 'live', S.live, 'dedupe', '', ...
    'reason', '', 'context', S.context, 'level', 'INFO', 'observed', false);
if isstruct(row)
    if isfield(row, 'level')
        c.level = row.level;
    end
    if row.structured && ~isempty(row.date)
        c.ts = [row.date ' ' row.time];
    end
    c.job = row.job;
end
if isempty(c.ts) && S.live
    % Live row without a source timestamp: time of observation. Replay never
    % fabricates a time.
    c.ts = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    c.observed = true;
end
if S.lineno > 0
    c.lines = S.lineno;
end
end

function c = local_parent(S, row, n, status, skip_text)
% Parent stage transition: ACTIVE / DONE / SKIPPED, numbered 1..10.
ids = local_stage_ids();
if strcmp(status, 'ACTIVE')
    text = local_stage_text(n, 'ACTIVE');
    kind = 'stage_started';
elseif strcmp(status, 'DONE')
    text = local_stage_text(n, 'DONE');
    kind = 'stage_completed';
else
    text = skip_text;
    kind = 'stage_skipped';
end
c = local_cand(S, row, status, n, ids{n}, kind, text, local_stage_category(n));
if n == 10 && local_is_mprage_only(S.profile)
    if strcmp(status, 'ACTIVE')
        c.text = 'Promoting NIfTI output';
    elseif strcmp(status, 'DONE')
        c.text = 'NIfTI output promoted';
    end
end
c.dedupe = [ids{n} '|' status];
if strcmp(status, 'SKIPPED')
    c.reason = 'backend:not_required';
end
end

function c = local_child(S, row, op, status, fallback)
% Child operation: always INFO (never a stage transition), fixed wording.
text = local_child_text(op, status);
if isempty(text)
    text = fallback;
end
c = local_cand(S, row, 'INFO', 0, op, 'milestone', text, 'remote_processing');
c.kind = 'operation_started';
if ~strcmp(status, 'ACTIVE')
    c.kind = 'operation_completed';
end
c.dedupe = [op '|' status];
end

function c = local_milestone(S, row, op, text, category)
c = local_cand(S, row, 'INFO', 0, op, 'milestone', text, category);
if strcmp(op, 'scheduler.submit')
    c.kind = 'scheduler_submission';
end
end

function [cands, S] = local_classify(S, row, context)
% Cancellation and failures override inherited START/DONE hints, including
% unstructured scheduler output. They never complete an open parent stage.
if local_is_cancellation(S, row, context)
    c = local_cand(S, row, 'CANCELLED', 0, 'event.cancelled', 'cancelled', ...
        local_public(row.message), 'run');
    cands = {c};
    return;
end
if any(strcmp(row.level, {'ERROR'; 'FAILURE'}))
    n = 0;
    if isfield(context, 'stage_index') && isnumeric(context.stage_index) && ...
            isscalar(context.stage_index) && any(context.stage_index == 1:10) && ...
            isfield(context, 'stage_count') && isequal(context.stage_count, 10)
        n = context.stage_index;
    end
    cands = {local_cand(S, row, 'ERROR', n, 'event.error', 'failure', ...
        local_public(row.message), 'diagnostics')};
    return;
end
if local_flag(context, 'completion_verified')
    % This flag belongs to this completion event, not to subsequent subjects.
    verified = true;
else
    verified = S.evidence.subject;
end
if strncmp(row.message, 'Subject completed', 17)
    cands = {local_completion(S, row, local_public(row.message), verified, 'run.subject_completion')};
    return;
elseif strncmp(row.message, 'Run completed:', 14)
    cands = {local_completion(S, row, local_public(row.message), ...
        local_flag(context, 'completion_verified') || S.evidence.run, 'run.completion')};
    return;
end
if (isfield(context, 'event_kind') && strcmp(context.event_kind, 'output_verified')) || ...
        strcmp(row.message, 'Promoted outputs verified.')
    cands = {local_cand(S, row, 'VERIFIED', 0, 'output.verify', 'output_verified', ...
        local_public(row.message), 'verified_completion')};
    return;
end
% Applied is an explicit outcome, not an observed start (compiled PREPARE).
q = local_recenter_match(row.message);
if ~isempty(q)
    cands = {local_recenter_cand(S, row, q)};
    return;
end
canon = '';
if isfield(context, 'stage_status') && ischar(context.stage_status)
    canon = upper(strtrim(context.stage_status));
end
if ~isempty(canon) && ~local_flag(context, 'console_unstructured')
    [cands, S] = local_canonical(S, row, canon, context);
    return;
end
[cands, S] = local_raw(S, row);
end

function yes = local_is_cancellation(S, row, context)
% Only explicit lifecycle events or observed scheduler grammars cancel output.
yes = isfield(context, 'event_kind') && strcmp(context.event_kind, 'cancelled');
workflow = ~local_flag(context, 'console_unstructured') && ...
    (local_flag(context, 'workflow_event') || ...
    (isfield(context, 'source') && strcmp(context.source, 'orchestrator')) || ...
    (strcmp(S.kind, 'pipeline') && row.structured));
if workflow && ~isempty(regexpi(row.message, '^Run cancel(l)?ed by user\.$', 'once'))
    yes = true;
end
if ~isempty(regexpi(row.message, '^MLSC job \d+ state cancelled\.?$', 'once'))
    yes = true;
end
% Slurm stderr, including its captured timestamp/error prefix. This marker
% may arrive in a backend log, but arbitrary backend cancellation words cannot.
if ~isempty(regexpi(row.message, ...
        '(^|error:\s+)\*\*\* JOB \d+ ON \S+ CANCELLED AT \S+ DUE to SIGNAL Terminated \*\*\*$', 'once'))
    yes = true;
end
end

function [cands, S] = local_canonical(S, row, canon, context)
% Canonical orchestrator events carry the public stage index and a status.
cands = {};
n = 0;
if isfield(context, 'stage_index') && isnumeric(context.stage_index) && ...
        isscalar(context.stage_index) && context.stage_index >= 1 && ...
        context.stage_index <= 10 && context.stage_index == floor(context.stage_index)
    n = context.stage_index;
end
if n > 0 && ~local_flag(context, 'workflow_event') && ...
        isfield(context, 'stage_count') && ~isempty(S.stage_map)
    [~, n, ~, ~, span] = pseudo_CT_stage_map(S.stage_map, n, context.stage_count);
    if ~isempty(span)
        context.stage_span = span;
        S.context = context;
    end
end
if isfield(context, 'operation_id') && strcmp(context.operation_id, 'output.promote_nifti')
    n = 10;
end
% The lifecycle's full-mode policy skip is not a skip of NIfTI promotion.
% Suppress only this explicit, different operation; never guess from profile.
if n == 10 && strcmp(canon, 'SKIPPED') && local_is_mprage_only(S.profile) && ...
        strcmp(row.message, 'Full-mode output finalization skipped by MPRAGE-only policy.')
    return;
end
text = row.message;
if isfield(context, 'stage_message') && ischar(context.stage_message) && ...
        ~isempty(strtrim(context.stage_message))
    text = local_public(context.stage_message);
end
switch canon
    case 'START'
        if n > 0
            cands{end + 1} = local_parent(S, row, n, 'ACTIVE', '');
        elseif isfield(context, 'operation_id')
            cands{end + 1} = local_child(S, row, context.operation_id, 'ACTIVE', text);
        end
    case 'DONE'
        if n > 0
            cands{end + 1} = local_parent(S, row, n, 'DONE', '');
        elseif isfield(context, 'operation_id')
            cands{end + 1} = local_child(S, row, context.operation_id, 'DONE', text);
        end
    case 'SKIPPED'
        if n > 0
            skip_text = [local_stage_label(n) ' not required'];
            if n == 9 && local_is_mprage_only(S.profile)
                skip_text = 'Full-mode DICOM output skipped (MPRAGE-only policy)';
            elseif n == 10 && isfield(context, 'operation_id') && ...
                    strcmp(context.operation_id, 'output.promote_nifti')
                skip_text = local_public(row.message);
            end
            if isfield(context, 'stage_message') && ischar(context.stage_message) && ...
                    ~isempty(strtrim(context.stage_message))
                skip_text = local_public(context.stage_message);
            end
            c = local_parent(S, row, n, 'SKIPPED', skip_text);
            if isfield(context, 'reason') && ischar(context.reason) && ~isempty(context.reason)
                c.reason = context.reason;
            end
            cands{end + 1} = c;
        end
    case 'WARN'
        c = local_cand(S, row, 'WARN', 0, '', 'warning', text, 'diagnostics');
        cands{end + 1} = c;
    case 'ERROR'
        cands{end + 1} = local_cand(S, row, 'ERROR', 0, 'diagnostic.error', ...
            'diagnostic.error', text, 'diagnostics');
    otherwise
        if any(strcmp(row.level, {'WARN'; 'WARNING'}))
            c = local_cand(S, row, 'WARN', 0, '', 'warning', text, 'diagnostics');
            cands{end + 1} = c;
        else
            cands{end + 1} = local_milestone(S, row, '', text, 'remote_processing');
            cands{end}.kind = 'milestone';
        end
end
end




% ------------------------------------------------------------ raw lines ----

function [cands, S] = local_raw(S, row)
% Classification of raw pipeline / backend / scheduler lines.
cands = {};
m = row.message;
if isempty(m)
    return;
end
lev = row.level;
is_warn = any(strcmp(lev, {'WARN'; 'WARNING'}));
pm = local_public(m);
label = local_warning_label(m);
if ~isempty(label)
    % Only exact text observed from another source establishes a mirror.
    % Labels alone (e.g. all rank-deficiency warnings) are not identity.
    origin = [S.kind '|' S.src '|' S.file];
    pipeline_sources = strncmp('pipeline|', S.warning_sources, 9);
    if strcmp(S.kind, 'pipeline')
        mirror_sources = ~pipeline_sources;
    else
        mirror_sources = pipeline_sources;
    end
    mirror = strcmp(m, S.warning_messages) & mirror_sources;
    S.warning_messages{end + 1} = m;
    S.warning_sources{end + 1} = origin;
    if any(mirror)
        return;
    end
    c = local_cand(S, row, 'WARN', 0, '', 'warning', label, 'diagnostics');
    cands{end + 1} = c;
    return;
end
if is_warn
    if local_is_continuation(m)
        return;
    end
    if strncmp(m, 'Version log', 11) || strncmp(m, 'CHANGELOG', 9) || ...
            strncmp(m, 'No image has been written!', 26)
        op = '';
        if strncmp(m, 'Version log', 11)
            op = 'diagnostic.version_fallback';
        end
        cands{end + 1} = local_cand(S, row, 'WARN', 0, op, 'warning', pm, 'diagnostics');
    end
    return;
end
if ~strcmp(S.kind, 'pipeline')
    q = local_recenter_match(m);
    if ~isempty(q)
        cands{end + 1} = local_recenter_cand(S, row, q);
    end
    return;
end

% ---- pipeline (permanent log) -------------------------------------------
if strncmp(m, 'Profile:', 8)
    cands{end + 1} = local_cand(S, row, 'INFO', 0, 'run.profile', 'run_started', pm, 'preparation');
    return;
end
if strncmp(m, 'Log header:', 11) || strncmp(m, 'Run log initialized', 19) || ...
        strncmp(m, 'Detailed profile summary saved', 30)
    return;
end
if row.dcm2nii || ~isempty(strfind(m, '[dcm2nii]'))
    input_op = S.subjects(S.subject_slot).stage_state(1) ~= 2;
    if strncmp(m, 'Input:', 6)
        if input_op
            op = 'input.dcm2nii';
        else
            op = 'output.dcm2nii';
        end
        cands{end + 1} = local_child(S, row, op, 'ACTIVE', '');
    elseif ~isempty(strfind(m, 'Conversion completed'))
        if input_op
            op = 'input.dcm2nii';
        else
            op = 'output.dcm2nii';
        end
        cands{end + 1} = local_child(S, row, op, 'DONE', '');
    end
    return;
end
if strncmp(m, 'Preparing input MPRAGE', 22)
    cands{end + 1} = local_parent(S, row, 1, 'ACTIVE', '');
elseif strncmp(m, 'Input prepared', 14)
    cands{end + 1} = local_parent(S, row, 1, 'DONE', '');
elseif ~isempty(local_recenter_match(m))
    cands{end + 1} = local_recenter_cand(S, row, local_recenter_match(m));
elseif strncmp(m, 'Normalizing MPRAGE with FreeSurfer', 34) || strncmp(m, 'MLSC normalization started', 26)
    cands{end + 1} = local_parent(S, row, 4, 'ACTIVE', '');
elseif strncmp(m, 'MPRAGE normalization completed', 30) || strncmp(m, 'MLSC normalization completed', 28)
    cands{end + 1} = local_parent(S, row, 4, 'DONE', '');
elseif strncmp(m, 'Aligning MPRAGE and creating subject mask', 41)
    cands{end + 1} = local_parent(S, row, 5, 'ACTIVE', '');
elseif strncmp(m, 'Alignment and masking completed', 31)
    cands{end + 1} = local_parent(S, row, 5, 'DONE', '');
elseif strncmp(m, 'Running SPM New Segment', 23)
    cands{end + 1} = local_parent(S, row, 6, 'ACTIVE', '');
elseif strncmp(m, 'Segmentation completed', 22)
    cands{end + 1} = local_parent(S, row, 6, 'DONE', '');
elseif strncmp(m, 'Registering atlases with DARTEL', 31)
    cands{end + 1} = local_parent(S, row, 7, 'ACTIVE', '');
elseif strncmp(m, 'Applying inverse warp', 21)
    cands{end + 1} = local_child(S, row, 'scientific.inverse_warp', 'ACTIVE', '');
elseif strncmp(m, 'Reslicing atlases into MPRAGE space', 35)
    cands{end + 1} = local_child(S, row, 'scientific.atlas_reslice', 'ACTIVE', '');
elseif strncmp(m, 'Atlas registration completed', 28)
    cands{end + 1} = local_parent(S, row, 7, 'DONE', '');
elseif strncmp(m, 'Building attenuation map and QC image', 37)
    cands{end + 1} = local_parent(S, row, 8, 'ACTIVE', '');
elseif strncmp(m, 'Attenuation map and QC completed', 32)
    cands{end + 1} = local_parent(S, row, 8, 'DONE', '');
elseif strncmp(m, 'MLSC alias-recenter completed', 29)
    if ~all(S.subjects(S.subject_slot).stage_state(2:3) ~= 0)
        % MLSC reports the combined compiled PREPARE phase only; the per-step
        % outcome stays remote, so say exactly that.
        c2 = local_cand(S, row, 'INFO', 2, 'prepare.recenter', 'delegation', ...
            'MPRAGE recentering handled in compiled phase; outcome not separately reported', 'preparation');
        c3 = local_cand(S, row, 'INFO', 3, 'prepare.alias_correct', 'delegation', ...
            'Aliasing correction handled in compiled phase; outcome not separately reported', 'preparation');
        c2.dedupe = 'prepare.combined_alias_recenter|2';
        c3.dedupe = 'prepare.combined_alias_recenter|3';
        cands{end + 1} = c2;
        cands{end + 1} = c3;
    end
elseif strncmp(m, 'MLSC stage-in completed', 23)
    cands{end + 1} = local_child(S, row, 'transport.stage_in', 'DONE', pm);
elseif strncmp(m, 'MLSC preparation completed', 26)
    cands{end + 1} = local_milestone(S, row, 'backend.prepare', pm, 'remote_processing');
elseif strncmp(m, 'MLSC alignment-mask completed', 29) || ...
        strncmp(m, 'MLSC segmentation completed', 27) || ...
        strncmp(m, 'MLSC DARTEL-warp-reslice completed', 34) || ...
        strncmp(m, 'MLSC attenuation-QC completed', 29)
    return;  % duplicates of specific scientific markers
elseif strncmp(m, 'MLSC verification started', 25)
    cands{end + 1} = local_child(S, row, 'transport.remote_verify', 'ACTIVE', '');
elseif strncmp(m, 'MLSC verification completed', 27)
    cands{end + 1} = local_child(S, row, 'transport.remote_verify', 'DONE', '');
elseif strncmp(m, 'MLSC copy-back started', 22)
    cands{end + 1} = local_child(S, row, 'transport.copyback', 'ACTIVE', '');
elseif strncmp(m, 'MLSC verified return to shared temp completed', 45)
    cands{end + 1} = local_child(S, row, 'transport.copyback', 'DONE', '');
elseif strncmp(m, 'MLSC connection and authentication succeeded', 44)
    cands{end + 1} = local_milestone(S, row, 'scheduler.auth', 'MLSC authentication succeeded', 'scheduler');
elseif ~isempty(regexp(m, '^MLSC job \d+ (accepted|state running|state pending|state completed|completed exit|still running|still pending)', 'once'))
    cands = local_scheduler_job(S, row, m, cands);
    [cands, S] = local_last_job(S, m, cands);
elseif strncmp(m, 'Submitting MLSC job', 19)
    cands{end + 1} = local_milestone(S, row, 'scheduler.submit', 'Submitting MLSC job', 'scheduler');
elseif strncmp(m, 'Verifying attenuation map', 25)
    c = local_cand(S, row, 'ACTIVE', 0, 'output.verify', 'milestone', pm, 'verified_completion');
    c.dedupe = 'output.verify|ACTIVE';
    cands{end + 1} = c;
elseif strncmp(m, 'Attenuation map verified', 24)
    % The backend's own post-output check; accepted as the VERIFIED evidence.
    c = local_cand(S, row, 'VERIFIED', 0, 'output.verify', 'verification', pm, 'verified_completion');
    c.dedupe = 'output.verify|VERIFIED';
    cands{end + 1} = c;
elseif strncmp(m, 'Applying local post-processing', 30)
    cands{end + 1} = local_child(S, row, 'output.postprocess', 'ACTIVE', '');
elseif strncmp(m, 'Local post-processing completed', 31)
    cands{end + 1} = local_child(S, row, 'output.postprocess', 'DONE', '');
elseif strncmp(m, 'Writing DICOM output', 20)
    cands{end + 1} = local_parent(S, row, 9, 'ACTIVE', '');
elseif strncmp(m, 'DICOM output written', 20)
    cands{end + 1} = local_parent(S, row, 9, 'DONE', '');
elseif strncmp(m, 'Skipping DICOM output by profile policy', 39)
    c = local_parent(S, row, 9, 'SKIPPED', 'Full-mode DICOM output skipped (MPRAGE-only policy)');
    c.reason = 'profile_policy:mprage_only';
    cands{end + 1} = c;
elseif strncmp(m, 'Promoting final outputs', 23) || strncmp(m, 'Promoting outputs and cleaning up', 33)
    c = local_parent(S, row, 10, 'ACTIVE', '');
    if local_is_mprage_only(S.profile)
        c.text = 'Promoting NIfTI output';   % the NIfTI promotion is the stage-10 operation
    end
    cands{end + 1} = c;
elseif strncmp(m, 'Outputs promoted', 16)
    c = local_parent(S, row, 10, 'DONE', '');
    if local_is_mprage_only(S.profile)
        c.text = 'NIfTI output promoted';
    end
    cands{end + 1} = c;
elseif strncmp(m, 'Cleaning up temporary files', 27)
    cands{end + 1} = local_child(S, row, 'output.cleanup', 'ACTIVE', '');
elseif strncmp(m, 'Cleanup completed', 17) || strncmp(m, 'Temporary files removed', 23)
    cands{end + 1} = local_child(S, row, 'output.cleanup', 'DONE', '');
elseif strncmp(m, 'Run failed', 10) || strncmp(m, 'Subject failed', 14)
    cands{end + 1} = local_cand(S, row, 'ERROR', 0, 'run.failure', 'run_failed', pm, 'verified_completion');
end
end

function c = local_recenter_cand(S, row, q)
if q.skipped
    c = local_parent(S, row, q.n, 'SKIPPED', [local_stage_label(q.n) ' not required']);
    c.reason = 'backend:not_required';
else
    c = local_parent(S, row, q.n, 'DONE', '');
    c.text = [local_stage_label(q.n) ' applied (reported by compiled PREPARE phase; start not separately reported)'];
    c.reason = 'backend:reported_applied';
end
c.category = 'preparation';
end

function c = local_completion(S, row, pm, verified, op)
kind = 'run_completed';
if strcmp(op, 'run.subject_completion')
    kind = 'subject_completed';
else
    % Compact counts so the summary stays on one console row.
    tk = regexp(pm, ['^Run completed: requested (\d+), started (\d+), succeeded (\d+), ' ...
        'failed (\d+), skipped (\d+) \(elapsed ([\d:]+)\)\.$'], 'tokens', 'once');
    if ~isempty(tk)
        pm = sprintf('Run completed: %s requested, %s started, %s succeeded, %s failed, %s skipped (%s).', ...
            tk{1}, tk{2}, tk{3}, tk{4}, tk{5}, tk{6});
    end
end
if verified
    c = local_cand(S, row, 'VERIFIED', 0, op, kind, pm, 'verified_completion');
    c.dedupe = [op '|VERIFIED'];
else
    if strcmp(op, 'run.subject_completion') && S.replay
        text = 'Pipeline reports subject completed (verification not established by this replay)';
    else
        text = pm;
    end
    c = local_cand(S, row, 'INFO', 0, op, kind, text, 'verified_completion');
end
end


function cands = local_scheduler_job(S, row, m, cands)
% Scheduler state lines for a MLSC job (INFO only).
tk = regexp(m, 'job\s+(\d+)', 'tokens', 'once');
job = '';
if ~isempty(tk)
    job = tk{1};
end
if ~isempty(strfind(m, 'still '))
    cands{end + 1} = local_milestone_job(S, row, job, m, 'scheduler.heartbeat', 'heartbeat');
else
    kind = 'scheduler_state';
    if ~isempty(strfind(m, 'accepted'))
        kind = 'scheduler_accepted';
    end
    cands{end + 1} = local_milestone_job(S, row, job, m, 'scheduler.job', kind);
end
end

function [cands, S] = local_last_job(S, m, cands)
% MLSC still-running lines are heartbeats, so apply the 60-second rule here.
if isempty(cands)
    return;
end
last = cands{end};
if ~strcmp(last.kind, 'heartbeat')
    return;
end
tk = regexp(m, 'job\s+(\d+)', 'tokens', 'once');
key = ['mlsc|' tk{1}];
minutes = local_elapsed_seconds(m);
[previous, found] = local_lookup(S, key);
if S.terminal || S.subjects(S.subject_slot).terminal
    cands(end) = [];   % no scheduler activity claim after a terminal row
    return;
end
if found && (isempty(minutes) || minutes - previous < 60)
    cands(end) = [];
    return;
end
S = local_store(S, key, sum([minutes 0]));
end

function c = local_milestone_job(S, row, job, m, op, kind)
c = local_milestone(S, row, [op '.' job], local_public(m), 'scheduler');
c.kind = kind;
c.job = job;
end

function [previous, found] = local_lookup(S, key)
previous = 0;
found = false;
for hi = 1:length(S.hb_keys)
    if strcmp(S.hb_keys{hi}, key)
        previous = S.hb_vals(hi);
        found = true;
        return;
    end
end
end

function S = local_store(S, key, value)
for hi = 1:length(S.hb_keys)
    if strcmp(S.hb_keys{hi}, key)
        S.hb_vals(hi) = value;
        return;
    end
end
S.hb_keys{end + 1} = key;
S.hb_vals(end + 1) = value;
end

% -------------------------------------------------------------- admission --



function [out, S] = local_admit(S, c)
[out, S] = local_admit_core(S, c);
end

function [out, S] = local_admit_core(S, c)
% Decides whether a candidate is shown now, and updates the stage state.
out = {};
if any(strcmp(c.status, {'CANCELLED'; 'ERROR'}))
    S.subjects(S.subject_slot).terminal = true;
    S.subjects(S.subject_slot).has_held = false;
    S.subjects(S.subject_slot).held = struct();
    if ~isfield(c.context, 'subject_index') || ...
            (isfield(c.context, 'scope') && strcmp(c.context.scope, 'run')) || ...
            (strcmp(c.status, 'CANCELLED') && strncmp(c.text, 'Run cancel', 10))
        S.terminal = true;
        for si = 1:length(S.subjects)
            S.subjects(si).has_held = false;
            S.subjects(si).held = struct();
        end
    end
elseif (S.terminal || (S.subjects(S.subject_slot).terminal && ...
        ~strcmp(c.kind, 'run_completed'))) && ...
        any(strcmp(c.status, {'ACTIVE'; 'DONE'; 'SKIPPED'; 'VERIFIED'}))
    return;
end
if ~isempty(c.dedupe)
    if any(strcmp(c.dedupe, S.subjects(S.subject_slot).seen))
        return;
    end
    S.subjects(S.subject_slot).seen{end + 1} = c.dedupe;
end
if strcmp(c.kind, 'subject_completed') && strcmp(c.status, 'VERIFIED')
    S.subjects(S.subject_slot).terminal = true;
    S.subjects(S.subject_slot).has_held = false;
    S.subjects(S.subject_slot).held = struct();
end
if S.subjects(S.subject_slot).has_held && c.stage > 0 && any(strcmp(c.status, {'ACTIVE'; 'DONE'; 'SKIPPED'}))
    if c.stage == 4 && strcmp(c.status, 'DONE')
        [o1, S] = local_transition(S, c);
        [o2, S] = local_release_held(S, true);
        out = [o1 o2];
        return;
    end
    [o0, S] = local_release_held(S, false);
    out = o0;
end
if c.stage == 5 && strcmp(c.status, 'ACTIVE') && S.subjects(S.subject_slot).stage_state(4) == 1
    S.subjects(S.subject_slot).has_held = true;
    S.subjects(S.subject_slot).held = c;
    return;
end
[o1, S] = local_transition(S, c);
out = [out o1];
end



function [out, S] = local_transition(S, c)
% Parent stages move forward only. An orphan DONE has neither an admitted
% ACTIVE nor the explicit compiled "Successfully applied" outcome for 2/3.
% The latter is labelled as a report, never paired with a synthetic ACTIVE.
out = {};
if c.stage < 1 || ~any(strcmp(c.status, {'ACTIVE'; 'DONE'; 'SKIPPED'}))
    out = {c};
    return;
end
n = c.stage;
st = S.subjects(S.subject_slot).stage_state(n);
if strcmp(c.status, 'ACTIVE') && st == 0
    S.subjects(S.subject_slot).stage_state(n) = 1;
    out = {c};
elseif strcmp(c.status, 'DONE') && (st == 1 || ...
        (st == 0 && any(n == [2 3]) && strcmp(c.reason, 'backend:reported_applied')))
    S.subjects(S.subject_slot).stage_state(n) = 2;
    out = {c};
elseif strcmp(c.status, 'SKIPPED') && st == 0
    S.subjects(S.subject_slot).stage_state(n) = 3;
    out = {c};
end
end

function [out, S] = local_release_held(S, annotate)
% Releases the held stage-5 start; annotated when shown after DONE(4).
out = {};
if ~S.subjects(S.subject_slot).has_held
    return;
end
h = S.subjects(S.subject_slot).held;
S.subjects(S.subject_slot).has_held = false;
S.subjects(S.subject_slot).held = struct();
if annotate
    % Shown after DONE(4): live rows carry the release (observation) time,
    % replay keeps a null time. The source time stays in original_timestamp.
    h.orig = h.ts;
    if S.live
        h.ts = datestr(now, 'yyyy-mm-dd HH:MM:SS');
        h.observed = isempty(h.orig);
    else
        h.ts = '';
    end
    h.text = [h.text ' (start reported before stage 4 ended)'];
end
[out, S] = local_transition(S, h);
end

% -------------------------------------------------------------- output -----

function [visible, console_line, event_record, S] = local_output(S, emitted)
visible = false;
console_line = '';
event_record = local_unavailable_event();
jsonl = strcmp(getenv('PSEUDOCT_OUTPUT_FORMAT'), 'jsonl');
rows = {};
for ci = 1:length(emitted)
    c = emitted{ci};
    % Live rows never display a time earlier than the previous displayed row
    % of this subject (backend and orchestrator clocks may interleave). The
    % admission time is shown; the source time stays in original_timestamp.
    % Replay keeps source times unchanged.
    slot = S.subject_slot;
    if c.live && ~isempty(c.ts)
        last = S.subjects(slot).last_ts;
        if ~isempty(last) && local_ts_before(c.ts, last)
            c.orig = c.ts;
            c.ts = datestr(now, 'yyyy-mm-dd HH:MM:SS');
            if local_ts_before(c.ts, last)
                c.ts = last;
            end
        end
        S.subjects(slot).last_ts = c.ts;
    end
    current_record = local_event_struct(S, c);
    if ci == 1
        event_record = current_record;
    end
    S.records(end + 1) = current_record;
    if jsonl
        local_emit_json_event(current_record);
    else
        [txt, S] = local_text_row(S, c);
        rows{end + 1} = txt; %#ok<AGROW>
    end
end
if ~isempty(emitted)
    visible = true;
end
if ~isempty(rows)
    console_line = rows{1};
    for ri = 2:length(rows)
        console_line = [console_line char(10) rows{ri}]; %#ok<AGROW>
    end
end
end

function yes = local_ts_before(a, b)
% True when 'yyyy-mm-dd HH:MM:SS' string a is strictly earlier than b.
yes = false;
if length(a) ~= length(b)
    return;
end
d = find(a ~= b, 1);
yes = ~isempty(d) && a(d) < b(d);
end

function ev = local_event_struct(S, c)
ids = local_stage_ids();
ev = local_unavailable_event();
ev.level = 'INFO';
if strcmp(c.status, 'ERROR')
    ev.level = 'ERROR';
elseif strcmp(c.status, 'WARN')
    ev.level = 'WARN';
elseif any(strcmp(c.status, {'DONE'; 'VERIFIED'}))
    ev.level = 'SUCCESS';
end
ev.subject = 'RUN';
if c.stage > 0
    ev.stage = sprintf('[%d/10]', c.stage);
    ev.stage_number = sprintf('%d', c.stage);
    ev.stage_total = '10';
    ev.stage_id = ids{c.stage};
end
ev.status = c.status;
if ~isempty(c.job)
    ev.job = c.job;
end
ev.message = c.text;
if isempty(c.ts)
    ev.timestamp = 'null';
else
    ev.timestamp = c.ts;
end
ev.profile = S.profile;
ev.backend = local_backend_of(S.profile);
ev.event_kind = c.kind;
% Preserve the public vocabulary from the pre-rewrite emitter.
if strcmp(c.kind, 'milestone')
    ev.event_kind = 'info';
elseif any(strcmp(c.kind, {'run_failed'; 'diagnostic.error'}))
    ev.event_kind = 'failure';
elseif strcmp(c.kind, 'scheduler')
    ev.event_kind = 'scheduler_state';
elseif strcmp(c.kind, 'verification')
    ev.event_kind = 'output_verified';
elseif strcmp(c.kind, 'run_started')
    ev.event_kind = 'info';
end
if ~isempty(c.op)
    ev.operation_id = c.op;
end
ev.event_category = c.category;
if strcmp(ev.event_category, 'remote_processing')
    ev.event_category = 'remote_execution';
end
if strncmp(c.op, 'output.', 7) && ~strcmp(c.op, 'output.verify')
    ev.event_category = 'finalization';
elseif strcmp(c.kind, 'subject_completed') && ~strcmp(c.status, 'VERIFIED')
    ev.event_category = 'subject';
elseif strcmp(c.kind, 'run_completed')
    ev.event_category = 'run';
elseif strcmp(c.status, 'CANCELLED') && isfield(c.context, 'subject_index')
    ev.event_category = 'subject';
end
ev.source = c.src;
if ~isempty(c.file)
    ev.source_file = c.file;
end
if ~isempty(c.reason)
    ev.reason = c.reason;
end
ev.stage_span = [];
ev.operation_ids = {};
ev.live = logical(c.live);
if isempty(c.orig) && c.observed
    ev.original_timestamp = 'null';   % no source timestamp existed
elseif isempty(c.orig)
    ev.original_timestamp = ev.timestamp;
else
    ev.original_timestamp = c.orig;
end
ev.source_lines = c.lines;
% Context is attached to the candidate, not read from the latest event: this
% also preserves provenance when the bounded stage-5 hold is released later.
context = c.context;
fields = {'operation_id'; 'event_kind'; 'event_category'; 'source'; ...
    'source_file'; 'reason'; 'original_timestamp'; 'stage_id'};
for ii = 1:length(fields)
    name = fields{ii};
    if isfield(context, name) && ischar(context.(name)) && ~isempty(context.(name))
        ev.(name) = context.(name);
    end
end
if c.stage > 0
    ev.stage_id = ids{c.stage};
end
if isfield(context, 'stage_span') && isnumeric(context.stage_span) && ...
        numel(context.stage_span) == 2 && all(isfinite(context.stage_span(:))) && ...
        all(context.stage_span(:) == floor(context.stage_span(:)))
    ev.stage_span = reshape(context.stage_span, 1, 2);
end
if isfield(context, 'operation_ids') && iscell(context.operation_ids)
    ev.operation_ids = context.operation_ids;
end
if isfield(context, 'subject_index') && ~isempty(context.subject_index)
    ev.subject = sprintf('S%02d', local_subject_index(context));
end
if isfield(context, 'job_number') && ~isempty(context.job_number)
    if isnumeric(context.job_number)
        ev.job = num2str(context.job_number);
    elseif ischar(context.job_number)
        ev.job = context.job_number;
    end
end
% Observed severity/evidence takes priority over inherited start hints.
if strcmp(c.status, 'CANCELLED')
    ev.event_kind = 'cancelled';
    if any(strcmp(c.level, {'INFO'; 'WARN'; 'ERROR'}))
        ev.level = c.level;
    end
elseif strcmp(c.status, 'ERROR')
    ev.event_kind = 'failure';
elseif strcmp(c.status, 'WARN')
    ev.event_kind = 'warning';
elseif strcmp(c.kind, 'output_verified')
    ev.event_kind = 'output_verified';
elseif c.stage == 10 && isfield(context, 'operation_id') && ...
        strcmp(context.operation_id, 'output.promote_nifti')
    % This operation is the numbered MPRAGE-only parent, not a child.
    ev.event_kind = c.kind;
end
end

function [text, S] = local_text_row(S, c)
% Fixed columns: TIME SUBJECT STAGE STATUS MESSAGE. The stage number is shown
% once, on the first row for that stage.
text = '';
if ~S.header_done
    S.header_done = true;
    if S.replay
        text = [text 'pseudoCT ' '—' ' ' local_profile_title(S.profile) ...
            ' ' '—' ' archived offline replay (not live)' char(10)];
    end
    text = [text sprintf('%-8s %-7s %-7s %-9s %s', 'TIME', 'SUBJECT', 'STAGE', 'STATUS', 'MESSAGE') char(10)];
    text = [text repmat('-', 1, 123) char(10)];
end
label = '';
if c.stage > 0 && ~S.subjects(S.subject_slot).label_shown(c.stage)
    label = sprintf('[%d/10]', c.stage);
    S.subjects(S.subject_slot).label_shown(c.stage) = true;
end
stamp = '--:--:--';
if length(c.ts) >= 19
    stamp = c.ts(12:19);
end
prefix = sprintf('%-8s %-7s %-7s %-9s ', stamp, ...
    sprintf('S%02d', local_subject_index(c.context)), label, c.status);
lead = '';
body = c.text;
while ~isempty(body) && body(1) == ' '
    lead = [lead ' ']; %#ok<AGROW>
    body = body(2:end);
end
words = local_wrap(body, max(30, 123 - length(prefix) - length(lead)));
for wi = 1:length(words)
    if wi == 1
        line = [prefix lead words{wi}];
    else
        line = [repmat(' ', 1, length(prefix)) words{wi}];
    end
    text = [text line char(10)]; %#ok<AGROW>
end
text = text(1:end - 1);
end

function words = local_wrap(body, width)
% Greedy word wrap (textwrap without long-word breaking).
words = {};
rest = body;
line = '';
tokens = regexp(rest, ' ', 'split');
for ti = 1:length(tokens)
    w = tokens{ti};
    if isempty(w)
        continue;
    end
    if isempty(line)
        line = w;
    elseif length(line) + 1 + length(w) <= width
        line = [line ' ' w];
    else
        words{end + 1} = line; %#ok<AGROW>
        line = w;
    end
end
if ~isempty(line) || isempty(words)
    words{end + 1} = line;
end
end

function events = local_empty_events()
events = struct('level', {}, 'subject', {}, 'stage', {}, 'status', {}, ...
    'job', {}, 'message', {}, 'timestamp', {}, 'profile', {}, 'backend', {}, ...
    'schema_version', {}, 'event_kind', {}, 'operation_id', {}, ...
    'event_category', {}, 'source', {}, 'source_file', {}, 'reason', {}, ...
    'stage_id', {}, 'stage_number', {}, 'stage_total', {}, 'stage_span', {}, ...
    'operation_ids', {}, 'live', {}, 'original_timestamp', {}, ...
    'source_lines', {}, 'source_timestamp', {}, 'orchestration_timestamp', {}, ...
    'orchestration_source_file', {}, 'orchestration_source_lines', {});
end

function event = local_unavailable_event()
event = struct('level', 'unavailable', 'subject', 'unavailable', ...
    'stage', 'unavailable', 'status', 'unavailable', 'job', 'unavailable', ...
    'message', 'unavailable', 'timestamp', 'unavailable', ...
    'profile', 'unavailable', 'backend', 'unavailable', ...
    'schema_version', '1', 'event_kind', 'unavailable', ...
    'operation_id', 'unavailable', 'event_category', 'unavailable', ...
    'source', 'unavailable', 'source_file', 'unavailable', ...
    'reason', 'unavailable', 'stage_id', 'unavailable', ...
    'stage_number', 'unavailable', 'stage_total', 'unavailable', ...
    'stage_span', [], 'operation_ids', {{}}, 'live', true, ...
    'original_timestamp', 'null', 'source_lines', [], ...
    'source_timestamp', '', 'orchestration_timestamp', '', ...
    'orchestration_source_file', '', 'orchestration_source_lines', []);
end

function backend = local_backend_of(profile_name)
backend = 'unavailable';
if ~ischar(profile_name) || isempty(profile_name)
    return;
end
if strncmp(profile_name, 'local-', 6)
    backend = 'local';
elseif strncmp(profile_name, 'mlsc-', 5)
    backend = 'mlsc';
end
end

function yes = local_contract_applies(profile_name)
%LOCAL_CONTRACT_APPLIES The additive event contract applies to every known
%   profile, including Local Current. The existing JSONL keys are unchanged.
yes = ischar(profile_name) && ~isempty(profile_name) && ...
    ~strcmp(profile_name, 'unavailable');
end

function local_emit_json_event(event_record)
record = '{"type":"progress"';
% Existing keys keep their order and meaning. The additive contract keys follow
% them and are emitted only for profiles where local_contract_applies is true.
fields = {'schema_version'; 'timestamp'; 'level'; 'subject'; 'stage'; ...
    'status'; 'job'; 'message'; 'profile'; 'backend'; 'event_kind'; ...
    'operation_id'; 'event_category'; 'source'; 'source_file'; 'reason'; ...
    'stage_id'; 'stage_number'; 'stage_total'; 'stage_span'; 'operation_ids'; ...
    'live'; 'original_timestamp'; 'source_lines'; 'source_timestamp'; ...
    'orchestration_timestamp'; 'orchestration_source_file'; 'orchestration_source_lines'};
required = {'timestamp'; 'level'; 'message'};
optional_context = {'subject'; 'stage'; 'status'; 'job'};
contract_fields = {'schema_version'; 'profile'; 'backend'; 'event_kind'; ...
    'operation_id'; 'event_category'; 'source'; 'source_file'; 'reason'; ...
    'stage_id'; 'stage_number'; 'stage_total'; 'stage_span'; 'operation_ids'; ...
    'live'; 'original_timestamp'};
numeric_fields = {'schema_version'; 'stage_number'; 'stage_total'};
contract_on = isstruct(event_record) && isfield(event_record, 'profile') && ...
    ischar(event_record.profile) && local_contract_applies(event_record.profile);
for ii = 1:length(fields)
    field_name = fields{ii};
    if any(strcmp(contract_fields, field_name)) && ~contract_on
        continue;
    end
    value = 'unavailable';
    if isstruct(event_record) && isfield(event_record, field_name)
        candidate = event_record.(field_name);
        if ischar(candidate)
            value = candidate;
    elseif strcmp(field_name, 'live') && (islogical(candidate) || isnumeric(candidate))
            value = candidate;
        elseif any(strcmp(field_name, {'stage_span'; 'operation_ids'; ...
                'source_lines'; 'orchestration_source_lines'}))
            value = candidate;
        end
    end
    if strcmp(field_name, 'stage_span') && isempty(value)
        continue;
    elseif strcmp(field_name, 'operation_ids') && isempty(value)
        continue;
    elseif any(strcmp(field_name, {'source_lines'; 'orchestration_source_lines'})) && isempty(value)
        continue;
    end
    missing_context = any(strcmp(optional_context, field_name)) && ...
        ischar(value) && any(strcmpi(value, {'null'; 'unavailable'}));
    if (ischar(value) && (isempty(value) || strcmp(value, 'unavailable'))) || missing_context || ...
            (strcmp(field_name, 'subject') && strcmp(value, 'RUN'))
        if any(strcmp(required, field_name))
            value = '';
        else
            continue;
        end
    end
    if any(strcmp(numeric_fields, field_name))
        % Integer values are built only from sprintf('%d'); unavailable
        % stage numbers are JSON null, never the invalid bare token.
        if ~ischar(value) || isempty(regexp(value, '^[0-9]+$', 'once'))
            value = 'null';
        end
        record = [record ',"' field_name '":' value]; %#ok<AGROW>
    elseif strcmp(field_name, 'live')
        if (islogical(value) || isnumeric(value)) && isscalar(value) && ...
                isfinite(double(value)) && logical(value)
            encoded = 'true';
        else
            encoded = 'false';
        end
        record = [record ',"' field_name '":' encoded]; %#ok<AGROW>
    elseif any(strcmp(field_name, {'source_lines'; 'orchestration_source_lines'}))
        if ~isnumeric(value) || any(~isfinite(value(:))) || ...
                any(value(:) < 1) || any(value(:) ~= floor(value(:)))
            continue;
        end
        encoded = sprintf('%d,', value);
        record = [record ',"' field_name '":[' encoded(1:end - 1) ']']; %#ok<AGROW>
    elseif strcmp(field_name, 'stage_span')
        if ~isnumeric(value) || numel(value) ~= 2 || ...
                any(~isfinite(value(:))) || any(value(:) ~= floor(value(:)))
            continue;
        end
        record = [record ',"' field_name '":[' ...
            sprintf('%d,%d', value(1), value(2)) ']']; %#ok<AGROW>
    elseif strcmp(field_name, 'operation_ids')
        if ~iscell(value) || ~all(cellfun(@ischar, value))
            continue;
        end
        encoded = '[';
        for jj = 1:length(value)
            if jj > 1
                encoded = [encoded ',']; %#ok<AGROW>
            end
            encoded = [encoded local_json_quote(value{jj})]; %#ok<AGROW>
        end
        encoded = [encoded ']'];
        record = [record ',"' field_name '":' encoded]; %#ok<AGROW>
    elseif any(strcmp(field_name, {'timestamp'; 'original_timestamp'})) && ...
            ischar(value) && strcmp(value, 'null')
        record = [record ',"' field_name '":null']; %#ok<AGROW>
    else
        record = [record ',"' field_name '":' local_json_quote(value)]; %#ok<AGROW>
    end
end
record = [record '}'];
fprintf(1, '%s\n', record);
end


function encoded = local_json_quote(value)
encoded = '"';
for ii = 1:length(value)
    code = double(value(ii));
    if code == 34
        encoded = [encoded '\"']; %#ok<AGROW>
    elseif code == 92
        encoded = [encoded '\\']; %#ok<AGROW>
    elseif code == 8
        encoded = [encoded '\b']; %#ok<AGROW>
    elseif code == 9
        encoded = [encoded '\t']; %#ok<AGROW>
    elseif code == 10
        encoded = [encoded '\n']; %#ok<AGROW>
    elseif code == 12
        encoded = [encoded '\f']; %#ok<AGROW>
    elseif code == 13
        encoded = [encoded '\r']; %#ok<AGROW>
    elseif code < 32
        encoded = [encoded sprintf('\\u%04x', code)]; %#ok<AGROW>
    else
        encoded = [encoded value(ii)]; %#ok<AGROW>
    end
end
encoded = [encoded '"'];
end
