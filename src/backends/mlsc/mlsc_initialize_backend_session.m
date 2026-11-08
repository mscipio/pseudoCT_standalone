function session = mlsc_initialize_backend_session(config, username, password, ...
        host_key_provider, requested_account, allow_account_dialog)
%MLSC_INITIALIZE_BACKEND_SESSION Authenticate to MLSC and prepare one submit session.
%   SESSION = MLSC_INITIALIZE_BACKEND_SESSION(CONFIG, USERNAME, PASSWORD,
%   HOST_KEY_PROVIDER, REQUESTED_ACCOUNT, ALLOW_ACCOUNT_DIALOG)
%   Called only at submit, by the frontend and by pseudo_CT_run_lifecycle.
%   CONFIG must be an 'mlsc' profile struct. USERNAME and PASSWORD are text.
%   HOST_KEY_PROVIDER is optional ([] selects the password path; see
%   mlsc_credentials_transport). REQUESTED_ACCOUNT is optional (''): the Slurm
%   account to use. When it is empty, the first account reported by MLSC is
%   used. ALLOW_ACCOUNT_DIALOG is optional (false). It is validated but not used:
%   account selection always runs without a dialog.
%   SESSION is a struct with transport (the callback struct from
%   mlsc_credentials_transport), authentication_status, account_status,
%   preflight_status, accounts (cell), selected_account, status ('ready' or
%   'failed'), submission_status, error_code and error_message. Failure sets
%   error_code to AUTHENTICATION_FAILED, ACCOUNT_QUERY_FAILED, NO_ACCOUNTS or
%   INVALID_GROUP_ACCOUNT, with a fixed error_message. On failure the transport
%   is closed and session.transport is []. Credentials are never returned.
%   Side effects: opens the MLSC connection and queries the account list. On
%   success the caller owns session.transport and must call its cleanup handle
%   when finished.
%   Errors: pseudo_CT:MLSCSessionRequest for an invalid request.
%   Minimum supported MATLAB: R2010b.

if nargin < 4
    host_key_provider = [];
end
if nargin < 5 || isempty(requested_account)
    requested_account = '';
end
if nargin < 6
    allow_account_dialog = false;
end
if ~isstruct(config) || numel(config) ~= 1 || ...
        ~isfield(config, 'mode') || ~strcmp(config.mode, 'mlsc') || ...
        ~local_credential_text(username) || ~local_credential_text(password) || ...
        ~ischar(requested_account) || (~isempty(requested_account) && ...
        size(requested_account, 1) ~= 1) || ...
        ~islogical(allow_account_dialog) || ~isscalar(allow_account_dialog)
    error('pseudo_CT:MLSCSessionRequest', ...
        'MLSC session initialization request is invalid.');
end

session = struct('transport', [], 'authentication_status', 'not_attempted', ...
    'account_status', 'not_attempted', 'preflight_status', 'not_attempted', ...
    'accounts', {{}}, 'selected_account', '', 'status', 'failed', ...
    'submission_status', 'not_attempted', 'error_code', '', ...
    'error_message', '');
try
    transport = mlsc_credentials_transport(config, username, password, ...
        host_key_provider);
catch ME
    session.authentication_status = 'failed';
    session.preflight_status = 'failed';
    session.error_code = 'AUTHENTICATION_FAILED';
    session.error_message = [local_error_message(session.error_code) ' ' ...
        local_transport_detail(ME, config, username, password)];
    return;
end
session.transport = transport;

verification_error = '';
try
    accepted = feval(transport.verify);
catch ME
    accepted = false;
    verification_error = local_transport_detail( ...
        ME, config, username, password);
end
if ~islogical(accepted) || ~isscalar(accepted) || ~accepted
    session.authentication_status = 'failed';
    session.preflight_status = 'failed';
    session.error_code = 'AUTHENTICATION_FAILED';
    session.error_message = local_error_message(session.error_code);
    if ~isempty(verification_error)
        session.error_message = [session.error_message ' ' verification_error];
    end
    local_close_transport(session.transport);
    session.transport = [];
    return;
