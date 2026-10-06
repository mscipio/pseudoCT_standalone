function success = pseudo_CT_run_local_legacy_subject(job, config, subject_index, subject_count, show_dialog)
%PSEUDO_CT_RUN_LOCAL_LEGACY_SUBJECT Direct-local legacy compiled subject.
%   Runs one subject with the legacy v2.0 compiled backend on the local
%   workstation: prepare input, isolated child normalization, synchronous
%   compiled invoke, verified gate, then the shared finalization utilities.
%   All paths are POSIX single-quoted. The child alone carries the
%   normalization environment; this workspace is never altered.
%
%   Minimum supported MATLAB: R2010b.

success = 0;
if nargin < 4
    error('pseudo_CT:InvalidJob', 'A job, config, and subject position are required.');
end
if nargin < 5 || isempty(show_dialog)
    show_dialog = false;
end
if ~isstruct(job) || numel(job) ~= 1
    error('pseudo_CT:InvalidJob', 'A single job struct is required.');
end
if ~isstruct(config) || numel(config) ~= 1
    error('pseudo_CT:ProfileRequired', 'A single profile config is required.');
end
if ~isnumeric(subject_index) || ~isscalar(subject_index) || ...
        ~isnumeric(subject_count) || ~isscalar(subject_count)
    error('pseudo_CT:InvalidJob', 'Subject position must be numeric scalars.');
end

base_context = struct('log_file', '', 'subject_index', subject_index, ...
    'subject_count', subject_count, 'scope', 'subject');
try
    base_context.log_file = job.log_file;
catch %#ok<CTCH>
    base_context.log_file = '';
end
try
    subject_started = job.subject_started;
catch %#ok<CTCH>
    subject_started = tic;
end

if ~isfield(config, 'mode') || ~ischar(config.mode) || ~strcmp(config.mode, 'local')
    pseudo_CT_output('ERROR', base_context, 'Legacy direct-local config requires local execution.');
    return;
end
if ~isfield(config, 'implementation') || ~ischar(config.implementation) || ...
        ~strcmp(config.implementation, 'legacy-v2')
    pseudo_CT_output('ERROR', base_context, 'Legacy direct-local config requires the legacy implementation.');
    return;
end
if ~isfield(config, 'normalization') || ~isstruct(config.normalization)
    pseudo_CT_output('ERROR', base_context, 'Legacy direct-local config is missing normalization.');
    return;
end
local_host = '';
try
    local_host = config.normalization.host;
catch %#ok<CTCH>
end
if ~(ischar(local_host) && (strcmp(local_host, '127.0.0.1') || strcmpi(local_host, 'localhost')))
    pseudo_CT_output('ERROR', base_context, 'Legacy direct-local config requires local normalization.');
    return;
end
cluster_flag = '';
try
    cluster_flag = config.normalization.cluster;
catch %#ok<CTCH>
end
if ~(ischar(cluster_flag) && strcmp(cluster_flag, 'No'))
    pseudo_CT_output('ERROR', base_context, 'Legacy direct-local config requires local normalization.');
    return;
end

if ~isfield(job, 'mprage_fn') || ~ischar(job.mprage_fn) || isempty(strtrim(job.mprage_fn))
    pseudo_CT_output('ERROR', base_context, 'Job is missing its MPRAGE input.');
    return;
end
if ~isfield(job, 'temp_dir') || ~ischar(job.temp_dir) || isempty(job.temp_dir)
    pseudo_CT_output('ERROR', base_context, 'Job is missing its temporary directory.');
    return;
end
if ~isfield(job, 'processing_dir') || ~ischar(job.processing_dir) || isempty(job.processing_dir)
    pseudo_CT_output('ERROR', base_context, 'Job is missing its processing directory.');
    return;
end
temp_dir = job.temp_dir;
processing_dir = job.processing_dir;
save_dir = '';
if isfield(job, 'save_dir') && ischar(job.save_dir)
    save_dir = job.save_dir;
end
umap_fn = '';
if isfield(job, 'umap_fn') && ischar(job.umap_fn)
    umap_fn = job.umap_fn;
end
check_aliasing = 1;
if isfield(config, 'aliasing_default')
    check_aliasing = config.aliasing_default;
end
if isfield(job, 'correct_aliasing')
    check_aliasing = job.correct_aliasing;
elseif isfield(job, 'check_aliasing')
    check_aliasing = job.check_aliasing;
end
if islogical(check_aliasing)
    check_aliasing = double(check_aliasing);
