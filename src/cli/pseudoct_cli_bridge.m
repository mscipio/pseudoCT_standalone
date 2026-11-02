function status = pseudoct_cli_bridge(mode)
%PSEUDOCT_CLI_BRIDGE Prepare and verify CLI requests using MATLAB v5 MAT.
%   All request/result paths and non-secret values arrive through environment
%   variables or a line-oriented input file. Passwords are never arguments,
%   environment values, JSON, request MAT files, or output records.
%   Minimum supported MATLAB: R2010b.

status = 70;
try
    if strcmp(mode, 'prepare_validate')
        spec = local_read_input(getenv('PSEUDOCT_CLI_INPUT'));
        request = local_request(spec, 'validate');
        local_save_request(getenv('PSEUDOCT_CLI_REQUEST'), request);
    elseif strcmp(mode, 'prepare_submit')
        spec = local_read_input(getenv('PSEUDOCT_CLI_INPUT'));
        validation = local_load_result(getenv('PSEUDOCT_CLI_RESULT'), ...
            spec.invocation_id, spec.profile, 'validate');
        if ~strcmp(validation.status, 'ready') || ...
                isempty(fieldnames(validation.resolved_job))
            error('pseudo_CT:CLIValidation', ...
                'A ready validated job is required before submit.');
        end
        request = local_request(spec, 'submit');
        request.resolved_job = validation.resolved_job;
        request.group_account = spec.group_account;
        request.credential_handoff = getenv('PSEUDOCT_CLI_HANDOFF');
        request.host_key_file = spec.host_key_file;
        local_save_request(getenv('PSEUDOCT_CLI_REQUEST'), request);
    elseif strcmp(mode, 'verify_result')
        result = local_load_result(getenv('PSEUDOCT_CLI_RESULT'), ...
            getenv('PSEUDOCT_CLI_INVOCATION'), ...
            getenv('PSEUDOCT_CLI_PROFILE'), ...
            getenv('PSEUDOCT_CLI_ACTION'));
        local_write_summary(getenv('PSEUDOCT_CLI_SUMMARY'), result);
    elseif strcmp(mode, 'store_credentials')
        local_store_credentials(getenv('PSEUDOCT_CLI_SECRET_FILE'), ...
            getenv('PSEUDOCT_CLI_HANDOFF_OUTPUT'));
    else
        error('pseudo_CT:CLIAction', 'Unknown CLI support operation.');
    end
    status = 0;
catch ME
    fprintf(2, 'pseudoct: MATLAB CLI support failed (%s).\n', ME.identifier);
end
end

function spec = local_read_input(path_name)
fid = fopen(path_name, 'r');
if fid == -1
    error('pseudo_CT:CLIInput', 'CLI input data is unavailable.');
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
spec.profile = local_read_line(fid);
spec.invocation_id = local_read_line(fid);
count_text = local_read_line(fid);
spec.has_umaps = strcmp(local_read_line(fid), '1');
count = str2double(count_text);
if ~isfinite(count) || count < 1 || count ~= floor(count) || count > 10000
    error('pseudo_CT:CLIInput', 'CLI subject count is invalid.');
end
spec.subjects = cell(count, 1);
for ii = 1:count
    spec.subjects{ii} = local_read_line(fid);
    if isempty(spec.subjects{ii})
        error('pseudo_CT:CLIInput', 'An MPRAGE path is empty.');
    end
end
spec.umap_files = {};
if spec.has_umaps
    spec.umap_files = cell(count, 1);
    for ii = 1:count
        spec.umap_files{ii} = local_read_line(fid);
        if isempty(spec.umap_files{ii})
            error('pseudo_CT:CLIInput', 'A UMAP path is empty.');
        end
    end
end
spec.correct_aliasing = local_read_option(fid);
spec.recenter_before_normalization = local_read_option(fid);
spec.cleanup_on_success = local_read_option(fid);
spec.current_artifact_root = local_read_line(fid);
spec.group_account = local_read_line(fid);
spec.host_key_file = local_read_line(fid);
if ~feof(fid)
    extra = fgetl(fid);
    if ischar(extra)
        error('pseudo_CT:CLIInput', 'CLI input data has unexpected fields.');
    end
