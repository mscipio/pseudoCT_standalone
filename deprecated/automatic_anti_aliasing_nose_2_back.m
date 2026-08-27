% Date: Sept/10/2014;
% Name: automatic_anti_aliasing_nose_2_back.m;
% Function to try to do an automatic anti-aliasing correction on the
% nose-2-back aliasing (the most common one).

function [Pnew, corrected] = automatic_anti_aliasing_nose_2_back(P)

thres_aliasing = 2;
Pnew = P;
corrected = -1; % = -1 No aliasing; = 0 aliasing but not corrected; = 1 corrected;
flip_nb = 0; % Initially we think the image is not flipped nose-2-back;

V_orig = spm_vol(deblank(P(1, :)));
Im_orig = spm_read_vols(V_orig);

[val, pos] = max(abs(V_orig.mat(1:3, 1:3)), [], 1);

[ax] = find(pos == 3); % The axial plane:
[sag] = find(pos == 1); %The side-2-side plane (that form sagital slices);
[Y, I] = max(Im_orig, [], ax);
ed = edge(squeeze(Y), 'canny'); ed = reshape(ed, size(Y));
sum_col = sum(ed, sag); % Sum along the sagital plane (ear to ear);
sum_col = sum_col(:);
[I] = find(sum_col > 1);
dist_nose = I(1) - 1;
[cor] = find(pos == 2); %The nose-2-back plane (that form coronal slices);
dist_back = size(Im_orig, cor) - I(end);

% Check if nose to back is flipped:
p1 = inv(V_orig.mat)*[0 0 0 1]';
p2 = inv(V_orig.mat)*[0 100 0 1]';
dd = p2(cor) - p1(cor);
if dd > 0
    flip_nb = 1;
    Im_orig = flipdim(Im_orig, cor);
end

[Y, permute_pos] = sort(pos); % To always select the axial view!
Im_perm = permute(Im_orig, permute_pos);

if dist_nose < thres_aliasing & dist_back < thres_aliasing
    % First see whether with the edges may work:
    [Y, I] = max(Im_orig, [], ax);
    ed = edge(squeeze(Y), 'canny'); ed = reshape(ed, size(Y));
    sum_col = sum(ed, sag); % Sum along the sagital plane (ear to ear);
    sum_col = sum_col(:); sum_col = sum_col(1:end-1);
    [pos_z] = find(sum_col == 0); pos_z = pos_z(find(pos_z > size(Im_orig, cor)/2));
    if length(pos_z) > 0
        pos_mini = round(mean(pos_z(:)));
    else
        % If not, try the classical one:
        [Y, I] = max(Im_orig, [], ax);
        sum_col = sum(Y, sag); sum_col = sum_col(:)/(size(Im_orig, sag));
        [maxi, pos_max] = max(sum_col(:)); sum_col2 = sum_col; sum_col2(1:pos_max) = maxi;
        [mini, pos_mini] = min(sum_col2(:));
    end
    if pos_mini == size(Im_orig, cor) % Look for a different one!
        Im_s = imgaussian(Y, 2);
        sum_col2 = sum(Im_s, sag); sum_col2 = sum_col2(:)/(size(Im_orig, sag));
        c = conv(sum_col2, [1 -2 1], 'same');
        [pks, loc] = findpeaks(c(1:(end-1)));
        cut_plane = loc(end);
    else
        cut_plane = pos_mini;
    end
    vox_disp = size(Im_orig, cor) - cut_plane + 1;
    displac = vox_disp*V_orig.hdr.pixdim(cor+1);
    if sum_col(1) == 0
        init_plane = 1; % Skip the first plane, as there is nothing!
    else
        init_plane = 0;
    end
    Im_out = cat(2, Im_perm(:, 1:init_plane, :), Im_perm(:, cut_plane:end, :), Im_perm(:, (init_plane+1):(cut_plane-1), :));
    %params = zeros(1, 3); params(cor) = -displac; if flip_nb, params(cor) = displac; end
    params = zeros(1, 3); params(2) = displac; if flip_nb, params(2) = -displac; end % New May/3/2017
    
    % Re-permute the image back to the original shape!:
    Im_out = permute(Im_out, pos);
    
    % Now show it to the user to accept it or not:
    [Y2, aux] = max(Im_out, [], ax);
    figure, subplot(1,2,1), imagesc(squeeze(Y)); title('Original');
    subplot(1,2,2), imagesc(squeeze(Y2)); title('After correction of aliasing');
    
    answ = questdlg(sprintf('Is the corrected image good to proceed?\n(If no, user needs to correct it manually!!)'), 'Anti-aliasing OK?', 'Yes', 'No', 'Yes');
    
    switch answ
        case 'Yes'
            % Flip back the image:
            if flip_nb, Im_out = flipdim(Im_out, cor); end
            corrected = 1;
            % Now save the new image as *_moved
            [p, n, e] = fileparts(V_orig.fname);
            new_fn = strcat(p, filesep, n, '_moved.nii');
            copyfile(strcat(p, filesep, n, e(1:4)),  new_fn);
            % Now we need to save the new matrix:
            V_orig.fname = new_fn;
            %V_orig.mat = V_orig.mat*(spm_matrix(params, 'Z*S*R*T')*eye(4));
            V_orig.mat = (spm_matrix(params, 'Z*S*R*T')*eye(4))*V_orig.mat; % New May/3/2017
            aux = spm_write_vol(V_orig, Im_out);
            % Legacy output: disp(sprintf('Orig image saved as:\n%s', new_fn));
            Pnew = new_fn;
        otherwise
            corrected = 0;
            % Legacy output: disp('Original image maintained!!');
    end
    close;
end

return
