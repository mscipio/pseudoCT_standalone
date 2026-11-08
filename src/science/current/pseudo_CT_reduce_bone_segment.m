function [Pnew_rc] = pseudo_CT_reduce_bone_segment(Pold_rc)
%PSEUDO_CT_REDUCE_BONE_SEGMENT Reduce the bone class of the segmentation.
%   PNEW_RC = PSEUDO_CT_REDUCE_BONE_SEGMENT(POLD_RC)
%   Applies morphological operations to the six tissue-class images (rc1..rc6).
%   Bone voxels inside the closed and eroded brain mask become CSF, and rc3
%   (WM, plus the remainder) is recomputed from the other classes.
%   POLD_RC is either a 6-row char matrix of rc*.nii paths or a 4D numeric array
%   with the six classes on dimension 4. A non-6-class input prints a message and
%   returns without setting PNEW_RC.
%   For file input, rc3 and rc4 are overwritten in place with SPM and returned
%   as rows 3 and 4 of PNEW_RC; the other rows are not set. For numeric input,
%   PNEW_RC is the new 4D array.
%   Side effects: rewrites the rc3 and rc4 files for file input. Errors: none
%   raised by this function; SPM errors propagate.
%   Minimum supported MATLAB: R2010b.

if isstr(Pold_rc)
    if size(Pold_rc, 1) ~= 6
        disp(sprintf('There are not 6 classes: %d classes', size(Pold_rc, 1)));
        return;
    end
    for ii=1:size(Pold_rc, 1)
        rc(:, :, :, ii) = spm_read_vols(spm_vol(deblank(Pold_rc(ii, :))));
    end
elseif isnumeric(Pold_rc)
    rc = Pold_rc;
    if size(rc, 4) ~= 6
        disp(sprintf('There are not 6 classes: %d classes', size(rc, 4)));
        return;
    end
else
    disp('Input must be either filenames or a 4D matrix!');
    return
end

% Create a brain mask: GM + WM + CSF;
thres_brain = 0.2;
brain_mask_orig = sum(rc(:, :, :, 1:3), 4) > thres_brain;
% Let's do a closure first:
brain_mask = imclose(brain_mask_orig, ones(7,7,7)); % Before was 5,5,5;

% Let's do the filling of holes in the 3 dimensions:
% for ii=1:size(brain_mask, 1)
%     brain_mask(ii, :, :) = imfill(squeeze(brain_mask(ii, :, :)), 8, 'holes');
% end
% for ii=1:size(brain_mask, 2)
%     brain_mask(:, ii, :) = imfill(squeeze(brain_mask(:, ii, :)), 8, 'holes');
% end
% for ii=1:size(brain_mask, 3)
%     brain_mask(:, :, ii) = imfill(squeeze(brain_mask(:, :, ii)), 8, 'holes');
% end

% We can include an erosion to avoid the bone to be very reduced:
brain_mask = imerode(brain_mask, ones(3,3,3)); % This line was not preset in the first version! Let's see how it goes!

% Now let's reassign the new classes with priorities: GM, WM, tissue and
% air will remain the same as before.  Only areas that are re-assigned from
% bone to CSF will change the probability values!
new_rc = rc;
aux = rc(:, :, :, 4); % Bone;
I = find(brain_mask);
aux(I) = 0;
new_rc(:, :, :, 4) = aux;
new_rc(:, :, :, 3) = 1 - sum(new_rc(:, :, :, [1 2 4 5 6]), 4);

% Now let's get the new files (if input was given as filenames! Otherwise
% return the 4D matrix:
if isstr(Pold_rc)
    for ii=3:4%size(Pold_rc, 1)
        Vorig = spm_vol(deblank(Pold_rc(ii, :)));
        Vnew =  Vorig;
        [pathr,fnr,extr] = fileparts(deblank(Pold_rc(ii, :)));
        %Vnew.fname = fullfile(pathr, strcat(fnr, '_new.nii'));
        aux = spm_write_vol(Vorig, new_rc(:, :, :, ii));
        Pnew_rc(ii, 1:length(Vnew.fname)) = Vnew.fname; 
    end
else
    Pnew_rc = new_rc;
end

return