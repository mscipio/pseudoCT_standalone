function pseudo_CT_print_profile_summary(manifest, processing_dir)
%PSEUDO_CT_PRINT_PROFILE_SUMMARY Print and save full profile configuration.
%   PSEUDO_CT_PRINT_PROFILE_SUMMARY(MANIFEST, PROCESSING_DIR) prints a
%   formatted summary of all active profile settings to the console and
%   saves it to PROCESSING_DIR/pseudo_CT_profile_summary.txt.
%
%   The summary replaces the previous single-line SPM tree printout.

%% === Resolve actual PCA backend ===
pca_backend = 'unknown';
try
    [~, pca_backend, ~] = pseudo_CT_pca_resolver(manifest);
catch
    % Launchpad remote PCA or invalid config — leave as 'unknown'
end

%% === Build summary lines ===
lines = {};
lines{end+1} = sprintf('=== pseudo-CT Profile Summary ===');
lines{end+1} = sprintf('Profile:            %s', manifest.name);
lines{end+1} = '';
lines{end+1} = sprintf('--- Paths ---');
lines{end+1} = sprintf('SPM root:           %s', manifest.spm_root);
lines{end+1} = sprintf('Batch atlas:        %s', manifest.atlas_assets.batch_atlas_path);
lines{end+1} = sprintf('Vers path:          %s', manifest.vers_path);
lines{end+1} = '';
lines{end+1} = sprintf('--- Pipeline Parameters ---');
lines{end+1} = sprintf('Recenter:           %s', manifest.recenter);
lines{end+1} = sprintf('Zero background:    %s', manifest.zero_background);
lines{end+1} = sprintf('Cleanup policy:     %s', manifest.cleanup_policy);
lines{end+1} = sprintf('Bone enabled:       %s', mat2str(manifest.bone_enabled));
lines{end+1} = sprintf('FWHM:               %d mm', manifest.fwhm);
lines{end+1} = sprintf('Aliasing default:   %d', manifest.aliasing_default);
lines{end+1} = sprintf('PCA backend:        %s', pca_backend);
lines{end+1} = sprintf('Runtime guard:      %s', manifest.runtime_guard);
lines{end+1} = '';
lines{end+1} = sprintf('--- VERS Override Order ---');
for ii = 1:length(manifest.vers_policy.order)
    lines{end+1} = sprintf('  %d. %s', ii, manifest.vers_policy.order{ii});
end

% Launchpad-specific settings
if ~isempty(fieldnames(manifest.launchpad_identity))
    lines{end+1} = '';
    lines{end+1} = sprintf('--- Launchpad Settings ---');
    li = manifest.launchpad_identity;
    if isfield(li, 'host'),          lines{end+1} = sprintf('Host:               %s', li.host); end
    if isfield(li, 'runner'),        lines{end+1} = sprintf('Runner:             %s', li.runner); end
    if isfield(li, 'mcr_root'),      lines{end+1} = sprintf('MCR root:           %s', li.mcr_root); end
    if isfield(li, 'queue'),         lines{end+1} = sprintf('Queue:              %s', li.queue); end
    if isfield(li, 'scratch'),       lines{end+1} = sprintf('Scratch:            %s', li.scratch); end
    if isfield(li, 'batch_templates'), lines{end+1} = sprintf('Batch templates:    %s', li.batch_templates); end
    if isfield(li, 'backend_spm_version'), lines{end+1} = sprintf('Backend SPM:        %s', li.backend_spm_version); end
    if isfield(li, 'backend_runtime'),     lines{end+1} = sprintf('Backend runtime:    %s', li.backend_runtime); end
end

lines{end+1} = '';
lines{end+1} = sprintf('--- MATLAB Environment ---');
lines{end+1} = sprintf('Version:            %s', version);
lines{end+1} = sprintf('Release:            %s', version('-release'));
if isfield(manifest, 'provenance') && isfield(manifest.provenance, 'expected_spm_version')
    if ~isempty(manifest.provenance.expected_spm_version)
        lines{end+1} = sprintf('Expected SPM:       %s', manifest.provenance.expected_spm_version);
    end
end
lines{end+1} = sprintf('=== End Summary ===');

%% === Print to console ===
for ii = 1:length(lines)
    disp(lines{ii});
end

%% === Save to file ===
if nargin >= 2 && ~isempty(processing_dir)
    summary_path = fullfile(processing_dir, 'pseudo_CT_profile_summary.txt');
    fid = fopen(summary_path, 'w');
    if fid ~= -1
        for ii = 1:length(lines)
            fprintf(fid, '%s\n', lines{ii});
        end
        fclose(fid);
        disp(sprintf('pseudo-CT: Profile summary saved to %s', summary_path));
    else
        warning('pseudoCT:SummaryWrite', 'Could not save profile summary to %s', summary_path);
    end
end

end
