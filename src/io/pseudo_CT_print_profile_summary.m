function pseudo_CT_print_profile_summary(profile_name, config, processing_dir)
%PSEUDO_CT_PRINT_PROFILE_SUMMARY Print and save the selected configuration.

pca_backend = 'remote';
if strcmp(config.mode, 'local')
    try
        [~, pca_backend] = pseudo_CT_pca_resolver(config);
    catch
        pca_backend = 'unavailable';
    end
end

lines = {};
lines{end+1} = '=== pseudo-CT Profile Summary ===';
lines{end+1} = sprintf('Profile:            %s', profile_name);
lines{end+1} = sprintf('Mode:               %s', config.mode);
lines{end+1} = '';
lines{end+1} = '--- Paths ---';
lines{end+1} = sprintf('SPM root:           %s', config.spm_root);
lines{end+1} = sprintf('Batch atlas:        %s', config.atlas_root);
lines{end+1} = '';
lines{end+1} = '--- Pipeline Parameters ---';
lines{end+1} = sprintf('Recenter:           %s', config.recenter_before_normalization);
lines{end+1} = sprintf('Zero background:    %s', config.zero_background);
lines{end+1} = sprintf('Cleanup on success: %s', mat2str(config.cleanup_on_success));
lines{end+1} = sprintf('Bone enabled:       %s', mat2str(config.bone_enabled));
lines{end+1} = sprintf('FWHM:               %g mm', config.fwhm);
lines{end+1} = sprintf('Aliasing default:   %d', config.aliasing_default);
lines{end+1} = sprintf('PCA backend:        %s', pca_backend);
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

lines{end+1} = '';
lines{end+1} = '--- MATLAB Environment ---';
lines{end+1} = sprintf('Version:            %s', version);
lines{end+1} = sprintf('Release:            %s', version('-release'));
lines{end+1} = '=== End Summary ===';

for ii = 1:length(lines)
    disp(lines{ii});
end

if nargin >= 3 && ~isempty(processing_dir)
    summary_path = fullfile(processing_dir, 'pseudo_CT_profile_summary.txt');
    fid = fopen(summary_path, 'w');
    if fid == -1
        warning('pseudoCT:SummaryWrite', ...
            'Could not save profile summary to %s', summary_path);
        return;
    end
    cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
    for ii = 1:length(lines)
        fprintf(fid, '%s\n', lines{ii});
    end
    disp(sprintf('pseudo-CT: Profile summary saved to %s', summary_path));
end
end
