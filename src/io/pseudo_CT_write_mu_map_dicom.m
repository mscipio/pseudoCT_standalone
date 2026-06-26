function pseudo_CT_write_mu_map_dicom(att_map_file, save_dir, umap_fn, temp_dir, varargin)

FWHM = 0;
if nargin > 4 && isnumeric(varargin{1})
    FWHM = varargin{1};
end

if exist(att_map_file, 'file') ~= 2
    error('pseudo_CT_write_mu_map_dicom:MissingAttenuationMap', 'Pseudo-CT processing finished without creating:\n%s', att_map_file);
end

interp_f = 1;
scale_val = 1;
mMR_nii2mu_dicom_blur_david(att_map_file, save_dir, umap_fn, interp_f, scale_val, FWHM, temp_dir);