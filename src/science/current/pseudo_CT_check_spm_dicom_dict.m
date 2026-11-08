function dict_path = pseudo_CT_check_spm_dicom_dict(resources_dir)
%PSEUDO_CT_CHECK_SPM_DICOM_DICT Join and verify the packaged SPM DICOM dictionary.
%   DICT_PATH = PSEUDO_CT_CHECK_SPM_DICOM_DICT(RESOURCES_DIR) puts RESOURCES_DIR
%   first on the MATLAB path, then verifies that RESOURCES_DIR/spm_dicom_dict.mat
%   exists, resolves by its bare name (spm_dicom_headers loads it that way),
%   loads, and holds a non-empty struct. Returns the absolute path.
%   Errors: pseudo_CT:SpmDicomDictMissing (absent, or not the bare-name
%   resolution), pseudo_CT:SpmDicomDictUnreadable (load fails or empty). The
%   message names the expected path. Minimum supported MATLAB: R2010b.

if ~ischar(resources_dir) || isempty(resources_dir)
    error('pseudo_CT:SpmDicomDictMissing', ...
        'SPM DICOM dictionary resources folder is not set.');
end
dict_path = fullfile(resources_dir, 'spm_dicom_dict.mat');
if exist(dict_path, 'file') ~= 2
    error('pseudo_CT:SpmDicomDictMissing', ...
        'SPM DICOM dictionary not found: %s', dict_path);
end
addpath(resources_dir, '-begin');
resolved = which('spm_dicom_dict.mat');
if ~strcmp(resolved, dict_path)
    error('pseudo_CT:SpmDicomDictMissing', ...
        'SPM DICOM dictionary does not resolve by bare name to %s (resolves to: %s)', ...
        dict_path, resolved);
end
try
    dict = load(dict_path);
catch ME
    error('pseudo_CT:SpmDicomDictUnreadable', ...
        'SPM DICOM dictionary cannot be read: %s (%s)', dict_path, ME.message);
end
if ~isstruct(dict) || isempty(fieldnames(dict))
    error('pseudo_CT:SpmDicomDictUnreadable', ...
        'SPM DICOM dictionary is empty or not a struct: %s', dict_path);
end
end