end
if ~isnumeric(check_aliasing) || ~isscalar(check_aliasing) || ~ismember(check_aliasing, [0 1])
    pseudo_CT_output('ERROR', base_context, 'Aliasing flag must be a scalar 0 or 1.');
    return;
end

legacy_runner = '';
legacy_mcr = '';
legacy_defaults = '';
legacy_batch = '';
legacy_att = '';
legacy_atlas = '';
legacy_source = '';
try
    legacy_runner = config.legacy.runner;
    legacy_mcr = config.legacy.mcr_root;
    legacy_defaults = config.legacy.defaults_mat;
    legacy_batch = config.legacy.batch_templates;
    legacy_att = config.legacy.att_map;
    legacy_atlas = config.atlas_root;
    legacy_source = config.normalization.source_command;
catch %#ok<CTCH>
end
if ~ischar(legacy_runner) || isempty(legacy_runner) || exist(legacy_runner, 'file') ~= 2
    pseudo_CT_output('ERROR', base_context, 'Legacy runner was not found.');
    return;
end
if ~ischar(legacy_mcr) || isempty(legacy_mcr) || exist(legacy_mcr, 'dir') ~= 7
    pseudo_CT_output('ERROR', base_context, 'Legacy runtime directory was not found.');
    return;
end
if ~ischar(legacy_defaults) || isempty(legacy_defaults) || exist(legacy_defaults, 'file') ~= 2
    pseudo_CT_output('ERROR', base_context, 'Legacy defaults file was not found.');
    return;
end
if ~ischar(legacy_batch) || isempty(legacy_batch) || exist(legacy_batch, 'dir') ~= 7
    pseudo_CT_output('ERROR', base_context, 'Legacy template directory was not found.');
    return;
end
if ~ischar(legacy_atlas) || isempty(legacy_atlas) || exist(legacy_atlas, 'dir') ~= 7
    pseudo_CT_output('ERROR', base_context, 'Legacy atlas directory was not found.');
    return;
end
if ~ischar(legacy_att) || isempty(strtrim(legacy_att))
    pseudo_CT_output('ERROR', base_context, 'Legacy attenuation-map name was not found.');
    return;
end
if ~ischar(legacy_source) || isempty(strtrim(legacy_source))
    pseudo_CT_output('ERROR', base_context, 'Legacy normalization command was not found.');
    return;
end
legacy_env = local_parse_source_env(legacy_source);
if ~ischar(legacy_env) || isempty(legacy_env) || exist(legacy_env, 'file') ~= 2
    pseudo_CT_output('ERROR', base_context, 'Legacy environment file was not found.');
    return;
end
if exist(temp_dir, 'dir') ~= 7
    [made, made_msg] = mkdir(temp_dir);
    if ~made
        pseudo_CT_output('ERROR', base_context, 'Could not create temporary directory: %s', made_msg);
        return;
    end
end
if ~local_is_writable_directory(temp_dir)
    pseudo_CT_output('ERROR', base_context, 'Temporary directory is not writable.');
    return;
end
if exist(processing_dir, 'dir') ~= 7
    [made, made_msg] = mkdir(processing_dir);
    if ~made
        pseudo_CT_output('ERROR', base_context, 'Could not create processing directory: %s', made_msg);
        return;
    end
end
if isfield(config, 'io_policy') && isstruct(config.io_policy) && ...
        isfield(config.io_policy, 'output') && strcmp(config.io_policy.output, 'nifti-and-dicom')
    if isempty(save_dir)
        pseudo_CT_output('ERROR', base_context, 'Job is missing its DICOM directory.');
        return;
    end
    if exist(save_dir, 'dir') ~= 7
        [made, made_msg] = mkdir(save_dir);
        if ~made
            pseudo_CT_output('ERROR', base_context, 'Could not create DICOM directory: %s', made_msg);
            return;
        end
    end
end

stage_context = local_stage_context(base_context, 1);
pseudo_CT_output('INFO', stage_context, 'Preparing input MPRAGE.');
try
    seed_nii = dcm2nii(job.mprage_fn, fullfile(temp_dir, 'mprage.nii'), 'Overwrite', true);
catch ME_stage
    pseudo_CT_output('ERROR', base_context, 'Input preparation failed: %s', ME_stage.message);
    return;
end
if ~ischar(seed_nii) || isempty(strtrim(seed_nii))
    pseudo_CT_output('ERROR', base_context, 'Input preparation produced no output.');
    return;
end
seed_nii = deblank(seed_nii);
if exist(seed_nii, 'file') ~= 2
    pseudo_CT_output('ERROR', base_context, 'Prepared input was not found.');
    return;
