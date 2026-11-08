function pseudo_CT_print_profile_summary(profile_name, config, processing_dirs, output_context, subject_options, run_evidence)
%PSEUDO_CT_PRINT_PROFILE_SUMMARY Save the selected configuration summary.
%   PSEUDO_CT_PRINT_PROFILE_SUMMARY(PROFILE_NAME, CONFIG, PROCESSING_DIRS,
%   OUTPUT_CONTEXT, SUBJECT_OPTIONS, RUN_EVIDENCE) writes
%   pseudo_CT_profile_summary.txt into each folder in PROCESSING_DIRS (char or
%   cell). Both local and MLSC profiles use it; it reports configured values
%   and does not confirm execution by itself.
%   PROFILE_NAME is the canonical profile ID, CONFIG the loaded profile struct,
%   OUTPUT_CONTEXT the logging context for pseudo_CT_output (optional),
%   SUBJECT_OPTIONS and RUN_EVIDENCE optional structs (default empty).
%   Local profiles report the PCA backend resolved by pseudo_CT_pca_resolver.
%   MLSC profiles report the configured PCA order and mark execution as
%   confirmed only when RUN_EVIDENCE.terminal is true.
%   Side effects: writes the summary text file and logs its path or a warning
%   through pseudo_CT_output. Missing folders are skipped with a warning.
%   Minimum supported MATLAB: R2010b.

if nargin < 5 || ~isstruct(subject_options)
    subject_options = struct();
end
if nargin < 6 || ~isstruct(run_evidence)
    run_evidence = struct();
end

pca_backend = 'remote';
if strcmp(config.mode, 'local')
    try
        [~, pca_backend] = pseudo_CT_pca_resolver(config);
    catch
        pca_backend = 'unavailable';
    end
elseif isfield(config, 'pca_order') && iscell(config.pca_order) && ...
        ~isempty(config.pca_order)
    % MLSC reports the configured PCA order from the profile (callable-first).
    pca_backend = local_join_names(config.pca_order);
end

lines = {};
lines{end+1} = '=== pseudo-CT Profile Summary ===';
lines{end+1} = sprintf('Profile:            %s', local_profile_display_name(profile_name, config));
lines{end+1} = sprintf('Canonical profile ID: %s', profile_name);
lines{end+1} = sprintf('Selected mode (configured): %s', config.mode);
if isfield(run_evidence, 'terminal') && isequal(run_evidence.terminal, true)
    lines{end+1} = 'Actual execution backend: MLSC lifecycle terminal outcome recorded; executor provenance is shown below when available.';
else
    lines{end+1} = 'Actual execution backend: Not confirmed by this pre-dispatch summary.';
end
lines{end+1} = '';
lines{end+1} = '--- Configured Paths ---';
lines{end+1} = sprintf('SPM root:           %s', config.spm_root);
lines{end+1} = sprintf('Batch atlas:        %s', config.atlas_root);
lines{end+1} = sprintf('Configured aliasing root: %s', config.aliasing_root);
lines{end+1} = '';
lines{end+1} = '--- Pipeline Parameters ---';
lines{end+1} = sprintf('Configured recentering default: %s', config.recenter_before_normalization);
lines{end+1} = sprintf('Configured zero background: %s', config.zero_background);
lines{end+1} = sprintf('Configured cleanup on success: %s', mat2str(config.cleanup_on_success));
lines{end+1} = sprintf('Configured bone enabled: %s', mat2str(config.bone_enabled));
lines{end+1} = sprintf('Configured FWHM: %g mm', config.fwhm);
lines{end+1} = sprintf('Configured aliasing default: %d', config.aliasing_default);
lines{end+1} = sprintf('Configured PCA order/backend selection: %s', pca_backend);
lines{end+1} = '';
lines{end+1} = '--- Configured I/O Policy ---';
lines{end+1} = sprintf('Reference:          %s', config.io_policy.reference);
lines{end+1} = sprintf('Output:             %s', config.io_policy.output);
lines{end+1} = sprintf('GUI:                %s', config.io_policy.gui);
if ~isempty(config.required_matlab_release)
    lines{end+1} = sprintf('Configured required MATLAB: R%s', config.required_matlab_release);
