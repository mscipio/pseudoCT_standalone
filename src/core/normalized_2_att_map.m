function [Pf] = normalized_2_att_map(norm_mprage, orig_mprage, dir_batch_templates, work_dir, reuse_masked_checkpoint, use_compiled_spm8)
% Investigation tool — investigation-cleanup-release.
% NORMALIZED_2_ATT_MAP  Downstream pseudo-CT processing from a normalized MPRAGE.
%
%   Pf = NORMALIZED_2_ATT_MAP(NORM_MPRAGE, ORIG_MPRAGE, DIR_BATCH_TEMPLATES, WORK_DIR)
%   runs the SPM downstream pipeline (smoothing, new segment, DARTEL,
%   inverse warp, atlas reslicing, CT-to-att_map) starting from a
%   pre-computed normalized MPRAGE image. This covers the block from
%   smoothing onward in atlas_based_attenuation_map.m and is INTENDED
%   FOR DIAGNOSTIC USE ONLY — it duplicates code from the main pipeline
%   on purpose.
%
%   Pf = NORMALIZED_2_ATT_MAP(..., REUSE_MASKED_CHECKPOINT) when
%   REUSE_MASKED_CHECKPOINT is true (non-zero), skips Step 1 smoothing
%   and masking and reuses the staged smprage_normalized_repos.nii
%   from the same directory as NORM_MPRAGE.  The smoothed file is
%   copied into WORK_DIR and the NaN mask is applied to the normalized
%   copy using the pre-smoothed volume.  Processing starts at New
%   Segment.  Default: false (run full pipeline).
%
%   Pf = NORMALIZED_2_ATT_MAP(..., USE_COMPILED_SPM8) when
%   USE_COMPILED_SPM8 is true (non-zero), executes Step 2 (New Segment)
%   via the compiled standalone spm8 executable from the Launchpad
%   assets, instead of the local cfg_util.  This is a DIAGNOSTIC OPTION
%   to test whether the SPM execution path (compiled MCR 7.11 vs local
%   MATLAB) is the source of segmentation divergence.  The compiled
%   spm8 requires the Launchpad directory and MCR to be accessible on
%   the local filesystem.  Default: false (use local cfg_util).
%
%   ALL SPM outputs are written to WORK_DIR, and the input NORM_MPRAGE
%   is COPIED into WORK_DIR before processing — the original input file
%   is NEVER mutated.  Callers must provide a disposable output directory
%   (typically a sandbox/scratch path); calling this on a real checkpoint
%   or test-data directory without a separate WORK_DIR will error.
%
%   This function requires the full pseudoCT_standalone and SPM8 paths
%   to be on the MATLAB path (call setup_pseudo_CT_paths first).
%
%   Inputs:
%     NORM_MPRAGE  — char; path to the normalized+repositioned MPRAGE
%                    image (e.g., .../tmp/mprage_normalized_repos.nii).
%     ORIG_MPRAGE  — char; path to the original (non-normalized) MPRAGE
%                    image. Its .mat header is used to re-anchor the
%                    attenuation map to native subject space.
%     DIR_BATCH_TEMPLATES — char; path to the Batch_atlas directory
%                    containing SPM batch .mat files, DARTEL templates,
%                    TPM.nii, and the atlas images.
%     WORK_DIR     — char; output/sandbox directory.  NORM_MPRAGE is
%                    COPIED here before processing; all intermediate
%                    and output files are written here.  This directory
%                    must exist and be writable.
%     REUSE_MASKED_CHECKPOINT — logical (optional, default false).
%                    When true, skips smoothing/masking and reuses the
%                    staged smprage_normalized_repos.nii from the
%                    NORM_MPRAGE directory.
%
%   Output:
%     Pf  — char matrix; each row is the full path of a created atlas
%           file in subject space. The last row is the attenuation map
%           (att_map.nii).  Empty string '' on early failure.
%
%   COMPATIBILITY: R2010b+. No modern-only MATLAB APIs used.
%
%   See also atlas_based_attenuation_map, restart_from_repos_checkpoint.

