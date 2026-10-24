function [Pf] = pseudo_CT_current_compute(P_in, dir_batch_templates_in, config, output_context_in, fh_in)
%PSEUDO_CT_CURRENT_COMPUTE Post-normalization computation for current pipeline.
%   Shared by atlas_based_attenuation_map (local-current facade) and
%   mlsc_current_payload (compiled-current compute phase). Implements the
%   post-normalization order exactly: MNI/PCA/masking/segmentation/bone/
%   DARTEL/inverse warp/reslice/attenuation/QC.
%
%   Preserves original P_orig affine semantics (P_orig = verified input at
%   entry), current thresholds, float32 output, 0.096 gap-fill, bone and
%   zero-background switches, and array TIFF/version output. config.fwhm
%   is not consumed here; DICOM finalization remains in run_pseudo_CT.
%
%   Inputs:
%     P_in: verified normalized input char matrix (post-FreeSurfer).
%     dir_batch_templates_in: atlas/batch template directory.
%     config: selected profile config struct.
%     output_context_in: logging context struct (optional).
%     fh_in: interactive figure handle from prepare (optional, [] when
%       optional).
%
%   Output:
%     Pf: char matrix of warped atlas outputs plus att_map.nii, or ''
%       when atlas resources are missing (facade early-return semantics).
%
%   Minimum supported MATLAB: R2010b.

Pf = '';
if nargin < 3 || ~isstruct(config) || numel(config) ~= 1
    error('pseudo_CT:ProfileRequired', ...
        'pseudo_CT_current_compute requires the selected profile config.');
end
if nargin < 4 || isempty(output_context_in) || ~isstruct(output_context_in)
    output_context_in = struct();
end
output_context = output_context_in;
headless = (isfield(config, 'headless') && isequal(config.headless, true)) || ...
    (isfield(output_context, 'headless') && ...
    isequal(output_context.headless, true));
if nargin < 5
    fh_in = [];
end
fh = fh_in;
P = P_in;
dir_batch_templates = dir_batch_templates_in;

code_version = local_resolve_code_version();

% Look for the Atlases (recomputed so compute is self-contained for the
% MLSC payload path; facade prepare already gated this same condition).
list_atlas = dir(fullfile(dir_batch_templates, '*Atlas*.nii'));
if length(list_atlas) == 0
    pseudo_CT_output('ERROR', output_context, 'No atlas NIfTI files were found.');
    pseudo_CT_output('INFO', output_context, '    %s', dir_batch_templates);
    return;
end

% Define the flags for reslicing (preserved from facade):
flg.mean  = 0; % Don't create a mean image;
flg.which = 1; % Don't reslice the first image;
flg.mask  = 0; % Don't mask;
flg.interp = 7; % 7th degree bspline;
flg.wrap = [0 0 0]; % No wrapping;

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Now reorient all images to make them close to the MNI template (ch2.nii)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
stage_started = tic;
stage_context = local_stage_context(output_context, 3);
pseudo_CT_output('INFO', stage_context, 'Aligning MPRAGE and creating subject mask.');
P_orig = P; % Let's save the original image filenames as we will need them to use their .mat to reposition the att-map!
P = move_image_2_MNI(P_orig, fullfile(dir_batch_templates, 'ch2.nii'), ...
    stage_context, config);
% Decompose the first image (reference to warp everthing into this image)
% into its fileparts:
[paths, fns, exts] = fileparts(deblank(P(1, :)));
if isempty(paths); paths = pwd; end


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Now smooth the image to create a better subject mask avoiding noise!
% And apply that mask to the MPRAGE*normalized image to avoid the noise in
% the segmentation!!
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% % Only the first image need to be smoothed to create the mask:
[pathm, fnm, extm] = fileparts(deblank(P(1, :)));
sm_fn = fullfile(pathm, strcat('s', fnm, extm)); % The new smoothed file filename!
spm_smooth(P(1, :), sm_fn, 4);
Ims = spm_read_vols(spm_vol(sm_fn));
[~, subj_mask] = head_mask_mprage(Ims, 15); % Create the mask!; Before v1.8 it was 20;
mm = imdilate(subj_mask, ones(13, 13, 13)); % Dilate the mask to compensate for the previous erosion in head_mask_mprage;
V_aux = spm_vol(deblank(P(1, :)));
Ims = spm_read_vols(V_aux);
II = find(mm == 0);
Ims(II) = NaN; % Let's make the outside NaN to avoid segmentation there!
aux = spm_write_vol(V_aux, Ims); % Re-save the MPRAGE*normalized image with the mask applied!
pseudo_CT_output('SUCCESS', stage_context, 'Alignment and masking completed (elapsed %s).', ...
    local_elapsed(toc(stage_started)));


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Now load, modify (with the new files) and run the NEW SEGMENT batch:
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
stage_started = tic;
stage_context = local_stage_context(output_context, 4);
pseudo_CT_output('INFO', stage_context, 'Running SPM New Segment.');
load(fullfile(dir_batch_templates, 'new_segment_batch.mat')); % A new variable called matlabbatch is created!
% We need to change the channels according to the loaded files:
nf = size(P, 1);
matlabbatch{1}.spm.tools.preproc8.channel(1).vols = {deblank(P(1, :))};
matlabbatch{1}.spm.tools.preproc8.warp.affreg = ''; % This option should be here only if there is an Affine coreg into the MNI before (in move_image_2_MNI.m);
matlabbatch{1}.spm.tools.preproc8.channel(1).biasfwhm = 30; % FWHM to 30mm;
matlabbatch{1}.spm.tools.preproc8.warp.reg = 10; % Warping regularization to 10;
for ii = 2:nf
    matlabbatch{1}.spm.tools.preproc8.channel(ii) = matlabbatch{1}.spm.tools.preproc8.channel(1);
    matlabbatch{1}.spm.tools.preproc8.channel(ii).vols = {deblank(P(ii, :))};
