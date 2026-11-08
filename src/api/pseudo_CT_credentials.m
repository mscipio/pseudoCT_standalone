function value = pseudo_CT_credentials(action, varargin)
%PSEUDO_CT_CREDENTIALS Store and consume a single-use private MAT credential.
%   PATH = PSEUDO_CT_CREDENTIALS('store', USERNAME, PASSWORD) writes one v5
%   credential MAT file under a private per-user directory on /dev/shm.
%   PATH = PSEUDO_CT_CREDENTIALS('store') prompts with the existing login
%   dialog before creating that file.
%   CREDENTIALS = PSEUDO_CT_CREDENTIALS('consume', PATH) validates the
%   owner-only tmpfs location and exact MAT shape, then overwrites and removes
%   the file and its directory before returning credentials. A consumed path
%   cannot be replayed. No credential value is displayed or returned in an
%   error. Minimum supported MATLAB: R2010b.

value = [];
if nargin < 1 || ~ischar(action)
    error('pseudo_CT:CredentialAction', ...
        'Credential operation is invalid.');
end
if strcmp(action, 'store')
    if nargin == 1
        [password, username] = pseudo_CT_password_entry_dialog( ...
            'enterUserName', true, 'ValidatePassword', true, ...
            'PasswordLengthMax', 50, ...
            'WindowName', 'Create single-use credential MAT file');
        if isequal(password, -1) || isempty(username)
            clear username password
            return;
        end
    elseif nargin == 3
        username = varargin{1};
        password = varargin{2};
    else
        error('pseudo_CT:CredentialShape', ...
            'Credential values have an invalid shape.');
    end
    value = local_store(username, password);
    clear username password
elseif strcmp(action, 'consume')
    if nargin ~= 2
        error('pseudo_CT:CredentialPath', ...
            'A single-use credential MAT path is required.');
    end
    value = local_consume(varargin{1});
else
    error('pseudo_CT:CredentialAction', ...
        'Credential operation is invalid.');
end
end

function path_name = local_store(username, password)
path_name = '';
if ~local_text(username) || ~local_text(password)
    error('pseudo_CT:CredentialShape', ...
        'Credential values have an invalid shape.');
end
local_require_tmpfs();
candidate = tempname('/dev/shm');
[~, suffix] = fileparts(candidate);
if isempty(regexp(suffix, '^[A-Za-z0-9_.-]+$', 'once'))
    error('pseudo_CT:CredentialStoreFailed', ...
        'Secure credential storage could not be established.');
end
private_dir = fullfile('/dev/shm', ['pseudo_CT_credentials_' suffix]);
credential_path = fullfile(private_dir, 'credentials.mat');
if ~local_safe_path(credential_path)
    error('pseudo_CT:CredentialStoreFailed', ...
        'Secure credential storage could not be established.');
end

credential = struct('username', username, 'password', password);
created = false;
store_state = containers.Map();
store_state('keep') = false;
store_state('created') = false;
store_guard = onCleanup(@() local_store_cleanup(credential_path, store_state)); %#ok<NASGU>
try
    [status, ~] = system(['mkdir -m 700 -- ' local_quote(private_dir)]);
    if status ~= 0
        error('pseudo_CT:CredentialStoreFailed', 'Secure storage failed.');
    end
    created = true;
    store_state('created') = true;
    local_require_mode(private_dir, '700', 'directory');
    local_require_absent(credential_path);
    [status, ~] = system(['umask 077; set -C; : > ' local_quote(credential_path)]);
    if status ~= 0
        error('pseudo_CT:CredentialStoreFailed', 'Secure storage failed.');
    end
    save(credential_path, 'credential', '-v6');
    local_require_mode(credential_path, '*', 'regular file');
    [status, ~] = system(['chmod 600 -- ' local_quote(credential_path)]);
    if status ~= 0
        error('pseudo_CT:CredentialStoreFailed', 'Secure storage failed.');
    end
    local_require_mode(credential_path, '600', 'regular file');
    path_name = credential_path;
    store_state('keep') = true;
catch
    clear credential username password
    if created
        local_best_effort_erase(credential_path);
    end
    error('pseudo_CT:CredentialStoreFailed', ...
        'Secure credential storage could not be established.');
end
clear credential username password
end

function local_store_cleanup(path_name, state)
if state('created') && ~state('keep')
    local_best_effort_erase(path_name);
end
end

