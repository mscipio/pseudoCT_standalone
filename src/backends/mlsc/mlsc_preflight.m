function report = mlsc_preflight(subject, config, runtime)
%MLSC_PREFLIGHT Validate one MLSC shared-filesystem subject before submit.
%   REPORT = MLSC_PREFLIGHT(SUBJECT, CONFIG, RUNTIME) validates the selected
%   MLSC resources, the shared subject input/temp paths, and any transient
%   submission values.  It performs no network or scheduler operation.
%
%   SUBJECT must identify the input already written by MATLAB in the existing
%   shared subject temporary directory with fields SHARED_INPUT and
%   SHARED_TEMP.  SEED_NII/TEMP_DIR are accepted as aliases for the existing
%   orchestration seam.  RUNTIME may contain ACCOUNT, SCRIPT_PATH, and
%   JOB_NAME; none of these values are persisted by this function.
%
%   T004 current branch (T014 authoritative): when CONFIG selects the
%   MLSC current implementation, only the payload portion is parameterized.
%   CONFIG.mlsc carries scheduler/host/shell/FreeSurfer fields only and
%   CONFIG.current carries the pinned artifact contract (runner, pinned
%   MCR_ROOT /usr/pubsw/common/matlab/26.1, build/resource manifest paths).
%   No catalog, no resolver, no dynamic discovery, no MCR 7.11 fallback.
%   Legacy invocation/ordering is untouched.
%
%   Minimum supported MATLAB: R2010b.

if nargin < 2 || ~isstruct(subject) || ~isstruct(config)
    error('pseudo_CT:MLSCPreflight', ...
        'An MLSC subject and selected profile config are required.');
end
if nargin < 3 || isempty(runtime)
    runtime = struct();
end
if ~isstruct(runtime) || numel(runtime) ~= 1
    error('pseudo_CT:MLSCPreflight', ...
        'Runtime MLSC submission values must be one struct.');
end

if ~isfield(config, 'mode') || ~ischar(config.mode) || ...
        ~strcmp(config.mode, 'mlsc')
    error('pseudo_CT:MLSCPreflight', ...
        'The selected profile is not an MLSC profile.');
end
if ~isfield(config, 'mlsc') || ~isstruct(config.mlsc) || ...
        numel(config.mlsc) ~= 1
    error('pseudo_CT:MLSCPreflight', ...
        'The selected profile has no valid MLSC resource block.');
end

is_current = false;
try
    is_current = mlsc_current_validate('is_current', config);
catch %#ok<CTCH>
    is_current = false;
end
if is_current
    mlsc = config.mlsc;
    local_validate_current_scheduler(mlsc);
    try
        mlsc_current_validate('validate_contract', config);
    catch ME
        if strncmp(ME.identifier, 'pseudo_CT:MLSC', length('pseudo_CT:MLSC'))
            rethrow(ME);
        end
        error('pseudo_CT:MLSCCurrentContract', ...
            'The MLSC current artifact contract is invalid.');
    end
else
mlsc = config.mlsc;
required_fields = {'host'; 'runner'; 'mcr_root'; 'defaults_mat'; ...
    'batch_templates'; 'shell'; 'freesurfer_env'; 'partition'; ...
    'nodes'; 'ntasks'; 'cpus_per_task'; 'memory'; 'time'};
for ii = 1:length(required_fields)
    if ~isfield(mlsc, required_fields{ii})
        error('pseudo_CT:MLSCPreflight', ...
            'The MLSC profile is missing a required resource value.');
    end
end

forbidden_fields = {'account'; 'username'; 'password'; 'passphrase'; ...
    'credentials'; 'credential'; 'token'; 'secret'};
for ii = 1:length(forbidden_fields)
    if isfield(mlsc, forbidden_fields{ii})
        error('pseudo_CT:MLSCPreflight', ...
            'MLSC credentials and scheduler accounts are runtime-only.');
    end
end

text_fields = {'host'; 'runner'; 'mcr_root'; 'defaults_mat'; ...
    'batch_templates'; 'shell'; 'freesurfer_env'; 'partition'; ...
    'memory'; 'time'};
for ii = 1:length(text_fields)
    local_require_text(mlsc.(text_fields{ii}), ...
        'pseudo_CT:MLSCPreflight');
