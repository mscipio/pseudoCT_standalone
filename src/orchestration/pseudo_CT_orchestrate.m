function value = pseudo_CT_orchestrate(operation, request)
%PSEUDO_CT_ORCHESTRATE Shared GUI and headless MATLAB orchestration API.
%   VALIDATE performs local-only checks and returns a serializable resolved
%   job. SUBMIT revalidates that job and dispatches it through the existing
%   lifecycle; authentication occurs only in this operation. RUN is a
%   scripting convenience that performs VALIDATE followed by SUBMIT.
%   Minimum supported MATLAB: R2010b.

if nargin ~= 2 || ~ischar(operation) || size(operation, 1) ~= 1 || ...
        ~isstruct(request) || numel(request) ~= 1
    error('pseudo_CT:OrchestrationRequest', ...
        'A supported orchestration operation and one request struct are required.');
end
operation = lower(strtrim(operation));
root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
runtime_dirs = {'api'; 'cli'; 'gui'; 'orchestration'; 'backends'; ...
    'config'; 'io'; 'qc'};
for ii = 1:length(runtime_dirs)
    path_here = fullfile(root_dir, 'src', runtime_dirs{ii});
    if exist(path_here, 'dir') == 7
        addpath(genpath(path_here), '-begin');
    end
end

switch operation
    case 'validate'
        value = local_validate(request, root_dir);
    case 'submit'
        value = local_submit(request, root_dir);
    case 'run'
        value = local_run(request, root_dir);
    otherwise
        error('pseudo_CT:OrchestrationAction', ...
            'Unknown pseudoCT orchestration operation.');
end
end

function report = local_validate(request, root_dir)
forbidden = {'username'; 'password'; 'credentials'; 'credential'; ...
    'credential_file'; 'credential_handoff'; 'group_account'; ...
    'host_key_file'; 'transport'; 'token'; 'secret'};
for ii = 1:length(forbidden)
    if isfield(request, forbidden{ii})
        error('pseudo_CT:OrchestrationRequest', ...
            'Validation does not accept credentials or transports.');
    end
end

profile_name = '';
if isfield(request, 'profile')
    profile_name = request.profile;
end
artifact_root = local_text_field(request, 'current_artifact_root', '');
if isfield(request, 'config')
    config = request.config;
    if ~isstruct(config) || numel(config) ~= 1
        error('pseudo_CT:InvalidProfile', ...
            'Validation requires one loaded profile config.');
    end
else
    if ~ischar(profile_name) || size(profile_name, 1) ~= 1 || ...
            isempty(strtrim(profile_name))
        error('pseudo_CT:InvalidProfile', ...
            'Validation requires a canonical profile key.');
    end
    config_root = fullfile(root_dir, 'src', 'config');
    config = pseudo_CT_load_profile(profile_name, config_root);
    config = pseudo_CT_apply_mlsc_current_overrides(config, profile_name, ...
        artifact_root);
end

local_validate_flag(request, 'correct_aliasing');
local_validate_flag(request, 'recenter_before_normalization');
local_validate_flag(request, 'cleanup_on_success');

subjects = local_subjects(request);
needs_dicom = false;
for ii = 1:length(subjects)
    if local_input_needs_dicom(subjects{ii})
        needs_dicom = true;
        break;
    end
end
% Validate uses only local paths and resources; it never authenticates,
% contacts a remote service, creates output directories, or runs science.
setup_pseudo_CT_paths(root_dir, config, 'validate', ...
    ~isempty(subjects), needs_dicom);
is_current_mlsc = false;
try
    is_current_mlsc = mlsc_current_validate('is_current', config);
catch %#ok<CTCH>
    is_current_mlsc = false;
end
if is_current_mlsc
    mlsc_current_validate('validate_for_execution', config);
