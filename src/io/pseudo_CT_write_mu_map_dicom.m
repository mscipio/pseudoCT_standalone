function pseudo_CT_write_mu_map_dicom(att_map_file, save_dir, umap_fn, temp_dir, varargin)
%PSEUDO_CT_WRITE_MU_MAP_DICOM Write the final pseudo-muMAP DICOM series.
%   PSEUDO_CT_WRITE_MU_MAP_DICOM(ATT_MAP_FILE, SAVE_DIR, UMAP_FN, TEMP_DIR)
%   PSEUDO_CT_WRITE_MU_MAP_DICOM(..., FWHM) and (..., FWHM, OUTPUT_CONTEXT)
%   ATT_MAP_FILE is the att_map.nii path. SAVE_DIR is the output folder for the
%   DICOM series (MR/pseudo_muMAP). UMAP_FN is the reference mu-map DICOM file.
%   TEMP_DIR is the working folder. FWHM (optional, default 0) is the smoothing
%   width in mm; OUTPUT_CONTEXT (optional, after FWHM) is a logging struct.
%   Calls pseudo_CT_mmr_nii2mu_dicom with interpolation 1 and scale 1.
%   Side effects: writes the DICOM series to SAVE_DIR and temporary files to
%   TEMP_DIR. Errors: pseudo_CT_write_mu_map_dicom:MissingAttenuationMap when
%   ATT_MAP_FILE does not exist.
%   Minimum supported MATLAB: R2010b.

FWHM = 0;
if nargin > 4 && isnumeric(varargin{1})
    FWHM = varargin{1};
end

if exist(att_map_file, 'file') ~= 2
    error('pseudo_CT_write_mu_map_dicom:MissingAttenuationMap', 'Pseudo-CT processing finished without creating:\n%s', att_map_file);
end

interp_f = 1;
scale_val = 1;
if nargin > 5 && isstruct(varargin{2})
    pseudo_CT_mmr_nii2mu_dicom(att_map_file, save_dir, umap_fn, interp_f, scale_val, FWHM, temp_dir, varargin{2});
else
    pseudo_CT_mmr_nii2mu_dicom(att_map_file, save_dir, umap_fn, interp_f, scale_val, FWHM, temp_dir);
end