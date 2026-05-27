%  mMR_nii2mu_dicom_blur_david.m
%  Author: Spencer Bowen (adapted from isocenter.m by Dan Chonde)
%  Lab Group: Catana
%  Date: 09-28-2011
%  Register nifti images (*.hdr or *.nii) to spatial frame of reference
%  of the mMR mu-maps and write as a dicom series
%  inputs:  nifti_in   = header file (*.hdr) or single file (*.nii) for the nifti images
%           dir_out    = directory to save the new dicom series mu-map
%	    tfm_file   = slicer3 tranformation matrix file (tfm) to register input data
%		         to the mMR PET spatial frame of reference
%	    mu_ref     = single dicom file (*.ima) of reference MR mu-map image
%	    interp_flag= 0 for near neighbor interpolation, and 1 for tri-linear
%	    scale_val  = scale the raw nifti_in image by a uniform value
%	    sigma      = FWHM (mm) of 3D Gaussian blurring function to smooth images
%       ssh2_conn  = to perform the ssh connextion to Brain-Vision (ssh2_conn = ssh2_config(HOSTNAME,USERNAME,PASSWORD))
%
% Version from David Izquierdo-Garcia, adapted from the one form Spencer
% Bowen, to use SPM code to coreg and blur the images before writing the
% final Dicom images;
%
%  mMR_nii2mu_dicom_blur_david(nifti_in,dir_out,tfm_file,tfm_file,mu_ref,interp_flag, scale_vali, sigma, ssh_log)
function mMR_nii2mu_dicom_blur_david(nifti_in,dir_out,mu_ref,interp_flag, scale_val, sigma)

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
    out_path= dir_out;
else
    [out_path,out_file,out_ext]=fileparts(fullfile(dir_out, filesep));
    if isempty(out_path), out_path = pwd; end
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
nifti_16bit = fullfile(out_path,'nifti_16bit_temp.nii');
V_scale = V;
V_scale.fname = nifti_16bit;
V_scale.dt(1) = 4; % int16;
spm_write_vol(V_scale, Im_scale);

%%%%%%%%%%%%%%%%%%%%%%%%%
% Convert the ref_file into nifti:
[Pnew] = convert_dicom_i_2_nii(mu_ref, 'ref_file.nii', out_path);

%%%%%%%%%%%%%%%%%%%%%%%
% Now reslice the V_scale into the ref_file:
job.ref = {Pnew}; job.source = {nifti_16bit}; job.other = {''};
job.roptions = spm_get_defaults('coreg.write');
spm_run_coreg_reslice(job); % Coreg but not reslice into UTE2 space!
nii_final_out = fullfile(out_path, 'rnifti_16bit_temp.nii');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% write the dicom series
%nii2dcm_header_copyV2(anlz_final_out,mu_ref,out_path); % old version!
nii2dcm_header_copy_vb20_david(nii_final_out,mu_ref,out_path);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% delete temporary files
if exist('nifti_temp','var')
	delete(nifti_temp);
end
% In local:
delete([nifti_16bit]);
delete(nii_final_out);
delete(Pnew);