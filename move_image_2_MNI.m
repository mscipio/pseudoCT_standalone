% Date: 03/31/2013;
% Name: move_image_2_MNI.m;
% Functio to move an image (or set of images) to get is as close as
% possible to the MNI template (ch2.nii);

function [Pout] = move_image_2_MNI(Pin, varargin)

autom_select_template = 1;
isPET = 0;
if nargin == 2
    if isnumeric(varargin{1})
        Vt = [];
        Imt = varargin{1};
        autom_select_template = 0;
    elseif isstr(varargin{1})
        Vt = spm_vol(varargin{1});
        Imt = spm_read_vols(Vt);
        autom_select_template = 0;
    elseif islogical(varargin{1})
        if varargin{1} == 0
            isPET = 0;
        elseif varargin{1} == 1
            isPET = 1;
        end
    end
end
    
if autom_select_template
    if exist(which('ch2.nii'))
        Vt = spm_vol(which('ch2.nii'));
    elseif isdir('/Users/di219/Harvard/AC/Atlas/Batch_atlas/')
        Vt = spm_vol('/Users/di219/Harvard/AC/Atlas/Batch_atlas/ch2.nii');
    elseif isdir('P:\Users\David\AC\Atlas\Batch_atlas\')
        Vt = spm_vol('P:\Users\David\AC\Atlas\Batch_atlas\ch2.nii');
    elseif isdir('D:\Users\David\AC\Atlas\Batch_atlas')
        Vt = spm_vol('D:\Users\David\AC\Atlas\Batch_atlas\ch2.nii');
    else
        disp(sprintf('I don''t know where the Templates are!!!'));
        return;
    end
    Imt = spm_read_vols(Vt);
end

disp('Opening the Template and calculating its position in real space ...');

% To get the origin of the file.
Ot = Vt.mat\[0 0 0 1]'; Ot=Ot(1:3)';

% Threshold to create a binary mask:
% Let's see if we can fit an exponential and a gaussian here!
func_h = @(params, xx) params(1).* exp( - .5.*(xx - params(2)).^2 ./ (params(3)^2)) + params(4);

% Get a binary mask:
mt = Imt > 50;

% Get an axial, coronal and sagital slices:
slt_a = imfill(mt(:, :, round(size(Imt,3)/2)), 'holes'); % Axial
slt_c = imfill(squeeze(mt(:, round(size(Imt,2)/2), :)), 'holes'); % Coronal
slt_s = imfill(squeeze(mt(round(size(Imt,1)/2), :, :)), 'holes'); % Saggital:
slt_a = slt_a - imerode(slt_a, ones(3));
slt_c = slt_c - imerode(slt_c, ones(3));
slt_s = slt_s - imerode(slt_s, ones(3));

% For the translations:
I = find(mt - imerode(mt, ones(3))); [rt, ct, dt] = ind2sub(size(Imt), I);
mm = Vt.mat*[rt ct dt ones(size(dt))]';
top_t = max(mm(3, :)); % Top-most voxel value of template (in mm from the AP centre);
back_t = min(mm(2, :)); % Backward-most voxel value of template (in mm from AP centre);
maxi = max(mm(1,:)); mini = min(mm(1,:));
rl_centre_t = mean([maxi mini]); % right-left centre in mm (should be zero, as is in AP centre);

% On axial plane:
[I] = find(slt_a == 1); [rt, ct] = ind2sub(size(mt), I);
Mt = [rt, ct];
[coef_t, score_t, latent_t] = local_princomp(Mt);



fn = deblank(Pin(1, :));
V = spm_vol(fn);
Im = spm_read_vols(V);

disp(sprintf('Opening file: %s and calculating the mask ... ', fn));

[N, X] = hist(Im(:), 100);
params = nlinfit(X, N, func_h, [max(N(:)), 0, 100, 1000]);
%keyboard
if isPET == 0
    thres = 20; % 400 for non-normalized images!
else
    thres = 0.001; % for PET images!
end

% To get the origin of the file.
O = V.mat\[0 0 0 1]'; O=O(1:3)';

m = Im > thres;
m = imfill(m, 26, 'holes');
% [L, num] = bwlabeln(m);
% m = zeros(size(m));
% for kk=1:num
%     aux = L == kk;
%     if sum(aux(:)) > 10000
%         m = m + aux;
%     end
% end


auxi = imfill(m(:, :, round(size(Im,3)/2)), 'holes'); % Axial
[L, num] = bwlabel(auxi); sl_a = zeros(size(auxi)); for kk=1:num, aux = L == kk; if sum(aux(:)) > 100, sl_a = sl_a + aux; end, end;
auxi = imfill(squeeze(m(:, round(size(Im,2)/2), :)), 'holes'); % Coronal
[L, num] = bwlabel(auxi); sl_c = zeros(size(auxi)); for kk=1:num, aux = L == kk; if sum(aux(:)) > 100, sl_c = sl_c + aux; end, end;
auxi = imfill(squeeze(m(round(size(Im,1)/2), :, :)), 'holes'); % Saggital:
[L, num] = bwlabel(auxi); sl_s = zeros(size(auxi)); for kk=1:num, aux = L == kk; if sum(aux(:)) > 100, sl_s = sl_s + aux; end, end;
sl_a = sl_a - imerode(sl_a, ones(3)); 
sl_c = sl_c - imerode(sl_c, ones(3));
sl_s = sl_s - imerode(sl_s, ones(3));


% Now compare each slice with the template and get an angle:
for jj=1:3
    switch jj
        case 1
            slt = slt_a;
            sl = sl_a;
        case 2
            slt = slt_c;
            sl = sl_c;
        case 3
            slt = slt_s;
            sl = sl_s;
        otherwise
            disp('Error!! There shouldn''t be more dimensions!!');
            return
    end
    [rt, ct] = find(slt == 1); Mt = [rt, ct];
    [r, c] = find(sl == 1); M = [r, c];
    [coef_t, score_t, latent_t] = local_princomp(Mt); coef_t;
    [coef, score, latent] = local_princomp(M); coef;
    a = [coef_t(:, 1)];
    b = [coef(:, 1)];
    costheta = dot(a,b)/(norm(a)*norm(b));
    theta(jj) = acos(costheta);
    %angle(jj) = atan2(norm(cross(a,b)),dot(a,b));
end

% If theta is too big, do pi - theta on that:
I = find(theta > pi/2); theta(I) = pi - theta(I);

% Let's include the rotations to make sure we pick the right extremes
% of the image:
theta(1) = 0;
theta(2) = 0; % Let's force roll to zero by now, as it seems wrong sometimes;
theta(3) = 0.3; % Let's force the pitch too!

% Display the angles for the axial (yaw), coronal (roll) and saggital
% (pitch):
disp(sprintf('Angles (in rads):\nAxial (yaw): %.3f\nCoronal (roll):%.3f\nSaggital (pitch):%.3f\n', theta(1), theta(2), theta(3)));

param = [0 0 0 theta(3) theta(2) theta(1) 1 1 1];
M  = spm_matrix(param);
M2  = M*V.mat;

% Now, we can do translations, based on the top-most voxel (up-down),
% which is the most positive voxel on the 3rd dimension, and also the
% forward-backward (the most negative voxel on second dimension). For
% the Right-Left, we can just get a mean of the extreme values and this
% should be zero.
I = find(m - imerode(m, ones(3))); [r, c, d] = ind2sub(size(Im), I);
mm = M2*[r c d ones(size(d))]';
top = max(mm(3, :)); % Top-most voxel value of template (in mm from the AP centre);
back = min(mm(2, :)); % Backward-most voxel value of template (in mm from AP centre);
maxi = max(mm(1,:)); mini = min(mm(1,:));
rl_centre = mean([maxi mini]); % right-left centre in mm (should be zero, as is in AP centre);

% Now let's calculate the translations (in mm):
t(3) = (top_t - top); % A positive value is going up!
t(2) = (back_t - back); % A positive value is going forward!
t(1) = (rl_centre_t - rl_centre); % A positive value is going right!

disp(sprintf('Translations (in mm):\nRight: %.3f\nForward: %.3f\nUp: %.3f\n', t(1), t(2), t(3)));

% Then to use it in the image, we need to create the matrix:
param = [t(1) t(2) t(3) theta(3) theta(2) theta(1) 1 1 1];
M = spm_matrix(param);


% We could now save it with a different name:
for jj=1:size(Pin, 1)
    fn = deblank(Pin(jj, :));
    V = spm_vol(fn);
    Im = spm_read_vols(V);
    [paths,fns,exts] = fileparts(fn);
    fns = fullfile(paths, strcat(fns, '_repos.nii'));
    % The new transformation matrix would be then:
    Mnew = M*V.mat;
    V_new = V;
    V_new.fname = fns; V_new.mat = Mnew;
    %ok = savenifti(fns, Im, Mnew, V.hdr.pixdim(2:4), spm_type(V.dt(1)));
    aux = spm_write_vol(V_new, Im);
    Pout(jj, 1:length(fns)) = fns;

%     if ok
%         disp(sprintf('Image saved succesfully:\n%s\n\n', fns));
%     else
%         disp(sprintf('Image NOT saved!!!\n%s\n\n', fns));
%     end
end

if size(Pout,1) ~= size(Pin, 1)
    disp('There was an error writing the images!');
    return;
end

% Now let's coreg (affine) the images:
%fh=openfig(fullfile(spm('Dir'),'spm_Interactive.fig'),'new','visible'); % Open the spm figure window to see how things are going!

job.ref = {Vt.fname}; job.source = {deblank(Pout(1, :))}; job.other = {''};
for jj=2:size(Pout, 1)
    job.other{jj-1, 1} = deblank(Pout(jj, :));
end
job.eoptions = spm_get_defaults('coreg.estimate');
job.eoptions.params = [0 0 0 0 0 0 1 1 1]; % Make sure the scaling is also included for the calculations;
evalc('spm_run_coreg_estimate(job);'); % Estimate but don't reslice!

%close(fh);

return

function [coef, score, latent] = local_princomp(X)

X = double(X);
if isempty(X)
    coef = eye(2);
    score = [];
    latent = zeros(2, 1);
    return;
end

mu = mean(X, 1);
X0 = bsxfun(@minus, X, mu);

if size(X0, 1) < 2
    coef = eye(size(X0, 2));
    score = X0;
    latent = zeros(size(X0, 2), 1);
    return;
end

[~, S, V] = svd(X0, 'econ');
coef = V;
score = X0*coef;
latent = (diag(S).^2) ./ (size(X0, 1) - 1);