end
session.authentication_status = 'authenticated';

try
    response = feval(transport.query_accounts);
    session.accounts = mlsc_parse_slurm_accounts(response);
catch %#ok<CTCH>
    session.account_status = 'unavailable';
    session.preflight_status = 'failed';
    session.error_code = 'ACCOUNT_QUERY_FAILED';
    session.error_message = local_error_message(session.error_code);
    local_close_transport(session.transport);
    session.transport = [];
    return;
end
if isempty(session.accounts)
    session.account_status = 'unavailable';
    session.preflight_status = 'failed';
    session.error_code = 'NO_ACCOUNTS';
    session.error_message = local_error_message(session.error_code);
    local_close_transport(session.transport);
    session.transport = [];
    return;
end

requested_account = strtrim(requested_account);
if isempty(requested_account)
    requested_account = session.accounts{1};
end
try
    session.selected_account = mlsc_select_account(session.accounts, ...
        requested_account, false);
catch ME
    session.preflight_status = 'failed';
    if strcmp(ME.identifier, 'pseudo_CT:MLSCAccountNotAvailable')
        session.account_status = 'invalid_group_account';
        session.error_code = 'INVALID_GROUP_ACCOUNT';
    else
        session.account_status = 'unavailable';
        session.error_code = 'ACCOUNT_QUERY_FAILED';
    end
    session.error_message = local_error_message(session.error_code);
    local_close_transport(session.transport);
    session.transport = [];
    return;
end
if isempty(session.selected_account)
    session.account_status = 'selection_required';
    session.preflight_status = 'failed';
    session.error_code = 'INVALID_GROUP_ACCOUNT';
    session.account_status = 'invalid_group_account';
    session.error_message = local_error_message(session.error_code);
    local_close_transport(session.transport);
    session.transport = [];
    return;
end
session.account_status = 'selected';
session.preflight_status = 'ready';
session.status = 'ready';
end

function detail = local_transport_detail(ME, config, username, password)
detail = ME.message;
if ischar(password) && ~isempty(password)
    detail = strrep(detail, password, '<redacted>');
end
if ischar(username) && ~isempty(username)
    detail = strrep(detail, username, '<user>');
end
if isstruct(config) && isfield(config, 'mlsc') && ...
        isstruct(config.mlsc) && isfield(config.mlsc, 'host') && ...
        ischar(config.mlsc.host) && ~isempty(config.mlsc.host)
    detail = strrep(detail, config.mlsc.host, '<host>');
end
detail = strrep(detail, char(10), ' ');
detail = strrep(detail, char(13), ' ');
detail = ['Underlying SSH2 cause [' ME.identifier ']: ' detail];
end

function valid = local_credential_text(value)
valid = ischar(value) && size(value, 1) == 1 && ...
    ~isempty(value) && ~any(value == char(0));
end

function message = local_error_message(code)
switch code
    case 'AUTHENTICATION_FAILED'
        message = 'Remote authentication failed; no further action was attempted.';
    case 'NO_ACCOUNTS'
        message = 'Authentication succeeded but no MLSC account was available.';
    case 'INVALID_GROUP_ACCOUNT'
        message = 'The requested MLSC group account was not returned for this user.';
    case 'ACCOUNT_SELECTION_REQUIRED'
        message = 'Select one exact account returned by MLSC preflight.';
    case 'ACCOUNT_QUERY_FAILED'
        message = 'Authenticated MLSC account discovery failed.';
    otherwise
        message = 'MLSC session initialization failed.';
end
end

function local_close_transport(transport)
if isstruct(transport) && isfield(transport, 'cleanup') && ...
        isa(transport.cleanup, 'function_handle')
    try
        feval(transport.cleanup);
    catch %#ok<CTCH>
    end
end
end