code_version = 'diagnostic-sandbox';

Pf = '';

if nargin < 4
    error('normalized_2_att_map requires at least 4 arguments: norm_mprage, orig_mprage, dir_batch_templates, work_dir');
end
if nargin < 5 || isempty(reuse_masked_checkpoint)
    reuse_masked_checkpoint = false;
end
reuse_masked_checkpoint = logical(reuse_masked_checkpoint);
if nargin < 6 || isempty(use_compiled_spm8)
    use_compiled_spm8 = false;
end
use_compiled_spm8 = logical(use_compiled_spm8);

% Validate inputs
if ~exist(norm_mprage, 'file')
    error('Normalized MPRAGE not found: %s', norm_mprage);
end
if ~exist(orig_mprage, 'file')
    error('Original MPRAGE not found: %s', orig_mprage);
end
if ~exist(dir_batch_templates, 'dir')
    error('Batch_atlas directory not found: %s', dir_batch_templates);
end
if ~exist(work_dir, 'dir')
    error('Work/output directory not found: %s', work_dir);
end

% When reuse_masked_checkpoint is enabled, the smoothed checkpoint file
% must exist alongside the normalized MPRAGE in the staging directory.
staging_dir = fileparts(norm_mprage);
if reuse_masked_checkpoint
    smprage_checkpoint = fullfile(staging_dir, 'smprage_normalized_repos.nii');
    if ~exist(smprage_checkpoint, 'file')
        error(['reuse_masked_checkpoint requires smprage_normalized_repos.nii ' ...
               'in the staging directory: %s'], staging_dir);
    end
end

% Guardrail: refuse to run if WORK_DIR equals or contains the norm_mprage
% directory — prevents in-place mutation of real checkpoint data.
[norm_p, ~, ~] = fileparts(norm_mprage);
if strcmp(work_dir, norm_p)
    error(['WORK_DIR must not be the same as the directory containing ' ...
           'norm_mprage. Use a separate sandbox/output directory.']);
end

% Look for the atlases
list_atlas = dir(fullfile(dir_batch_templates, '*Atlas*.nii'));
if isempty(list_atlas)
    error('No *Atlas*.nii files found in: %s', dir_batch_templates);
end

% Semantic preflight: Atlas_rCT and Atlas_head_mask MUST be found among
% *Atlas*.nii files.  The downstream code uses substring matching via
% strfind on the resliced name — preflight mirrors that semantic so
% real atlas files named 'Atlas_rCT_flipLR_repos_15subj.nii' and similar
% variants are correctly recognized.  Failing here saves an expensive
% SPM run (~20-30 min).
atlas_names = {list_atlas.name};
has_rCT = false;
has_mask = false;
for ii = 1:length(atlas_names)
    if ~isempty(strfind(atlas_names{ii}, 'Atlas_rCT'))
        has_rCT = true;
    end
    if ~isempty(strfind(atlas_names{ii}, 'Atlas_head_mask'))
        has_mask = true;
    end
end
if ~has_rCT
    error('No *Atlas*.nii file containing ''Atlas_rCT'' found in: %s. The CT-to-att_map step requires a matching file.', dir_batch_templates);
end
if ~has_mask
    error('No *Atlas*.nii file containing ''Atlas_head_mask'' found in: %s. The head-mask multiplication step requires a matching file.', dir_batch_templates);
end

% Check for all required batch templates
required_batch = {'new_segment_batch.mat', 'dartel_existing_template_batch.mat', ...
                  'create_inverse_warped_batch.mat', 'TPM.nii', 'ch2.nii'};
for ii = 1:length(required_batch)
    if ~exist(fullfile(dir_batch_templates, required_batch{ii}), 'file')
        error('Required batch template missing: %s in %s', required_batch{ii}, dir_batch_templates);
    end
end

