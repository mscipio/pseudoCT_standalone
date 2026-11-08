function pseudo_CT_mmr_nii2mu_dicom(nifti_in,dir_out,mu_ref,interp_flag, scale_val, sigma, temp_dir, output_context)
%PSEUDO_CT_MMR_NII2MU_DICOM Write an attenuation map as an mMR mu-map DICOM series.
%   PSEUDO_CT_MMR_NII2MU_DICOM(NIFTI_IN, DIR_OUT, MU_REF, INTERP_FLAG, SCALE_VAL,
%   SIGMA, TEMP_DIR, OUTPUT_CONTEXT)
%   Registers NIFTI_IN to the reference mu-map MU_REF, optionally smooths it,
%   and writes the DICOM series to DIR_OUT.
%   NIFTI_IN is the NIfTI file to convert (att_map.nii in the pipeline).
%   DIR_OUT is the output folder; it is created when missing and defaults to pwd
%   when empty. MU_REF is one DICOM file of the reference mu-map, used as the
%   metadata template. INTERP_FLAG is optional; it is not used by the current
%   registration step, which takes its settings from spm_get_defaults('coreg.write').
%   SCALE_VAL is optional (default 1): the image is multiplied by SCALE_VAL and
%   by 1e4, rounded, and stored as int16. SIGMA is optional: the FWHM in mm of a
%   3D Gaussian smoothing, where 0 (default) means no smoothing. TEMP_DIR is
%   optional (default DIR_OUT). OUTPUT_CONTEXT is an optional logging struct;
%   when present, the reference conversion uses pseudo_CT_convert_dicom_quiet,
%   otherwise dcm2nii.
%   Side effects: creates DIR_OUT and TEMP_DIR when missing; writes temporary
%   NIfTI files in TEMP_DIR (nifti_16bit_temp.nii, rnifti_16bit_temp.nii,
%   ref_file.nii) and deletes the 16-bit input when finished. Writes the DICOM
%   series through pseudo_CT_nii2dcm_header_copy.
%   Errors: mMR_nii2mu_dicom_blur_david:CreateOutputDirFailed and
%   mMR_nii2mu_dicom_blur_david:CreateTempDirFailed (identifiers kept for
%   compatibility). Calls with no arguments open interactive pickers that
%   reference undefined variables; always pass NIFTI_IN and MU_REF.
%   Origin: Spencer Bowen (2011), adapted by David Izquierdo-Garcia to use SPM
%   for coregistration and blurring. Minimum supported MATLAB: R2010b.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% load the input file
current_dir=pwd;
if nargin<1
    [nifti_file,nifti_path,~]=uigetfile('*.nii;*.hdr', 'Pick a nifti file to transform');
    nifti_in=fullfile(dcm_path,dcm_file);
end

[nifti_path,filename,ext]=fileparts(nifti_in);
nifti_file=strcat(filename,ext);
if isempty(nifti_path)
    nifti_path=pwd;
end

if nargin<2
    dir_out=uigetdir(current_dir,'Select folder to write mu-map dicom series');
end
if isempty(dir_out)
    dir_out = pwd;
end
if nargin<7 || ~ischar(temp_dir) || isempty(strtrim(temp_dir))
    temp_dir = dir_out;
end
if exist(dir_out, 'dir') ~= 7
    [success, msg] = mkdir(dir_out);
    if success == 0
        error('mMR_nii2mu_dicom_blur_david:CreateOutputDirFailed', 'Could not create output folder %s: %s', dir_out, msg);
    end
end
if exist(temp_dir, 'dir') ~= 7
    [success, msg] = mkdir(temp_dir);
    if success == 0
        error('mMR_nii2mu_dicom_blur_david:CreateTempDirFailed', 'Could not create temp folder %s: %s', temp_dir, msg);
    end
end
 
if nargin<4
    interp_flag = 0;
end

if nargin<5
    scale_val   = 1;
end

if nargin<6
    smooth_image = 0;
    sigma        = 0;
elseif sigma==0
    smooth_image = 0;
    kvox_str     = '0';
else 
    smooth_image = 1;
    kvox_str     = '64';
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Read in the nifti file
% load the nifti header
V = spm_vol(nifti_in);
Im = spm_read_vols(V);
Im_scale = scale_val*round(1.0e4*Im);

% sigma = FWHM/(2*sqrt(2*ln(2)));
sigma = sigma/(2*sqrt(2*log(2)));

%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Smooth it if required by user:
if smooth_image
    x=-ceil(kvox_str/2):ceil(kvox_str/2);
    Hx = exp(-(x.^2/(2*((sigma/double(V.hdr.pixdim(3)))^2)))); % Heigth
    Hx = Hx/sum(Hx(:));
    Hx = reshape(Hx, [length(Hx) 1]);
    Hy = exp(-(x.^2/(2*((sigma/double(V.hdr.pixdim(2)))^2)))); % Width
    Hy = Hy/sum(Hy(:));
    Hy = reshape(Hy, [1 length(Hy)]);
    H = exp(-(x.^2/(2*((sigma/double(V.hdr.pixdim(4)))^2)))); % Depth
    H = H/sum(H(:));
    Hz = reshape(H, [1 1 length(H)]);
    Im_scale=imfilter(imfilter(imfilter(Im_scale,Hx, 'same' ,'replicate'),Hy, 'same' ,'replicate'),Hz, 'same' ,'replicate');
end

% write to temporary file
nifti_16bit = fullfile(temp_dir,'nifti_16bit_temp.nii');
V_scale = V;
V_scale.fname = nifti_16bit;
V_scale.dt(1) = 4; % int16;
spm_write_vol(V_scale, Im_scale);

%%%%%%%%%%%%%%%%%%%%%%%%%
% Convert the ref_file into nifti:
if nargin >= 8 && isstruct(output_context)
    % Pipeline callers pass their event context: converter output goes to the
    % run log only, never to the public console/JSONL.
    Pnew = pseudo_CT_convert_dicom_quiet(mu_ref, fullfile(temp_dir, 'ref_file.nii'), output_context);
else
    Pnew = dcm2nii(mu_ref, fullfile(temp_dir, 'ref_file.nii'), 'Overwrite', true);
end

%%%%%%%%%%%%%%%%%%%%%%%
% Now reslice the V_scale into the ref_file:
job.ref = {Pnew}; job.source = {nifti_16bit}; job.other = {''};
job.roptions = spm_get_defaults('coreg.write');
spm_run_coreg_reslice(job); % Coreg but not reslice into UTE2 space!
nii_final_out = fullfile(temp_dir, 'rnifti_16bit_temp.nii');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% write the dicom series
pseudo_CT_nii2dcm_header_copy(nii_final_out,mu_ref,dir_out);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% delete temporary files
if exist('nifti_temp','var')
	delete(nifti_temp);
end
% In local:
delete([nifti_16bit]);
delete(nii_final_out);
delete(Pnew);