end

if strcmp(config.mode, 'mlsc') && isfield(config, 'current')
    lines{end+1} = '';
    lines{end+1} = '--- MLSC Current Artifact (configured; not execution evidence) ---';
    lines{end+1} = sprintf('Configured runner:  %s', config.current.runner);
    lines{end+1} = sprintf('Configured MCR root: %s', config.current.mcr_root);
    lines{end+1} = sprintf('Configured build manifest: %s', config.current.build_manifest);
    lines{end+1} = 'Build identifier is recorded in the build manifest, not in profile configuration; see Execution Provenance.';
    lines{end+1} = sprintf('Configured resource manifest: %s', config.current.resource_manifest);
    lines{end+1} = sprintf('Configured artifact root: %s', local_artifact_root(config));
    if isfield(config.current, 'required_outputs') && ...
            iscell(config.current.required_outputs)
        lines{end+1} = sprintf('Required outputs:   %s', ...
            local_join_names(config.current.required_outputs));
    end
    lines{end+1} = 'Configured status:  Artifact configuration loaded; runtime validation/execution not confirmed here.';
end

if strcmp(config.mode, 'mlsc') && isfield(config, 'mlsc') && ...
        isstruct(config.mlsc)
    lines{end+1} = '';
    lines{end+1} = '--- Configured MLSC Submission Settings (not observed executor facts) ---';
    fields = {'host', 'shell', 'partition', 'cpus_per_task', ...
        'memory', 'time'};
    labels = {'host', 'shell', 'partition', 'CPUs/task', ...
        'memory', 'time'};
    for ii = 1:numel(fields)
        if isfield(config.mlsc, fields{ii})
            value = config.mlsc.(fields{ii});
            if ischar(value) || (isnumeric(value) && isscalar(value))
                if ischar(value)
                    value_text = value;
                else
                    value_text = num2str(value);
                end
                lines{end+1} = sprintf('Configured %s: %s', ...
                    labels{ii}, value_text);
            end
        end
    end
end

lines{end+1} = '';
lines{end+1} = '--- Submitter MATLAB Environment (local, pre-dispatch) ---';
lines{end+1} = sprintf('MATLAB version/build: %s', version);
lines{end+1} = sprintf('MATLAB release:     R%s', version('-release'));
lines{end+1} = '';
lines{end+1} = '--- Execution Provenance ---';
lines{end+1} = 'Submitter:          Local MATLAB process that wrote this summary.';
aliasing_requested = local_requested_option(subject_options, 'correct_aliasing');
recentering_requested = local_requested_option(subject_options, ...
    'recenter_before_normalization');
lines{end+1} = sprintf('Requested aliasing correction: %s', aliasing_requested);
lines{end+1} = ['Confirmed aliasing correction: Not confirmed ', ...
    '(no per-stage confirmation evidence recorded).'];
lines{end+1} = sprintf('Requested recentering: %s', recentering_requested);
lines{end+1} = ['Confirmed recentering: Not confirmed ', ...
    '(no per-stage confirmation evidence recorded).'];
if isfield(run_evidence, 'terminal') && isequal(run_evidence.terminal, true)
    lines{end+1} = sprintf('Current-run MLSC scheduler state: %s', ...
        local_evidence_text(run_evidence, 'scheduler_state'));
    lines{end+1} = sprintf('Current-run local finalization: %s', ...
        local_evidence_text(run_evidence, 'finalization_status'));
else
    lines{end+1} = 'Current-run MLSC outcome: Not available in pre-dispatch summary.';
end
executor_provenance = local_evidence_struct(run_evidence, ...
    'executor_provenance');
lines{end+1} = sprintf('Configured profile MCR root: %s', ...
    local_configured_profile_mcr_root(config));
lines{end+1} = sprintf('Executor SLURM_JOB_ID (sidecar): %s', ...
    local_provenance_text(executor_provenance, 'job_id'));
lines{end+1} = sprintf('Executor hostname (OS): %s', ...
    local_provenance_text(executor_provenance, 'hostname'));
lines{end+1} = sprintf('Executor CPU model (OS): %s', ...
    local_provenance_text(executor_provenance, 'cpu_model'));