end
% Let's include the right path to the template TPM.nii files:
for ii = 1:6
    if isdeployed
        matlabbatch{1}.spm.tools.preproc8.tissue(ii).tpm = {strcat(fullfile(dir_batch_templates, 'TPM.nii,'), num2str(ii))};
    else
        matlabbatch{1}.spm.tools.preproc8.tissue(ii).tpm = {strcat(fullfile(spm('Dir'), 'toolbox', 'Seg', 'TPM.nii,'), num2str(ii))};
    end
end
fns_seg_batch = strcat(paths, filesep, 'new_segment_', date, '_batch.mat');
fprintf('New Segment batch save diagnostics:\n');
fprintf('  filename: %s (class %s, size %s)\n', fns_seg_batch, ...
    class(fns_seg_batch), mat2str(size(fns_seg_batch)));
fprintf('  paths: %s; date: %s; pwd: %s\n', paths, date, pwd);
dest_dir = fileparts(fns_seg_batch);
fprintf('  destination directory: %s (exists: %d)\n', dest_dir, ...
    exist(dest_dir, 'dir') == 7);
fprintf('  matlabbatch: class %s, size %s, ndims %d\n', ...
    class(matlabbatch), mat2str(size(matlabbatch)), ndims(matlabbatch));
if iscell(matlabbatch) && ~isempty(matlabbatch) && isstruct(matlabbatch{1})
    batch_fields = fieldnames(matlabbatch{1});
    fprintf('  top-level batch fields:');
    for field_index = 1:min(length(batch_fields), 20)
        fprintf(' %s', batch_fields{field_index});
    end
    if length(batch_fields) > 20
        fprintf(' ...');
    end
    fprintf('\n');
end
try
    save(fns_seg_batch, 'matlabbatch');
catch ME
    fprintf(2, 'New Segment batch save failed: %s: %s\n', ...
        ME.identifier, ME.message);
    for stack_index = 1:length(ME.stack)
        fprintf(2, '  at %s (%s:%d)\n', ME.stack(stack_index).name, ...
            ME.stack(stack_index).file, ME.stack(stack_index).line);
    end
    rethrow(ME);
end
clear matlabbatch;
if headless || ~isdeployed
    evalc('cfg_util(''run'', fns_seg_batch);');
else
    if ispc
        exe_cmd = strcat('!', fullfile(config.spm_root, 'spm8.exe'));
    elseif ismac
        exe_cmd = strcat('!', fullfile(config.spm_root, 'spm8.app/Contents/MacOS/spm8'));
    elseif isunix
        exe_cmd = strcat('!', fullfile(config.spm_root, 'spm8'));
    else
        error('pseudo_CT:UnsupportedPlatform', 'The current platform is unsupported.');
    end
    cmd = [exe_cmd ' run ' fns_seg_batch];
    eval([cmd]);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Apply bone reduction when enabled by the selected profile.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if config.bone_enabled
    for ii = 1:6
        aux = strcat(paths, filesep, 'rc', num2str(ii), fns, exts);
        Prc_old(ii, 1:length(aux)) = aux;
    end
    [Prc_new] = reduce_bone_segment(Prc_old);
