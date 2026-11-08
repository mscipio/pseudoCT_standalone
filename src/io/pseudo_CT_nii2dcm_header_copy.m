function pseudo_CT_nii2dcm_header_copy(nifti_in,dcm_ref,dcm_out)
%PSEUDO_CT_NII2DCM_HEADER_COPY Write a NIfTI volume as a DICOM series with reference metadata.
%   PSEUDO_CT_NII2DCM_HEADER_COPY(NIFTI_IN, DCM_REF, DCM_OUT)
%   NIFTI_IN is the NIfTI file (.nii or .hdr) with the image data. DCM_REF is
%   one file of the reference DICOM series; its header metadata and SeriesNumber
%   are copied into the new series. DCM_OUT is the output folder, created when
%   missing (pwd when empty).
%   The volume is flipped along its second dimension before writing, and the
%   images are written as DICOM slices, one file per slice, reusing the padding
%   and metadata layout of the reference series.
%   Side effects: creates DCM_OUT when missing and writes the DICOM files there.
%   Errors: nii2dcm_header_copy_vb20_david:CreateOutputDirFailed (identifier kept
%   for compatibility). Calls with fewer than three arguments open interactive
%   pickers that reference undefined variables; always pass all three.
%   Origin: Spencer Bowen (2011), adapted by David Izquierdo to reorient the
%   volume to eye(4). Minimum supported MATLAB: R2010b.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% define constants
%addpath('/home/slbowen/work/PVE_correction/code/DicomTagsReadWrite');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% load the input file
if nargin<1
[nifti_file,nifti_path,~]=uigetfile('*.nii;*.hdr', 'Pick a nifti file to transform');
    nifti_in=fullfile(dcm_path,dcm_file);
else 
    [nifti_in_path, nifti_in_file, nifti_in_ext] = fileparts(nifti_in);
    if isempty(nifti_in_path), nifti_in_path = pwd; end
end

% load the reference file
if nargin<2
    [dcm_ref_file,dcm_ref_path,~]=uigetfile('*.dcm;*.ima', 'Pick a reference dicom file to copy metadata from');
    dcm_ref=fullfile(dcm_ref_path,dcm_ref_file);
else
    [dcm_ref_path, dcm_ref_file, dcm_ref_ext] = fileparts(dcm_ref);
    if isempty(dcm_ref_path), dcm_ref_path = pwd; end
end
% reference extension
dcm_ref_ext = char(regexp(dcm_ref,'.\w{3,3}$','match'));	

% generate the output suffix
if nargin<3
    [dcm_out_path]=ugetdir(pwd, 'Choose output directory for new dicom series');
else
	dcm_out_path = dcm_out;
	if isempty(dcm_out_path), dcm_out_path = pwd; end
	if exist(dcm_out_path, 'dir') ~= 7
		[success, msg] = mkdir(dcm_out_path);
		if success == 0
			error('nii2dcm_header_copy_vb20_david:CreateOutputDirFailed', 'Could not create output folder %s: %s', dcm_out_path, msg);
		end
	end
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% read the input nifti images
V = spm_vol(nifti_in);
nifti_in_dims = V.dim;
% scale volume by 1.0e4;
nifti_vol    = double(spm_read_vols(V));

%%%%%%%%
% Flip dimension 2 on axial:
nifti_vol = flipdim(nifti_vol, 2);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% read the reference metdata
%dicom_ref_all = dir(fullfile(dcm_ref_path,['*' dcm_ref_ext])); % Original
dicom_ref_all = dir(fullfile(dcm_ref_path,[dcm_ref_file(1:2), '*'])); % For images like in Julie collab
dicom_ref_info= dicominfo(dcm_ref);
% determine the length of the dicom metadata
% length of the image data
img_bytes = double(dicom_ref_info.Rows)*double(dicom_ref_info.Columns)*double(dicom_ref_info.BitsAllocated)/8;
% read the dicom image for all files with the same series id
dicom_ref_meta= cell(1);
pad_ref_meta  = cell(1);
file_out_name = cell(1);
slice_ref_total= 0;
for m=1:numel(dicom_ref_all)
    test_info=dicominfo(fullfile(dcm_ref_path,dicom_ref_all(m).name));
    if  test_info.SeriesNumber==dicom_ref_info.SeriesNumber
        dicom_slice_number=test_info.InstanceNumber;
	%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
	% determine if DataSetTrailingPadding was used and adjust accordingly
	fid = fopen(fullfile(dcm_ref_path,dicom_ref_all(m).name),'rb');
	fseek(fid,dicom_ref_all(m).bytes-max(round(0.04*img_bytes),200),0);
	pad_length= 0;
	temp_tag  = zeros([1 4]);
	while ~feof(fid) && (numel(temp_tag)==4)
		temp_tag = fread(fid,4,'uint16',0,'ieee-le');
		if numel(temp_tag)<4
			continue;
		end
		if (mean(temp_tag'==[65532 65532 16975 0]))==1
			% data has DataSetTrailingPadding present
			pad_length = fread(fid,1,'uint32',0,'ieee-le');
			junk_dat =fread(fid,pad_length+1,'uint8');
			if feof(fid)
				pad_length = pad_length+3*4; % for metadata length
				break;
			else
				fseek(fid,-pad_length-1,0);
			end
		end
		fseek(fid,-7,0);
    end
    fclose(fid); % Add by David Izquierdo (to close all fid fopen)!
	% determine the length of the dicom metadata
	header_bytes  = dicom_ref_all(m).bytes - img_bytes-pad_length;
	% read in the raw byte data
	fid_temp = fopen(fullfile(dcm_ref_path,dicom_ref_all(m).name),'rb');
	dcm_temp = fread(fid_temp,header_bytes,'uint8');
	if pad_length
		fseek(fid_temp,img_bytes,0);
		pad_temp = fread(fid_temp,inf,'uint8');
		pad_ref_meta{dicom_slice_number} = pad_temp;
	else
		pad_ref_meta{dicom_slice_number} = '';
	end
	fclose(fid_temp);
	dicom_ref_meta{dicom_slice_number} = dcm_temp;
	slice_ref_total = slice_ref_total+1;
	file_out_name{dicom_slice_number}  = dicom_ref_all(m).name;
    end
end

series_num = dicom_ref_info.SeriesNumber;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% ensure that input and output images are the same dimensions
if (dicom_ref_info.Rows ~= nifti_in_dims(2)) || (dicom_ref_info.Columns ~= nifti_in_dims(1))...
   || (slice_ref_total ~= nifti_in_dims(3))
	error('pseudo_CT:DICOMDimensionMismatch', ...
	    ['NIfTI dimensions [%d %d %d] do not match DICOM dimensions ', ...
	     '[%d %d %d].'], nifti_in_dims(1), nifti_in_dims(2), ...
	    nifti_in_dims(3), dicom_ref_info.Columns, dicom_ref_info.Rows, ...
	    slice_ref_total);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% write the new dicom series with the copied metadata
for m=1:slice_ref_total
	out_file = fullfile(dcm_out_path,file_out_name{m});	
	% open the data file and write meta and image data
	fid_out = fopen(out_file,'wb');
	fwrite(fid_out,char(dicom_ref_meta{m}),'uint8',0,'ieee-le');
	fwrite(fid_out,nifti_vol(:,:,m),'uint16',0,'ieee-le'); % Original
    if ~isempty(pad_ref_meta{m})
		fwrite(fid_out,char(pad_ref_meta{m}),'uint8',0,'ieee-le');
	end
	%fwrite(fid_out,nifti_vol(:,:,slice_ref_total-m+1),'uint16',0,'ieee-le');
	fclose(fid_out);
end