function credentials = local_consume(path_name)
credentials = struct('username', '', 'password', '');
if ~local_safe_path(path_name)
    error('pseudo_CT:CredentialPath', ...
        'Single-use credential MAT file is invalid or already consumed.');
end
private_dir = fileparts(path_name);
consume_guard = onCleanup(@() local_consume_cleanup(path_name)); %#ok<NASGU>
loaded = struct();
valid = false;
erase_ok = false;
try
    local_require_tmpfs();
    local_require_mode(private_dir, '700', 'directory');
    local_require_mode(path_name, '600', 'regular file');
    info = dir(path_name);
    if isempty(info) || info(1).bytes < 1 || info(1).bytes > 65536
        error('pseudo_CT:CredentialShape', 'Invalid credential MAT file.');
    end
    if ~local_mat_v5(path_name)
        error('pseudo_CT:CredentialShape', 'Invalid credential MAT file.');
    end
    variables = whos('-file', path_name);
    if length(variables) ~= 1 || ~strcmp(variables(1).name, 'credential') || ...
            ~strcmp(variables(1).class, 'struct') || ...
            ~isequal(variables(1).size, [1 1])
        error('pseudo_CT:CredentialShape', 'Invalid credential MAT file.');
    end
    loaded = load(path_name, 'credential');
    if isfield(loaded, 'credential') && isstruct(loaded.credential) && ...
            numel(loaded.credential) == 1
        names = sort(fieldnames(loaded.credential));
        if length(names) == 2 && strcmp(names{1}, 'password') && ...
                strcmp(names{2}, 'username') && ...
                local_text(loaded.credential.username) && ...
                local_text(loaded.credential.password)
            valid = true;
        end
    end
catch
    valid = false;
end

% Erase while the private directory and file permissions are still verified.
% Failure to overwrite, unlink, or remove the private directory is fatal.
try
    erase_ok = local_erase(path_name);
catch
    erase_ok = false;
end
if ~erase_ok
    clear loaded credentials
    error('pseudo_CT:CredentialEraseFailed', ...
        'Single-use credential storage could not be securely removed.');
end
if ~valid
    clear loaded credentials
    error('pseudo_CT:CredentialShape', ...
        'Single-use credential MAT file has an invalid shape.');
end
credentials = loaded.credential;
clear loaded
end

function local_consume_cleanup(path_name)
if exist(fileparts(path_name), 'dir') == 7
    local_best_effort_erase(path_name);
end
end

function ok = local_erase(path_name)
ok = false;
if ~local_safe_path(path_name)
    return;
end
private_dir = fileparts(path_name);
link_status = local_symlink_status(private_dir);
if link_status == 0
    % Remove only the named directory link; never traverse its target.
    [unlink_status, ~] = system(['rm -- ' local_quote(private_dir)]);
    if unlink_status ~= 0 || ~local_path_absent(private_dir)
        return;
    end
    ok = local_path_absent(path_name);
    return;
elseif link_status ~= 1
    return;
end
try
    local_require_tmpfs();
    local_require_mode(private_dir, '700', 'directory');
    link_status = local_symlink_status(path_name);
    if link_status == 0
        % Unlink the validated pathname itself; rm does not follow a symlink.
        [unlink_status, ~] = system(['rm -- ' local_quote(path_name)]);
        if unlink_status ~= 0 || ~local_path_absent(path_name)
            return;
        end
    elseif link_status ~= 1
        return;
    elseif exist(path_name, 'file') == 2
        % Check the exact file type immediately before fopen so a symlink
        % target is never overwritten.
        local_require_mode(path_name, '*', 'regular file');
    end
catch
    return;
end
if exist(path_name, 'file') == 2
    fid = fopen(path_name, 'r+b');
    if fid == -1
        return;
    end
    write_ok = true;
    if fseek(fid, 0, 'eof') ~= 0
        write_ok = false;
        byte_count = 0;
    else
        byte_count = ftell(fid);
        if isempty(byte_count) || byte_count < 0 || ...
                fseek(fid, 0, 'bof') ~= 0
            write_ok = false;
            byte_count = 0;
        end
    end
    zeros_block = zeros(1, min(4096, max(1, byte_count)), 'uint8');
    remaining = byte_count;
    while write_ok && remaining > 0
        count = min(length(zeros_block), remaining);
        if fwrite(fid, zeros_block(1:count), 'uint8') ~= count
            write_ok = false;
        end
        remaining = remaining - count;
    end
    close_status = fclose(fid);
    if ~write_ok || close_status ~= 0
        return;
    end
    delete(path_name);
    if ~local_path_absent(path_name)
        return;
    end
