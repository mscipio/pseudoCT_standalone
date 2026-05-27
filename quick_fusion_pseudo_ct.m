% Date: Jun/25/2016;
% Name: quick_fusion_pseudo_ct.m;
% Function to quickly display the 3 middle planes (Axial, Coronal and
% Sagital) with the fused view of the MR and Pseudo-CT images;

function composite = quick_fusion_pseudo_ct(pat_folder)

pct = 0.5; % Fusion overlay power!
load('hot_map_mpitool_1024.mat');
map = my_hot_map_1024/255;
composite = 0;

%mr_image = fullfile(pat_folder, 'MR_PET', 'MS_RAGE2.nii');
cd(pat_folder);
listi = cellstr(ls('*normalized.nii'));
if length(listi) == 0
    disp('Unable to find a *normalized.nii file');
    return;
end
% Get the first one:
mr_image = fullfile(pat_folder, listi{1});
ct_image = fullfile(pat_folder, 'att_map.nii');

try
    mr_im = spm_read_vols(spm_vol(mr_image));
    ct_im = spm_read_vols(spm_vol(ct_image));
catch
    disp('Unable to open the nifti files');
    return
end

% Reslice if needed:
if (size(mr_im, 1) ~= size(ct_im, 1)) | (size(mr_im, 2) ~= size(ct_im, 2)) | (size(mr_im, 3) ~= size(ct_im, 3))
    disp('Reslicing ...');
    P(1, :) = mr_image;
    P(2, 1:length(ct_image)) = ct_image;
    flg.mean  = 0; % Don't create a mean image;
    flg.which = 1; % Don't reslice the first image;
    flg.mask  = 0; % Don't mask;
    flg.interp = 7; % 7th degree bspline;
    flg.wrap = [0 0 0]; % No wrapping;
    ct_im = spm_reslice_david(P, flg);
end

% Get the different slices:
cor_mr = rot90(mr_im(:, :, round(size(mr_im, 3)/2)), -1);
cor_ct = rot90(ct_im(:, :, round(size(ct_im, 3)/2)), -1);
ax_mr = rot90(squeeze(mr_im(:, round(size(mr_im, 2)/2), :)));
ax_ct = rot90(squeeze(ct_im(:, round(size(ct_im, 2)/2), :)));
sag_mr = (squeeze(mr_im(round(size(mr_im, 2)/2), :, :)));
sag_ct = (squeeze(ct_im(round(size(ct_im, 2)/2), :, :)));
mip_cor_mr = rot90(squeeze(max(mr_im, [], 3)), -1);
mip_cor_ct = rot90(squeeze(max(ct_im, [], 3)), -1);
mip_ax_mr = rot90(squeeze(max(mr_im, [], 2)));
mip_ax_ct = rot90(squeeze(max(ct_im, [], 2)));
mip_sag_mr = (squeeze(max(mr_im, [], 1)));
mip_sag_ct = (squeeze(max(ct_im, [], 1)));

sag = toverlay2(sag_mr, sag_ct/max(sag_ct(:)), pct, 0, map);
ax = toverlay2(ax_mr, ax_ct/max(ax_ct(:)), pct, 0, map);
cor = toverlay2(cor_mr, cor_ct/max(cor_ct(:)), pct, 0, map);
mip_sag = toverlay2(mip_sag_mr, mip_sag_ct/max(mip_sag_ct(:)), pct, 0, map);
mip_ax = toverlay2(mip_ax_mr, mip_ax_ct/max(mip_ax_ct(:)), pct, 0, map);
mip_cor = toverlay2(mip_cor_mr, mip_cor_ct/max(mip_cor_ct(:)), pct, 0, map);

%zz = zeros(size(ax, 1), size(sag, 2), 3);

composite = [cor sag mip_cor; ax mip_sag mip_ax];

return