function pseudo_CT_print_profile_summary(profile_name, config, processing_dirs, output_context, subject_options, run_evidence)
%PSEUDO_CT_PRINT_PROFILE_SUMMARY Print and save the selected configuration.

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
elseif isfield(config, 'implementation') && ischar(config.implementation) && ...
        strcmp(config.implementation, 'current') && ...
        isfield(config, 'pca_order') && iscell(config.pca_order) && ...
        ~isempty(config.pca_order)
    % MLSC current owns its payload PCA order (callable-first); the
    % 'remote' label below describes the legacy compiled backend only.
    pca_backend = local_join_names(config.pca_order);
end

lines = {};
lines{end+1} = '=== pseudo-CT Profile Summary ===';
lines{end+1} = sprintf('Profile:            %s', local_profile_display_name(profile_name, config));
lines{end+1} = sprintf('Canonical profile ID: %s', profile_name);
lines{end+1} = sprintf('Selected mode (configured): %s', config.mode);
if isfield(config, 'implementation') && ischar(config.implementation)
    lines{end+1} = sprintf('Selected implementation (configured): %s', config.implementation);
end
if isfield(run_evidence, 'terminal') && isequal(run_evidence.terminal, true)
    lines{end+1} = 'Actual execution backend: MLSC lifecycle terminal outcome recorded; executor provenance is shown below when available.';
else
    lines{end+1} = 'Actual execution backend: Not confirmed by this pre-dispatch summary.';
end
lines{end+1} = '';
lines{end+1} = '--- Configured Paths ---';
lines{end+1} = sprintf('SPM root:           %s', config.spm_root);
lines{end+1} = sprintf('Batch atlas:        %s', config.atlas_root);
if ~strcmp(config.mode, 'launchpad')
lines{end+1} = sprintf('Configured aliasing root: %s', config.aliasing_root);
end
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

if strcmp(config.mode, 'launchpad')
    lines{end+1} = '';
    lines{end+1} = '--- Configured Launchpad Settings ---';
    lines{end+1} = sprintf('Configured host:    %s', config.launchpad.host);
    lines{end+1} = sprintf('Configured runner:  %s', config.launchpad.runner);
    lines{end+1} = sprintf('Configured MCR root: %s', config.launchpad.mcr_root);
    lines{end+1} = sprintf('Configured queue:   %s', config.launchpad.queue);
    lines{end+1} = sprintf('Configured scratch: %s', config.launchpad.scratch);
    lines{end+1} = sprintf('Configured templates: %s', config.launchpad.batch_templates);
end

if isfield(config, 'legacy') && isstruct(config.legacy)
    lines{end+1} = '';
    lines{end+1} = '--- Configured Legacy Runtime/Artifact (not execution evidence) ---';
    if isfield(config.legacy, 'runner')
        lines{end+1} = sprintf('Configured runner:  %s', config.legacy.runner);
    end
    if isfield(config.legacy, 'mcr_root')
        lines{end+1} = sprintf('Configured MCR root: %s', config.legacy.mcr_root);
    end
    if isfield(config.legacy, 'defaults_mat')
        lines{end+1} = sprintf('Configured defaults MAT: %s', config.legacy.defaults_mat);
    end
    if isfield(config.legacy, 'batch_templates')
        lines{end+1} = sprintf('Configured batch templates: %s', config.legacy.batch_templates);
    end
    lines{end+1} = 'Configured build ID: Not confirmed (no build ID recorded in profile).';
end

if isfield(config, 'implementation') && ischar(config.implementation) && ...
        strcmp(config.implementation, 'current') && ...
        strcmp(config.mode, 'mlsc') && isfield(config, 'current')
    lines{end+1} = '';
    lines{end+1} = '--- MLSC Current Artifact (configured; not execution evidence) ---';
    lines{end+1} = sprintf('Configured runner:  %s', config.current.runner);
    lines{end+1} = sprintf('Configured MCR root: %s', config.current.mcr_root);
    lines{end+1} = sprintf('Configured build manifest: %s', config.current.build_manifest);
    lines{end+1} = 'Build identifier is recorded in the build manifest, not in profile configuration; see Execution Provenance.';
    lines{end+1} = sprintf('Configured resource manifest: %s', config.current.resource_manifest);
    lines{end+1} = sprintf('Configured artifact root: %s', local_artifact_root(config));
    lines{end+1} = sprintf('Configured Gate-A record: %s', local_gate_a_record(config));
    if isfield(config.current, 'required_outputs') && ...
            iscell(config.current.required_outputs)
        lines{end+1} = sprintf('Required outputs:   %s', ...
            local_join_names(config.current.required_outputs));
    end
    lines{end+1} = 'Configured status:  Candidate is gated; runtime validation/execution not confirmed here.';
end

if strcmp(config.mode, 'mlsc') && isfield(config, 'mlsc') && ...
        isstruct(config.mlsc)
    lines{end+1} = '';
    lines{end+1} = '--- Configured MLSC Submission Settings (not observed executor facts) ---';
    fields = {'host', 'runner', 'mcr_root', 'defaults_mat', ...
        'batch_templates', 'shell', 'partition', 'cpus_per_task', ...
        'memory', 'time'};
    labels = {'host', 'runner', 'MCR root', 'defaults MAT', ...
        'batch templates', 'shell', 'partition', 'CPUs/task', ...
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

% Legacy output:
% for ii = 1:length(lines)
%     disp(lines{ii});
% end

if nargin >= 3 && ~isempty(processing_dirs)
    if ischar(processing_dirs)
        processing_dirs = {processing_dirs};
    end
    for jj = 1:length(processing_dirs)
    summary_path = fullfile(processing_dirs{jj}, 'pseudo_CT_profile_summary.txt');
    fid = fopen(summary_path, 'w');
    if fid == -1
        % Legacy output: warning('pseudoCT:SummaryWrite', ...
        %     'Could not save profile summary to %s', summary_path);
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
    % Legacy output: disp(sprintf('pseudo-CT: Profile summary saved to %s', summary_path));
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
%LOCAL_ARTIFACT_ROOT Resolved artifact root for summary display (H).
%   The T007 build layout keeps manifests at the artifact root, so the root
%   is the directory containing the build manifest. R2010b only.
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

function value = local_gate_a_record(config)
%LOCAL_GATE_A_RECORD Resolved Gate-A record for summary display (H).
value = '(none)';
try
    if isstruct(config) && isfield(config, 'current') && ...
            isstruct(config.current) && ...
            isfield(config.current, 'gate_a_record') && ...
            ischar(config.current.gate_a_record) && ...
            ~isempty(strtrim(config.current.gate_a_record))
        value = strtrim(config.current.gate_a_record);
    end
catch %#ok<CTCH>
    value = '(none)';
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