end
if isempty(regexp(mlsc.host, '^[A-Za-z0-9_.:-]+$', 'once'))
    error('pseudo_CT:MLSCPreflight', ...
        'The MLSC host contains unsafe shell/transport characters.');
end

integer_fields = {'nodes'; 'ntasks'; 'cpus_per_task'};
for ii = 1:length(integer_fields)
    value = mlsc.(integer_fields{ii});
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
            value < 1 || value ~= floor(value)
        error('pseudo_CT:MLSCPreflight', ...
            'MLSC Slurm resource values must be positive integers.');
    end
end
if isempty(regexp(mlsc.partition, '^[A-Za-z0-9_.-]+$', 'once'))
    error('pseudo_CT:MLSCPreflight', ...
        'The MLSC Slurm partition contains unsafe shell/Slurm characters.');
end
[~, shell_name, ~] = fileparts(mlsc.shell);
if ~strcmp(shell_name, 'bash')
    error('pseudo_CT:MLSCPreflight', ...
        'The MLSC batch script requires a configured Bash shell.');
end
if isempty(regexp(mlsc.memory, '^[1-9][0-9]*[KMGTP]$', 'once')) || ...
        isempty(regexp(mlsc.time, '^[0-9][0-9]:[0-5][0-9]:[0-5][0-9]$', 'once'))
    error('pseudo_CT:MLSCPreflight', ...
        'MLSC memory and time values are not valid Slurm values.');
end

% A shebang cannot be shell-quoted, so reject control/metacharacters for the
% configured shell while all other command arguments are quoted below.
shell_meta = {char(9); sprintf('\n'); char(13); char(32); ';'; '|'; '&'; ...
    char(96); '$'; '('; ')'; '<'; '>'; '['; ']'; '{'; '}'; '!'; ...
    char(39); char(34); char(92)};
for ii = 1:length(shell_meta)
    if ~isempty(strfind(mlsc.shell, shell_meta{ii}))
        error('pseudo_CT:MLSCPreflight', ...
            'The configured MLSC shell cannot be used safely as a shebang.');
    end
end
end

shared_input = local_subject_value(subject, {'shared_input'; 'seed_nii'});
shared_temp = local_subject_value(subject, {'shared_temp'; 'temp_dir'});
local_require_text(shared_input, 'pseudo_CT:MLSCPreflight');
local_require_text(shared_temp, 'pseudo_CT:MLSCPreflight');

input_parent = fileparts(shared_input);
if isempty(input_parent)
    input_parent = '.';
end
if ~strcmp(local_strip_trailing_separators(input_parent), ...
        local_strip_trailing_separators(shared_temp))
    error('pseudo_CT:MLSCPreflight', ...
        'The MLSC input must be a top-level file in the shared subject temp.');
end
if exist(shared_input, 'file') ~= 2 || ~local_is_readable(shared_input)
    error('pseudo_CT:MLSCInputUnreadable', ...
        'The shared MLSC subject input is not readable.');
end
if exist(shared_temp, 'dir') ~= 7 || ~local_is_writable_directory(shared_temp)
    error('pseudo_CT:MLSCTempUnwritable', ...
        'The shared MLSC subject temporary directory is not writable.');
end

if is_current
    % Current artifact files (runner/MCR_ROOT/manifests) are already
    % validated by mlsc_current_validate('validate_contract') above;
    % only the scheduler files owned by config.mlsc need existence here.
    resource_files = {mlsc.shell; mlsc.freesurfer_env};
else
    resource_files = {mlsc.runner; mlsc.defaults_mat; mlsc.shell; ...
        mlsc.freesurfer_env};
end
for ii = 1:length(resource_files)
    if exist(resource_files{ii}, 'file') ~= 2
        error('pseudo_CT:MissingResource', ...
            'A configured MLSC file resource is unavailable.');
    end
end
if is_current
    resource_dirs = {};
else
    resource_dirs = {mlsc.mcr_root; mlsc.batch_templates};
end
for ii = 1:length(resource_dirs)
    if exist(resource_dirs{ii}, 'dir') ~= 7
        error('pseudo_CT:MissingResource', ...
            'A configured MLSC directory resource is unavailable.');
    end
