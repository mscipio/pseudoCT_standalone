function pseudo_CT_print_profile_summary(profile_name, config, processing_dirs, output_context)
%PSEUDO_CT_PRINT_PROFILE_SUMMARY Print and save the selected configuration.

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
lines{end+1} = sprintf('Profile:            %s', profile_name);
lines{end+1} = sprintf('Mode:               %s', config.mode);
if isfield(config, 'implementation') && ischar(config.implementation)
    lines{end+1} = sprintf('Implementation:     %s', config.implementation);
end
lines{end+1} = '';
lines{end+1} = '--- Paths ---';
lines{end+1} = sprintf('SPM root:           %s', config.spm_root);
lines{end+1} = sprintf('Batch atlas:        %s', config.atlas_root);
if ~strcmp(config.mode, 'launchpad')
    lines{end+1} = sprintf('Aliasing root:      %s', config.aliasing_root);
end
lines{end+1} = '';
lines{end+1} = '--- Pipeline Parameters ---';
lines{end+1} = sprintf('Recenter:           %s', config.recenter_before_normalization);
lines{end+1} = sprintf('Zero background:    %s', config.zero_background);
lines{end+1} = sprintf('Cleanup on success: %s', mat2str(config.cleanup_on_success));
lines{end+1} = sprintf('Bone enabled:       %s', mat2str(config.bone_enabled));
lines{end+1} = sprintf('FWHM:               %g mm', config.fwhm);
lines{end+1} = sprintf('Aliasing default:   %d', config.aliasing_default);
lines{end+1} = sprintf('PCA backend:        %s', pca_backend);
lines{end+1} = '';
lines{end+1} = '--- I/O Policy ---';
lines{end+1} = sprintf('Reference:          %s', config.io_policy.reference);
lines{end+1} = sprintf('Output:             %s', config.io_policy.output);
lines{end+1} = sprintf('GUI:                %s', config.io_policy.gui);
if ~isempty(config.required_matlab_release)
    lines{end+1} = sprintf('Required MATLAB:    R%s', config.required_matlab_release);
end

if strcmp(config.mode, 'launchpad')
    lines{end+1} = '';
    lines{end+1} = '--- Launchpad Settings ---';
    lines{end+1} = sprintf('Host:               %s', config.launchpad.host);
    lines{end+1} = sprintf('Runner:             %s', config.launchpad.runner);
    lines{end+1} = sprintf('MCR root:           %s', config.launchpad.mcr_root);
    lines{end+1} = sprintf('Queue:              %s', config.launchpad.queue);
    lines{end+1} = sprintf('Scratch:            %s', config.launchpad.scratch);
    lines{end+1} = sprintf('Batch templates:    %s', config.launchpad.batch_templates);
end

if isfield(config, 'implementation') && ischar(config.implementation) && ...
        strcmp(config.implementation, 'current') && ...
        strcmp(config.mode, 'mlsc') && isfield(config, 'current')
    lines{end+1} = '';
    lines{end+1} = '--- MLSC Current Artifact (operator-supplied, pending Gate-A verification) ---';
    lines{end+1} = sprintf('Runner:             %s', config.current.runner);
    lines{end+1} = sprintf('MCR root:           %s', config.current.mcr_root);
    lines{end+1} = sprintf('Build manifest:     %s', config.current.build_manifest);
    lines{end+1} = sprintf('Resource manifest:  %s', config.current.resource_manifest);
    lines{end+1} = sprintf('Artifact root:      %s', local_artifact_root(config));
    lines{end+1} = sprintf('Gate-A record:      %s', local_gate_a_record(config));
    if isfield(config.current, 'required_outputs') && ...
            iscell(config.current.required_outputs)
        lines{end+1} = sprintf('Required outputs:   %s', ...
            local_join_names(config.current.required_outputs));
    end
    lines{end+1} = 'Status:             Real execution fails preflight pending artifact/native evidence.';
    lines{end+1} = '';
    lines{end+1} = '--- MLSC Scheduler ---';
    lines{end+1} = sprintf('Host:               %s', config.mlsc.host);
    lines{end+1} = sprintf('Shell:              %s', config.mlsc.shell);
    lines{end+1} = sprintf('Partition:          %s', config.mlsc.partition);
    lines{end+1} = sprintf('CPUs per task:      %d', config.mlsc.cpus_per_task);
    lines{end+1} = sprintf('Memory:             %s', config.mlsc.memory);
    lines{end+1} = sprintf('Time:               %s', config.mlsc.time);
end

lines{end+1} = '';
lines{end+1} = '--- MATLAB Environment ---';
lines{end+1} = sprintf('Version:            %s', version);
lines{end+1} = sprintf('Release:            %s', version('-release'));
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