elseif isfield(config, 'mode') && strcmp(config.mode, 'local') && ...
        isfield(config, 'implementation') && ...
        strcmp(config.implementation, 'current')
    % Local current-lineage profiles use the same immutable compiled artifact
    % contract as MLSC current, validated before input preparation or normalization.
    artifact_config = struct();
    artifact_config.implementation = 'current';
    artifact_config.current = config.current;
    mlsc_current_validate('validate_for_execution', artifact_config);
end

umap_supplied = isfield(request, 'umap_files') && ...
    ~isempty(request.umap_files);
require_explicit_umap = isfield(request, 'require_explicit_umap') && ...
    isequal(request.require_explicit_umap, true);
umap_files = cell(1, length(subjects));
if umap_supplied
    umap_files = request.umap_files;
    if ischar(umap_files)
        if size(umap_files, 1) == 1
            umap_files = {umap_files};
        else
            umap_files = cellstr(umap_files);
        end
    end
    if ~iscell(umap_files) || length(umap_files) ~= length(subjects)
        error('pseudo_CT:OrchestrationInput', ...
            'UMAP inputs must match the requested subject list positionally.');
    end
    for ii = 1:length(umap_files)
        if ~ischar(umap_files{ii}) || ...
                (~isempty(umap_files{ii}) && size(umap_files{ii}, 1) ~= 1) || ...
                any(umap_files{ii} == char(0))
            error('pseudo_CT:OrchestrationInput', ...
                'Each UMAP input must be an empty or single-row path.');
        end
    end
end
if strcmp(config.io_policy.reference, 'none') && umap_supplied && ...
        any(~cellfun('isempty', umap_files))
    error('pseudo_CT:OrchestrationInput', ...
        'This MPRAGE-only profile does not accept UMAP inputs.');
end
output_config = struct('layout', 'profile-default');
if isfield(request, 'output_config')
    output_config = request.output_config;
    if ~isstruct(output_config) || numel(output_config) ~= 1 || ...
            (~isempty(fieldnames(output_config)) && ...
            (~isfield(output_config, 'layout') || ...
            ~ischar(output_config.layout) || ...
            ~strcmp(output_config.layout, 'profile-default') || ...
            length(fieldnames(output_config)) ~= 1))
        error('pseudo_CT:OrchestrationRequest', ...
            'Only the profile-default output layout is supported.');
    end
end
output_config = struct('layout', 'profile-default');

aliasing = local_option(request, 'correct_aliasing', ...
    get_config_value(config, 'aliasing_default', 1));
recenter = local_option(request, 'recenter_before_normalization', ...
    get_config_value(config, 'recenter_before_normalization', false));
cleanup = local_option(request, 'cleanup_on_success', ...
    get_config_value(config, 'cleanup_on_success', true));
if ischar(recenter)
    recenter = local_yes_no(recenter);
end
options = struct('correct_aliasing', logical(aliasing), ...
    'recenter_before_normalization', logical(recenter), ...
    'cleanup_on_success', logical(cleanup));
jobs = struct('mprage_fn', {}, 'umap_fn', {}, 'correct_aliasing', {}, ...
    'recenter_before_normalization', {}, 'io_policy', {}, ...
    'processing_dir', {}, 'temp_dir', {}, 'save_dir', {}, ...
    'mprage_identity', {}, 'umap_identity', {}, 'umap_resolution', {});
