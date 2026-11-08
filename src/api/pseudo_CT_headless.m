function result = pseudo_CT_headless(request_path, result_path)
%PSEUDO_CT_HEADLESS Run one v2 headless request and write its result MAT file.
%   RESULT = PSEUDO_CT_HEADLESS(REQUEST_PATH, RESULT_PATH)
%   REQUEST_PATH is a v2 request MAT file (schema pseudoCT.headless-request/v2).
%   RESULT is the v2 result struct (schema pseudoCT.headless-result/v2), which is
%   also saved to RESULT_PATH as MAT-file version 6, variable 'result'.
%   The action is 'validate' or 'submit'. VALIDATE is local-only. SUBMIT accepts a
%   previously resolved job: remote profiles consume a secure, single-use
%   credential handoff here, and local profiles submit without authentication.
%   On failure, a pseudoct-headless-diagnostics.txt file is written beside
%   RESULT_PATH, and RESULT carries status 'failed' with a fixed error_code.
%   Side effects: reads REQUEST_PATH, writes RESULT_PATH and, on failure, the
%   diagnostics file; runs the requested validate or submit action.
%   Errors: pseudo_CT:HeadlessPaths when a path argument is missing or invalid.
%   Minimum supported MATLAB: R2010b.

result = local_empty_result();
credentials = [];
request = struct();
if nargin ~= 2 || ~local_plain_path(request_path) || ...
        ~local_plain_path(result_path)
    error('pseudo_CT:HeadlessPaths', ...
        'A request MAT path and result MAT path are required.');
end
api_dir = fileparts(mfilename('fullpath'));
root_dir = fileparts(fileparts(api_dir));
runtime_dirs = {'api'; 'cli'; 'gui'; 'orchestration'; 'backends'; ...
    'config'; 'io'; 'qc'};
for ii = 1:length(runtime_dirs)
    path_here = fullfile(root_dir, 'src', runtime_dirs{ii});
    if exist(path_here, 'dir') == 7
        addpath(genpath(path_here), '-begin');
    end
end
try
    request = local_load_request(request_path);
    result = local_bind_result(request, result);
    if isfield(request, 'action') && ischar(request.action) && ...
            strcmp(request.action, 'submit') && ...
            ~(isfield(request, 'profile') && ...
            local_is_local_profile(request.profile)) && ...
            isfield(request, 'credential_handoff') && ...
            ischar(request.credential_handoff) && ...
            ~isempty(request.credential_handoff)
        credentials = pseudo_CT_credentials('consume', ...
            request.credential_handoff);
    end
    local_validate_request(request);
    if strcmp(request.action, 'submit')
        result.resolved_job = request.resolved_job;
    end
    result.invocation_id = request.invocation_id;
    result.action = request.action;
    result.profile = request.profile;
    if strcmp(request.action, 'validate')
        result = local_validate(request, result);
    else
        result = local_submit(request, result, credentials);
    end
catch ME
    diag = local_exception_report(ME);
    for kk = 1:length(diag)
        % One preformatted %s argument per line: in the compiled runtime a
        % literal before %s moves the value to the next line, which the launcher
        % would drop (it forwards only lines starting with pseudoct-headless:).
        fprintf(2, '%s\n', ['pseudoct-headless: ' diag{kk}]);
    end
    try
        diag_file = fopen(fullfile(fileparts(result_path), ...
            'pseudoct-headless-diagnostics.txt'), 'w');
        if diag_file ~= -1
            for kk = 1:length(diag)
                fprintf(diag_file, '%s\n', diag{kk});
            end
            fclose(diag_file);
        end
    catch
    end

    clear credentials
    result.status = 'failed';
    result.error_code = local_error_code(ME.identifier, result.action);
    result.error_message = local_error_message(result.error_code);
    result.diagnostics = struct('code', result.error_code, ...
        'message', result.error_message);
    if isempty(result.action)
        result.action = 'unknown';
    end