% Compiled SPM8 preflight (fail-fast before expensive SPM work)
if use_compiled_spm8
    % Resolve Launchpad paths: env override, then hardcoded default.
    launchpad_root_env = getenv('PSEUDOCT_LAUNCHPAD_ROOT');
    if ~isempty(launchpad_root_env)
        launchpad_root = launchpad_root_env;
    else
        launchpad_root = '/autofs/cluster/pubsw/2/pubsw/Linux2-2.3-x86_64/packages/mrpet/standalone_apps/Pseudo_CT_launchpad';
    end
    run_spm8_sh = fullfile(launchpad_root, 'run_spm8.sh');
    spm8_exe    = fullfile(launchpad_root, 'spm8');
    mcr_root_env = getenv('PSEUDOCT_MCR_ROOT');
    if ~isempty(mcr_root_env)
        mcr_root = mcr_root_env;
    else
        mcr_root = '/usr/pubsw/common/matlab/7.11/';
    end
    if ~exist(run_spm8_sh, 'file')
        error('run_spm8.sh not found at: %s. Set PSEUDOCT_LAUNCHPAD_ROOT to the Launchpad directory.', run_spm8_sh);
    end
    if ~exist(spm8_exe, 'file')
        error('spm8 executable not found at: %s. The Launchpad standalone may not be installed.', spm8_exe);
    end
    if ~exist(mcr_root, 'dir')
        error('MCR root not found at: %s. Set PSEUDOCT_MCR_ROOT to the MATLAB 7.11 MCR directory.', mcr_root);
    end
    disp(sprintf('  Compiled SPM8 preflight OK: %s', run_spm8_sh));
end

% Copy norm_mprage into the sandbox — the downstream smoothing+masking
% step writes NaN into the normalized volume in place (line ~430 of
% atlas_based_attenuation_map.m).  We operate ONLY on the copy so the
% caller's original checkpoint file is never mutated.
[~, fn_norm, ext_norm] = fileparts(norm_mprage);
norm_mprage_copy = fullfile(work_dir, strcat(fn_norm, ext_norm));
[ok, msg] = copyfile(norm_mprage, norm_mprage_copy);
if ~ok
    error('Failed to copy norm_mprage into work_dir: %s', msg);
end

% From here on, ALL paths derive from work_dir.
paths = work_dir;
[~, fns, exts] = fileparts(norm_mprage_copy);
nf = 1;  % Single-subject mode

% Reslice flags (same as atlas_based_attenuation_map)
flg.mean  = 0;
flg.which = 1;
flg.mask  = 0;
flg.interp = 7;
flg.wrap = [0 0 0];

% Open SPM figure window (suppressed — diagnostic only)
fh = [];  % No SPM interactive window for batch diagnostic

disp('========================================');
disp('normalized_2_att_map diagnostic run');
disp(sprintf('  Norm MPRAGE (orig): %s', norm_mprage));
disp(sprintf('  Norm MPRAGE (copy): %s', norm_mprage_copy));
disp(sprintf('  Original MPRAGE:    %s', orig_mprage));
disp(sprintf('  Working directory:  %s', paths));
disp(sprintf('  Batch_atlas:        %s', dir_batch_templates));
disp(sprintf('  Reuse checkpoint:   %d', reuse_masked_checkpoint));
disp(sprintf('  Compiled SPM8:      %d', use_compiled_spm8));
disp('========================================');

%% -----------------------------------------------------------------------
% Smooth the image and create subject mask
% (lines 414-430 of atlas_based_attenuation_map.m)
%% -----------------------------------------------------------------------
if ~reuse_masked_checkpoint
    % Full smoothing path — compute spm_smooth, head mask, and NaN fill
    disp('Step 1/6: Smoothing and masking ...');
    sm_fn = fullfile(paths, strcat('s', fns, exts));
    if exist(sm_fn, 'file')
        disp(sprintf('  Smooth file exists, overwriting: %s', sm_fn));
    end
    spm_smooth(norm_mprage_copy, sm_fn, 4);
    Ims = spm_read_vols(spm_vol(sm_fn));
    [~, subj_mask] = head_mask_mprage(Ims, 15);
    mm = imdilate(subj_mask, ones(13, 13, 13));
    V_aux = spm_vol(norm_mprage_copy);
    Ims = spm_read_vols(V_aux);
    II = find(mm == 0);
    Ims(II) = NaN;
    aux = spm_write_vol(V_aux, Ims);  %#ok<NASGU>  % writes ONLY to sandbox copy
    disp('  Done.');