elseif exist(private_dir, 'dir') ~= 7
    return;
end
if exist(private_dir, 'dir') == 7
    local_require_mode(private_dir, '700', 'directory');
    [removed, ~] = rmdir(private_dir);
    if ~removed || ~local_path_absent(private_dir)
        return;
    end
end
ok = local_path_absent(path_name) && local_path_absent(private_dir);
end

function local_best_effort_erase(path_name)
try
    local_erase(path_name);
catch
end
end

function local_require_tmpfs()
[status, filesystem] = system('stat -f -c %T /dev/shm');
[access_status, ~] = system('test -d /dev/shm && test -w /dev/shm && test -x /dev/shm');
if status ~= 0 || access_status ~= 0 || ~strcmp(strtrim(filesystem), 'tmpfs')
    error('pseudo_CT:CredentialStorageUnavailable', ...
        'Private memory-backed credential storage is unavailable.');
end
end

function local_require_mode(path_name, expected_mode, expected_type)
if ~local_safe_target(path_name)
    error('pseudo_CT:CredentialPermissions', ...
        'Private credential permissions could not be established.');
end

[uid_status, uid_text] = system('id -u');
[stat_status, stat_text] = system(['stat -c ''%u %a %F'' -- ' ...
    local_quote(path_name)]);
if uid_status ~= 0 || stat_status ~= 0
    error('pseudo_CT:CredentialPermissions', ...
        'Private credential permissions could not be established.');
end
% GNU stat's %F is multiword (for example, "regular file"); capture the
% remainder as the type rather than splitting all output on whitespace.
parts = regexp(strtrim(stat_text), ...
    '^([0-9]+)\s+([0-7]+)\s+(.+)$', 'tokens', 'once');
if isempty(parts) || ~strcmp(parts{1}, strtrim(uid_text)) || ...
        (~strcmp(expected_mode, '*') && ~strcmp(parts{2}, expected_mode)) || ...
        ~strcmpi(parts{3}, expected_type)
    error('pseudo_CT:CredentialPermissions', ...
        'Private credential permissions could not be established.');
end
end

function local_require_absent(path_name)
if ~local_safe_path(path_name)
    error('pseudo_CT:CredentialPermissions', ...
        'Private credential permissions could not be established.');
end
[status, ~] = system(['if test -e ' local_quote(path_name) ...
    ' || test -L ' local_quote(path_name) '; then exit 1; fi']);
if status ~= 0
    error('pseudo_CT:CredentialPermissions', ...
        'Private credential permissions could not be established.');
end
end

function safe = local_safe_target(path_name)
safe = (local_safe_path(path_name) || ...
    (ischar(path_name) && size(path_name, 1) == 1 && ...
    ~isempty(regexp(path_name, ...
    '^/dev/shm/pseudo_CT_credentials_[A-Za-z0-9_.-]+$', 'once'))));
if safe
    safe = local_symlink_status(path_name) == 1;
end
end

function status = local_symlink_status(path_name)
[status, ~] = system(['test -L ' local_quote(path_name)]);
end

function absent = local_path_absent(path_name)
[status, ~] = system(['if test -e ' local_quote(path_name) ...
    ' || test -L ' local_quote(path_name) '; then exit 1; else exit 0; fi']);
absent = status == 0;
end

function safe = local_safe_path(path_name)
safe = ischar(path_name) && size(path_name, 1) == 1 && ...
    ~isempty(path_name) && ~any(path_name == char(0)) && ...
    ~isempty(regexp(path_name, ...
    '^/dev/shm/pseudo_CT_credentials_[A-Za-z0-9_.-]+/credentials\.mat$', ...
    'once'));
end

function valid = local_text(value)
valid = ischar(value) && size(value, 1) == 1 && ~isempty(value) && ...
    ~any(value == char(0));
end

function valid = local_mat_v5(path_name)
valid = false;
fid = fopen(path_name, 'rb');
if fid == -1
    return;
end
header = fread(fid, 19, 'uint8');
fclose(fid);
valid = length(header) == 19 && ...
    strcmp(char(header(:)'), 'MATLAB 5.0 MAT-file');
end

function quoted = local_quote(value)
quoted = ['''' value ''''];
end
