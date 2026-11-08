function atlas_names = pseudo_CT_check_installed_resources(resources_dir)
%PSEUDO_CT_CHECK_INSTALLED_RESOURCES Fail closed on a missing packaged resource.
%   ATLAS_NAMES = PSEUDO_CT_CHECK_INSTALLED_RESOURCES(RESOURCES_DIR) verifies
%   that the installed resources folder (<package>/resources) holds every file
%   the current pipeline reads: the fixed names below, plus at least one
%   *Atlas*.nii. Returns the sorted atlas basenames (cell column). Any missing
%   file raises pseudo_CT:MissingResource naming its absolute path. The SPM
%   DICOM dictionary is checked separately by pseudo_CT_check_spm_dicom_dict.
%   Used by setup (every installed purpose) and by the worker in direct mode.
%   Minimum supported MATLAB: R2010b.

if ~ischar(resources_dir) || isempty(strtrim(resources_dir))
    error('pseudo_CT:MissingResource', ...
        'Installed resources folder is not set.');
end
fixed = {'ch2.nii'; 'new_segment_batch.mat'; ...
    'dartel_existing_template_batch.mat'; 'create_inverse_warped_batch.mat'; ...
    'Template_1.nii'; 'Template_2.nii'; 'Template_3.nii'; ...
    'Template_4.nii'; 'Template_5.nii'; 'Template_6.nii'; 'TPM.nii'};
for ii = 1:length(fixed)
    required_path = fullfile(resources_dir, fixed{ii});
    if exist(required_path, 'file') ~= 2
        error('pseudo_CT:MissingResource', ...
            'Installed resource missing: %s', required_path);
    end
end
listing = dir(fullfile(resources_dir, '*Atlas*.nii'));
if isempty(listing)
    error('pseudo_CT:MissingResource', ...
        'Installed atlas resource missing: %s', ...
        fullfile(resources_dir, '*Atlas*.nii'));
end
atlas_names = sort({listing.name})';
end
