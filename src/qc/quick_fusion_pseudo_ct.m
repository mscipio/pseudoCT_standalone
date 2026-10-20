% Date: Jun/25/2016;
% Name: quick_fusion_pseudo_ct.m;
% Function to quickly display the 3 middle planes (Axial, Coronal and
% Sagital) with the fused view of the MR and Pseudo-CT images;

function composite = quick_fusion_pseudo_ct(pat_folder, colormap_mat)
%QUICK_FUSION_PSEUDO_CT Fused MR/pseudo-CT validation composite (T003 headless seam).
%   COMPOSITE = QUICK_FUSION_PSEUDO_CT(PAT_FOLDER) preserves the legacy
%   default exactly: the QC colormap is the bundled
%   hot_map_mpitool_1024.mat beside this source, and the rendered composite
%   is unchanged.
%   COMPOSITE = QUICK_FUSION_PSEUDO_CT(PAT_FOLDER, COLORMAP_MAT) uses an
%   explicit headless resource location instead of assuming a loose MAT
%   beside source. COLORMAP_MAT must be an existing .mat file containing a
%   non-empty numeric my_hot_map_1024; anything else fails closed.
%   Empty/missing COLORMAP_MAT selects the legacy default.
%
%   Minimum supported MATLAB: R2010b.

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
    % Legacy output: disp('Unable to find a *normalized.nii file');
    return;
end
% Get the first one:
mr_image = fullfile(pat_folder, listi{1});
ct_image = fullfile(pat_folder, 'att_map.nii');

try
    mr_im = spm_read_vols(spm_vol(mr_image));
    ct_im = spm_read_vols(spm_vol(ct_image));
catch
    % Legacy output: disp('Unable to open the nifti files');
    return
end

% Reslice if needed:
if (size(mr_im, 1) ~= size(ct_im, 1)) | (size(mr_im, 2) ~= size(ct_im, 2)) | (size(mr_im, 3) ~= size(ct_im, 3))
    % Legacy output: disp('Reslicing ...');
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