end
result.schema = 'pseudoCT.headless-result/v2';
save(result_path, 'result', '-v6');
clear request credentials
end

function lines = local_exception_report(ME)
%LOCAL_EXCEPTION_REPORT Exception fields as text lines, safe in compiled mode.
%   Lengths are printed next to each field so an empty value is distinguishable
%   from a missing one; lasterr and getReport are fallbacks for the message.
text = @(value) strrep(char(value), char(10), ' | ');
lines = {sprintf('exception class=%s identifier_len=%d message_len=%d stack_frames=%d', ...
    class(ME), numel(ME.identifier), numel(ME.message), numel(ME.stack)), ...
    ['exception identifier=' text(ME.identifier)], ...
    ['exception message=' text(ME.message)], ...
    ['exception lasterr=' text(lasterr)]};
try
    lines{end + 1} = ['exception report=' text(getReport(ME, 'basic'))];
catch
end
for kk = 1:min(5, numel(ME.stack))
    lines{end + 1} = sprintf('exception at %s line=%d file_len=%d', ...
        text(ME.stack(kk).name), ME.stack(kk).line, numel(ME.stack(kk).file)); %#ok<AGROW>
end
end

function result = local_empty_result()
result = struct('schema', 'pseudoCT.headless-result/v2', ...
    'invocation_id', '', 'action', '', 'profile', '', 'status', 'failed', ...
    'error_code', 'INVALID_REQUEST', ...
    'error_message', 'The request could not be validated.', ...
    'authentication_status', 'not_attempted', ...
    'submission_status', 'not_attempted', 'backend', 'local', ...
    'group_account', '', 'job_ids', [], ...
    'scientific_completion', 'not_applicable', ...
    'dispatch_status', 'not_dispatched', 'resolved_job', struct(), ...
    'evidence', struct(), 'diagnostics', struct('code', '', 'message', ''));
end

function request = local_load_request(path_name)
if exist(path_name, 'file') ~= 2 || ~local_mat_v5(path_name)
    error('pseudo_CT:HeadlessRequest', 'Request MAT file is unavailable or invalid.');
end
variables = whos('-file', path_name);
if length(variables) ~= 1 || ~strcmp(variables(1).name, 'request') || ...
        ~strcmp(variables(1).class, 'struct') || ...
        ~isequal(variables(1).size, [1 1])
    error('pseudo_CT:HeadlessRequest', 'Request MAT schema is invalid.');
end
loaded = load(path_name, 'request');
if ~isfield(loaded, 'request')
    error('pseudo_CT:HeadlessRequest', 'Request MAT schema is invalid.');
end
request = loaded.request;
clear loaded
end

function local_validate_request(request)
required = {'schema'; 'invocation_id'; 'action'; 'profile'; 'subjects'; ...
    'umap_files'; 'output_config'; 'options'; 'resolved_job'; ...
    'group_account'; 'credential_handoff'; 'host_key_file'; ...
    'current_artifact_root'};
if ~isstruct(request) || numel(request) ~= 1 || ...
        ~isequal(sort(fieldnames(request)), sort(required))
    error('pseudo_CT:HeadlessRequest', 'Request MAT schema is invalid.');
end
if ~local_plain_text(request.schema) || ...
        ~strcmp(request.schema, 'pseudoCT.headless-request/v2') || ...
        ~local_uuid(request.invocation_id) || ...
        ~local_enum(request.action, {'validate'; 'submit'}) || ...
        ~local_allowed_profile(request.profile)
    error('pseudo_CT:HeadlessRequest', 'Request MAT schema is invalid.');