for ii = 1:length(subjects)
    input_path = subjects{ii};
    local_require_readable_file(input_path, 'MPRAGE');
    reference_path = '';
    resolution = 'not_applicable';
    if strcmp(config.io_policy.reference, 'umap-required')
        if umap_supplied && ~isempty(umap_files{ii})
            reference_path = umap_files{ii};
            resolution = 'explicit';
        elseif require_explicit_umap
            error('pseudo_CT:OrchestrationInput', ...
                'A resolved submit job is missing its explicit UMAP reference.');
        else
            [~, reference_path] = pseudo_CT_discover_ute_umap(input_path);
            resolution = 'autodiscovered';
        end
        local_require_readable_file(reference_path, 'UMAP reference');
    elseif umap_supplied && ~isempty(umap_files{ii})
        error('pseudo_CT:OrchestrationInput', ...
            'This MPRAGE-only profile does not accept UMAP inputs.');
    end
    input_dir = fileparts(input_path);
    if isempty(input_dir)
        input_dir = pwd;
    end
    [processing_dir, temp_dir, save_dir] = ...
        pseudo_CT_resolve_output_dirs(input_dir);
    local_require_writable_target(processing_dir);
    local_require_writable_target(temp_dir);
    if strcmp(config.io_policy.output, 'nifti-and-dicom')
        local_require_writable_target(save_dir);
    end
    jobs(ii).mprage_fn = input_path;
    jobs(ii).umap_fn = reference_path;
    jobs(ii).correct_aliasing = options.correct_aliasing;
    jobs(ii).recenter_before_normalization = ...
        options.recenter_before_normalization;
    jobs(ii).io_policy = config.io_policy;
    jobs(ii).processing_dir = processing_dir;
    jobs(ii).temp_dir = temp_dir;
    jobs(ii).save_dir = save_dir;
    jobs(ii).mprage_identity = local_input_identity(input_path);
    jobs(ii).umap_identity = local_optional_input_identity(reference_path);
    jobs(ii).umap_resolution = resolution;
end

artifact_identity = local_artifact_identity(config, profile_name, root_dir);
invocation_id = local_text_field(request, 'invocation_id', '');
if ~isempty(invocation_id) && isempty(regexp(invocation_id, ...
        '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$', ...
        'once'))
    error('pseudo_CT:OrchestrationRequest', 'Invocation identifier is invalid.');
end
resolved_job = struct('schema', 'pseudoCT.resolved-job/v1', ...
    'profile', profile_name, 'invocation_id', invocation_id, ...
    'subjects', jobs, 'options', options, 'output_config', output_config, ...
    'artifact_identity', artifact_identity, ...
    'current_artifact_root', artifact_root, ...
    'validation_evidence', struct('local_only', true, ...
    'checks', {{'profile'; 'inputs'; 'output_directories'; ...
    'runtime_dependencies'; 'artifact_integrity'}}, ...
    'validated_at', datestr(now, 30)));
report = struct('schema', 'pseudoCT.validation/v2', 'ok', true, ...
    'profile', profile_name, 'subject_count', length(subjects), ...
    'authentication_status', 'not_attempted', ...
    'submission_status', 'not_attempted', 'resolved_job', resolved_job);
end

function report = local_submit(request, root_dir)
if ~isfield(request, 'resolved_job') || ~isstruct(request.resolved_job) || ...
        numel(request.resolved_job) ~= 1 || ...
        ~isfield(request.resolved_job, 'schema') || ...
        ~strcmp(request.resolved_job.schema, 'pseudoCT.resolved-job/v1') || ...
        ~isfield(request.resolved_job, 'subjects') || ...
        ~isfield(request.resolved_job, 'profile') || ...
        ~isfield(request.resolved_job, 'options') || ...
        ~isfield(request.resolved_job, 'artifact_identity')
    error('pseudo_CT:OrchestrationRequest', ...
        'Submit requires one resolved job returned by local validation.');
end
resolved = request.resolved_job;
if ~isstruct(resolved.subjects) || isempty(resolved.subjects) || ...
        ~ischar(resolved.profile) || ~isfield(resolved, 'invocation_id') || ...
        ~isfield(resolved, 'output_config') || ~isfield(resolved, 'current_artifact_root')
    error('pseudo_CT:OrchestrationRequest', 'Resolved job schema is invalid.');
end
subjects = {resolved.subjects.mprage_fn};
umaps = {resolved.subjects.umap_fn};
validation_request = struct('profile', resolved.profile, ...
    'subjects', {subjects}, 'umap_files', {umaps}, ...
    'output_config', resolved.output_config, ...
    'require_explicit_umap', true, ...
    'correct_aliasing', resolved.options.correct_aliasing, ...
    'recenter_before_normalization', ...
    resolved.options.recenter_before_normalization, ...
    'invocation_id', resolved.invocation_id);