end

runtime_forbidden_fields = {'username'; 'password'; 'passphrase'; ...
    'credentials'; 'credential'; 'token'; 'secret'};
for ii = 1:length(runtime_forbidden_fields)
    if isfield(runtime, runtime_forbidden_fields{ii})
        error('pseudo_CT:MLSCPreflight', ...
            'MLSC authentication material is not a submission parameter.');
    end
end
if isfield(runtime, 'account')
    local_require_runtime_text(runtime.account, 'pseudo_CT:MLSCPreflight');
end
if isfield(runtime, 'script_path')
    local_require_runtime_text(runtime.script_path, 'pseudo_CT:MLSCPreflight');
    script_parent = fileparts(runtime.script_path);
    if isempty(script_parent)
        script_parent = '.';
    end
    [~, script_name, script_ext] = fileparts(runtime.script_path);
    if isempty(script_name) && isempty(script_ext)
        error('pseudo_CT:MLSCPreflight', ...
            'The runtime MLSC script path must name a file.');
    end
    if exist(script_parent, 'dir') ~= 7 || ...
            ~local_is_writable_directory(script_parent)
        error('pseudo_CT:MLSCScriptUnwritable', ...
            'The runtime MLSC script directory is not writable.');
    end
end
if isfield(runtime, 'job_name')
    local_require_runtime_text(runtime.job_name, 'pseudo_CT:MLSCPreflight');
end
if isfield(runtime, 'submission_correlation_id') && ...
        ~isempty(runtime.submission_correlation_id)
    local_require_runtime_text(runtime.submission_correlation_id, ...
        'pseudo_CT:MLSCPreflight');
end

if ~isfield(config, 'aliasing_default')
    error('pseudo_CT:MLSCPreflight', ...
        'The selected MLSC profile has no aliasing default.');
end
check_aliasing = config.aliasing_default;
if isfield(subject, 'check_aliasing')
    check_aliasing = subject.check_aliasing;
elseif isfield(subject, 'correct_aliasing')
    check_aliasing = subject.correct_aliasing;
end
if ~(isnumeric(check_aliasing) || islogical(check_aliasing)) || ...
        ~isscalar(check_aliasing) || ~ismember(double(check_aliasing), [0 1])
        error('pseudo_CT:MLSCPreflight', ...
            'MLSC check_aliasing must be a scalar 0 or 1.');
end

[~, input_name, input_ext] = fileparts(shared_input);
if isempty(input_name) || isempty(input_ext)
    error('pseudo_CT:MLSCPreflight', ...
        'The shared MLSC input must have a filename and extension.');
end
normalized_name = [input_name '_normalized' input_ext];
needs_normalization = isempty(regexp(lower([input_name input_ext]), ...
    '_normalized\.nii$', 'once'));

report = struct();
report.schema = 'pseudo-CT.mlsc-preflight/v1';
report.ok = true;
report.shared_input_readable = true;
report.shared_temp_writable = true;
report.check_aliasing = double(check_aliasing);
report.input_name = [input_name input_ext];
report.normalized_name = normalized_name;
report.needs_normalization = needs_normalization;
report.secure_transport_required = true;
end

function value = local_subject_value(subject, names)
value = '';
for ii = 1:length(names)
    if isfield(subject, names{ii})
        value = subject.(names{ii});
        return;
    end
end
end

function local_require_text(value, identifier)
if ~ischar(value) || size(value, 1) ~= 1 || isempty(value) || ...
        any(value == char(0))
    error(identifier, 'An MLSC path/resource value is invalid.');
end
end

function local_require_runtime_text(value, identifier)
if ~ischar(value) || size(value, 1) ~= 1 || isempty(value) || ...
        any(value == char(0))
    error(identifier, 'A runtime MLSC submission value is invalid.');
end
end

function readable = local_is_readable(file_path)
fid = fopen(file_path, 'r');
readable = fid ~= -1;
if readable
    fclose(fid);
end
end

function writable = local_is_writable_directory(directory_path)
if exist(directory_path, 'dir') ~= 7
    writable = false;
    return;