lines{end+1} = sprintf('Executor architecture (OS): %s', ...
    local_provenance_text(executor_provenance, 'architecture'));
lines{end+1} = sprintf('Executor shell terminal outcome: %s', ...
    local_provenance_text(executor_provenance, 'shell_terminal_outcome'));
lines{end+1} = sprintf('Executor selected MCR root (observed path): %s', ...
    local_provenance_text(executor_provenance, 'selected_mcr_root'));
lines{end+1} = sprintf('Executor selected Runtime library directory: %s', ...
    local_provenance_text(executor_provenance, 'runtime_library_dir'));
lines{end+1} = sprintf('Executor Runtime library directory present: %s', ...
    local_provenance_text(executor_provenance, ...
    'runtime_library_present'));
lines{end+1} = sprintf('Executor Runtime release (metadata read on executor): %s', ...
    local_provenance_text(executor_provenance, 'runtime_release'));
lines{end+1} = sprintf('Recorded build manifest compiler release: %s', ...
    local_provenance_text(executor_provenance, ...
    'build_manifest_compiler_release'));
lines{end+1} = sprintf(['Recorded build manifest required MCR: ', ...
    'version=%s; generation=%s; architecture=%s; root=%s'], ...
    local_provenance_text(executor_provenance, ...
    'build_manifest_mcr_version'), ...
    local_provenance_text(executor_provenance, ...
    'build_manifest_generation'), ...
    local_provenance_text(executor_provenance, 'build_manifest_arch'), ...
    local_provenance_text(executor_provenance, ...
    'build_manifest_mcr_root'));
lines{end+1} = sprintf(['Recorded build identifier (manifest metadata): ', ...
    'source_commit=%s; runner_checksum=%s'], ...
    local_provenance_text(executor_provenance, ...
    'build_manifest_source_commit'), ...
    local_provenance_text(executor_provenance, ...
    'build_manifest_runner_checksum'));
lines{end+1} = '';
lines{end+1} = '--- Configured Scientific Dependencies (not executor observations) ---';
if isfield(config, 'spm_root')
lines{end+1} = sprintf('Configured SPM path: %s', config.spm_root);
end

if isfield(config, 'd2n_root')
    lines{end+1} = sprintf('Configured DICOM-to-NIfTI path: %s', config.d2n_root);
end
if isfield(config, 'aliasing_root')
    lines{end+1} = sprintf('Configured aliasing path: %s', config.aliasing_root);
end
if isfield(config, 'normalization') && isstruct(config.normalization)
    if isfield(config.normalization, 'source_command')
        lines{end+1} = sprintf('Configured FreeSurfer environment: %s', ...
            config.normalization.source_command);
    end
    if isfield(config.normalization, 'child_lib_path')
        lines{end+1} = sprintf('Configured FreeSurfer library path: %s', ...
            config.normalization.child_lib_path);
    end
    if isfield(config.normalization, 'host')
        lines{end+1} = sprintf('Configured normalization host: %s', ...
            config.normalization.host);
    end
end
lines{end+1} = '=== End Summary ===';

if nargin >= 3 && ~isempty(processing_dirs)
    if ischar(processing_dirs)
        processing_dirs = {processing_dirs};
    end
    for jj = 1:length(processing_dirs)
    summary_path = fullfile(processing_dirs{jj}, 'pseudo_CT_profile_summary.txt');
    fid = fopen(summary_path, 'w');
    if fid == -1
        if nargin >= 4 && isstruct(output_context)
            pseudo_CT_output('WARN', output_context, ...
                'Detailed profile summary could not be saved.');
            pseudo_CT_output('INFO', output_context, '    %s', summary_path);
        end
        continue;
    end
    for ii = 1:length(lines)
        fprintf(fid, '%s\n', lines{ii});
    end
    fclose(fid);
    end
    if nargin >= 4 && isstruct(output_context)
        pseudo_CT_output('INFO', output_context, ...
            'Detailed profile summary saved as pseudo_CT_profile_summary.txt.');
    end
end
end

function text = local_join_names(names)
%LOCAL_JOIN_NAMES R2010b-compatible comma join for required outputs.
text = '';
for ii = 1:numel(names)
    if ii > 1
        text = [text ', ']; %#ok<AGROW>
    end
    if ischar(names{ii})
        text = [text strtrim(names{ii})]; %#ok<AGROW>
    end