if isfield(resolved.options, 'cleanup_on_success')
    validation_request.cleanup_on_success = ...
        resolved.options.cleanup_on_success;
end
if isfield(resolved, 'current_artifact_root')
    validation_request.current_artifact_root = resolved.current_artifact_root;
end
try
    fresh_report = local_validate(validation_request, root_dir);
catch ME
    error('pseudo_CT:StaleResolvedJob', ...
        'A resolved input, output, profile, or artifact is no longer valid; validate again (%s).', ...
        ME.identifier);
end
if ~local_same_resolved_job(resolved, fresh_report.resolved_job)
    error('pseudo_CT:StaleResolvedJob', ...
        'Resolved inputs, outputs, profile, or artifacts changed; validate again before submit.');
end

credentials = struct();
if isfield(request, 'credentials')
    credentials = request.credentials;
    if ~isstruct(credentials) || numel(credentials) ~= 1 || ...
            ~isfield(credentials, 'username') || ~isfield(credentials, 'password')
        error('pseudo_CT:OrchestrationRequest', 'Submit credential handoff is invalid.');
    end
end
group_account = local_text_field(request, 'group_account', '');
provider = [];
if isfield(request, 'host_key_provider')
    provider = request.host_key_provider;
end
args = {'profile', resolved.profile, 'subjects', subjects, ...
    'umap_files', umaps, 'resolved_jobs', resolved.subjects, ...
    'headless_mode', ~isempty(fieldnames(credentials)), ...
    'headless_credentials', credentials, 'group_account', group_account, ...
    'mlsc_host_key_provider', provider};
if isfield(resolved.options, 'cleanup_on_success')
    args = [args {'cleanup_on_success', ...
        resolved.options.cleanup_on_success}]; %#ok<AGROW>
end
if isfield(resolved, 'current_artifact_root') && ...
        ~isempty(resolved.current_artifact_root)
    args = [args {'mlsc_current_artifact_root', ...
        resolved.current_artifact_root}]; %#ok<AGROW>
end
report = pseudo_CT_run_lifecycle(args{:});
backend = 'local';
if any(strcmp(resolved.profile, ...
        {'mlsc-current'; 'mlsc-legacy'; 'mlsc-mprage-only'}))
    backend = 'mlsc';
elseif strcmp(resolved.profile, 'launchpad-legacy')
    backend = 'launchpad';
end
selected_group = '';
if isfield(report, 'selected_account')
    selected_group = report.selected_account;
end
report.schema = 'pseudoCT.submission/v1';
if ~isempty(report.error_code)
    report.dispatch_status = 'failed';
elseif strcmp(backend, 'local') && strcmp(report.run_status, 'returned')
    % Direct local execution has no scheduler submission status or ID; this
    % only records that the local execution path was entered and returned.
    report.dispatch_status = 'dispatched';
elseif strcmp(report.submission_status, 'not_attempted')
    report.dispatch_status = 'not_dispatched';
else
    report.dispatch_status = 'dispatched';
end
report.backend = backend;
report.group_account = selected_group;
report.scientific_completion = report.completion_status;
report.resolved_job = resolved;
end

function report = local_run(request, root_dir)
if ~isfield(request, 'arguments') || ~iscell(request.arguments)
    error('pseudo_CT:OrchestrationRequest', ...
        'A run request must contain named run arguments as a cell array.');
end
arguments = request.arguments;
if isempty(arguments)
    report = pseudo_CT_run_lifecycle();
    return;
end
options = struct();
for ii = 1:2:length(arguments)
    if ii == length(arguments) || ~ischar(arguments{ii})
        error('pseudo_CT:OrchestrationRequest', ...
            'Run arguments must be name/value pairs.');
    end
    options.(arguments{ii}) = arguments{ii + 1};
end
if ~isfield(options, 'profile') || ~isfield(options, 'subjects') || ...
        isempty(options.subjects) || (ischar(options.subjects) && ...
        strcmpi(strtrim(options.subjects), 'batch'))
    report = pseudo_CT_run_lifecycle(arguments{:});
    return;