end
exten = '';
pseudo_CT_output('SUCCESS', stage_context, 'Segmentation completed (elapsed %s).', ...
    local_elapsed(toc(stage_started)));


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Once finished, we need to run the DARTEL EXISTING TEMPLATE batch:
% We will use the newly generated files from the New Segment process run
% just above! (rc1*.nii, where * is the P(1, :) file!);
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
stage_started = tic;
stage_context = local_stage_context(output_context, 5);
pseudo_CT_output('INFO', stage_context, 'Registering atlases with DARTEL.');
load(fullfile(dir_batch_templates, 'dartel_existing_template_batch.mat')); % A new variable called matlabbatch is created!
% Let's replace the files again:
for ii = 1:6
    matlabbatch{1}.spm.tools.dartel.warp1.images{ii} = {strcat(paths, filesep, 'rc', num2str(ii), fns, exten, exts)};
end
% Let's include the right path to the Large FOV templates:
for ii = 1:6
    tmp_aux = strcat('Template_', num2str(ii), '.nii');
    matlabbatch{1}.spm.tools.dartel.warp1.settings.param(ii).template = {fullfile(dir_batch_templates, tmp_aux)};
end
fns_dartel_exist_template_batch = strcat(paths, filesep, 'dartel_existing_template_', date, '_batch.mat');
save(fns_dartel_exist_template_batch, 'matlabbatch');
clear matlabbatch;
if headless || ~isdeployed
    evalc('cfg_util(''run'', fns_dartel_exist_template_batch);');
else
    cmd = [exe_cmd ' run ' fns_dartel_exist_template_batch];
    eval([cmd]);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Once finished, just need to run the INVERSE WARPED batch to create the atlases
% back into subject space:
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
pseudo_CT_output('INFO', stage_context, '    Applying inverse warp.');
load(fullfile(dir_batch_templates, 'create_inverse_warped_batch.mat'));
% Let's modify the flow-field field:
matlabbatch{1}.spm.tools.dartel.crt_iwarped.flowfields = {strcat(paths, filesep, 'u_rc1', fns, exten, exts)};
% Now we need to change the Atlases that will be warped into subject space:
for ii = 1:length(list_atlas)
    matlabbatch{1}.spm.tools.dartel.crt_iwarped.images{ii} = fullfile(dir_batch_templates, list_atlas(ii).name);
end
fns_create_inverse_warped_batch = strcat(paths, filesep, 'create_inverse_warped_', date, '_batch.mat');
save(fns_create_inverse_warped_batch, 'matlabbatch');
if headless || ~isdeployed
    evalc('cfg_util(''run'', fns_create_inverse_warped_batch);');