end
local_optional_text(request.group_account, 'group_account');
local_optional_text(request.credential_handoff, 'credential_handoff');
local_optional_text(request.host_key_file, 'host_key_file');
local_optional_text(request.current_artifact_root, 'current_artifact_root');
% The artifact-root override is development-only: MLSC profiles only (same rule as the
% CLI and the frontend). Local profiles reject it with the shared identifier.
if ~isempty(request.current_artifact_root) && local_is_local_profile(request.profile)
    error('run_pseudo_CT:InvalidMlscCurrentOverride', ['current_artifact_root is a ' ...
        'development-only override accepted only for the mlsc and mlsc-mprage-only ' ...
        'profiles; a local profile is incompatible.']);
end
if ~isstruct(request.output_config) || numel(request.output_config) ~= 1 || ...
        ~isstruct(request.options) || numel(request.options) ~= 1
    error('pseudo_CT:HeadlessRequest', 'Request output/options fields are invalid.');
end
if strcmp(request.action, 'validate')
    if ~isempty(request.credential_handoff) || ~isempty(request.host_key_file) || ...
        ~isempty(request.group_account) || ...
        ~isstruct(request.resolved_job) || numel(request.resolved_job) ~= 1 || ...
        ~isempty(fieldnames(request.resolved_job))
        error('pseudo_CT:HeadlessRequest', ...
            'Validate requests cannot contain submit-only fields.');
    end
    if ~ischar(request.subjects) && ~iscell(request.subjects)
        error('pseudo_CT:HeadlessRequest', 'Validate subjects must be paths.');
    end
    if ~isempty(request.umap_files) && ~ischar(request.umap_files) && ...
            ~iscell(request.umap_files)
        error('pseudo_CT:HeadlessRequest', 'UMAP inputs must be paths.');
    end
    local_options(request.options);
else
    if ~isempty(request.subjects) || ~isempty(request.umap_files) || ...
            ~isempty(fieldnames(request.options)) || ...
            ~isempty(fieldnames(request.output_config)) || ...
            ~isempty(request.current_artifact_root) || ...
            ~isstruct(request.resolved_job) || numel(request.resolved_job) ~= 1
        error('pseudo_CT:HeadlessRequest', ...
            'Submit requests require one previously validated resolved job.');
    end
    local_resolved_job(request.resolved_job);
    if ~strcmp(request.resolved_job.profile, request.profile) || ...
            ~strcmp(request.resolved_job.invocation_id, request.invocation_id)
        error('pseudo_CT:HeadlessRequest', ...
            'Submit binding does not match the resolved job.');
    end
    if local_is_local_profile(request.profile)
        if ~isempty(request.credential_handoff) || ...
                ~isempty(request.group_account) || ~isempty(request.host_key_file)
            error('pseudo_CT:HeadlessRequest', ...
                'Local submit requests cannot contain authentication or scheduler fields.');
        end
    elseif isempty(request.credential_handoff)
        error('pseudo_CT:HeadlessRequest', ...
            'Remote submit requests require a one-time credential handoff.');
    end
end
end

function result = local_validate(request, result)
validation_request = struct('profile', request.profile, ...
    'output_config', request.output_config, ...
    'invocation_id', request.invocation_id);
if ~isempty(request.subjects)
    validation_request.subjects = request.subjects;
end
if ~isempty(request.umap_files)
    validation_request.umap_files = request.umap_files;
end
if ~isempty(request.current_artifact_root)
    validation_request.current_artifact_root = request.current_artifact_root;
end
if isfield(request.options, 'correct_aliasing') && ...
        ~isempty(request.options.correct_aliasing)
    validation_request.correct_aliasing = request.options.correct_aliasing;
end
if isfield(request.options, 'recenter_before_normalization') && ...
        ~isempty(request.options.recenter_before_normalization)
    validation_request.recenter_before_normalization = ...
        request.options.recenter_before_normalization;
end
if isfield(request.options, 'cleanup_on_success') && ...
        ~isempty(request.options.cleanup_on_success)
    validation_request.cleanup_on_success = ...
        request.options.cleanup_on_success;