end
validation_request = struct('profile', options.profile, ...
    'subjects', {options.subjects});
copy_names = {'umap_files'; 'correct_aliasing'; ...
    'recenter_before_normalization'; 'cleanup_on_success'; 'output_config'};
for ii = 1:length(copy_names)
    if isfield(options, copy_names{ii})
        validation_request.(copy_names{ii}) = options.(copy_names{ii});
    end
end
if isfield(options, 'mlsc_current_artifact_root')
    validation_request.current_artifact_root = ...
        options.mlsc_current_artifact_root;
end
validated = local_validate(validation_request, root_dir);
submit_request = struct('resolved_job', validated.resolved_job);
copy_names = {'group_account'; 'headless_credentials'; ...
    'mlsc_host_key_provider'};
for ii = 1:length(copy_names)
    if isfield(options, copy_names{ii})
        if strcmp(copy_names{ii}, 'headless_credentials')
            submit_request.credentials = options.(copy_names{ii});
        elseif strcmp(copy_names{ii}, 'mlsc_host_key_provider')
            submit_request.host_key_provider = options.(copy_names{ii});
        else
            submit_request.(copy_names{ii}) = options.(copy_names{ii});
        end
    end
end
report = local_submit(submit_request, root_dir);
end

function same = local_same_resolved_job(a, b)
same = strcmp(a.profile, b.profile) && ...
    isequal(a.invocation_id, b.invocation_id) && ...
    isequal(a.current_artifact_root, b.current_artifact_root) && ...
    local_same_options(a.options, b.options) && ...
    isequal(a.output_config, b.output_config) && ...
    isequal(a.artifact_identity, b.artifact_identity) && ...
    length(a.subjects) == length(b.subjects);
if ~same
    return;
end

fields = {'mprage_fn'; 'umap_fn'; 'correct_aliasing'; ...
    'recenter_before_normalization'; 'processing_dir'; 'temp_dir'; ...
    'save_dir'; 'mprage_identity'; 'umap_identity'; 'io_policy'};
for ii = 1:length(a.subjects)
    for jj = 1:length(fields)
        if ~isequal(a.subjects(ii).(fields{jj}), b.subjects(ii).(fields{jj}))
            same = false;
            return;
        end
    end
end
end

function same = local_same_options(a, b)
if isequal(a, b)
    same = true;
elseif isstruct(a) && numel(a) == 1 && isstruct(b) && numel(b) == 1 && ...
        ~isfield(a, 'cleanup_on_success') && ...
        isfield(b, 'cleanup_on_success')
    same = isequal(a, rmfield(b, 'cleanup_on_success'));
else
    same = false;
end
end

function values = local_subjects(request)
values = {};
if ~isfield(request, 'subjects') || isempty(request.subjects)
    return;
end

candidate = request.subjects;
if ischar(candidate)
    if size(candidate, 1) == 1
        candidate = {candidate};
    else
        candidate = cellstr(candidate);
    end
end
if ~iscell(candidate)
    error('pseudo_CT:OrchestrationInput', ...
        'Subject inputs must be a path or cell array of paths.');
end
for ii = 1:length(candidate)
    if ~ischar(candidate{ii}) || size(candidate{ii}, 1) ~= 1 || ...
            isempty(strtrim(candidate{ii})) || any(candidate{ii} == char(0))
        error('pseudo_CT:OrchestrationInput', ...
            'Each subject input must be a non-empty file path.');
    end
values{end + 1} = candidate{ii}; %#ok<AGROW>
end
end

function required = local_input_needs_dicom(path_name)
required = true;
if exist(path_name, 'dir') == 7
    return;
end
[~, ~, ext] = fileparts(path_name);
if strcmpi(ext, '.nii')
    required = false;
elseif strcmpi(ext, '.gz')
    inner_path = path_name(1:end - length(ext));
    [~, ~, inner_ext] = fileparts(inner_path);
    required = ~strcmpi(inner_ext, '.nii');
