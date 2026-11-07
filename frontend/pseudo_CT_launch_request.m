function out = pseudo_CT_launch_request(action, varargin)
%PSEUDO_CT_LAUNCH_REQUEST Shared parameter-to-launcher translation for the frontend.
%   REQUEST = PSEUDO_CT_LAUNCH_REQUEST('parse', ARGS, ROOT_DIR) validates the
%   Name, Value cell ARGS of run_pseudo_CT and returns a normalized request.
%   ROOT_DIR is the folder that holds run_pseudo_CT.m and bin/pseudoct. Input
%   files are checked before the launcher is resolved.
%
%   RESULT = PSEUDO_CT_LAUNCH_REQUEST('invoke', REQUEST) runs the compiled
%   launcher (bin/pseudoct run validate|run ... --format jsonl). Every argument
%   is POSIX single-quoted; no user text is interpolated unquoted. The child
%   process environment drops MATLAB's library and path variables so the
%   launcher selects its own MATLAB Runtime. RESULT is a struct with ok,
%   exit_code, action, profile, outcome, submission_status,
%   authentication_status, dispatch_status, scientific_completion_status,
%   backend, error_code, error_message, job_ids (cell), stderr and
%   record_found.
%
%   ARGV = PSEUDO_CT_LAUNCH_REQUEST('argv', REQUEST, CONFIG_PATH) returns the
%   launcher argument cell (without the launcher path). CONFIG_PATH is used
%   only for multi-subject requests.
%   JSON = PSEUDO_CT_LAUNCH_REQUEST('config', REQUEST) returns the multi-subject
%   --config text (mprage and umap arrays).
%   KEY = PSEUDO_CT_LAUNCH_REQUEST('fingerprint', REQUEST) returns the text that
%   identifies the inputs and options of one validation. Compare it with the
%   fingerprint stored at validation time to detect changed inputs.
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
        out = local_argv(varargin{1}, '');
        if nargin > 2
            out = local_argv(varargin{1}, varargin{2});
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
    otherwise
        error('pseudo_CT:FrontendUsage', 'Unknown frontend request action.');
end
end

function req = local_parse(args, root_dir)
if ~iscell(args) || mod(numel(args), 2) ~= 0
    error('pseudo_CT:FrontendUsage', 'Arguments must be Name, Value pairs.');
end
req = struct('profile', '', 'mprage', {{}}, 'umap', {{}}, 'action', 'validate', ...
    'cli_action', 'validate', 'runtime', '', 'mcr_root', '', 'launcher', '', ...
    'correct_aliasing', '', 'recenter', '', 'cleanup', '', 'artifact_root', '', ...
    'group_account', '', 'host_key_file', '', 'credential_handoff', '');
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
        case 'action'
            req.action = lower(local_text(value, 'Action'));
            if ~any(strcmp(req.action, {'validate'; 'submit'}))
                error('pseudo_CT:FrontendUsage', 'Action must be validate or submit.');
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
if isempty(req.profile) || isempty(req.mprage)
    error('pseudo_CT:FrontendUsage', 'Profile and MPRAGE are required.');
end
if ~any(strcmp(req.profile, {'local'; 'local-mprage-only'; 'mlsc'; 'mlsc-mprage-only'}))
    error('pseudo_CT:InvalidProfile', 'Unknown profile: %s', req.profile);
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
req.launcher = local_resolve_launcher(req.launcher, root_dir);
req.fingerprint = local_fingerprint(req);
end

function launcher = local_resolve_launcher(launcher, root_dir)
%LOCAL_RESOLVE_LAUNCHER Explicit argument, then PSEUDOCT_LAUNCHER, then the
%   installed bin/pseudoct beside run_pseudo_CT.m. A source checkout (no
%   runtimes/ folder) has no compiled launcher and must name one explicitly.
if isempty(launcher)
    env_value = strtrim(getenv('PSEUDOCT_LAUNCHER'));
    if ~isempty(env_value)
        launcher = local_abs(env_value);
    elseif exist(fullfile(root_dir, 'runtimes'), 'dir') == 7
        launcher = fullfile(root_dir, 'bin', 'pseudoct');
    else
        error('pseudo_CT:FrontendLauncher', ...
            ['No installed distribution beside run_pseudo_CT.m. Pass Launcher, ' ...
            'or set PSEUDOCT_LAUNCHER, to the compiled bin/pseudoct.']);
    end
end
if exist(launcher, 'file') ~= 2
    error('pseudo_CT:FrontendLauncher', 'The launcher is unavailable: %s', launcher);
end
end

function argv = local_argv(req, config_path)
argv = {'run'};
if ~isempty(req.runtime)
    argv = [argv, {'--mcr', req.runtime}];
end
if ~isempty(req.mcr_root)
    argv = [argv, {'--mcr-root', req.mcr_root}];
end
argv = [argv, {req.cli_action, '--profile', req.profile}];
if numel(req.mprage) > 1
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
argv = [argv, {'--format', 'jsonl'}];
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
if numel(req.mprage) > 1
    config_path = [tempname '.json'];
    local_write_text(config_path, local_config_text(req));
    cleanup_config = onCleanup(@() local_delete(config_path)); %#ok<NASGU>
end
out_file = tempname;
err_file = tempname;
cleanup_files = onCleanup(@() local_delete({out_file; err_file})); %#ok<NASGU>
argv = local_argv(req, config_path);
command = [local_clean_prefix() local_sh(req.launcher) local_join_sh(argv) ...
    ' >' local_sh(out_file) ' 2>' local_sh(err_file)];
[status, ~] = system(command);
stderr_text = local_read(err_file);
script = fullfile(fileparts(mfilename('fullpath')), 'pseudo_CT_result_fields.py');
[parse_status, parse_text] = system([local_clean_prefix() ...
    'python3 -I -B ' local_sh(script) ' ' local_sh(out_file)]);
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
    out.error_message = local_field(fields, 'error_message');
    out.job_ids = local_split_words(local_field(fields, 'job_ids'));
end
out.ok = (status == 0) && out.record_found;
if status ~= 0 && isempty(out.error_message)
    out.error_message = sprintf('launcher exit status %d: %s', status, ...
        local_tail(stderr_text, 300));
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
% creates the one-use handoff only for Submit, which must still match.
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
text = local_join(parts, char(10));
end

function stamp = local_file_stamp(path_text)
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