end
end

function text = local_profile_display_name(profile_name, config)
%LOCAL_PROFILE_DISPLAY_NAME Human-facing name while retaining canonical ID.
text = profile_name;
try
    if isstruct(config) && isfield(config, 'presentation') && ...
            isstruct(config.presentation) && ...
            isfield(config.presentation, 'display_name') && ...
            ischar(config.presentation.display_name) && ...
            ~isempty(strtrim(config.presentation.display_name))
        text = config.presentation.display_name;
    end
catch %#ok<CTCH>
    text = profile_name;
end
end

function value = local_artifact_root(config)
%LOCAL_ARTIFACT_ROOT Artifact root for summary display.
%   The artifact root is the folder that contains the build manifest. Returns
%   '' when the profile has no build manifest path.
value = '';
try
    if isstruct(config) && isfield(config, 'current') && ...
            isstruct(config.current) && ...
            isfield(config.current, 'build_manifest') && ...
            ischar(config.current.build_manifest) && ...
            ~isempty(strtrim(config.current.build_manifest))
        [parent, ~, ~] = fileparts(strtrim(config.current.build_manifest));
        value = parent;
    end
catch %#ok<CTCH>
    value = '';
end
if isempty(value)
    value = '(unknown)';
end
end

function text = local_requested_option(options, field_name)
text = 'Not recorded';
if ~isfield(options, field_name)
    return;
end
value = options.(field_name);
if islogical(value) || (isnumeric(value) && isscalar(value))
    if logical(value)
        text = 'Yes';
    else
        text = 'No';
    end
end
end

function text = local_evidence_text(evidence, field_name)
text = 'Not recorded';
if isfield(evidence, field_name)
    value = evidence.(field_name);
    if ischar(value) && size(value, 1) == 1 && ~isempty(value)
        text = value;
    end
elseif isfield(evidence, 'evidence') && isstruct(evidence.evidence)
    text = local_evidence_text(evidence.evidence, field_name);
elseif isfield(evidence, 'snapshot') && isstruct(evidence.snapshot)
    text = local_evidence_text(evidence.snapshot, field_name);
end
end

function value = local_evidence_struct(evidence, field_name)
value = struct();
if isstruct(evidence) && isfield(evidence, field_name) && ...
        isstruct(evidence.(field_name)) && isscalar(evidence.(field_name))
    value = evidence.(field_name);
elseif isstruct(evidence) && isfield(evidence, 'evidence') && ...
        isstruct(evidence.evidence)
    value = local_evidence_struct(evidence.evidence, field_name);
elseif isstruct(evidence) && isfield(evidence, 'snapshot') && ...
        isstruct(evidence.snapshot)
    value = local_evidence_struct(evidence.snapshot, field_name);
end
end

function text = local_provenance_text(provenance, field_name)
text = 'Not confirmed';
try
    if isstruct(provenance) && isfield(provenance, field_name)
        value = provenance.(field_name);
        if ischar(value) && size(value, 1) == 1 && ...
                ~isempty(strtrim(value)) && ~any(value == char(0)) && ...
                isempty(regexp(value, '[\r\n]', 'once'))
            text = strtrim(value);
        end
    end
catch %#ok<CTCH>
    text = 'Not confirmed';
end
end

function text = local_configured_profile_mcr_root(config)
text = 'Not confirmed';
try
    if isstruct(config) && isfield(config, 'current') && ...
            isstruct(config.current) && isfield(config.current, 'mcr_root') && ...
            ischar(config.current.mcr_root) && ...
            ~isempty(strtrim(config.current.mcr_root))
        text = strtrim(config.current.mcr_root);
    elseif isstruct(config) && isfield(config, 'mlsc') && ...
            isstruct(config.mlsc) && isfield(config.mlsc, 'mcr_root') && ...
            ischar(config.mlsc.mcr_root) && ...
            ~isempty(strtrim(config.mlsc.mcr_root))
        text = strtrim(config.mlsc.mcr_root);
    end
catch %#ok<CTCH>
    text = 'Not confirmed';
end
end