end
end

function local_validate_flag(request, name)
if ~isfield(request, name) || isempty(request.(name))
    return;
end
value = request.(name);
if (~isnumeric(value) && ~islogical(value)) || ~isscalar(value) || ...
        ~isreal(value) || ~ismember(double(value), [0 1])
    error('pseudo_CT:OrchestrationParameter', ...
        'Processing overrides must be scalar 0 or 1 values.');
end
end

function value = local_option(request, name, fallback)
value = fallback;
if isfield(request, name) && ~isempty(request.(name))
    value = request.(name);
end
if ischar(value)
    value = local_yes_no(value);
end
if (~isnumeric(value) && ~islogical(value)) || ~isscalar(value) || ...
        ~isreal(value) || ~ismember(double(value), [0 1])
    error('pseudo_CT:OrchestrationParameter', ...
        'Processing options must be scalar 0 or 1 values.');
end
end

function value = get_config_value(config, name, fallback)
value = fallback;
if isstruct(config) && isfield(config, name)
    value = config.(name);
end
end

function value = local_yes_no(value)
if ~ischar(value) || size(value, 1) ~= 1
    error('pseudo_CT:OrchestrationParameter', 'A profile option is invalid.');
end
normalized = lower(strtrim(value));
if any(strcmp(normalized, {'yes'; 'true'; 'on'; '1'}))
    value = true;
elseif any(strcmp(normalized, {'no'; 'false'; 'off'; '0'}))
    value = false;
else
    error('pseudo_CT:OrchestrationParameter', 'A profile option is invalid.');
end
end

function local_require_readable_file(path_name, label)
if ~ischar(path_name) || size(path_name, 1) ~= 1 || ...
        isempty(strtrim(path_name)) || any(path_name == char(0)) || ...
        exist(path_name, 'file') ~= 2
    error('pseudo_CT:OrchestrationInput', ...
        '%s input is unavailable.', label);
end
fid = fopen(path_name, 'r');
if fid == -1
    error('pseudo_CT:OrchestrationInput', ...
        '%s input is not readable.', label);
end
fclose(fid);
end

function identity = local_optional_input_identity(path_name)
if isempty(path_name)
    identity = struct('path', '', 'kind', '', 'bytes', 0, ...
        'datenum', 0, 'sha256', '', 'entries', {{}});
else
    identity = local_input_identity(path_name);
end
end

function identity = local_input_identity(path_name)
info = dir(path_name);
if isempty(info)
    error('pseudo_CT:OrchestrationInput', 'An input changed during validation.');
end
identity = struct('path', path_name, 'kind', 'file', 'bytes', info(1).bytes, ...
    'datenum', info(1).datenum, 'sha256', '', 'entries', {{}});
if isdir(path_name)
    identity.kind = 'directory';
    entries = dir(fullfile(path_name, '*'));
    names = {};
    for ii = 1:length(entries)
        if any(strcmp(entries(ii).name, {'.'; '..'}))
            continue;
        end
        names{end + 1} = sprintf('%s|%d|%.15g|%d', entries(ii).name, ...
            entries(ii).bytes, entries(ii).datenum, entries(ii).isdir); %#ok<AGROW>
    end
    identity.entries = names;
else
    identity.sha256 = local_file_sha256(path_name);
end
end

function identity = local_artifact_identity(config, profile_name, root_dir)
config_root = fullfile(root_dir, 'src', 'config');
profiles = pseudo_CT_list_profiles(config_root, false);
profile_path = '';
for ii = 1:length(profiles)
    if strcmp(profiles(ii).name, profile_name)
        profile_path = profiles(ii).file_path;
        break;
    end
end
if isempty(profile_path)
    error('pseudo_CT:InvalidProfile', 'The selected profile is unavailable.');
