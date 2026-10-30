function status = pseudoct_headless_cli()
%PSEUDOCT_HEADLESS_CLI Run one request from the standalone shell launcher.
%   Uses only the request/result paths supplied by the fixed R2010b bootstrap.

status = 70;
request_path = getenv('PSEUDOCT_REQUEST_MAT');
result_path = getenv('PSEUDOCT_RESULT_MAT');
if isempty(request_path) || isempty(result_path)
    return;
end

try
    % Keep request contents out of MATLAB's terminal output. This is a fixed
    % expression; paths are passed as data, never interpolated into code.
    captured_output = evalc( ...
        'dispatch_result = pseudo_CT_headless(request_path, result_path);'); %#ok<NASGU>
    clear captured_output

    if exist(result_path, 'file') ~= 2 || ~local_mat_v5(result_path)
        return;
    end
    variables = whos('-file', result_path);
    if length(variables) ~= 1 || ~strcmp(variables(1).name, 'result') || ...
            ~strcmp(variables(1).class, 'struct') || ...
            ~isequal(variables(1).size, [1 1])
        return;
    end
    loaded = load(result_path, 'result');
    if ~isfield(loaded, 'result') || ...
            ~local_result_record(loaded.result) || ...
            ~isequal(dispatch_result, loaded.result)
        clear loaded
        return;
    end
    result = loaded.result;
    clear loaded

    expected = local_expected_request(request_path);
    if expected.has_binding
        if ~strcmp(result.invocation_id, expected.invocation_id) || ...
                ~strcmp(result.profile, expected.profile)
            return;
        end
        if expected.has_action
            % A handled, well-formed request must produce the strict bound
            % result contract. Invalid actions still produce a useful generic
            % request-failure result, but cannot pass this validator.
            try
                validated = pseudo_CT_validate_headless_result(result_path, ...
                    expected.invocation_id, expected.profile);
            catch
                return;
            end
            if ~isequal(validated, result)
                return;
            end
        end
    end
    status = local_status_code(result);
catch
    % Do not expose MATLAB exception text or paths; the shell maps this to 70.
    status = 70;
end
end

function valid = local_result_record(result)
required = {'schema'; 'invocation_id'; 'action'; 'profile'; 'status'; ...
    'error_code'; 'error_message'; 'authentication_status'; ...
    'submission_status'; 'backend'; 'group_account'; 'job_ids'; ...
    'scientific_completion'; 'dispatch_status'; 'resolved_job'; ...
    'evidence'; 'diagnostics'};
valid = isstruct(result) && numel(result) == 1;
if ~valid
    return;
end
names = sort(fieldnames(result));
valid = length(names) == length(required) && ...
    all(strcmp(names, sort(required))) && ...
    ischar(result.schema) && strcmp(result.schema, ...
    'pseudoCT.headless-result/v2') && ischar(result.status) && ...
    ischar(result.error_code);
end

function expected = local_expected_request(path_name)
expected = struct('has_binding', false, 'has_action', false, ...
    'invocation_id', '', 'profile', '');
try
    if ~local_mat_v5(path_name)
        return;
    end
    variables = whos('-file', path_name);
    if length(variables) ~= 1 || ~strcmp(variables(1).name, 'request') || ...
            ~strcmp(variables(1).class, 'struct') || ...
            ~isequal(variables(1).size, [1 1])
        return;
    end
    loaded = load(path_name, 'request');
    if ~isfield(loaded, 'request') || ~isstruct(loaded.request) || ...
            numel(loaded.request) ~= 1
        clear loaded
        return;
    end
    request = loaded.request;
    clear loaded
    if isfield(request, 'invocation_id') && ...
            ischar(request.invocation_id) && size(request.invocation_id, 1) == 1 && ...
            ~isempty(regexp(request.invocation_id, ...
            '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$', ...
            'once')) && isfield(request, 'profile') && ...
            ischar(request.profile) && size(request.profile, 1) == 1 && ...
            any(strcmp(request.profile, {'mlsc-current'; ...
            'mlsc-mprage-only'; 'mlsc-legacy'; 'launchpad-legacy'}))
        expected.has_binding = true;
        expected.invocation_id = request.invocation_id;
        expected.profile = request.profile;
    end
    expected.has_action = expected.has_binding && isfield(request, 'action') && ...
        ischar(request.action) && size(request.action, 1) == 1 && ...
            any(strcmp(request.action, {'validate'; 'submit'}));
catch
    expected = struct('has_binding', false, 'has_action', false, ...
        'invocation_id', '', 'profile', '');
end
end

function status = local_status_code(result)
if any(strcmp(result.status, {'ready'; 'submitted'}))
    status = 0;
elseif any(strcmp(result.error_code, ...
        {'INVALID_REQUEST'; 'PROFILE_NOT_ALLOWED'}))
    status = 2;
elseif strcmp(result.status, 'failed')
    status = 3;
else
    status = 70;
end
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