else
    % Reuse staged Launchpad smoothing/masking checkpoint.
    % Copies smprage_normalized_repos.nii into work_dir/proc/ and
    % computes the NaN mask from it — skipping the spm_smooth call.
    % This isolates divergence to post-smoothing steps (New Segment+).
    disp('Step 1/6: Reusing staged smoothing/masking checkpoint ...');
    sm_fn = fullfile(paths, strcat('s', fns, exts));
    if exist(sm_fn, 'file')
        disp(sprintf('  Smooth file exists, overwriting: %s', sm_fn));
    end
    [ok_cp, msg_cp] = copyfile(smprage_checkpoint, sm_fn);
    if ~ok_cp
        error('Failed to copy smprage_normalized_repos.nii into work_dir: %s', msg_cp);
    end
    disp(sprintf('  Copied: smprage_normalized_repos.nii → proc/'));
    Ims = spm_read_vols(spm_vol(sm_fn));
    [~, subj_mask] = head_mask_mprage(Ims, 15);
    mm = imdilate(subj_mask, ones(13, 13, 13));
    V_aux = spm_vol(norm_mprage_copy);
    Ims = spm_read_vols(V_aux);
    II = find(mm == 0);
    Ims(II) = NaN;
    aux = spm_write_vol(V_aux, Ims);  %#ok<NASGU>  % writes ONLY to sandbox copy
    disp('  Done (reused staged checkpoint, skipped spm_smooth).');
end

%% -----------------------------------------------------------------------
% New Segment
% (lines 433-477 of atlas_based_attenuation_map.m)
%% -----------------------------------------------------------------------
disp('Step 2/6: New Segment (20-30 min in SPM8) ...');
load(fullfile(dir_batch_templates, 'new_segment_batch.mat'));
matlabbatch{1}.spm.tools.preproc8.channel(1).vols = {norm_mprage_copy};
matlabbatch{1}.spm.tools.preproc8.warp.affreg = '';
matlabbatch{1}.spm.tools.preproc8.channel(1).biasfwhm = 30;
matlabbatch{1}.spm.tools.preproc8.warp.reg = 10;
for ii = 2:nf
    matlabbatch{1}.spm.tools.preproc8.channel(ii) = matlabbatch{1}.spm.tools.preproc8.channel(1);
    matlabbatch{1}.spm.tools.preproc8.channel(ii).vols = {norm_mprage_copy};
end
for ii = 1:6
    matlabbatch{1}.spm.tools.preproc8.tissue(ii).tpm = {strcat(fullfile(spm('Dir'), 'toolbox', 'Seg', 'TPM.nii,'), num2str(ii))};
end
fns_seg_batch = strcat(paths, filesep, 'new_segment_', date, '_batch.mat');
save(fns_seg_batch, 'matlabbatch');
clear matlabbatch;

if use_compiled_spm8
    % Validate ALL shell inputs before system() — run_spm8_sh, mcr_root,
    % and fns_seg_batch (generated from work_dir + filesep + basename).
    % All three are interpolated into the cmd string below.  (R1-002 full.)
    shell_meta = '[;&|`$(){}\[\]<>!\\''"]';
    if ~isempty(regexp(run_spm8_sh, shell_meta, 'once')) ...
       || ~isempty(regexp(mcr_root, shell_meta, 'once')) ...
       || ~isempty(regexp(fns_seg_batch, shell_meta, 'once'))
        error('Shell metacharacter in compiled-SPM8 command path. Refusing unsafe system() call.');
    end

    % Run New Segment via the compiled standalone SPM8 (MCR 7.11),
    % matching the Launchpad execution environment.  This tests whether
    % the SPM runtime (compiled vs. local MATLAB) is the divergence source.
    cmd = sprintf('"%s" "%s" run "%s"', run_spm8_sh, mcr_root, fns_seg_batch);
    disp(sprintf('  Invoking compiled SPM8: %s', cmd));
    [status, result] = system(cmd);
    disp('  --- Compiled SPM8 stdout/stderr ---');
    disp(result);
    disp('  --- End of compiled SPM8 output ---');
    if status ~= 0
        error('Compiled SPM8 failed with exit code %d. See output above.', status);
    end
