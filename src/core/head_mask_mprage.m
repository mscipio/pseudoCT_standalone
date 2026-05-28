% Date: 02/18/2013;
% Name: head_mask_mprage.m;
% Program to generate a head_mask based on the UTE1 images.
% New version, from original head_mask.m.  This time we also perform the
% filling of holes in the 2nd dimension (which seems to be Axial in
% reality!).

function [Pf, head_mask] = head_mask_mprage(varargin)

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
    disp('No image has been written!')
else
    [pathd,fnd,extd] = fileparts(deblank(P));
    fname = fullfile(pathd, 'Atlas_head_mask.nii');
    ok = savenifti(fname, head_mask, V.mat, V.hdr.pixdim(2:4), 'uint8');
    if ok
        disp(sprintf('File saved succesfully:\n%s', fname));
        Pf = fname;
    end
end
    
return