end
validated = pseudo_CT_orchestrate('validate', validation_request);
result.status = 'ready';
result.error_code = '';
result.error_message = '';
result.authentication_status = 'not_attempted';
result.submission_status = 'not_attempted';
result.backend = local_backend(request.profile);
result.group_account = '';
result.job_ids = [];
result.scientific_completion = 'not_applicable';
result.dispatch_status = 'not_dispatched';
result.resolved_job = validated.resolved_job;
result.evidence = validated.resolved_job.validation_evidence;
result.diagnostics = struct('code', '', 'message', '');
end

function result = local_submit(request, result, credentials)
if local_is_local_profile(request.profile)
    api_request = struct('resolved_job', request.resolved_job);
else
    if ~isstruct(credentials) || numel(credentials) ~= 1 || ...
            ~isfield(credentials, 'username') || ~isfield(credentials, 'password')
        error('pseudo_CT:HeadlessRequest', ...
            'A single-use credential handoff is required.');
    end
    provider = local_host_key_provider(request.host_key_file);
    api_request = struct('resolved_job', request.resolved_job, ...
        'credentials', credentials, 'group_account', request.group_account, ...
        'host_key_provider', provider);
end
dispatch = pseudo_CT_orchestrate('submit', api_request);
result.status = 'submitted';
if isfield(dispatch, 'error_code') && ~isempty(dispatch.error_code)
    result.status = 'failed';
    result.error_code = dispatch.error_code;
    result.error_message = dispatch.error_message;
elseif local_is_local_profile(request.profile) && ...
        isfield(dispatch, 'scientific_completion') && ...
        ~strcmp(dispatch.scientific_completion, 'completed')
    % Local execution is synchronous. A returned dispatcher is not success
    % unless the authoritative completion record confirms completion.
    result.status = 'failed';
    result.error_code = 'SUBMIT_FAILED';
    result.error_message = local_error_message(result.error_code);
else
    result.error_code = '';
    result.error_message = '';
end
result.authentication_status = dispatch.authentication_status;
result.submission_status = dispatch.submission_status;
result.backend = dispatch.backend;
result.group_account = dispatch.group_account;
result.job_ids = dispatch.job_ids;
result.scientific_completion = dispatch.scientific_completion;
result.dispatch_status = dispatch.dispatch_status;
result.resolved_job = dispatch.resolved_job;
result.evidence = struct('validation', dispatch.resolved_job.validation_evidence, ...
    'warnings', dispatch.warnings);
result.diagnostics = struct('code', result.error_code, ...
    'message', result.error_message);
clear credentials provider api_request
end

function local_options(options)
allowed = {'correct_aliasing'; 'recenter_before_normalization'; ...
    'cleanup_on_success'};
names = fieldnames(options);
for ii = 1:length(names)
    if ~any(strcmp(names{ii}, allowed))
        error('pseudo_CT:HeadlessRequest', 'An unsupported processing option was supplied.');
    end
end
for ii = 1:length(allowed)
    if isfield(options, allowed{ii})
        value = options.(allowed{ii});
        if ~isempty(value) && ((~isnumeric(value) && ~islogical(value)) || ...
                ~isscalar(value) || ~isreal(value) || ...
                ~ismember(double(value), [0 1]))
            error('pseudo_CT:HeadlessRequest', 'A processing option is invalid.');
        end
    end
end
end

function local_resolved_job(job)
required = {'schema'; 'profile'; 'invocation_id'; 'subjects'; 'options'; ...
    'output_config'; 'artifact_identity'; 'current_artifact_root'; ...
    'validation_evidence'};
if ~isequal(sort(fieldnames(job)), sort(required)) || ...
        ~local_plain_text(job.schema) || ...
        ~strcmp(job.schema, 'pseudoCT.resolved-job/v1') || ...
        ~local_allowed_profile(job.profile) || ~local_uuid(job.invocation_id) || ...
        ~isstruct(job.subjects) || isempty(job.subjects) || ...
        ~isstruct(job.options) || ...
        ~isstruct(job.output_config) || ~isstruct(job.artifact_identity) || ...
        ~isstruct(job.validation_evidence) || ~local_safe_serializable(job)
    error('pseudo_CT:HeadlessRequest', 'Resolved job schema is invalid.');