end
if ~local_allowed_profile(spec.profile) || ...
        isempty(regexp(spec.invocation_id, ...
        '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$', ...
        'once'))
    error('pseudo_CT:CLIInput', 'Profile or invocation ID is invalid.');
end
if spec.has_umaps && local_mprage_only(spec.profile)
    error('pseudo_CT:CLIInput', 'MPRAGE-only profiles do not accept UMAP files.');
end
end

function line = local_read_line(fid)
line = fgetl(fid);
if ~ischar(line) || any(line == char(0))
    error('pseudo_CT:CLIInput', 'CLI input data is incomplete or invalid.');
end
end

function value = local_read_option(fid)
text = local_read_line(fid);
if isempty(text)
    value = [];
elseif strcmp(text, '0')
    value = false;
elseif strcmp(text, '1')
    value = true;
else
    error('pseudo_CT:CLIInput', 'A processing option is invalid.');
end
end

function request = local_request(spec, action)
request = struct();
request.schema = 'pseudoCT.headless-request/v2';
request.invocation_id = spec.invocation_id;
request.action = action;
request.profile = spec.profile;
if strcmp(action, 'validate')
    request.subjects = spec.subjects;
    if spec.has_umaps
        request.umap_files = spec.umap_files;
    else
        request.umap_files = {};
    end
    request.output_config = struct('layout', 'profile-default');
    request.options = struct();
    if ~isempty(spec.correct_aliasing)
        request.options.correct_aliasing = spec.correct_aliasing;
    end
    if ~isempty(spec.recenter_before_normalization)
        request.options.recenter_before_normalization = ...
            spec.recenter_before_normalization;
    end
    if ~isempty(spec.cleanup_on_success)
        request.options.cleanup_on_success = spec.cleanup_on_success;
    end
    request.resolved_job = struct();
    request.current_artifact_root = spec.current_artifact_root;
else
    request.subjects = {};
    request.umap_files = {};
    request.output_config = struct();
    request.options = struct();
    request.resolved_job = struct();
    request.current_artifact_root = '';
end
request.group_account = '';
request.credential_handoff = '';
request.host_key_file = '';
end

function local_save_request(path_name, request)
if isempty(path_name) || size(path_name, 1) ~= 1
    error('pseudo_CT:CLIRequestPath', 'Request MAT path is invalid.');
end
save(path_name, 'request', '-v6');
if ~local_mat_v5(path_name)
    error('pseudo_CT:CLIRequestMAT', 'MATLAB did not write a v5 request file.');
end
variables = whos('-file', path_name);
if length(variables) ~= 1 || ~strcmp(variables(1).name, 'request') || ...
        ~strcmp(variables(1).class, 'struct') || ...
        ~isequal(variables(1).size, [1 1])
    error('pseudo_CT:CLIRequestMAT', 'Serialized request MAT schema is invalid.');
end
loaded = load(path_name, 'request');
required = {'schema'; 'invocation_id'; 'action'; 'profile'; 'subjects'; ...
    'umap_files'; 'output_config'; 'options'; 'resolved_job'; ...
    'group_account'; 'credential_handoff'; 'host_key_file'; ...
    'current_artifact_root'};
if ~isfield(loaded, 'request') || ~isstruct(loaded.request) || ...
        numel(loaded.request) ~= 1 || ...
        ~isequal(sort(fieldnames(loaded.request)), sort(required)) || ...
        ~strcmp(loaded.request.schema, 'pseudoCT.headless-request/v2') || ...
        ~strcmp(loaded.request.action, request.action) || ...
        ~strcmp(loaded.request.invocation_id, request.invocation_id) || ...
        ~strcmp(loaded.request.profile, request.profile)
    clear loaded
    error('pseudo_CT:CLIRequestMAT', ...
        'Serialized request MAT failed its v2 field/binding check.');
end
clear loaded
end

function result = local_load_result(path_name, invocation_id, profile, action)
if isempty(path_name) || exist(path_name, 'file') ~= 2 || ...
        ~local_mat_v5(path_name)
    error('pseudo_CT:CLIResultMAT', 'Result MAT is unavailable or not v5.');