end
pseudo_CT_output('SUCCESS', stage_context, 'Input prepared (elapsed %s).', ...
    local_elapsed(toc(subject_started)));

[~, input_base, input_ext] = fileparts(seed_nii);
if isempty(input_base) || isempty(input_ext)
    pseudo_CT_output('ERROR', base_context, 'Prepared input has no valid filename.');
    return;
end
normalized_name = [input_base '_normalized' input_ext];
needs_normalization = isempty(regexp(lower([input_base input_ext]), '_normalized\.nii$', 'once'));
input_path = seed_nii;
normalized_path = fullfile(temp_dir, normalized_name);

if needs_normalization
    norm_context = local_stage_context(base_context, 2);
    pseudo_CT_output('INFO', norm_context, 'Normalizing MPRAGE with FreeSurfer.');
    q_env = local_shell_quote(legacy_env);
    q_in = local_shell_quote(input_path);
    q_out = local_shell_quote(normalized_path);
    inner_cmd = ['source ' q_env '; mri_normalize ' q_in ' ' q_out];
    q_inner = local_shell_quote(inner_cmd);
    norm_cmd = ['env -u LD_LIBRARY_PATH tcsh -f -c ' q_inner];
    [norm_status, norm_detail] = system(norm_cmd);
    if norm_status ~= 0
        pseudo_CT_output('ERROR', norm_context, 'FreeSurfer normalization failed.');
        if ischar(norm_detail) && ~isempty(strtrim(norm_detail))
            pseudo_CT_output('ERROR', norm_context, 'FreeSurfer failure detail: %s', strtrim(norm_detail));
        end
        pseudo_CT_output('ERROR', norm_context, 'FreeSurfer exit status: %d.', norm_status);
        return;
    end
    if exist(normalized_path, 'file') ~= 2
        pseudo_CT_output('ERROR', norm_context, 'FreeSurfer did not create the normalized NIfTI file.');
        return;
    end
    norm_info = dir(normalized_path);
    if isempty(norm_info) || norm_info(1).bytes == 0
        pseudo_CT_output('ERROR', norm_context, 'FreeSurfer normalized file is empty.');
        return;
    end
    pseudo_CT_output('SUCCESS', norm_context, 'MPRAGE normalization completed (elapsed %s).', ...
        local_elapsed(toc(subject_started)));
else
    norm_context = local_stage_context(base_context, 2);
    pseudo_CT_output('INFO', norm_context, 'Normalization input already normalized; skipping.');
    normalized_path = input_path;
end

staged_input = normalized_path;
invoke_context = local_stage_context(base_context, 3);
pseudo_CT_output('INFO', invoke_context, 'Running legacy compiled backend.');
q_runner = local_shell_quote(legacy_runner);
q_mcr = local_shell_quote(legacy_mcr);
q_staged = local_shell_quote(staged_input);
q_batch = local_shell_quote(legacy_batch);
q_defaults = local_shell_quote(legacy_defaults);
runner_cmd = [q_runner ' ' q_mcr ' ' q_staged ' ' q_batch ' 0 ' num2str(check_aliasing) ' ' q_defaults];
[runner_status, runner_detail] = system(runner_cmd);
if runner_status ~= 0
    pseudo_CT_output('ERROR', invoke_context, 'Legacy compiled backend failed.');
    if ischar(runner_detail) && ~isempty(strtrim(runner_detail))
        pseudo_CT_output('ERROR', invoke_context, 'Backend failure detail: %s', strtrim(runner_detail));
    end
    pseudo_CT_output('ERROR', invoke_context, 'Backend exit status: %d.', runner_status);
    return;
end
pseudo_CT_output('SUCCESS', invoke_context, 'Legacy compiled backend finished (elapsed %s).', ...
    local_elapsed(toc(subject_started)));

verify_context = local_stage_context(base_context, 4);
att_path = fullfile(temp_dir, legacy_att);
if exist(att_path, 'file') ~= 2
    pseudo_CT_output('ERROR', verify_context, 'Required attenuation map was not found.');
    pseudo_CT_output('INFO', verify_context, '    %s', att_path);
    return;
end
att_info = dir(att_path);
if isempty(att_info) || att_info(1).bytes == 0
    pseudo_CT_output('ERROR', verify_context, 'Required attenuation map is empty.');
    return;
end
pseudo_CT_output('SUCCESS', verify_context, 'Attenuation map verified (elapsed %s).', ...
    local_elapsed(toc(subject_started)));

