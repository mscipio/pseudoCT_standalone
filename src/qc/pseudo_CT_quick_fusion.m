function composite = pseudo_CT_quick_fusion(pat_folder, colormap_mat)
%PSEUDO_CT_QUICK_FUSION Build a fused MR/pseudo-CT validation composite.
%   COMPOSITE = PSEUDO_CT_QUICK_FUSION(PAT_FOLDER) uses the bundled QC colormap
%   hot_map_mpitool_1024.mat beside this file.
%   COMPOSITE = PSEUDO_CT_QUICK_FUSION(PAT_FOLDER, COLORMAP_MAT) uses an explicit
%   .mat file instead. It must exist and contain a non-empty numeric
%   my_hot_map_1024; anything else fails closed. An empty COLORMAP_MAT selects
%   the bundled colormap.
%   The composite overlays the pseudo-CT on the MR for the three middle planes
%   (axial, coronal, sagittal) and their maximum-intensity projections, using
%   pseudo_CT_overlay2. It is called by the current compute phase
%   (pseudo_CT_current_compute) to make the validation image.
%   Side effects: reads the NIfTI files in PAT_FOLDER. Minimum supported MATLAB:
%   R2010b. Originally dated 06/25/2016.

pct = 0.5; % Fusion overlay power!
tool_dir = fileparts(mfilename('fullpath'));
if nargin < 2 || isempty(colormap_mat)
    colormap_path = fullfile(tool_dir, 'hot_map_mpitool_1024.mat');
else
    if ~ischar(colormap_mat) || size(colormap_mat, 1) ~= 1 || isempty(strtrim(colormap_mat))
        error('pseudo_CT:QCColormapInvalid', ...
            'QC colormap resource must be a single-row path string.');
    end
    colormap_path = strtrim(colormap_mat);
end
if exist(colormap_path, 'file') ~= 2
    error('pseudo_CT:QCColormapMissing', ...
        'QC colormap resource not found: %s', colormap_path);
end
loaded_map = load(colormap_path);
if ~isfield(loaded_map, 'my_hot_map_1024') || ~isnumeric(loaded_map.my_hot_map_1024) || ...
        isempty(loaded_map.my_hot_map_1024)
    error('pseudo_CT:QCColormapInvalid', ...
        'QC colormap resource is invalid (expected numeric my_hot_map_1024): %s', colormap_path);
end
my_hot_map_1024 = loaded_map.my_hot_map_1024;
map = my_hot_map_1024/255;
composite = 0;

%mr_image = fullfile(pat_folder, 'MR_PET', 'MS_RAGE2.nii');
cd(pat_folder);
listi = cellstr(ls('*normalized.nii'));
if length(listi) == 0
    return;
end
% Get the first one:
mr_image = fullfile(pat_folder, listi{1});
ct_image = fullfile(pat_folder, 'att_map.nii');

try
    mr_im = spm_read_vols(spm_vol(mr_image));
    ct_im = spm_read_vols(spm_vol(ct_image));
catch
    return
end

% Reslice if needed:
if (size(mr_im, 1) ~= size(ct_im, 1)) | (size(mr_im, 2) ~= size(ct_im, 2)) | (size(mr_im, 3) ~= size(ct_im, 3))
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

sag = pseudo_CT_overlay2(sag_mr, sag_ct/max(sag_ct(:)), pct, 0, map);
ax = pseudo_CT_overlay2(ax_mr, ax_ct/max(ax_ct(:)), pct, 0, map);
cor = pseudo_CT_overlay2(cor_mr, cor_ct/max(cor_ct(:)), pct, 0, map);
mip_sag = pseudo_CT_overlay2(mip_sag_mr, mip_sag_ct/max(mip_sag_ct(:)), pct, 0, map);
mip_ax = pseudo_CT_overlay2(mip_ax_mr, mip_ax_ct/max(mip_ax_ct(:)), pct, 0, map);
mip_cor = pseudo_CT_overlay2(mip_cor_mr, mip_cor_ct/max(mip_cor_ct(:)), pct, 0, map);

%zz = zeros(size(ax, 1), size(sag, 2), 3);

composite = [cor sag mip_cor; ax mip_sag mip_ax];

return
