function [Pf, head_mask] = pseudo_CT_head_mask_mprage(varargin)
%PSEUDO_CT_HEAD_MASK_MPRAGE Create a head mask from an MR volume.
%   [PF, HEAD_MASK] = PSEUDO_CT_HEAD_MASK_MPRAGE(IMAGE, THRESHOLD)
%   IMAGE is a char path to a NIfTI file or a numeric volume. THRESHOLD is
%   optional (default 20): voxels above it are head candidates. Holes are
%   filled in all three planes, and the mask is eroded with a 7x7x7 cube.
%   HEAD_MASK is the logical head mask, the same size as the input volume.
%   PF is the path of the written Atlas_head_mask.nii (saved beside a file input
%   as uint8), or '' for a numeric input.
%   The no-argument form opens an SPM image picker and is for interactive use
%   only; the pipeline always passes IMAGE.
%   Side effects: writes Atlas_head_mask.nii beside a file input. Errors: none
%   raised by this function; SPM errors propagate.
%   Originally dated 02/18/2013. Minimum supported MATLAB: R2010b.

Pf = '';
head_mask = [];

thres = 20; % Initialize the threshold in case no value is passed as input!
im_input = 0;

if nargin == 2
    thres = varargin{2};
    im_input = 1;
elseif nargin == 1
    im_input = 1;
else
    im_input = 0;
end

if im_input
    if ischar(varargin{1})
        P = varargin{1};
        V = spm_vol(P);
        Im = spm_read_vols(V);
    else
        P = '';
        Im = varargin{1};
    end
else
    P = spm_select(1, 'image', 'Select the MR image to create the head mask (usually UTE_1)!');
    V = spm_vol(P);
    Im = spm_read_vols(V);
end

head_mask = Im > thres;

% Now in 2nd dimension:
for ii=1:size(Im, 2)
    head_mask(:, ii, :) = imfill(squeeze(head_mask(:, ii, :)), 'holes');
end

% Now in axial: imfill:
for ii=1:size(Im, 3)
    head_mask(:, :, ii) = imfill(head_mask(:, :, ii), 'holes');
end

% Now in saggital:
for ii=1:size(Im, 1)
    head_mask(ii, :, :) = imfill(squeeze(head_mask(ii, :, :)), 'holes');
end

% Now in 2nd dimension again:
for ii=1:size(Im, 2)
    head_mask(:, ii, :) = imfill(squeeze(head_mask(:, ii, :)), 'holes');
end

% Let's just erode the image a tiny little bit (if threshold was set a
% little bit too low on the UTE!):
head_mask = imerode(head_mask, ones(7,7,7)); % Original;
%%head_mask = imerode(head_mask, ones(5,5,5));

% Now write the image into a file:
if size(P,1) == 0
    % Legacy output: disp('No image has been written!')
else
    [pathd,fnd,extd] = fileparts(deblank(P));
    fname = fullfile(pathd, 'Atlas_head_mask.nii');
    ok = savenifti(fname, head_mask, V.mat, V.hdr.pixdim(2:4), 'uint8');
    if ok
        % Legacy output: disp(sprintf('File saved succesfully:\n%s', fname));
        Pf = fname;
    end
end
    
return