end
result = pseudo_CT_validate_headless_result(path_name, invocation_id, profile);
if ~strcmp(result.action, action)
    error('pseudo_CT:CLIResultBinding', 'Result action does not match the CLI operation.');
end
end

function local_write_summary(path_name, result)
if isempty(path_name)
    error('pseudo_CT:CLISummaryPath', 'Result summary path is invalid.');
end
fid = fopen(path_name, 'w');
if fid == -1
    error('pseudo_CT:CLISummaryPath', 'Result summary cannot be written.');
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
values = {result.status; result.error_code; result.authentication_status; ...
    result.submission_status; result.backend; result.scientific_completion; ...
    result.dispatch_status; local_job_ids(result.job_ids); result.action; ...
    result.error_message};
for ii = 1:length(values)
    if isempty(values{ii})
        values{ii} = '-';
    end
    fprintf(fid, '%s\n', values{ii});
end
end

function text = local_job_ids(values)
text = '';
for ii = 1:numel(values)
    if ii > 1
        text = [text ' ']; %#ok<AGROW>
    end
    text = [text num2str(values(ii), 15)]; %#ok<AGROW>
end
end

function local_store_credentials(secret_path, handoff_output)
if isempty(secret_path) || isempty(handoff_output) || ...
        isempty(regexp(secret_path, ...
        '^/dev/shm/pseudoct-cli-credentials-[A-Za-z0-9_.-]+/login$', 'once'))
    error('pseudo_CT:CLISecretPath', 'Private credential input is unavailable.');
end
fid = fopen(secret_path, 'r');
if fid == -1
    error('pseudo_CT:CLISecretPath', 'Private credential input is unavailable.');
end
username = fgetl(fid);
password = fgetl(fid);
extra = fgetl(fid);
fclose(fid);
if ~ischar(username) || isempty(username) || ~ischar(password) || ...
        isempty(password) || ischar(extra)
    clear username password
    error('pseudo_CT:CLISecretShape', 'Private credential input is invalid.');
end
% Remove the terminal staging file before writing the approved one-use MAT.
local_erase_secret(secret_path);
handoff = pseudo_CT_credentials('store', username, password);
clear username password
if ~ischar(handoff) || isempty(handoff)
    error('pseudo_CT:CLICredentialStore', 'Credential handoff was not created.');
end
fid = fopen(handoff_output, 'w');
if fid == -1
    local_erase_secret(handoff);
    error('pseudo_CT:CLICredentialStore', 'Credential handoff reference cannot be written.');
end
write_ok = false;
try
    bytes_written = fprintf(fid, '%s\n', handoff);
    close_status = fclose(fid);
    fid = -1;
    write_ok = bytes_written == length(handoff) + 1 && close_status == 0;
catch
    if fid ~= -1
        fclose(fid);
        fid = -1;
    end
end
if ~write_ok
    local_erase_secret(handoff);
    clear handoff
    error('pseudo_CT:CLICredentialStore', 'Credential handoff reference cannot be written.');
end
clear handoff
end

function local_erase_secret(path_name)
try
    info = dir(path_name);
    if ~isempty(info)
        fid = fopen(path_name, 'r+b');
        if fid ~= -1
            zeros_block = zeros(1, min(4096, max(1, info(1).bytes)), 'uint8');
            remaining = info(1).bytes;
            while remaining > 0
                count = min(remaining, length(zeros_block));
                fwrite(fid, zeros_block(1:count), 'uint8');
                remaining = remaining - count;
            end
            fclose(fid);
        end
        delete(path_name);
    end
    parent = fileparts(path_name);
    if exist(parent, 'dir') == 7
        rmdir(parent);
    end
catch
end
end

function valid = local_allowed_profile(profile)
valid = ischar(profile) && any(strcmp(profile, ...
    {'local-current'; 'local-legacy'; 'local-mprage-only'; ...
    'mlsc-current'; 'mlsc-legacy'; 'mlsc-mprage-only'; 'launchpad-legacy'}));
end

function valid = local_mprage_only(profile)
valid = any(strcmp(profile, ...
    {'local-mprage-only'; 'mlsc-mprage-only'}));
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
