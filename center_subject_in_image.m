% Date: Sept/04/2014;
% Name: center_subject_in_image.m
% Function to center the subject in the middle of the image but leaving it
% in the same space (similar to the anti-aliasing code).

function [P_new, aliasing] = center_subject_in_image(P, varargin)

check_aliasing = 0; % Not check aliasing;
P_new = P;
aliasing = 0;
thres = 5; % Number of planes allowed to differ between front and back ends!

if nargin > 1
    check_aliasing = varargin{1};
end

V_orig = spm_vol(deblank(P(1, :)));
Im_orig = spm_read_vols(V_orig);

[val, pos] = max(abs(V_orig.mat(1:3, 1:3)), [], 1);

% switch pos(3)
%     case 1
%         orientation = 'Sag';
%     case 2
%         orientation = 'Cor';
%     case 3
%         orientation = 'Tra';
%     otherwise
%         disp('There is a problem!!')
%         return
% end

% Smooth the data and mask it: Date: Sept/15/2016;
Im = imgaussian(Im_orig, 2);
[Pf, head_mask] = head_mask_mprage(Im, 60);
Im = Im_orig.*imdilate(head_mask, ones(5,5,5));

[ax] = find(pos == 3); % The axial plane:
[sag] = find(pos == 1); %The side-2-side plane (that form sagital slices);
[Y, I] = max(Im, [], ax);
ed = edge(squeeze(Y), 'canny'); ed = reshape(ed, size(Y));
sum_col = sum(ed, sag); % Sum along the sagital plane (ear to ear);
sum_col = sum_col(:);
[I] = find(sum_col > 1);
dist_nose = I(1) - 1;
[cor] = find(pos == 2); %The nose-2-back plane (that form coronal slices);
dist_back = size(Im, cor) - I(end);

if dist_nose < 2 & dist_back < 2 & check_aliasing % Check for automatic anti-aliasing!
    [P_new, corrected] = automatic_anti_aliasing_nose_2_back(P);
    if corrected == 0
        answ = questdlg(sprintf('Do you want to proceed with the original (uncorrected) image?\n(if No, program will quit!)', 'Yes', 'No', 'No'));
        switch answ
            case 'Yes'
                disp(sprintf('Continuing with original image!'));
            otherwise
                aliasing = 1;
                return
        end
    end
    
elseif abs(dist_back - dist_nose) > thres % Check if image needs recentering! Only if the nose is too close to the border!
    [Y, permute_pos] = sort(pos); % To always select the axial view!
    Im_perm = permute(Im_orig, permute_pos);

    vox_disp = round(abs(dist_nose - dist_back)/2);
    displac = vox_disp*V_orig.hdr.pixdim(cor+1);
    switch sign(dist_back - dist_nose)
        case 1 % More space in the back than in the nose: remove spaces from the back and add them at the front!;
            Im_out = cat(2, Im_perm(:, (end-vox_disp+1):end, :), Im_perm(:, 1:(end-vox_disp), :));
            %params = zeros(1, 3); params(cor) = -displac;
            params = zeros(1, 3); params(2) = displac; % New May/3/2017
        case -1 % Add the planes from the beginning at the end
            Im_out = cat(2, Im_perm(:, (vox_disp+1):end, :), Im_perm(:, 1:vox_disp, :));
            %params = zeros(1, 3); params(cor) = displac;
            params = zeros(1, 3); params(2) = -displac; % New May/3/2017
        otherwise % Nothing here
    end
    % Re-permute the image back to the original shape!:
    Im_out = permute(Im_out, pos);

    % Now save the new image as *_moved*;
    [p, n, e] = fileparts(P);
    new_fn = strcat(p, filesep, n, '_moved.nii');
    copyfile(strcat(p, filesep, n, e(1:4)),  new_fn);
    % Now we need to save the new matrix:
    V_orig.fname = new_fn;
    %V_orig.mat = V_orig.mat*(spm_matrix(params, 'Z*S*R*T')*eye(4));
    V_orig.mat = (spm_matrix(params, 'Z*S*R*T')*eye(4))*V_orig.mat; % New May/3/2017
    aux = spm_write_vol(V_orig, Im_out);
    disp(sprintf('Image has been recentered:\n%s!', new_fn));
    %[Y, aux] = max(Im_orig, [], ax);
    %[Y2, aux] = max(Im_out, [], ax);
    %figure, subplot(1,2,1), imagesc(squeeze(Y)); title('Original');
    %subplot(1,2,2), imagesc(squeeze(Y2)); title('After Recentering');
    P_new = new_fn;
else
    disp('Original image did not need to be recentered!!');
end


return