end
identity = struct('profile_path', profile_path, ...
    'profile_sha256', local_file_sha256(profile_path), ...
    'runner_path', '', 'runner_sha256', '', ...
    'build_manifest_path', '', 'build_manifest_sha256', '', ...
    'resource_manifest_path', '', 'resource_manifest_sha256', '');
if isfield(config, 'current') && isstruct(config.current)
    fields = {'runner'; 'build_manifest'; 'resource_manifest'};
    for ii = 1:length(fields)
        if isfield(config.current, fields{ii})
            path_name = config.current.(fields{ii});
            if ~ischar(path_name) || exist(path_name, 'file') ~= 2
                error('pseudo_CT:OrchestrationArtifact', ...
                    'A validated current artifact is unavailable.');
            end
            hash = local_file_sha256(path_name);
            if strcmp(fields{ii}, 'runner')
                identity.runner_path = path_name;
                identity.runner_sha256 = hash;
            elseif strcmp(fields{ii}, 'build_manifest')
                identity.build_manifest_path = path_name;
                identity.build_manifest_sha256 = hash;
            else
                identity.resource_manifest_path = path_name;
                identity.resource_manifest_sha256 = hash;
            end
        end
    end
end
end

function hash = local_file_sha256(path_name)
try
    hash = mlsc_release_gate('sha256_file', path_name);
catch ME
    error('pseudo_CT:OrchestrationArtifact', ...
        'A local input or artifact could not be fingerprinted: %s', ME.message);
end
if ~ischar(hash) || isempty(hash)
    error('pseudo_CT:OrchestrationArtifact', ...
        'A local input or artifact could not be fingerprinted.');
end
end

function local_require_writable_target(target_path)
if ~ischar(target_path) || size(target_path, 1) ~= 1 || ...
        isempty(target_path) || any(target_path == char(0))
    error('pseudo_CT:OrchestrationOutput', ...
        'A configured output path is invalid.');
end
candidate = target_path;
while exist(candidate, 'dir') ~= 7
    if exist(candidate, 'file') == 2
        error('pseudo_CT:OrchestrationOutput', ...
            'A configured output path is occupied by a file.');
    end
    parent = fileparts(candidate);
    if isempty(parent) || strcmp(parent, candidate)
        error('pseudo_CT:OrchestrationOutput', ...
            'A usable output directory could not be resolved.');
    end
    candidate = parent;
end
[available, attributes] = fileattrib(candidate);
if ~available || (~attributes.UserWrite && ...
        ~attributes.GroupWrite && ~attributes.OtherWrite)
    error('pseudo_CT:OrchestrationOutput', ...
        'The existing parent of a configured output path is not writable.');
end
end

function value = local_text_field(request, name, fallback)
value = fallback;
if isfield(request, name)
    value = request.(name);
end
if ~ischar(value) || (~isempty(value) && size(value, 1) ~= 1) || ...
        any(value == char(0))
    error('pseudo_CT:OrchestrationRequest', ...
        'An orchestration text field is invalid.');
end
end

function provider = local_host_key_provider(request)
provider = [];
if ~isfield(request, 'host_key_file') || isempty(request.host_key_file)
    return;
end
path_name = request.host_key_file;
if ~ischar(path_name) || size(path_name, 1) ~= 1 || ...
        any(path_name == char(0))
    error('pseudo_CT:HeadlessHostKey', ...
        'Strict MLSC host-key material is unavailable.');
end
fid = fopen(path_name, 'r');
if fid == -1
    error('pseudo_CT:HeadlessHostKey', ...
        'Strict MLSC host-key material is unavailable.');
end
provider = fscanf(fid, '%c');
close_status = fclose(fid);
if close_status ~= 0 || isempty(provider)
    provider = [];
    error('pseudo_CT:HeadlessHostKey', ...
        'Strict MLSC host-key material is unavailable.');
end
end

function local_cleanup_transport(transport)
if isstruct(transport) && isfield(transport, 'cleanup') && ...
        isa(transport.cleanup, 'function_handle')
    try
        feval(transport.cleanup);
    catch %#ok<CTCH>
    end
end
end