else
    cmd = [exe_cmd ' run ' fns_create_inverse_warped_batch];
    eval([cmd]);
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Once finished, there should be 5 new files (from the 5 Atlases: CT,
% MPRAGE, UTE_1, UTE_2 and head_mask! RESLICE the new atlas into subject
% space
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
pseudo_CT_output('INFO', stage_context, '    Reslicing atlases into MPRAGE space.');
num_atlas = length(matlabbatch{1}.spm.tools.dartel.crt_iwarped.images); % Number of warped atlas just created
clear Pr;
Pr(1, :) = deblank(P(1, :));
for ii = 1:num_atlas
    [pathw, fnw, extw] = fileparts(matlabbatch{1}.spm.tools.dartel.crt_iwarped.images{ii});
    aux = strcat(paths, filesep, 'w', fnw, '_', 'u_rc1', fns, exten, extw);
    Pr((ii+1), 1:length(aux)) = aux; % Just in case the new name is longer than the matrix Pr!
end
% Let's reslice them back into MPRAGE space (P(1, :)):
spm_reslice(Pr, flg); % Reslice only!


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Finished! Just display the final files created!!:
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
for ii = 1:num_atlas
    [pathf, fnf, extf] = fileparts(deblank(Pr(ii+1, :)));
    aux = strcat(pathf, filesep, 'r', fnf, extf);
    Pf(ii, 1:length(aux)) = aux; % Just in case the new name is longer than the matrix P!
end
pseudo_CT_output('SUCCESS', stage_context, 'Atlas registration completed (elapsed %s).', ...
    local_elapsed(toc(stage_started)));

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Finally, we just need to convert the CT atlas into an attenuation map and
% multiply by the head_mask to get a clean attenuation map!
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
stage_started = tic;
stage_context = local_stage_context(output_context, 6);
pseudo_CT_output('INFO', stage_context, 'Building attenuation map and QC image.');
% First look for th CT file within Pf:
for ii = 1:num_atlas
    st_f = strfind(deblank(Pf(ii, :)), 'Atlas_rCT');
    if length(st_f) > 0
        pos_CT = ii;
        break;
    end
end
V_CT = spm_vol(Pf(pos_CT, :));
CT = spm_read_vols(V_CT);
[att_map] = CT_2_att_map(CT);

% Now, let's multiply it by the head_mask:
for ii = 1:num_atlas
    st_f = strfind(deblank(Pf(ii, :)), 'Atlas_head_mask');
    if length(st_f) > 0
        pos_mask = ii;
        break;
    end
end
V_mask = spm_vol(Pf(pos_mask, :));
mask = spm_read_vols(V_mask);
att_map = att_map .* mask;

% Now let's save the attenuation map in the same space:
fn_att_map = fullfile(paths, 'att_map_no_filled.nii');
V_att_map = V_CT;
V_att_map.fname = fn_att_map;
V_att_map.dt = [16 0]; % To save it as float32;

% Let's change the .mat to match the original MPRAGE image:
V_orig = spm_vol(deblank(P_orig(1, :)));
V_att_map.mat = V_orig.mat;

% Let's get Original MPRAGE mask and then let's make whatever is not
% covered by the atlas mask become soft-tissue:
orig_mprage = spm_read_vols(V_orig);
[aux, subj_mask] = head_mask_mprage(orig_mprage, 20); % It used to be 30 up to version 1.5 included;
% For version 1.7: Choose only the biggest blob in the mask!
[L, num] = bwlabeln(subj_mask);
if num > 1
    for ii = 1:num
        aux = L == ii;
        suma(ii) = sum(aux(:));
    end
    [Y, pos_max] = max(suma);
    subj_mask = L == pos_max;
end

I = find((subj_mask - mask) == 1); % Only those voxels where subj_mask exists but not mask!
att_map(I) = 0.096; % Make those voxels to be Soft-tissue = 0.096;
% Version 1.6.1: Once I have filled the gaps (as in version 1.5) then get the outter part
% of the extended mask and assign those to 0.096 if they are ok in MPRAGE!
subj_mask_dil = imdilate(subj_mask, ones(7, 7, 7));
subj_mask_eroded = imerode(subj_mask, ones(13, 13, 13)); % For version 1.6;
diff = (subj_mask_dil - subj_mask_eroded) .* (att_map < 0.08) .* (orig_mprage > 20); % For version 1.6
I = find(diff); att_map(I) = 0.096;
% Optionally multiply by the subject mask. The selected profile owns this
% compatibility policy.
if strcmp(config.zero_background, 'Yes')
    att_map = att_map .* ((subj_mask_dil + (orig_mprage > 20)) > 0);
end
% Rename the filename to save it!
fn_att_map = fullfile(paths, 'att_map.nii');
V_att_map.fname = fn_att_map;

% Let's write the file:
aux = spm_write_vol(V_att_map, att_map);

% Add the attenuation map file to the list to be returned:
Pf(num_atlas+1, 1:length(fn_att_map)) = fn_att_map;

% Jun/25/2016: Printing a validation image (T003: explicit bundled QC
% colormap location; single-arg default output is unchanged because the
% helper resolves that same bundled file).
composite = quick_fusion_pseudo_ct(paths, local_qc_colormap_resource());
imwrite(composite, fullfile(paths, 'Fusion_MR_Pseudo_CT_validation.tiff'), 'Resolution', 300);

try
    if ~isempty(fh)
        close(fh);
    end
catch
end

% Write Pseudo_CT_AC_Version.txt with changelog content
status = pseudo_CT_write_version_log(code_version, paths, stage_context);
if status ~= 1
    pseudo_CT_output('WARN', stage_context, ...
        'Version log used fallback content because CHANGELOG.md could not be copied.');
end
pseudo_CT_output('SUCCESS', stage_context, ...
    'Attenuation map and QC completed (elapsed %s).', local_elapsed(toc(stage_started)));


return
end

function code_version = local_resolve_code_version()
code_version = '2.8.4';  % fallback
try
    root_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
    fid = fopen(fullfile(root_dir, 'CHANGELOG.md'), 'r');
    if fid ~= -1
        v = strtrim(fgetl(fid));
        fclose(fid);
        if ~isempty(v) && ischar(v)
            code_version = v;
        end
    end
catch %#ok<CTCH>
end
end

function context = local_stage_context(context, stage_index)
context.stage_index = stage_index;
context.stage_count = 8;
end

function colormap_path = local_qc_colormap_resource()
% Explicit bundled QC colormap resource under src/qc,
% never a loose MAT assumed beside caller output. Resolves the same file
% the quick_fusion default uses, so rendered output is unchanged; a missing
% bundled resource fails closed instead of surfacing a raw load error.
qc_dir = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'qc');
colormap_path = fullfile(qc_dir, 'hot_map_mpitool_1024.mat');
if exist(colormap_path, 'file') ~= 2
    error('pseudo_CT:QCColormapMissing', ...
        'QC colormap resource missing: %s', colormap_path);
end
end

function value = local_elapsed(seconds)
seconds = max(0, floor(seconds));
value = sprintf('%02d:%02d:%02d', floor(seconds / 3600), ...
    floor(rem(seconds, 3600) / 60), rem(seconds, 60));
end