end
subject_fields = {'mprage_fn'; 'umap_fn'; 'correct_aliasing'; ...
    'recenter_before_normalization'; 'io_policy'; 'processing_dir'; ...
    'temp_dir'; 'save_dir'; 'mprage_identity'; 'umap_identity'; ...
    'umap_resolution'};
for ii = 1:length(job.subjects)
    if ~isequal(sort(fieldnames(job.subjects(ii))), sort(subject_fields))
        error('pseudo_CT:HeadlessRequest', ...
            'Resolved subject schema is invalid.');
    end
end
names = fieldnames(job);
for ii = 1:length(names)
    if any(strcmpi(names{ii}, {'username'; 'password'; 'credentials'; ...
            'transport'; 'session'; 'token'; 'secret'}))
        error('pseudo_CT:HeadlessRequest', ...
            'Resolved job cannot contain credentials or sessions.');
    end
end
end

function valid = local_safe_serializable(value)
valid = true;
if isstruct(value)
    forbidden = {'username'; 'password'; 'credentials'; 'credential'; ...
        'transport'; 'session'; 'token'; 'secret'};
    names = fieldnames(value);
    for ii = 1:length(names)
        name = lower(names{ii});
        if any(strcmp(name, forbidden)) || ...
                ~isempty(strfind(name, 'credential')) || ...
                ~local_safe_serializable({value.(names{ii})})
            valid = false;
            return;
        end
    end
elseif iscell(value)
    for ii = 1:numel(value)
        if ~local_safe_serializable(value{ii})
            valid = false;
            return;
        end
    end
elseif ~(ischar(value) || isnumeric(value) || islogical(value))
    valid = false;
end
end

function result = local_bind_result(request, result)
if isstruct(request) && numel(request) == 1
    if isfield(request, 'invocation_id') && local_uuid(request.invocation_id)
        result.invocation_id = request.invocation_id;
    end
    if isfield(request, 'action') && local_enum(request.action, {'validate'; 'submit'})
        result.action = request.action;
    end
    if isfield(request, 'profile') && local_allowed_profile(request.profile)
        result.profile = request.profile;
        result.backend = local_backend(request.profile);
    end
end
end

function provider = local_host_key_provider(path_name)
provider = [];
if isempty(path_name)
    return;
end
fid = fopen(path_name, 'r');
if fid == -1
    error('pseudo_CT:HeadlessHostKey', 'Strict MLSC host-key material is unavailable.');
end
provider = fscanf(fid, '%c');
close_status = fclose(fid);
if close_status ~= 0 || isempty(provider)
    provider = [];
    error('pseudo_CT:HeadlessHostKey', 'Strict MLSC host-key material is unavailable.');
end
end

function code = local_error_code(identifier, operation)
%LOCAL_ERROR_CODE Named failures keep their mapping. Unclassified failures are
%   scoped by the bound operation: only submit reports SUBMIT_FAILED, while
%   validation (and any failure before the operation is bound) reports
%   VALIDATION_FAILED, so validation never claims a submission was attempted.
code = 'VALIDATION_FAILED';
if strcmp(operation, 'submit')
    code = 'SUBMIT_FAILED';
end
if strcmp(identifier, 'pseudo_CT:HeadlessRequest') || ...
        strcmp(identifier, 'pseudo_CT:CredentialShape') || ...
        strcmp(identifier, 'pseudo_CT:CredentialPath')
    code = 'INVALID_REQUEST';
elseif strcmp(identifier, 'pseudo_CT:InvalidProfile') || ...
        strcmp(identifier, 'pseudo_CT:HeadlessProfile')
    code = 'PROFILE_NOT_ALLOWED';