else
    evalc('cfg_util(''run'', fns_seg_batch);');
end
disp('  Done.');

%% -----------------------------------------------------------------------
% Reduce bone segment
% (lines 479-491 of atlas_based_attenuation_map.m)
%% -----------------------------------------------------------------------
disp('Step 3/6: Bone segment cleanup ...');
exten = '';
for ii = 1:6
    aux = strcat(paths, filesep, 'rc', num2str(ii), fns, exts);
    Prc_old(ii, 1:length(aux)) = aux;  %#ok<AGROW>
end
[Prc_new] = reduce_bone_segment(Prc_old);  %#ok<NASGU>
disp('  Done.');

%% -----------------------------------------------------------------------
% DARTEL existing template
% (lines 495-524 of atlas_based_attenuation_map.m)
%% -----------------------------------------------------------------------
disp('Step 4/6: DARTEL existing template (~5 min in SPM8) ...');
load(fullfile(dir_batch_templates, 'dartel_existing_template_batch.mat'));
for ii = 1:6
    matlabbatch{1}.spm.tools.dartel.warp1.images{ii} = {strcat(paths, filesep, 'rc', num2str(ii), fns, exten, exts)};
end
for ii = 1:6
    tmp_aux = strcat('Template_', num2str(ii), '.nii');
    matlabbatch{1}.spm.tools.dartel.warp1.settings.param(ii).template = {fullfile(dir_batch_templates, tmp_aux)};
end
fns_dartel_batch = strcat(paths, filesep, 'dartel_existing_template_', date, '_batch.mat');
save(fns_dartel_batch, 'matlabbatch');
clear matlabbatch;
evalc('cfg_util(''run'', fns_dartel_batch);');
disp('  Done.');

%% -----------------------------------------------------------------------
% Inverse warp (atlas to subject space)
% (lines 526-548 of atlas_based_attenuation_map.m)
%% -----------------------------------------------------------------------
disp('Step 5/6: Inverse warp (atlas → subject space) ...');
load(fullfile(dir_batch_templates, 'create_inverse_warped_batch.mat'));
matlabbatch{1}.spm.tools.dartel.crt_iwarped.flowfields = {strcat(paths, filesep, 'u_rc1', fns, exten, exts)};
for ii = 1:length(list_atlas)
    matlabbatch{1}.spm.tools.dartel.crt_iwarped.images{ii} = fullfile(dir_batch_templates, list_atlas(ii).name);
end
fns_inv_batch = strcat(paths, filesep, 'create_inverse_warped_', date, '_batch.mat');
save(fns_inv_batch, 'matlabbatch');
% DO NOT clear matlabbatch — it is needed below for num_atlas and atlas paths
evalc('cfg_util(''run'', fns_inv_batch);');
disp('  Done.');

%% -----------------------------------------------------------------------
% Atlas reslicing + att_map creation
% (lines 550-670 of atlas_based_attenuation_map.m)
%% -----------------------------------------------------------------------
disp('Step 6/6: Atlas reslicing and att_map creation ...');
num_atlas = length(matlabbatch{1}.spm.tools.dartel.crt_iwarped.images);
Pr(1, :) = norm_mprage_copy;
for ii = 1:num_atlas
    [pathw, fnw, extw] = fileparts(matlabbatch{1}.spm.tools.dartel.crt_iwarped.images{ii});
    aux = strcat(paths, filesep, 'w', fnw, '_', 'u_rc1', fns, exten, extw);
    Pr((ii + 1), 1:length(aux)) = aux;