post_context = local_stage_context(base_context, 5);
pseudo_CT_output('INFO', post_context, 'Applying local post-processing.');
if isfield(config, 'zero_background') && ischar(config.zero_background) && strcmp(config.zero_background, 'Yes')
    pseudo_CT_apply_background_mask(temp_dir, post_context);
end
pseudo_CT_output('SUCCESS', post_context, 'Local post-processing completed (elapsed %s).', ...
    local_elapsed(toc(subject_started)));

writes_dicom = isfield(config, 'io_policy') && isstruct(config.io_policy) && ...
    isfield(config.io_policy, 'output') && strcmp(config.io_policy.output, 'nifti-and-dicom');
if writes_dicom
    dicom_context = local_stage_context(base_context, 6);
    pseudo_CT_output('INFO', dicom_context, 'Writing DICOM output.');
    try
        fwhm_value = 0;
        if isfield(config, 'fwhm')
            fwhm_value = config.fwhm;
        end
        pseudo_CT_write_mu_map_dicom(att_path, save_dir, umap_fn, temp_dir, fwhm_value);
    catch ME_dicom
        pseudo_CT_output('ERROR', dicom_context, 'DICOM output failed: %s', ME_dicom.message);
        return;
    end
    pseudo_CT_output('SUCCESS', dicom_context, 'DICOM output written (elapsed %s).', ...
        local_elapsed(toc(subject_started)));
else
    pseudo_CT_output('INFO', post_context, 'Skipping DICOM output by profile policy.');
end

promote_context = local_stage_context(base_context, 7);
pseudo_CT_output('INFO', promote_context, 'Promoting final outputs.');
promotion_success = pseudo_CT_promote_final_outputs(temp_dir, processing_dir, seed_nii, promote_context);
if ~promotion_success
    pseudo_CT_output('ERROR', promote_context, 'Output promotion failed; temporary files were preserved.');
    pseudo_CT_output('INFO', promote_context, '    %s', temp_dir);
    return;
end
pseudo_CT_output('SUCCESS', promote_context, 'Outputs promoted (elapsed %s).', ...
    local_elapsed(toc(subject_started)));

cleanup_context = local_stage_context(base_context, 8);
pseudo_CT_output('INFO', cleanup_context, 'Cleaning up temporary files.');
do_cleanup = false;
if isfield(config, 'cleanup_on_success')
    do_cleanup = isequal(config.cleanup_on_success, true);
end
if do_cleanup
    [remove_success, remove_msg] = rmdir(temp_dir, 's');
    if ~remove_success
        pseudo_CT_output('WARN', cleanup_context, 'Temporary cleanup failed: %s', remove_msg);
    end
end
pseudo_CT_output('SUCCESS', cleanup_context, 'Cleanup completed (elapsed %s).', ...
    local_elapsed(toc(subject_started)));

if show_dialog && ~isdeployed
    try
        warndlg('Pseudo-CT processing completed.', 'Pseudo-CT completed');
    catch %#ok<CTCH>
    end
end

success = 1;
pseudo_CT_output('SUCCESS', base_context, 'Subject completed (elapsed %s).', ...
    local_elapsed(toc(subject_started)));
end

function context = local_stage_context(context, stage_index)
context.stage_index = stage_index;
context.stage_count = 8;
end

function value = local_elapsed(seconds)
seconds = max(0, floor(seconds));
hours = floor(seconds / 3600);
minutes = floor(rem(seconds, 3600) / 60);
seconds = rem(seconds, 60);
value = sprintf('%02d:%02d:%02d', hours, minutes, seconds);
end

function quoted = local_shell_quote(value)
single_quote = char(39);
double_quote = char(34);
quoted = single_quote;
for ii = 1:length(value)
    if value(ii) == char(0)
        error('pseudo_CT:InvalidPath', 'A shell value contains a NUL character.');
    elseif value(ii) == single_quote
        quoted = [quoted single_quote double_quote single_quote double_quote single_quote]; %#ok<AGROW>
    else
        quoted = [quoted value(ii)]; %#ok<AGROW>
    end
end
quoted = [quoted single_quote];
end

function env_path = local_parse_source_env(source_command)
env_path = '';
if ~ischar(source_command) || isempty(strtrim(source_command))
    return;
end
trimmed = strtrim(source_command);
prefix = 'source ';
if strncmp(trimmed, prefix, length(prefix))
    env_path = strtrim(trimmed(length(prefix) + 1:end));
else
    return;
end
if length(env_path) >= 2 && env_path(1) == char(39) && env_path(end) == char(39)
    env_path = env_path(2:end - 1);
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
