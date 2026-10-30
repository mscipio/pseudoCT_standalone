function session = mlsc_initialize_backend_session(config, username, password, ...
        host_key_provider, requested_account, allow_account_dialog)
%MLSC_INITIALIZE_BACKEND_SESSION Shared MLSC auth/account initialization.
%   Used only at submit by GUI, script, and headless paths. Credentials remain in
%   the transport closure only. The returned session retains that transport
%   for submission and monitoring; callers must clean it up when finished.
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
catch %#ok<CTCH>
    session.authentication_status = 'failed';
    session.preflight_status = 'failed';
    session.error_code = 'AUTHENTICATION_FAILED';
    session.error_message = local_error_message(session.error_code);
    return;
end
session.transport = transport;

try
    accepted = feval(transport.verify);
catch %#ok<CTCH>
    accepted = false;
end
if ~islogical(accepted) || ~isscalar(accepted) || ~accepted
    session.authentication_status = 'failed';
    session.preflight_status = 'failed';
    session.error_code = 'AUTHENTICATION_FAILED';
    session.error_message = local_error_message(session.error_code);
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
