function out = pseudo_CT_launch_request(action, varargin)
%PSEUDO_CT_LAUNCH_REQUEST Shared parameter-to-launcher translation for the frontend.
%   REQUEST = PSEUDO_CT_LAUNCH_REQUEST('parse', ARGS, ROOT_DIR) validates the
%   Name, Value cell ARGS of run_pseudo_CT and returns a normalized request.
%   ROOT_DIR is the folder that holds run_pseudo_CT.m and bin/pseudoct. Input
%   files are checked before the launcher is resolved.
%
%   RESULT = PSEUDO_CT_LAUNCH_REQUEST('invoke', REQUEST) runs the compiled
%   launcher (bin/pseudoct validate|run ... --format text --result-file PATH).
%   The launcher's stdout is not redirected, so its progress text is sent to the
%   MATLAB Command Window. Whether it appears live during the run is not yet
%   confirmed on the installed MATLAB. The result record is read from PATH.
%   Every argument is POSIX single-quoted; no user text is interpolated unquoted. The child
%   process environment drops MATLAB's library and path variables so the
%   launcher selects its own MATLAB Runtime. RESULT is a struct with ok,
%   exit_code, action, profile, outcome, submission_status,
%   authentication_status, dispatch_status, scientific_completion_status,
%   backend, error_code, error_message, job_ids (cell), stderr and
%   record_found.
%
%   ARGV = PSEUDO_CT_LAUNCH_REQUEST('argv', REQUEST, CONFIG_PATH) returns the
%   launcher argument cell (without the launcher path). CONFIG_PATH is used
%   only for multi-subject requests: the --subjects file written for Subject
%   pairs, or the --config JSON for a cell of MPRAGE paths.
%
%   Subject inputs: 'Subject', FILE passes a subjects file (--subjects FILE);
%   'Subject', {{MPRAGE, UMAP}, ...} is written to a temporary subjects file by
%   'invoke'. The launcher parses and checks subjects files; MATLAB does not.
%   JSON = PSEUDO_CT_LAUNCH_REQUEST('config', REQUEST) returns the multi-subject
%   --config text (mprage and umap arrays).
%   KEY = PSEUDO_CT_LAUNCH_REQUEST('fingerprint', REQUEST) returns the text that
%   identifies the inputs and options of one validation. Compare it with the
%   fingerprint stored at validation time to detect changed inputs.
%
%   CHECK = PSEUDO_CT_LAUNCH_REQUEST('check-subjects', LAUNCHER, PROFILE, FILE) runs the
%   read-only 'LAUNCHER check-subjects --profile PROFILE --subjects FILE --format tsv'
%   (the launcher's subjects-file parser; MATLAB does not parse the file) and returns a
%   struct with ok (true when the file is valid), exit_code, subjects (struct array: id,
%   and for MPRAGE and UMAP the value as written, the absolute path, the resolved file
%   and the detail; fields mprage, mprage_path, mprage_resolved, mprage_detail, umap,
%   umap_path, umap_resolved, umap_detail), errors (struct array: line, subject,
%   message) and message (text when the launcher printed no table).
%
%   Credentials are never accepted as parameters or placed on a command line.
%   The only credential-related input is CredentialHandoff, a path to an
%   existing single-use handoff created by the launcher's own mechanism.
%   Minimum supported MATLAB: R2010b.

if nargin < 1 || ~ischar(action)
    error('pseudo_CT:FrontendUsage', 'A frontend request action is required.');
end
switch lower(action)
    case 'parse'
        if nargin ~= 3
            error('pseudo_CT:FrontendUsage', 'Parse needs the arguments and the root folder.');
        end
        out = local_parse(varargin{1}, varargin{2});
    case 'argv'
        out = local_argv(varargin{1}, '', '');
        if nargin > 2
            out = local_argv(varargin{1}, varargin{2}, '');
        end
    case 'config'
        out = local_config_text(varargin{1});
    case 'fingerprint'
        out = local_fingerprint(varargin{1});
    case 'invoke'
        out = local_invoke(varargin{1});
    case 'launcher'
        if nargin ~= 3
            error('pseudo_CT:FrontendUsage', 'Launcher needs the explicit path and the root folder.');
        end
        out = local_resolve_launcher(local_abs(varargin{1}), varargin{2});
    case 'releases'
        out = local_releases(varargin{1});
    case 'check-subjects'
        if nargin ~= 4
            error('pseudo_CT:FrontendUsage', ...
                'check-subjects needs the launcher, the profile and the subjects file.');
        end
        out = local_check_subjects(varargin{1}, varargin{2}, varargin{3});
    otherwise
        error('pseudo_CT:FrontendUsage', 'Unknown frontend request action.');
end
end

function req = local_parse(args, root_dir)
if ~iscell(args) || mod(numel(args), 2) ~= 0
    error('pseudo_CT:FrontendUsage', 'Arguments must be Name, Value pairs.');
end
req = struct('profile', '', 'mprage', {{}}, 'umap', {{}}, 'subjects_file', '', ...
    'subjects', {{}}, 'action', 'validate', ...
    'cli_action', 'validate', 'runtime', '', 'mcr_root', '', 'launcher', '', ...
    'correct_aliasing', '', 'recenter', '', 'cleanup', '', 'artifact_root', '', ...
    'group_account', '', 'host_key_file', '', 'credential_handoff', '', ...
    'max_concurrent', '');
for kk = 1:2:numel(args)
    name = args{kk};
    if ~ischar(name) || size(name, 1) ~= 1
        error('pseudo_CT:FrontendUsage', 'Parameter names must be text.');
    end
    key = lower(strrep(name, '_', ''));
    value = args{kk + 1};
    if ~strcmp(key, 'credentialhandoff') && local_is_secret_name(key)
        error('pseudo_CT:FrontendSecretArgument', ...
            ['Credentials are not accepted as frontend parameters. Use ' ...
            'CredentialHandoff with an existing launcher handoff file.']);
    end
    switch key
        case 'profile'
            req.profile = local_text(value, 'Profile');
        case 'mprage'
            req.mprage = local_path_list(value, 'MPRAGE');
        case 'umap'
            req.umap = local_path_list(value, 'UMAP');
        case 'subject'
            [req.subjects_file, req.subjects] = local_subject_value(value);
        case 'action'
            req.action = lower(local_text(value, 'Action'));
            if ~any(strcmp(req.action, {'validate'; 'submit'; 'authenticate'}))
                error('pseudo_CT:FrontendUsage', 'Action must be validate, submit or authenticate.');
            end
        case 'runtime'
            req.runtime = local_text(value, 'Runtime');
            if isempty(regexp(req.runtime, '^[A-Za-z0-9]+$', 'once'))
                error('pseudo_CT:FrontendUsage', 'Runtime must be a release label, for example R2010b.');
            end
        case 'mcrroot'
            req.mcr_root = local_abs(local_text(value, 'McrRoot'));
        case 'launcher'
            req.launcher = local_abs(local_text(value, 'Launcher'));
        case 'correctaliasing'
            req.correct_aliasing = local_yes_no(value, 'CorrectAliasing');
        case 'recenterbeforenormalization'
            req.recenter = local_yes_no(value, 'RecenterBeforeNormalization');
        case 'cleanuponsuccess'
            req.cleanup = local_yes_no(value, 'CleanupOnSuccess');
        case 'maxconcurrent'
            req.max_concurrent = local_max_concurrent(value);
        case 'currentartifactroot'
            req.artifact_root = local_text(value, 'CurrentArtifactRoot');
        case 'groupaccount'
            req.group_account = local_text(value, 'GroupAccount');
        case 'hostkeyfile'
            req.host_key_file = local_abs(local_text(value, 'HostKeyFile'));
        case 'credentialhandoff'
            req.credential_handoff = local_abs(local_text(value, 'CredentialHandoff'));
        otherwise
            error('pseudo_CT:FrontendUsage', 'Unknown parameter: %s', name);
    end
end
has_subject = ~isempty(req.subjects_file) || ~isempty(req.subjects);
if isempty(req.profile) || (isempty(req.mprage) && ~has_subject)
    error('pseudo_CT:FrontendUsage', 'Profile and Subject (or MPRAGE) are required.');
end
if has_subject && (~isempty(req.mprage) || ~isempty(req.umap))
    error('pseudo_CT:FrontendUsage', 'Use either Subject or MPRAGE/UMAP, not both.');
end
if ~isempty(req.subjects_file)
    local_require_file(req.subjects_file, 'Subject file');
end
if ~any(strcmp(req.profile, {'local'; 'local-mprage-only'; 'mlsc'; 'mlsc-mprage-only'}))
    error('pseudo_CT:InvalidProfile', 'Unknown profile: %s', req.profile);
end
% The artifact-root override is development-only and accepted for MLSC profiles only
% (same rule as bin/pseudoct and pseudo_CT_apply_mlsc_current_overrides).
if ~isempty(req.artifact_root) && ~any(strcmp(req.profile, {'mlsc'; 'mlsc-mprage-only'}))
    error('run_pseudo_CT:InvalidMlscCurrentOverride', ['CurrentArtifactRoot is a ' ...
        'development-only override accepted only for the mlsc and mlsc-mprage-only ' ...
        'profiles; profile ''%s'' is incompatible.'], req.profile);
end
if ~isempty(req.umap) && numel(req.umap) ~= numel(req.mprage)
    error('pseudo_CT:OrchestrationInput', ...
        'UMAP paths must be positionally paired with MPRAGE paths.');
end
for kk = 1:numel(req.mprage)
    local_require_file(req.mprage{kk}, 'MPRAGE');
end
for kk = 1:numel(req.umap)
    local_require_file(req.umap{kk}, 'UMAP');
end
if ~isempty(req.credential_handoff)
    local_require_file(req.credential_handoff, 'Credential handoff');
end
if strcmp(req.action, 'submit')
    req.cli_action = 'run';
end
% Internal to the frontend: 'authenticate' is not a run_pseudo_CT Action value. It is one
% authentication-only launcher call (authenticate) for an MLSC profile.
if strcmp(req.action, 'authenticate')
    req.cli_action = 'authenticate';
    if isempty(req.credential_handoff) || ...
            ~any(strcmp(req.profile, {'mlsc'; 'mlsc-mprage-only'}))
        error('pseudo_CT:FrontendUsage', ...
            'Authenticate needs an MLSC profile and a CredentialHandoff.');
    end
end
req.launcher = local_resolve_launcher(req.launcher, root_dir);
req.fingerprint = local_fingerprint(req);
end

function launcher = local_resolve_launcher(launcher, root_dir)
%LOCAL_RESOLVE_LAUNCHER The launcher for this root. An installed distribution (the
%   tree without src/) always runs the bin/pseudoct beside run_pseudo_CT.m: it never
%   reads PSEUDOCT_LAUNCHER and never falls back to source. An explicit Launcher is
%   accepted there only when it names that same bundled file (the GUI passes it);
%   any other value is refused with run_pseudo_CT:LauncherOverrideDevelopmentOnly.
%   In a source checkout the explicit Launcher, then PSEUDOCT_LAUNCHER, are the
%   development and test hooks.
bundled = fullfile(root_dir, 'bin', 'pseudoct');
if local_is_installed(root_dir)
    if exist(fullfile(root_dir, 'runtimes'), 'dir') ~= 7
        error('pseudo_CT:FrontendLauncher', ['This pseudoCT installation is ' ...
            'incomplete: runtimes/ is missing beside run_pseudo_CT.m. Reinstall ' ...
            'the pseudoCT distribution.']);
    end
    if ~isempty(launcher) && ~strcmp(launcher, bundled)
        error('run_pseudo_CT:LauncherOverrideDevelopmentOnly', ['The Launcher ' ...
            'argument is a development and test override for source checkouts only. ' ...
            'An installed distribution always runs its bundled bin/pseudoct; remove ' ...
            'the Launcher argument.']);
    end
    launcher = bundled;
elseif isempty(launcher)
    env_value = strtrim(getenv('PSEUDOCT_LAUNCHER'));
    if isempty(env_value)
        error('pseudo_CT:FrontendLauncher', ['No launcher: this is a source ' ...
            'checkout, which is for development only. Pass Launcher, or set ' ...
            'PSEUDOCT_LAUNCHER, to a compiled bin/pseudoct.']);
    end
    launcher = local_abs(env_value);
end
if exist(launcher, 'file') ~= 2
    error('pseudo_CT:FrontendLauncher', 'The launcher is unavailable: %s', launcher);
end
end

function text = local_max_concurrent(value)
%LOCAL_MAX_CONCURRENT MaxConcurrent as launcher text: an integer from 1 to 32.
if ischar(value)
    value = str2double(strtrim(value));
end
if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ~isfinite(value) || ...
        value ~= fix(value) || value < 1 || value > 32
    error('pseudo_CT:FrontendUsage', 'MaxConcurrent must be an integer from 1 to 32.');
end
text = sprintf('%d', value);
end

function flag = local_is_installed(root_dir)
%LOCAL_IS_INSTALLED True for the packaged layout: no src/ tree beside run_pseudo_CT.m.
flag = exist(fullfile(root_dir, 'src'), 'dir') ~= 7;
end

function argv = local_argv(req, config_path, result_path)
%LOCAL_ARGV RESULT_PATH empty: the jsonl argument list of the 'argv' action. Otherwise
%   the text launch whose result record is written to RESULT_PATH ('invoke').
if strcmp(req.cli_action, 'authenticate')
    argv = local_authenticate_argv(req, result_path);
    return;
end
argv = {req.cli_action};
if ~isempty(req.runtime)
    argv = [argv, {'--mcr', req.runtime}];
end
if ~isempty(req.mcr_root)
    argv = [argv, {'--mcr-root', req.mcr_root}];
end
argv = [argv, {'--profile', req.profile}];
if ~isempty(req.subjects_file)
    argv = [argv, {'--subjects', req.subjects_file}];
elseif ~isempty(req.subjects)
    argv = [argv, {'--subjects', config_path}];
elseif numel(req.mprage) > 1
    argv = [argv, {'--config', config_path}];
else
    argv = [argv, {'--mprage', req.mprage{1}}];
    if ~isempty(req.umap)
        argv = [argv, {'--umap', req.umap{1}}];
    end
end
if ~isempty(req.correct_aliasing)
    argv = [argv, {'--correct-aliasing', req.correct_aliasing}];
end
if ~isempty(req.recenter)
    argv = [argv, {'--recenter-before-normalization', req.recenter}];
end
if ~isempty(req.cleanup)
    argv = [argv, {'--cleanup-on-success', req.cleanup}];
end
if ~isempty(req.max_concurrent)
    argv = [argv, {'--max-concurrent', req.max_concurrent}];
end
if ~isempty(req.artifact_root)
    argv = [argv, {'--current-artifact-root', req.artifact_root}];
end
if ~isempty(req.group_account)
    argv = [argv, {'--group-account', req.group_account}];
end
if ~isempty(req.host_key_file)
    argv = [argv, {'--host-key-file', req.host_key_file}];
end
if ~isempty(req.credential_handoff)
    argv = [argv, {'--credential-handoff', req.credential_handoff}];
end
if isempty(result_path)
    argv = [argv, {'--format', 'jsonl'}];
else
    argv = [argv, {'--format', 'text', '--result-file', result_path}];
end
end

function argv = local_authenticate_argv(req, result_path)
%LOCAL_AUTHENTICATE_ARGV authenticate: one authentication-only launcher call with an
%   existing credential handoff. No inputs, options or submission.
argv = {'authenticate'};
if ~isempty(req.runtime)
    argv = [argv, {'--mcr', req.runtime}];
end
if ~isempty(req.mcr_root)
    argv = [argv, {'--mcr-root', req.mcr_root}];
end
argv = [argv, {'--profile', req.profile, ...
    '--credential-handoff', req.credential_handoff}];
if ~isempty(req.group_account)
    argv = [argv, {'--group-account', req.group_account}];
end
if ~isempty(req.host_key_file)
    argv = [argv, {'--host-key-file', req.host_key_file}];
end
if isempty(result_path)
    argv = [argv, {'--format', 'jsonl'}];
else
    argv = [argv, {'--format', 'text', '--result-file', result_path}];
end
end

function text = local_config_text(req)
items = cell(1, 2);
items{1} = ['"mprage": [' local_json_list(req.mprage) ']'];
if ~isempty(req.umap)
    items{2} = ['"umap": [' local_json_list(req.umap) ']'];
    text = ['{' items{1} ', ' items{2} '}' char(10)];
else
    text = ['{' items{1} '}' char(10)];
end
end

function text = local_subjects_text(pairs)
%LOCAL_SUBJECTS_TEXT Subjects-file text for SUBJECT pairs {MPRAGE, UMAP} ('' UMAP: none),
%   with identifiers Subject_001, Subject_002, ... The quoting rules are those of
%   pseudo_CT_subjects_file (shared with the window's export); the paths are absolute
%   single lines (local_subject_value).
ids = cell(1, numel(pairs));
mprage = cell(1, numel(pairs));
umap = cell(1, numel(pairs));
for kk = 1:numel(pairs)
    ids{kk} = sprintf('Subject_%03d', kk);
    mprage{kk} = pairs{kk}{1};
    umap{kk} = pairs{kk}{2};
end
text = pseudo_CT_subjects_file('text', ids, mprage, umap);
end

function check = local_check_subjects(launcher, profile, file)
%LOCAL_CHECK_SUBJECTS One read-only 'check-subjects --format tsv' launcher call; the table
%   contract (header, subject, error and end rows, escapes) is in docs/headless-cli.md.
check = struct('ok', false, 'exit_code', -1, 'subjects', local_empty_subjects(), ...
    'errors', struct('line', {}, 'subject', {}, 'message', {}), 'message', '');
if ~ischar(launcher) || exist(launcher, 'file') ~= 2
    error('pseudo_CT:FrontendLauncher', 'The launcher is unavailable: %s', launcher);
end
out_file = tempname;
err_file = tempname;
cleanup_files = onCleanup(@() local_delete({out_file; err_file})); %#ok<NASGU>
argv = {'check-subjects', '--profile', local_text(profile, 'Profile'), ...
    '--subjects', local_text(file, 'Subject file'), '--format', 'tsv'};
status = system([local_clean_prefix() local_sh(launcher) local_join_sh(argv) ...
    ' >' local_sh(out_file) ' 2>' local_sh(err_file)]);
check.exit_code = status;
text = local_read_utf8(out_file);
lines = regexp(text, '\n', 'split');
if isempty(lines) || ~strcmp(lines{1}, sprintf('pseudoct-subjects-tsv\t1'))
    message = strtrim([text char(10) local_read(err_file)]);
    if isempty(message)
        message = sprintf('check-subjects exit status %d', status);
    end
    check.message = local_tail(strrep(message, 'pseudoct: ', ''), 4000);
    return;
end
ended = false;
for kk = 2:numel(lines)
    if isempty(lines{kk})
        continue;
    end
    fields = regexp(lines{kk}, '\t', 'split');
    switch fields{1}
        case 'subject'
            if numel(fields) ~= 10
                check.message = 'check-subjects printed a malformed subject row.';
                return;
            end
            values = cell(1, 9);
            for jj = 1:9
                values{jj} = local_tsv_unescape(fields{jj + 1});
            end
            check.subjects(end + 1) = struct('id', values{1}, ...
                'mprage', values{2}, 'mprage_path', values{3}, ...
                'mprage_resolved', values{4}, 'mprage_detail', values{5}, ...
                'umap', values{6}, 'umap_path', values{7}, ...
                'umap_resolved', values{8}, 'umap_detail', values{9});
        case 'error'
            if numel(fields) ~= 4
                check.message = 'check-subjects printed a malformed error row.';
                return;
            end
            check.errors(end + 1) = struct('line', str2double(fields{2}), ...
                'subject', local_tsv_unescape(fields{3}), ...
                'message', local_tsv_unescape(fields{4}));
        case 'end'
            ended = true;
            break;
        otherwise
            check.message = 'check-subjects printed an unknown row.';
            return;
    end
end
if ~ended
    check.message = 'check-subjects output is incomplete.';
    return;
end
check.ok = status == 0 && isempty(check.errors) && ~isempty(check.subjects);
end

function subjects = local_empty_subjects()
subjects = struct('id', {}, 'mprage', {}, 'mprage_path', {}, 'mprage_resolved', {}, ...
    'mprage_detail', {}, 'umap', {}, 'umap_path', {}, 'umap_resolved', {}, ...
    'umap_detail', {});
end

function value = local_tsv_unescape(text)
%LOCAL_TSV_UNESCAPE Reverse of the launcher's escapes: \\ \t \n \r and \xHH.
value = '';
if isempty(strfind(text, char(92))) %#ok<STREMP>
    value = text;
    return;
end
kk = 1;
while kk <= length(text)
    ch = text(kk);
    if ch ~= char(92) || kk == length(text)
        value = [value ch]; %#ok<AGROW>
        kk = kk + 1;
        continue;
    end
    next = text(kk + 1);
    switch next
        case char(92)
            value = [value char(92)]; %#ok<AGROW>
            kk = kk + 2;
        case 't'
            value = [value char(9)]; %#ok<AGROW>
            kk = kk + 2;
        case 'n'
            value = [value char(10)]; %#ok<AGROW>
            kk = kk + 2;
        case 'r'
            value = [value char(13)]; %#ok<AGROW>
            kk = kk + 2;
        case 'x'
            if kk + 3 <= length(text)
                value = [value char(hex2dec(text(kk + 2:kk + 3)))]; %#ok<AGROW>
                kk = kk + 4;
            else
                value = [value ch]; %#ok<AGROW>
                kk = kk + 1;
            end
        otherwise
            value = [value ch]; %#ok<AGROW>
            kk = kk + 1;
    end
end
end

function text = local_read_utf8(path_text)
text = '';
fid = fopen(path_text, 'r', 'n', 'UTF-8');
if fid < 0
    return;
end
text = fread(fid, '*char')';
fclose(fid);
end

function [file, pairs] = local_subject_value(value)
%LOCAL_SUBJECT_VALUE 'Subject': a subjects-file path, or a cell of {MPRAGE} or
%   {MPRAGE, UMAP} cells (one per subject; a single subject is {{MPRAGE, UMAP}}).
%   Relative paths are made absolute against the current folder. Existence, file
%   type and DICOM series are checked by the launcher, for all subjects together.
file = '';
pairs = {};
if ischar(value)
    file = local_abs(local_text(value, 'Subject'));
    return;
end
if ~iscell(value) || isempty(value)
    error('pseudo_CT:FrontendUsage', ['Subject must be a subjects-file path or a cell ' ...
        'of {MPRAGE, UMAP} cells.']);
end
pairs = cell(1, numel(value));
for kk = 1:numel(value)
    item = value{kk};
    if ~iscell(item) || numel(item) < 1 || numel(item) > 2
        error('pseudo_CT:FrontendUsage', ['Subject %d must be a cell {MPRAGE, UMAP} ' ...
            '(or {MPRAGE} for an MPRAGE-only profile); one subject is written ' ...
            '{{MPRAGE, UMAP}}.'], kk);
    end
    mprage = local_abs(local_text(item{1}, sprintf('Subject %d MPRAGE', kk)));
    umap = '';
    if numel(item) == 2
        umap = local_abs(local_text(item{2}, sprintf('Subject %d UMAP', kk)));
    end
    pairs{kk} = {mprage, umap};
end
end

function text = local_json_list(values)
text = '';
for kk = 1:numel(values)
    if kk > 1
        text = [text ', ']; %#ok<AGROW>
    end
    text = [text '"' strrep(strrep(values{kk}, char(92), [char(92) char(92)]), '"', ...
        [char(92) '"']) '"']; %#ok<AGROW>
end
end

function out = local_invoke(req)
if exist(req.launcher, 'file') ~= 2
    error('pseudo_CT:FrontendLauncher', 'The launcher is unavailable: %s', req.launcher);
end
config_path = '';
if ~isempty(req.subjects) && ~strcmp(req.cli_action, 'authenticate')
    % Subject pairs travel to the launcher as a subjects file, the same input as
    % 'Subject', FILE; the launcher parses and checks it.
    config_path = [tempname '.txt'];
    local_write_text(config_path, local_subjects_text(req.subjects));
    cleanup_config = onCleanup(@() local_delete(config_path)); %#ok<NASGU>
elseif numel(req.mprage) > 1 && ~strcmp(req.cli_action, 'authenticate')
    config_path = [tempname '.json'];
    local_write_text(config_path, local_config_text(req));
    cleanup_config = onCleanup(@() local_delete(config_path)); %#ok<NASGU>
end
result_file = tempname;
err_file = tempname;
cleanup_files = onCleanup(@() local_delete({result_file; err_file})); %#ok<NASGU>
argv = local_argv(req, config_path, result_file);
% stdout is not redirected: the progress text goes to the MATLAB Command Window (live
% display to be confirmed on the installed MATLAB).
% stderr is kept in a temp file for error parsing only. The record is read from
% result_file (written atomically by bin/pseudoct --result-file).
command = [local_clean_prefix() local_sh(req.launcher) local_join_sh(argv) ...
    ' 2>' local_sh(err_file)];
status = system(command);
stderr_text = local_read(err_file);
script = fullfile(fileparts(mfilename('fullpath')), 'pseudo_CT_result_fields.py');
[parse_status, parse_text] = system([local_clean_prefix() ...
    local_sh(local_python()) ' -I -B ' local_sh(script) ' ' local_sh(result_file)]);
fields = struct();
if parse_status == 0
    fields = local_key_values(parse_text);
end
out = struct('ok', false, 'exit_code', status, 'action', req.action, ...
    'profile', req.profile, 'record_found', isfield(fields, 'outcome'), ...
    'outcome', 'no_result', 'submission_status', '', 'authentication_status', '', ...
    'dispatch_status', '', 'scientific_completion_status', '', 'backend', '', ...
    'error_code', '', 'error_message', '', 'job_ids', {{}}, ...
    'stderr', local_tail(stderr_text, 1000));
if out.record_found
    out.outcome = fields.outcome;
    out.submission_status = local_field(fields, 'submission_status');
    out.authentication_status = local_field(fields, 'authentication_status');
    out.dispatch_status = local_field(fields, 'dispatch_status');
    out.scientific_completion_status = local_field(fields, 'scientific_completion_status');
    out.backend = local_field(fields, 'backend');
    out.error_code = local_field(fields, 'error_code');
    % Lines of a multi-line message arrive joined by the unit separator (char 31).
    out.error_message = strrep(local_field(fields, 'error_message'), char(31), char(10));
    out.job_ids = local_split_words(local_field(fields, 'job_ids'));
end
out.ok = (status == 0) && out.record_found;
if status ~= 0 && isempty(out.error_message)
    out.error_message = sprintf('launcher exit status %d: %s', status, ...
        local_tail(stderr_text, 300));
end
end

function python = local_python()
%LOCAL_PYTHON Interpreter for frontend helper scripts, chosen like bin/pseudoct does. An
%   installed distribution (no src/ beside run_pseudo_CT.m) always uses its own private
%   runtime python/bin/python3, never a system Python; a missing runtime is an error. A
%   source checkout is development-only: PSEUDOCT_PYTHON, else python3.
root_dir = fileparts(fileparts(mfilename('fullpath')));
if ~local_is_installed(root_dir)
    python = strtrim(getenv('PSEUDOCT_PYTHON'));
    if isempty(python)
        python = 'python3';
    end
    return;
end
python = fullfile(root_dir, 'python', 'bin', 'python3');
if exist(python, 'file') ~= 2
    error('pseudo_CT:FrontendLauncher', ['This pseudoCT installation is incomplete: ' ...
        'python/bin/python3 is missing beside run_pseudo_CT.m. Reinstall the pseudoCT ' ...
        'distribution.']);
end
end

function releases = local_releases(launcher)
%LOCAL_RELEASES Installed release labels from 'bin/pseudoct --list-releases'.
%   Empty unless the launcher sits in an installed distribution (runtimes/).
releases = struct('label', {}, 'mcr_version', {}, 'default', {});
if isempty(launcher) || exist(launcher, 'file') ~= 2
    return;
end
root_dir = fileparts(fileparts(launcher));
if exist(fullfile(root_dir, 'runtimes'), 'dir') ~= 7
    return;
end
out_file = tempname;
cleanup_out = onCleanup(@() local_delete(out_file)); %#ok<NASGU>
[status, ~] = system([local_clean_prefix() local_sh(launcher) ' --list-releases >' ...
    local_sh(out_file) ' 2>/dev/null']);
if status ~= 0
    error('pseudo_CT:FrontendLauncher', 'The installed release list is unavailable.');
end
lines = regexp(local_read(out_file), char(10), 'split');
for kk = 1:numel(lines)
    if isempty(strtrim(lines{kk}))
        continue;
    end
    fields = regexp(lines{kk}, char(9), 'split');
    if numel(fields) ~= 3
        error('pseudo_CT:FrontendLauncher', 'The installed release list is malformed.');
    end
    releases(end + 1) = struct('label', strtrim(fields{1}), ...
        'mcr_version', strtrim(fields{2}), ...
        'default', strcmp(strtrim(fields{3}), 'default')); %#ok<AGROW>
end
end

function text = local_fingerprint(req)
% Action and credential handoff are excluded: the GUI validates first and
% creates the one-use handoff only for the submit call, which must still match.
parts = {['profile=' req.profile]; ...
    ['runtime=' req.runtime]; ['mcr_root=' req.mcr_root]; ...
    ['aliasing=' req.correct_aliasing]; ['recenter=' req.recenter]; ...
    ['cleanup=' req.cleanup]; ['artifact_root=' req.artifact_root]; ...
    ['group_account=' req.group_account]; ['host_key_file=' req.host_key_file]};
for kk = 1:numel(req.mprage)
    parts{end + 1, 1} = ['mprage=' req.mprage{kk} local_file_stamp(req.mprage{kk})]; %#ok<AGROW>
end
for kk = 1:numel(req.umap)
    parts{end + 1, 1} = ['umap=' req.umap{kk} local_file_stamp(req.umap{kk})]; %#ok<AGROW>
end
if ~isempty(req.subjects_file)
    parts{end + 1, 1} = ['subjects_file=' req.subjects_file ...
        local_file_stamp(req.subjects_file)];
end
for kk = 1:numel(req.subjects)
    parts{end + 1, 1} = sprintf('subject%d=%s%s|%s%s', kk, ...
        req.subjects{kk}{1}, local_file_stamp(req.subjects{kk}{1}), ...
        req.subjects{kk}{2}, local_file_stamp(req.subjects{kk}{2})); %#ok<AGROW>
end
text = local_join(parts, char(10));
end

function stamp = local_file_stamp(path_text)
if isempty(path_text)
    stamp = '';
    return;
end
info = dir(path_text);
if isempty(info)
    stamp = '|missing';
else
    stamp = sprintf('|%d|%.6f', info(1).bytes, info(1).datenum);
end
end

function text = local_text(value, label)
if ~ischar(value) || size(value, 1) ~= 1 || isempty(strtrim(value)) || ...
        any(value == char(0)) || any(value == char(10)) || any(value == char(13))
    error('pseudo_CT:FrontendUsage', '%s must be one non-empty line of text.', label);
end
text = strtrim(value);
end

function paths = local_path_list(value, label)
if isempty(value)
    paths = {};
elseif ischar(value)
    paths = {local_abs(local_text(value, label))};
elseif iscell(value)
    paths = cell(1, numel(value));
    for kk = 1:numel(value)
        paths{kk} = local_abs(local_text(value{kk}, label));
    end
else
    error('pseudo_CT:FrontendUsage', '%s must be a path or a cell of paths.', label);
end
end

function value = local_yes_no(value, label)
if isempty(value)
    value = '';
elseif islogical(value) || (isnumeric(value) && isscalar(value))
    if value
        value = 'yes';
    else
        value = 'no';
    end
elseif ischar(value) && any(strcmpi(value, {'yes'; 'no'}))
    value = lower(value);
else
    error('pseudo_CT:FrontendUsage', '%s must be yes/no or a logical.', label);
end
end

function path_text = local_abs(path_text)
if ~isempty(path_text) && path_text(1) ~= '/'
    path_text = fullfile(pwd, path_text);
end
end

function local_require_file(path_text, label)
if exist(path_text, 'file') ~= 2
    error('pseudo_CT:OrchestrationInput', '%s input is unavailable.', label);
end
end

function flag = local_is_secret_name(key)
secrets = {'password'; 'passwd'; 'username'; 'user'; 'secret'; 'token'; ...
    'passphrase'; 'credential'};
flag = false;
for kk = 1:numel(secrets)
    if ~isempty(strfind(key, secrets{kk})) %#ok<STREMP>
        flag = true;
        return;
    end
end
end

function text = local_clean_prefix()
%LOCAL_CLEAN_PREFIX Child environment without MATLAB's runtime or path variables.
text = 'env -u LD_LIBRARY_PATH -u LD_PRELOAD -u MATLABPATH -u XAPPLRESDIR ';
end

function quoted = local_sh(text)
q = char(39);
quoted = [q strrep(text, q, [q char(92) q q]) q];
end

function text = local_join_sh(argv)
text = '';
for kk = 1:numel(argv)
    text = [text ' ' local_sh(argv{kk})]; %#ok<AGROW>
end
end

function text = local_join(parts, separator)
text = '';
for kk = 1:numel(parts)
    if kk > 1
        text = [text separator]; %#ok<AGROW>
    end
    text = [text parts{kk}]; %#ok<AGROW>
end
end

function words = local_split_words(text)
words = {};
rest = strtrim(text);
while ~isempty(rest)
    [word, rest] = strtok(rest, ' ');
    words{end + 1} = word; %#ok<AGROW>
    rest = strtrim(rest);
end
end

function fields = local_key_values(text)
fields = struct();
lines = regexp(text, char(10), 'split');
for kk = 1:numel(lines)
    line = lines{kk};
    eq = find(line == '=', 1);
    if isempty(eq)
        continue;
    end
    name = line(1:eq - 1);
    if isvarname(name)
        fields.(name) = line(eq + 1:end);
    end
end
end

function value = local_field(fields, name)
value = '';
if isfield(fields, name)
    value = fields.(name);
end
end

function text = local_read(path_text)
text = '';
fid = fopen(path_text, 'r');
if fid < 0
    return;
end
text = fread(fid, '*char')';
fclose(fid);
end

function local_write_text(path_text, text)
fid = fopen(path_text, 'w');
if fid < 0
    error('pseudo_CT:FrontendUsage', 'Cannot write the launcher config file.');
end
fprintf(fid, '%s', text);
fclose(fid);
end

function local_delete(files)
if ischar(files)
    files = {files};
end
for kk = 1:numel(files)
    if exist(files{kk}, 'file') == 2
        delete(files{kk});
    end
end
end

function text = local_tail(text, count)
if length(text) > count
    text = text(end - count + 1:end);
end
end