end
probe_path = tempname(directory_path);
fid = fopen(probe_path, 'w');
writable = fid ~= -1;
if writable
    fclose(fid);
    if exist(probe_path, 'file') == 2
        delete(probe_path);
    end
end
end

function value = local_strip_trailing_separators(value)
while length(value) > 1 && (value(end) == '/' || value(end) == char(92))
    value(end) = '';
end
end

function local_validate_current_scheduler(mlsc)
%LOCAL_VALIDATE_CURRENT_SCHEDULER Scheduler-only MLSC block for current.
%   Requires host/shell/FreeSurfer/partition/resources only. Rejects legacy
%   payload fields (runner/mcr_root/defaults_mat/batch_templates) so no
%   fake legacy contract can satisfy current validation. Mirrors the
%   legacy text/integer/partition/shell/memory/time checks without
%   duplicating the current artifact contract (owned by
%   mlsc_current_validate).
legacy_fields = {'runner'; 'mcr_root'; 'defaults_mat'; 'batch_templates'};
for ii = 1:length(legacy_fields)
    if isfield(mlsc, legacy_fields{ii})
        error('pseudo_CT:MLSCPreflight', ...
            'The MLSC current profile must not carry legacy field %s.', ...
            legacy_fields{ii});
    end
end
required_fields = {'host'; 'shell'; 'freesurfer_env'; 'partition'; ...
    'nodes'; 'ntasks'; 'cpus_per_task'; 'memory'; 'time'};
for ii = 1:length(required_fields)
    if ~isfield(mlsc, required_fields{ii})
        error('pseudo_CT:MLSCPreflight', ...
            'The MLSC profile is missing a required resource value.');
    end
end
forbidden_fields = {'account'; 'username'; 'password'; 'passphrase'; ...
    'credentials'; 'credential'; 'token'; 'secret'};
for ii = 1:length(forbidden_fields)
    if isfield(mlsc, forbidden_fields{ii})
        error('pseudo_CT:MLSCPreflight', ...
            'MLSC credentials and scheduler accounts are runtime-only.');
    end
end
text_fields = {'host'; 'shell'; 'freesurfer_env'; 'partition'; ...
    'memory'; 'time'};
for ii = 1:length(text_fields)
    local_require_text(mlsc.(text_fields{ii}), ...
        'pseudo_CT:MLSCPreflight');
end
if isempty(regexp(mlsc.host, '^[A-Za-z0-9_.:-]+$', 'once'))
    error('pseudo_CT:MLSCPreflight', ...
        'The MLSC host contains unsafe shell/transport characters.');
end
integer_fields = {'nodes'; 'ntasks'; 'cpus_per_task'};
for ii = 1:length(integer_fields)
    value = mlsc.(integer_fields{ii});
    if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
            value < 1 || value ~= floor(value)
        error('pseudo_CT:MLSCPreflight', ...
            'MLSC Slurm resource values must be positive integers.');
    end
end
if isempty(regexp(mlsc.partition, '^[A-Za-z0-9_.-]+$', 'once'))
    error('pseudo_CT:MLSCPreflight', ...
        'The MLSC Slurm partition contains unsafe shell/Slurm characters.');
end
[~, shell_name, ~] = fileparts(mlsc.shell);
if ~strcmp(shell_name, 'bash')
    error('pseudo_CT:MLSCPreflight', ...
        'The MLSC batch script requires a configured Bash shell.');
end
if isempty(regexp(mlsc.memory, '^[1-9][0-9]*[KMGTP]$', 'once')) || ...
        isempty(regexp(mlsc.time, '^[0-9][0-9]:[0-5][0-9]:[0-5][0-9]$', 'once'))
    error('pseudo_CT:MLSCPreflight', ...
        'MLSC memory and time values are not valid Slurm values.');
end
shell_meta = {char(9); sprintf('\n'); char(13); char(32); ';'; '|'; '&'; ...
    char(96); '$'; '('; ')'; '<'; '>'; '['; ']'; '{'; '}'; '!'; ...
    char(39); char(34); char(92)};
for ii = 1:length(shell_meta)
    if ~isempty(strfind(mlsc.shell, shell_meta{ii}))
        error('pseudo_CT:MLSCPreflight', ...
            'The configured MLSC shell cannot be used safely as a shebang.');
    end
end
end