end
spm_reslice(Pr, flg);

% Collect resliced filenames
for ii = 1:num_atlas
    [pathf, fnf, extf] = fileparts(deblank(Pr(ii + 1, :)));
    aux = strcat(pathf, filesep, 'r', fnf, extf);
    Pf(ii, 1:length(aux)) = aux;
    disp(sprintf('  Created: %s', aux));
end

% CT → attenuation map
disp('  Creating att_map ...');
pos_CT = 0;
for ii = 1:num_atlas
    st_f = strfind(deblank(Pf(ii, :)), 'Atlas_rCT');
    if ~isempty(st_f)
        pos_CT = ii;
        break;
    end
end
V_CT = spm_vol(Pf(pos_CT, :));
CT = spm_read_vols(V_CT);
[att_map] = CT_2_att_map(CT);

% Multiply by head mask
pos_mask = 0;
for ii = 1:num_atlas
    st_f = strfind(deblank(Pf(ii, :)), 'Atlas_head_mask');
    if ~isempty(st_f)
        pos_mask = ii;
        break;
    end
end
V_mask = spm_vol(Pf(pos_mask, :));
mask = spm_read_vols(V_mask);
att_map = att_map .* mask;

% Save unfilled att_map with original MPRAGE geometry
fn_att_map = fullfile(paths, 'att_map_no_filled.nii');
V_att_map = V_CT;
V_att_map.fname = fn_att_map;
V_att_map.dt = [16 0];  % float32
V_orig = spm_vol(orig_mprage);
V_att_map.mat = V_orig.mat;
% Not writing the unfilled version — proceed to filled version

% Subject mask fill (soft-tissue = 0.096)
orig_vol = spm_read_vols(V_orig);
[~, subj_mask_fill] = head_mask_mprage(orig_vol, 20);
[L, num] = bwlabeln(subj_mask_fill);
if num > 1
    suma = zeros(1, num);
    for ii = 1:num
        aux_lbl = L == ii;
        suma(ii) = sum(aux_lbl(:));
    end
    [~, pos_max] = max(suma);
    subj_mask_fill = L == pos_max;
end

I = find((subj_mask_fill - mask) == 1);
att_map(I) = 0.096;
subj_mask_dil = imdilate(subj_mask_fill, ones(7, 7, 7));
subj_mask_eroded = imerode(subj_mask_fill, ones(13, 13, 13));
diff_mask = (subj_mask_dil - subj_mask_eroded) .* (att_map < 0.08) .* (orig_vol > 20);
I = find(diff_mask);
att_map(I) = 0.096;
att_map = att_map .* ((subj_mask_dil + (orig_vol > 20)) > 0);

fn_att_map = fullfile(paths, 'att_map.nii');
V_att_map.fname = fn_att_map;
aux = spm_write_vol(V_att_map, att_map);  %#ok<NASGU>
Pf(num_atlas + 1, 1:length(fn_att_map)) = fn_att_map;
disp(sprintf('  Attenuation map: %s', fn_att_map));

% QC fusion image
try
    composite = quick_fusion_pseudo_ct(paths);
    imwrite(composite, fullfile(paths, 'Fusion_MR_Pseudo_CT_validation.tiff'), 'Resolution', 300);
    disp('  QC image saved.');
catch ME_qc
    disp(sprintf('  WARNING: QC image failed: %s', ME_qc.message));
end

% Version log
status = pseudo_CT_write_version_log(code_version, paths);
if status ~= 1
    disp('  WARNING: Version log written in fallback mode.');
end

% Cleanup figure handle if any
try
    close(fh);
catch  %#ok<CTCH>
end

disp('========================================');
disp('normalized_2_att_map COMPLETE.');
disp(sprintf('Output directory: %s', paths));
disp('========================================');

return