elseif strcmp(identifier, 'pseudo_CT:StaleResolvedJob')
    code = 'STALE_RESOLVED_JOB';
elseif strcmp(identifier, 'pseudo_CT:MLSCTransportRejected')
    code = 'AUTHENTICATION_FAILED';
elseif strcmp(identifier, 'pseudo_CT:MLSCNoAccounts')
    code = 'NO_ACCOUNTS';
elseif strcmp(identifier, 'pseudo_CT:HeadlessHostKey')
    code = 'HOST_KEY_UNAVAILABLE';
elseif strcmp(identifier, 'pseudo_CT:CredentialEraseFailed')
    code = 'CREDENTIAL_ERASE_FAILED';
elseif strncmp(identifier, 'pseudo_CT:Credential', length('pseudo_CT:Credential'))
    code = 'CREDENTIAL_STORAGE_FAILED';
end
end

function message = local_error_message(code)
switch code
    case 'INVALID_REQUEST'
        message = 'The request or one-time credential handoff was invalid or consumed.';
    case 'PROFILE_NOT_ALLOWED'
        message = 'The requested profile is not enabled for this interface.';
    case 'VALIDATION_FAILED'
        message = 'Local validation failed; no authentication, submission, or dispatch was attempted.';
    case 'STALE_RESOLVED_JOB'
        message = 'Inputs or artifacts changed; validate again before submit.';
    case 'AUTHENTICATION_FAILED'
        message = 'Remote authentication failed; no submission was attempted.';
    case 'NO_ACCOUNTS'
        message = 'Authentication succeeded but no MLSC group account was available.';
    case 'HOST_KEY_UNAVAILABLE'
        message = 'Strict MLSC host-key material is unavailable.';
    case 'CREDENTIAL_ERASE_FAILED'
        message = 'Credential storage could not be removed; authentication stopped.';
    case 'CREDENTIAL_STORAGE_FAILED'
        message = 'Secure single-use credential storage is unavailable.';
    otherwise
        message = 'The requested operation failed; consult non-secret diagnostics.';
end
end

function backend = local_backend(profile)
if any(strcmp(profile, {'mlsc'; 'mlsc-mprage-only'}))
    backend = 'mlsc';
else
    backend = 'local';
end
end

function local_optional_text(value, label)
if ~ischar(value) || (~isempty(value) && ...
        (size(value, 1) ~= 1 || any(value == char(0))))
    error('pseudo_CT:HeadlessRequest', '%s must be empty or single-row text.', label);
end
end

function valid = local_plain_path(value)
valid = ischar(value) && size(value, 1) == 1 && ...
    ~isempty(value) && ~any(value == char(0));
end

function valid = local_plain_text(value)
valid = ischar(value) && (isempty(value) || size(value, 1) == 1) && ...
    ~any(value == char(0));
end

function valid = local_uuid(value)
valid = local_plain_text(value) && ~isempty(regexp(value, ...
    '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$', ...
    'once'));
end

function valid = local_allowed_profile(value)
valid = local_plain_text(value) && any(strcmp(value, ...
    {'mlsc'; 'mlsc-mprage-only'; ...
    'local'; 'local-mprage-only'}));
end

function valid = local_is_local_profile(value)
valid = ischar(value) && size(value, 1) == 1 && any(strcmp(value, ...
    {'local'; 'local-mprage-only'}));
end

function valid = local_enum(value, choices)
valid = local_plain_text(value) && any(strcmp(value, choices));
end

function valid = local_mat_v5(path_name)
valid = false;
fid = fopen(path_name, 'rb');
if fid == -1
    return;
end
header = fread(fid, 19, 'uint8');
fclose(fid);
valid = length(header) == 19 && strcmp(char(header(:)'), 'MATLAB 5.0 MAT-file');
end
