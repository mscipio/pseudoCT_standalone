function pseudo_CT_apply_background_mask(temp_dir, context)
%PSEUDO_CT_APPLY_BACKGROUND_MASK Apply the optional local subject mask.
%   This mode-neutral finalization helper contains the historical Launchpad
%   masking behavior. It deliberately leaves the attenuation map unchanged
%   when the normalized MPRAGE is unavailable or masking cannot be applied.
%
%   Minimum supported MATLAB: R2010b.

if nargin < 2 || ~isstruct(context)
    context = struct();
end

att_map_path = fullfile(temp_dir, 'att_map.nii');
normalized_path = fullfile(temp_dir, 'mprage_normalized.nii');
if exist(normalized_path, 'file') ~= 2
    pseudo_CT_output('WARN', context, ...
        'Background masking skipped because normalized MPRAGE is missing.');
    return;
end

try
    V_att_map = spm_vol(att_map_path);
    att_map = spm_read_vols(V_att_map);
    V_orig = spm_vol(normalized_path);
    orig_mprage = spm_read_vols(V_orig);
    if ~isequal(size(att_map), size(orig_mprage))
        pseudo_CT_output('WARN', context, ...
            'Background masking skipped because NIfTI dimensions differ.');
        return;
    end

    [~, subj_mask] = head_mask_mprage(orig_mprage, 20);
    [L, num] = bwlabeln(subj_mask);
    if num > 1
        component_sizes = zeros(1, num);
        for ii = 1:num
            component_sizes(ii) = sum(L(:) == ii);
        end
        [~, pos_max] = max(component_sizes);
        subj_mask = L == pos_max;
    end
    subj_mask_dil = imdilate(subj_mask, ones(7, 7, 7));
    att_map = att_map .* ((subj_mask_dil + (orig_mprage > 20)) > 0);
    spm_write_vol(V_att_map, att_map);
catch ME_mask
    pseudo_CT_output('WARN', context, 'Background masking skipped: %s', ...
        ME_mask.message);
end
end
